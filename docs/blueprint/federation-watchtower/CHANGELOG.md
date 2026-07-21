# Federation Watchtower — CHANGELOG

> This file is the append-only change log. No entry may be modified or deleted.
> All entries must follow the format defined in blueprint.md Part V.

---

## CL-0000 — Document Initialization

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-001, MOD-015]
Section Tags: [[SYS-OVERVIEW-v1], [QUALITY-v1]]
Files Changed: [blueprint.md, checklist.md, CHANGELOG.md]
Description : Created a separate authoritative Federation Watchtower blueprint
              and unlocked companion checklist from the enterprise blueprint
              scaffold. This package records the deployed baseline, target
              contracts, and explicit gaps without modifying the existing
              production blueprint or starting an enforcement loop.
Tests Passing: existing Federation serverless 7/7 tests and TypeScript check
Phase       : PHASE-0
Rollback Ref: N/A — initial document creation
```

## CL-0001 — Existing Baseline Incorporated

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-002, MOD-003, MOD-004, MOD-005, MOD-006, MOD-007, MOD-008,
               MOD-009, MOD-010, MOD-011, MOD-012, MOD-013, MOD-014]
Section Tags: [[MODULE-REGISTRY-v1], [SPECS-v1], [DATA-ARCH-v1]]
Files Changed: [blueprint.md, checklist.md, CHANGELOG.md]
Description : Incorporated the existing Federation system specification,
              deployed endpoint names, current source modules, room/capacity
              rules, agent lifecycle, statement ratio, organization proof,
              payment direction, and Watchtower visual requirements. Existing
              implementation is marked EXISTS or PARTIAL; unfinished behavior
              is marked PLANNED so the checklist can guide a later release.
Tests Passing: documentation validation 34/34; existing API tests recorded
Phase       : PHASE-0
Rollback Ref: N/A — documentation-only amendment
```

## CL-0002 — Remove Runtime Package Coupling

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-005, MOD-014]
Section Tags: [[SYS-OVERVIEW-v1], [MODULE-REGISTRY-v1], [SPECS-v1]]
Files Changed: [blueprint.md, checklist.md, CHANGELOG.md]
Description : Removed the specific Character Kit package as a Federation
              blueprint dependency. Federation remains runtime-neutral and
              accepts only declared manifests, connection state, capabilities,
              and observable events. Optional client or enforcement packages may
              connect, but they are not required to define Federation identity,
              safety, personality, or visual representation.
Tests Passing: blueprint validation 34/34; checklist regenerated with 8 phases
Phase       : PHASE-0
Rollback Ref: N/A — documentation-only amendment
```

## CL-0003 — Add Secure Local Socket CLI Contract

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-005, MOD-014, MOD-015]
Section Tags: [[SYS-OVERVIEW-v1], [SPECS-v1], [QUALITY-v1]]
Files Changed: [blueprint.md, checklist.md, CHANGELOG.md]
Description : Added a runtime-neutral Unix-domain socket CLI contract for
              local Federation agents and operators. The CLI shares canonical
              event, authorization, redaction, idempotency, audit, and
              diagnostic rules with HTTP ingress while remaining optional for
              hosted agents and unrelated runtime enforcement packages.
Tests Passing: blueprint validation 34/34; checklist regenerated with socket task
Phase       : PHASE-3
Rollback Ref: N/A — documentation-only amendment
```

## CL-0004 — Public Watchtower Camera Console Slice

```
Date        : 2026-07-17 00:00 UTC
Contributor : Codex
Modules     : [MOD-008, MOD-009, MOD-014, MOD-015]
Section Tags: [[WATCH-PUBLIC-v1], [CAMERA-PROJECTION-v1], [QUALITY-v1]]
Files Changed: [source/federation-tv-widget/public/index.html,
                source/federation-tv-widget/public/tv-widget.js,
                source/federation-tv-widget/src/tv-widget.js,
                docs/review/HOST_SURFACE_CONTRACT.md,
                checklist.md, CHANGELOG.md]
Description : Reworked the public Watchtower into a selected-room camera console
              with a room picker, accessible agent roster, public detail drawer,
              terminal-style activity feed, reduced-motion control, and feed-only
              fallback. The visual shell borrows the useful surveillance-console
              hierarchy of an external reference without copying its camera feeds,
              glitch behavior, or fabricated log content. A single delayed ambient
              cameo may appear only in a quiet camera room; it is labelled as
              presentation with no operational event and never enters the feed.
Tests Passing: Worker types; serverless 14/14; SDK 3/3; browser JavaScript syntax; git diff --check
Phase       : PHASE-4 (partial evidence only; prerequisites and release gate remain incomplete)
Rollback Ref: uncommitted working tree — revert the listed public UI files and documentation entry together
```

## CL-0005 — Owner-Scoped Lifecycle and Webhook Presence Slice

```
Date        : 2026-07-17
Contributor : Codex
Modules     : [MOD-002, MOD-003, MOD-005, MOD-006, MOD-007, MOD-011, MOD-014]
Section Tags: [[IDENTITY-ACCESS-v1], [INGRESS-v1], [WATCHDOG-v1], [ORG-VERIFY-v1]]
Files Changed: [0004_federation_lifecycle.sql, lifecycle.ts, index.ts,
                agent-registry.ts, agent-watchdog.ts, package SDK, README files]
Description : Added an additive canonical owner/agent lifecycle: one-time
              owner and agent credentials, validated manifests, public registry
              projection, connect/heartbeat/event/disconnect API routes,
              durable watchdog expiry, immutable lifecycle records, and a
              package-facing scoped agent client. Added owner-bound organization
              applications with exactly five normalized technical answers and
              two non-GitHub social proofs. The shared ingestion secret remains
              legacy/server-side only; the new lifecycle never returns it.
Tests Passing: Worker type generation and serverless suite PASS; SDK 4/4; git diff --check
Phase       : PHASE-1/PHASE-3 partial implementation; remote migration and
              authenticated production lifecycle evidence remain incomplete
Rollback Ref: do not apply 0004 migration; if already applied, revoke issued
              credentials and disable the new routes before a follow-up additive rollback
```

