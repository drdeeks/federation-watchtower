---
name: enterprise-blueprint
description: "Enterprise blueprint skill with integrated enforcement and checklist-driven execution. Generates blueprint.md + checklist.md + CHANGELOG.md with full enterprise structure. Validates against 58+ enterprise rules. Integrates loop-enforcer chain for sequential phase enforcement where checklist is the single source of truth. No hand-off to separate skills required — complete lifecycle in one skill."
license: MIT
metadata:
  tags:
    - blueprint
    - architecture
    - enterprise
    - planning
    - checklist
    - validation
    - testing
    - phase-gating
    - devops
  openclaw:
    tags:
      - blueprint
      - architecture
      - enterprise
      - planning
    category: devops
    priority: high
  hermes:
    tags:
      - creation
      - development
      - planning
    category: development
    related_skills:
      - portable-linux-usb
      - backup-protocol
  providers:
    - openai
    - claude
    - mistral
    - gemini
    - hermes
    - copilot
    - any
version: 1.0.0
---

# Enterprise Blueprint

Unified system for generating, validating, testing, and maintaining enterprise-grade technical blueprints alongside synchronized enforcement checklists, with agent role assignment and progress measurement built in. **The full lifecycle — generate → validate → test → assign — lives in this single skill; nothing hands off to a separate validation or testing skill to complete.** The blueprint is the law. The checklist is the enforcement.

## Provider Compatibility

| Provider | Compatibility | Notes |
|---|---|---|
| Claude (Anthropic) | Full | Tool use, MCP servers, artifact generation |
| OpenAI / ChatGPT | Full | Function calling, Actions, assistants |
| Mistral / Vibe | Full | Tool calling, script execution |
| Gemini (Google) | Full | Extensions, Vertex AI |
| Hermes (Nous) | Full | Tool-use fine-tuned |
| GitHub Copilot | Partial | Code generation; use external runner for scripts |
| Any LLM + tools | Full | All scripts are plain Python, provider-independent |

## Free-First Strategy

| Tier | Cost | Stack | Escalation Criteria |
|---|---|---|---|
| **Tier 0** | $0/mo | Python 3.8+ stdlib only | Default — covers all individual use |
| **Tier 1** | $0-5/mo | + CI/CD automated validation | When validating 10+ blueprints automatically |
| **Tier 2** | $5-20/mo | + Hosted blueprint registry | When distributing across a team or org |

Free alternatives: every script uses Python stdlib exclusively — zero pip installs, zero paid services. The $0 toolchain covers the full lifecycle from init through assignment metrics. Escalate only when team collaboration or automated pipelines justify additional cost.

## Core Concepts

A blueprint project produces two coexisting documents in the same output directory:

- **blueprint.md** — The authoritative master specification (single source of truth)
- **checklist.md** — The enforcement companion, phase-synchronized to the blueprint

Supporting metadata files:

- **project.json** — Phase registry, configuration, and version tracking
- **assignments.json** — Agent role assignments keyed by phase and module ID

Both documents share version numbers and rollback tag anchors. When `blueprint.md` is amended, `checklist.md` must be updated in the same commit. The checklist may never lead the blueprint — it enforces what the blueprint defines.

## Workflow: Initialize a New Blueprint

### Step 1 — Scaffold the Project

```bash
# Default phases
python3 scripts/init_blueprint.py "Project Name" --path ./output/project-name

# Custom phases
python3 scripts/init_blueprint.py "Project Name" --path ./output \
  --phases "Pre-Build,Foundation,Auth,Core,Integration,Launch"

# Preview without writing files
python3 scripts/init_blueprint.py "Project Name" --path ./output --dry-run
```

`blueprint.md` and `checklist.md` are created with all required enterprise sections, rollback tags, change log stub, and module registry populated.

### Step 2 — Populate Blueprint Top-Down

Replace all markers following this sequence:
Part I (vision, architecture) → Part II (module registry) → Part III (specifications) → Part IV (data architecture) → Part V (change control) → Part VI (phase checklists) → Part VII (quality standards).

### Step 3 — Validate

```bash
python3 scripts/validate_blueprint.py ./output/project-name/blueprint.md
python3 scripts/validate_blueprint.py ./output/project-name/blueprint.md --verbose
python3 scripts/validate_blueprint.py ./output/project-name/blueprint.md --json
```

