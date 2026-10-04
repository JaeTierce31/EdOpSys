BEGIN;
SET search_path=edopsys_observability,public;

INSERT INTO obs_observations VALUES
('obs-base-r','JaeTierce31/EdOpSys','REPOSITORY_HEAD','refs/heads/main','b0f19f2d0ce8a086604ed1f08d1202cd5650dae8','2026-10-04T15:19:10Z','sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','{}'),
('obs-build-r','JaeTierce31/EdOpSys','BUILD_RECEIPT','PR#3','32a2064cf0aa179e2b0f2c8f40e56e705cf37fec','2026-10-04T15:19:10Z','sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','{}'),
('obs-ci-r','JaeTierce31/EdOpSys','CI_RUN','actions/37206695993','32a2064cf0aa179e2b0f2c8f40e56e705cf37fec','2026-10-04T13:45:19Z','sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','{}'),
('obs-review-r','JaeTierce31/EdOpSys','PR_REVIEW','Mistral-Vibe-review','32a2064cf0aa179e2b0f2c8f40e56e705cf37fec','2026-10-04T14:47:00Z','sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd','{}'),
('obs-int-r','JaeTierce31/EdOpSys','ARTIFACT_INTEGRITY','R-source-manifest','0609035dc2373e8b2224e739761df88b5f2c7030b25b8db7434b5bf8638e680a','2026-10-04T14:47:00Z','sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','{}'),
('obs-auth-av','JaeTierce31/EdOpSys','AUTHORITY_RECORD','authority-registry-v2','17145394aa274dfca76003ac6e8be07082a997c1','2026-10-04T15:19:10Z','sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff','{}'),
('obs-auth-mn','JaeTierce31/EdOpSys','AUTHORITY_RECORD','authority-registry-v2','17145394aa274dfca76003ac6e8be07082a997c1','2026-10-04T15:19:10Z','sha256:abababababababababababababababababababababababababababababababab','{}');

INSERT INTO repository_baseline VALUES('obs-base-r','JaeTierce31/EdOpSys','b0f19f2d0ce8a086604ed1f08d1202cd5650dae8','BUILD-CLP-001-R','adab09caa0093c9490a8f1ab215a719bf0fa9aa4','dddd7d91494a5c3916146387828efd643b957fa2','95a1da390d81d3fefe611c74405505aa28fa686d','5427aff8c10370085546cf98ae83dacd5939bb0a','b0f19f2d0ce8a086604ed1f08d1202cd5650dae8','2026-10-04T15:19:10Z');
INSERT INTO build_status VALUES('obs-build-r','JaeTierce31/EdOpSys','BUILD-CLP-001-R',true,'32a2064cf0aa179e2b0f2c8f40e56e705cf37fec','b0f19f2d0ce8a086604ed1f08d1202cd5650dae8','5427aff8c10370085546cf98ae83dacd5939bb0a',61,61,'success','APPROVED_EXTERNAL',0,true,'2026-10-04T15:19:10Z');
INSERT INTO ci_runs VALUES('obs-ci-r','JaeTierce31/EdOpSys','BUILD-CLP-001-R',37206695993,'32a2064cf0aa179e2b0f2c8f40e56e705cf37fec','32a2064cf0aa179e2b0f2c8f40e56e705cf37fec','completed','success','success','2026-10-04T13:45:19Z');
INSERT INTO pr_reviews(id,repository,pr_number,reviewed_sha,expected_head_sha,reviewer,severity,finding_status,resolved,superseded,merge_blocking,observed_at,finding_key)
VALUES('obs-review-r','JaeTierce31/EdOpSys',3,'32a2064cf0aa179e2b0f2c8f40e56e705cf37fec','32a2064cf0aa179e2b0f2c8f40e56e705cf37fec','Mistral Vibe',NULL,'APPROVED',true,false,false,'2026-10-04T14:47:00Z','__summary__');
INSERT INTO artifact_integrity VALUES('obs-int-r','JaeTierce31/EdOpSys','governance/clp-001/builds/BUILD-CLP-001-R/receipts/R-source-manifest.json',true,'PASS','0609035dc2373e8b2224e739761df88b5f2c7030b25b8db7434b5bf8638e680a','0609035dc2373e8b2224e739761df88b5f2c7030b25b8db7434b5bf8638e680a',2413,2413,'2026-10-04T14:47:00Z');
INSERT INTO artifact_integrity_scope VALUES('obs-int-r','JaeTierce31/EdOpSys','BUILD-CLP-001-R','2026-10-04T14:47:00Z');
INSERT INTO authority_records VALUES
('obs-auth-av','JaeTierce31/EdOpSys','AUTH-APPLEVALLEY-155360','2025-S21','SC-0','US-MN-DAKOTA-APPLE-VALLEY','sha256:00b53bf9346e8e89debff50503783b2bcbe311715c6cb1a560c3076a2b971004','FRESHNESS_REVIEW_DUE',false,'2026-10-04T15:19:10Z'),
('obs-auth-mn','JaeTierce31/EdOpSys','AUTH-MN-PLUMBING-4714','2020-MN-PLUMBING-CODE','SC-0','US-MN','sha256:1a49eaa526cffbc39613fc0b64fd70daeb8e41a025baed00f708fc5b013b0bc2','CURRENT',false,'2026-10-04T15:19:10Z');

INSERT INTO governance_status_assertions VALUES
('G0-BLOCKED-HIST','JaeTierce31/EdOpSys','G0','designation_status','"BLOCKED_PENDING_SOURCE_BUNDLE_UPLOAD"','governance/clp-001/g0/G0-STATUS.json',NULL,'2026-10-04T08:50:00Z','2026-10-04T09:03:06Z','G0-DESIGNATED-CURRENT',1,'SUPERSEDED'),
('G0-DESIGNATED-CURRENT','JaeTierce31/EdOpSys','G0','designation_status','"DESIGNATED"','governance/clp-001/g1/G0-designation.json','adab09caa0093c9490a8f1ab215a719bf0fa9aa4','2026-10-04T09:03:06Z',NULL,NULL,2,'CURRENT');
INSERT INTO governance_supersession_receipts VALUES('G0-SUPERSESSION-001','JaeTierce31/EdOpSys','G0-BLOCKED-HIST','G0-DESIGNATED-CURRENT','Earlier fail-closed G0 status was historically valid; later byte-exact G0 designation supersedes its current operational interpretation.','sha256:1111111111111111111111111111111111111111111111111111111111111111','2026-10-04T09:03:06Z');
INSERT INTO governance_drift_findings VALUES('DRIFT-G0-001','JaeTierce31/EdOpSys','STALE_STATUS_ASSERTION','G0','P2','SUPERSEDED','G0-SUPERSESSION-001','2026-10-04T15:19:10Z');
COMMIT;
