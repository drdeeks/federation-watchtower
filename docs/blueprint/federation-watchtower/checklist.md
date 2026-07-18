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
- [ ] **PHASE-0.2** Freeze event, identity, status, color, and public/private route contracts
- [ ] **PHASE-0.3** Reconcile existing system specification with this blueprint
- [ ] **PHASE-0.V** Validation gate: `hemlock test-all` → PASS

### [PHASE-1-v1] — PHASE-1: Identity & Access

**Feature Flags:** FEAT_IDENTITY_ACCESS

- [ ] **PHASE-1.1** Implement owner/session roles and scoped authorization
- [ ] **PHASE-1.2** Validate signed manifests and immutable agent identity
- [ ] **PHASE-1.3** Separate public reads from owner controls and audit denials
- [ ] **PHASE-1.V** Validation gate: `hemlock test-all` → PASS

### [PHASE-2-v1] — PHASE-2: Persistence & Room Families

**Feature Flags:** FEAT_PERSISTENCE_ROOM_FAMILIES, FEAT_INGR

- [ ] **PHASE-2.1** Apply relational schema with rollback and invariants
- [ ] **PHASE-2.2** Implement event idempotency and transactional room sequence
- [ ] **PHASE-2.3** Implement capacity, mirrors, relief crews, and membership history
- [ ] **PHASE-2.V** Validation gate: `hemlock test-all` → PASS

### [PHASE-3-v1] — PHASE-3: Ingress & Integrations

**Feature Flags:** FEAT_INGRESS_INTEGRATIONS

- [ ] **PHASE-3.1** Conform REST, webhook, npm, and MCP adapters to canonical events
- [ ] **PHASE-3.2** Add connect, heartbeat, emit, disconnect, and diagnostic examples
- [ ] **PHASE-3.3** Verify signatures, replay protection, redaction, limits, retries, and outages
- [ ] **PHASE-3.4** Secure and contract-test the local Unix socket CLI
- [ ] **PHASE-3.V** Validation gate: `hemlock test-all` → PASS

### [PHASE-4-v1] — PHASE-4: Watchtower UI & Choreography

**Feature Flags:** FEAT_WATCHTOWER_UI_CHOREOGRAPHY

- [ ] **PHASE-4.1** Replace static cards with compact 35-agent camera composition — current evidence: public 35-slot camera shell exists; live stream/snapshot and production position projection remain pending
- [ ] **PHASE-4.2** Project real events into bounded movement and action queues — current evidence: public feed/agent callbacks are wired; canonical projection scheduler and audit references remain pending
- [ ] **PHASE-4.3** Render attributable bubbles with feed-only, mute, and reduced-motion fallbacks — current evidence: feed-only and reduced-motion controls exist; bubble attribution, mute, and stream-recovery evidence remain pending
- [ ] **PHASE-4.V** Validation gate: `hemlock test-all` → PASS

### [PHASE-5-v1] — PHASE-5: Statement Induction & Payments

**Feature Flags:** FEAT_STATEMENT_INDUCTION_PAYMENTS

- [ ] **PHASE-5.1** Seed and moderate statements/questions while enforcing five-to-one ratio
- [ ] **PHASE-5.2** Implement organization proof and exactly five technical questions
- [ ] **PHASE-5.3** Implement x402-compatible quote, settlement, replay, and refund records
- [ ] **PHASE-5.V** Validation gate: `hemlock test-all` → PASS

### [PHASE-6-v1] — PHASE-6: Governance & Safety

**Feature Flags:** FEAT_GOVERNANCE_SAFETY

- [ ] **PHASE-6.1** Enforce pause, archive, transfer, and no-hard-delete room governance
- [ ] **PHASE-6.2** Add moderation, redaction, throttles, safe fallbacks, and escalation
- [ ] **PHASE-6.3** Make presentation labels and critical incident behavior auditable
- [ ] **PHASE-6.V** Validation gate: `hemlock test-all` → PASS

### [PHASE-7-v1] — PHASE-7: Verification & Release

**Feature Flags:** FEAT_VERIFICATION_RELEASE

- [ ] **PHASE-7.1** Run unit, integration, contract, migration, browser, accessibility, and load tests
- [ ] **PHASE-7.2** Validate all public endpoints, real event projection, registration, review, and payment paths
- [ ] **PHASE-7.3** Produce final release evidence and holistic review with known limitations
- [ ] **PHASE-7.V** Validation gate: `hemlock test-all` → PASS

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
