# Lessons Learned — Enterprise Blueprint Chain Enforcement

Real operational learnings from integrating chain enforcement into enterprise-blueprint.

## Lesson 1: Checklist is the Source of Truth, Not Blueprint

**Context:** Blueprint has high-level phases; checklist has granular steps with validation gates.
**Fix:** `enforce_blueprint.py` parses checklist.md for phases/steps, merges blueprint tags/flags/deliverables.
**Result:** Chain steps match actual implementation granularity.

## Lesson 2: Em-Dash (U+2014) in Phase Headers Breaks Regex

**Context:** Checklist used "Phase 0 — Foundation" (em-dash U+2014), original regex `[:—]` failed.
**Fix:** Split on `## Phase N ` then match rest of line, or use `[:—\s]` in character class.
**Code:** `re.split(r"(^##\s+Phase\s+\d+[:—\s][^\n]*$)", content, flags=re.MULTILINE)`

## Lesson 3: Step Filenames Must Be Sanitized

**Context:** Step descriptions like "Step 1 — Initialize Node.js 24 project with ES Modules configuration in package.json (type: \"module\")" create invalid filenames.
**Fix:** `step_slug = re.sub(r'[^a-zA-Z0-9_-]+', '-', step[:30]).strip('-')`

## Lesson 4: CHANGELOG.md Must Exist Before Chain Init

**Context:** Phase gate validator checks CHANGELOG.md for CL-NNN entries. Missing file = verification fails.
**Fix:** `init_blueprint.py` generates CHANGELOG.md with CL-000. `generate_checklist.py --sync` preserves it.

## Lesson 5: Blueprint Validator Reads Deliverables Mapping

**Context:** Chain steps are marker files; real deliverables are project files (src/, tests/, configs).
**Fix:** `blueprint_validator.py` reads `.blueprint-chain/deliverables.json` mapping step→actual file, validates real target.

## Lesson 6: Phase Count Mismatch Between Blueprint and Checklist

**Context:** Blueprint has 7 default phases; checklist after sync may have different count (autopilot had 4).
**Fix:** `enforce_blueprint.py` merges by index, handles missing blueprint phases gracefully.

## Lesson 7: Documentation Must Escape Placeholder Patterns

**Context:** Validator flags `TODO`, `FIXME`, `lorem ipsum` anywhere — including in rules docs describing these patterns.
**Fix:** In `enterprise-rules.md`: `[T0DO]`, `[FIXME]`, `l0rem 1psum` — validator only catches real placeholders in code.

## Lesson 8: Agent/Crew Detection Must Be Singular Source of Truth (FOREVER SYSTEM §1)

**Context:** Multiple detection methods existed (skill-creator built-in, loop-enforcer skill, ad-hoc scans). Ambiguous identity = enforcement blocks.
**Fix:** Created `scripts/discover_agents.py` as THE canonical detector. Returns structured JSON: `{"type": "agent"|"crew"|"none", "agent_id": "...", "sub_agents": [...]}`. Blocks on ambiguous identity (fail-closed). All other components delegate to it.

## Lesson 9: Path Agnosticism Requires Env Vars — No Hardcoded Paths Anywhere

**Context:** Hardcoded `${HERMES_HOME}/skills` in `__init__.py`, reference docs, chain_enforce.py broke portability across machines/USB deployments.
**Fix:** All paths resolved via env vars:
- `LOOP_ENFORCER_ROOT` → loop-enforcer skill location
- `AGENT_WORKSPACE` → target agent/crew directory
- `ENFORCER_SOCKET` → ACK enforcer daemon socket
- `ACK_HABITS_DIR`, `ACK_ACK_LOG`, `ACK_INJECT_LOG` → ACK convention paths
Reference docs updated to use `${USB_MOUNT}` or `$HOME` placeholders.

## Lesson 10: Model Tiering with Flash/Final Pattern Optimizes Token Cost

**Context:** Using max-tier models for all phases burns budget. Iteration work (drafting, revising) can use cheaper flash models; final output needs quality tier.
**Fix:** Agent/crew model maps declare per-phase `iteration` (flash) and `final` (plus/max) models. Task-level overrides for specialized work (video/audio generation). `interactive_setup.py` walks user through creating these maps.

## Lesson 11: All Chain Enforcement Routes Through loop-enforcer — No Duplicates