## CL-0006 — Production Lifecycle Evidence

```
Date        : 2026-07-17
Contributor : Codex
Modules     : [MOD-002, MOD-003, MOD-005, MOD-006, MOD-007, MOD-011, MOD-015]
Section Tags: [[IDENTITY-ACCESS-v1], [INGRESS-v1], [WATCHDOG-v1], [QUALITY-v1]]
Files Changed: [PRODUCTION_LIFECYCLE_EVIDENCE.md, CHANGELOG.md]
Description : Applied additive lifecycle migration 0004 and deployed Worker
              version bb29a04c-3abf-476a-b637-2684ec2acc96. A disposable
              production owner/agent completed registration, connect,
              heartbeat, real event/public projection, persistence refresh, and
              automatic watchdog expiry to offline. A separate owner-bound
              organization application accepted exactly five technical answers
              and two non-GitHub social proofs.
Tests Passing: production lifecycle and organization application contracts PASS
Phase       : PHASE-1/PHASE-3 partial evidence; reviewer roles, revocation UI,
              room-family completion, and release checklist gates remain incomplete
Rollback Ref: Worker rollback to prior version; migration is additive and must
              be superseded by an additive disable/revocation migration if needed
```

## CL-0007 — Authoritative Room Scene Projection Slice

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-003, MOD-006, MOD-007, MOD-008, MOD-009]
Section Tags: [[CAMERA-PROJECTION-v1], [CHOREOGRAPHY-v1], [WATCHDOG-v1]]
Files Changed: [room-scene.ts, lifecycle.ts, agent-watchdog.ts, index.ts,
                wrangler.toml, ROOM_SCENE_CONTRACT.md, room-scene.test.ts]
Description : Added one SQLite-backed Durable Object coordination atom per
              public room. It persists bounded agent placement, destination,
              action, presentation provenance, sequence, and recent scene
              events. Real lifecycle and operational inputs project into the
              scene; a scheduled ambient beat may move an active agent but is
              explicitly labelled as presentation with no operational event.
              The public read-only scene snapshot is exposed on fapi. Browser
              coordinate/sprite rendering is intentionally not claimed here.
Tests Passing: Worker type generation; serverless 18/18; git diff --check
Phase       : PHASE-4 partial implementation; no checklist item marked pending
              endpoint, browser, and production acceptance evidence
Rollback Ref: remove ROOM_SCENE binding/routes and revert scene invocation;
              RoomScene storage is isolated from operational D1 evidence
```

## CL-0008 — Public Room Scene Consumption and Submission Handoff

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-008, MOD-009, MOD-015]
Section Tags: [[CAMERA-PROJECTION-v1], [CHOREOGRAPHY-v1], [QUALITY-v1]]
Files Changed: [tv-widget.js, index.html, SUBMISSION_RUNBOOK.md, README.md]
Description : Wired the public widget to the read-only authoritative room-scene
              endpoint. A selected camera room now uses server-issued positions,
              destination, animation, and provenance; ambient movement carries
              a visible label. The public home selects the first real room when
              available instead of presenting an all-room static grid. Added a
              concise release and Devpost handoff runbook.
Tests Passing: pending browser syntax, Worker suite, and deployment verification
Phase       : PHASE-4 partial implementation; sprite rendering, stream cursors,
              production scene evidence, and checklist gate remain incomplete
Rollback Ref: revert widget scene fetch/placement and retain the roster/feed
              fallback; the RoomScene backend remains independently reversible
```

## CL-0009 — Room Scene Production Release Evidence

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-008, MOD-009, MOD-015]
Section Tags: [[CAMERA-PROJECTION-v1], [CHOREOGRAPHY-v1], [QUALITY-v1]]
Files Changed: [CHANGELOG.md, ROOM_SCENE_CONTRACT.md]
Description : Deployed RoomScene binding, lifecycle projection, public snapshot
              route, and Watchtower scene consumer as Worker version
              524b7f37-f53f-4e87-9b6a-b91834a2a7be. Public health returned 200;
              the selected existing room returned an empty but valid scene
              snapshot, and the deployed widget contained the scene endpoint
              and projected-camera code. No fake scene data was seeded.
Tests Passing: Worker types; serverless 18/18; browser syntax; public health,
              scene snapshot, and deployed widget inspection PASS
Phase       : PHASE-4 partial evidence; live newly-projected agent, sprite
              renderer, stream cursors, and full checklist gate remain pending
Rollback Ref: Worker rollback to preceding version; RoomScene data is isolated
              from operational D1 evidence and can be disabled by route/call-site rollback
```

## CL-0010 — Navigation, Presentation Cadence, and Package Handoff

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-008, MOD-009, MOD-015]
Section Tags: [[CAMERA-PROJECTION-v1], [CHOREOGRAPHY-v1], [QUALITY-v1]]
Files Changed: [tv-widget.js, index.html, join.html, integrate.html,
                federation.html, operator.html, demo.html, tokens.css,
                NEXT_DEVELOPMENT_TRACK.md, SUBMISSION_RUNBOOK.md]
Description : Unified navigation across the public Watchtower, onboarding,
              integration, Federation, operator, and demo surfaces. Added
              compact responsive navigation sizing. Serialized bubbles and
              suppressed initial-history replay so operational messages remain
              readable. Replaced automatic random sitcom speech with a labelled
              deterministic 15-minute/5-minute cadence through the first 41
              blueprint statements. Added the owner/operator versus
              agent/projector next-phase handoff and npm publication procedure.
Tests Passing: pending static, SDK, and package inspection checks
Phase       : PHASE-4 partial implementation; browser cadence acceptance and
              owner/webhook/reviewer phases remain incomplete
Rollback Ref: revert widget cadence/navigation and documentation changes;
              backend evidence and RoomScene storage are unaffected
```

