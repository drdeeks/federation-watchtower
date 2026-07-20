# Enforcer Validation Architecture

## The Core Problem Solved This Session

**Original issue**: The `auto-verify-complete` flag allowed agents to **validate their own work** — creator reviewing own output. This violates Creative Orchestration Doctrine Principle V: *Critique Is Equal to Creation* — the reviewer must be independent from the creator.

## Architecture After Fix

```
┌─────────────────────────────────────────────────────────────────┐
│                        ENFORCER (loop-enforcer)                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Chain State    │  │  Validators     │  │  Gate Logic     │  │
│  │  (.chain/*.json)│  │  (per-phase)    │  │  (verify→complete)│
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
└───────────┼────────────────────┼────────────────────┼───────────┘
            │                    │                    │
            ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        AGENT INTERFACE                           │
│  chain_worker.py:  check → verify (enforcer runs validator)     │
│                                      → complete                  │
│  NO auto-verify-complete (removed)                               │
└─────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. Validator Registry (`scripts/validator_registry.py`)
Maps `project_type` → `{phase_index: validator_script}`. Extensible for new project types.

### 2. Blueprint Frontmatter
```markdown
**Project Type:** `web-app`   # or agent-crew, web3-dapp, mobile-flutter, etc.
```

### 3. Chain Initialization (`enforce_blueprint.py`)
- Reads project type from blueprint
- Looks up validator map from registry
- Creates `.blueprint-chain/` marker files + `validators.json` mapping each gate → validator
- Calls `chain.py create` to initialize actual chain state in `.chain/`

### 4. Verification Flow
```
Agent: chain_worker.py verify <step>
  │
  ▼
Enforcer (chain.py): 
  1. Reads validator from state
  2. Executes: validator_script <step_path>
  3. Exit code 0 → step.state = "verified", next step = "active"
  4. Exit code 1 → step.state = "active" (stay), output error
  │
  ▼
Agent: chain_worker.py complete <step>  (only if verified)
```

### 5. Validator Contract
```bash
# All validators share this interface
python3 validate_phaseX_*.py <project_root>
# Exit 0 = PASS, 1 = FAIL, 2 = usage error
# Stdout: ✓/✗ per check with details
# Stderr: execution errors only
```

## Phase Gate Pattern (Per Phase)

Each phase has:
- Phase gate (prerequisite check)
- N task steps (work items)
- **Validation gate** (enforcer-run validator)

Example for Phase 0:
```
phase-00-Phase-0:-Foundation          ← Phase gate (checks CHANGELOG.md)
phase-00-step-01-PHASE-0.1-...        ← Task 1
phase-00-step-02-PHASE-0.V-...        ← VALIDATION GATE (runs validate_phase0_foundation.py)
```

## Project Types Supported (Fully Validated This Session)

| Type | Phases 0-4 Validators |
|------|----------------------|
| `agent-crew` | foundation → core_services → runtime_agents → persistence_hardening → integration_validation |
| `web-app` | foundation → backend_api → frontend_web → persistence_hardening → integration_web |
| `web3-dapp` | foundation → backend_api → frontend_web → smart_contracts → integration_web3 |
| `mobile-flutter` | foundation → backend_api → mobile_flutter → mobile_hardening → integration_mobile |

## Partially Implemented / Planned Project Types

| Type | Phase 0 | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|------|---------|---------|---------|---------|---------|
| mobile-react-native | foundation | backend_api | 🚧 mobile_react_native | mobile_hardening | integration_mobile |
| desktop-tauri | foundation | backend_rust | 🚧 desktop_tauri | desktop_hardening | integration_desktop |
| desktop-electron | foundation | backend_node | 🚧 desktop_electron | desktop_hardening | integration_desktop |
| desktop-wails | foundation | backend_go | 🚧 desktop_wails | desktop_hardening | integration_desktop |
| cli-rust | foundation | cli_rust | cli_rust | cli_hardening | integration_cli |
| cli-go | foundation | cli_go | cli_go | cli_hardening | integration_cli |
| cli-python | foundation | cli_python | cli_python | cli_hardening | integration_cli |
| cli-node | foundation | cli_node | cli_node | cli_hardening | integration_cli |
| backend-fastapi | foundation | backend_fastapi | backend_fastapi | persistence_hardening | integration_backend |
| backend-node | foundation | backend_node | backend_node | persistence_hardening | integration_backend |
| backend-go | foundation | backend_go | backend_go | persistence_hardening | integration_backend |
| backend-rust | foundation | backend_rust | backend_rust | persistence_hardening | integration_backend |
| smart-contracts | foundation | sc_core | sc_advanced | ✅ smart_contracts | integration_sc |
| ml-pipeline | foundation | ml_data | ml_training | ml_serving | integration_ml |
| infra-terraform | foundation | terraform_core | terraform_modules | terraform_hardening | integration_infra |
| docs-site | foundation | docs_content | docs_site | docs_hardening | integration_docs |

✅ = Implemented and tested | 🚧 = Planned/Stub | (blank) = Not started

## Critical Invariants Maintained

1. **Enforcer owns validators** — Agent never calls validator directly
2. **Phase N+1 locked until Phase N validated + completed** — Chain state enforces this
3. **Validators check real deliverables** — Not placeholder commands
4. **Fail-closed** — Any validator error → phase stays active
5. **Idempotent validators** — Safe to re-run
6. **No auto-verify-complete** — Explicit verify → complete separation

## Testing the Architecture

```bash
# Initialize project with project type
cd /tmp/test-project
echo "**Project Type:** \`web-app\`" > blueprint.md
# ... add phases ...
python3 scripts/generate_checklist.py blueprint.md -o checklist.md
python3 scripts/enforce_blueprint.py . --init

# Verify phase 0 (enforcer runs foundation validator)
python3 scripts/enforce_blueprint.py . --phase 0 --verify

# Complete phase 0 (only if verified)
python3 scripts/enforce_blueprint.py . --phase 0 --complete

# Phase 1 now active
python3 scripts/enforce_blueprint.py . --phase 1 --verify
```

## Lessons Learned

1. **Registry pattern scales** — Adding new project types = adding validator scripts + registry entry
2. **Blueprint frontmatter = source of truth** — Single declaration drives entire validation pipeline
3. **Chain state in `.chain/` is the lock** — No separate daemon needed, survives restarts
4. **Validator exit codes = gate** — Simple, universal, language-agnostic
5. **Separation of verify/complete is essential** — Enforcer validates, agent completes; never conflate

## Validator Execution Pitfalls (Critical)

### ❌ NEVER use `python3 validator.py`
This breaks shebang scripts and shell validators. Run validator DIRECTLY:

```python
# CORRECT - Direct execution
validator = step.get("validator")
if validator:
    try:
        result = subprocess.run(
            [validator, abs_path],  # Run validator directly
            capture_output=True, text=True, timeout=30
        )
        passed = result.returncode == 0
        output = result.stdout + result.stderr
    except Exception as e:
        passed = False
        output = str(e)
```

### ✅ All validators must be executable
```bash
chmod +x scripts/validate_phase*.py
```

### ✅ Validators receive step file path — navigate to project root
```python
project_root = Path(step_path).parent.parent
```

### ✅ Exit codes = pass/fail
- 0 = pass
- non-zero = fail
- Stdout/stderr captured for output

### ✅ Sanitize filenames consistently
```python
# Both create and lookup must use same sanitization
step_name = step[:40].replace(' ', '-').replace('—', '').replace(':', '').replace('/', '-')
```

### ✅ Phase gate step index = num_phase_steps + 1
Phase steps: 1..N, Gate: N+1. Lookup logic must match.