# Enterprise Validation Pitfalls

## CRITICAL: NEVER Use skill_manage(action='patch') to Update Skills

The user has corrected this MULTIPLE TIMES. This is the #1 pitfall.

`skill_manage(action='patch')` only edits the SKILL.md text. It does NOT:
- Run validate.py
- Run auto_fix.py
- Run re-validate (hard gate)
- Run test_script.py (syntax + shebang + --help)
- Run verify_sources.py
- Run package_skills.py (version bump + .skill archive)

**Result:** Skills look correct but have broken scripts, missing --help handlers, hardcoded paths, or syntax errors that only surface at runtime.

### Correct Workflow

```bash
# 1. Make changes to skill files directly
#    (write_file, patch, or edit scripts/references as needed)

# 2. Run the full validation pipeline
python3 <skill-creator-scripts>/skill_enhance.py update \
    --path <skill-name> \
    --tier enterprise \
    --noninteractive

# 3. Verify ALL 11 gates pass
#    Look for: "enterprise-tier pipeline COMPLETE — all gates passed, chain enforced"

# 4. If test_script.py fails, fix the failing scripts BEFORE re-running
python3 <skill-creator-scripts>/test_script.py <skill-name>/scripts/
```

### What Each Gate Does

| Gate | What It Checks | What Happens If Fails |
|------|----------------|----------------------|
| extract | Extracts skill from archive | Pipeline stops |
| scaffold | Creates new skill (skipped for update) | N/A |
| SKILL.md frontmatter | 7+ tags, description, no REPLACE_ME | Pipeline stops |
| scripts/ | 3+ substantive scripts exist | Pipeline stops |
| references/ | 5+ substantive docs exist | Pipeline stops |
| validate.py | Enterprise validation (58+ rules) | Auto-fix runs, then re-validate |
| auto_fix.py | Safe moves only (no destructive changes) | Informational |
| re-validate | HARD GATE — must pass after auto_fix | Pipeline stops |
| test_script.py | Syntax + shebang + --help for ALL scripts | Pipeline stops |
| verify_sources.py | External source check | Informational |
| package_skills.py | Bumps version, emits .skill archive | Pipeline stops |

### Common Mistake Pattern

```
# WRONG — this only edits text, no validation
skill_manage(action='patch', name='my-skill', old_string='...', new_string='...')

# RIGHT — edit files, then validate
# Step 1: edit the files
write_file(path='skills/my-skill/SKILL.md', content='...')
# Step 2: validate
terminal(command='python3 skill_enhance.py update --path my-skill --tier enterprise --noninteractive')
```

---

## __pycache__ Directory in Scripts

The validator flags `__pycache__` as a cached/junk directory.

**Fix:** Before running skill_enhance.py, clean up:
```bash
rm -rf <skill-dir>/scripts/__pycache__
```

---

## Script Fails test_script.py

Scripts must pass syntax check, have shebang, and support `--help`.

**Common failure:** Script crashes on `--help` because it requires arguments before parsing.

**Fix:** Add early `--help` handler before any imports that require arguments:
```python
import sys
if len(sys.argv) > 1 and sys.argv[1] in ("--help", "-h"):
    print("Usage: script.py <args>")
    print("Description of what it does.")
    sys.exit(0)
```

---

## Hardcoded Paths

The validator FAILS on hardcoded paths like `/home/<user>/...` in scripts and references.

**Fix:** Replace with placeholders:
- `$HOME/qwen-cloud-2026` → `${WORKSPACE_ROOT}/qwen-cloud-2026`
- `$HOME/.hermes` → `${HEMLOCK_HOME}` or `~/.hermes`
- `$HOME/projects` → `${WORKSPACE_ROOT}/projects`

---

## Skill Name Ambiguity

If `skill_view(name='autonomous-crew')` returns "Ambiguous skill name", use the categorized path:
```bash
skill_view(name='devops/autonomous-crew')
```

This happens when the same skill name exists in multiple directories.
