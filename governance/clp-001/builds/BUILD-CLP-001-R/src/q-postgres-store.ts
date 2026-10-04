import { canonicalize, hashCanonical, type GoldenEvent, type ChainRecord } from './index.js';
import { GovernanceStore, type EvidenceRecord, type StoreSnapshot } from './persistence.js';
import { replayPersistedCase } from './adapter.js';
import type { AppendBundle, CaseStateReceipt, CertificationWrite, DurableAppendResult, DurableBackup, DurableStore, ReplayEnvelope, SqlClient, SqlPool } from './q-contract.js';

function makeStateReceipt(bundle:AppendBundle,prior:string|null):CaseStateReceipt{
  const state=bundle.event.decision ?? prior ?? 'REPORTED';
  const base={correlation_id:bundle.event.correlation_id,aggregate_id:bundle.event.aggregate_id,aggregate_version:bundle.event.aggregate_version,source_event_id:bundle.event.event_id,state};
  const receipt={...base,state_hash:hashCanonical(base)};
  if(bundle.state && hashCanonical(bundle.state)!==hashCanonical(receipt)) throw new Error('state receipt mismatch');
  return receipt;
}

export class PgTransactionalStore implements DurableStore{
  constructor(private readonly pool:SqlPool){}
  async appendBundle(bundle:AppendBundle):Promise<DurableAppendResult>{
    const c=await this.pool.connect();
    try{
      await c.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
      const existing=await c.query<{request_hash:string,result_event_id:string|null}>('SELECT request_hash,result_event_id FROM clp_commands WHERE command_id=$1 FOR UPDATE',[bundle.command_id]);
      if(existing.rows.length){
        if(existing.rows[0].request_hash!==bundle.request_hash) throw new Error('idempotency key conflict');
        await c.query('COMMIT');
        return {status:'IDEMPOTENT_REPLAY',event_id:existing.rows[0].result_event_id??bundle.event.event_id};
      }
      const priorState=await c.query<{state?:string;decision?:string}>('SELECT state FROM clp_case_state_history WHERE correlation_id=$1 ORDER BY aggregate_version DESC LIMIT 1 FOR UPDATE',[bundle.event.correlation_id]);
      const sr=makeStateReceipt(bundle,priorState.rows[0]?.state??priorState.rows[0]?.decision??null);
      await c.query('INSERT INTO clp_commands(command_id,request_hash,result_event_id) VALUES($1,$2,$3)',[bundle.command_id,bundle.request_hash,bundle.event.event_id]);
      for(const v of bundle.versions){
        const h=hashCanonical(v.record);
        const r=await c.query<{canonical_hash:string}>('INSERT INTO clp_versions(version_ref,canonical_hash,payload) VALUES($1,$2,$3::jsonb) ON CONFLICT (version_ref) DO NOTHING RETURNING canonical_hash',[v.ref,h,canonicalize(v.record)]);
        if((r.rowCount??r.rows.length)===0){
          const prior=await c.query<{canonical_hash:string}>('SELECT canonical_hash FROM clp_versions WHERE version_ref=$1',[v.ref]);
          if(!prior.rows[0]||prior.rows[0].canonical_hash!==h) throw new Error('immutable version conflict');
        }
      }
      for(const e of bundle.evidence) await c.query('INSERT INTO clp_evidence(evidence_id,correlation_id,content_hash,payload) VALUES($1,$2,$3,$4::jsonb)',[e.evidence_id,bundle.event.correlation_id,e.content_hash,canonicalize(e)]);
      await c.query('INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload) VALUES($1,$2,$3,$4,$5,$6,$7,$8::jsonb)',[bundle.event.event_id,bundle.event.correlation_id,bundle.event.aggregate_id,bundle.event.aggregate_version,bundle.event.event_type,bundle.event.decision,bundle.event.event_hash,canonicalize(bundle.event)]);
      await c.query('INSERT INTO clp_case_state_history(correlation_id,aggregate_id,aggregate_version,source_event_id,state,state_hash) VALUES($1,$2,$3,$4,$5,$6)',[sr.correlation_id,sr.aggregate_id,sr.aggregate_version,sr.source_event_id,sr.state,sr.state_hash]);
      for(const ch of bundle.chain){
        if(ch.event_id===bundle.event.event_id&&ch.event_hash!==bundle.event.event_hash) throw new Error('chain event hash mismatch');
        await c.query('INSERT INTO clp_chain(event_id,correlation_id,ordinal,event_hash,previous_chain_hash,chain_hash) VALUES($1,$2,$3,$4,$5,$6)',[ch.event_id,bundle.event.correlation_id,ch.ordinal,ch.event_hash,ch.previous_chain_hash,ch.chain_hash]);
      }
      for(const n of bundle.lineage) await c.query('INSERT INTO clp_lineage(lineage_id,correlation_id,parents,payload) VALUES($1,$2,$3::jsonb,$4::jsonb)',[n.id,bundle.event.correlation_id,canonicalize(n.parents),canonicalize(n)]);
      for(const cert of bundle.certifications) await c.query('INSERT INTO clp_certifications(certification_id,certification_hash,payload,correlation_id) VALUES($1,$2,$3::jsonb,$4)',[cert.certification_id,hashCanonical(cert),canonicalize(cert),bundle.event.correlation_id]);
      await c.query('COMMIT');
      return {status:'APPENDED',event_id:bundle.event.event_id};
    }catch(err){ try{await c.query('ROLLBACK');}catch{} throw err; }finally{c.release();}
  }

