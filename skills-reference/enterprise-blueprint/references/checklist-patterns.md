# Checklist Patterns Reference

Design patterns for writing, generating, and maintaining enterprise enforcement
checklists that coexist with technical blueprints. Covers item anatomy, phase
structure, sync rules, and quality standards.

## Table of Contents

1. [Coexistence Model](#1-coexistence-model)
2. [Checklist Item Anatomy](#2-checklist-item-anatomy)
3. [Phase Block Structure](#3-phase-block-structure)
4. [Gate Patterns](#4-gate-patterns)
5. [Step Writing Standards](#5-step-writing-standards)
6. [Sync Rules](#6-sync-rules)
7. [Status Lifecycle](#7-status-lifecycle)
8. [Common Anti-Patterns](#8-common-anti-patterns)

---

## 1. Coexistence Model

The checklist and the blueprint are two views of the same system. The
blueprint defines what the system is. The checklist enforces how it gets
built. They must be version-matched at all times.

**Coexistence rules:**

- Blueprint version N.N maps exactly to Checklist version N.N.
- When the blueprint is amended, the checklist must be updated in the
  same commit. No exceptions.
- A checklist item may not describe behavior that contradicts its
  corresponding blueprint section.
- The checklist may be more granular than the blueprint (more steps per
  phase), but it may not be less granular (omitting required phases).
- Checked items (`[x]`) are permanent. If a checked item must be reversed
  (e.g., a rollback occurred), a new unchecked item is added below it with
  an explanation. The checked item is never unchecked.

**File placement:**

```
project-name/
├── blueprint.md        ← authoritative specification
├── checklist.md        ← enforcement companion
├── project.json        ← phase registry and metadata
└── assignments.json    ← agent assignments per scope
```

Both files live in the same directory and are committed together.

---

## 2. Checklist Item Anatomy

Every checklist item follows this five-field anatomy. All fields are
optional except the label, but well-formed items include all five.

```markdown
- [ ] **Label** (imperative verb phrase — what must be done)
  _Detail: one sentence elaborating on the constraint or scope._
  - _Example:_ Concrete command, file path, or output that demonstrates completion.
  - _Validation:_ The specific test, check, or observable result that proves this is done.
  - _Rollback:_ What to execute or revert if this step must be undone.
```

**Label rules:**
- Must be an imperative verb phrase: "Create the migration", not "Migration created".
- Must be specific enough that two different engineers implement it identically.
- Must be ≤ 80 characters.
- Must not be "Step N" alone — that is a container, not an actionable item.

**Validation field rules:**
- Must reference a named test, a CLI command with expected output, or an
  observable system state (e.g., "Feature flag dashboard shows FEAT_X = true").
- "Works correctly" is not a valid validation. Define what correct means.
- The validation must be independently verifiable without context from the
  person who performed the step.

**Rollback field rules:**
- Must reference a specific file, command, or flag change.
- "Revert the change" is not a valid rollback. Name the file or migration.
- If the rollback is "N/A — append-only", state that explicitly.

---

## 3. Phase Block Structure

Every phase block in the checklist must contain exactly these six sections
in this order. Sections may not be reordered or omitted.

```markdown
## Phase N — Phase Title

[Metadata block: section tag, feature flag, status, assigned agent, prerequisite]

### Pre-Phase Gate
[Items that must be verified TRUE before any work on this phase begins]

### Implementation Steps
[Ordered, granular steps — each with label, detail, example, validation, rollback]

### Screen & Feature Verification (if applicable)
[One item per screen or feature spec defined in Part III for this phase]

### Phase Validation Gate
[Items that must ALL be true before this phase status is set to COMPLETE]

### Agent Sign-Off
[Name, date, commit hash, notes block — completed by the responsible agent]
```

**Metadata block format:**

```markdown
**Section Tag:** `[PHASE-N-v1]` | **Feature Flag:** `FEAT_PHASE_NAME`
**Status:** `NOT STARTED` | **Assigned Agent:** _unassigned_
**Prerequisite:** Phase N-1 must be `COMPLETE` with change log entry written.
```

The Status field is one of four values only: `NOT STARTED`, `IN PROGRESS`,
`BLOCKED`, `COMPLETE`. No custom statuses. The agent updates this field
as work progresses. It is the only mutable field in the metadata block
without requiring a new change log entry.

---

## 4. Gate Patterns

Gates are decision points that block progress if any item is unchecked.
Three gate types exist in the enterprise checklist.

### Pre-Phase Gate

Blocks entry into a phase. All items must be checked before any
implementation work begins. Standard pre-phase gate items:

- Prior phase change log entry written and appended.
- Prior phase CI tests passing (green).
- Feature flag for this phase created and set to `disabled` in production.
- Database migration rollback files prepared for this phase.
- Agent assignment confirmed in `assignments.json`.

These five items appear in every phase gate, verbatim. Phase-specific
gate items may be added after the standard five.

### Phase Validation Gate

Blocks marking a phase `COMPLETE`. All items must be true simultaneously:

- All implementation steps checked.
- All phase tests passing in CI.
- Feature flag confirmed enabled on staging, disabled in production.
- Change log entry written and appended.
- Blueprint updated to reflect any deviations.
- Assigned agent has signed off.
- No p95 performance budget violations logged.

### Global Completion Gate

At the end of the checklist. Blocks declaring the project production-complete.
Every phase must be `COMPLETE`. All flags must be enabled in production.
Performance, security, and compliance criteria must all pass.

---

## 5. Step Writing Standards

### The Verb-First Rule

Every step label begins with an action verb in the imperative mood:

| Weak (avoid) | Strong (use) |
|---|---|
| Database migration | Create the database migration for `agents` table |
| Feature flag | Create feature flag `FEAT_AGENT_REGISTRY` and set to `disabled` |
| Tests | Write integration tests for `POST /api/v1/agents` |
| Deployment | Deploy to staging and run the smoke test suite |

### The Specificity Rule

Steps must be specific enough to be unambiguous, not so specific that they
become instructions for a single codebase configuration. Good specificity:

- Names the file type, not the filename (unless the filename is canonical).
- Names the test category, not every test name.
- Names the expected observable output, not the internal implementation.

### Ordering Rule

Steps within a phase must be ordered to reflect actual dependency:
infrastructure → API → feature logic → flag enable → change log. A step
may not require a later step to have been completed first.

### Granularity Rule

Each step should represent approximately one to four hours of work.
If a step would take longer, break it into sub-steps. If a step takes
less than fifteen minutes, consider merging it with an adjacent step.
Checklists are not task trackers — they are enforcement documents.

---

## 6. Sync Rules

When `generate_checklist.py --sync` is run after a blueprint amendment:

**Added phases** (in blueprint but not in checklist): A new phase block is
inserted at the correct ordinal position. Existing phase blocks are not
moved or modified.

**Modified phase titles** (title changed in blueprint): The phase block
header is updated. All items within the block are preserved unchanged.

**Removed phases** (deleted from blueprint): The phase block is NOT removed
from the checklist. A strikethrough note is prepended:
`> ~~This phase was removed from blueprint.md in amendment CL-NNN.~~`
Completion history is preserved.

**New screens/features added to Part III**: If the phase containing those
specs is not yet `COMPLETE`, the Screen & Feature Verification section
for that phase gains a new unchecked item. If the phase is already `COMPLETE`,
a correction entry is added to the change log and the item is added with
a note: `(Added post-completion — verify and re-gate if necessary)`.

**Checked items** are never modified by sync. The `--sync` operation only
adds; it never removes or modifies existing content.

---

## 7. Status Lifecycle

```
NOT STARTED → IN PROGRESS → COMPLETE
                 ↓
              BLOCKED → IN PROGRESS → COMPLETE
```

**Rules for each transition:**

| From | To | Who | Requirement |
|---|---|---|---|
| NOT STARTED | IN PROGRESS | Assigned agent | Pre-phase gate all checked |
| IN PROGRESS | BLOCKED | Assigned agent | Note explaining the blocker appended |
| BLOCKED | IN PROGRESS | Assigned agent | Blocker resolved; note appended |
| IN PROGRESS | COMPLETE | Assigned agent | Phase validation gate all checked; sign-off block filled |
| COMPLETE | (any) | N/A | Cannot revert — a rollback creates a new phase entry |

A phase status of `COMPLETE` is permanent. If a rollback occurs that
invalidates a completed phase, the blueprint and checklist are amended
(via the formal amendment procedure) to add a new phase representing the
re-implementation work. The original completed phase record is preserved.

---

## 8. Common Anti-Patterns

### The Vague Step

```
- [ ] **Set up authentication**
```

Fix: Break into concrete steps. "Implement `POST /api/v1/auth/connect`
with Reown session creation", "Write unit test: `auth.connect.valid-wallet-
returns-jwt`", "Enable `FEAT_AUTH` on staging".

### The Untestable Validation

```
- [ ] **Deploy the API**
  - _Validation:_ Looks good.
```

Fix: "All smoke tests pass; `GET /api/v1/health` returns `{success: true}`
from the staging URL."

### The Missing Rollback

```
- [ ] **Run database migration**
  - _Rollback:_ Undo it.
```

Fix: "Execute `db/migrations/20260601_001_ROLLBACK.sql`; verify schema
returns to prior state on a staging database."

### The Checked-Item Erasure

Never uncheck a checked item. If a rollback occurred, add:
```
- [x] **Create migration for `agents` table** ~~(rolled back — see CL-007)~~
- [ ] **Re-create migration for `agents` table** (post-rollback, v2 schema)
```

### The Orphaned Phase

A phase that appears in the checklist but has no corresponding phase in
the blueprint. Resolve by either adding the phase to the blueprint or
marking it deprecated in the checklist via a sync operation.
