---
name: loop-enforcer
description: "Enforce sequential dependency chains on files, tasks, and services. Locks steps until prior work is verified complete. Interactive menu + agent API. Prevents destructive ops by enforcing additive-only builds with chained verification gates. Use when building projects where files must be created in order, or when agents must not destroy existing work."
version: 1.0.6
license: MIT
metadata:
  openclaw:
    version: "1.0"
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
    tags: [automation, devops, enforcement]
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

## Enhancement Hooks

| Skill | Enhancement | When |
|---|---|---|
| `skill-creator` | Package validated skills | After chain completes |
| `enterprise-blueprint` | Blueprint-guided build chains | Phase-gated projects |
| `kanban-orchestrator` | Task chain tracking | Multi-agent coordination |

## Key References

- `references/workflows.md` — common chain patterns (sequential, TDD, blueprint-guided)
- `references/validators.md` — validator examples and custom validator authoring
- `references/agent-integration.md` — agent MUST check before write
- `references/state-format.md` — JSON schema + log format
- `references/design-principles.md` — additive-only, verification gates, atomicity
- `references/lessons/operational-lessons.md` — 7 real lessons from building this skill
- `references/skill-creator-integration.md` — how skill-creator uses loop-enforcer to lock its 11-step pipeline
- `references/chain-enforcement-integration.md` — reusable pattern for any multi-step pipeline

## Sources

| Source | URL | Last Verified |
|---|---|---|
| Python pathlib | docs.python.org/3/library/pathlib.html | 2026-07-04 |
| Python json | docs.python.org/3/library/json.html | 2026-07-04 |
| Python subprocess | docs.python.org/3/library/subprocess.html | 2026-07-04 |