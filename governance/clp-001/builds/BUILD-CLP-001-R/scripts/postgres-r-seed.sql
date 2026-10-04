\set ON_ERROR_STOP on
INSERT INTO clp_commands(command_id,request_hash,result_event_id) VALUES('cmd-r-seed','sha256:req-r','evt-r-seed');
INSERT INTO clp_versions(version_ref,canonical_hash,payload) VALUES('CLP-001-TRANSITIONS@1.0.0','sha256:version-r','{"policy_id":"CLP-001-TRANSITIONS","version":"1.0.0"}'::jsonb);
INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload)
VALUES(
'evt-r-seed','corr-r-seed','CASE-R-SEED',1,'IssueIntakeStructured','INTAKE_STRUCTURED',
'sha256:076dcd5aa3584022fa3c6c6f1a6159f027b84c3d5dafa46a55fd250fe8dda3a1',
'{"event_id":"evt-r-seed","event_type":"IssueIntakeStructured","occurred_at":"2026-10-04T00:00:01.000Z","actor_id":"SYSTEM","actor_type":"SYSTEM","aggregate_id":"CASE-R-SEED","aggregate_version":1,"causation_event_id":null,"correlation_id":"corr-r-seed","input_refs":[],"output_refs":[],"source_refs":[],"policy_refs":[],"evidence_refs":["EVID-R-SEED"],"decision":"INTAKE_STRUCTURED","reason_code":null,"event_hash":"sha256:076dcd5aa3584022fa3c6c6f1a6159f027b84c3d5dafa46a55fd250fe8dda3a1"}'::jsonb
);
INSERT INTO clp_case_state_history(correlation_id,aggregate_id,aggregate_version,source_event_id,state,state_hash)
VALUES('corr-r-seed','CASE-R-SEED',1,'evt-r-seed','INTAKE_STRUCTURED','sha256:state-r');
INSERT INTO clp_certifications(certification_id,certification_hash,payload,correlation_id)
VALUES('CERT-R-SEED','sha256:cert-r','{"certification_id":"CERT-R-SEED","status":"PASS"}'::jsonb,'corr-r-seed');

INSERT INTO clp_evidence(evidence_id,correlation_id,content_hash,payload)
VALUES(
'EVID-R-SEED','corr-r-seed','sha256:dbc82d401c10273ce51226fa5851ead568ccc4fe99752ef18e1b323b4a11081e',
'{"evidence_id":"EVID-R-SEED","evidence_class":"E1","evidence_type":"STRUCTURED_INTAKE","content":{"issue_class":"TOILET_FILL_VALVE_FAILURE","synthetic":true},"parent_evidence_ids":[],"content_hash":"sha256:dbc82d401c10273ce51226fa5851ead568ccc4fe99752ef18e1b323b4a11081e","created_at":"2026-10-04T00:00:00.000Z","privacy_class":"INTERNAL"}'::jsonb
);
INSERT INTO clp_chain(event_id,correlation_id,ordinal,event_hash,previous_chain_hash,chain_hash)
VALUES('evt-r-seed','corr-r-seed',1,'sha256:076dcd5aa3584022fa3c6c6f1a6159f027b84c3d5dafa46a55fd250fe8dda3a1',NULL,'sha256:f5506a8a87cff79044409b9517fd5f5a7fce9d2b0fdeb61ccafec9f749fc91ae');
INSERT INTO clp_lineage(lineage_id,correlation_id,parents,payload)
VALUES('EVID-R-SEED','corr-r-seed','[]'::jsonb,'{"id":"EVID-R-SEED","parents":[]}'::jsonb);