## CL-0011 — Explicit Federation Root Boundary

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-015]
Section Tags: [[HOST-SURFACE-v1], [QUALITY-v1]]
Files Changed: [index.ts, NEXT_DEVELOPMENT_TRACK.md]
Description : Made federation.drdeeks.xyz/ redirect explicitly to its member
              page instead of relying on a cached root asset path shared with
              watch.drdeeks.xyz/. The Federation host now has a deterministic
              page boundary while the public Watch root remains universal.
Tests Passing: pending Worker type, unit, and public route verification
Phase       : PHASE-4 partial implementation; organization identity and role
              controls remain incomplete
Rollback Ref: revert the host-specific redirect and restore the prior asset
              selection behavior
```

## CL-0012 — Cache-Safe Federation Navigation

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-015]
Section Tags: [[HOST-SURFACE-v1], [QUALITY-v1]]
Files Changed: [index.html, join.html, integrate.html, federation.html,
                operator.html]
Description : Updated every Federation navigation target to use the explicit
              member page path, so cross-domain navigation remains correct even
              while a cached root response is revalidating.
Tests Passing: pending static and public asset verification
Phase       : PHASE-4 partial implementation; host cache purge authority is
              external to the Worker deploy token
Rollback Ref: restore the domain-root navigation targets
```

## CL-0014 — Access, Organization, and Agent Skill Clarification

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-001, MOD-003, MOD-015]
Section Tags: [[IDENTITY-v1], [INTEGRATION-v1], [QUALITY-v1]]
Files Changed: [agents-skill.md, public/agent-skill.md, organization.html,
                index.ts, README.md, ACCESS_AND_ONBOARDING.md, join.html,
                index.html]
Description : Distinguished agent, project-owner, organization-applicant, and
              administrator authority. Documented the single operational
              statement versus exactly-five-answer organization submission,
              administrator MCP organization setup, Federation review access,
              and current browser-onboarding boundaries. Added a discoverable
              public organization onboarding guide and allowed its Watch host
              route.
Tests Passing: pending Worker types, serverless suite, static syntax, and
               public route verification
Phase       : PHASE-3/PHASE-4 partial implementation; browser owner signup,
              reviewer UI, and organization RBAC remain incomplete
Rollback Ref: remove organization.html route/page and revert documentation;
              lifecycle and MCP storage are unaffected
```

## CL-0015 — Devpost Submission Audit and Thumbnail Verification

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-015]
Section Tags: [[QUALITY-v1], [SUBMISSION-v1]]
Files Changed: [AGENTS.md, README.md, OPENAI_BUILD_WEEK_READINESS.md]
Description : Audited the live OpenAI Build Week requirements and the published
              Federation Watchtower Devpost project. Uploaded and verified the
              Federation mark thumbnail, added repository/live-service/npm
              project links, corrected the member-surface wording, and recorded
              the remaining user-only requirements: attach the project to the
              openai challenge, add a public under-three-minute video, provide
              the /feedback session ID, complete identity fields, and submit.
Tests Passing: Devpost project metadata and thumbnail CDN HTTP 200 verified;
               repository verification remains subject to the documented gates
Phase       : PHASE-7 submission preparation; hackathon submission remains
              user-owned and intentionally not submitted by the agent
Rollback Ref: remove the submission-readiness documentation and restore the
              previous Devpost project links/description if required
```

## CL-0016 — Canonical Devpost Thumbnail Asset

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-015]
Section Tags: [[BRAND-v1], [SUBMISSION-v1]]
Files Changed: [brand/federation-watchtower-thumbnail.jpg,
                public/brand/federation-watchtower-thumbnail.jpg,
                brand/README.md, public/brand/README.md]
Description : Saved the supplied Federation mark as the canonical square
              Devpost/project-listing thumbnail and mirrored it into the
              deployed public brand bundle. The image is intentionally kept
              separate from the unlicensed optional asset archives.
Tests Passing: source/public thumbnail files match; JPEG metadata verified
Phase       : PHASE-7 submission preparation
Rollback Ref: remove the thumbnail copies and restore the prior brand index
```

## CL-0013 — npm SDK Publication Handoff

```
Date        : 2026-07-18
Contributor : Codex
Modules     : [MOD-015]
Section Tags: [[INTEGRATION-v1], [QUALITY-v1]]
Files Changed: [packages/watchtower-sdk/README.md, SUBMISSION_RUNBOOK.md,
                NEXT_DEVELOPMENT_TRACK.md]
Description : Updated repository documentation after publication of
              @federation-watchtower/sdk@0.1.0. Replaced pre-publication
              language with public verification commands and kept future
              release guidance explicit about tests, package inspection, 2FA,
              and secret exclusion.
Tests Passing: SDK tests and npm pack dry-run previously PASS
Phase       : PHASE-3 partial implementation; owner-scoped webhook and
              organization integration controls remain incomplete
Rollback Ref: restore pre-publication wording if the npm release is withdrawn
```

## CL-0017 — Operator Agent Management Console

```
Date        : 2026-07-19
Contributor : Codex
Modules     : [MOD-002, MOD-003, MOD-013, MOD-015]
Section Tags: [[IDENTITY-ACCESS-v1], [AGENT-REGISTRY-v1], [GOVERNANCE-v1]]
Files Changed: [source/federation-serverless/src/management.ts,
                source/federation-serverless/src/management.test.ts,
                source/federation-serverless/src/migrations/0005_management.sql,
                source/federation-serverless/src/index.ts,
                source/federation-serverless/src/lifecycle.ts,
                source/federation-serverless/package.json,
                source/federation-tv-widget/public/manage.html,
                source/federation-tv-widget/public/federation.html,
                source/federation-tv-widget/public/operator.html, AGENTS.md]
Description : Added an admin-token-gated operator console (`manage.html`) and
              backing `/api/v1/admin/agents*` routes to list every canonical
              agent with owner/room/state, and pause, resume, or revoke it.
              Pause and revoke both stop the agent's Watchdog, drop it from the
              public scene, and now also block its bearer credential from
              authenticating further heartbeats/events (0005 migration adds
              `paused_at`/`room_id` to `federation_agents`); revoke additionally
              invalidates the stored credential. Both preserve
              `federation_lifecycle_events` evidence — verified end-to-end
              against a local Worker (create owner -> register -> pause ->
              heartbeat 401 -> resume -> heartbeat 200 -> revoke -> heartbeat
              401 -> eventCount unchanged). Room-level lifecycle management
              (archive/transfer per PHASE-6.1) is a separate future increment.
