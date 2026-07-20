# Skill Creator Validation Workflow with skill_enhance.py

## Overview

This document describes the enterprise-tier skill validation workflow using `skill_enhance.py` from the skill-creator skill (NOT skill-creator-pro). This is the mandatory validation pipeline for all skills in this environment.

## Validation Pipeline

```bash
# Run enterprise validation on a skill
python3 ~/agent-toolkit-v14/skills/skill-creator/scripts/skill_enhance.py update \
    --path <skill-dir> \
    --noninteractive
```

## Enterprise Tier Gates (All Must Pass)

| Gate | Requirement | Auto-Fixable |
|------|-------------|--------------|
| SKILL.md frontmatter | 7+ tags, description ok, no REPLACE_ME | No |
| scripts/ | 5+ substantive scripts | Yes (safe moves) |
| references/ | 7+ substantive docs | Yes (safe moves) |
| validate.py | All checks pass | No (informational) |
| auto_fix.py | Safe moves only, never deletes | Yes |
| re-validate | HARD GATE — must pass | No |
| test_script.py | Syntax + shebang + --help | No (blocking) |
| verify_sources.py | External source check | No |
| package_skills.py | Package skill archive | Yes |

## Validation Output Codes

```
✓ = pass    ✗ = fail    · = informational
```

**Critical:** The re-validate step after auto_fix is the HARD GATE. If it fails, the skill does NOT meet enterprise tier.

## Platform-Agnostic Path Requirements

**NEVER use hardcoded paths in skills:**
- ❌ `${WORKSPACE_ROOT}/...`
- ❌ `/root/...`
- ❌ `/Users/...`

**USE placeholders:**
- ✅ `<HEMLOCK_HOME>` — Hermes home directory
- ✅ `<WORKSPACE_ROOT>` — Workspace root directory
- ✅ `~/.hermes` — User Hermes directory
- ✅ `$HOME` — Home directory

The validator will FAIL on hardcoded paths in scripts and references.

## Required Frontmatter Tags (Enterprise)

```yaml
metadata:
  tags:
    - <domain-tag-1>
    - <domain-tag-2>
    - <domain-tag-3>
    - <domain-tag-4>
    - <domain-tag-5>
    - <domain-tag-6>
    - <domain-tag-7>
    - <domain-tag-8>
  category: <devops|data-science|mlops|...>
  hermes:
    tags: [<tag1>, <tag2>, <tag3>]
    related_skills: [<skill1>, <skill2>]
```

**Minimum 7 tags required.** Recommended tags for this project:
- `enterprise`, `automation`, `orchestration`, `kanban`, `chain-enforcement`
- `platform-agnostic`, `multi-agent`, `validation-over-syntax`

## Scripts Requirements (Enterprise)

- **Minimum 5 substantive scripts** in `scripts/`
- Must have shebang (`#!/usr/bin/env python3` or `#!/bin/bash`)
- Must support `--help` flag
- Must pass syntax check
- Cannot be empty or placeholder

## References Requirements (Enterprise)

- **Minimum 7 substantive reference docs** in `references/`
- Must be markdown (.md) with real content
- Cannot be empty or placeholder
- Should reference external sources if applicable

## Common Validation Failures & Fixes

### 1. Hardcoded Path in Script
```
✗ [FAIL] Hardcoded path in script — scripts/chain_enforce.py:10
```
**Fix:** Replace `${WORKSPACE_ROOT}/qwen-cloud-2026` with `<WORKSPACE_ROOT>/qwen-cloud-2026`

### 2. Unexpected Frontmatter Keys
```
✗ [FAIL] Unexpected keys: environments, platforms
```
**Fix:** Remove `platforms` and `environments` from frontmatter. Use only `metadata.tags` and `metadata.category`.

### 3. Insufficient References/Scripts
```
✗ [FAIL] References: need 7+, got 5
```
**Fix:** Add 2+ more substantive .md files to `references/`

### 4. Empty or Placeholder Files
```
✗ [FAIL] scripts/test.sh is empty or placeholder
```
**Fix:** Add real implementation or remove from count

### 5. Missing Shebang or --help
```
✗ [FAIL] scripts/myscript.py: missing shebang or --help support
```
**Fix:** Add `#!/usr/bin/env python3` and `--help` handling

## Running Validation Locally

```bash
# 1. Check initial status (informational)
python3 ~/agent-toolkit-v14/skills/skill-creator/scripts/validate.py <skill-dir>

# 2. Run auto-fix (safe moves only)
python3 ~/agent-toolkit-v14/skills/skill-creator/scripts/auto_fix.py <skill-dir>

# 3. Re-validate (HARD GATE)
python3 ~/agent-toolkit-v14/skills/skill-creator/scripts/validate.py <skill-dir>

# 4. Full pipeline
python3 ~/agent-toolkit-v14/skills/skill-creator/scripts/skill_enhance.py update \
    --path <skill-dir> \
    --noninteractive
```

## Version Bumping

On successful package, skill_enhance.py auto-bumps version:
- Patch: bug fixes, docs
- Minor: new features, scripts, references
- Major: breaking changes

## Package Verification

The pipeline extracts and verifies the .skill archive:
```
✓ extracted archive verified — version=X.Y.Z, root layout intact, all file hashes match source (no mutations)
```

## Do NOT Use

- ❌ skill-creator-pro (not available in this environment)
- ❌ Manual version editing in SKILL.md (auto-managed)
- ❌ Hardcoded paths anywhere in skill files
- ❌ Empty scripts/references to pad counts

## See Also

- `references/enterprise-validation-pitfalls.md` — Common pitfalls when using skill_enhance.py
- skill-creator skill — Author, edit, audit, validate, package, upgrade AgentSkills