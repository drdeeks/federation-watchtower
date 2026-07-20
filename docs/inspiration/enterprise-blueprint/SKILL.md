---
name: enterprise-blueprint
description: Parse, validate, and generate execution checklists from enterprise project
  blueprints. Provides 58+ validation rules, phase-gated workflow planning, and CI/CD
  integration. Use when creating project blueprints, validating blueprint structure,
  generating execution checklists, or planning multi-phase enterprise workflows. Triggers
  on 'blueprint', 'enterprise blueprint', 'project blueprint', 'blueprint validation',
  'checklist generation', 'phase planning'.
version: 1.0.8
license: MIT
metadata:
  category: project-planning
  complexity: enterprise
  tags:
  - enterprise
  - blueprint
  - project planning
  - validation
  - checklist generation
  - workflow planning
  - phase gating
  - CI/CD integration
  - execution planning
---

# Enterprise Blueprint

Standalone enterprise blueprint workflow engine. Parses blueprint structure, validates against 58+ enterprise rules, generates execution checklists, and plans multi-phase workflows. Zero external dependencies — Python 3.8+ stdlib only.

## When to Use

- Creating or reviewing enterprise project blueprints
- Validating blueprint structure (7 chapters, 6+ phases, 15+ tasks)
- Generating phase-by-phase execution checklists
- Planning resource allocation and dependency chains
- CI/CD integration for automated validation gates

## Core Capabilities

### Blueprint Structure Parsing
- **7 Required Chapters**: Part I-VII following enterprise standards
- **Phase Extraction**: Detects and tracks 6-7 development phases
- **Task Breakdown**: Granular checklist items with validation gates
- **Rollback Management**: Phase and section rollback tag tracking

### Enterprise Validation
- **58+ Rules**: Comprehensive validation against enterprise standards
- **Quality Scoring**: 0-100 compliance score with detailed breakdown
- **Chapter Validation**: Ensures all 7 enterprise chapters present
- **Phase Compliance**: Minimum 6 phases, proper structure

### Checklist Generation
- **Phase-by-Phase Breakdown**: Detailed task breakdown per development phase
- **Validation Gates**: Phase completion verification points
- **Progress Tracking**: Real-time completion metrics and dashboard
- **Dependency Mapping**: Sequential phase and task dependencies

### Workflow Planning
- **Timeline Generation**: Phase-based execution schedules
- **Resource Allocation**: Hour estimates and validation requirements
- **Critical Path**: Dependency analysis for bottleneck identification
- **Status Reporting**: Completion tracking and progress dashboards

## Usage

The primary tool is `generate_checklist.py` — a unified lifecycle tool and the single manager for blueprint lifecycle, enforcement, and looping. `enforce_blueprint.py` is a thin compat wrapper that delegates to it for legacy CLI callers. The old standalone `enterprise_blueprint_checker.py` (a competing, independent checklist/validation implementation) has been removed — use `generate_checklist.py` directly.

### Generate checklist from blueprint (default subcommand)
```bash
python3 scripts/generate_checklist.py ./project/blueprint.md
# Output: ./project/checklist.md + ./project/checklist-data.json
```

### Init enforcement chain
```bash
# Loop-locked only (default, no validators)
python3 scripts/generate_checklist.py ./project --init

# With blueprint-driven validators
python3 scripts/generate_checklist.py ./project --init --with-validators
```

### Chain operations
```bash
python3 scripts/generate_checklist.py ./project --status       # chain state
python3 scripts/generate_checklist.py ./project --phase 0 --step 0 --verify
python3 scripts/generate_checklist.py ./project --phase 0 --step 0 --complete
python3 scripts/generate_checklist.py ./project --phase 0 --step 0 --check
python3 scripts/generate_checklist.py ./project --menu          # interactive
python3 scripts/generate_checklist.py ./project --generate-validators
```

### Initialize New Blueprint
```bash
python3 scripts/init_blueprint.py "My Project" --path ./output/project-name
```

