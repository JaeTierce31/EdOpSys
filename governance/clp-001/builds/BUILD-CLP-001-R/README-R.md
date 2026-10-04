# BUILD-CLP-001-R v1.0.4

Infrastructure-only successor to merged BUILD-CLP-001-Q. Parent repository baseline: `5427aff8c10370085546cf98ae83dacd5939bb0a`.

R closes three deferred durability gaps without changing frozen CLP-001 domain semantics:

1. **Explicit append-only case-state history** — every consequential event receives a state receipt; null-decision events inherit the prior state instead of resetting transition anchoring.
2. **Correlation-bound certification reconstruction** — persisted certifications are reconstructable per correlation through a separate replay envelope, preserving the historical replay hash contract.
3. **Database-native recovery proof** — PostgreSQL `pg_dump`/`pg_restore` into a fresh database must reproduce the deterministic replay projection over events, state history, version fingerprints, evidence, event chain, lineage, and certifications for both R-native and migrated legacy correlations.

Still excluded: resident UI, worker UI, marketplace, payments, social/community, gamification, production identity federation, and expanded AI authority.
