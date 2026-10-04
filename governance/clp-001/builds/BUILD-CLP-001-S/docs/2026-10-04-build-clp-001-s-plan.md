# BUILD-CLP-001-S Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an append-only PostgreSQL governance observability projection and deterministic repository-health views without granting execution authority.

**Architecture:** Source evidence is ingested as append-only observations/snapshots in `edopsys_observability`; deterministic SQL views compute domain health. A dedicated assertion/supersession model preserves stale historical facts while resolving current truth through higher-authority later evidence.

**Tech Stack:** PostgreSQL 16, SQL/PLpgSQL, GitHub Actions.

**Spec:** `docs/BUILD-CLP-001-S-SPEC.md`

## Global Constraints
- Parent baseline MUST be merged R `b0f19f2d0ce8a086604ed1f08d1202cd5650dae8`.
- Observability MUST NOT mutate CLP domain history or authorize domain actions.
- Existing Q/R constraints and triggers MUST remain unchanged.
- UNKNOWN MUST NOT collapse into HEALTHY.
- Historical stale G0 evidence MUST be superseded, never rewritten/deleted.

## Review Focus
- Missing observation sets return UNKNOWN rather than optimistic health.
- CI success on a stale head returns STALE_HEAD/DEGRADED.
- Resolved/superseded P1 findings no longer block.
- Historical G0 blockage remains queryable while current G0 status resolves designated.
- Append-only protections reject mutation in both CLP and observability tables.

---

### Task 1: Schema + append-only observation model
**Files:** migration and SQL tests.
- [ ] Write failing schema contract tests.
- [ ] Implement schema/tables/comments/triggers.
- [ ] Verify schema contract passes.

### Task 2: Deterministic health views
**Files:** migration and health-rule tests.
- [ ] Write T1-T9 failing health tests.
- [ ] Implement build/integrity/CI/review/authority/drift/repository/timeline/JSON views.
- [ ] Verify all health tests pass.

### Task 3: Stale-G0 supersession fixture
**Files:** `fixtures/repository-observations.sql`.
- [ ] Write fixture assertions for historical blockage + current designation + resolved drift.
- [ ] Insert machine-readable assertions, supersession receipt and resolved drift record.
- [ ] Verify current G0 projection is not BLOCKED by the historical assertion.

### Task 4: PostgreSQL 16 gate + immutable-domain test
**Files:** workflow and `tests/s-health.sql`.
- [ ] Add T10 mutation rejection test for CLP and observability.
- [ ] Run migration + fixture + tests against PostgreSQL 16 in CI.
- [ ] Record exact-head run before review.
