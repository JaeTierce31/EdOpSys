BEGIN;
CREATE SCHEMA IF NOT EXISTS edopsys_observability;
COMMENT ON SCHEMA edopsys_observability IS 'Observability projections are descriptive and MUST NOT authorize CLP state transitions, worker eligibility, verification, payout, or policy execution.';

CREATE TABLE edopsys_observability.obs_observations(
 observation_id text PRIMARY KEY, repository text NOT NULL, observation_type text NOT NULL,
 source_ref text NOT NULL, source_sha text, observed_at timestamptz NOT NULL,
 payload_hash text NOT NULL, payload jsonb NOT NULL);
CREATE TABLE edopsys_observability.repository_baseline(
 id text PRIMARY KEY REFERENCES edopsys_observability.obs_observations(observation_id), repository text NOT NULL,
 canonical_head text NOT NULL, latest_merged_build text NOT NULL, g0_sha text, g1_sha text,
 p_merge_sha text,q_merge_sha text,r_merge_sha text,observed_at timestamptz NOT NULL);
CREATE TABLE edopsys_observability.build_status(
 id text PRIMARY KEY REFERENCES edopsys_observability.obs_observations(observation_id),repository text NOT NULL,
 build_id text NOT NULL,authorized boolean NOT NULL,implementation_sha text,merge_sha text,parent_sha text,
 tests_passed int,tests_total int,ci_conclusion text,review_state text,blocking_findings int NOT NULL DEFAULT 0,
 canonical boolean NOT NULL DEFAULT false,observed_at timestamptz NOT NULL);
CREATE TABLE edopsys_observability.authority_records(
 id text PRIMARY KEY REFERENCES edopsys_observability.obs_observations(observation_id),repository text NOT NULL,
 authority_id text NOT NULL,version text NOT NULL,source_class text,jurisdiction text,content_hash text,
 freshness_status text NOT NULL CHECK(freshness_status IN('CURRENT','FRESHNESS_REVIEW_DUE','SUPERSEDED','HISTORICAL_ONLY','CONFLICT','UNKNOWN')),
 execution_blocking boolean NOT NULL DEFAULT false,observed_at timestamptz NOT NULL);
CREATE TABLE edopsys_observability.artifact_integrity(
 id text PRIMARY KEY REFERENCES edopsys_observability.obs_observations(observation_id),repository text NOT NULL,
 artifact_path text NOT NULL,required boolean NOT NULL DEFAULT true,status text NOT NULL CHECK(status IN('PASS','MISSING','HASH_MISMATCH','SIZE_MISMATCH','UNVERIFIED')),
 expected_sha256 text,observed_sha256 text,expected_bytes bigint,observed_bytes bigint,observed_at timestamptz NOT NULL);
CREATE TABLE edopsys_observability.ci_runs(
 id text PRIMARY KEY REFERENCES edopsys_observability.obs_observations(observation_id),repository text NOT NULL,
 build_id text NOT NULL,run_id bigint NOT NULL,head_sha text NOT NULL,expected_head_sha text NOT NULL,
 status text NOT NULL,conclusion text,substantive_result text,observed_at timestamptz NOT NULL);
CREATE TABLE edopsys_observability.pr_reviews(
 id text PRIMARY KEY REFERENCES edopsys_observability.obs_observations(observation_id),repository text NOT NULL,
 pr_number int NOT NULL,reviewed_sha text NOT NULL,expected_head_sha text NOT NULL,reviewer text NOT NULL,
 severity text CHECK(severity IS NULL OR severity IN('P0','P1','P2','P3')),finding_status text NOT NULL,
 resolved boolean NOT NULL DEFAULT false,superseded boolean NOT NULL DEFAULT false,merge_blocking boolean NOT NULL DEFAULT false,
 observed_at timestamptz NOT NULL);