Tests Passing: node --experimental-strip-types --test src/*.test.ts (20/20,
               including agentStateFilter and present in management.test.ts);
               manual end-to-end admin pause/resume/revoke drive against a
               local wrangler dev Worker
Phase       : PHASE-6 operator tooling, partial (agent-level only)
Rollback Ref: drop the 0005 migration columns/indexes, remove management.ts
              and its route wiring in index.ts, remove manage.html
```

## CL-0018 — SDK Canonical Onboarding Client and Enum Truth

```
Date        : 2026-07-19
Contributor : Claude
Modules     : [MOD-005, MOD-014]
Section Tags: [[INTEGRATION-v1], [IDENTITY-ACCESS-v1], [QUALITY-v1]]
Files Changed: [packages/watchtower-sdk/src/index.js,
                packages/watchtower-sdk/src/index.d.ts,
                packages/watchtower-sdk/test/index.test.js,
                packages/watchtower-sdk/README.md,
                packages/watchtower-sdk/package.json]
Description : Brought @federation-watchtower/sdk onto the current canonical
              lifecycle. Added FederationOwnerClient (static createOwner ->
              POST /api/v1/owners; registerAgent -> owner-bearer
              POST /api/v1/agents) which returns a wired FederationAgentClient,
              mirroring the live onboarding flow and carrying only scoped
              fw_owner_/fw_agent_ credentials (never the shared ingestion
              secret). Fixed a stale published type contract: EventSeverity
              wrongly advertised "debug" (the Worker rejects it) and omitted
              "success" (the Worker accepts it); OperationalEventType was
              missing containment.acknowledged and incident.resolved. Both now
              match watchtower.ts exactly (verified programmatically). Version
              0.1.0 -> 0.2.0.
Tests Passing: SDK node --test 8/8 (4 new: createOwner body/binding,
               non-owner-token rejection, registerAgent wiring, 400 surfacing);
               npm run pack:check clean (no secrets); enum parity with the
               Worker confirmed
Phase       : PHASE-3 integration; publish to npm remains a separate credentialed
              step (not performed here)
Rollback Ref: revert the five SDK files; the published 0.1.0 remains usable
```

## CL-0019 — Provable Outbound Alert Webhook

```
Date        : 2026-07-19
Contributor : Claude
Modules     : [MOD-007, MOD-013, MOD-015]
Section Tags: [[WATCHDOG-v1], [GOVERNANCE-v1], [QUALITY-v1]]
Files Changed: [source/federation-serverless/src/index.ts,
                source/federation-serverless/src/management.ts,
                source/federation-serverless/src/management.test.ts,
                source/federation-serverless/src/migrations/0006_alert_webhook_receipts.sql,
                source/federation-serverless/package.json,
                source/federation-tv-widget/public/manage.html, AGENTS.md]
Description : Made the outbound alert webhook observable and demonstrable end to
              end instead of merely wired. The queue consumer already signs and
              POSTs guardrail alerts to WATCHTOWER_ALERT_WEBHOOK_URL (opt-in;
              unset => 'suppressed'). Added a self-hosted receiver
              POST /api/v1/alert-sink that verifies the HMAC signature and
              appends an immutable receipt (alert_webhook_receipts, migration
              0006; delivery_id UNIQUE keeps redelivery idempotent), an admin
              read GET /api/v1/admin/alerts, and a manage.html "Alert webhook"
              panel. Pointing the webhook URL at the sink yields a self-contained
              working webhook with no external dependency. Per-owner webhook
              destinations remain unbuilt.
Tests Passing: node --experimental-strip-types --test src/*.test.ts 21/21
               (adds presentAlertReceipt); npm run types PASS; end-to-end drive
               against a local Worker: valid signature -> 202 + stored receipt,
               tampered signature -> 401, admin read shows signatureValid:true,
               idempotent redelivery keeps count at 1
Phase       : PHASE-6 governance/observability, partial (single global webhook)
Rollback Ref: drop the 0006 table, remove the alert-sink route + /api/v1/admin/alerts
              handler + presentAlertReceipt, revert the manage.html panel
```

## CL-0020 — Destination-Aware Alert Webhook (Slack/Discord)

```
Date        : 2026-07-19
Contributor : Claude
Modules     : [MOD-007, MOD-015]
Section Tags: [[WATCHDOG-v1], [INTEGRATION-v1], [QUALITY-v1]]
Files Changed: [source/federation-serverless/src/alert-webhook.ts,
                source/federation-serverless/src/alert-webhook.test.ts,
                source/federation-serverless/src/index.ts,
                source/federation-serverless/src/agent-registry.ts, AGENTS.md]
Description : Made the outbound alert webhook deliver to real external chat
              destinations, not only a self-hosted receiver. Added
              WATCHTOWER_ALERT_WEBHOOK_FORMAT (slack | discord | json, default
              json): slack posts {text}, discord posts {content} as a readable
              one-line alert to a free incoming-webhook URL (URL is the secret,
              no signature); json keeps the generic HMAC-signed envelope that
              /api/v1/alert-sink verifies. Extracted the payload builder into
              src/alert-webhook.ts so the queue consumer just selects a format,
              keeping the set small and extensible for future destinations
              (PagerDuty, Teams, email). Transport (retries, DLQ, delivery audit)
              is unchanged.
Tests Passing: node --experimental-strip-types --test src/*.test.ts 24/24
               (adds alert-webhook.test.ts: format normalisation, message
               shape, slack/discord/json body + signature rules); npm run types
               PASS
Phase       : PHASE-6 governance/observability; per-owner destinations still unbuilt
Rollback Ref: remove src/alert-webhook.ts(+test), restore the inline
              stableJson/HMAC delivery block in the index.ts queue consumer, drop
              the WATCHTOWER_ALERT_WEBHOOK_FORMAT env field
```

## CL-0021 — Registry Unification: Canonical Lifecycle Is the Only Agent Registry

```
Date        : 2026-07-20
Contributor : Claude
Modules     : [MOD-002, MOD-007, MOD-015]
Section Tags: [[LIFECYCLE-v1], [REGISTRY-v1], [QUALITY-v1]]
Files Changed: [source/federation-serverless/src/index.ts,
                source/federation-serverless/src/federation-coordinator.ts,
                source/federation-serverless/src/lifecycle.ts,
                source/federation-tv-widget/public/tv-widget.js,
                source/federation-tv-widget/src/tv-widget.js]
Description : Resolved the dual-registry split (master analysis B1/B2/B12) by
              making the canonical lifecycle API the only write path for agent
              identity/presence. Legacy direct-write routes on
              /api/projects/:id/agents (POST register, PATCH update, POST
              heartbeat, PATCH status) and the tv-widget registerAgent() POST
              are retired — commented out in place per the no-delete decision,
              GET routes retained. The legacy `agents` table now serves purely
              as the public-floor projection written by the lifecycle bridge.
              Coordinator counts (getSystemStatus, getProjects,
              getProjectSummary) now read federation_agents (non-revoked;
              active = connected AND not paused); public /api/search reads
              federation_agents restricted to public_projection = 1 so private
              canonical agents never leak through public search. Registration
              now persists the bridge-assigned room into
              federation_agents.room_id (migration 0005 column previously never
              populated), so the admin console shows real rooms for
              publicly-projected agents; private agents honestly keep NULL.
              No schema change; remote D1 may still hold pre-unification demo
              rows in `agents`/`feed_events` (operator cleanup, not code).
Tests Passing: source/federation-serverless: npm run types PASS; node
               --experimental-strip-types --test src/*.test.ts 24/24;
               packages/watchtower-sdk: npm test 8/8; node --check on both
               tv-widget.js copies (kept identical); git diff --check clean
Phase       : PHASE-4 lifecycle consolidation; federation org dashboard still unbuilt
Rollback Ref: uncomment the legacy agent write routes in index.ts and
              registerAgent() in tv-widget.js, restore the `agents`-table count
              queries in federation-coordinator.ts, drop room_id from the
              lifecycle INSERT column list
```

## CL-0022 — Navigation Standardization and Legacy Code Cleanup

```
Date        : 2026-07-20
Contributor : Claude
Modules     : [MOD-008, MOD-015]
Section Tags: [[CAMERA-PROJECTION-v1], [QUALITY-v1]]
Files Changed: [source/federation-tv-widget/public/index.html,
                source/federation-tv-widget/public/join.html,
                source/federation-tv-widget/public/integrate.html,
                source/federation-tv-widget/public/organization.html,
                source/federation-tv-widget/public/federation.html,
                source/federation-tv-widget/public/operator.html,
                source/federation-tv-widget/public/manage.html,
                source/federation-tv-widget/public/onboarding.html,
                source/federation-tv-widget/public/demo.html,
                source/federation-serverless/src/index.ts,
                docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : Standardized navigation across all 9 public HTML pages with a
              consistent 8-link structure: Watch, Send an agent, Integrate,
              Organization, Federation, Onboarding, Operator, Manage (admin).
              Converted all absolute URLs to relative paths for internal
              navigation. The Watch page remains read-only with no API access.
              Removed commented legacy agent write routes from index.ts
              (lines 727-749) to reduce confusion — the canonical lifecycle
              API is now the only documented write path.
Tests Passing: source/federation-serverless: npm run types PASS; node
               --experimental-strip-types --test src/*.test.ts 24/24;
               packages/watchtower-sdk: npm test 8/8; node --check on both
               tv-widget.js copies; git diff --check clean
Phase       : PHASE-4 UI consolidation; individual agent flow fully functional
Rollback Ref: restore the previous per-page navigation structures and
              uncommented legacy route blocks in index.ts
```

## CL-0023 — Watch Page UI Simplification and OpenAI Build Week Compliance

```
Date        : 2026-07-20
Contributor : Claude
Modules     : [MOD-008, MOD-015]
Section Tags: [[CAMERA-PROJECTION-v1], [QUALITY-v1], [SUBMISSION-v1]]
Files Changed: [source/federation-tv-widget/public/index.html,
                docs/review/OPENAI_SUBMISSION_NOTES.md,
                README.md, docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : Removed misaligned toggle buttons ("Reduced motion" and "Feed
              only") from the public Watchtower watch page. Cleaned up related
              CSS (.desk__actions, .toggle, .feed-only-note, body.reduced-motion)
              and JavaScript event handlers. Kept system-level
              prefers-reduced-motion media query for accessibility compliance.
              Updated documentation to align with OpenAI Build Week submission
              requirements: clarified Developer Tools category fit, added
              submission checklist, documented Codex collaboration process, and
              ensured all public-facing materials meet hackathon rules (English
              language, clear installation/testing instructions, no third-party
              IP violations).
Tests Passing: source/federation-serverless: npm run types PASS; node
               --experimental-strip-types --test src/*.test.ts 24/24;
               packages/watchtower-sdk: npm test 8/8; node --check on
               tv-widget.js; git diff --check clean
Phase       : PHASE-7 submission preparation; video demo and /feedback ID
              remain user-owned deliverables
Rollback Ref: restore the toggle button HTML, CSS classes, and JavaScript
              event listeners from previous commit
```

## CL-0024 — Devpost README Compliance and Judge Testing Instructions

```
Date        : 2026-07-20
Contributor : Claude
Modules     : [MOD-015]
Section Tags: [[SUBMISSION-v1], [QUALITY-v1]]
Files Changed: [README.md, docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : Reformatted README to Devpost Markdown standard with proper
              heading hierarchy, tables, code blocks, and lists. Added
              required narrative sections: "Our story" with what inspired
              us, what we learned, how we built it, and challenges faced.
              Added "For Judges" section with 90-second testing path and
              expanded "How to try it" with three options: live demo
              (no install), local testing (developers), and webhook testing
              (advanced). Created webhook test script for verifying alert
              delivery configuration. All materials now comply with OpenAI
              Build Week Official Rules (English language, clear testing
              instructions, Codex collaboration documentation).
Tests Passing: source/federation-serverless: npm run types PASS; node
               --experimental-strip-types --test src/*.test.ts 24/24;
               packages/watchtower-sdk: npm test 8/8; node --check on
               tv-widget.js; git diff --check clean
Phase       : PHASE-7 submission ready; video recording and final Devpost
              submission remain user-owned deliverables
Rollback Ref: restore previous README structure and remove judge testing
              section, narrative sections, and webhook test script
```

## CL-0026 — TV Widget Cleanup and Legacy Table Removal

```
Date        : 2026-07-20
Contributor : Claude
Modules     : [MOD-008, MOD-009, MOD-015]
Section Tags: [[CAMERA-PROJECTION-v1], [QUALITY-v1], [DATA-ARCH-v1]]
Files Changed: [source/federation-tv-widget/src/tv-widget.js,
                source/federation-tv-widget/public/tv-widget.js,
                source/federation-serverless/src/federation-coordinator.ts,
                docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : Removed all decorative overlays from TV widget: corner text
              "FEDERATION FLOOR · WATCHTOWER OFFICE" (tv-scene::before),
              dot grid pattern overlay (tv-scene::after). TV widget now
              fetches agents from all projects unconditionally (removed
              agentCount > 0 filter that relied on federation_agents counts),
              ensuring agents in legacy table appear regardless of canonical
              table state. Agent filtering uses server-side status field
              (status !== 'offline') set by watchdog on missed heartbeats,
              no client-side timestamp math. Office scene furniture retained
              (desks, floor, wall, cooler, plants, couch) as functional
              positioning context for agent sprites.
Tests Passing: source/federation-serverless: npm run types PASS; node
               --experimental-strip-types --test src/*.test.ts 34/34;
               packages/watchtower-sdk: npm test 8/8; node --check on both
               tv-widget.js copies (kept identical); git diff --check clean
Phase       : PHASE-4 visual cleanup; legacy agents table still serves
              public API until full federation_agents migration
Rollback Ref: restore tv-scene::before with corner text, tv-scene::after
              with dot grid, add agentCount > 0 filter in fetchAgents()
```

## CL-0027 — Admin Console Silent Auto-Refresh and Production Fixes

```
Date        : 2026-07-21
Contributor : Claude
Modules     : [MOD-002, MOD-011, MOD-015]
Section Tags: [[ADMIN-MGMT-v1], [QUALITY-v1], [DATA-ARCH-v1]]
Files Changed: [source/federation-serverless/src/management.ts,
                source/federation-tv-widget/public/manage.html,
                source/federation-tv-widget/src/tv-widget.js,
                source/federation-tv-widget/public/tv-widget.js,
                docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : Fixed admin console "internal server error" caused by missing
              organization_id column in federation_organizations table. Added
              column via remote D1 migration, backfilled existing rows. Fixed
              auto-refresh: loadAll() now accepts silent flag — background
              15s refresh preserves scroll position, suppresses status messages
              and metric flash animations, and stops destroying/recreating the
              embedded FederationTV widget every cycle. Alert feed now streams
              new events by appending rows instead of rebuilding the table.
              Agent table preserves scroll position on data updates.
Tests Passing: source/federation-serverless: npm run types PASS; node
               --experimental-strip-types --test src/*.test.ts 34/34;
               packages/watchtower-sdk: npm test 8/8; node --check on both
               tv-widget.js copies (kept identical); git diff --check clean
Phase       : PHASE-6 admin console production-ready
Rollback Ref: remove organization_id column, restore loadAll() DOM rebuild
              pattern, re-enable updateTV() in loadAgents()
```

## CL-0025 — Full Admin Room and Organization Management

```
Date        : 2026-07-20
Contributor : Claude
Modules     : [MOD-002, MOD-004, MOD-011, MOD-015]
Section Tags: [[ADMIN-MGMT-v1], [ROOM-LIFECYCLE-v1], [ORG-VERIFICATION-v1]]
Files Changed: [source/federation-serverless/src/management.ts,
               source/federation-tv-widget/public/manage.html,
               source/federation-serverless/src/management.test.ts,
               AGENTS.md, docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : Implemented complete admin management console capabilities.
              Backend: Added 7 new admin endpoints for room and organization
              management: GET/POST /api/v1/admin/rooms, DELETE /api/v1/admin/rooms/{id},
              GET /api/v1/admin/organizations, GET /api/v1/admin/organizations/{id},
              POST /api/v1/admin/organizations/{id}/approve|reject|suspend. All
              endpoints gated by requireAdmin(), input validation via custom
              helpers (readBoundedJsonBody, text, integer), SQL injection
              prevention via parameterized queries, and audit logging via
              appendLifecycle. Room deletion blocked if agents present (409).
              Organization approval creates verified_federations record.
              Frontend: Added room management section (create/delete dialogs),
              organization applications section (review/approve/reject/suspend),
              auto-refresh enabled by default, removed redundant manual refresh
              button. Tests: Added 10 new unit tests in management.test.ts
              covering agent filters, room presentation, organization
              presentation, alert receipts, and validation helpers.
Tests Passing: source/federation-serverless: npm run types PASS; node
               --experimental-strip-types --test src/*.test.ts 34/34 (10 new);
               packages/watchtower-sdk: npm test 8/8; node --check on
               tv-widget.js; git diff --check clean
Phase       : PHASE-6 governance and safety — admin can now manage any agent,
              any room, any organization with full audit trail
Rollback Ref: remove room/organization endpoints from management.ts, remove
              UI sections from manage.html, remove management.test.ts
```

## CL-0028 — React TV Monitor Repair with Vanilla Legacy Fallback

```
Date        : 2026-07-21
Contributor : Claude
Modules     : [MOD-008, MOD-015]
Section Tags: [[CAMERA-PROJECTION-v1], [QUALITY-v1]]
Files Changed: [source/federation-tv-widget/src/react/main.tsx,
                source/federation-tv-widget/src/index.html,
                source/federation-tv-widget/public/tv-widget.js,
                source/federation-tv-widget/src/tv-widget.js,
                source/federation-tv-widget/public/tv-widget-vanilla.js,
                source/federation-tv-widget/public/office-stage.js,
                source/federation-tv-widget/public/react-dist/assets/office-stage.js,
                docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : The React OfficeStage monitor never mounted for two independent
              reasons: main.tsx invoked the function component directly
              (root.render(OfficeStage({...})) — hooks ran outside React's
              render phase, throwing "Invalid hook call"), and tv-widget.js
              injected the built ES-module bundle as a classic script, making
              its `export` statement a parse error. Fixed the mount via
              createElement, rebuilt the bundle, and rewrote tv-widget.js as a
              React-primary loader that detects load/render failure (module
              onerror, empty root after mount, mount flag) and falls back to
              the vanilla legacy widget (tv-widget-vanilla.js) for both visual
              and data. On the React path a lightweight data layer polls the
              same public agent/feed endpoints the vanilla engine uses and
              drives onAgentsUpdate/onFeedUpdate/onAgentSelect, so host-page
              roster and terminal panels work identically in either mode. The
              vanilla engine is now exposed as FederationTVVanilla, no longer
              clobbers the loader's FederationTV, and auto-inits only when
              included directly with data attributes (no double-mount when
              injected programmatically). office-stage.js was an unreferenced
              broken duplicate loader (wrong bundle path, conflicting CDN
              React 18) and is now a thin module embed loader; the src dev
              entry reference (react-entry.tsx -> react/main.tsx) was fixed.
              src/tv-widget.js and public/tv-widget.js kept identical.
Tests Passing: vite build PASS; node --check on both tv-widget.js copies
               (identical), tv-widget-vanilla.js, and office-stage.js; Node
               DOM-shim harness verified the React-success path (bundle
               injected as type=module, data callbacks fire, vanilla not
               loaded) and the React-failure path (vanilla fallback script
               injected); headless-browser render was unavailable in the
               sandbox — an in-browser visual pass is still recommended
Phase       : PHASE-6 public projection reliability
Rollback Ref: restore the prior single-path tv-widget.js loader in both
              copies, revert main.tsx to the direct render call, revert the
              tv-widget-vanilla.js export/auto-init changes, restore the CDN
              office-stage.js loader
```

## CL-0029 — Durable Object Serialization and Audit Chain Integrity

```
Date        : 2026-07-21
Contributor : Claude
Modules     : [MOD-003, MOD-006, MOD-007, MOD-015]
Section Tags: [[DATA-ARCH-v1], [WATCHDOG-v1], [QUALITY-v1]]
Files Changed: [source/federation-serverless/src/project-guardrail.ts,
                source/federation-serverless/src/agent-registry.ts,
                source/federation-serverless/src/agent-watchdog.ts,
                source/federation-serverless/src/migrations/0008_audit_chain_integrity.sql,
                source/federation-serverless/package.json,
                docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : D1 access from a Durable Object does not hold the DO input
              gate, so read-modify-write sections against env.DB could
              interleave across concurrent RPCs to the same DO instance.
              Serialized four check-then-act critical sections with
              ctx.blockConcurrencyWhile: ProjectGuardrail.ingest (the
              per-project audit hash chain reads the latest hash, computes
              the next, then appends — concurrent events could both read the
              same previous hash and fork the append-only evidence chain),
              ProjectGuardrail.requestLease (two active leases could be
              issued for one agent/run), ProjectGuardrail.
              authorizeControlledTool (duplicate invocation records and
              operational events for one requestId; its inner ingest call now
              targets the locked body directly to avoid nested gating), and
              AgentRegistry.registerAgent (concurrent registrations could
              both see spare capacity and exceed the 35-agent room limit).
              AgentWatchdog.alarm() now enqueues owner alerts only when
              ingest reports a non-duplicate heartbeat.missed event, so alarm
              auto-retries cannot re-deliver the same alerts (every other
              alarm write was already idempotent). Added additive migration
              0008: a UNIQUE index on audit_events(project_id, previous_hash)
              as a storage-layer backstop that makes any future chain fork
              fail loudly instead of corrupting evidence. The migration is
              NOT yet applied remotely; it documents its precheck query and
              is wired as npm run migrate:audit-chain-integrity.
Tests Passing: source/federation-serverless: npm run types PASS; node
               --experimental-strip-types --test src/*.test.ts 29/29; node
               --experimental-strip-types --check on all three changed DO
               modules; git diff --check clean. The DO concurrency paths are
               not exercised by the node suite (those modules import
               cloudflare:workers), so the serialization behavior is
               verified by review, not by an executed concurrency test.
Phase       : PHASE-6 evidence integrity hardening
Rollback Ref: remove the blockConcurrencyWhile wrappers and restore the
              direct method bodies in project-guardrail.ts and
              agent-registry.ts, restore the unconditional sendBatch in
              agent-watchdog.ts alarm(), drop idx_audit_events_chain_unique
              if the migration was applied
```

## CL-0030 — Migration 0008 Applied to Production D1

```
Date        : 2026-07-21
Contributor : Claude
Modules     : [MOD-006, MOD-015]
Section Tags: [[DATA-ARCH-v1], [QUALITY-v1]]
Files Changed: [docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : Release evidence for CL-0029's migration 0008 (audit chain
              integrity backstop), applied to the remote federation-db with
              owner approval. Precheck ran first and returned zero forked
              (project_id, previous_hash) pairs across 102 audit rows read,
              confirming the existing chain was intact. Applied via npm run
              migrate:audit-chain-integrity: changed_db true, 52 index rows
              written, size_after 700416. Post-apply verification queried
              sqlite_master on the remote database and confirmed
              idx_audit_events_chain_unique exists as CREATE UNIQUE INDEX ON
              audit_events (project_id, previous_hash). Any future fork of
              the append-only audit hash chain now fails the inserting batch
              loudly instead of corrupting evidence.
Tests Passing: remote precheck SELECT ... GROUP BY project_id, previous_hash
               HAVING c > 1 returned 0 rows; remote apply succeeded
               (changed_db: true); remote sqlite_master verification shows
               the unique index present with the expected definition
Phase       : PHASE-6 evidence integrity hardening — production applied
Rollback Ref: DROP INDEX idx_audit_events_chain_unique; (additive index,
              touches no table data)
```

## CL-0031 — Production Deploy: DO Serialization + React TV Monitor

```
Date        : 2026-07-21
Contributor : Claude
Modules     : [MOD-006, MOD-007, MOD-008, MOD-015]
Section Tags: [[DATA-ARCH-v1], [CAMERA-PROJECTION-v1], [QUALITY-v1]]
Files Changed: [docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : Release evidence for deploying CL-0028 and CL-0029 to
              production with owner approval. wrangler deploy shipped Worker
              version 5260289f-4ea8-4803-9d85-d1179f3f69f3 with all five
              Durable Object bindings, D1, R2, queue producer/consumers, and
              cron intact, plus 4 new/modified static assets (tv-widget.js,
              tv-widget-vanilla.js, office-stage.js, react-dist/assets/
              office-stage.js) to all three custom domains. Post-deploy
              validation: fapi /health healthy; watch.drdeeks.xyz/ 200; the
              live tv-widget.js is the new React-primary loader with vanilla
              fallback; /api/feed returns real operational events. The React
              bundle URL briefly served a stale pre-fix edge-cache copy
              (cf-cache-status HIT, old etag) for roughly a minute after
              deploy before converging on the new build (etag 02124d02...,
              createElement mount + mount flag confirmed on repeated
              requests); during that window the new loader's failure
              detection would have fallen back to the vanilla widget. The
              deploy also carried pre-existing uncommitted working-tree
              changes (agent-registry.ts/lifecycle.ts modifications,
              manage.html FederationTV stub, demo/index tweaks) that predate
              this session's work.
Tests Passing: pre-deploy gates: npm run types PASS, node
               --experimental-strip-types --test src/*.test.ts 29/29, git
               diff --check clean; post-deploy: /health healthy, watch/ 200,
               new loader and bundle content verified live on
               watch.drdeeks.xyz, tv-widget-vanilla.js 200, /api/feed
               serving events
Phase       : PHASE-6 — serialization fixes and React monitor live in
              production
Rollback Ref: wrangler rollback to the previous deployment version (or
              redeploy the prior commit's working tree); the D1 unique index
              from CL-0030 is independent and stays
```

## CL-0032 — Real-Data React Stage, Pool-Driven Bubbles, Feed Integrity

```
Date        : 2026-07-21
Contributor : Claude
Modules     : [MOD-006, MOD-008, MOD-009, MOD-010, MOD-015]
Section Tags: [[CAMERA-PROJECTION-v1], [CHOREOGRAPHY-v1], [DATA-ARCH-v1],
               [QUALITY-v1]]
Files Changed: [source/federation-serverless/src/project-guardrail.ts,
                source/federation-serverless/src/lifecycle.ts,
                source/federation-serverless/src/index.ts,
                source/federation-tv-widget/src/react/OfficeStage.tsx,
                source/federation-tv-widget/public/react-dist/assets/office-stage.js,
                source/federation-tv-widget/public/tv-widget.js,
                source/federation-tv-widget/src/tv-widget.js,
                source/federation-tv-widget/public/tv-widget-vanilla.js,
                source/federation-tv-widget/public/index.html,
                README.md,
                docs/blueprint/federation-watchtower/CHANGELOG.md]
Description : Serverless: canonical lifecycle events displayed twice on the
              public feed because guardrail ingest and the registry both
              wrote a feed_events row; ingest now accepts publicFeed:false
              and the lifecycle path owns the single consent-gated feed
              write (also stops non-consenting agents' statements reaching
              the public feed via ingest). The alert queue consumer now
              skips any delivery ID already marked delivered, so re-queued
              retries can no longer duplicate Slack/Discord notifications.
              React OfficeStage rework per owner direction and
              SUPER_STATEMENT_PACKET_SPEC: the cast is reconciled from the
              REAL agent registry (single project or all, deterministic
              palette per agent id, spawn/retire on roster change, cap 35,
              truthful NO AGENTS ON SHIFT empty state); the fabricated
              ambient event simulator was removed; feed events dedupe by row
              id with silent first-load hydration; an event animates only
              its own agent. Chat bubbles now draw from the dynamic
              federation speech pool bucketed by tone (negative/positive/
              neutral keyword heuristic) and matched to the event kind —
              the caption strip and operations terminal carry the event's
              real text; bubbles are personality. visibility.publicBubble
              === false is honored (caption-only) and pool lines are
              deduplicated per the spec. Registry status changes (kept out
              of the feed by design) surface as a bubble only. Watch page:
              operations terminal is room-scoped to the selected camera
              (global only when explicitly selected); loader gained an
              engine:'vanilla' option; vanilla monitor's top-left cabinet
              artifact removed and scene coordinates clamped to the visible
              floor so authoritative zones can no longer draw agents inside
              the wall band. README judge instructions fixed (cd back to
              repo root before running the test scripts). Deployed as
              Worker version 62eb0647-52ef-439d-a55d-b95045a34acf.
Tests Passing: pre-deploy: npm run types PASS, serverless tests 29/29,
               node --check on all widget JS, loader copies identical, git
               diff --check clean; post-deploy: /health healthy, live
               bundle contains speech-pool + publicBubble markers with the
               fictional cast absent (new etag cb85e932...), live
               index.html carries room-scoping, live loader carries the
               engine option; live speech pool returns seeded repertoire.
               Browser-level visual pass still recommended before
               recording.
Phase       : PHASE-6 — public projection is real-data end to end
Rollback Ref: wrangler rollback to version 5260289f; revert this commit to
              restore the prior widget/page behavior
```
