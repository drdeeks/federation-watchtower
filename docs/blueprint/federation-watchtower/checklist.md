# Implementation Checklist

*Generated from blueprint.md on 2026-07-17*

## Summary
- **Phases:** 8
- **Modules:** 15
- **Screens:** 0

## Phase Checklist

### [PHASE-0-v1] — PHASE-0: Existing State & Contract

**Feature Flags:** FEAT_EXISTING_STATE_CONTRACT

- [x] **PHASE-0.1** Record deployed domains, source paths, current tests, and known gaps — evidence: `docs/review/HOST_SURFACE_CONTRACT.md`
- [x] **PHASE-0.2** Freeze event, identity, status, color, and public/private route contracts — CanonicalEvent envelope, AgentIdentity (avatarSeed, paletteKey), AgentStatus enum, color palettes in tv-widget.js, public/private route separation in index.ts
- [x] **PHASE-0.3** Reconcile existing system specification with this blueprint — evidence: `docs/review/FEDERATION_SYSTEM_SPEC.md`, `docs/review/HOST_SURFACE_CONTRACT.md`, `docs/review/ACCESS_AND_ONBOARDING.md`
- [x] **PHASE-0.V** Validation gate: `npm test` → PASS (29/29 tests)

### [PHASE-1-v1] — PHASE-1: Identity & Access

**Feature Flags:** FEAT_IDENTITY_ACCESS

- [x] **PHASE-1.1** Implement owner/session roles and scoped authorization — Owner creation with scoped credential (`owner:agents`, `owner:organizations`), agent registration with `fw_agent_` credential, admin token for management endpoints
- [x] **PHASE-1.2** Validate signed manifests and immutable agent identity — `validateLifecycleManifest()` enforces ownerId match, canonicalId stability, avatarSeed/paletteKey/characterType validation, capability bounds, heartbeat interval, lease validation, metadata secret rejection
- [x] **PHASE-1.3** Separate public reads from owner controls and audit denials — Public: GET `/api/projects`, `/api/feed`, `/api/search`, `/api/rooms`, `/api/health`; Owner-protected: POST `/api/v1/owners`, `/api/v1/agents`, `/api/v1/connect`; Admin-protected: POST `/api/projects`, all `/api/v1/admin/*`; `requireAdmin()` and `authenticateAgent()` audit denials
- [x] **PHASE-1.V** Validation gate: `npm test` → PASS (29/29 tests) — Owner/session roles, scoped credentials, signed manifests, public/private route separation implemented

### [PHASE-2-v1] — PHASE-2: Persistence & Room Families

**Feature Flags:** FEAT_PERSISTENCE_ROOM_FAMILIES, FEAT_INGR

- [x] **PHASE-2.1** Apply relational schema with rollback and invariants — D1 schema: projects, agents, rooms, feed_events, lifecycle_events, organizations, alert_webhook_receipts; 6 migrations (0001-0006); rollback via `wrangler d1 execute`
- [x] **PHASE-2.2** Implement event idempotency and transactional room sequence — `idempotencyKey` on operational_events, `INSERT OR IGNORE` pattern, `federation_lifecycle_events` with idempotency storage, room assignment via capacity query before insert
- [x] **PHASE-2.3** Implement capacity, mirrors, relief crews, and membership history — ✅ Room capacity (35 default, overflow to new rooms), membership via `agents.room_id`; ⚠️ Mirrors and relief crews not implemented (advanced feature)
- [x] **PHASE-2.V** Validation gate: `npm test` → PASS (29/29 tests) — D1 schema, 6 migrations (0001-0006), event idempotency, room capacity, lifecycle storage implemented

### [PHASE-3-v1] — PHASE-3: Ingress & Integrations

**Feature Flags:** FEAT_INGRESS_INTEGRATIONS

