BEGIN;
SET search_path=edopsys_observability,public;
CREATE OR REPLACE FUNCTION pg_temp.assert_eq(actual text,expected text,label text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION '% expected %, got %',label,expected,actual; END IF;END$$;
CREATE OR REPLACE FUNCTION pg_temp.assert_gt0(actual bigint,label text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF actual IS NULL OR actual<=0 THEN RAISE EXCEPTION '% expected >0, got %',label,actual; END IF;END$$;
CREATE OR REPLACE FUNCTION pg_temp.obs(repo text,id text,typ text) RETURNS void LANGUAGE plpgsql AS $$BEGIN INSERT INTO obs_observations VALUES(id,repo,typ,id,NULL,clock_timestamp(),'sha256:'||repeat('a',64),'{}');END$$;
CREATE OR REPLACE FUNCTION pg_temp.base(repo text,id text) RETURNS void LANGUAGE plpgsql AS $$BEGIN PERFORM pg_temp.obs(repo,id,'REPOSITORY_HEAD');INSERT INTO repository_baseline VALUES(id,repo,'head','BUILD-X','g0','g1','p','q','r',clock_timestamp());END$$;
CREATE OR REPLACE FUNCTION pg_temp.core(repo text,prefix text) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 PERFORM pg_temp.base(repo,prefix||'-b');
 PERFORM pg_temp.obs(repo,prefix||'-build','BUILD_RECEIPT');INSERT INTO build_status VALUES(prefix||'-build',repo,'BUILD-X',true,'impl','merge','parent',1,1,'success','APPROVED',0,true,clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-ci','CI_RUN');INSERT INTO ci_runs VALUES(prefix||'-ci',repo,'BUILD-X',1,'impl','impl','completed','success','success',clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-rev','PR_REVIEW');INSERT INTO pr_reviews(id,repository,pr_number,reviewed_sha,expected_head_sha,reviewer,severity,finding_status,resolved,superseded,merge_blocking,observed_at,finding_key) VALUES(prefix||'-rev',repo,1,'impl','impl','reviewer',NULL,'APPROVED',true,false,false,clock_timestamp(),'__summary__');
 PERFORM pg_temp.obs(repo,prefix||'-int','ARTIFACT_INTEGRITY');INSERT INTO artifact_integrity VALUES(prefix||'-int',repo,'required',true,'PASS','x','x',1,1,clock_timestamp());INSERT INTO artifact_integrity_scope VALUES(prefix||'-int',repo,'BUILD-X',clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-auth','AUTHORITY_RECORD');INSERT INTO authority_records VALUES(prefix||'-auth',repo,'AUTH','v1','SC-0','J','h','CURRENT',false,clock_timestamp());
 INSERT INTO governance_status_assertions VALUES(prefix||'-g0',repo,'G0','designation_status','"DESIGNATED"','g0.json','sha',clock_timestamp(),NULL,NULL,2,'CURRENT');
END$$;
CREATE OR REPLACE FUNCTION pg_temp.good(repo text,prefix text) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 PERFORM pg_temp.core(repo,prefix);
 INSERT INTO governance_drift_findings VALUES(prefix||'-drift',repo,'ASSESSMENT','repository','P3','RESOLVED',NULL,clock_timestamp());
END$$;

-- T1 unresolved P1 -> BLOCKED; blocked canonical build contributes blocker count.
SELECT pg_temp.good('t1','t1'); SELECT pg_temp.obs('t1','t1-p1','PR_REVIEW');
INSERT INTO pr_reviews(id,repository,pr_number,reviewed_sha,expected_head_sha,reviewer,severity,finding_status,resolved,superseded,merge_blocking,observed_at,finding_key) VALUES('t1-p1','t1',1,'impl','impl','reviewer','P1','OPEN',false,false,true,clock_timestamp()+interval '1 second','F1');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t1'),'BLOCKED','T1-P1');
SELECT pg_temp.good('t1b','t1b'); SELECT pg_temp.obs('t1b','t1b-build2','BUILD_RECEIPT');
INSERT INTO build_status VALUES('t1b-build2','t1b','BUILD-X',false,'impl2',NULL,'parent',1,1,'success','APPROVED',0,true,clock_timestamp()+interval '1 second');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t1b'),'BLOCKED','T1-build');
SELECT pg_temp.assert_gt0((SELECT blocking_reason_count FROM v_repository_health WHERE repository='t1b'),'T1-build-blocker-count');

-- T2 append-only later resolution of same logical finding removes block.
SELECT pg_temp.good('t2','t2'); SELECT pg_temp.obs('t2','t2-p1-open','PR_REVIEW');
INSERT INTO pr_reviews(id,repository,pr_number,reviewed_sha,expected_head_sha,reviewer,severity,finding_status,resolved,superseded,merge_blocking,observed_at,finding_key) VALUES('t2-p1-open','t2',1,'impl','impl','reviewer','P1','OPEN',false,false,true,clock_timestamp(),'F1');
SELECT pg_sleep(0.01); SELECT pg_temp.obs('t2','t2-p1-resolved','PR_REVIEW');
INSERT INTO pr_reviews(id,repository,pr_number,reviewed_sha,expected_head_sha,reviewer,severity,finding_status,resolved,superseded,merge_blocking,observed_at,finding_key) VALUES('t2-p1-resolved','t2',1,'impl','impl','reviewer','P1','RESOLVED',true,false,false,clock_timestamp(),'F1');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t2'),'HEALTHY','T2');

-- T3 missing required artifact -> BLOCKED.
SELECT pg_temp.good('t3','t3'); SELECT pg_temp.obs('t3','t3-miss','ARTIFACT_INTEGRITY');
INSERT INTO artifact_integrity VALUES('t3-miss','t3','missing',true,'MISSING','x',NULL,1,NULL,clock_timestamp());INSERT INTO artifact_integrity_scope VALUES('t3-miss','t3','BUILD-X',clock_timestamp());
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t3'),'BLOCKED','T3');

-- T4 hash mismatch -> BLOCKED.
SELECT pg_temp.good('t4','t4'); SELECT pg_temp.obs('t4','t4-hash','ARTIFACT_INTEGRITY');
INSERT INTO artifact_integrity VALUES('t4-hash','t4','bad',true,'HASH_MISMATCH','x','y',1,1,clock_timestamp());INSERT INTO artifact_integrity_scope VALUES('t4-hash','t4','BUILD-X',clock_timestamp());
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t4'),'BLOCKED','T4');

-- T5 canonical exact-head CI remains PASS despite newer non-canonical failure.
SELECT pg_temp.good('t5','t5'); SELECT pg_temp.obs('t5','t5-ci-y','CI_RUN');
INSERT INTO ci_runs VALUES('t5-ci-y','t5','BUILD-Y',2,'bad','bad','completed','failure','failure',clock_timestamp()+interval '2 seconds');
SELECT pg_temp.assert_eq((SELECT ci_health FROM v_ci_health WHERE repository='t5' AND build_id='BUILD-X'),'PASS','T5-ci');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t5'),'HEALTHY','T5-health');

-- T6 stale-head CI on canonical build -> STALE_HEAD / DEGRADED.
SELECT pg_temp.good('t6','t6'); SELECT pg_temp.obs('t6','t6-ci2','CI_RUN');
INSERT INTO ci_runs VALUES('t6-ci2','t6','BUILD-X',2,'old','new','completed','success','success',clock_timestamp()+interval '1 second');
SELECT pg_temp.assert_eq((SELECT ci_health FROM v_ci_health WHERE repository='t6' AND build_id='BUILD-X'),'STALE_HEAD','T6-ci');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t6'),'DEGRADED','T6-health');

-- T7 stale historical G0 superseded -> current designation and no block.
SELECT pg_temp.good('t7','t7');
INSERT INTO governance_status_assertions VALUES('t7-old','t7','G0','designation_status','"BLOCKED"','old.json',NULL,clock_timestamp()-interval '2 sec',clock_timestamp()-interval '1 sec','t7-g0',1,'SUPERSEDED');
INSERT INTO governance_supersession_receipts VALUES('t7-rec','t7','t7-old','t7-g0','later authority supersedes earlier status','sha256:'||repeat('b',64),clock_timestamp());
INSERT INTO governance_drift_findings VALUES('t7-drift2','t7','STALE_STATUS','G0','P2','SUPERSEDED','t7-rec',clock_timestamp());
SELECT pg_temp.assert_eq((SELECT value#>>'{}' FROM v_governance_assertion_current WHERE repository='t7' AND subject='G0'),'DESIGNATED','T7-current');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t7'),'HEALTHY','T7-health');

-- T8 missing required observations -> UNKNOWN, including missing drift assessment.
SELECT pg_temp.base('t8','t8-b');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t8'),'UNKNOWN','T8-missing-many');
SELECT pg_temp.core('t8d','t8d');
SELECT pg_temp.assert_eq((SELECT drift_status FROM v_repository_health WHERE repository='t8d'),'UNKNOWN','T8-drift-gate');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t8d'),'UNKNOWN','T8-drift-overall');

-- T9 freshness review due -> DEGRADED; blocking authority conflict outranks UNKNOWN.
SELECT pg_temp.good('t9','t9'); SELECT pg_temp.obs('t9','t9-auth2','AUTHORITY_RECORD');
INSERT INTO authority_records VALUES('t9-auth2','t9','AUTH2','v1','SC-0','J','h','FRESHNESS_REVIEW_DUE',false,clock_timestamp()+interval '1 second');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t9'),'DEGRADED','T9-freshness');
SELECT pg_temp.good('t9c','t9c'); SELECT pg_temp.obs('t9c','t9c-unknown','AUTHORITY_RECORD'); SELECT pg_temp.obs('t9c','t9c-conflict','AUTHORITY_RECORD');
INSERT INTO authority_records VALUES('t9c-unknown','t9c','AUTH-U','v1','SC-0','J','h','UNKNOWN',false,clock_timestamp()),('t9c-conflict','t9c','AUTH-C','v1','SC-0','J','h','CONFLICT',true,clock_timestamp()+interval '1 second');
SELECT pg_temp.assert_eq((SELECT authority_status FROM v_repository_health WHERE repository='t9c'),'BLOCKED','T9-conflict-gate');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t9c'),'BLOCKED','T9-conflict-overall');

-- T10 append-only rejects observability and CLP mutation.
DO $$BEGIN BEGIN UPDATE repository_baseline SET canonical_head='mutated' WHERE repository='t1'; RAISE EXCEPTION 'T10 observability mutation unexpectedly succeeded'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
BEGIN INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload) VALUES('t10-event','t10','a',1,'Test','REPORTED','h','{}'); UPDATE clp_events SET event_type='mutated' WHERE event_id='t10-event'; RAISE EXCEPTION 'T10 CLP mutation unexpectedly succeeded'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;END$$;

-- T11 baseline advances without build observation -> UNKNOWN, never stale historical build health.
SELECT pg_temp.good('t11','t11'); SELECT pg_temp.obs('t11','t11-base-y','REPOSITORY_HEAD');
INSERT INTO repository_baseline VALUES('t11-base-y','t11','head-y','BUILD-Y','g0','g1','p','q','r',clock_timestamp()+interval '2 seconds');
SELECT pg_temp.assert_eq((SELECT build_status FROM v_repository_health WHERE repository='t11'),'UNKNOWN','T11-build-binding');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t11'),'UNKNOWN','T11-overall');

-- T12 latest observation for one logical authority clears historical conflict.
SELECT pg_temp.good('t12','t12'); SELECT pg_temp.obs('t12','t12-auth-conflict','AUTHORITY_RECORD');
INSERT INTO authority_records VALUES('t12-auth-conflict','t12','AUTH','v2','SC-0','J','h2','CONFLICT',true,clock_timestamp()+interval '1 second');
SELECT pg_temp.assert_eq((SELECT authority_status FROM v_repository_health WHERE repository='t12'),'BLOCKED','T12-conflict');
SELECT pg_temp.obs('t12','t12-auth-current','AUTHORITY_RECORD');
INSERT INTO authority_records VALUES('t12-auth-current','t12','AUTH','v3','SC-0','J','h3','CURRENT',false,clock_timestamp()+interval '2 seconds');
SELECT pg_temp.assert_eq((SELECT authority_status FROM v_repository_health WHERE repository='t12'),'HEALTHY','T12-latest-authority');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t12'),'HEALTHY','T12-overall');

-- T13 old review cannot authorize a newly active build head.
SELECT pg_temp.good('t13','t13'); SELECT pg_temp.obs('t13','t13-base-y','REPOSITORY_HEAD'); SELECT pg_temp.obs('t13','t13-build-y','BUILD_RECEIPT'); SELECT pg_temp.obs('t13','t13-ci-y','CI_RUN'); SELECT pg_temp.obs('t13','t13-int-y','ARTIFACT_INTEGRITY');
INSERT INTO repository_baseline VALUES('t13-base-y','t13','head-y','BUILD-Y','g0','g1','p','q','r',clock_timestamp()+interval '2 seconds');
INSERT INTO build_status VALUES('t13-build-y','t13','BUILD-Y',true,'impl-y','merge-y','parent',1,1,'success','APPROVED',0,true,clock_timestamp()+interval '2 seconds');
INSERT INTO ci_runs VALUES('t13-ci-y','t13','BUILD-Y',2,'impl-y','impl-y','completed','success','success',clock_timestamp()+interval '2 seconds');
INSERT INTO artifact_integrity VALUES('t13-int-y','t13','required-y',true,'PASS','y','y',1,1,clock_timestamp()+interval '2 seconds');INSERT INTO artifact_integrity_scope VALUES('t13-int-y','t13','BUILD-Y',clock_timestamp()+interval '2 seconds');
SELECT pg_temp.assert_eq((SELECT review_status FROM v_repository_health WHERE repository='t13'),'UNKNOWN','T13-review-binding');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t13'),'UNKNOWN','T13-overall');

-- T14 old integrity cannot authorize a newly active build.
SELECT pg_temp.good('t14','t14'); SELECT pg_temp.obs('t14','t14-base-y','REPOSITORY_HEAD'); SELECT pg_temp.obs('t14','t14-build-y','BUILD_RECEIPT'); SELECT pg_temp.obs('t14','t14-ci-y','CI_RUN'); SELECT pg_temp.obs('t14','t14-rev-y','PR_REVIEW');
INSERT INTO repository_baseline VALUES('t14-base-y','t14','head-y','BUILD-Y','g0','g1','p','q','r',clock_timestamp()+interval '2 seconds');
INSERT INTO build_status VALUES('t14-build-y','t14','BUILD-Y',true,'impl-y','merge-y','parent',1,1,'success','APPROVED',0,true,clock_timestamp()+interval '2 seconds');
INSERT INTO ci_runs VALUES('t14-ci-y','t14','BUILD-Y',2,'impl-y','impl-y','completed','success','success',clock_timestamp()+interval '2 seconds');
INSERT INTO pr_reviews(id,repository,pr_number,reviewed_sha,expected_head_sha,reviewer,severity,finding_status,resolved,superseded,merge_blocking,observed_at,finding_key) VALUES('t14-rev-y','t14',2,'impl-y','impl-y','reviewer',NULL,'APPROVED',true,false,false,clock_timestamp()+interval '2 seconds','__summary__');
SELECT pg_temp.assert_eq((SELECT integrity_status FROM v_repository_health WHERE repository='t14'),'UNKNOWN','T14-integrity-binding');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t14'),'UNKNOWN','T14-overall');

SELECT 'S_T1_T14_CANONICAL_BINDING_PASS';
ROLLBACK;
