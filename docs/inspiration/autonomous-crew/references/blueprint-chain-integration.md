# Blueprint-Chain Integration

## Blueprint → Loop-Enforcer Chain Pipeline

### 1. Validate Blueprint First

```bash
python3 scripts/validate-blueprint.py <blueprint.md> --json
# Must return 0 FAIL
```

### 2. Generate Checklist

```bash
python3 scripts/generate-checklist.py <blueprint.md>
# Outputs: checklist.md
```

### 3. Parse Phases from Checklist

```bash
python3 scripts/parse-checklist-phases.py <checklist.md>
# Outputs: JSON array of phases with section tags, feature flags
```

### 4. Create Loop-Enforcer Chain

```bash
python3 scripts/create-blueprint-chain.py <project-dir> <blueprint.md>
# Creates: .chain/<project>-blueprint.json
# Steps = phases, marker files = .phase-{n}-{flag}.marker
# Validators = generated phase validators
```

### 5. Generate Phase Validators

```bash
python3 scripts/generate-phase-validators.py <project-dir> <checklist.md>
# Creates: .chain/validators/phase_{n}_validator.py
# Validators check DELIVERABLES, not syntax
```

### 6. Wire Kanban to Chain

```bash
python3 scripts/wire-kanban-to-chain.py <crew-id> <chain-name>
# Creates kanban tasks for each phase, wired to chain step
# Task body includes chain check/verify/complete commands
```

### 7. Spawn Agents with Identity

```bash
# For each phase, spawn assigned agent with:
# - Constitution loaded at t=0
# - 4 habits: identity-enforcement, tool-enforcement, reflective-loop, blueprint-phase-gate
# - Enforcer daemon running
# - Memory pipeline initialized
# - Chain step assigned
```

### 8. Start Dispatcher

```bash
hemlock-agent gateway start
# Embedded dispatcher runs every 60s
# Reads chain state, dispatches next active phase
```

## Chain State Machine

```
locked → active → pending_verify → verified → complete
                 ↑                   │
                 └─── (retry) ───────┘
```

- **locked**: Prior phase not complete
- **active**: Ready for assigned agent to work
- **pending_verify**: Agent ran validator, awaiting result
- **verified**: Validator passed, next phase unlocked
- **complete**: Agent ran chain complete, phase done

## Phase Validator Design

### Tier 1: Syntax (necessary but insufficient)
```python
check_syntax(filepath)  # python -m py_compile, node --check, etc.
```

### Tier 2: Contract Compliance
```python
check_contract_compliance(filepath, spec.interface)
# - Function signatures match
# - Return types match
# - Error envelope format
```

### Tier 3: Functional Completeness
```python
run_functional_tests(filepath, spec.test_cases)
# - All test cases pass
# - Delivers what spec promises
```

### Tier 4: Character Alignment
```python
check_character_alignment(filepath, constitution_principles)
# - Honors agent's stated principles
# - No boundary violations
# - Completes what it starts
```

## Example: Mnemosyne Phase 0 Validator

```python
def validate_phase_0(project_root: Path) -> bool:
    checks = [
        ("src/config/index.js", "ConfigLoader with 25+ params"),
        ("src/services/logger.js", "Pino with correlation IDs"),
        ("src/services/metrics.js", "Counter/histogram/gauge"),
        ("src/services/health.js", "Subsystem status + latency"),
        ("src/services/circuit-breaker.js", "3-state machine"),
        (".env.example", "All 25+ env vars documented"),
        ("CHANGELOG.md", "CL-001 through CL-XXX present"),
        ("package.json", "type: module, all scripts defined"),
    ]
    return all(validate_deliverable(project_root / path, spec) for path, spec in checks)
```

## Kanban Task Body Template

```markdown
# {PROJECT}: Phase {n} — {title}

**Chain:** `{project}-blueprint`
**Step Index:** {n}
**Marker File:** `.phase-{n}-{flag}.marker`

## Required Workflow

**Before starting:**
```bash
python3 ${HEMLOCK_HOME}/skills/devops/loop-enforcer/scripts/chain.py check {project} {project}-blueprint .phase-{n}-{flag}.marker
```
If state is `locked` → STOP. Prior phase not complete.

**After completing work:**
```bash
# 1. Verify deliverables
python3 ${HEMLOCK_HOME}/skills/devops/loop-enforcer/scripts/chain.py verify {project} {project}-blueprint .phase-{n}-{flag}.marker

# 2. Complete step (unlocks next phase)
python3 ${HEMLOCK_HOME}/skills/devops/loop-enforcer/scripts/chain.py complete {project} {project}-blueprint .phase-{n}-{flag}.marker
```

## Checklist Reference
Full checklist: `{BASE}/{project}/checklist.md`
Full blueprint: `{BASE}/{project}/blueprint.md`