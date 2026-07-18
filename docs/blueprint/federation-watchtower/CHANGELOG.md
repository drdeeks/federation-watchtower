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
