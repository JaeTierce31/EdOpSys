#!/usr/bin/env bash
set -euo pipefail
ROOT="governance/clp-001/g0"
MAT="$ROOT/materialize"
OUT="$ROOT/source-bundles"
mkdir -p "$OUT"

cat "$MAT/A/part-000" "$MAT/A/part-001" "$MAT/A/part-002" > "$OUT/BUILD-A-source-bundle.json"
cat "$MAT/B/part-000" "$MAT/B/part-001" "$MAT/B/part-002" > "$OUT/BUILD-B-source-bundle.json"
cat \
 "$MAT/C/part-000" "$MAT/C/part-001" "$MAT/C/part-002a" \
 "$MAT/C/rest-001" "$MAT/C/rest-002" "$MAT/C/rest-003" "$MAT/C/rest-004" \
 "$MAT/C/rest-005" "$MAT/C/rest-006" "$MAT/C/rest-007" "$MAT/C/rest-008" \
 "$MAT/C/rest-009" "$MAT/C/rest-010" "$MAT/C/rest-011" "$MAT/C/rest-012" \
 "$MAT/C/rest-013" "$MAT/C/rest-014" "$MAT/C/rest-015" \
 > "$OUT/BUILD-C-source-bundle.json"

A_EXPECTED="94598061d5b00454a55907b0ca5e3164396b2cebdc32bdf87077dfe4429f9ea4"
B_EXPECTED="8364753ae4db383975d033f35a2450ce675ef8fb50e91483a6f758ad2a25e86d"
C_EXPECTED="23c9fdc618cbbc49d4259a1c6829a813b898352d58fb5175086cac05fd786503"

A_ACTUAL="$(sha256sum "$OUT/BUILD-A-source-bundle.json" | awk '{print $1}')"
B_ACTUAL="$(sha256sum "$OUT/BUILD-B-source-bundle.json" | awk '{print $1}')"
C_ACTUAL="$(sha256sum "$OUT/BUILD-C-source-bundle.json" | awk '{print $1}')"
A_BYTES="$(wc -c < "$OUT/BUILD-A-source-bundle.json" | tr -d ' ')"
B_BYTES="$(wc -c < "$OUT/BUILD-B-source-bundle.json" | tr -d ' ')"
C_BYTES="$(wc -c < "$OUT/BUILD-C-source-bundle.json" | tr -d ' ')"

[[ "$A_ACTUAL" == "$A_EXPECTED" ]] || { echo "A hash mismatch" >&2; exit 11; }
[[ "$B_ACTUAL" == "$B_EXPECTED" ]] || { echo "B hash mismatch" >&2; exit 12; }
[[ "$C_ACTUAL" == "$C_EXPECTED" ]] || { echo "C hash mismatch" >&2; exit 13; }
[[ "$A_BYTES" == "28575" ]] || { echo "A size mismatch" >&2; exit 21; }
[[ "$B_BYTES" == "46896" ]] || { echo "B size mismatch" >&2; exit 22; }
[[ "$C_BYTES" == "157376" ]] || { echo "C size mismatch" >&2; exit 23; }

cat > "$OUT/SHA256SUMS" <<EOF
$A_EXPECTED  BUILD-A-source-bundle.json
$B_EXPECTED  BUILD-B-source-bundle.json
$C_EXPECTED  BUILD-C-source-bundle.json
EOF

cat > "$OUT/G0-MATERIALIZATION-VERIFICATION.json" <<EOF
{
  "verification_id": "CLP-001-G0-MATERIALIZATION-1",
  "status": "PASS",
  "algorithm": "SHA-256",
  "bundles": [
    {"id":"BUILD-CLP-001-A","path":"BUILD-A-source-bundle.json","sha256":"$A_ACTUAL","bytes":$A_BYTES},
    {"id":"BUILD-CLP-001-B","path":"BUILD-B-source-bundle.json","sha256":"$B_ACTUAL","bytes":$B_BYTES},
    {"id":"BUILD-CLP-001-C","path":"BUILD-C-source-bundle.json","sha256":"$C_ACTUAL","bytes":$C_BYTES}
  ],
  "historical_replay_hash": "sha256:62e1f774d99ea358a40956be98bb6b3516a6bbfa4f6ca9cad040a7794a1b79f9",
  "event_chain_root": "sha256:ab33c276b86cb4a0e5dba12b2abd70cdfcaca625bff8adbafe98e779d0d09818"
}
EOF

echo "CLP-001 G0 source bundle materialization: PASS"
