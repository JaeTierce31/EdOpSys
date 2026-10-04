\set ON_ERROR_STOP on
-- Populate Q-era data before migration 002 to prove upgrade backfill.
INSERT INTO clp_events(event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload)
VALUES
('evt-r-legacy-1','corr-r-legacy','CASE-R-LEGACY',1,'ResidentIssueReported',NULL,'sha256:legacy-1','{"event_id":"evt-r-legacy-1","correlation_id":"corr-r-legacy","aggregate_id":"CASE-R-LEGACY","aggregate_version":1,"event_type":"ResidentIssueReported","decision":null}'::jsonb),
('evt-r-legacy-2','corr-r-legacy','CASE-R-LEGACY',2,'ResidentEvidenceAttached',NULL,'sha256:legacy-2','{"event_id":"evt-r-legacy-2","correlation_id":"corr-r-legacy","aggregate_id":"CASE-R-LEGACY","aggregate_version":2,"event_type":"ResidentEvidenceAttached","decision":null}'::jsonb),
('evt-r-legacy-3','corr-r-legacy','CASE-R-LEGACY',3,'IssueIntakeStructured','INTAKE_STRUCTURED','sha256:legacy-3','{"event_id":"evt-r-legacy-3","correlation_id":"corr-r-legacy","aggregate_id":"CASE-R-LEGACY","aggregate_version":3,"event_type":"IssueIntakeStructured","decision":"INTAKE_STRUCTURED"}'::jsonb),
('evt-r-legacy-4','corr-r-legacy','CASE-R-LEGACY',4,'AuthorityRetrieved',NULL,'sha256:legacy-4','{"event_id":"evt-r-legacy-4","correlation_id":"corr-r-legacy","aggregate_id":"CASE-R-LEGACY","aggregate_version":4,"event_type":"AuthorityRetrieved","decision":null}'::jsonb);
INSERT INTO clp_certifications(certification_id,certification_hash,payload)
VALUES('CERT-R-LEGACY','sha256:legacy-cert','{"certification_id":"CERT-R-LEGACY","status":"PASS"}'::jsonb);
