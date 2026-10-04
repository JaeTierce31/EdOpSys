# BUILD-CLP-001-S — Repository Governance Observability + Health Projection

Parent baseline: `b0f19f2d0ce8a086604ed1f08d1202cd5650dae8` (merged BUILD-CLP-001-R).

S adds an append-only PostgreSQL observability schema and deterministic views for repository/build/authority/integrity/CI/review/drift health. It does not alter CLP domain semantics and does not authorize domain actions.

## Canonical boundary

> Observability projections are descriptive and MUST NOT authorize CLP state transitions, worker eligibility, verification, payout, or policy execution.

## Health model

- `BLOCKED`: unresolved P0/P1, required artifact failure, canonical CI failure, blocking authority conflict, or blocked canonical build.
- `UNKNOWN`: required observations are absent or verification is incomplete.
- `DEGRADED`: stale-head CI, authority freshness debt, unresolved P2, or non-blocking open drift.
- `HEALTHY`: all required gates present and passing.

## Dashboard views

- `v_build_health`
- `v_authority_health`
- `v_integrity_health`
- `v_ci_health`
- `v_review_health`
- `v_governance_assertion_current`
- `v_governance_drift`
- `v_governance_timeline`
- `v_repository_health`
- `v_dashboard_summary_json`

## Stale G0 supersession

`governance/clp-001/g0/G0-STATUS.json` is preserved as historical evidence. `fixtures/G0-STATUS-SUPERSESSION.json` records why its earlier blocked operational status is superseded by the later G0 designation without rewriting history.

## Verification

`tests/s-health.sql` contains deterministic T1–T10 tests. The GitHub Actions PostgreSQL 16 gate applies Q→R→S migrations, loads repository observations, runs T1–T10, and checks the live EdOpSys projection.
