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