## Output Formats

| Format | Use Case |
|--------|----------|
| Markdown | Human-readable checklists and reports |
| JSON | Machine-readable for CI/CD pipelines |
| Validation Reports | Detailed compliance scores and fix guidance |

## Error Handling

- Detailed error messages with fix guidance
- Graceful degradation for missing or corrupt files
- Automatic rollback and recovery workflows
- Enterprise compliance strict validation

## Key References

- `references/enterprise-rules.md` — 58+ validation rules
- `references/phase-templates.md` — Phase-specific templates
- `references/blueprint-structure.md` — Blueprint structure standards
- `references/checklist-patterns.md` — Checklist generation patterns
- `references/hackathon-blueprint-lessons.md` — Best practices and lessons learned
- `references/skill-enhancement-pipeline.md` — ACK character enforcement pipeline (11 gates) via skill-creator/skill_enhance.py
- `references/loop-enforcer-integration.md` — Loop-enforcer chain enforcement integration (gaps, env vars, worker API)
- `references/agent-detection-rules.md` — Agent/crew detection rules (singular source of truth)
- `references/model-tiering-strategy.md` — Token-optimized model tiering with flash/final pattern
- `references/templates/agent-model-map-template.yaml` — Agent model map template
- `references/templates/crew-model-map-template.yaml` — Crew model map template
- `references/verification-results-v1.0.6.md` — Complete test transcripts for self-healing, tamper resistance, opt-out, agent watch
- `references/validator-registry.md` — Project-Type → Phase Validator Registry (this session)

## Self-Enhancement Pipeline (ACK Character Enforcement)

The enterprise-blueprint skill can self-validate through the **skill-creator's ACK character enforcement pipeline** (`skill-creator/scripts/skill_enhance.py`). This applies the Agent Character Kit's enforcement methodology to the skill itself:

```bash
python3 .hermes/skills/skill-creator/scripts/skill_enhance.py update \
  --path .hermes/skills/devops/enterprise-blueprint \
  --tier enterprise --noninteractive
```

### 11-Gate Chain Enforcement

| Gate | Purpose | Hard/Soft |
|------|---------|-----------|
| 1. Scaffold | Skill structure exists | Soft (skipped on update) |
|| 2. Frontmatter | 7+ tags, description ≥100 chars, no placeholder markers | Hard |
| 3. Scripts | ≥3 substantive scripts (no __pycache__) | Hard |
| 4. References | ≥5 substantive reference docs | Hard |
| 5. Validate | Enterprise validation (58+ rules) | Hard |
| 6. Auto-fix | Safe structural fixes only | Hard |
| 7. Re-validate | 0 FAIL required (warnings OK) | **Hard (gate)** |
| 8. Test scripts | Syntax + shebang + --help exits 0 | Hard |
| 9. Verify sources | Provider tags remapped, no dead URLs | Soft |
| 10. Package | Version bump, .skill archive emitted | Hard |
| 11. Extract-verify | Archive layout intact, hashes match | Hard |

### Pitfalls Encountered (v1.0.4 + cumulative)

