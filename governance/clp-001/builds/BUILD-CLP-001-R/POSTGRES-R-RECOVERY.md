# BUILD-CLP-001-R PostgreSQL Recovery Contract

R verifies PostgreSQL-native recovery with `pg_dump -Fc` and `pg_restore` into a fresh database. The verification compares a deterministic replay projection over event, explicit case-state history, pinned version fingerprint, and correlation-bound certification data before and after restore. The restored database must reproduce the same projection digest and current state/certification queries.

This is an infrastructure recovery proof, not a substitute for provider-level PITR drills. Production deployment must additionally record provider backup policy, retention, encryption, restore credentials, and periodic restoration receipts.
