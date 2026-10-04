BEGIN;
SET search_path=edopsys_observability,public;

-- v1.0.2 hardening: derive integrity from recorded measurements and bind CI
-- to both the active baseline build and the active implementation SHA.
DROP VIEW v_dashboard_summary_json;
DROP VIEW v_repository_health;
DROP VIEW v_integrity_health;

CREATE VIEW v_integrity_health AS
WITH b AS (
  SELECT DISTINCT ON(repository) *
  FROM repository_baseline
  ORDER BY repository,observed_at DESC,id DESC
), current_integrity AS (
  SELECT a.*,s.build_id
  FROM artifact_integrity a
  JOIN artifact_integrity_scope s ON s.id=a.id AND s.repository=a.repository
), agg AS (
  SELECT b.repository,
    count(a.*) FILTER(WHERE a.required) required_count,
    count(a.*) FILTER(
      WHERE a.required AND (
        a.status IN('MISSING','HASH_MISMATCH','SIZE_MISMATCH')
        OR a.observed_sha256 IS NULL
        OR a.observed_bytes IS NULL
        OR a.expected_sha256 IS NULL
        OR a.expected_bytes IS NULL
        OR a.expected_sha256 IS DISTINCT FROM a.observed_sha256
        OR a.expected_bytes IS DISTINCT FROM a.observed_bytes
      )
    ) blocked_count,
    count(a.*) FILTER(WHERE a.required AND a.status='UNVERIFIED') unverified_count
  FROM b
  LEFT JOIN current_integrity a
    ON a.repository=b.repository AND a.build_id=b.latest_merged_build
  GROUP BY b.repository
)
SELECT repository,CASE
  WHEN blocked_count>0 THEN 'BLOCKED'
  WHEN required_count=0 OR unverified_count>0 THEN 'UNKNOWN'
  ELSE 'HEALTHY' END health
FROM agg;

CREATE VIEW v_repository_health AS
WITH b AS (
  SELECT DISTINCT ON(repository) *
  FROM repository_baseline
  ORDER BY repository,observed_at DESC,id DESC
), bu AS (
  SELECT repository,build_id,implementation_sha,health
  FROM v_build_health
), active AS (
  SELECT b.*,bu.implementation_sha,bu.health build_health
  FROM b
  LEFT JOIN bu ON bu.repository=b.repository AND bu.build_id=b.latest_merged_build
), ci_latest AS (
  SELECT DISTINCT ON(c.repository,c.build_id,c.head_sha) c.*
  FROM ci_runs c
  JOIN active x
    ON x.repository=c.repository
   AND x.latest_merged_build=c.build_id
   AND x.implementation_sha=c.head_sha
  ORDER BY c.repository,c.build_id,c.head_sha,c.observed_at DESC,c.id DESC
), ci AS (
  SELECT x.repository,x.latest_merged_build build_id,
    CASE
      WHEN x.implementation_sha IS NULL THEN 'NO_RUN'
      WHEN c.id IS NULL THEN 'NO_RUN'
      WHEN c.status IN('queued','in_progress') THEN 'IN_PROGRESS'
      WHEN c.conclusion='success' AND c.head_sha=x.implementation_sha THEN 'PASS'
      WHEN c.conclusion IN('failure','cancelled','timed_out','action_required','startup_failure') THEN 'FAIL'
      ELSE 'NO_RUN'
    END ci_health
  FROM active x
  LEFT JOIN ci_latest c
    ON c.repository=x.repository
   AND c.build_id=x.latest_merged_build
   AND c.head_sha=x.implementation_sha
), i AS (SELECT * FROM v_integrity_health),
rv AS (SELECT * FROM v_review_health),a AS (SELECT * FROM v_authority_health),d AS (SELECT * FROM v_governance_drift)
SELECT x.repository,x.canonical_head,x.latest_merged_build,
  CASE WHEN EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=x.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CONFLICT') THEN 'BLOCKED'
       WHEN EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=x.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CURRENT') THEN 'CURRENT'
       ELSE 'UNKNOWN' END governance_status,
  COALESCE(x.build_health,'UNKNOWN') build_status,
  COALESCE(ci.ci_health,'NO_RUN') ci_status,
  COALESCE(i.health,'UNKNOWN') integrity_status,
  COALESCE(rv.health,'UNKNOWN') review_status,
  COALESCE(a.health,'UNKNOWN') authority_status,
  COALESCE(d.health,'UNKNOWN') drift_status,
  (COALESCE(rv.p0,0)+COALESCE(rv.p1,0)
   +CASE WHEN COALESCE(x.build_health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END
   +CASE WHEN COALESCE(i.health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END
   +CASE WHEN COALESCE(ci.ci_health,'NO_RUN')='FAIL' THEN 1 ELSE 0 END
   +CASE WHEN COALESCE(a.health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END
   +CASE WHEN COALESCE(d.health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END
   +CASE WHEN EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=x.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CONFLICT') THEN 1 ELSE 0 END) blocking_reason_count,
  CASE
    WHEN COALESCE(x.build_health,'UNKNOWN')='BLOCKED' OR COALESCE(i.health,'UNKNOWN')='BLOCKED' OR COALESCE(rv.health,'UNKNOWN')='BLOCKED' OR COALESCE(a.health,'UNKNOWN')='BLOCKED' OR COALESCE(d.health,'UNKNOWN')='BLOCKED' OR COALESCE(ci.ci_health,'NO_RUN')='FAIL' OR EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=x.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CONFLICT') THEN 'BLOCKED'
    WHEN COALESCE(x.build_health,'UNKNOWN')='UNKNOWN' OR COALESCE(i.health,'UNKNOWN')='UNKNOWN' OR COALESCE(rv.health,'UNKNOWN')='UNKNOWN' OR COALESCE(a.health,'UNKNOWN')='UNKNOWN' OR COALESCE(d.health,'UNKNOWN')='UNKNOWN' OR COALESCE(ci.ci_health,'NO_RUN') IN('NO_RUN','IN_PROGRESS') OR NOT EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=x.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CURRENT') THEN 'UNKNOWN'
    WHEN COALESCE(x.build_health,'UNKNOWN')='DEGRADED' OR COALESCE(rv.health,'UNKNOWN')='DEGRADED' OR COALESCE(a.health,'UNKNOWN')='DEGRADED' OR COALESCE(d.health,'UNKNOWN')='DEGRADED' THEN 'DEGRADED'
    ELSE 'HEALTHY' END overall_health
FROM active x
LEFT JOIN ci ON ci.repository=x.repository AND ci.build_id=x.latest_merged_build
LEFT JOIN i ON i.repository=x.repository
LEFT JOIN rv ON rv.repository=x.repository
LEFT JOIN a ON a.repository=x.repository
LEFT JOIN d ON d.repository=x.repository;

CREATE VIEW v_dashboard_summary_json AS
SELECT repository,jsonb_build_object(
  'overall_health',overall_health,'canonical_head',canonical_head,'latest_build',latest_merged_build,'blocking_reason_count',blocking_reason_count,
  'gates',jsonb_build_object('governance',governance_status,'build',build_status,'ci',ci_status,'integrity',integrity_status,'review',review_status,'authority',authority_status,'drift',drift_status),
  'timeline',COALESCE((SELECT jsonb_agg(jsonb_build_object('at',occurred_at,'kind',event_kind,'id',event_id,'details',details) ORDER BY occurred_at) FROM v_governance_timeline t WHERE t.repository=r.repository),'[]'::jsonb)
+) dashboard FROM v_repository_health r;

COMMIT;