CREATE TABLE edopsys_observability.governance_status_assertions(
 assertion_id text PRIMARY KEY,repository text NOT NULL,subject text NOT NULL,predicate text NOT NULL,value jsonb NOT NULL,
 source_path text NOT NULL,source_commit text,observed_at timestamptz NOT NULL,valid_to timestamptz,
 superseded_by text REFERENCES edopsys_observability.governance_status_assertions(assertion_id),authority_rank int NOT NULL,
 status text NOT NULL CHECK(status IN('CURRENT','HISTORICAL','SUPERSEDED','CONFLICT','UNKNOWN')));
CREATE TABLE edopsys_observability.governance_supersession_receipts(
 receipt_id text PRIMARY KEY,repository text NOT NULL,superseded_assertion_id text NOT NULL REFERENCES edopsys_observability.governance_status_assertions(assertion_id),
 superseding_assertion_id text NOT NULL REFERENCES edopsys_observability.governance_status_assertions(assertion_id),rationale text NOT NULL,receipt_hash text NOT NULL,observed_at timestamptz NOT NULL);
CREATE TABLE edopsys_observability.governance_drift_findings(
 finding_id text PRIMARY KEY,repository text NOT NULL,finding_type text NOT NULL,subject text NOT NULL,severity text NOT NULL CHECK(severity IN('P0','P1','P2','P3')),
 resolution_status text NOT NULL CHECK(resolution_status IN('OPEN','RESOLVED','SUPERSEDED','ACCEPTED_RISK')),resolution_receipt text REFERENCES edopsys_observability.governance_supersession_receipts(receipt_id),detected_at timestamptz NOT NULL);

DO $$DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['obs_observations','repository_baseline','build_status','authority_records','artifact_integrity','ci_runs','pr_reviews','governance_status_assertions','governance_supersession_receipts','governance_drift_findings'] LOOP EXECUTE format('CREATE TRIGGER %I_append_only BEFORE UPDATE OR DELETE ON edopsys_observability.%I FOR EACH ROW EXECUTE FUNCTION public.clp_reject_mutation()',t,t); END LOOP;END$$;

