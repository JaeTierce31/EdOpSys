import { GovernanceStore } from './persistence.js';
import { replayPersistedCase } from './adapter.js';
import { hashCanonical } from './index.js';
import type { AppendBundle, CaseStateReceipt, DurableAppendResult, DurableBackup, DurableStore, ReplayEnvelope } from './q-contract.js';

function clone<T>(v:T):T{return JSON.parse(JSON.stringify(v));}
function stateReceipt(bundle:AppendBundle,prior:string|null):CaseStateReceipt{
  const state=bundle.event.decision ?? prior ?? 'REPORTED';
  const base={correlation_id:bundle.event.correlation_id,aggregate_id:bundle.event.aggregate_id,aggregate_version:bundle.event.aggregate_version,source_event_id:bundle.event.event_id,state};
  const derived={...base,state_hash:hashCanonical(base)};
  if(bundle.state){
    if(bundle.state.correlation_id!==derived.correlation_id||bundle.state.aggregate_id!==derived.aggregate_id||bundle.state.aggregate_version!==derived.aggregate_version||bundle.state.source_event_id!==derived.source_event_id||bundle.state.state!==derived.state||bundle.state.state_hash!==derived.state_hash) throw new Error('state receipt mismatch');
  }
  return derived;
}

function deriveStateHistory(backup:DurableBackup):CaseStateReceipt[]{
  const byCorrelation=new Map<string,typeof backup.store.events>();
  for(const ev of backup.store.events){
    const xs=byCorrelation.get(ev.correlation_id)??[]; xs.push(ev); byCorrelation.set(ev.correlation_id,xs);
  }
  const out:CaseStateReceipt[]=[];
  for(const [correlationId,events] of byCorrelation){
    let prior:string|null=null;
    for(const ev of [...events].sort((a,b)=>a.aggregate_version-b.aggregate_version||a.event_id.localeCompare(b.event_id))){
      const state:string=ev.decision ?? prior ?? 'REPORTED';
      const base={correlation_id:correlationId,aggregate_id:ev.aggregate_id,aggregate_version:ev.aggregate_version,source_event_id:ev.event_id,state};
      out.push({...base,state_hash:hashCanonical(base)});
      prior=state;
    }
  }
  return out;
}
function reconstructStateHistory(backup:DurableBackup):CaseStateReceipt[]{
  const derived=deriveStateHistory(backup);
  if(backup.state_history===undefined) return derived;
  const supplied=backup.state_history.map(clone);
  if(hashCanonical(supplied)!==hashCanonical(derived)) throw new Error('backup state history mismatch');
  return supplied;
}
function deriveCertificationCorrelations(backup:DurableBackup):Map<string,string>{
  const correlations=[...new Set(backup.store.events.map(e=>e.correlation_id))];
  const out=new Map<string,string>();
  for(const [id,raw] of backup.store.certifications??[]){
    const record=raw as any;
    const explicit=typeof record?.correlation_id==='string'&&record.correlation_id?record.correlation_id:(typeof record?.correlationId==='string'&&record.correlationId?record.correlationId:null);
    if(explicit){out.set(id,explicit);continue;}
    if(correlations.length===1){out.set(id,correlations[0]);continue;}
    throw new Error('ambiguous legacy certification correlation binding');
  }
  return out;
}
function reconstructCertificationCorrelations(backup:DurableBackup):Map<string,string>{
  const derived=deriveCertificationCorrelations(backup);
  if(backup.certification_correlations===undefined) return derived;
  const supplied=new Map(backup.certification_correlations.map(clone));
  const suppliedSorted=[...supplied.entries()].sort(([a],[b])=>a.localeCompare(b));
  const derivedSorted=[...derived.entries()].sort(([a],[b])=>a.localeCompare(b));
  if(hashCanonical(suppliedSorted)!==hashCanonical(derivedSorted)) throw new Error('backup certification correlation mismatch');
  return supplied;
}
export class ReferenceTransactionalStore implements DurableStore{
  private store:GovernanceStore;
  private commandRequestHashes=new Map<string,string>();
  private stateHistory:CaseStateReceipt[]=[];
  private certificationCorrelations=new Map<string,string>();
  private tail:Promise<void>=Promise.resolve();
  constructor(store=new GovernanceStore()){this.store=store;}