### Step 4 — Sync Checklist

After populating the blueprint, sync the checklist to pull in all phases and sections:

```bash
python3 scripts/generate_checklist.py ./output/project-name/blueprint.md --sync
```

## Workflow: Validate a Blueprint

```bash
# Standard scored report
python3 scripts/validate_blueprint.py ./project/blueprint.md

# Full verbose — all checks including passes
python3 scripts/validate_blueprint.py ./project/blueprint.md --verbose

# Machine-readable JSON for CI pipelines
python3 scripts/validate_blueprint.py ./project/blueprint.md --json
```

The validator checks all enterprise rules: required parts, rollback tags on every section, change log presence and format, module registry completeness, feature flag coverage, performance budgets, and testing requirements. **Rating thresholds**: ENTERPRISE GRADE (0 FAIL, 0 WARN) → PRODUCTION READY (0 FAIL, 1-4 WARN) → NEEDS HARDENING (0 FAIL, 5-9 WARN) → INCOMPLETE (1-3 FAIL) → NOT ENTERPRISE GRADE (4+ FAIL). See [references/enterprise-rules.md](references/enterprise-rules.md) for the full rule set and fix guidance.

## Workflow: Generate or Sync the Checklist

```bash
# Generate checklist from existing blueprint
python3 scripts/generate_checklist.py ./project/blueprint.md

# Sync after blueprint amendments (adds new phases, preserves checked items)
python3 scripts/generate_checklist.py ./project/blueprint.md --sync

# Write to a specific path
python3 scripts/generate_checklist.py ./project/blueprint.md \
  --output ./project/checklist.md
```

Parsed from the blueprint: phase markers, module registry entries, rollback tags, and screen/feature spec headers. Each checklist phase gets: prerequisites, granular implementation steps with example commands, a validation gate, and an agent sign-off block. See [references/checklist-patterns.md](references/checklist-patterns.md) for pattern detail.

## Workflow: Assign and Track Agents

```bash
# Assign an agent to a phase
python3 scripts/assign_agents.py ./project --assign "AgentName:PHASE-1"

# Assign an agent to a specific module
python3 scripts/assign_agents.py ./project --assign "AgentName:MOD-003"

# List all current assignments
python3 scripts/assign_agents.py ./project --list

# Full assignment and completion status report
python3 scripts/assign_agents.py ./project --report

# Performance metrics and bottleneck detection
python3 scripts/assign_agents.py ./project --metrics
```

See [references/agent-roles.md](references/agent-roles.md) for role taxonomy, delegation patterns, load-balancing rules, and measurement framework.

## Workflow: Run Phase-Gated Tests

Testing closes the lifecycle in the same skill that generated the blueprint — a
phase is not "done" until its tier of tests passes. `test-runner.py` discovers
`tests/<tier>/` and runs each tier in order (unit → integration → e2e →
playwright), stopping at the first failing gate.

```bash
# Run every discovered tier, phase-gated (stop at first failing tier)
python3 scripts/test-runner.py ./project

# Run a single tier
python3 scripts/test-runner.py ./project --tier unit

# Preview the plan without executing anything
python3 scripts/test-runner.py ./project --dry-run

# Machine-readable report for CI / the guardrail gate
python3 scripts/test-runner.py ./project --json
```