- **Hardcoded paths**: Session-specific paths (`${USB_MOUNT}` or `$HOME`) in reference docs trigger validator warnings — use placeholders
- **Missing reference links**: Every file in `references/` MUST be linked in SKILL.md references section
- **Duplicate sections**: Duplicate headers (e.g., "## Pitfalls" appearing twice) trigger warnings
- **Cached bytecode**: `scripts/__pycache__/` triggers structural violations — clean before validation
- **Missing --help handlers**: Scripts without `--help` that exits 0 fail test_script gate
- **Placeholder text in SKILL.md body**: Example text mentioning banned patterns (e.g., "Placeholder checkboxes", "TODO markers") triggers validator FAIL — remove or rephrase
- **Template permissions**: Templates in `references/templates/` must be chmod 0444 (auto-fixed by pipeline but slows it down)
- **Check all references before deleting/renaming a script**: `grep -rn "old_script_name"` across all scripts, `__init__.py`, SKILL.md, and references before removing or renaming. A deleted script that `__init__.py` or `apply_blueprint.py` references will break the skill entrypoint. Restoring a compat wrapper is a fix, not a prevention.
- **Chain name filesystem safety**: Chain names derived from `data.project_name` become filenames under `.chain/`. If the blueprint's `Project:` line is very long (100+ chars) or contains special characters (em-dashes, Unicode), the resulting filename can exceed the filesystem's NAME_MAX (typically 255 bytes) or PATH_MAX, producing `Errno 36: File name too long`. Always sanitize: strip non-alphanumeric chars, spaces→dashes, hard-cap at 80 chars. Use a shared `_chain_name(data)` function called by ALL subcommands that construct the chain name (init, status, phase, menu) so they stay consistent.
- **Argparse abbreviation trap (Python-specific)**: Python's `argparse` auto-abbreviates long flags by default (`allow_abbrev=True`). If you pass `--output /path/to/file` but the actual flag is `--output-dir`, argparse silently matches `--output` as an abbreviation for `--output-dir` and treats the intended file path as a directory path. This creates paths like `file/checklist.md` instead of `checklist.md`. Avoid ambiguous flag prefixes that match multiple longer flags. When calling a script from another script (`__init__.py` calling `generate_checklist.py`), explicitly pass the full flag name, not an abbreviated one.
- **Subprocess arg order**: When calling a script that accepts `--root` as a keyword argument, pass it as `--root /path`, not as a positional argument `/path`. Positional arguments are often consumed by positional-only parsers (e.g., test-runner.py uses the first positional for the test tier, not the project root). Always check the target script's `--help` before composing a subprocess call.
- **Consistent chain name across all subcommands**: If `create_chain()` uses a sanitized chain name but `status`/`phase`/`menu` subcommands construct the chain name from raw `data.project_name`, they'll look for a different file than what was created. Extract chain name building into a shared function and use it everywhere.
- **Re-init must clear old chain state**: `chain.py create` refuses to overwrite (`"error": "Chain already exists"`). The fix is to glob `.chain/<chain-name>.json` and `.log` before calling create. This is baked into `generate_checklist.py`'s `create_chain()` — always re-init via `generate_checklist.py --init` rather than calling `chain.py create` directly.

## Lessons Learned (This Session — v1.0.6 Enterprise Validation)

See `references/lessons/chain-enforcement-lessons.md` for full 15 lessons. Key takeaways:

1. **Agent/crew detection must be singular source of truth** (FOREVER SYSTEM §1) — `discover_agents.py` is THE canonical detector; all components delegate to it
2. **Path agnosticism requires env vars everywhere** — `LOOP_ENFORCER_ROOT`, `AGENT_WORKSPACE`, `ENFORCER_SOCKET`, ACK convention paths; no hardcoded paths anywhere
3. **Model tiering with flash/final pattern optimizes token cost** — iteration (flash) vs final (plus/max) per phase/task; `interactive_setup.py` generates versioned maps
4. **All chain enforcement routes through loop-enforcer** — no duplicate implementations; `__init__.py` delegates to `generate_checklist.py`; worker API is thin plugin
5. **Opt-out flag required** — `--no-loop-enforcement` generates checklist only, skips chain init
6. **Template configs essential** — versioned YAML templates prevent hand-written config drift
7. **Interactive setup prevents misconfiguration** — walks user through detection → template → per-phase models → task overrides → write + verify
8. **Dogfood validation via skill_enhance.py is non-negotiable** — 11 gates must pass (0 FAIL, warnings OK) on every release

## Verification Results (v1.0.6 Session — Live End-to-End Tests)

### Agent Watch (Chain State) Created ✅
- File-based state machine at `.chain/blueprint-<agent>.json` with 6 steps, timestamps, attempts, transitions
- Marker files in `.blueprint-chain/` for each step (0-byte presence files)
- No external daemon needed — survives process crashes, container restarts, USB moves