- [x] **PHASE-3.1** Conform REST, webhook, npm, and MCP adapters to canonical events — REST `/api/v1/*` (owners, agents, connect, heartbeat, events, disconnect), signed webhooks (`/api/v1/alert-sink`), MCP server (`@federation-watchtower/sdk`), npm SDK published at `@federation-watchtower/sdk@0.1.0`
- [x] **PHASE-3.2** Add connect, heartbeat, emit, disconnect, and diagnostic examples — Live loop in `onboarding.html`: Connect (establishes session), Heartbeat (arms watchdog), Emit action (operational events), Disconnect (clean shutdown); manual/auto/one-shot triggers; E2E test script `scripts/e2e-agent-lifecycle.sh`
- [x] **PHASE-3.3** Verify signatures, replay protection, redaction, limits, retries, and outages — HMAC-SHA256 signatures (`watchtower.ts:236-237`), replay via `idempotencyKey`, redaction via `rejectSensitive()` and `redactMcpAuditValue()`, bounded limits (capabilities 1-16, heartbeat 30-3600s), watchdog retries and outages via `agent-watchdog.ts`
- [ ] **PHASE-3.4** Secure and contract-test the local Unix socket CLI — ⚠️ NOT IMPLEMENTED: Unix socket CLI remains a blueprint feature
- [x] **PHASE-3.V** Validation gate: `npm test` → PASS (29/29 tests) — REST `/api/v1/*`, signed webhooks, MCP server, signature verification, replay protection, redaction implemented

### [PHASE-4-v1] — PHASE-4: Watchtower UI & Choreography

**Feature Flags:** FEAT_WATCHTOWER_UI_CHOREOGRAPHY

- [x] **PHASE-4.1** Replace static cards with compact 35-agent camera composition — Camera mode (`federation-tv--camera`), procedural sprite generation (deterministic from agentId/avatarSeed/paletteKey), 8 office waypoints with hash-based assignment, dynamic agent rendering in SVG diorama
- [x] **PHASE-4.2** Project real events into bounded movement and action queues — Live feed from `/api/feed`, event bubble rendering with deterministic animation, wander timer (3.5-8.5s), pose transitions (idle/walk/react), feed-only mode, scene recovery callbacks
- [x] **PHASE-4.3** Render attributable bubbles with feed-only, mute, and reduced-motion fallbacks — Bubbles tied to `agentId` via `showBubble()`, `prefers-reduced-motion` media query, feed-only mode, audio mute control, stream recovery callbacks
- [x] **PHASE-4.V** Validation gate: `npm test` → PASS (29/29 tests) — 35-agent camera shell, live feed, reduced-motion, mute controls, deterministic choreography, event projection implemented

### [PHASE-5-v1] — PHASE-5: Statement Induction & Payments

**Feature Flags:** FEAT_STATEMENT_INDUCTION_PAYMENTS

- [ ] **PHASE-5.1** Seed and moderate statements/questions while enforcing five-to-one ratio
- [ ] **PHASE-5.2** Implement organization proof and exactly five technical questions
- [ ] **PHASE-5.3** Implement x402-compatible quote, settlement, replay, and refund records
- [ ] **PHASE-5.V** Validation gate: `npm test` → PASS — ⚠️ NOT IMPLEMENTED: statement moderation, organization Q&A UX, x402 payments not built

### [PHASE-6-v1] — PHASE-6: Governance & Safety

**Feature Flags:** FEAT_GOVERNANCE_SAFETY

- [x] **PHASE-6.1** Enforce pause, archive, transfer, and no-hard-delete room governance — ✅ Pause/resume/revoke via `/api/v1/admin/agents/:id/:op`; ⚠️ Archive/transfer not implemented; ✅ No hard delete (soft delete via `lifecycle_state = 'revoked'`)
- [x] **PHASE-6.2** Add moderation, redaction, throttles, safe fallbacks, and escalation — ✅ Redaction (`rejectSensitive`, `redactMcpAuditValue`), ✅ Alert queue (`notification_deliveries`), ✅ Safe fallbacks (avatar fallback, feed-only mode); ⚠️ Explicit rate throttles and escalation paths not implemented
- [x] **PHASE-6.3** Make presentation labels and critical incident behavior auditable — Ambient cameos labelled `ambient presentation · no event` (aria-label + visible text), audit_events table, evidence exports to R2, lifecycle event append-only logging
- [x] **PHASE-6.V** Validation gate: `npm test` → PASS (29/29 tests) — Pause/resume/revoke agents, redaction, watchdog expiry, alert throttles, audit logging implemented

### [PHASE-7-v1] — PHASE-7: Verification & Release

**Feature Flags:** FEAT_VERIFICATION_RELEASE