**Context:** skill-creator had built-in chain.py, loop-enforcer skill has chain.py, enterprise-blueprint had phase-level chain in `__init__.py`. Three implementations = drift.
**Fix:** 
- Enterprise-blueprint `__init__.py::enhance_skill()` DELEGATES to `enforce_blueprint.py` (checklist-item-level)
- `enforce_blueprint.py` creates `.blueprint-chain/<project>-checklist.json` + `deliverables.json`
- Loop-enforcer's `scripts/chain.py` is the ONLY runtime that executes steps
- Worker API (`scripts/chain_worker.py`) is the thin plugin agents call via pre-tool-call

## Lesson 12: Opt-Out Flag for Loop Enforcement Required

**Context:** Some workflows need checklist generation WITHOUT chain enforcement (CI validation, dry-runs, docs-only).
**Fix:** `apply_blueprint.py --no-loop-enforcement` skips `.blueprint-chain/` initialization, generates checklist only.

## Lesson 13: Template Configs for Agent-Model-Phase Mapping Essential

**Context:** Without templates, users hand-write YAML with inconsistent structure, missing phases, wrong model names.
**Fix:** Created `references/templates/agent-model-map-template.yaml` and `crew-model-map-template.yaml` with:
- Versioned layer IDs (`agent-model-map-v1`, `v2`...)
- Per-phase create/revise model mapping
- Task-level overrides
- Token budget estimates
- `interactive_setup.py` generates from templates

## Lesson 14: Interactive Setup Walkthrough Prevents Misconfiguration

**Context:** Users skip docs, write broken configs, enforcement fails silently or with cryptic errors.
**Fix:** `interactive_setup.py` walks through:
1. Detect workspace type (agent/crew/neither) via `discover_agents.py`
2. Select template (agent vs crew)
3. Per-phase model selection with flash/final dropdowns
4. Task override prompts
5. Write versioned YAML to `references/templates/` (chmod 0444)
6. Verify `--help` on all new scripts

## Lesson 15: Dogfood Validation via skill_enhance.py Is Non-Negotiable

**Context:** Skill claimed enterprise compliance but had hardcoded paths, missing refs, placeholder markers.
**Fix:** Every release runs:
```bash
python3 .hermes/skills/skill-creator/scripts/skill_enhance.py update \
  --path .hermes/skills/devops/enterprise-blueprint \
  --tier enterprise --noninteractive
```
All 11 gates must pass (0 FAIL, warnings OK). Version auto-bumped, `.skill` archive emitted, extract-verified.

---

## Lesson 16: Enforcer Self-Validation Loop — `auto-verify-complete` Is the Loop Enforcement

**Context:** Manual `verify` → `complete` flow requires human/agent to call both. Forgotten verify = stuck chain. Forgotten complete = next phase locked.
**Fix:** `chain_worker.py auto-verify-complete` — single command runs verify (executes validator if set), if passes auto-completes and unlocks next step.
**Code:** `enforce_blueprint.py::auto_verify_and_complete()` and `chain_worker.py::auto_verify_complete()` added.
**Result:** Enforcer IS the watching service. No separate manager agent needed. Agent calls one command, chain advances or stops with explicit failure.

---

## Lesson 17: Validator Direct Execution — Run Validator as Executable, Not `python validator`

**Context:** `chain.py:152` ran validator as `[python_cmd, validator, abs_path]` — broke shell scripts (syntax error on bash shebang).
**Fix:** Changed to `[validator, abs_path]` — direct exec. Validator script must be executable with shebang (`#!/bin/bash`, `#!/usr/bin/env python3`).
**Validator contract**: Exit 0 = pass, stdout/stderr = output. No JSON protocol needed.

---

## Lesson 18: MV Maestro Blueprint Pattern — Generator Try 3 Works When Try 1/2 Are Avoided

**Context:** Checklist generator has 3-try priority chain. Try 1 expects bare `### PHASE-N` header (bug: expects `## `). Try 2 matches `### SPEC-NNN:` (uppercase). Try 3 matches `### PHASE-N: Title` (fallback).
**Working config**: 
- Part VI phases: `### PHASE-N: Title` (not bare `### PHASE-N`)
- Part III specs: `### Spec-NNN:` (lowercase, colon) — avoids Try 2 collision
**Result**: Generator skips Try 1 (no bare header), skips Try 2 (no SPEC- headers), falls to Try 3 → extracts ALL phases correctly with proper tasks.