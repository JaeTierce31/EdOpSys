\set ON_ERROR_STOP on
INSERT INTO clp_commands(command_id,request_hash,result_event_id) VALUES('cmd-r-seed','sha256:req-r','evt-r-seed');
INSERT INTO clp_versions(version_ref,canonical_hash,payload) VALUES('CLP-001-TRANSITIONS@1.0.0','sha256:version-r','{"policy_id":"CLP-001-TRANSITIONS","version":"1.0.0"}'::jsonb);
INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload)
VALUES('evt-r-seed','corr-r-seed','CASE-R-SEED',1,'IssueIntakeStructured','INTAKE_STRUCTURED','sha256:event-r','{"event_id":"evt-r-seed","correlation_id":"corr-r-seed","aggregate_id":"CASE-R-SEED","aggregate_version":1,"event_type":"IssueIntakeStructured","decision":"INTAKE_STRUCTURED"}'::jsonb);
INSERT INTO clp_case_state_history(correlation_id,aggregate_id,aggregate_version,source_event_id,state,state_hash)
VALUES('corr-r-seed','CASE-R-SEED',1,'evt-r-seed','INTAKE_STRUCTURED','sha256:state-r');
INSERT INTO clp_certifications(certification_id,certification_hash,payload,correlation_id)
VALUES('CERT-R-SEED','sha256:cert-r','{"certification_id":"CERT-R-SEED","status":"PASS"}'::jsonb,'corr-r-seed');
INSERT INTO clp_evidence(evidence_id,correlation_id,content_hash,payload)
VALUES('EVID-R-SEED','corr-r-seed','sha256:evidence-r','{"evidence_id":"EVID-R-SEED","kind":"TEST_EVIDENCE","content_hash":"sha256:evidence-r"}'::jsonb);
INSERT INTO clp_chain(event_id,correlation_id,ordinal,event_hash,previous_chain_hash,chain_hash)
VALUES('evt-r-seed','corr-r-seed',1,'sha256:event-r',NULL,'sha256:chain-r');
INSERT INTO clp_lineage(lineage_id,correlation_id,parents,payload)
VALUES('LINEAGE-R-SEED','corr-r-seed','[]'::jsonb,'{"id":"LINEAGE-R-SEED","parents":[]}'::jsonb);