  async caseStateReceipt(correlationId:string):Promise<CaseStateReceipt|null>{
    const c=await this.pool.connect();
    try{
      const r=await c.query<CaseStateReceipt>('SELECT correlation_id,aggregate_id,aggregate_version,source_event_id,state,state_hash FROM clp_case_state_history WHERE correlation_id=$1 ORDER BY aggregate_version DESC LIMIT 1',[correlationId]);
      return r.rows[0]??null;
    }finally{c.release();}
  }
  async caseState(correlationId:string):Promise<string|null>{
    const r=await this.caseStateReceipt(correlationId) as any;
    return r?.state ?? r?.decision ?? null;
  }
  async replay(correlationId:string){
    const c=await this.pool.connect();
    try{
      const er=await c.query<{payload:GoldenEvent}>('SELECT payload FROM clp_events WHERE correlation_id=$1 ORDER BY aggregate_version',[correlationId]);
      if(!er.rows.length) throw new Error('correlation id not found');
      const events=er.rows.map(r=>r.payload);
      const evid=await c.query<{payload:EvidenceRecord}>('SELECT payload FROM clp_evidence WHERE correlation_id=$1 ORDER BY evidence_id',[correlationId]);
      const chr=await c.query<ChainRecord>('SELECT ordinal,event_id,event_hash,previous_chain_hash,chain_hash FROM clp_chain WHERE correlation_id=$1 ORDER BY ordinal',[correlationId]);
      const lin=await c.query<{payload:{id:string;parents:string[]}}>('SELECT payload FROM clp_lineage WHERE correlation_id=$1 ORDER BY lineage_id',[correlationId]);
      const refs=[...new Set(events.flatMap(e=>[...e.source_refs,...e.policy_refs]))];
      const vr=refs.length?await c.query<{version_ref:string;canonical_hash:string;payload:unknown}>('SELECT version_ref,canonical_hash,payload FROM clp_versions WHERE version_ref = ANY($1::text[])',[refs]):{rows:[]};
      const versions=Object.fromEntries(vr.rows.map(r=>[r.version_ref,r.payload]));
      const version_hashes=Object.fromEntries(vr.rows.map(r=>[r.version_ref,r.canonical_hash]));
      const snapshot:StoreSnapshot={events,evidence:evid.rows.map(r=>r.payload),versions,version_hashes,commands:[],chain:chr.rows,lineage:lin.rows.map(r=>r.payload),certifications:[]};
      return replayPersistedCase(correlationId,GovernanceStore.fromSnapshot(snapshot));
    }finally{c.release();}
  }
  async replayEnvelope(correlationId:string):Promise<ReplayEnvelope>{
    const replay=await this.replay(correlationId);
    const c=await this.pool.connect();
    try{
      const r=await c.query<{payload:CertificationWrite}>('SELECT payload FROM clp_certifications WHERE correlation_id=$1 ORDER BY certification_id',[correlationId]);
      return {replay,certifications:r.rows.map(x=>x.payload)};
    }finally{c.release();}
  }
  backup():DurableBackup{throw new Error('PostgreSQL backup requires database-native export adapter');}
}
