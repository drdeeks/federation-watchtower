---
name: loop-enforcer
description: Enforce sequential dependency chains on files, tasks, and services. Locks
  steps until prior work is verified complete. Interactive menu + agent API. Prevents
  destructive ops by enforcing additive-only builds with chained verification gates.
  Use when building projects where files must be created in order, or when agents
  must not destroy existing work.
version: 1.0.14
license: MIT
metadata:
  openclaw:
    version: '1.0'
    category: devops
    complexity: enterprise
  openai:
    type: function
    parameters:
    - name: command
      type: string
    - name: project_dir
      type: string
    - name: chain_name
      type: string
  hermes:
    category: devops
  tags:
  - chain enforcement
  - file locking
  - sequential dependencies
  - verification gates
  - destructive prevention
  - additive builds
  - audit logging
---

# Loop Enforcer

Sequential dependency chain enforcement. Locks files until prior steps are verified. Prevents agents from touching work they shouldn't. Logs everything.

## Provider Compatibility

| Provider | Compatibility | Notes |
|---|---|---|
| Hermes Agent | Full | Native skill, all features |
| OpenAI | Full | Python stdlib only, any runtime |
| Claude | Full | No provider-specific deps |
| Gemini | Full | Platform agnostic |
| Local | Full | No network required |

## Free-First Strategy

| Cost Tier | Approach |
|---|---|
| Free | All features — Python stdlib only, no pip installs, no API calls |
| Paid | None required |

Zero cost. Everything runs locally with Python stdlib.

## Core Stack

| Component | Role | Cost | Free Alternative |
|---|---|---|---|
| chain.py | Core enforcement engine | Free | N/A |
| chain_report.py | Status reporter | Free | N/A |
| validate.py | Step validator | Free | N/A |
| JSON state | Persistence | Free | N/A |

## Workflow: Sequential Chain Enforcement

1. **Create chain**: `chain.py create <project> <name> <file1> <file2> ...`
2. **Agent checks**: `chain.py check <project> <name> <file>` — returns state
3. **If active**: Write the file → verify → complete → next unlocks
4. **If locked**: Stop. Do not touch.
5. **All logged**: Timestamped audit trail in `.chain/<name>.log`

### Step States

```
locked → active → pending_verify → verified → complete
                  ↑                     |
                  └─── (retry) ─────────┘
```

### Interactive Menu

```bash
chain.py menu <project> <name>
```

Commands: `[v]erify` `[c]omplete` `[s]tatus` `[l]og` `[a]dd` `[q]uit`

## Scripts

| Script | Purpose |
|---|---|
| `scripts/chain.py` | Core engine — create, check, verify, complete, set-validator, add, list, status, log, menu |
| `scripts/chain_report.py` | Human-readable chain status with progress bar |
| `scripts/validate.py` | Unified validator — file exists, non-empty, min lines/chars, required/forbidden patterns, syntax check, custom checks, spec file |
| `scripts/chain_audit.py` | Audit and compliance reporter — integrity checks, verification gaps, timeline analysis |
| `scripts/chain_migrate.py` | Chain migration tool — export/import, version upgrades, cross-project sync |

## Templates

| Template | Purpose |
|---|---|
| `templates/validator-spec.json` | Example validator spec with all checks enabled — copy and modify for your chain steps |

## Enforced Output Statistics

All commands return JSON:

```json
{
  "ok": true,
  "chain": "my-chain",
  "steps": 9,
  "active": 1,
  "locked": 8,
  "verified": 0,
  "complete": 0
}
```

Check response:
```json
{
  "path": "/path/to/file.js",
  "state": "active",
  "index": 0
}
```

Verify response:
```json
{
  "ok": true,
  "path": "/path/to/file.js",
  "state": "verified",
  "output": "OK: file.js (Syntax OK (node))\n"
}
```

## Error Handling

| Error | Cause | Fix |
|---|---|---|
| `Chain not found` | Wrong name or dir | Check `chain.py list` |
| `Path not in chain` | File not registered | `chain.py add` it |
| `Step is locked` | Prior step incomplete | Complete prior step first |
| `Step must be verified` | Skipped verification | Run `chain.py verify` first |
| `Validator failed` | File doesn't meet criteria | Fix file, retry verify |

## Kanban Worker Integration (MANDATORY for Phased Tasks)

When a kanban worker is assigned a phased task (title contains "Phase"), the loop-enforcer chain MUST be checked before ANY work begins. This is wired into KANBAN_GUIDANCE step 2b.

### Helper Script: chain_enforce.py

A wrapper that finds the chain, resolves the phase step, and calls chain.py:

```bash
# Check if phase is active (exit 0 = proceed, exit 1 = blocked)
python3 <HEMLOCK_HOME>/scripts/chain_enforce.py check <project> <phase_num>

# Verify + complete phase after work is done
python3 <HEMLOCK_HOME>/scripts/chain_enforce.py complete <project> <phase_num>

# Show chain status for a project
python3 <HEMLOCK_HOME>/scripts/chain_enforce.py status <project>
```

**chain_enforce.py searches for chains in this order:**
1. `.crew-*/.blueprint-chain/` (highest priority — crew-manager chains)
2. `.blueprint-chain/` (standard location)
3. `.chain/` (fallback)

This means crew-manager.py creates chains in `.crew-<name>/.blueprint-chain/` and chain_enforce.py finds them automatically.

### Worker Flow

1. Worker receives task: "Autopilot: Phase 2 — Workflow Orchestration"
2. Worker runs: `chain_enforce.py check autopilot 2`
3. If `can_proceed: true` → do the work
4. If `can_proceed: false` → `kanban_block(reason="Chain locked: prior phase not complete")`
5. After work: `chain_enforce.py complete autopilot 2`
6. Log: `kanban_comment(body="Chain enforced: autopilot-blueprint step 2 verified+complete")`

### Common Failure: Out-of-Order Phase Execution

If kanban tasks are dispatched without chain checks, phases run simultaneously and the chain state becomes meaningless. All phases must execute sequentially — Phase 0 complete → Phase 1 active → Phase 1 complete → Phase 2 active, etc.

**Fix:** Reset all phase tasks to `ready`, reset chain state (step[0]=active, rest=locked), and ensure KANBAN_GUIDANCE step 2b is present in the worker prompt.

### Project Directory Mapping

Projects live in `<WORKSPACE_ROOT>/qwen-cloud-2026/<project>/`. Symlinks at the workspace root provide convenient access. Each project has `.chain/<project>-blueprint.json` (or `blueprint-<project>.json`).

---

## Kanban Deployment for Project Verification (Verified 2026-07-06)

### Deploying Verification Kanban Board

```bash
# 1. Initialize kanban DB
hemlock-agent kanban init

# 2. Create project board
hemlock-agent kanban boards create <board-name> --description "<desc>"

# 3. Switch to board
hemlock-agent kanban boards switch <board-name>

# 4. Create verification tasks for each project
hemlock-agent kanban create "Project: Verify server starts, health endpoints, core API" --assignee <profile>

# 5. Start gateway (runs embedded dispatcher)
hemlock-agent gateway start

# 6. Dispatch tasks
hemlock-agent kanban dispatch

# 7. Monitor progress
hemlock-agent kanban watch
hemlock-agent kanban list
```

### Verified Task Template (All 5 Hackathon Projects)

| Project | Track | Assignee | Verification Checklist |
|---------|-------|----------|------------------------|
| Mnemosyne | 1: MemoryAgent | mnemosyne-lead | Server starts, health/ready endpoints, 4-layer memory API |
| Autopilot | 4: Workflow Automation | autopilot-architect | Server starts, health/ready, workflow trigger API |
| Aires | 2: AI Showrunner | aires-director | Server starts, health/ready, production creation API |
| Agora | 3: Agent Society | agora-architect | demo.js runs all 5 phases (constitutional, legislative, voting, judicial, executive) |
| Edgewalker | 5: EdgeAgent | edgewalker-architect | `cargo check` passes, kernel runtime starts |

### Infrastructure Verification Tasks

| Component | Assignee | Verification |
|-----------|----------|--------------|
| Federation Gateway | autopilot-architect | Port 41207, 5 projects, 600 agents, 20 rooms, TV room plugin |
| 4 Core Skills | default | Enterprise validation: agent-identity-architecture, autonomous-crew, autonomous-crew-autonomous-crew, loop-enforcer |

### Key Findings (2026-07-06)

1. **Gateway is internal A2A infrastructure** — not user-facing. Manage via `hemlock-agent kanban watch` / terminal.
2. **TV Sitcom MCP server (port 41208)** is the ONLY external-facing piece for company integration.
3. **All 7 tasks completed** in ~20 minutes with zero cross-project dependencies.
4. **Assignee must exist on disk** — `federation-gateway` and `skill-tester` profiles needed creation or reassignment to existing profiles.
5. **Enterprise validation** via `skill_enhance.py update --path <skill> --noninteractive` is mandatory for all skills.


## Kanban Integration (MANDATORY for Phased Tasks)

**Critical pitfall:** The kanban dispatcher does NOT check chain state before dispatching. If you create Phase 0-6 tasks, the dispatcher will happily run them all simultaneously. Chain enforcement is the WORKER's responsibility, not the dispatcher's.

### How it works

The `KANBAN_GUIDANCE` in `prompt_builder.py` now includes step **2b. Chain enforcement** which mandates:

### Worker Flow

