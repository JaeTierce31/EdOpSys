import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('R migration adds append-only state history and certification correlation binding',()=>{
  const sql=fs.readFileSync(new URL('../../migrations/002_clp001_r.sql',import.meta.url),'utf8');
  assert.match(sql,/CREATE TABLE IF NOT EXISTS clp_case_state_history/);
  assert.match(sql,/PRIMARY KEY \(correlation_id, aggregate_version\)/);
  assert.match(sql,/UNIQUE \(source_event_id\)/);
  assert.match(sql,/clp_case_state_history_append_only/);
  assert.match(sql,/WITH RECURSIVE ordered AS/);
  assert.match(sql,/COALESCE\(o\.decision, d\.state\)/);
  assert.match(sql,/ALTER TABLE clp_certifications ADD COLUMN IF NOT EXISTS correlation_id TEXT/);
  assert.match(sql,/DISABLE TRIGGER clp_certifications_append_only/);
  assert.match(sql,/ENABLE TRIGGER clp_certifications_append_only/);
  assert.match(sql,/count\(DISTINCT correlation_id\) = 1/);
  assert.match(sql,/ambiguous legacy certification correlation binding/);
  assert.match(sql,/ALTER COLUMN correlation_id SET NOT NULL/);
});

test('R recovery gate seeds populated Q data before migration 002 and asserts backfill',()=>{
  const sh=fs.readFileSync(new URL('../../scripts/postgres-r-backup-restore.sh',import.meta.url),'utf8');
  assert.ok(sh.indexOf('postgres-r-legacy-q-seed.sql') < sh.indexOf('002_clp001_r.sql'));
  assert.match(sh,/corr-r-legacy/);
  assert.match(sh,/CERT-R-LEGACY/);
});


test('R recovery projection covers both migrated legacy and R-native correlations',()=>{
  const sh=fs.readFileSync(new URL('../../scripts/postgres-r-backup-restore.sh',import.meta.url),'utf8');
  assert.match(sh,/corr-r-legacy/);
  assert.match(sh,/corr-r-seed/);
  assert.match(sh,/IN \('corr-r-seed','corr-r-legacy'\)/);
  assert.match(sh,/DST_DB.*corr-r-legacy|corr-r-legacy.*DST_DB/s);
});


test('R-native recovery seed is a replayable GoldenEvent-shaped fixture',()=>{
  const sql=fs.readFileSync(new URL('../../scripts/postgres-r-seed.sql',import.meta.url),'utf8');
  for(const field of ['occurred_at','actor_id','actor_type','causation_event_id','input_refs','output_refs','source_refs','policy_refs','evidence_refs','reason_code']) assert.match(sql,new RegExp(`\"${field}\"`));
  assert.match(sql,/sha256:076dcd5aa3584022fa3c6c6f1a6159f027b84c3d5dafa46a55fd250fe8dda3a1/);
  assert.match(sql,/sha256:dbc82d401c10273ce51226fa5851ead568ccc4fe99752ef18e1b323b4a11081e/);
  assert.match(sql,/sha256:f5506a8a87cff79044409b9517fd5f5a7fce9d2b0fdeb61ccafec9f749fc91ae/);
});
