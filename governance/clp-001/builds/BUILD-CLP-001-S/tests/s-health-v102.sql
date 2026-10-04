BEGIN;
SET search_path=edopsys_observability,public;
CREATE OR REPLACE FUNCTION pg_temp.assert_eq(actual text,expected text,label text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION '% expected %, got %',label,expected,actual; END IF;END$$;
CREATE OR REPLACE FUNCTION pg_temp.obs(repo text,id text,typ text) RETURNS void LANGUAGE plpgsql AS $$BEGIN INSERT INTO obs_observations VALUES(id,repo,typ,id,NULL,clock_timestamp(),'sha256:'||repeat('a',64),'{}');END$$;
CREATE OR REPLACE FUNCTION pg_temp.good(repo text,prefix text) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 PERFORM pg_temp.obs(repo,prefix||'-base','REPOSITORY_HEAD');INSERT INTO repository_baseline VALUES(prefix||'-base',repo,'head','BUILD-X','g0','g1','p','q','r',clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-build','BUILD_RECEIPT');INSERT INTO build_status VALUES(prefix||'-build',repo,'BUILD-X',true,'impl','merge','parent',1,1,'success','APPROVED',0,true,clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-ci','CI_RUN');INSERT INTO ci_runs VALUES(prefix||'-ci',repo,'BUILD-X',1,'impl','impl','completed','success','success',clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-rev','PR_REVIEW');INSERT INTO pr_reviews(id,repository,pr_number,reviewed_sha,expected_head_sha,reviewer,severity,finding_status,resolved,superseded,merge_blocking,observed_at,finding_key) VALUES(prefix||'-rev',repo,1,'impl','impl','reviewer',NULL,'APPROVED',true,false,false,clock_timestamp(),'__summary__');
 PERFORM pg_temp.obs(repo,prefix||'-int','ARTIFACT_INTEGRITY');INSERT INTO artifact_integrity VALUES(prefix||'-int',repo,'required',true,'PASS','x','x',1,1,clock_timestamp());INSERT INTO artifact_integrity_scope VALUES(prefix||'-int',repo,'BUILD-X',clock_timestamp());
 PERFORM pg_temp.obs(repo,prefix||'-auth','AUTHORITY_RECORD');INSERT INTO authority_records VALUES(prefix||'-auth',repo,'AUTH','v1','SC-0','J','h','CURRENT',false,clock_timestamp());
 INSERT INTO governance_status_assertions VALUES(prefix||'-g0',repo,'G0','designation_status','"DESIGNATED"','g0.json','sha',clock_timestamp(),NULL,NULL,2,'CURRENT');
 INSERT INTO governance_drift_findings VALUES(prefix||'-drift',repo,'ASSESSMENT','repository','P3','RESOLVED',NULL,clock_timestamp());
END$$;

-- T15: same build ID advances to a new implementation SHA. Old successful CI MUST NOT authorize it.
SELECT pg_temp.good('t15','t15');
SELECT pg_temp.obs('t15','t15-build-new','BUILD_RECEIPT');
INSERT INTO build_status VALUES('t15-build-new','t15','BUILD-X',true,'impl-new','merge-new','parent',1,1,'success','APPROVED',0,true,clock_timestamp()+interval '2 seconds');
SELECT pg_temp.obs('t15','t15-review-new','PR_REVIEW');
INSERT INTO pr_reviews(id,repository,pr_number,reviewed_sha,expected_head_sha,reviewer,severity,finding_status,resolved,superseded,merge_blocking,observed_at,finding_key) VALUES('t15-review-new','t15',2,'impl-new','impl-new','reviewer',NULL,'APPROVED',true,false,false,clock_timestamp()+interval '2 seconds','__summary__');
SELECT pg_temp.assert_eq((SELECT ci_status FROM v_repository_health WHERE repository='t15'),'NO_RUN','T15-ci-implementation-binding');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t15'),'UNKNOWN','T15-fail-closed');

-- T16: caller-supplied PASS cannot override contradictory or incomplete measurements.
SELECT pg_temp.good('t16','t16');
SELECT pg_temp.obs('t16','t16-bad-integrity','ARTIFACT_INTEGRITY');
INSERT INTO artifact_integrity VALUES('t16-bad-integrity','t16','bad-pass',true,'PASS','expected','observed',10,9,clock_timestamp()+interval '1 second');
INSERT INTO artifact_integrity_scope VALUES('t16-bad-integrity','t16','BUILD-X',clock_timestamp()+interval '1 second');
SELECT pg_temp.assert_eq((SELECT integrity_status FROM v_repository_health WHERE repository='t16'),'BLOCKED','T16-measurement-derived-integrity');
SELECT pg_temp.assert_eq((SELECT overall_health FROM v_repository_health WHERE repository='t16'),'BLOCKED','T16-fail-closed');

SELECT 'S_T15_T16_EXACT_EVIDENCE_BINDING_PASS';
ROLLBACK;
