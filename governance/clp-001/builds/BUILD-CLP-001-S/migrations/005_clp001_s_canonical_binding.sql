BEGIN;
SET search_path=edopsys_observability,public;

-- Bind integrity evidence to a specific build without mutating historical rows.
CREATE TABLE artifact_integrity_scope(
  id text PRIMARY KEY REFERENCES artifact_integrity(id),
  repository text NOT NULL,
  build_id text NOT NULL,
  observed_at timestamptz NOT NULL
);
CREATE TRIGGER artifact_integrity_scope_append_only
BEFORE UPDATE OR DELETE ON artifact_integrity_scope
FOR EACH ROW EXECUTE FUNCTION public.clp_reject_mutation();

-- Projection-only hardening: every health gate is bound to the active baseline.
DROP VIEW v_dashboard_summary_json;
DROP VIEW v_repository_health;
DROP VIEW v_integrity_health;
DROP VIEW v_review_health;
DROP VIEW v_authority_health;

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
    count(a.*) FILTER(WHERE a.required AND a.status IN('MISSING','HASH_MISMATCH','SIZE_MISMATCH')) blocked_count,
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

CREATE VIEW v_review_health AS
WITH b AS (
  SELECT DISTINCT ON(repository) *
  FROM repository_baseline
  ORDER BY repository,observed_at DESC,id DESC
), cb AS (
  SELECT b.repository,b.latest_merged_build,v.implementation_sha
  FROM b
  LEFT JOIN v_build_health v
    ON v.repository=b.repository AND v.build_id=b.latest_merged_build
), latest AS (
  SELECT DISTINCT ON(p.repository,p.pr_number,p.finding_key) p.*
  FROM pr_reviews p
  JOIN cb ON cb.repository=p.repository AND cb.implementation_sha=p.reviewed_sha
  ORDER BY p.repository,p.pr_number,p.finding_key,p.observed_at DESC,p.id DESC
), agg AS (
  SELECT b.repository,
    count(l.*) FILTER(WHERE l.severity='P0' AND NOT l.resolved AND NOT l.superseded) p0,
    count(l.*) FILTER(WHERE l.severity='P1' AND NOT l.resolved AND NOT l.superseded) p1,
    count(l.*) FILTER(WHERE l.severity='P2' AND NOT l.resolved AND NOT l.superseded) p2,
    count(l.*) review_count,
    count(l.*) FILTER(WHERE l.reviewed_sha=cb.implementation_sha AND l.expected_head_sha=cb.implementation_sha AND l.finding_status IN('APPROVED','CLEAN')) exact_head_clean_count
  FROM b
  LEFT JOIN cb ON cb.repository=b.repository
  LEFT JOIN latest l ON l.repository=b.repository
  GROUP BY b.repository
)
SELECT *,CASE
  WHEN review_count=0 THEN 'UNKNOWN'
  WHEN p0>0 OR p1>0 THEN 'BLOCKED'
  WHEN p2>0 THEN 'DEGRADED'
  WHEN exact_head_clean_count>0 THEN 'HEALTHY'
  ELSE 'UNKNOWN' END health
FROM agg;

CREATE VIEW v_authority_health AS
WITH repos AS (
  SELECT DISTINCT repository FROM repository_baseline
), latest AS (
  SELECT DISTINCT ON(repository,authority_id) *
  FROM authority_records
  ORDER BY repository,authority_id,observed_at DESC,id DESC
), agg AS (
  SELECT r.repository,
    count(a.*) FILTER(WHERE a.freshness_status NOT IN('SUPERSEDED','HISTORICAL_ONLY')) active_count,
    count(a.*) FILTER(WHERE a.freshness_status='CONFLICT' AND a.execution_blocking) blocking_conflict_count,
    count(a.*) FILTER(WHERE a.freshness_status='UNKNOWN') unknown_count,
    count(a.*) FILTER(WHERE a.freshness_status='FRESHNESS_REVIEW_DUE') freshness_due_count,
    count(a.*) FILTER(WHERE a.freshness_status='CONFLICT' AND NOT a.execution_blocking) nonblocking_conflict_count
  FROM repos r
  LEFT JOIN latest a ON a.repository=r.repository
  GROUP BY r.repository
)
SELECT repository,CASE
  WHEN blocking_conflict_count>0 THEN 'BLOCKED'
  WHEN active_count=0 OR unknown_count>0 THEN 'UNKNOWN'
  WHEN freshness_due_count>0 OR nonblocking_conflict_count>0 THEN 'DEGRADED'
  ELSE 'HEALTHY' END health
FROM agg;

CREATE VIEW v_repository_health AS
WITH b AS (
  SELECT DISTINCT ON(repository) *
  FROM repository_baseline
  ORDER BY repository,observed_at DESC,id DESC
), bu AS (
  SELECT repository,build_id,health
  FROM v_build_health
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
LEFT JOIN bu ON bu.repository=b.repository AND bu.build_id=b.latest_merged_build
LEFT JOIN v_ci_health ci ON ci.repository=b.repository AND ci.build_id=b.latest_merged_build
LEFT JOIN i ON i.repository=b.repository
LEFT JOIN rv ON rv.repository=b.repository
LEFT JOIN a ON a.repository=b.repository
LEFT JOIN d ON d.repository=b.repository;

CREATE VIEW v_dashboard_summary_json AS
SELECT repository,jsonb_build_object(
  'overall_health',overall_health,'canonical_head',canonical_head,'latest_build',latest_merged_build,'blocking_reason_count',blocking_reason_count,
  'gates',jsonb_build_object('governance',governance_status,'build',build_status,'ci',ci_status,'integrity',integrity_status,'review',review_status,'authority',authority_status,'drift',drift_status),
  'timeline',COALESCE((SELECT jsonb_agg(jsonb_build_object('at',occurred_at,'kind',event_kind,'id',event_id,'details',details) ORDER BY occurred_at) FROM v_governance_timeline t WHERE t.repository=r.repository),'[]'::jsonb)
) dashboard FROM v_repository_health r;
COMMIT;
