#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:=127.0.0.1}" "${PGPORT:=5432}" "${PGUSER:=postgres}" "${PGPASSWORD:=postgres}" "${PGDATABASE:=postgres}"
export PGHOST PGPORT PGUSER PGPASSWORD
SRC_DB="${R_SOURCE_DB:-clp_r_source}"
DST_DB="${R_RESTORE_DB:-clp_r_restore}"
DUMP="${R_DUMP_PATH:-/tmp/clp001-r.dump}"

dropdb --if-exists "$SRC_DB" >/dev/null 2>&1 || true
dropdb --if-exists "$DST_DB" >/dev/null 2>&1 || true
createdb "$SRC_DB"
psql -v ON_ERROR_STOP=1 -d "$SRC_DB" -f migrations/001_clp001_q.sql >/dev/null
psql -v ON_ERROR_STOP=1 -d "$SRC_DB" -f scripts/postgres-r-legacy-q-seed.sql >/dev/null
psql -v ON_ERROR_STOP=1 -d "$SRC_DB" -f migrations/002_clp001_r.sql >/dev/null
[[ "$(psql -At -d "$SRC_DB" -c "SELECT state FROM clp_case_state_history WHERE correlation_id='corr-r-legacy' ORDER BY aggregate_version DESC LIMIT 1")" == "INTAKE_STRUCTURED" ]]
[[ "$(psql -At -d "$SRC_DB" -c "SELECT count(*) FROM clp_case_state_history WHERE correlation_id='corr-r-legacy'")" == "4" ]]
[[ "$(psql -At -d "$SRC_DB" -c "SELECT correlation_id FROM clp_certifications WHERE certification_id='CERT-R-LEGACY'")" == "corr-r-legacy" ]]
psql -v ON_ERROR_STOP=1 -d "$SRC_DB" -f scripts/postgres-r-seed.sql >/dev/null

projection_sql="SELECT md5(jsonb_build_object(
 'events',(SELECT jsonb_agg(to_jsonb(t) ORDER BY aggregate_version) FROM (SELECT event_id,correlation_id,aggregate_id,aggregate_version,event_type,decision,event_hash,payload FROM clp_events WHERE correlation_id IN ('corr-r-seed','corr-r-legacy')) t),
 'state',(SELECT jsonb_agg(to_jsonb(t) ORDER BY aggregate_version) FROM (SELECT correlation_id,aggregate_id,aggregate_version,source_event_id,state,state_hash FROM clp_case_state_history WHERE correlation_id IN ('corr-r-seed','corr-r-legacy')) t),
 'versions',(SELECT jsonb_agg(to_jsonb(t) ORDER BY version_ref) FROM (SELECT version_ref,canonical_hash,payload FROM clp_versions WHERE version_ref='CLP-001-TRANSITIONS@1.0.0') t),
 'evidence',(SELECT jsonb_agg(to_jsonb(t) ORDER BY evidence_id) FROM (SELECT evidence_id,correlation_id,content_hash,payload FROM clp_evidence WHERE correlation_id IN ('corr-r-seed','corr-r-legacy')) t),
 'chain',(SELECT jsonb_agg(to_jsonb(t) ORDER BY ordinal) FROM (SELECT event_id,correlation_id,ordinal,event_hash,previous_chain_hash,chain_hash FROM clp_chain WHERE correlation_id IN ('corr-r-seed','corr-r-legacy')) t),
 'lineage',(SELECT jsonb_agg(to_jsonb(t) ORDER BY lineage_id) FROM (SELECT lineage_id,correlation_id,parents,payload FROM clp_lineage WHERE correlation_id IN ('corr-r-seed','corr-r-legacy')) t),
 'certifications',(SELECT jsonb_agg(to_jsonb(t) ORDER BY certification_id) FROM (SELECT certification_id,certification_hash,payload,correlation_id FROM clp_certifications WHERE correlation_id IN ('corr-r-seed','corr-r-legacy')) t)
)::text);"
SRC_DIGEST=$(psql -At -d "$SRC_DB" -c "$projection_sql")
pg_dump -Fc -d "$SRC_DB" -f "$DUMP"
createdb "$DST_DB"
pg_restore --no-owner --no-privileges -d "$DST_DB" "$DUMP"
DST_DIGEST=$(psql -At -d "$DST_DB" -c "$projection_sql")
[[ -n "$SRC_DIGEST" && "$SRC_DIGEST" == "$DST_DIGEST" ]]
[[ "$(psql -At -d "$DST_DB" -c "SELECT state FROM clp_case_state_history WHERE correlation_id IN ('corr-r-seed','corr-r-legacy') ORDER BY aggregate_version DESC LIMIT 1")" == "INTAKE_STRUCTURED" ]]
[[ "$(psql -At -d "$DST_DB" -c "SELECT count(*) FROM clp_certifications WHERE correlation_id IN ('corr-r-seed','corr-r-legacy') AND certification_id='CERT-R-SEED'")" == "1" ]]
printf 'R_BACKUP_RESTORE_PASS source=%s restored=%s\n' "$SRC_DIGEST" "$DST_DIGEST"
