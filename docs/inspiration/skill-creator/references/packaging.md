# Skill Packaging Reference

## Table of Contents

- [Overview](#overview)
- [.skill File Format](#skill-file-format)
- [Packaging Process](#packaging-process)
- [Package Skills Script](#package-skills-script)
- [Integration with Upgrade](#integration-with-upgrade)
- [Verification](#verification)
- [Distribution](#distribution)

## Overview

Skills are distributed as **`.skill` files** - ZIP archives containing the complete skill directory structure. This enables versioned, portable, and verifiable skill distribution.

## .skill File Format

```
skill-name.skill (ZIP archive)
├── skill-name/
│   ├── SKILL.md              (required)
│   ├── scripts/              (optional)
│   │   ├── script1.py
│   │   └── script2.sh
│   ├── references/           (optional)
│   │   ├── deep-dive.md
│   │   └── api-reference.md
│   └── assets/               (optional)
│       ├── template.tmpl
│       └── logo.png
```

### Archive Structure Rules

1. **Root folder named after skill** - `skill-name/`
2. **SKILL.md at root** - `skill-name/SKILL.md`
3. **Relative paths preserved** - All files maintain relative structure
4. **Compression** - ZIP DEFLATE, level 6
5. **Excluded** - `.git/`, `__pycache__/`, `node_modules/`, `.venv/`, `*.pyc`, `*.log`, hidden files

## Packaging Process

### Automatic (via Upgrade)

```bash
# Upgrade + package in one command
python3 scripts/upgrade_to_enterprise.py \
  --target /path/to/skills \
  --package \
  --output-dir /path/to/skills
```

### Manual Packaging

```bash
# Package all skills
python3 scripts/package_skills.py \
  --skills-root /path/to/skills \
  --output-dir /path/to/output \
  --overwrite \
  --json

# Package specific skills
python3 scripts/package_skills.py \
  --skills-root /path/to/skills \
  --skills skill-a skill-b skill-c \
  --output-dir /path/to/output \
  --overwrite

# Package single skill
python3 scripts/package_skills.py \
  --skills-root /path/to/skills \
  --skill my-skill \
  --output-dir /path/to/output
```

## Package Skills Script

### Options

| Option | Description |
|--------|-------------|
| `--skills-root` | Root directory containing skill directories (required) |
| `--output-dir` | Output directory for .skill files (default: skills-root) |
| `--skill` | Package single skill by name |
| `--skills` | Package multiple skills by name (space-separated) |
| `--overwrite` | Overwrite existing .skill files (default) |
| `--no-overwrite` | Skip existing .skill files |
| `--json` | Output JSON for automation |

### JSON Output Format

```json
{
  "operation": "package_skills",
  "timestamp": "2026-06-09T21:49:00",
  "status": "success",
  "details": {
    "skills_root": "/path/to/skills",
    "output_dir": "/path/to/output",
    "packaged": [
      {
        "skill": "skill-name",
        "status": "success",
        "output": "/path/to/skill-name.skill",
        "files": 15,
        "size_bytes": 135282,
        "size_kb": 132.1
      }
    ],
    "skipped": [],
    "failed": [],
    "total_files": 1821,
    "total_size_bytes": 15364950
  }
}
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All skills packaged successfully |
| 1 | One or more skills failed |

## Integration with Upgrade

The `upgrade_to_enterprise.py` script now supports automatic packaging:

```bash
# Upgrade all skills AND package them
python3 scripts/upgrade_to_enterprise.py \
  --target /path/to/skills \
  --package \
  --output-dir /path/to/skills \
  --json
```

### Upgrade + Package Flow

1. **Scan** target directory for skill directories
2. **Upgrade** each skill (add directories, sections, fix issues)
3. **Validate** upgraded skills
4. **Package** each skill to .skill file (if `--package` flag)
5. **Report** results with packaging summary

## Verification

### Verify .skill File

```bash
# Extract and validate
mkdir -p /work/verify && cd /work/verify
unzip -o /path/to/skill-name.skill
python3 /path/to/validate_all.py --target /work/verify --json
```

### Verify Package Contents

```bash
# List contents
unzip -l /path/to/skill-name.skill

# Check structure
unzip -l /path/to/skill-name.skill | grep -E "SKILL\.md|scripts/|references/"
```

### Automated Verification

```bash
#!/bin/bash
# verify_all_packages.sh
for skill in /path/to/skills/*.skill; do
    name=$(basename "$skill" .skill)
    echo "Verifying $name..."
    mkdir -p /work/verify/$name
    unzip -q -o "$skill" -d /work/verify/$name
    python3 /path/to/validate_all.py --target /work/verify/$name --json | \
      python3 -c "import sys, json; d=json.load(sys.stdin); sys.exit(0 if d['skills'][0]['valid'] else 1)" || exit 1
done
echo "All packages verified"
```

## Distribution

### Skill Registry Format

```json
{
  "skill-name": {
    "version": "1.0.0",
    "description": "From SKILL.md frontmatter",
    "url": "https://registry.example.com/skill-name.skill",
    "sha256": "abc123...",
    "size_bytes": 135282,
    "skill_name": "skill-name",
    "uploaded": "2026-06-09T21:49:00Z",
    "dependencies": [],
    "tags": ["enterprise", "organization"]
  }
}
```

### Publishing Checklist

- [ ] Skill validates (`validate_all.py` passes)
- [ ] No hardcoded paths (`fix_hardcoded.py` clean)
- [ ] No placeholders (`placeholder_scanner.py` clean)
- [ ] Package creates successfully
- [ ] Package extracts and validates
- [ ] SHA256 recorded
- [ ] Version incremented in frontmatter

### Installation from .skill

```bash
# Install skill from .skill file
mkdir -p ~/skills
cd ~/skills
unzip -o /path/to/skill-name.skill
# Skill ready at ~/skills/skill-name/
```

## Quick Reference

```bash
# Full workflow: upgrade + package + verify
python3 scripts/upgrade_to_enterprise.py --target /skills --package --json
python3 scripts/package_skills.py --skills-root /skills --json

# Package specific skills
python3 scripts/package_skills.py --skills-root /skills --skills a b c --json

# Verify package
unzip -l skill.skill | head -20
```