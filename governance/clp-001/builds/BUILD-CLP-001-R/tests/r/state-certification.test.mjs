import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { buildGoldenCase, hashCanonical } from '../../dist/src/index.js';
import { ReferenceTransactionalStore } from '../../dist/src/q-reference-store.js';
import { QKernelService } from '../../dist/src/q-service.js';
import { authorizeTransition, evaluateEligibility } from '../../input/BUILD-CLP-001-B/dist/src/index.js';

const policy=JSON.parse(fs.readFileSync(new URL('../../input/BUILD-CLP-001-B/input/BUILD-CLP-001-A/fixtures/transition-policy.json', import.meta.url),'utf8'));
function bundleFor(ev, commandId, opts={}){
  const g=buildGoldenCase();
  const ch=g.event_chain.find(x=>x.event_id===ev.event_id);
  return {command_id:commandId,request_hash:hashCanonical({commandId,event:ev}),event:ev,evidence:opts.evidence??[],versions:opts.versions??[],chain:ch?[ch]:[],lineage:opts.lineage??[],certifications:opts.certifications??[]};
}

test('null-decision event preserves explicit authoritative state history', async()=>{
  const g=buildGoldenCase();
  const store=new ReferenceTransactionalStore();
  for(const ev of g.events.slice(0,3)) await store.appendBundle(bundleFor(ev,`cmd-${ev.aggregate_version}`));
  assert.equal(await store.caseState(g.correlation_id),'INTAKE_STRUCTURED');
  await store.appendBundle(bundleFor(g.events[3],'cmd-4'));
  assert.equal(await store.caseState(g.correlation_id),'INTAKE_STRUCTURED');
  const receipt=await store.caseStateReceipt(g.correlation_id);
  assert.equal(receipt.aggregate_version,4);
  assert.equal(receipt.state,'INTAKE_STRUCTURED');
  assert.equal(receipt.source_event_id,g.events[3].event_id);
});

test('transition service writes target state receipt and rejects mismatched persisted state', async()=>{
  const g=buildGoldenCase();
  const store=new ReferenceTransactionalStore();
  const svc=new QKernelService(store,policy,{authorizeTransition,evaluateEligibility});
  for(const ev of g.events.slice(0,2)) await store.appendBundle(bundleFor(ev,`cmd-seed-${ev.aggregate_version}`));
  const ev=g.events[2];
  const b=bundleFor(ev,'cmd-transition',{versions:[{ref:'CLP-001-TRANSITIONS@1.0.0',record:policy}]});
  await svc.executeTransition({from:'REPORTED',to:'INTAKE_STRUCTURED',satisfied_guards:['resident_origin_evidence_present'],bundle:b});
  assert.equal((await store.caseStateReceipt(g.correlation_id)).state,'INTAKE_STRUCTURED');
  const repeated={...g.events[2],event_id:'evt-repeat',aggregate_version:4,causation_event_id:g.events[2].event_id}; const rp={...repeated}; delete rp.event_hash; repeated.event_hash=hashCanonical(rp);
  await assert.rejects(svc.executeTransition({from:'REPORTED',to:'INTAKE_STRUCTURED',satisfied_guards:['resident_origin_evidence_present'],bundle:{...bundleFor(repeated,'cmd-bad'),versions:[{ref:'CLP-001-TRANSITIONS@1.0.0',record:policy}]}}),/persisted state mismatch/);
});

test('certifications reconstruct only for requested correlation without changing replay hash', async()=>{
  const g=buildGoldenCase();
  const store=new ReferenceTransactionalStore();
  const ev=g.events[0];
  await store.appendBundle(bundleFor(ev,'cmd-cert-a',{evidence:g.evidence.slice(0,2),certifications:[{certification_id:'CERT-A',status:'PASS'}]}));
  const other={...ev,event_id:'evt-other',aggregate_id:'CASE-OTHER',correlation_id:'corr-other',evidence_refs:[]};
  const payload={...other}; delete payload.event_hash; other.event_hash=hashCanonical(payload);
  await store.appendBundle(bundleFor(other,'cmd-cert-b',{evidence:g.evidence.slice(0,2).map((x,i)=>({...x,evidence_id:x.evidence_id+'-B',parent_evidence_ids:[]})),certifications:[{certification_id:'CERT-B',status:'PASS'}]}));
  const base=await store.replay(g.correlation_id);
  const env=await store.replayEnvelope(g.correlation_id);
  assert.equal(env.replay.replay_hash,base.replay_hash);
  assert.deepEqual(env.certifications.map(x=>x.certification_id),['CERT-A']);
});