### Self-Healing Verified ✅
| Test | Action | Result |
|------|--------|--------|
| State file deleted | `rm .chain/blueprint-*.json` → re-run `apply_blueprint.py` | Chain recreated fresh from checklist |
| State file corrupted | `echo '{"bad":true}' > .chain/blueprint-*.json` → `chain_worker.py status` | Fail-closed: `KeyError: 'steps'` — no silent recovery, explicit error |
| Re-apply after corruption | Re-run `apply_blueprint.py` on corrupted agent | Clean chain created, no residue from bad state |

### Tamper Resistance Verified ✅
| Attack | Attempt | Result |
|--------|---------|--------|
| Fake completion | Edit `.chain/blueprint-*.json` to set all steps `"state": "complete"` | `chain_worker.py status` shows tampered state but `check` returns `"locked"` for future steps — index gate blocks |
| Skip phase | Call `complete` on step 2 without step 1 | `verify` rejects: `"Step is 'locked', must be 'active' to verify"` |
| Marker file mismatch | Delete `.blueprint-chain/phase-00-*` but keep `.chain` state | Next `status` shows mismatch — chain validation catches drift |

### Opt-Out Flag Working ✅
```bash
apply_blueprint.py --target /path/agent --blueprint bp.md --no-loop-enforcement
# → Generates checklist.md ONLY, no .blueprint-chain/, no .chain/ state file
```

### Enterprise Validation Gates Passed (11/11) ✅
```
v1.0.4 → v1.0.5 → v1.0.6 (this session)
- All scripts pass syntax + --help + shebang
- 14 substantive scripts, 28 reference docs
- 0 FAIL, 11 WARNINGS (optional refs not linked in SKILL.md)
- Archive extracted & verified: hashes match, layout intact
```

## Checklist Generator — Single Source of Truth (Consolidated)

The checklist generator was rewritten to be the **single source of truth** for all enforcement. Blueprint is parsed ONCE by `generate_checklist.py`, which outputs two files:

| File | Purpose |
|------|---------|
| `checklist.md` | Human-readable task list with phase/step breakdown |
| `checklist-data.json` | Structured data for enforcement (phases, tasks, deliverables, validation gates, rollback, feature flags) |

### Flow (Consolidated)

**One tool, all verbs.** `enforce_blueprint.py` was folded into `generate_checklist.py` — the old file was replaced by a thin compat wrapper that delegates all legacy calls to the unified tool.

```
blueprint.md ──→ generate_checklist.py generate ──→ checklist.md
                                                     └──→ checklist-data.json ←── generate_checklist.py init
                                                                                    generate_checklist.py verify
                                                                                    generate_checklist.py complete
                                                                                    generate_checklist.py status
```

| Subcommand | Function |
|------------|----------|
| `generate` (default) | Parse blueprint, write `checklist.md` + `checklist-data.json` |
| `init` | Build enforcement chain from existing `checklist-data.json` |
| `verify` | Verify a phase step |
| `complete` | Complete a phase step |
| `status` | Show chain state |
| `check` | Check step status |
| `menu` | Interactive chain menu |
| `generate-validators` | Generate phase validators from blueprint data |

### Enforcement Modes

`--mode` flag on `generate` subcommand:

| Mode | Behavior | Use Case |
|------|----------|----------|
| `plain` | Just the checklist, no locking | Reference/planning only |
| `loop` | Checklist + loop locking (default) | Single agent with phase gating |
| `agent` | Checklist + loop + agent enforcement | Multi-agent with per-agent gates |
| `crew` | Checklist + loop + crew enforcement | Full crew orchestration |

### Opt-In Validators

Validators are **disabled by default** — only loop locking. Enable with `--with-validators`:

```bash
# Default: loop-locked ONLY (no validators)
python3 scripts/generate_checklist.py . --init

# Opt-in: generates per-phase validators from blueprint Part VI tables
python3 scripts/generate_checklist.py . --init --with-validators

# During generate (pre-populates enforcement config)
python3 scripts/generate_checklist.py blueprint.md --with-validators
```

