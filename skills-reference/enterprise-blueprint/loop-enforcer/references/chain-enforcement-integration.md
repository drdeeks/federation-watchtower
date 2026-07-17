# Chain Enforcement Integration Pattern

How to integrate loop-enforcer chain enforcement into ANY multi-step pipeline.

Used by `skill-creator/skill_enhance.py` for the 11-step enterprise pipeline.

## Core Pattern

```python
from pathlib import Path
import tempfile, shutil, subprocess, sys

LOOP_ENFORCER = Path("~/.hermes/skills/loop-enforcer/scripts/chain.py").expanduser()

def run_pipeline(chain_name: str, steps: list[str], work_fn):
    # 1. Create TEMP workdir (NOT in project root!)
    chain_workdir = Path(tempfile.mkdtemp(prefix=f"chain-{chain_name}-"))
    step_dir = chain_workdir / "steps"
    step_dir.mkdir()
    
    # Create marker files for each step
    for s in steps:
        (step_dir / s).touch()
    
    try:
        # 2. Create chain
        step_paths = [str(step_dir / s) for s in steps]
        subprocess.run([sys.executable, str(LOOP_ENFORCER), "create", 
                       str(chain_workdir), chain_name, *step_paths], check=True)
        
        # 3. For each step: verify → run work → complete
        for i, step_path in enumerate(step_paths):
            # Check if active (will be locked until previous completes)
            # Run the actual work for this step
            work_fn(i, step_path)
            
            # Verify (runs validator if set)
            subprocess.run([sys.executable, str(LOOP_ENFORCER), "verify",
                           str(chain_workdir), chain_name, str(step_path)], check=True)
            
            # Complete (unlocks next)
            subprocess.run([sys.executable, str(LOOP_ENFORCER), "complete",
                           str(chain_workdir), chain_name, str(step_path)], check=True)
        
        return True
    finally:
        # 4. ALWAYS clean up (self-delete)
        shutil.rmtree(chain_workdir, ignore_errors=True)
```

## skill-creator's 11-Step Pipeline

```python
STEPS = [
    "scaffold",        # 0: auto-complete for create
    "frontmatter",     # 1: SKILL.md filled in
    "scripts",         # 2: 3+ substantive scripts
    "references",      # 3: 5+ substantive refs
    "validate",        # 4: validate.py (ENTERPRISE)
    "auto_fix",        # 5: auto_fix.py
    "re_validate",     # 6: validate.py (HARD GATE)
    "test_scripts",    # 7: test_script.py
    "verify_sources",  # 8: verify_sources.py
    "package",         # 9: package_skills.py
    "extract_verify",  # 10: extract + hash compare
]
```

## Key Principles

| Principle | Implementation |
|---|---|
| **Temp workdir** | `/tmp/chain-<name>-<random>/` — never pollutes skill root |
| **Atomic gates** | Each step verified + completed before next unlocks |
| **Self-cleaning** | `finally: shutil.rmtree()` — cleans on success OR failure |
| **Validator per step** | `chain.py set-validator` attaches step-specific checks |
| **Audit trail** | `.chain/<name>.log` in temp dir records every transition |

## Why This Works

1. **No skill pollution** — `.chain/` and `.chain-steps/` never touch the skill directory
2. **Enforced sequence** — can't run "package" before "re_validate" passes
3. **Visible progress** — `chain.py status` shows exactly where pipeline is
4. **Recoverable** — if interrupted, chain state persists in temp dir
5. **Testable** — each step is independently verifiable

## Reuse in Other Skills

Any skill with a multi-step pipeline (build → test → lint → package → deploy, etc.) can copy this exact pattern. The only skill-specific part is `work_fn` — the chain mechanics are identical.