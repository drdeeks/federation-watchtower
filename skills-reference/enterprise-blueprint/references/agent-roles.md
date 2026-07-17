# Agent Roles Reference

Role taxonomy, delegation patterns, assignment governance, load-balancing
rules, and the measurement framework for tracking agent performance across
blueprint implementation phases.

## Table of Contents

1. [Role Taxonomy](#1-role-taxonomy)
2. [Scope Types](#2-scope-types)
3. [Assignment Governance](#3-assignment-governance)
4. [Delegation Patterns](#4-delegation-patterns)
5. [Load Balancing Rules](#5-load-balancing-rules)
6. [Measurement Framework](#6-measurement-framework)
7. [Multi-Agent Coordination](#7-multi-agent-coordination)
8. [Escalation Procedures](#8-escalation-procedures)

---

## 1. Role Taxonomy

Every agent assigned to a blueprint scope carries a primary role. Roles
define the domain of responsibility and the types of deliverables the
agent is accountable for. An agent may carry at most two roles on a
single project — primary and secondary. A third role requires a formal
scope split.

| Role | Primary Domain | Owns in Blueprint |
|---|---|---|
| **Architect** | System design and structural decisions | Part I (vision, architecture), Part II (module registry) |
| **Backend** | Server logic, APIs, database | Part IV schemas, Part III API specs, migration files |
| **Frontend** | UI components, screens, interactions | Part III screen specs, all client-side components |
| **Blockchain** | Smart contracts, on-chain logic, wallet integration | Contract specs in Part III, on-chain data in Part IV |
| **AI Integration** | LLM APIs, prompt management, content pipelines | AI feature specs in Part III, prompt config in Part IV |
| **QA** | Test coverage, E2E suite, performance budgets | Part VII testing requirements, all test files |
| **DevOps** | CI/CD, feature flags, monitoring, deployment | Part V contributor rules, pipeline configuration |
| **Security** | Auth flows, payment security, compliance, audits | Auth specs in Part III, GDPR items in Part VII |
| **Agent (AI)** | Autonomous implementation within assigned scope | Same domains as above; operates without human hand-holding |

**Agent vs. human distinction:** An agent assigned to a scope operates
autonomously and produces deliverables without per-step human direction.
It reads the relevant blueprint section and checklist items as its spec,
produces the implementation, writes the change log entry, and updates the
assignment status. Human contributors follow the same rules but may
require clarification interactions.

---

## 2. Scope Types

A scope is the unit of assignment. Every scope maps to exactly one entry
in `assignments.json`. Two scope types exist:

**Phase scopes** (`PHASE-N`): Cover all work within a single implementation
phase. Recommended for focused, sequential phases where one agent or team
owns the entire phase deliverable.

**Module scopes** (`MOD-NNN`): Cover a specific module's implementation
across all phases. Recommended when a module spans multiple phases and
benefits from a single owner who maintains context across the full lifecycle.

**Choosing between them:** Use phase scopes when phases are largely
independent (infrastructure, then auth, then features). Use module scopes
when modules are deeply interdependent across phases (e.g., an auth module
that evolves across every phase). Never assign the same scope twice — if
both a phase scope and a module scope are assigned, the module scope takes
precedence for the overlapping work.

---

## 3. Assignment Governance

**Pre-assignment requirements:**

Before assigning any agent to a scope, the following must be true. These
are not optional: an unmet prerequisite invalidates the assignment.

1. The scope (phase or module) must exist and be defined in the blueprint.
2. The blueprint section corresponding to the scope must have a valid
   rollback tag applied.
3. The feature flag for the scope must exist in the feature flag system.
4. `project.json` must reflect the current phase structure.

**Assignment immutability:** Once a phase is marked `COMPLETE`, its
assignment record is permanent. The agent field, completion timestamp,
and sign-off block are read-only. If the phase is re-opened (via an
amendment), a new assignment record is created for the amended scope.

**Transfer of assignment:** If an agent must be replaced mid-scope, the
outgoing agent must write a handoff note appended to `assignments.json`
under a `handoff_notes` field for that scope. The new agent reads the
handoff note before beginning work. The change log must record the
transfer under a `Files Changed` entry for `assignments.json`.

---

## 4. Delegation Patterns

### Pattern: Phase Owner with Module Specialists

One agent owns the phase (responsible for the change log entry and the
phase sign-off). Multiple specialists own individual modules within the
phase. The phase owner coordinates, integrates, and validates; the
specialists implement.

```
PHASE-3 Owner: AlphaAgent (Backend)
  MOD-005 → BetaAgent (Frontend)
  MOD-009 → GammaAgent (Blockchain)
  MOD-011 → AlphaAgent (Backend, retained)
```

**Best for:** Phases with heterogeneous technical requirements.

### Pattern: Single Agent Full-Phase

One agent owns the full phase scope, all modules within it, and the
sign-off. Appropriate when the phase is technically homogeneous or when
the agent has cross-domain capability.

**Best for:** Foundation phases (infrastructure, schema creation) and
single-concern phases (pure API layer, pure frontend).

### Pattern: Parallel Module Tracks

Multiple agents work simultaneously on independent modules. The phase
is only marked `COMPLETE` when all parallel module scopes are marked
`COMPLETE`. The phase sign-off is co-signed by all module owners.

**Best for:** Phases with genuinely independent parallel workstreams (e.g.,
blockchain contract deployment and frontend build can proceed simultaneously).
Requires careful dependency mapping to confirm modules are truly independent
before assigning parallel tracks.

### Pattern: AI Agent Autonomous Track

An AI agent is assigned a scope and operates autonomously: reads the
blueprint and checklist, implements, writes the change log, and marks
completion. A human reviewer validates the sign-off before the gate
closes. The human reviewer is recorded in the sign-off block.

**Best for:** Well-specified, bounded scopes with clear validation criteria
and comprehensive test coverage that allows the agent's output to be
objectively evaluated.

---

## 5. Load Balancing Rules

**Overload threshold:** An agent carrying more than 4 active scopes
simultaneously is considered overloaded. The `assign_agents.py --metrics`
command flags this automatically.

**Load distribution targets:**

| Phase Count | Recommended Agent Count | Max Scopes per Agent |
|---|---|---|
| 1-3 phases | 1-2 agents | 3 |
| 4-6 phases | 2-4 agents | 4 |
| 7-10 phases | 3-6 agents | 4 |
| 11+ phases | 5+ agents | 4 |

**Redistribution trigger:** If any agent is overloaded and a BLOCKED scope
exists, redistribution is mandatory. Run `assign_agents.py --metrics` and
follow the recommendations to split the overloaded agent's scopes before
unblocking proceeds.

**Specialization preservation:** When redistributing, preserve role
specialization. Do not assign a Frontend agent to a Blockchain scope
simply to balance load — the correct response is to bring in a Blockchain
specialist or reduce the scope by deferring non-critical items to a later
phase.

---

## 6. Measurement Framework

The measurement framework produces three categories of metrics. All are
computable from `assignments.json` using `assign_agents.py --metrics`.

### Completion Metrics

**Completion rate:** `completed_scopes / total_scopes × 100`. The
primary headline metric. Reported as a percentage.

**Phase completion sequence:** Are phases completing in order? Out-of-order
completions (e.g., Phase 3 complete while Phase 2 is blocked) indicate
either a scoping error or a gate violation.

### Velocity Metrics

**Completion velocity:** `completed_scopes / elapsed_days`. Indicates
the pace of implementation. Baseline this in Phase 1 to use as a
forecasting reference for subsequent phases.

**Scope age:** How long each incomplete scope has been in `in_progress`
status. Scopes older than twice the project's average phase duration are
flagged as stale and require a status update or reassignment.

### Bottleneck Metrics

**Agent overload indicator:** Any agent carrying more than 4 active scopes.
Surfaced by `--metrics` with a redistribution recommendation.

**Blocked scope count:** Any scope in `blocked` status. Every blocked scope
requires an active resolution plan documented in its `assignments.json`
`notes` field.

**Unassigned scope count:** Scopes that have no assigned agent. Every
unassigned scope blocks the phase it belongs to from starting.

---

## 7. Multi-Agent Coordination

When multiple agents work on the same project simultaneously, three
coordination rules apply unconditionally.

**Rule 1 — Scope isolation:** Agents do not work on the same scope
simultaneously. If a scope requires two agents, it must be split into
two distinct sub-scopes with clearly defined boundaries before any
implementation begins.

**Rule 2 — Change log serialization:** Change log entries are written
sequentially. If two agents complete work simultaneously, their entries
are numbered in the order their PRs merge. No two entries share a CL
number.

**Rule 3 — Gate arbitration:** When a phase gate requires sign-off from
multiple agents (parallel track pattern), all sign-offs must be recorded
before the phase status transitions to `COMPLETE`. A partial sign-off
does not constitute completion.

**Conflict resolution:** If two agents produce conflicting implementations
for adjacent scopes, the Architect role resolves the conflict. The
resolution is documented in a change log entry citing both conflicting
CL entries and the resolution decision.

---

## 8. Escalation Procedures

### Scope Blocked

1. The assigned agent sets scope status to `blocked` in `assignments.json`.
2. Agent appends a `blocker_description` to the scope's notes field with:
   what is blocked, why it is blocked, and what is needed to unblock.
3. If the blocker is a dependency on another scope: the dependent scope's
   agent is notified. The blocking scope is prioritized.
4. If the blocker is an ambiguity in the blueprint: the Architect role
   issues a blueprint amendment to resolve the ambiguity. Implementation
   does not proceed on ambiguous specifications.
5. If the blocker persists for more than the project's average phase
   duration: a formal reassignment review is conducted.

### Agent Non-Responsive

If an assigned agent does not update its scope status for more than the
project's average phase duration, the scope is flagged as stale. The
project Architect initiates a handoff procedure: the current agent's
partial work is documented in a handoff note, the scope is reassigned,
and a change log entry records the transition.

### Gate Violation

If a phase gate is bypassed (implementation begins before pre-phase gate
items are all checked, or a phase is marked complete before its validation
gate is satisfied), this constitutes a gate violation. Gate violations
require a corrective change log entry, a retrospective review of what
produced the bypass, and a process note appended to the relevant phase
block in the checklist documenting the violation and corrective action.
Gate violations are never silently resolved.