### Usage Examples

```bash
# Generate checklist + data
python3 scripts/generate_checklist.py blueprint.md

# Init chain (loop-locked)
python3 scripts/generate_checklist.py /project --init

# Init chain with validators
python3 scripts/generate_checklist.py /project --init --with-validators

# Chain status
python3 scripts/generate_checklist.py /project --status

# Phase operations
python3 scripts/generate_checklist.py /project --phase 0 --step 0 --verify
python3 scripts/generate_checklist.py /project --phase 0 --step 0 --complete
python3 scripts/generate_checklist.py /project --phase 0 --step 0 --check

# Generate validators separately
python3 scripts/generate_checklist.py /project --generate-validators
```

### Blueprint Structure That Works (Part VI Tables)

The authoritative source of deliverables per phase is the **Part VI implementation checklist table**:

```markdown
## PART VI: Deliverables and Validation
### PHASE-0: Foundation
| Prerequisite | Feature Flag | Deliverables | Validation Gate | Rollback |
|--------------|--------------|--------------|-----------------|----------|
| Ventoy USB | FEAT_USB_BOOT | iso/maestro.iso | Boot test | RB-001 |
```

Each row = one task in the checklist. The data flows into `checklist-data.json` for enforcement.

**Parsing priority**: Part VI tables → fallback to checkbox tasks in phase sections. The old 3-try fallback was removed in favor of this clean single-phase parsing approach.

### Blueprint-Driven Validator Generator (This Session — Primary Pattern)

**Key Principle**: The blueprint IS the source of truth. Validators are GENERATED from Part VI implementation checklist tables, not from project-type assumptions.

### Pitfall: `chain.py create` Doesn't Overwrite — Must Clear Old State

`chain.py create` (in loop-enforcer) refuses to overwrite. If you re-init, it returns `{"error": "Chain already exists"}`. The fix is baked into `generate_checklist.py`'s `create_chain()` — it globs `.chain/<chain-name>.json` and `.log` and deletes them before calling `chain.py create`. Always call `generate_checklist.py . --init` rather than calling `chain.py create` directly for this reason.

### Architecture
```
Blueprint Part VI Tables (deliverables per phase)
        ↓
scripts/blueprint_validator_gen.py (parses tables, generates validators)
        ↓
.project/.blueprint-chain/validators/validate_phase{N}_blueprint.py
        ↓\ngenerate_checklist.py --with-validators maps gates → generated validators
        ↓
Enforcer (loop-enforcer) runs validator on verify() — AGENTS NEVER RUN VALIDATORS
```

### Opt-In Validator Pattern (Default = Loop-Locking Only)
```bash
# Default: checklist + phase locking ONLY (no validators)
python3 generate_checklist.py /project --init

# Opt-in: generates validators from blueprint Part VI tables
python3 generate_checklist.py /project --init --with-validators
```

**Why**: Validators are enforcer-only tools. Agents must not validate their own work (Creative Orchestration Doctrine Principle V: Critique Is Equal to Creation).

### Validator Generation Process (`blueprint_validator_gen.py`)
1. Parses **Part VI implementation checklist tables** in blueprint.md
2. Each table row = one deliverable with: prerequisite, feature flag, deliverable(s), validation gate, rollback
3. Generates `validate_phase{N}_blueprint.py` per phase in `.blueprint-chain/validators/`
4. Each validator checks EXACTLY what the blueprint declares (ISO files, scripts, configs, binaries, etc.)
5. **No project-type registry** — validation is blueprint-driven only. The old `registry.py` was deleted.

### New Phase-Specific Validators Created