  private async locked<T>(fn:()=>Promise<T>|T):Promise<T>{
    const prev=this.tail; let release!:()=>void; this.tail=new Promise<void>(r=>{release=r;});
    await prev; try{return await fn();}finally{release();}
  }

  async appendBundle(bundle:AppendBundle):Promise<DurableAppendResult>{
    return this.locked(async()=>{
      const prior=this.commandRequestHashes.get(bundle.command_id);
      if(prior!==undefined){
        if(prior!==bundle.request_hash) throw new Error('idempotency key conflict');
        return {status:'IDEMPOTENT_REPLAY',event_id:bundle.event.event_id};
      }
      const staged=GovernanceStore.fromSnapshot(this.store.snapshot());
      const stagedStates=this.stateHistory.map(clone);
      const stagedCertCorr=new Map(this.certificationCorrelations);
      for(const v of bundle.versions) staged.pinVersion(v.ref,v.record);
      for(const e of bundle.evidence) staged.appendEvidence(e);
      const eventResult=staged.appendEvent(bundle.event,bundle.command_id);
      for(const c of bundle.chain){
        if(c.event_id===bundle.event.event_id && c.event_hash!==bundle.event.event_hash) throw new Error('chain event hash mismatch');
        staged.appendChainRecord(c);
      }
      for(const n of bundle.lineage) staged.appendLineageNode(n);
      for(const c of bundle.certifications){ const bound=stagedCertCorr.get(c.certification_id); if(bound!==undefined&&bound!==bundle.event.correlation_id) throw new Error('immutable certification correlation conflict'); staged.appendCertification(c); if(bound===undefined) stagedCertCorr.set(c.certification_id,bundle.event.correlation_id); }
      const priorState=stagedStates.filter(x=>x.correlation_id===bundle.event.correlation_id).sort((a,b)=>a.aggregate_version-b.aggregate_version).at(-1)?.state ?? null;
      const sr=stateReceipt(bundle,priorState);
      const conflict=stagedStates.find(x=>x.correlation_id===sr.correlation_id&&x.aggregate_version===sr.aggregate_version);
      if(conflict){ if(hashCanonical(conflict)!==hashCanonical(sr)) throw new Error('immutable state conflict'); }
      else stagedStates.push(sr);
      this.store=staged;
      this.stateHistory=stagedStates;
      this.certificationCorrelations=stagedCertCorr;
      this.commandRequestHashes.set(bundle.command_id,bundle.request_hash);
      return {status:eventResult.status,event_id:bundle.event.event_id};
    });
  }

  backup():DurableBackup{
    return {format:'CLP001-Q-BACKUP-v1',store:clone(this.store.snapshot()),command_request_hashes:[...this.commandRequestHashes.entries()].map(clone),state_history:this.stateHistory.map(clone),certification_correlations:[...this.certificationCorrelations.entries()]};
  }
  static restore(backup:DurableBackup):ReferenceTransactionalStore{
    if(backup.format!=='CLP001-Q-BACKUP-v1') throw new Error('unsupported backup format');
    const out=new ReferenceTransactionalStore(GovernanceStore.fromSnapshot(clone(backup.store)));
    out.commandRequestHashes=new Map(backup.command_request_hashes.map(clone));
    out.stateHistory=reconstructStateHistory(backup);
    out.certificationCorrelations=reconstructCertificationCorrelations(backup);
    return out;
  }
  replay(correlationId:string){return replayPersistedCase(correlationId,this.store);}
  replayEnvelope(correlationId:string):ReplayEnvelope{
    const replay=this.replay(correlationId);
    const snap=this.store.snapshot();
    const certifications=snap.certifications.filter(([id])=>this.certificationCorrelations.get(id)===correlationId).map(([,record])=>clone(record as any));
    return {replay,certifications};
  }
  caseState(correlationId:string){return this.caseStateReceipt(correlationId)?.state??null;}
  caseStateReceipt(correlationId:string){return this.stateHistory.filter(x=>x.correlation_id===correlationId).sort((a,b)=>a.aggregate_version-b.aggregate_version).at(-1)??null;}
  governanceSnapshot(){return this.store.snapshot();}
  backupHash(){return hashCanonical(this.backup());}
}