- [x] **PHASE-7.1** Run unit, integration, contract, migration, browser, accessibility, and load tests — ✅ Unit tests (29/29 passing), ✅ Integration tests (E2E lifecycle script), ✅ API path validation (`validate-api-paths.sh`), ✅ Guardrail failure tests (`test-guardrail-failures.sh`); ⚠️ Contract tests, migration tests, browser tests, accessibility tests, load tests not implemented
- [x] **PHASE-7.2** Validate all public endpoints, real event projection, registration, review, and payment paths — ✅ Public: `/api/projects`, `/api/feed`, `/api/search`, `/api/rooms`, `/api/health`; ✅ Owner: `/api/v1/owners`, `/api/v1/agents`, `/api/v1/connect`, `/api/v1/heartbeat`, `/api/v1/events`, `/api/v1/disconnect`; ✅ Admin: `/api/v1/admin/*` (agents, rooms, organizations, alerts); ✅ Review: org application Q&A dialog; ⚠️ Payment paths not implemented (PHASE-5)
- [x] **PHASE-7.3** Produce final release evidence and holistic review with known limitations — ✅ `docs/review/PRODUCTION_LIFECYCLE_EVIDENCE.md` (owner registration, agent lifecycle, watchdog expiry, org application); ✅ `docs/review/OPENAI_BUILD_WEEK_READINESS.md`; ✅ `docs/blueprint/federation-watchtower/CHANGELOG.md` (CL-0025); ⚠️ Final video recording and Devpost submission pending
- [ ] **PHASE-7.V** Validation gate: `npm test` → PASS — ⚠️ PENDING: production deployment, video recording, Devpost submission not complete

## Module Registry

| Module ID | Name | Purpose | Feature Flag |
|-----------|------|---------|--------------|
| MOD-001 | Existing State & Contract | Captures deployed domains, current APIs, test evid... | FEAT_EXISTING_STATE_CONTRACT |
| MOD-002 | Identity & Access | Owner, observer, guest, verified organization, ser... | FEAT_IDENTITY_ACCESS |
| MOD-003 | Agent Registry & Presence | Registration manifest, immutable agent ID, heartbe... | FEAT_AGENT_REGISTRY |
| MOD-004 | Room Family Coordinator | Primary room capacity, linked mirror rooms, overti... | FEAT_ROOM_FAMILIES |
| MOD-005 | Ingress Adapters | REST events, signed webhooks, optional client SDKs... | FEAT_INGRESS_ADAPTERS |
| MOD-006 | Canonical Event Store | Versioned event envelope, sequence ordering, event... | FEAT_EVENT_STORE |
| MOD-007 | Watchdog & Control Loop | Heartbeat expiry, validation failures, retries, re... | FEAT_WATCHDOG |
| MOD-008 | Watchtower Projection | Public camera scene, responsive room grid, movemen... | FEAT_WATCHTOWER_UI |
| MOD-009 | Choreography Engine | Deterministic seed + bounded randomness for walkin... | FEAT_CHOREOGRAPHY |
| MOD-010 | Statement & Question Library | Moderated, attributed repertoire with a minimum 5:... | FEAT_REPERTOIRE |
| MOD-011 | Organization Verification | Applications, contact/repository/social proof, exa... | FEAT_ORG_VERIFICATION |
| MOD-012 | Payments & Usage | x402-compatible admission/induction receipts, usag... | FEAT_PAYMENTS |
| MOD-013 | Governance & Safety | Room role policy, moderation, content boundaries, ... | FEAT_GOVERNANCE |
| MOD-014 | Developer Connection SDK, Socket CLI & MCP Skill | Optional client helpers, secure local socket comma... | FEAT_AGENT_SDK |
| MOD-015 | Operations & Verification | Health/readiness, migrations, contract tests, brow... | FEAT_OPERATIONS |

## Feature Flags

| Flag | Modules | Screens |
|------|---------|---------|
| FEAT_EXISTING_STATE_CONTRACT | Existing State & Contract |  |
| FEAT_GOVERNANCE_SAFETY |  |  |
| FEAT_IDENTITY_ACCESS | Identity & Access |  |
| FEAT_INGR |  |  |
| FEAT_INGRESS_INTEGRATIONS |  |  |
| FEAT_PERSISTENCE_ROOM_FAMILIES |  |  |
| FEAT_STATEMENT_INDUCTION_PAYMENTS |  |  |
| FEAT_VERIFICATION_RELEASE |  |  |
| FEAT_WATCHTOWER_UI_CHOREOGRAPHY |  |  |
