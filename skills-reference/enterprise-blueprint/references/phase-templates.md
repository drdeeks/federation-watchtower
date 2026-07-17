# Phase Templates Reference

Ready-to-use templates for the most common implementation phase types.
Each template includes the standard phase structure, typical deliverables,
prerequisite conditions, validation gates, and common failure modes.
Adapt the content — never the structure.

## Table of Contents

1. [How to Use These Templates](#1-how-to-use-these-templates)
2. [Phase Type: Pre-Build](#2-phase-type-pre-build)
3. [Phase Type: Foundation & Infrastructure](#3-phase-type-foundation--infrastructure)
4. [Phase Type: Authentication & Identity](#4-phase-type-authentication--identity)
5. [Phase Type: Core Feature Build](#5-phase-type-core-feature-build)
6. [Phase Type: Integration Layer](#6-phase-type-integration-layer)
7. [Phase Type: Testing & Hardening](#7-phase-type-testing--hardening)
8. [Phase Type: Launch & Live Ops](#8-phase-type-launch--live-ops)
9. [Custom Phase Guidelines](#9-custom-phase-guidelines)

---

## 1. How to Use These Templates

Each template below is a complete phase definition ready to be pasted into
`blueprint.md` (Part VI) and `checklist.md`. Replace every `[bracketed
placeholder]` with the project-specific value before committing.

After pasting, run:
```bash
python3 scripts/generate_checklist.py ./project/blueprint.md --sync
```

to synchronize the new phase into the checklist with all gate items and
implementation steps pre-populated.

The templates represent the minimum viable phase content. Complex phases
will require additional deliverables and steps — add them after the template
items, never before (preserve the order of standard items).

---

## 2. Phase Type: Pre-Build

**Purpose:** Establish all infrastructure, tooling, conventions, and
governance prerequisites before any application code is written.
This phase costs nothing to undo. Every subsequent phase depends on it.

**Typical duration:** 1-3 days for a single engineer; 1 day for a team.

### Blueprint Entry

```markdown
## Phase 0: Pre-Build

**Section Tag:** `[PHASE-0-v1]`
**Feature Flag:** `FEAT_PRE_BUILD` (infrastructure only — no user-facing flag)
**Assigned Agent:** _unassigned_

### Prerequisites

N/A — this is the first phase.

### Deliverables

- [ ] Repository created with standard directory structure.
- [ ] CI/CD pipeline configured and passing on a hello-world commit.
- [ ] `CHANGELOG.md` created with append-only CI check active.
- [ ] `global_change_log` database table created with INSERT-only trigger.
- [ ] Feature flag system initialized; all flags default to `disabled`.
- [ ] All module IDs registered in `modules` config table.
- [ ] Monitoring and error tracking connected to staging.
- [ ] Local development setup documented and verified on a clean machine.

### Validation Gate

> This phase is complete when: CI is green, monitoring is live, feature
> flags are operational, and a second engineer can set up the dev environment
> from the documentation alone without assistance.
```

**Common failure modes:**
- CI check for append-only `CHANGELOG.md` not actually enforced (pushed
  a line edit and it merged). Fix: test the CI check with an intentional
  violation before marking phase complete.
- Feature flags initialized but not defaulting to `disabled`. Fix: verify
  each flag's default value in the flags system before proceeding.
- Monitoring connected but not alerting on errors. Fix: trigger a deliberate
  error and confirm the alert arrives before sign-off.

---

## 3. Phase Type: Foundation & Infrastructure

**Purpose:** Create all database schemas, baseline API structure, and
shared utilities that subsequent phases build on. Nothing user-facing
ships in this phase.

**Typical duration:** 3-7 days depending on schema complexity.

### Blueprint Entry

```markdown
## Phase 1: Foundation & Infrastructure

**Section Tag:** `[PHASE-1-v1]`
**Feature Flag:** `FEAT_FOUNDATION`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 0 must be `COMPLETE`. CI is green. Monitoring is live.

### Deliverables

- [ ] All database schemas from Part IV created via versioned migrations.
      Every migration has a rollback file.
- [ ] Standard API envelope implemented and unit-tested.
- [ ] Base API routing structure established (all routes return 501 until
      implemented in later phases — this is intentional).
- [ ] Authentication middleware skeleton present (enforces JWT shape even
      if full auth is Phase 2 work).
- [ ] Error code registry implemented and typed.
- [ ] Shared utilities (logging, config, retry, circuit breaker) in place.
- [ ] All Part IV schemas validated against the spec — no column missing,
      no constraint missing.

### Validation Gate

> All schemas apply and roll back cleanly on a fresh database. The base API
> returns the standard envelope on all routes (200 or 501). No existing
> test regresses.
```

**Common failure modes:**
- Schema created without the rollback migration file. Fix: mandate rollback
  file in the PR template; make it a CI check.
- INSERT-only tables created without the database-level trigger. Fix: add
  trigger creation to the migration; validate it by attempting an UPDATE.
- Shared utilities added but not tested. Fix: require unit tests for all
  utility functions before the phase validation gate closes.

---

## 4. Phase Type: Authentication & Identity

**Purpose:** Implement the complete authentication and identity layer:
wallet connection, session management, player/user onboarding, and any
external identity service integration.

**Typical duration:** 3-5 days. Auth is never as simple as it looks.

### Blueprint Entry

```markdown
## Phase 2: Authentication & Identity

**Section Tag:** `[PHASE-2-v1]`
**Feature Flag:** `FEAT_AUTH`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 1 `COMPLETE`. All Part IV auth-related schemas are deployed.

### Deliverables

- [ ] Auth provider SDK integrated and tested (wallet connection, social
      login, or both per spec).
- [ ] Session JWT: creation, validation, refresh, and expiry all implemented
      and tested.
- [ ] New user onboarding flow: all steps functional end-to-end.
- [ ] Returning user flow: session restored correctly.
- [ ] External identity integration (if specified in Part III) connected
      with circuit breaker and fallback behavior.
- [ ] All Part III auth screen specifications implemented.
- [ ] E2E test covers new user flow and returning user flow.

### Validation Gate

> New user onboarding E2E test passes. Returning user session restore test
> passes. Invalid session redirect test passes. External identity service
> unreachable test confirms fallback behavior activates.
```

**Common failure modes:**
- Session JWT not validated on every protected route from day one. Fix:
  add auth middleware to all routes in Phase 1 skeleton; it enforces shape
  even before auth is implemented.
- Social login tested in isolation but not with wallet-derived session.
  Fix: test the combined flow (social login → embedded wallet → JWT) as
  an explicit E2E case.
- External identity service failure not handled gracefully. Fix: write a
  test that mocks the external service as unreachable and confirm the
  fallback response is correct.

---

## 5. Phase Type: Core Feature Build

**Purpose:** Implement the primary product features: the screens, business
logic, and data flows that define what the product does. This is typically
the largest phase by scope.

**Typical duration:** 1-4 weeks depending on feature count. If this phase
exceeds 4 weeks of estimated work, split it into sub-phases.

### Blueprint Entry

```markdown
## Phase 3: Core Feature Build

**Section Tag:** `[PHASE-3-v1]`
**Feature Flag:** `FEAT_CORE`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 2 `COMPLETE`. Auth layer is stable. All core schemas are deployed.

### Deliverables

- [ ] All Part III core feature screen specifications implemented.
- [ ] All business logic defined in Part III implemented server-side.
      No business logic lives in the client.
- [ ] Feature flag `FEAT_CORE` (and sub-flags per module) gating all
      new surfaces — flags enabled on staging, disabled in production.
- [ ] All Part IV API endpoints for core features implemented.
- [ ] Unit test coverage ≥ 80% on all new modules.
- [ ] Integration test for every new API endpoint (success + error case).
- [ ] Discovery or data events flowing to the real-time feed (if specified).

### Validation Gate

> All core feature E2E tests pass on staging. No p95 API response exceeds
> the Part VII budget. `FEAT_CORE` flag verified: staging enabled,
> production disabled. Coverage report shows ≥ 80%.
```

**Common failure modes:**
- Feature flag gates the UI but not the API. Fix: enforce flag check in
  API middleware, not just the frontend routing.
- Business logic added to the client for speed. Fix: move to server
  before the phase gate — never allow client-side business logic to ship.
- Phase scope grows mid-implementation ("while we're in there…"). Fix:
  any new scope discovered mid-phase is logged as a future phase item,
  not added to the current phase without a formal blueprint amendment.

---

## 6. Phase Type: Integration Layer

**Purpose:** Connect the application to external services, on-chain systems,
third-party APIs, and inter-service communication. Focuses on the boundaries
between the system and what lies outside it.

**Typical duration:** 2-5 days per major integration.

### Blueprint Entry

```markdown
## Phase 4: Integration Layer

**Section Tag:** `[PHASE-4-v1]`
**Feature Flag:** `FEAT_INTEGRATIONS`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 3 `COMPLETE`. Core features are stable on staging.

### Deliverables

- [ ] All external service clients implemented with: timeout configuration,
      exponential backoff retry, circuit breaker, and graceful fallback.
- [ ] All on-chain interactions implemented with: commit-then-execute pattern,
      ownership verification, and rollback-safe transaction handling.
- [ ] Webhook handlers for external event sources implemented and tested
      with mocked payloads.
- [ ] Cache layer implemented for all external reads with defined TTLs.
- [ ] Integration test for each external service with mocked failure mode.
- [ ] Real-time data flows (WebSocket, SSE, polling fallback chain) tested
      at 10× expected concurrent connections.

### Validation Gate

> Every external dependency has a passing mock-failure integration test.
> Circuit breaker activates correctly when a dependency is mocked as
> unavailable. On-chain verification cannot be bypassed by a stale cache.
```

**Common failure modes:**
- Circuit breaker implemented but never tested with a real failure. Fix:
  write a test that simulates the external service returning 5xx and
  confirm the circuit opens after the defined threshold.
- On-chain reads cached but cache not invalidated on ownership transfer.
  Fix: implement the indexer webhook handler before caching is enabled;
  test transfer event → cache invalidation → fresh read in sequence.

---

## 7. Phase Type: Testing & Hardening

**Purpose:** Close coverage gaps, run the full E2E suite, conduct load
testing, resolve performance regressions, and complete the security review.
No new features. Only quality improvement.

**Typical duration:** 3-7 days.

### Blueprint Entry

```markdown
## Phase 5: Testing & Hardening

**Section Tag:** `[PHASE-5-v1]`
**Feature Flag:** N/A — no new user-facing features
**Assigned Agent:** _unassigned_ (typically QA + Security roles)

### Prerequisites

Phase 4 `COMPLETE`. All features are implemented and flags are enabled
on staging.

### Deliverables

- [ ] Unit test coverage ≥ 80% across all modules (not just new ones).
- [ ] E2E tests pass for all critical user flows defined in Part III.
- [ ] Load test results documented: all Part VII performance budgets met
      under 2× expected concurrent users.
- [ ] Security review complete: auth flows, payment paths, on-chain
      interactions, and data exposure surfaces all audited.
- [ ] All FAIL items from `validate_blueprint.py` resolved.
- [ ] All known bugs triaged: P0 and P1 fixed, P2 documented with timeline.

### Validation Gate

> `validate_blueprint.py` returns 0 FAIL, ≤ 4 WARN. Load test report
> shows all p95 budgets met. Security review sign-off documented.
> No P0 or P1 bugs open.
```

---

## 8. Phase Type: Launch & Live Ops

**Purpose:** Enable features in production, establish live operational
procedures, and verify the system is running correctly under real load.

**Typical duration:** 1-3 days for initial launch; ongoing for live ops.

### Blueprint Entry

```markdown
## Phase 6: Launch & Live Ops

**Section Tag:** `[PHASE-6-v1]`
**Feature Flag:** ALL (all flags enabled in production in this phase)
**Assigned Agent:** _unassigned_ (typically DevOps + Architect roles)

### Prerequisites

Phase 5 `COMPLETE`. Security review signed off. All budgets met.

### Deliverables

- [ ] All feature flags enabled in production in the defined rollout order.
- [ ] Post-launch monitoring dashboards live and alerting configured.
- [ ] Runbook created for each P0 failure mode (what to do, who to page).
- [ ] Rollback procedure tested in staging: confirm full rollback completes
      within the defined RTO.
- [ ] Data export (GDPR) verified functional in production.
- [ ] Final change log entry written documenting the production launch.
- [ ] Blueprint marked as FINAL in document header.

### Validation Gate

> All flags enabled. Monitoring shows no anomalous error rates. Rollback
> tested. Final change log entry appended. Blueprint version updated.
```

---

## 9. Custom Phase Guidelines

When a project requires a phase not covered by the above templates:

**Naming:** Use the format `Phase N: [Noun Phrase]`. The noun phrase
describes what is produced, not how it is produced. "Phase 4: Agent
Federation Layer" is correct. "Phase 4: Build and Deploy Agent Federation"
is not.

**Duration calibration:** If the estimated duration exceeds 4 weeks, the
phase must be split. A phase that cannot be delivered in 4 weeks is a
project milestone, not a phase.

**Validation gate requirement:** Every custom phase must define a validation
gate that is objective and independently verifiable. "The team feels it is
ready" is not a gate criterion.

**Feature flag requirement:** Every custom phase that introduces user-facing
functionality must have a corresponding `FEAT_` flag that controls all
surfaces introduced in that phase. Infrastructure-only phases may waive
the user-facing flag but must still document what is and is not reversible.
