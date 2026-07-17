---
name: skill-installer
description: "Graceful skill installation and lifecycle manager. Handles .skill zip archives, directory-based skills, and remote packages with automatic validation against skill-creator. Use when: installing new skills, updating skills, extracting .skill files, importing skill packages, or validating skill integrity before deployment."
version: 1.0.11
license: MIT
metadata:
  author: skill-creator
  category: skill-management
  tags:
    - install a skill
    - skill installation
    - extract skill archive
    - import skill package
    - batch install skills
    - skill lifecycle management
    - validate before install
---

# Skill Installer

Graceful skill installation and lifecycle manager that handles all skill formats with automatic validation.

## When to Use

- Installing new skills from .skill zip archives
- Importing skill packages from remote sources
- Updating existing skills with newer versions
- Extracting and integrating bundled skill packages
- Validating skill integrity before deployment
- Batch installing multiple skills from a directory

## Features

- **Multi-format support**: .skill zip archives, directory-based skills, remote packages
- **Automatic extraction**: Graceful handling of nested zip structures
- **Validation-first**: Every skill validated against skill-creator before installation
- **Rollback support**: Failed installations automatically reverted
- **Duplicate detection**: Prevents overwriting without explicit confirmation
- **Batch operations**: Install/update entire skill packages at once
- **Integrity checks**: Verify checksums and signatures when available

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCODE_SKILLS_DIR` | `${SKILLS_DIR}` | Skills installation directory |
| `SKILL_TEMP_DIR` | System temp | Temporary extraction directory |

## Skill Format Handling

### .skill Zip Archives

.skill files are zip archives containing the full skill directory structure:

```bash
# Single skill installation
python3 scripts/install_skill.py /path/to/skill.skill --target "${OPENCODE_SKILLS_DIR}"

# With validation
python3 scripts/install_skill.py /path/to/skill.skill --target "${OPENCODE_SKILLS_DIR}" --validate
```

### Directory-Based Skills

Skills structured as directories with SKILL.md:

```bash
# Install from directory
python3 scripts/install_skill.py /path/to/skill-directory/ --target "${OPENCODE_SKILLS_DIR}"

# Install with all subdirectories
python3 scripts/install_skill.py /path/to/skills/ --target "${OPENCODE_SKILLS_DIR}" --recursive
```

### Remote Packages

```bash
# Install from URL
python3 scripts/install_skill.py https://example.com/skill.skill --target "${OPENCODE_SKILLS_DIR}"

# Install from git repository
python3 scripts/install_skill.py git@github.com:user/repo.git --target "${OPENCODE_SKILLS_DIR}"
```

## Installation Workflow

### Step 1: Detect Format

Format detection is built into the installer — `install_skill.py` identifies
.skill archives, skill directories, and remote packages automatically before
doing anything else. There is no separate detection script to run.

### Step 2: Extract (if needed)

```bash
python3 scripts/extract_skill.py /path/to/skill.skill --output "${SKILL_TEMP_DIR}/skill-extract/"
```

Handles:
- Nested zip archives
- Multiple skills in single package
- Preserves directory structure
- Extracts SKILL.md, scripts/, references/

### Step 3: Validate

```bash
python3 scripts/validate_install.py /path/to/extracted-skill/ [--enterprise] [--json]
```

All rules come from skill-creator's `validate.py` — a live install if one is
present, otherwise the byte-identical copy bundled in this skill's
`scripts/`. This skill works standalone; it never invents rules of its own.

### Step 4: Install

```bash
python3 scripts/install_skill.py /path/to/validated-skill/ --target "${OPENCODE_SKILLS_DIR}"
```

Actions:
- Creates skill directory
- Copies all files
- Preserves existing scripts/references
- Updates skill manifest
- Generates installation receipt

### Step 5: Post-Install Validation

Built into `install_skill.py`: after copying, the installed directory is
re-validated through the same delegation path. On failure with
`--rollback-on-failure`, the previous state is restored automatically.

## Batch Installation

### From Package Directory

```bash
python3 scripts/batch_install.py /path/to/skill-package/ --target "${OPENCODE_SKILLS_DIR}" --validate-all
```

Process:
1. Scan package for all .skill files and directories
2. Detect format for each
3. Extract if needed
4. Validate each against skill-creator
5. Install validated skills
6. Report successes and failures

### From Zip Archive

```bash
python3 scripts/batch_install.py /path/to/all-skills.zip --target "${OPENCODE_SKILLS_DIR}"
```

Handles:
- Multiple .skill files in single archive
- Nested skill directories
- Mixed formats within archive

## Validation Integration

All installations automatically validate against skill-creator:

### Validation Pipeline

```
Input → Format Detection → Extraction → Validation → Installation → Post-Check
                              ↓              ↓
                         skill-creator  skill-creator
                          validate.py    validate.py
