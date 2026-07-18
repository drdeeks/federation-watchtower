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
