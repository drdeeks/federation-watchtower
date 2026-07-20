# Skill Update Workflow — CRITICAL

## NEVER use skill_manage(action='patch') to update skills

This is the #1 mistake that causes frustration. `skill_manage(action='patch')` only edits text — it does NOT run validation.

## Correct Workflow

```bash
# 1. Edit skill files (write_file, patch, etc.)
# 2. Run skill_enhance.py update
python3 <skill-creator-path>/scripts/skill_enhance.py update \
  --path <skill-path> \
  --tier enterprise \
  --noninteractive

# 3. Verify all 11 gates pass
```

## What skill_enhance.py Enforces

- Frontmatter validation (7+ tags, description)
- Script validation (3+ substantive, syntax, shebang, --help)
- Reference validation (5+ substantive, cross-references)
- Enterprise rules (58+ checks)
- Version bump
- Packaging

## User Correction Signal

If the user says anything about "use enhance script" or "stop using skill_manage", STOP and switch to skill_enhance.py immediately.
