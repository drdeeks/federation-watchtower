# Enterprise Blueprint Skill Validation Pitfalls

## 1. Hardcoded Paths in References

**Symptom:** `skill_enhance.py` fails with `[WARN] Hardcoded path in doc — references/<file>.md → '${USB_MOUNT}/$HOME'`

**Cause:** Session-specific paths leaked into reference documents. The validator scans ALL files in the skill, including `references/`.

**Fix:** Replace `${USB_MOUNT}/$HOME` with `${USB_MOUNT}` placeholders in ALL reference files, not just scripts.

**Example:**
```markdown
# Before (FAILS)
- `${USB_MOUNT}/projects/hemlock-test` (2.4G)

# After (PASSES) 
- `${USB_MOUNT}/projects/hemlock-test` (2.4G)
```

## 2. Placeholder Markers in SKILL.md

**Symptom:** `[FAIL] Contains placeholder marker → Line: - [ ] No placeholder markers in production code`

**Cause:** A checklist item `- [ ] No placeholder markers in production code` was left in the SKILL.md body. The validator treats this as a placeholder marker.

**Fix:** Remove or complete the checkbox item. The validator does not distinguish between "real" markers and "example" markers in markdown.

## 3. Missing Reference Links in SKILL.md

**Symptom:** `[WARN] Reference not referenced in SKILL.md → Missing: references/<file>.md`

**Cause:** New reference files added to `references/` but not linked from the SKILL.md references section.

**Fix:** Every file in `references/` MUST be listed in the SKILL.md references section with a one-line description and when-to-read guidance.

## 4. `__pycache__` in Scripts Directory

**Symptom:** `[FAIL] Subdirectory in scripts/ — __pycache__` and `[FAIL] Cached/junk dir found`

**Cause:** Python bytecode cache created during script execution.

**Fix:** Run `find scripts/ -name __pycache__ -type d -exec rm -rf {} +` before validation. Add to CI.

## 5. Script Missing `--help` Handler

**Symptom:** `[FAIL] Runtime: --help timed out after 30s` or `--help exited 1 with no usage text`

**Cause:** Script doesn't handle `--help` flag, or it tries to run main logic before checking for help.

**Fix:** Add `--help` check at TOP of `main()`:
```python
def main():
    if "--help" in sys.argv or "-h" in sys.argv:
        print("Script Name")
        print("Usage: script.py [options]")
        sys.exit(0)
    # rest of main...
```

## 6. Provider Tags in Frontmatter (Enterprise)

**Symptom:** Provider tag remap: `openclaw`, `hermes` → tags remapped into `metadata.{openclaw,hermes}.tags`

**Cause:** Frontmatter has `providers:` list at top level. Enterprise validator moves these to `metadata.openclaw.tags` and `metadata.hermes.tags`.

**Fix:** Ensure `metadata.openclaw` and `metadata.hermes` exist with their own `tags` arrays. The validator will remap automatically.

## 7. Script Referenced But Not in SKILL.md

**Symptom:** `[WARN] Script not referenced in SKILL.md → Missing: scripts/<script>.py`

**Cause:** New script added to `scripts/` but not listed in the SKILL.md scripts table.

**Fix:** Add every script to the scripts table with purpose description.

---

## Validation Checklist Before Running `skill_enhance.py`

- No `${USB_MOUNT}/$HOME` or absolute paths in ANY file (scripts, refs, SKILL.md)
- No placeholder markers in SKILL.md body (checkboxes count)
- Every file in `references/` linked in SKILL.md references section
- `scripts/__pycache__` removed
- Every script has `--help` handler that exits 0
- Every script listed in SKILL.md scripts table
- Frontmatter has `metadata.openclaw.tags` and `metadata.hermes.tags`
- No provider names hardcoded in scripts (use env vars / config)

---

## Session 2026-07-09 Fixes Applied

| Issue | Files Fixed |
|-------|-------------|
| Hardcoded `${USB_MOUNT}` in hackathon-blueprint-lessons.md | Replaced with `${USB_MOUNT}` placeholders |
| Placeholder marker in SKILL.md line 433 | Removed `- [ ] No placeholder markers in production code` |
| Missing reference links | Added 6 missing references to SKILL.md |
| `__pycache__` in scripts/ | Deleted |
| `blueprint_validator.py` missing `--help` | Added handler |
| `enforce_blueprint.py` import error | Fixed imports to use `ChecklistGenerator` and `BlueprintValidator` classes |

---

*Generated during enterprise-blueprint v2.0.0 → v2.0.1 validation cycle*