CREATE VIEW edopsys_observability.v_build_health AS
SELECT DISTINCT ON(repository,build_id) *,CASE WHEN blocking_findings>0 OR NOT authorized OR ci_conclusion NOT IN('success') THEN 'BLOCKED' WHEN ci_conclusion IS NULL OR review_state IS NULL THEN 'UNKNOWN' WHEN review_state NOT IN('APPROVED','APPROVED_EXTERNAL','CLEAN') THEN 'DEGRADED' ELSE 'HEALTHY' END health
FROM edopsys_observability.build_status ORDER BY repository,build_id,observed_at DESC,id DESC;
CREATE VIEW edopsys_observability.v_integrity_health AS
SELECT r.repository,CASE WHEN count(a.*) FILTER(WHERE a.required AND a.status IN('MISSING','HASH_MISMATCH','SIZE_MISMATCH'))>0 THEN 'BLOCKED' WHEN count(a.*) FILTER(WHERE a.required)=0 OR count(a.*) FILTER(WHERE a.required AND a.status='UNVERIFIED')>0 THEN 'UNKNOWN' ELSE 'HEALTHY' END health
FROM (SELECT DISTINCT repository FROM edopsys_observability.repository_baseline) r LEFT JOIN edopsys_observability.artifact_integrity a USING(repository) GROUP BY r.repository;
CREATE VIEW edopsys_observability.v_ci_health AS
SELECT DISTINCT ON(repository,build_id) *,CASE WHEN status<>'completed' THEN 'IN_PROGRESS' WHEN head_sha<>expected_head_sha THEN 'STALE_HEAD' WHEN conclusion='success' AND substantive_result='success' THEN 'PASS' ELSE 'FAIL' END ci_health
FROM edopsys_observability.ci_runs ORDER BY repository,build_id,observed_at DESC,id DESC;
CREATE VIEW edopsys_observability.v_review_health AS
SELECT r.repository,count(p.*) FILTER(WHERE severity='P0' AND NOT resolved AND NOT superseded) p0,count(p.*) FILTER(WHERE severity='P1' AND NOT resolved AND NOT superseded) p1,count(p.*) FILTER(WHERE severity='P2' AND NOT resolved AND NOT superseded) p2,
CASE WHEN count(p.*)=0 THEN 'UNKNOWN' WHEN count(p.*) FILTER(WHERE severity IN('P0','P1') AND NOT resolved AND NOT superseded)>0 THEN 'BLOCKED' WHEN count(p.*) FILTER(WHERE severity='P2' AND NOT resolved AND NOT superseded)>0 THEN 'DEGRADED' WHEN count(p.*) FILTER(WHERE reviewed_sha=expected_head_sha AND finding_status IN('APPROVED','CLEAN'))>0 THEN 'HEALTHY' ELSE 'UNKNOWN' END health
FROM (SELECT DISTINCT repository FROM edopsys_observability.repository_baseline) r LEFT JOIN edopsys_observability.pr_reviews p USING(repository) GROUP BY r.repository;
CREATE VIEW edopsys_observability.v_authority_health AS
SELECT r.repository,CASE WHEN count(a.*)=0 OR count(a.*) FILTER(WHERE freshness_status='UNKNOWN')>0 THEN 'UNKNOWN' WHEN count(a.*) FILTER(WHERE freshness_status='CONFLICT' AND execution_blocking)>0 THEN 'BLOCKED' WHEN count(a.*) FILTER(WHERE freshness_status='FRESHNESS_REVIEW_DUE')>0 THEN 'DEGRADED' ELSE 'HEALTHY' END health
FROM (SELECT DISTINCT repository FROM edopsys_observability.repository_baseline) r LEFT JOIN edopsys_observability.authority_records a USING(repository) GROUP BY r.repository;
CREATE VIEW edopsys_observability.v_governance_drift AS
SELECT r.repository,count(d.*) FILTER(WHERE resolution_status='OPEN' AND severity IN('P0','P1')) blocking_open_count,count(d.*) FILTER(WHERE resolution_status='OPEN' AND severity IN('P2','P3')) nonblocking_open_count,
CASE WHEN count(d.*) FILTER(WHERE resolution_status='OPEN' AND severity IN('P0','P1'))>0 THEN 'BLOCKED' WHEN count(d.*) FILTER(WHERE resolution_status='OPEN' AND severity IN('P2','P3'))>0 THEN 'DEGRADED' ELSE 'HEALTHY' END health
FROM (SELECT DISTINCT repository FROM edopsys_observability.repository_baseline) r LEFT JOIN edopsys_observability.governance_drift_findings d USING(repository) GROUP BY r.repository;
CREATE VIEW edopsys_observability.v_governance_assertion_current AS
SELECT DISTINCT ON(repository,subject,predicate) * FROM edopsys_observability.governance_status_assertions WHERE valid_to IS NULL AND status IN('CURRENT','CONFLICT','UNKNOWN') ORDER BY repository,subject,predicate,authority_rank DESC,observed_at DESC,assertion_id DESC;
CREATE VIEW edopsys_observability.v_governance_timeline AS
SELECT repository,observed_at occurred_at,'ASSERTION' event_kind,assertion_id event_id,jsonb_build_object('subject',subject,'predicate',predicate,'status',status) details FROM edopsys_observability.governance_status_assertions
UNION ALL SELECT repository,observed_at,'SUPERSESSION',receipt_id,jsonb_build_object('superseded',superseded_assertion_id,'superseding',superseding_assertion_id) FROM edopsys_observability.governance_supersession_receipts
UNION ALL SELECT repository,detected_at,'DRIFT',finding_id,jsonb_build_object('type',finding_type,'severity',severity,'resolution',resolution_status) FROM edopsys_observability.governance_drift_findings;
CREATE VIEW edopsys_observability.v_repository_health AS
WITH b AS(SELECT DISTINCT ON(repository)* FROM edopsys_observability.repository_baseline ORDER BY repository,observed_at DESC,id DESC),bu AS(SELECT DISTINCT ON(repository) repository,health FROM edopsys_observability.v_build_health WHERE canonical ORDER BY repository,observed_at DESC),ci AS(SELECT DISTINCT ON(repository) repository,ci_health FROM edopsys_observability.v_ci_health ORDER BY repository,observed_at DESC),i AS(SELECT * FROM edopsys_observability.v_integrity_health),rv AS(SELECT * FROM edopsys_observability.v_review_health),a AS(SELECT * FROM edopsys_observability.v_authority_health),d AS(SELECT * FROM edopsys_observability.v_governance_drift)
SELECT b.repository,b.canonical_head,b.latest_merged_build,COALESCE(bu.health,'UNKNOWN') build_status,COALESCE(ci.ci_health,'NO_RUN') ci_status,COALESCE(i.health,'UNKNOWN') integrity_status,COALESCE(rv.health,'UNKNOWN') review_status,COALESCE(a.health,'UNKNOWN') authority_status,COALESCE(d.health,'HEALTHY') drift_status,
(COALESCE(rv.p0,0)+COALESCE(rv.p1,0)+CASE WHEN COALESCE(i.health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END+CASE WHEN COALESCE(ci.ci_health,'NO_RUN')='FAIL' THEN 1 ELSE 0 END+CASE WHEN COALESCE(a.health,'UNKNOWN')='BLOCKED' THEN 1 ELSE 0 END+CASE WHEN COALESCE(d.health,'HEALTHY')='BLOCKED' THEN 1 ELSE 0 END) blocking_reason_count,
CASE WHEN COALESCE(bu.health,'UNKNOWN')='BLOCKED' OR COALESCE(i.health,'UNKNOWN')='BLOCKED' OR COALESCE(rv.health,'UNKNOWN')='BLOCKED' OR COALESCE(a.health,'UNKNOWN')='BLOCKED' OR COALESCE(d.health,'HEALTHY')='BLOCKED' OR COALESCE(ci.ci_health,'NO_RUN')='FAIL' THEN 'BLOCKED'
WHEN COALESCE(bu.health,'UNKNOWN')='UNKNOWN' OR COALESCE(i.health,'UNKNOWN')='UNKNOWN' OR COALESCE(rv.health,'UNKNOWN')='UNKNOWN' OR COALESCE(a.health,'UNKNOWN')='UNKNOWN' OR COALESCE(ci.ci_health,'NO_RUN') IN('NO_RUN','IN_PROGRESS') THEN 'UNKNOWN'
WHEN COALESCE(bu.health,'UNKNOWN')='DEGRADED' OR COALESCE(rv.health,'UNKNOWN')='DEGRADED' OR COALESCE(a.health,'UNKNOWN')='DEGRADED' OR COALESCE(d.health,'HEALTHY')='DEGRADED' OR COALESCE(ci.ci_health,'NO_RUN')='STALE_HEAD' THEN 'DEGRADED' ELSE 'HEALTHY' END overall_health
FROM b LEFT JOIN bu USING(repository) LEFT JOIN ci USING(repository) LEFT JOIN i USING(repository) LEFT JOIN rv USING(repository) LEFT JOIN a USING(repository) LEFT JOIN d USING(repository);
CREATE VIEW edopsys_observability.v_dashboard_summary_json AS SELECT repository,jsonb_build_object('overall_health',overall_health,'canonical_head',canonical_head,'latest_build',latest_merged_build,'blocking_reason_count',blocking_reason_count,'gates',jsonb_build_object('build',build_status,'ci',ci_status,'integrity',integrity_status,'review',review_status,'authority',authority_status,'drift',drift_status),'timeline',COALESCE((SELECT jsonb_agg(jsonb_build_object('at',occurred_at,'kind',event_kind,'id',event_id,'details',details) ORDER BY occurred_at) FROM edopsys_observability.v_governance_timeline t WHERE t.repository=r.repository),'[]'::jsonb)) dashboard FROM edopsys_observability.v_repository_health r;
COMMIT;
