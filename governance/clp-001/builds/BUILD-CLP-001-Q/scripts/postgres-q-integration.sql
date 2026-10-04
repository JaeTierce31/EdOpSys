\set ON_ERROR_STOP on
\i migrations/001_clp001_q.sql

-- aggregate-version uniqueness
INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload)
VALUES('ci-e1','ci-a','agg-ci',1,'Test','S','h1','{}');
DO $$ BEGIN
  BEGIN
    INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload)
    VALUES('ci-e2','ci-a','agg-ci',1,'Test','S','h2','{}');
    RAISE EXCEPTION 'expected aggregate version uniqueness failure';
  EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;

-- idempotency uniqueness
INSERT INTO clp_commands(command_id,request_hash,result_event_id) VALUES('ci-cmd','r1','ci-e1');
DO $$ BEGIN
  BEGIN
    INSERT INTO clp_commands(command_id,request_hash,result_event_id) VALUES('ci-cmd','r2','ci-e1');
    RAISE EXCEPTION 'expected idempotency uniqueness failure';
  EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;

-- independent correlations may each begin at ordinal one
INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload)
VALUES('ci-ca','corr-a','agg-a',1,'Test','S','ha','{}'),('ci-cb','corr-b','agg-b',1,'Test','S','hb','{}');
INSERT INTO clp_chain(event_id,correlation_id,ordinal,event_hash,previous_chain_hash,chain_hash)
VALUES('ci-ca','corr-a',1,'ha',NULL,'cha'),('ci-cb','corr-b',1,'hb',NULL,'chb');

-- append-only trigger
DO $$ BEGIN
  BEGIN
    UPDATE clp_events SET decision='MUTATED' WHERE event_id='ci-e1';
    RAISE EXCEPTION 'expected append-only mutation failure';
  EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
END $$;

-- failed transactional bundle leaves no residue
DO $$ BEGIN
  BEGIN
    INSERT INTO clp_commands(command_id,request_hash,result_event_id) VALUES('ci-rollback','rr','ci-bad');
    INSERT INTO clp_versions(version_ref,canonical_hash,payload) VALUES('ci-version','hv','{}');
    INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload)
      VALUES('ci-bad','ci-a','agg-ci',1,'Test','S','bad','{}');
  EXCEPTION WHEN unique_violation THEN NULL; END;
  IF EXISTS(SELECT 1 FROM clp_commands WHERE command_id='ci-rollback') THEN RAISE EXCEPTION 'rollback command residue'; END IF;
  IF EXISTS(SELECT 1 FROM clp_versions WHERE version_ref='ci-version') THEN RAISE EXCEPTION 'rollback version residue'; END IF;
END $$;

SELECT 'BUILD-CLP-001-Q postgres integration PASS' AS result;