| Phase | Project Type | Validator | Key Deliverables Checked |
|-------|-------------|-----------|-------------------------|
| 0 | All | `validate_phase0_foundation.py` | `.gitignore` patterns, dir structure, README, LICENSE, pyproject.toml, git init, linting |
| 1 | agent-crew | `validate_phase1_core_services.py` | API spec, DB config, service entry point, /health endpoint, config mgmt, logging, lock files, unit tests |
| 1 | web-app/dapp/backend | `validate_phase1_backend_api.py` | Same as above, tailored for web backends |
| 2 | web-app/dapp | `validate_phase2_frontend_web.py` | **Next.js/Vite/Svelte/Astro/Nuxt/Remix/Gatsby config**, pages/routes, components, TypeScript config, lint/format, build output, accessibility, SEO meta, responsive breakpoints, tests |
| 2 | mobile-flutter | `validate_phase2_mobile_flutter.py` | **pubspec.yaml**, platform dirs (android/ios/macos/windows/linux/web), build configs (gradle/Podfile), code signing, Fastlane/Codemagic, flutter analyze/test |
| 2 | agent-crew | `validate_phase2_runtime_agents.py` | Agent defs (SOUL.md/agent.json), Dockerfile/process mgmt, crew config, comms (Redis/gRPC), observability, lifecycle scripts |
| 3 | web3-dapp | `validate_phase3_smart_contracts.py` | **Foundry/Hardhat/Brownie/Ape config**, contracts in contracts/src/, tests, deploy scripts, ABIs (out/artifacts/), gas reports, Slither/Mythril, Etherscan verification |
| 3 | general | `validate_phase3_persistence_hardening.py` | Backup/restore scripts, firewall (nftables/iptables), hardening, volumes, secrets (SOPS/age), SSL, audit |
| 4 | web-app/dapp | `validate_phase4_integration_web.py` | E2E tests (Cypress/Playwright), CI/CD (GitHub Actions), deploy config (k8s/helm/terraform/Docker/vercel/netlify), smoke tests, perf tests (k6/locust), security scans (CodeQL/Semgrep/Trivy), docs, changelog, observability, feature flags |
| 4 | agent-crew | `validate_phase4_integration_validation.py` | Same as above + agent-specific integration tests |

### Reference Added
- `references/validator-registry.md` — Project-Type → Phase Validator Registry (this session)

## New References Added This Session

- `references/verification-results-v1.0.6.md` — Complete test transcripts for self-healing, tamper resistance, opt-out, agent watch
- `scripts/test_runner.py` — Phase-gated test orchestrator (syntax + help + execution probe)
- `scripts/test-runner.py` — Alias for compatibility
- `scripts/validate_phase0_foundation.py` — Phase 0 validator (git, .gitignore, README, LICENSE, pyproject.toml, dir structure, linting)
- `scripts/validate_phase1_core_services.py` — Phase 1 validator (API spec, DB config, service entry point, /health endpoint, config mgmt, logging, lock files, unit tests)
- `scripts/validate_phase2_runtime_agents.py` — Phase 2 validator (agent defs, Dockerfile/process mgmt, crew config, comms, observability, lifecycle scripts)
- `scripts/validate_phase3_persistence_hardening.py` — Phase 3 validator (backup/restore scripts, firewall, hardening, volumes, secrets, SSL, audit)
- `scripts/validate_phase4_integration_validation.py` — Phase 4 validator (integration/e2e tests, CI/CD, deploy config, smoke tests, contract tests, perf tests, security scanning, docs, changelog)
- `scripts/blueprint_validator_gen.py` — Blueprint-driven validator generator (parses Part VI tables, generates per-project validators)

## Enforcer Validation Architecture (This Session — Critical Fix)

**Problem**: The original `auto-verify-complete` allowed the **agent to validate itself** — creator reviewing own work. Violates Creative Orchestration Doctrine Principle V: *Critique Is Equal to Creation*.

**Solution**: Split verify/complete; enforcer owns validators. **Agents NEVER run validators** — only the enforcer can.

