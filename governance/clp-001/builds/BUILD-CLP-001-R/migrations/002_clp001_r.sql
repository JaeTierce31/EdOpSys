BEGIN;
CREATE TABLE IF NOT EXISTS clp_case_state_history (
  correlation_id TEXT NOT NULL,
  aggregate_id TEXT NOT NULL,
  aggregate_version BIGINT NOT NULL CHECK (aggregate_version > 0),
  source_event_id TEXT NOT NULL REFERENCES clp_events(event_id) ON DELETE RESTRICT,
  state TEXT NOT NULL,
  state_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (correlation_id, aggregate_version),
  UNIQUE (source_event_id)
);
CREATE INDEX IF NOT EXISTS idx_clp_case_state_latest ON clp_case_state_history(correlation_id, aggregate_version DESC);
DROP TRIGGER IF EXISTS clp_case_state_history_append_only ON clp_case_state_history;
CREATE TRIGGER clp_case_state_history_append_only BEFORE UPDATE OR DELETE ON clp_case_state_history FOR EACH ROW EXECUTE FUNCTION clp_reject_mutation();

ALTER TABLE clp_certifications ADD COLUMN IF NOT EXISTS correlation_id TEXT;
CREATE INDEX IF NOT EXISTS idx_clp_certifications_correlation ON clp_certifications(correlation_id, certification_id);
COMMIT;