```

The installer ships no validation rules of its own — `scripts/validate_install.py` locates skill-creator (env override → sibling directory → configured skills dir) and delegates every verdict to its `validate.py`. See [references/creator-delegation.md](references/creator-delegation.md).

### Validation Rules

The full rule set lives in skill-creator's validator; see
[references/validation-rules.md](references/validation-rules.md) for the
operator summary (5-root-item structure, tag minimums, extension
allowlists, placeholder/secret/path scans, nested-SKILL.md rejection).
There is no scoring or leniency system — the verdict is `fails == 0` at
the requested tier, and warnings never block.

### Validation Output

```json
{
  "operation": "validate_install",
  "success": true,
  "delegated_to": "<validator path>",
  "tier": "basic",
  "valid": true,
  "status": "pass",
  "fails": 0,
  "warnings": 0,
  "checks": []
}
```

## Rollback Support

If installation fails validation:

```bash
# Automatic rollback (default behavior)
python3 scripts/install_skill.py /path/to/skill.skill --target "${OPENCODE_SKILLS_DIR}" --rollback-on-failure
```

For manual recovery, consult the receipt in `.receipts/` and see
[references/rollback-procedures.md](references/rollback-procedures.md).

## Installation Receipts

Every installation generates a receipt:

```json
{
  "receipt_id": "uuid",
  "skill_name": "skill-name",
  "version": "1.0.0",
  "installed_at": "2026-06-09T15:53:00Z",
  "source": "/path/to/skill.skill",
  "format": "skill-zip",
  "validation_score": 0.95,
  "files_installed": [
    "SKILL.md",
    "scripts/main.py",
    "references/overview.md"
  ],
  "rollback_path": "/path/to/backup/"
}
```

## Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/install_skill.py` | Main installer (detect → extract → validate → install → post-check → rollback) | `source --target dir [--validate]` |
| `scripts/extract_skill.py` | Extract .skill archives | `archive --output dir` |
| `scripts/validate_install.py` | Pre-install validation (locates skill-creator or uses bundled copy) | `skill-dir [--enterprise] [--json]` |
| `scripts/validate.py` | Bundled byte-identical copy of skill-creator's validator — standalone fallback | `skill-dir [--basic] [--json]` |
| `scripts/skill_root.py` | Bundled skill-root discovery (dependency of the validator) | `--root/--scan/--nested path` |
| `scripts/batch_install.py` | Batch installation | `package-dir --target dir` |

## Error Handling

| Error | Response |
|-------|----------|
| Invalid .skill archive | Report format error, skip |
| Missing SKILL.md | Reject skill, log error |
| Validation failed | Rollback, report issues |
| Already exists | Prompt for overwrite confirmation |
| Permission denied | Report, suggest sudo |
| Disk full | Clean temp files, retry |
| Network error (remote) | Retry with exponential backoff |

## Enterprise Validation Pillars

| Pillar | Weight | Description |
|--------|--------|-------------|
| Frontmatter | 20% | Valid YAML, required keys, naming |
| Structure | 15% | Directory layout, file organization |
| Content | 20% | Accuracy, completeness, no placeholders |
| Agnostic | 15% | No hardcoded paths, cross-platform |
| Redundancy | 10% | No overlap with existing skills |
| Sources | 10% | Documented, verified, current |
| Scripts | 5% | Working, tested, documented |
| Accessibility | 5% | Clear triggers, good descriptions |

## Key References

- **Skill anatomy**: [references/skill-anatomy.md](references/skill-anatomy.md)
- **Format detection**: [references/format-detection.md](references/format-detection.md)
- **Validation rules**: [references/validation-rules.md](references/validation-rules.md)
- **Rollback procedures**: [references/rollback-procedures.md](references/rollback-procedures.md)
