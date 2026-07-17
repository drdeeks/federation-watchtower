# Loop-Enforcer × Skill-Creator Integration

How the enterprise skill pipeline uses loop-enforcer to lock its 11 gates.

## Pipeline Gates as Chain Steps

| Step | Gate | Chain Step | Description |
|------|------|------------|-------------|
| 1 | scaffold | `scaffold` | Auto-complete for create; skip for update |
| 2 | frontmatter | `frontmatter` | SKILL.md filled (tags, desc, no REPLACE_ME) |
| 3 | scripts | `scripts` | Substantive scripts ≥ tier minimum |
| 4 | references | `references` | Substantive refs ≥ tier minimum |
| 5 | validate | `validate` | Initial enterprise validation (informational) |
| 6 | auto_fix | `auto_fix` | Safe moves only, never deletes content |
| 7 | re_validate | `re_validate` | **HARD GATE** — must pass enterprise |
| 8 | test_scripts | `test_scripts` | Syntax + shebang + --help for every script |
| 9 | verify_sources | `verify_sources` | External URL/endpoint check (non-blocking) |
| 10 | package | `package` | Bumps version, emits `.skill` archive |
| 11 | extract_verify | `extract_verify` | Hash-compare archive vs source (no mutations) |

## Temp Chain Workdir (Auto-Clean)

```
skill-dir/
  SKILL.md, __init__.py, scripts/, references/, skill.skill
  # NO .chain/ or .chain-steps/ here!

/tmp/chain-skill-<name>-<random>/
  steps/
    scaffold, frontmatter, scripts, references,
    validate, auto_fix, re_validate, test_scripts,
    verify_sources, package, extract_verify
  # Chain state lives here, DELETED on completion
```

## Usage Pattern (from skill_enhance.py)

```python
from pathlib import Path
import tempfile, shutil, subprocess

LOOP_ENFORCER = Path("~/.hermes/skills/loop-enforcer/scripts/chain.py").expanduser()

def run_pipeline(skill_dir: Path):
    chain_name = f"skill-{skill_dir.name}"
    chain_workdir = Path(tempfile.mkdtemp(prefix=f"chain-{chain_name}-"))
    
    try:
        chain_step_dir = chain_workdir / "steps"
        chain_step_dir.mkdir()
        for s in CHAIN_STEPS:
            (chain_step_dir / s).touch()
        
        # Create chain
        subprocess.run(["python3", LOOP_ENFORCER, "create", 
                       str(chain_workdir), chain_name, 
                       *[str(chain_step_dir / s) for s in CHAIN_STEPS]])
        
        # For each gate:
        for i, step_name in enumerate(CHAIN_STEPS):
            step_path = chain_step_dir / step_name
            
            # 1. Do the actual work for this gate
            if step_name == "frontmatter":
                wait_for_frontmatter(skill_dir)
            elif step_name == "scripts":
                wait_for_scripts(skill_dir)
            # ... etc ...
            
            # 2. Verify (runs validator if set)
            subprocess.run(["python3", LOOP_ENFORCER, "verify",
                           str(chain_workdir), chain_name, str(step_path)])
            
            # 3. Complete (unlocks next)
            subprocess.run(["python3", LOOP_ENFORCER, "complete",
                           str(chain_workdir), chain_name, str(step_path)])
    
    finally:
        shutil.rmtree(chain_workdir, ignore_errors=True)  # ALWAYS CLEAN
```

## Key Design Points

1. **Skill root stays clean** — no chain artifacts left behind
2. **Each gate is a locked step** — cannot proceed until verified + completed
3. **Validator on re_validate gate** — set validator on the `re_validate` step for the hard enterprise check
4. **Temp dir auto-deletes** — `finally` block guarantees cleanup on success OR failure
5. **Chain state portable** — chain_workdir can be anywhere (tmpfs, disk, etc.)

## Agent Integration

Agents MUST check before touching skill files:

```bash
# Before editing SKILL.md
python3 ~/.hermes/skills/loop-enforcer/scripts/chain.py check \
  /tmp/chain-skill-xyz skill-my-skill /tmp/chain-skill-xyz/steps/frontmatter
# Returns: "active" (can edit) or "locked" (cannot edit)
```

The skill-creator pipeline enforces this programmatically — but any external tool/agent working on skills should also respect the chain.