# EdOpSys CLP-001 G0 materialization

Upload the four files in this package to `governance/clp-001/g0/source-bundles/` in `JaeTierce31/EdOpSys` without modifying their contents.

After upload, record the resulting repository HEAD SHA. That commit becomes the G0 candidate only after the three source-bundle SHA-256 values match `G0-MATERIALIZATION-MANIFEST.json`. Then regenerate CLP001Certification to bind that exact G0 SHA, generate a fresh Ed25519 signing key, sign the bound receipt, and commit the receipt/public key as G1.

Do not authorize BUILD-CLP-001-D before G1 verification passes.
