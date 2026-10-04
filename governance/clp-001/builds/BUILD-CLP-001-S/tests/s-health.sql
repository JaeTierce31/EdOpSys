BEGIN;
SET search_path=edopsys_observability,public;
CREATE OR REPLACE FUNCTION pg_temp.assert_eq(actual text,expected text,label text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION '% expected %, got %',label,expected,actual; END IF;END$$;
CREATE OR REPLACE FUNCTION pg_temp.obs(repo text,id text,typ text) RETURNS void LANGUAGE plpgsql AS $$BEGIN INSERT INTO obs_observations VALUES(id,repo,typ,id,NULL,clock_timestamp(),'sha256:'||repeat('a',64),'{}');END$$;
CREATE OR REPLACE FUNCTION pg_temp.base(repo text,id text) RETURNS void LANGUAGE plpgsql AS $$BEGIN PERFORM pg_temp.obs(repo,id,'REPOSITORY_HEAD');INSERT INTO repository_baseline VALUES(id,repo,'head','BUILD-X','g0','g1','p','q','r',clock_timestamp());END$$;
CREATE OR REPLACE FUNCTION pg_temp.good(repo text,prefix text) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 PERFORM pg_temp.base(repo,prefix||'-b');
 PERFORM pg_temp.obs(repo,prefix||'-build','BUILD_RECEIPT');INSERT INTO build_status VALUES(prefix||'-build',repo,'BUILD-X',true,'impl','merge','parent',1,1,'success','APPROVED',0,true,clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-ci','CI_RUN');INSERT INTO ci_runs VALUES(prefix||'-ci',repo,'BUILD-X',1,'impl','impl','completed','success','success',clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-rev','PR_REVIEW');INSERT INTO pr_reviews VALUES(prefix||'-rev',repo,1,'impl','impl','reviewer',NULL,'APPROVED',true,false,false,clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-int','ARTIFACT_INTEGRITY');INSERT INTO artifact_integrity VALUES(prefix||'-int',repo,'required',true,'PASS','x','x',1,1,clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-auth','AUTHORITY_RECORD');INSERT INTO authority_records VALUES(prefix||'-auth',repo,'AUTH','v1','SC-0','J','h','CURRENT',false,clock_timestamp());
 INSERT INTO governance_status_assertions VALUES(prefix||'-g0',repo,'G0','designation_status','"DESIGNATED"','g0.json','sha',clock_timestamp(),NULL,NULL,2,'CURRENT');
END$$;

-- T1 unresolved P1 -> BLOCKED
SELECT pg_temp.good('t1','t1'); SELECT pg_temp.obs('t1','t1-p1','PR_REVIEW');
INSERT INTO pr_reviews VALUES('t1-p1','t1',1,'impl','impl','reviewer','P1','OPEN',false,false,true,clock_timestamp());
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t1'),'BLOCKED','T1');

-- T2 resolved P1 no longer blocks
SELECT pg_temp.good('t2','t2'); SELECT pg_temp.obs('t2','t2-p1','PR_REVIEW');
INSERT INTO pr_reviews VALUES('t2-p1','t2',1,'impl','impl','reviewer','P1','RESOLVED',true,false,false,clock_timestamp());
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t2'),'HEALTHY','T2');

-- T3 missing required artifact -> BLOCKED
SELECT pg_temp.good('t3','t3'); SELECT pg_temp.obs('t3','t3-miss','ARTIFACT_INTEGRITY');
INSERT INTO artifact_integrity VALUES('t3-miss','t3','missing',true,'MISSING','x',NULL,1,NULL,clock_timestamp());
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t3'),'BLOCKED','T3');

-- T4 hash mismatch -> BLOCKED
SELECT pg_temp.good('t4','t4'); SELECT pg_temp.obs('t4','t4-hash','ARTIFACT_INTEGRITY');
INSERT INTO artifact_integrity VALUES('t4-hash','t4','bad',true,'HASH_MISMATCH','x','y',1,1,clock_timestamp());
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t4'),'BLOCKED','T4');

-- T5 exact-head CI -> PASS
SELECT pg_temp.good('t5','t5');
SELECT pg_temp.assert_eq((SELECT ci_health FROM v_ci_health WHERE repository='t5'),'PASS','T5');

-- T6 stale-head CI -> STALE_HEAD and DEGRADED
SELECT pg_temp.good('t6','t6'); SELECT pg_temp.obs('t6','t6-ci2','CI_RUN');
INSERT INTO ci_runs VALUES('t6-ci2','t6','BUILD-X',2,'old','new','completed','success','success',clock_timestamp()+interval '1 second');
SELECT pg_temp.assert_eq((SELECT ci_health FROM v_ci_health WHERE repository='t6'),'STALE_HEAD','T6-ci');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t6'),'DEGRADED','T6-health');

-- T7 stale G0 superseded -> current designation and no block
SELECT pg_temp.good('t7','t7');
INSERT INTO governance_status_assertions VALUES('t7-old','t7','G0','designation_status','"BLOCKED"','old.json',NULL,clock_timestamp()-interval '2 sec',clock_timestamp()-interval '1 sec','t7-g0',1,'SUPERSEDED');
INSERT INTO governance_supersession_receipts VALUES('t7-rec','t7','t7-old','t7-g0','later authority supersedes earlier status','sha256:'||repeat('b',64),clock_timestamp());
INSERT INTO governance_drift_findings VALUES('t7-drift','t7','STALE_STATUS','G0','P2','SUPERSEDED','t7-rec',clock_timestamp());
SELECT pg_temp.assert_eq((SELECT value#>>'{}' FROM v_governance_assertion_current WHERE repository='t7' AND subject='G0'),'DESIGNATED','T7-current');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t7'),'HEALTHY','T7-health');

-- T8 missing required observations -> UNKNOWN
SELECT pg_temp.base('t8','t8-b');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t8'),'UNKNOWN','T8');

-- T9 freshness review due -> DEGRADED
SELECT pg_temp.good('t9','t9'); SELECT pg_temp.obs('t9','t9-auth2','AUTHORITY_RECORD');
INSERT INTO authority_records VALUES('t9-auth2','t9','AUTH2','v1','SC-0','J','h','FRESHNESS_REVIEW_DUE',false,clock_timestamp()+interval '1 second');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t9'),'DEGRADED','T9');

-- T10 append-only rejects observability and CLP mutation
DO $$BEGIN BEGIN UPDATE repository_baseline SET canonical_head='mutated' WHERE repository='t1'; RAISE EXCEPTION 'T10 observability mutation unexpectedly succeeded'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
BEGIN INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload) VALUES('t10-event','t10','a',1,'Test','REPORTED','h','{}'); UPDATE clp_events SET event_type='mutated' WHERE event_id='t10-event'; RAISE EXCEPTION 'T10 CLP mutation unexpectedly succeeded'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;END$$;

SELECT 'S_T1_T10_PASS';
ROLLBACK;
