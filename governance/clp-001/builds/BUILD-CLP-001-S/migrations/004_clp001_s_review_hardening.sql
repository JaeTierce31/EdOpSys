BEGIN;
SET search_path=edopsys_observability,public;

-- Stable logical key permits append-only review finding state transitions.
ALTER TABLE pr_reviews ADD COLUMN finding_key text NOT NULL DEFAULT '__summary__';

CREATE OR REPLACE VIEW v_review_health AS
WITH repos AS (
  SELECT DISTINCT repository FROM repository_baseline
), latest AS (
  SELECT DISTINCT ON(repository,pr_number,finding_key) *
  FROM pr_reviews
  ORDER BY repository,pr_number,finding_key,observed_at DESC,id DESC
), agg AS (
  SELECT r.repository,
    count(l.*) FILTER(WHERE l.severity='P0' AND NOT l.resolved AND NOT l.superseded) p0,
    count(l.*) FILTER(WHERE l.severity='P1' AND NOT l.resolved AND NOT l.superseded) p1,
    count(l.*) FILTER(WHERE l.severity='P2' AND NOT l.resolved AND NOT l.superseded) p2,
    count(l.*) review_count,
    count(l.*) FILTER(WHERE l.reviewed_sha=l.expected_head_sha AND l.finding_status IN('APPROVED','CLEAN')) exact_head_clean_count
  FROM repos r LEFT JOIN latest l USING(repository) GROUP BY r.repository
)
SELECT *,CASE
  WHEN review_count=0 THEN 'UNKNOWN'
  WHEN p0>0 OR p1>0 THEN 'BLOCKED'
  WHEN p2>0 THEN 'DEGRADED'
  WHEN exact_head_clean_count>0 THEN 'HEALTHY'
  ELSE 'UNKNOWN' END health
FROM agg;

CREATE OR REPLACE VIEW v_authority_health AS
SELECT r.repository,CASE
  WHEN count(a.*) FILTER(WHERE freshness_status='CONFLICT' AND execution_blocking)>0 THEN 'BLOCKED'
  WHEN count(a.*)=0 OR count(a.*) FILTER(WHERE freshness_status='UNKNOWN')>0 THEN 'UNKNOWN'
  WHEN count(a.*) FILTER(WHERE freshness_status='FRESHNESS_REVIEW_DUE')>0 THEN 'DEGRADED'
  ELSE 'HEALTHY' END health
FROM (SELECT DISTINCT repository FROM repository_baseline) r
LEFT JOIN authority_records a USING(repository) GROUP BY r.repository;

CREATE OR REPLACE VIEW v_governance_drift AS
SELECT r.repository,
  count(d.*) drift_observation_count,
  count(d.*) FILTER(WHERE resolution_status='OPEN' AND severity IN('P0','P1')) blocking_open_count,
  count(d.*) FILTER(WHERE resolution_status='OPEN' AND severity IN('P2','P3')) nonblocking_open_count,
  CASE
    WHEN count(d.*)=0 THEN 'UNKNOWN'
    WHEN count(d.*) FILTER(WHERE resolution_status='OPEN' AND severity IN('P0','P1'))>0 THEN 'BLOCKED'
    WHEN count(d.*) FILTER(WHERE resolution_status='OPEN' AND severity IN('P2','P3'))>0 THEN 'DEGRADED'
    ELSE 'HEALTHY' END health
FROM (SELECT DISTINCT repository FROM repository_baseline) r
LEFT JOIN governance_drift_findings d USING(repository) GROUP BY r.repository;

