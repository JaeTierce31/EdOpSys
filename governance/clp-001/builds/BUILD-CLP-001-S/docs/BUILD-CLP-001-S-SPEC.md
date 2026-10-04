# BUILD-CLP-001-S — Repository Governance Observability + Health Projection

Baseline: `b0f19f2d0ce8a086604ed1f08d1202cd5650dae8` (merged BUILD-CLP-001-R).

## Purpose
Create a PostgreSQL-backed, append-only observability projection for repository governance health. The projection ingests evidence-derived observations and exposes deterministic views suitable for a future dashboard.

## Authority boundary
Observability projections are descriptive and MUST NOT authorize CLP state transitions, worker eligibility, verification, payout, or policy execution.

GitHub governance artifacts, signed/hashed receipts, authority records, CI evidence, and independent reviews remain source evidence. SQL views are derived projections only.

## Required health states
`HEALTHY`, `DEGRADED`, `BLOCKED`, `UNKNOWN`.

## Required rules
- Unresolved P0/P1 -> BLOCKED.
- Missing required artifact or hash/size mismatch -> BLOCKED.
- Failed canonical CI -> BLOCKED.
- Authority conflict that blocks execution -> BLOCKED.
- Missing required observation -> UNKNOWN (never HEALTHY).
- Non-blocking governance drift -> DEGRADED.
- Authority freshness review due -> DEGRADED unless an explicit fail-closed policy marks it blocking.
- Unresolved P2 -> DEGRADED.
- Stale-head CI -> DEGRADED.
- HEALTHY only when every required gate is present and passing.

## Stale G0 rule
`governance/clp-001/g0/G0-STATUS.json` is retained as historically valid evidence of an earlier blocked state. It is superseded, not deleted or rewritten, by the later G0 designation chain. The supersession relationship must be machine-readable.