| Component | Role |
|-----------|------|
| `generate_checklist.py` | **Single unified tool**: generates checklist data AND manages chain state. Subcommands: generate, init, verify, complete, status, check, menu, generate-validators. After generation, reads only from `checklist-data.json` — never re-parses blueprint. Clears old chain state on re-init. |
| `chain.py` (loop-enforcer) | On `verify`, reads validator from state, executes it DIRECTLY (not via `python3`), marks `verified`/`active` |
| `chain_worker.py` | Agent interface: `check` → `verify` (enforcer runs validator) → `complete` — **no auto-verify-complete** |
| Phase validators | Independent scripts checking **real deliverables** (files, configs, patterns), not placeholder commands |

**Blueprint-Driven Validator Generator** (`scripts/blueprint_validator_gen.py`):
- Parses **Part VI implementation checklist tables** in blueprint.md for deliverables per phase
- Generates `validate_phase{N}_blueprint.py` scripts in `.blueprint-chain/validators/`
- Each validator checks EXACTLY what the blueprint declares (ISO files, scripts, configs, binaries, etc.)
- Falls back to project-type registry only if Part VI tables not found

**Validator Contract**:
```python
def check_<phase>(project_root: Path) -> tuple[bool, list[str]]:
    # Returns (passed, messages)
    # messages: ["ERROR: ...", "WARN: ..."]
    # Errors block phase completion; warnings only surface
```

**Phase Gate Flow** (enforcer-controlled):
```
1. Agent completes work → calls `chain_worker.py verify <step>`
2. Enforcer reads validators.json → sets validator on step
3. Enforcer runs validator DIRECTLY (subprocess.run([validator, path])) — exit code = pass/fail
4. If pass: step.state = "verified", next step.state = "active"
5. Agent calls `complete` → step.state = "complete"
6. Phase N+1 remains locked until Phase N validator passes
```

**Doctrine Compliance** (Creative Orchestration):
- **Identity immutable** — Phase gates reference blueprint tags/flags
- **Singular responsibility** — Each validator owns one phase's checks
- **Every decision → artifact** — Validators check for actual files/configs
- **Iterative critique** — Failed validation = phase stays active, agent fixes, re-verify
- **Critique = creation** — Phase gates are mandatory enforcer review
- **Regenerate only failure** — Failed phase re-verified; others stay complete
- **Hierarchical** — Phase N+1 locked until Phase N validated + completed

## Validator Implementation Pitfalls (This Session)

1. **Never use `python3 validator.py`** — breaks shebang scripts. Run validator directly: `subprocess.run([validator_path, step_path])`
2. **Validators receive step file path** — must navigate to project root: `project_root = Path(step_path).parent.parent`
3. **All validators must be executable** — `chmod +x scripts/*.py` (and shell scripts)
4. **Exit codes = pass/fail** — 0 = pass, non-zero = fail. Stdout/stderr captured for output.
5. **No agent self-validation** — removed `auto-verify-complete` from `chain_worker.py` entirely
6. **Sanitize filenames** — em-dashes, colons break matching. Use `.replace('—', '').replace(':', '')` consistently
7. **Phase gate step index = num_steps + 1** — phase steps 1..N, gate at N+1. Lookup logic must match.
8. **Blueprint-driven validators are primary** — `blueprint_validator_gen.py` generates validators from Part VI tables; project-type registry is fallback only
9. **Validator generated per project** — each project gets its own validators in `.blueprint-chain/validators/` matching its blueprint's exact deliverables
10. **Part VI tables are the source of truth** — if blueprint has implementation tables, they drive validation; no project-type assumptions

## File Index (validator-complete)

