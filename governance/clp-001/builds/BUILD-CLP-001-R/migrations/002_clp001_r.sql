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

-- Deterministically backfill authoritative state for every pre-R event.
-- The first event defaults to REPORTED when it carries no decision; later
-- null-decision events inherit the prior authoritative state.
WITH RECURSIVE ordered AS (
  SELECT e.*,
         row_number() OVER (PARTITION BY correlation_id ORDER BY aggregate_version, event_id) AS rn
  FROM clp_events e
), derived AS (
  SELECT correlation_id, aggregate_id, aggregate_version, event_id,
         COALESCE(decision, 'REPORTED')::text AS state,
         rn
  FROM ordered
  WHERE rn = 1
  UNION ALL
  SELECT o.correlation_id, o.aggregate_id, o.aggregate_version, o.event_id,
         COALESCE(o.decision, d.state)::text AS state,
         o.rn
  FROM derived d
  JOIN ordered o
    ON o.correlation_id = d.correlation_id
   AND o.rn = d.rn + 1
)
INSERT INTO clp_case_state_history(correlation_id,aggregate_id,aggregate_version,source_event_id,state,state_hash)
SELECT correlation_id, aggregate_id, aggregate_version, event_id, state,
       'legacy-md5:' || md5(correlation_id || ':' || aggregate_version::text || ':' || event_id || ':' || state)
FROM derived
ON CONFLICT DO NOTHING;

ALTER TABLE clp_certifications ADD COLUMN IF NOT EXISTS correlation_id TEXT;

-- Prefer an explicit legacy payload binding when present.
UPDATE clp_certifications
SET correlation_id = COALESCE(NULLIF(payload->>'correlation_id',''), NULLIF(payload->>'correlationId',''))
WHERE correlation_id IS NULL;

-- If and only if the database contains exactly one case correlation, that
-- correlation is an unambiguous binding for any remaining legacy certs.
WITH sole AS (
  SELECT min(correlation_id) AS correlation_id
  FROM clp_events
  HAVING count(DISTINCT correlation_id) = 1
)
UPDATE clp_certifications c
SET correlation_id = sole.correlation_id
FROM sole
WHERE c.correlation_id IS NULL;

-- Never guess across multiple cases. Ambiguous legacy certification
-- bindings block migration until an explicit mapping is supplied.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM clp_certifications WHERE correlation_id IS NULL) THEN
    RAISE EXCEPTION 'R migration refused: ambiguous legacy certification correlation binding';
  END IF;
END
$$;

ALTER TABLE clp_certifications ALTER COLUMN correlation_id SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_clp_certifications_correlation ON clp_certifications(correlation_id, certification_id);
COMMIT;