CREATE OR REPLACE VIEW v_repository_health AS
WITH b AS (
  SELECT DISTINCT ON(repository)* FROM repository_baseline ORDER BY repository,observed_at DESC,id DESC
), bu AS (
  SELECT DISTINCT ON(repository) repository,build_id,health FROM v_build_health WHERE canonical ORDER BY repository,observed_at DESC
), i AS (SELECT * FROM v_integrity_health),
rv AS (SELECT * FROM v_review_health),a AS (SELECT * FROM v_authority_health),d AS (SELECT * FROM v_governance_drift)
SELECT b.repository,b.canonical_head,b.latest_merged_build,
  CASE WHEN EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=b.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CONFLICT') THEN 'BLOCKED'
       WHEN EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=b.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CURRENT') THEN 'CURRENT'
       ELSE 'UNKNOWN' END governance_status,
  COALESCE(bu.health,'UNKNOWN') build_status,
  COALESCE(ci.ci_health,'NO_RUN') ci_status,
  COALESCE(i.health,'UNKNOWN') integrity_status,
  COALESCE(rv.health,'UNKNOWN') review_status,
  COALESCE(a.health,'UNKNOWN') authority_status,
  COALESCE(d.health,'UNKNOWN') drift_status,
  (COALESCE(rv.p0,0)+COALESCE(rv.p1,0)
   +CASE WHEN COALESCE(bu.health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END
   +CASE WHEN COALESCE(i.health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END
   +CASE WHEN COALESCE(ci.ci_health,'NO_RUN')='FAIL' THEN 1 ELSE 0 END
   +CASE WHEN COALESCE(a.health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END
   +CASE WHEN COALESCE(d.health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END
   +CASE WHEN EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=b.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CONFLICT') THEN 1 ELSE 0 END) blocking_reason_count,
  CASE
    WHEN COALESCE(bu.health,'UNKNOWN')='BLOCKED' OR COALESCE(i.health,'UNKNOWN')='BLOCKED' OR COALESCE(rv.health,'UNKNOWN')='BLOCKED' OR COALESCE(a.health,'UNKNOWN')='BLOCKED' OR COALESCE(d.health,'UNKNOWN')='BLOCKED' OR COALESCE(ci.ci_health,'NO_RUN')='FAIL' OR EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=b.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CONFLICT') THEN 'BLOCKED'
    WHEN COALESCE(bu.health,'UNKNOWN')='UNKNOWN' OR COALESCE(i.health,'UNKNOWN')='UNKNOWN' OR COALESCE(rv.health,'UNKNOWN')='UNKNOWN' OR COALESCE(a.health,'UNKNOWN')='UNKNOWN' OR COALESCE(d.health,'UNKNOWN')='UNKNOWN' OR COALESCE(ci.ci_health,'NO_RUN') IN('NO_RUN','IN_PROGRESS') OR NOT EXISTS(SELECT 1 FROM v_governance_assertion_current g WHERE g.repository=b.repository AND g.subject='G0' AND g.predicate='designation_status' AND g.status='CURRENT') THEN 'UNKNOWN'
    WHEN COALESCE(bu.health,'UNKNOWN')='DEGRADED' OR COALESCE(rv.health,'UNKNOWN')='DEGRADED' OR COALESCE(a.health,'UNKNOWN')='DEGRADED' OR COALESCE(d.health,'UNKNOWN')='DEGRADED' OR COALESCE(ci.ci_health,'NO_RUN')='STALE_HEAD' THEN 'DEGRADED'
    ELSE 'HEALTHY' END overall_health
FROM b
LEFT JOIN bu USING(repository)
LEFT JOIN v_ci_health ci ON ci.repository=b.repository AND ci.build_id=b.latest_merged_build
LEFT JOIN i USING(repository) LEFT JOIN rv USING(repository) LEFT JOIN a USING(repository) LEFT JOIN d USING(repository);

CREATE OR REPLACE VIEW v_dashboard_summary_json AS
SELECT repository,jsonb_build_object(
  'overall_health',overall_health,'canonical_head',canonical_head,'latest_build',latest_merged_build,'blocking_reason_count',blocking_reason_count,
  'gates',jsonb_build_object('governance',governance_status,'build',build_status,'ci',ci_status,'integrity',integrity_status,'review',review_status,'authority',authority_status,'drift',drift_status),
  'timeline',COALESCE((SELECT jsonb_agg(jsonb_build_object('at',occurred_at,'kind',event_kind,'id',event_id,'details',details) ORDER BY occurred_at) FROM v_governance_timeline t WHERE t.repository=r.repository),'[]'::jsonb)
) dashboard FROM v_repository_health r;
COMMIT;