test('transport exposes case-scoped replay envelope but no certification write endpoint', async()=>{
  const { createTransportHandler }=await import('../../dist/src/q-transport.js');
  const g=buildGoldenCase(); const store=new ReferenceTransactionalStore();
  await store.appendBundle(bundleFor(g.events[0],'cmd-env',{evidence:g.evidence.slice(0,2),certifications:[{certification_id:'CERT-ENV',status:'PASS'}]}));
  const svc=new QKernelService(store,policy,{authorizeTransition,evaluateEligibility});
  const h=createTransportHandler(svc);
  const r=await h({method:'GET',path:`/v1/clp001/cases/${g.correlation_id}/replay-envelope`});
  assert.equal(r.status,200); assert.deepEqual(r.body.certifications.map(x=>x.certification_id),['CERT-ENV']);
  assert.equal((await h({method:'POST',path:'/v1/clp001/certifications',body:{}})).status,404);
});

test('restore migrates legacy Q backup metadata deterministically', async()=>{
  const g=buildGoldenCase();
  const store=new ReferenceTransactionalStore();
  for(const ev of g.events.slice(0,4)) await store.appendBundle(bundleFor(ev,`cmd-legacy-${ev.aggregate_version}`,ev.aggregate_version===1?{evidence:g.evidence.slice(0,2),certifications:[{certification_id:'CERT-LEGACY',status:'PASS'}]}:{}));
  const legacy=JSON.parse(JSON.stringify(store.backup()));
  delete legacy.state_history;
  delete legacy.certification_correlations;
  const restored=ReferenceTransactionalStore.restore(legacy);
  assert.equal(await restored.caseState(g.correlation_id),'INTAKE_STRUCTURED');
  assert.equal((await restored.caseStateReceipt(g.correlation_id)).aggregate_version,4);
  assert.deepEqual(Object.fromEntries(restored.backup().certification_correlations),{'CERT-LEGACY':g.correlation_id});
});

test('restore rejects ambiguous legacy certification correlation binding', async()=>{
  const g=buildGoldenCase();
  const store=new ReferenceTransactionalStore();
  await store.appendBundle(bundleFor(g.events[0],'cmd-legacy-a',{certifications:[{certification_id:'CERT-AMB',status:'PASS'}]}));
  const other={...g.events[0],event_id:'evt-legacy-other',aggregate_id:'CASE-LEGACY-OTHER',correlation_id:'corr-legacy-other',evidence_refs:[]};
  const payload={...other}; delete payload.event_hash; other.event_hash=hashCanonical(payload);
  await store.appendBundle(bundleFor(other,'cmd-legacy-b'));
  const legacy=JSON.parse(JSON.stringify(store.backup()));
  delete legacy.state_history;
  delete legacy.certification_correlations;
  assert.throws(()=>ReferenceTransactionalStore.restore(legacy),/ambiguous legacy certification correlation binding/);
});

test('certification correlation binding is immutable across idempotent payload reuse', async()=>{
  const g=buildGoldenCase();
  const store=new ReferenceTransactionalStore();
  const cert={certification_id:'CERT-BOUND',status:'PASS'};
  await store.appendBundle(bundleFor(g.events[0],'cmd-bound-a',{evidence:g.evidence.slice(0,2),certifications:[cert]}));
  const other={...g.events[0],event_id:'evt-bound-other',aggregate_id:'CASE-BOUND-OTHER',correlation_id:'corr-bound-other',evidence_refs:[]};
  const payload={...other}; delete payload.event_hash; other.event_hash=hashCanonical(payload);
  await assert.rejects(store.appendBundle(bundleFor(other,'cmd-bound-b',{certifications:[cert]})),/immutable certification correlation conflict/);
  assert.deepEqual(Object.fromEntries(store.backup().certification_correlations),{'CERT-BOUND':g.correlation_id});
});