Each tier is run with whatever runner is present (pytest → unittest → bash
fallback), so the same command works whether a project ships Python or shell
tests. A failing gate blocks the corresponding checklist phase from being marked
complete. See [references/testing-framework.md](references/testing-framework.md)
for tier discovery and runner selection, [references/phase-gating.md](references/phase-gating.md)
for how test gates bind to checklist phases, and [references/cli-wiring.md](references/cli-wiring.md)
for wiring the runner into a pipeline or the guardrail gate.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/init_blueprint.py` | Scaffold a new blueprint + checklist pair with full enterprise structure |
| `scripts/validate_blueprint.py` | Validate a blueprint against enterprise rules; FAIL/WARN/PASS scoring |
| `scripts/generate_checklist.py` | Generate or sync a granular enforcement checklist from a blueprint |
| `scripts/test-runner.py` | Orchestrate tiered phase-gated tests (unit/integration/e2e/playwright); pytest→unittest→bash fallback; `--tier`, `--dry-run`, `--json` |
| `scripts/assign_agents.py` | Manage agent role assignments and report completion metrics |
| `scripts/enforce_blueprint.py` | Initialize and manage blueprint lifecycle chains (phase gates, step verification, completion tracking) |
| `scripts/blueprint_validator.py` | Custom validator for blueprint chain steps — reads deliverables.json and validates actual project files |

## Enforced Output Statistics

Every script produces structured JSON on completion:

```json
{
  "operation": "init_blueprint | validate | generate_checklist | test_run | assign_agents",
  "timestamp": "ISO8601",
  "status": "success | failed | dry_run",
  "project": "project-name",
  "details": {},
  "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
}
```

All scripts support `--json` for machine-readable output suitable for CI pipelines.

## Error Handling

| Error | Response |
|---|---|
| Blueprint file not found | Report path; suggest `init_blueprint.py` |
| Missing required section (e.g., no PART IV) | Name the section; cite enterprise-rules.md |
| Missing rollback tag on section | Report header; provide correct tag format |
| Checklist out of sync with blueprint | List diverged phases; run `generate_checklist.py --sync` |
| `assignments.json` corrupt or missing | Rebuild from `project.json`; log the incident |
| Phase marked complete with failing tests | Block sign-off; require test fix before flag set |
| Python < 3.8 | Report minimum version; suggest upgrade |

See [references/enterprise-rules.md](references/enterprise-rules.md) for the full error catalog and recovery procedures. See [references/phase-templates.md](references/phase-templates.md) for phase-specific recovery patterns.

## Safety Practices

- Never overwrite critical files — use override protocol
- Blueprint files are critical — always backup before modification
- Use `--dry-run` flag to preview changes before applying
- See [safety-practices.md](references/safety-practices.md) for details
- See [critical-file-protection.md](references/critical-file-protection.md) for override protocol

## Enhancement Hooks

| Skill | Enhancement | When to Add |
|---|---|---|
| `skill-creator` | Package and validate this skill itself | When distributing enterprise-blueprint |
| `html-report` | Visual validation dashboard | When auditing 10+ blueprints |
| `xlsx` | Export assignments and metrics to spreadsheet | When managing large multi-agent teams |
| `docx` | Generate a Word document from blueprint | When delivering to external stakeholders |
| `frontend-design` | Interactive checklist web UI | When teams need browser-based tracking |

## Pitfalls

**NEVER delete, destroy, or nuke existing source code, demos, tests, or project files.** The blueprint's contributor rules (Part V) say "append only — no entry may be modified, deleted, or replaced." This applies to ALL project files, not just change log entries. When building on top of an existing project: ADD new files, EXPAND existing files, APPEND to content. NEVER run `rm -rf` on src/, tests/, demo.js, or any directory containing work. "Trash is always greater than purged." If you need to restructure, move files — don't delete them. Git commit before touching anything. The enterprise blueprint IS the guardrail — follow it WITHOUT being asked.

**Feature flags MUST start with a letter after `FEAT_`.** The validator regex is `FEAT_[A-Z][A-Z0-9_]+` — flags like `FEAT_001_AGENT` FAIL because `0` doesn't match `[A-Z]`. Correct: `FEAT_AGENT_SIMULATION`. Wrong: `FEAT_001_AGENT_SIMULATION`.

**Subagents improvise non-standard headers.** When delegating blueprint writing, provide the EXACT header template or the subagent will invent its own format (missing Version, READ FIRST preamble, TOC). The header MUST be:
```
# PROJECT_NAME — ENTERPRISE BLUEPRINT
## Version 1.0 | Document Class: MASTER SPECIFICATION
### Generated: YYYY-MM-DD

> **READ FIRST — DOCUMENT AUTHORITY**
> This document is the single source of truth for...
```

**CL entries need `## CL-NNN` headings, not just code blocks.** The validator regex requires `##\s+CL-\d+` as a markdown heading. Entries buried inside a code block without the heading pattern don't count. Format:
```
## CL-001
```
Date        : ...
```
```

**Blueprints under 1500 lines are almost always incomplete.** Enterprise-grade blueprints with full SQL schemas, ASCII diagrams, feature specs, and checklists typically run 2000-3000 lines. If validation shows many WARN items and the file is short, the content is thin — not just missing headers.

**Always scaffold with `init_blueprint.py` first, never write from scratch.** The script generates the correct Part structure, rollback tags, and section headers. Writing a blueprint manually risks missing required sections that the validator catches as FAIL.