```
1. kanban_show() — orient
2. cd $HERMES_KANBAN_WORKSPACE
2b. chain_enforce.py check <project> <phase>
    ├─ can_proceed: true  → do the work
    └─ can_proceed: false → kanban_block("Chain locked: prior phase not complete")
3. Do the work (heartbeat if long)
4. chain_enforce.py complete <project> <phase>
5. kanban_complete(summary, metadata)
```

### CRITICAL: Chain Steps Must Include Specific Deliverables

**Root cause of enterprise compliance failures:** Chain enforcement only tracked phase completion (Phase 0-6 marked "complete") without validating that specific deliverables were actually created.

**The checklist.md is the source of truth.** Each phase in the chain MUST have sub-steps for every deliverable the checklist requires. Example:

```
Phase 6: Deployment & Operations
├── Step 6.1: Create assignments.json
│   └── Validation: File exists, has correct structure, all phases assigned
├── Step 6.2: Create Dockerfile
│   └── Validation: Docker builds successfully, HEALTHCHECK configured
├── Step 6.3: Create docker-compose.yml
│   └── Validation: Compose config validates, services defined
├── Step 6.4: Create API.md
│   └── Validation: All endpoints documented with examples
└── Step 6.5: Run enterprise blueprint validation
    └── Validation: All 58+ rules pass
```

**Never mark a phase as "complete" if deliverables are missing.** The chain.py complete command must verify ALL sub-steps before marking the parent phase complete.

**Root cause analysis before patching.** When something goes wrong (missing deliverables, failed validation, incomplete work), always investigate WHY it happened before fixing. The user wants to understand the systemic issue, not just patch the symptom. Check: Were the tasks created correctly? Did the validation gate actually run? Was the checklist enforced? Document the root cause in your completion summary.

**Production-ready, not just demos.** The blueprint must enforce ALL aspects of a production-ready application, not just code implementation. Every phase must include validation gates that verify the complete deliverable exists and functions — API documentation, deployment configuration, testing, monitoring, security, and full functionality.

### Pitfall: Empty phase markers

NEVER create `.phase-*.marker` files as empty stubs. This signals "done" without
actual work. Markers should only be created by `chain.py complete` after verification.
If you find empty markers, delete them and reset the chain step to `active`.

### Pitfall: Root directory vs qwen-cloud-2026

Project code lives in `<WORKSPACE_ROOT>/qwen-cloud-2026/<project>/`.
Root-level directories (`<WORKSPACE_ROOT>/<project>/`) should be symlinks:
```bash
ln -s qwen-cloud-2026/<project> <WORKSPACE_ROOT>/<project>
```
The chain JSON paths must point to the REAL directory, not the symlink.

### Pitfall: Chain Directory Name Mismatch

`chain_enforce.py` searches for chains in multiple locations:
1. `.crew-*/.blueprint-chain/` (highest priority — crew-manager chains)
2. `.blueprint-chain/` (standard location)
3. `.chain/` (fallback)

If you have chains in multiple locations, the crew-manager chains take priority. This is by design — crew-manager.py creates chains in `.crew-<name>/.blueprint-chain/` and chain_enforce.py finds them automatically.

### Pitfall: Kanban Dispatcher Does Not Check Chain

The kanban dispatcher does NOT check chain state before dispatching. If you create Phase 0-6 tasks, the dispatcher will happily run them all simultaneously. Chain enforcement is the WORKER's responsibility, not the dispatcher's.

## Enhancement Hooks

| Skill | Enhancement | When |
|---|---|---|
| `skill-creator` | Package validated skills | After chain completes |
| `enterprise-blueprint` | Blueprint-guided build chains | Phase-gated projects |
| `kanban-orchestrator` | Task chain tracking | Multi-agent coordination |

## Key References

- `references/workflows.md` — common chain patterns (sequential, TDD, blueprint-guided)
- `references/validators.md` — validator examples and custom validator authoring
- `references/agent-integration.md` — how agents must interact with chains
- `references/state-format.md` — JSON state schema and log format
- `references/design-principles.md` — additive-only, verification gates, atomicity rules
- `references/lessons/operational-lessons.md` — real operational learnings from building this skill
- `references/operational-guide.md` — quick-start guide and operational patterns
- `references/chain-deliverable-validation-failure.md` — CRITICAL: Why chain must validate specific deliverables, not just phase completion

## Sources

| Source | URL | Last Verified |
|---|---|---|
| Python pathlib | docs.python.org/3/library/pathlib.html | 2026-07-04 |
| Python json | docs.python.org/3/library/json.html | 2026-07-04 |
| Python subprocess | docs.python.org/3/library/subprocess.html | 2026-07-04 |

## See Also

- `references/enterprise-validation-pitfalls.md` — Hardcoded paths, file type rules, tier requirements when using skill_enhance.py

## File Index (validator-complete)

- `references/chain-enforcement.md` — Chain Enforcement Integration with Kanban Workers
