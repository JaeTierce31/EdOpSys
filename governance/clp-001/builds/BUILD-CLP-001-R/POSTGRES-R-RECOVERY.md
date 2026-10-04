# BUILD-CLP-001-R PostgreSQL Recovery Contract

R verifies PostgreSQL-native recovery with `pg_dump -Fc` and `pg_restore` into a fresh database. The verification compares a deterministic replay projection over event, explicit case-state history, pinned version fingerprint, and correlation-bound certification data before and after restore. The restored database must reproduce the same projection digest and current state/certification queries.

This is an infrastructure recovery proof, not a substitute for provider-level PITR drills. Production deployment must additionally record provider backup policy, retention, encryption, restore credentials, and periodic restoration receipts.


## State hash compatibility

`clp_case_state_history.state_hash` intentionally carries a scheme marker. Runtime-created R receipts use the canonical application hash contract (`sha256:...` via `hashCanonical`). Migration-derived historical receipts use the `legacy-md5:` prefix because migration 002 must be executable on baseline PostgreSQL without introducing a `pgcrypto` dependency. Consumers MUST treat the prefix as part of the hash scheme identifier and MUST NOT compare legacy-md5 and sha256 digests as if they were the same algorithm. New runtime receipts MUST continue to use the canonical SHA-256 application contract.