**Match depth to the reference standard.** Users expect blueprints with: 50+ line ASCII architecture diagrams, full SQL CREATE TABLE statements (not descriptions), complete API contract tables, 5-8 components per feature with 5-8 testable rules each, and 3-5 error states with user-facing messages AND system behavior. Minimal outlines fail the "no placeholders" requirement.

**Validator v2 enforces 58 checks — stricter than v1.** New FAIL-class checks: document >1500 lines, ASCII architecture diagram (20+ box-drawing chars), 3+ feature specs with all 9 required fields, phase deliverables + validation gates. New WARN-class checks: 3+ SQL tables, 5-level error hierarchy, concrete performance metrics (6+ with units), rollback procedures per phase, >2500 lines for "thorough" rating.

**Feature spec field names use UNDERSCORES, not spaces.** Specs commonly use `ERROR_STATES:` (with underscore) in code blocks, but the validator regex `ERROR[\s_]+STATES` accepts both. When writing specs, use the format that matches your existing convention — both `ERROR STATES` and `ERROR_STATES` pass validation.

**Validator regexes are case-sensitive unless `re.IGNORECASE` is set.** The rollback procedure check uses `[Rr]ollback\s+[Pp]rocedure` with `re.IGNORECASE`, so `ROLLBACK PROCEDURE:`, `rollback procedure`, and `Rollback Procedure` all match. Always pass `re.IGNORECASE` when building content-matching regexes for blueprints.

**Deliverables/Gates appear in multiple formats.** Some blueprints use `### Deliverables` (h3 heading), others use `**Detailed Deliverables:**` (bold), others use plain `Deliverables:` in tables. The validator matches the word `Deliverables` and `Validation Gate` regardless of surrounding formatting. Don't assume a single format.

**Reserved rollback tag stems are mandatory.** Every blueprint must contain tags with these stems: `SYS-OVERVIEW`, `MODULE-REGISTRY`, `SPECS`, `DATA-ARCH`, `CHANGE-CONTROL`, `QUALITY`. Add them as blockquotes after each Part heading: `> **Rollback Tag:** \`[TAG-STEM-v1]\``.

**Dummy content regex excludes legitimate uses.** The validator does NOT flag "hackathon" (contains "hack"), "MockDashScopeProvider" (contains "mock"), or "test files" as dummy content. Only true placeholders like `lorem ipsum`, `foo bar`, `FIXME` are flagged. Don't waste time removing legitimate technical terms.

## Overlapping Skills

**`enterprise-blueprint-validation`** (devops category) is a strict subset of this skill — it covers validation, checklist generation, and testing but with an older validator (pre-v2) and hardcoded `hemlock` CLI commands. The curator should consolidate it into this skill and delete the standalone validation skill. All its functionality is now covered here with the v2 validator (58 checks).

- **Blueprint compliance standard and required sections**: [references/blueprint-standard.md](references/blueprint-standard.md) — Read when building, auditing, or amending a blueprint
- **Checklist generation patterns and item anatomy**: [references/checklist-patterns.md](references/checklist-patterns.md) — Read when writing, generating, or syncing checklist items
- **Agent role taxonomy, delegation, and measurement**: [references/agent-roles.md](references/agent-roles.md) — Read when assigning agents or analyzing bottlenecks
- **Phase-type templates for common implementation phases**: [references/phase-templates.md](references/phase-templates.md) — Read when populating a specific phase type for the first time
- **Enterprise enforcement rules and full error catalog**: [references/enterprise-rules.md](references/enterprise-rules.md) — Read when validating, troubleshooting, or enforcing compliance
- **Tiered test discovery and runner selection**: [references/testing-framework.md](references/testing-framework.md) — Read when adding tests or configuring the test-runner
- **Binding test gates to checklist phases**: [references/phase-gating.md](references/phase-gating.md) — Read when a phase must not complete until its tests pass
- **Wiring the test-runner into a pipeline or the guardrail gate**: [references/cli-wiring.md](references/cli-wiring.md) — Read when automating tests in CI or chaining to guardrail-enforcement
- **Chain enforcement lessons learned**: [references/lessons/chain-enforcement-lessons.md](references/lessons/chain-enforcement-lessons.md) — Read when debugging phase parsing, filename sanitization, or deliverable mapping