- `references/checklist-consolidation.md` — Checklist tool consolidation: enforce_blueprint.py merged into generate_checklist.py
- `references/agent-roles.md` — Agent Roles Reference
- `references/blueprint-standard.md` — Blueprint Standard Reference (v2)
- `references/cli-wiring.md` — CLI Wiring Reference
- `references/critical-file-protection.md` — Critical File Protection
- `references/enforcer-validation-architecture.md` — Enforcer Validation Architecture (this session)
- `references/lessons/chain-enforcement-lessons.md` — Lessons Learned — Enterprise Blueprint Chain Enforcement
- `references/phase-gating.md` — Phase Gating Reference
- `references/safety-practices.md` — Safety Practices
- `references/testing-framework.md` — Testing Framework Reference
- `references/validation-rules.md` — Validation Rules Reference
- `references/agent-detection-rules.md` — Agent/Crew Detection Rules
- `references/model-tiering-strategy.md` — Model Tiering Strategy
- `references/templates/agent-model-map-template.yaml` — Agent Model Map Template
- `references/templates/crew-model-map-template.yaml` — Crew Model Map Template
- `references/validator-registry.md` — Project-Type → Phase Validator Registry (this session)
- `references/verification-results-v1.0.6.md` — Live End-to-End Verification Results (self-healing, tamper resistance, opt-out, agent watch)
- `scripts/assign_agents.py` — enterprise-blueprint — Assign agent roles and track implementation metrics
- `scripts/blueprint_validator.py` — Validator for blueprint chain steps.
- `scripts/generate_checklist.py` — **Single unified tool**: generate, init, verify, complete, status, check, menu, generate-validators. Reads only from checklist-data.json after generation. `enforce_blueprint.py` is now a thin compat wrapper around this tool.
- `scripts/test-runner.py` — Phase-Gated Test Orchestrator
- `scripts/test_runner.py` — Alias for compatibility
- `scripts/validate_blueprint.py` — Blueprint Validation Script
- `scripts/discover_agents.py` — Detect agent/crew/project identity (singular source of truth)
- `scripts/apply_blueprint.py` — Main entry: --target/--crew/--agents with --no-loop-enforcement opt-out
- `scripts/chain_worker.py` — Real plugin interface for agent→loop-enforcer
- `scripts/interactive_setup.py` — Walkthrough creating agent-model-map.yaml / crew-model-map.yaml
- `scripts/validate_phase0_foundation.py` — Phase 0 validator (git, .gitignore, README, LICENSE, pyproject.toml, dir structure, linting)
- `scripts/validate_phase1_core_services.py` — Phase 1 validator (agent-crew: API spec, DB config, service entry point, /health endpoint, config mgmt, logging, lock files, unit tests)
- `scripts/validate_phase1_backend_api.py` — Phase 1 validator (web-app/dapp/backend: API spec, DB config, service entry, health, config, logging, lock files, unit tests)
- `scripts/validate_phase2_runtime_agents.py` — Phase 2 validator (agent-crew: agent defs, Dockerfile/process mgmt, crew config, comms, observability, lifecycle scripts)
- `scripts/validate_phase2_frontend_web.py` — Phase 2 validator (web-app/dapp: Next.js/Vite/Nuxt/SvelteKit/Astro, pages, components, TypeScript, lint, build, a11y, SEO, tests)
- `scripts/validate_phase2_mobile_flutter.py` — Phase 2 validator (mobile-flutter: pubspec, platform dirs, Android/iOS/desktop/web config, main.dart, analysis_options, tests, code signing, Fastlane, CI/CD, flavors, l10n)
- `scripts/validate_phase3_persistence_hardening.py` — Phase 3 validator (agent-crew/backend: backup/restore scripts, firewall, hardening, volumes, secrets, SSL, audit)
- `scripts/validate_phase3_smart_contracts.py` — Phase 3 validator (web3-dapp/contracts: Foundry/Hardhat/Brownie/Ape, contracts, tests, deploy, ABIs, gas, static analysis, verification, networks, deps, CI/CD, SPDX, NatSpec, sizes)
- `scripts/validate_phase4_integration_validation.py` — Phase 4 validator (agent-crew: e2e tests, CI/CD, deploy config, smoke tests, perf tests, security scans, docs, changelog, observability, feature flags)
- `scripts/validate_phase4_integration_web.py` — Phase 4 validator (web-app/dapp: same as above + web-specific deploy configs)
