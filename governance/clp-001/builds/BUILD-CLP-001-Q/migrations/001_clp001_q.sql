BEGIN;
CREATE TABLE IF NOT EXISTS clp_commands (
  command_id TEXT PRIMARY KEY,
  request_hash TEXT NOT NULL,
  result_event_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS clp_events (
  event_id TEXT PRIMARY KEY,
  correlation_id TEXT NOT NULL,
  aggregate_id TEXT NOT NULL,
  aggregate_version BIGINT NOT NULL CHECK (aggregate_version > 0),
  event_type TEXT NOT NULL,
  decision TEXT,
  event_hash TEXT NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (aggregate_id, aggregate_version)
);
CREATE INDEX IF NOT EXISTS idx_clp_events_correlation ON clp_events(correlation_id, aggregate_version);
CREATE TABLE IF NOT EXISTS clp_evidence (
  evidence_id TEXT PRIMARY KEY,
  correlation_id TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clp_evidence_correlation ON clp_evidence(correlation_id, evidence_id);
CREATE TABLE IF NOT EXISTS clp_versions (
  version_ref TEXT PRIMARY KEY,
  canonical_hash TEXT NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS clp_chain (
  event_id TEXT PRIMARY KEY REFERENCES clp_events(event_id) ON DELETE RESTRICT,
  correlation_id TEXT NOT NULL,
  ordinal BIGINT NOT NULL CHECK (ordinal > 0),
  event_hash TEXT NOT NULL,
  previous_chain_hash TEXT,
  chain_hash TEXT NOT NULL,
  UNIQUE (correlation_id, ordinal)
);
CREATE TABLE IF NOT EXISTS clp_lineage (
  lineage_id TEXT NOT NULL,
  correlation_id TEXT NOT NULL,
  parents JSONB NOT NULL,
  payload JSONB NOT NULL,
  PRIMARY KEY (correlation_id, lineage_id)
);
CREATE INDEX IF NOT EXISTS idx_clp_lineage_correlation ON clp_lineage(correlation_id, lineage_id);
CREATE TABLE IF NOT EXISTS clp_certifications (
  certification_id TEXT PRIMARY KEY,
  certification_hash TEXT NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION clp_reject_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'CLP append-only table % rejects %', TG_TABLE_NAME, TG_OP USING ERRCODE='55000';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS clp_events_append_only ON clp_events;
CREATE TRIGGER clp_events_append_only BEFORE UPDATE OR DELETE ON clp_events FOR EACH ROW EXECUTE FUNCTION clp_reject_mutation();
DROP TRIGGER IF EXISTS clp_evidence_append_only ON clp_evidence;
CREATE TRIGGER clp_evidence_append_only BEFORE UPDATE OR DELETE ON clp_evidence FOR EACH ROW EXECUTE FUNCTION clp_reject_mutation();
DROP TRIGGER IF EXISTS clp_versions_append_only ON clp_versions;
CREATE TRIGGER clp_versions_append_only BEFORE UPDATE OR DELETE ON clp_versions FOR EACH ROW EXECUTE FUNCTION clp_reject_mutation();
DROP TRIGGER IF EXISTS clp_commands_append_only ON clp_commands;
CREATE TRIGGER clp_commands_append_only BEFORE UPDATE OR DELETE ON clp_commands FOR EACH ROW EXECUTE FUNCTION clp_reject_mutation();
DROP TRIGGER IF EXISTS clp_chain_append_only ON clp_chain;
CREATE TRIGGER clp_chain_append_only BEFORE UPDATE OR DELETE ON clp_chain FOR EACH ROW EXECUTE FUNCTION clp_reject_mutation();
DROP TRIGGER IF EXISTS clp_lineage_append_only ON clp_lineage;
CREATE TRIGGER clp_lineage_append_only BEFORE UPDATE OR DELETE ON clp_lineage FOR EACH ROW EXECUTE FUNCTION clp_reject_mutation();
DROP TRIGGER IF EXISTS clp_certifications_append_only ON clp_certifications;
CREATE TRIGGER clp_certifications_append_only BEFORE UPDATE OR DELETE ON clp_certifications FOR EACH ROW EXECUTE FUNCTION clp_reject_mutation();
COMMIT;
