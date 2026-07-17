# Skill Installer with Embedded Validation Reference

## Skill Format Detection

### Supported Formats
| Format | Extension | Detection |
|--------|-----------|-----------|
| YAML | `.skill`, `.yaml`, `.yml` | YAML with `name:` + `metadata:` |
| JSON | `.skill.json` | JSON with `name` + `metadata` |
| Directory | `SKILL.md` in dir | Directory with `SKILL.md` + `scripts/` |

### Detection Logic
```python
def detect_skill_format(path):
    if path.endswith('.skill') or path.endswith('.yaml') or path.endswith('.yml'):
        # Parse YAML, check for 'name' and 'metadata' keys
        return 'yaml'
    elif path.endswith('.skill.json'):
        # Parse JSON, check for 'name' and 'metadata'
        return 'json'
    elif os.path.isdir(path) and os.path.exists(os.path.join(path, 'SKILL.md')):
        return 'directory'
    return None
```

## Installation Pipeline

### 1. Format Detection
```python
format = detect_skill_format(source_path)
if not format:
    raise ValueError(f"Unknown skill format: {source_path}")
```

### 2. Validation
```python
def validate_skill(skill_data):
    required = ['name', 'metadata']
    for field in required:
        if field not in skill_data:
            raise ValidationError(f"Missing required field: {field}")
    
    # Validate metadata structure
    meta = skill_data['metadata']
    if 'category' not in meta:
        warnings.warn("Missing category in metadata")
```

### 3. Conflict Resolution
```python
def resolve_conflict(target_path, skill_name):
    if os.path.exists(target_path):
        # Check version
        existing = load_skill(target_path)
        if existing['version'] == new_version:
            return 'skip'  # Same version
        elif existing['version'] < new_version:
            return 'upgrade'  # Backup old, install new
        else:
            return 'downgrade'  # Warn, require --force
```

### 4. Atomic Installation
```python
def install_skill(source, destination):
    # 1. Stage in temp directory
    # 2. Validate all files
    # 3. Atomic move (rename) to destination
    # 4. Update registry
    # 5. Create receipt
```

## Embedded Validation Rules

### Required Fields
```yaml
# SKILL.md (YAML frontmatter)
name: skill-name
description: "Description"
license: MIT
metadata:
  category: infrastructure
  complexity: enterprise
  tags:
    - tag1
    - tag2
```

### Validation Checks
```python
validation_rules = [
    ("name", "must be lowercase with hyphens", r'^[a-z0-9-]+$'),
    ("version", "semver format", r'^\d+\.\d+\.\d+$'),
    ("license", "valid SPDX", spdx_license_list),
    ("metadata.category", "required", lambda x: bool(x)),
    ("metadata.complexity", "valid enum", ["simple", "intermediate", "enterprise"]),
]
```

## Installation Receipts

### receipt.json
```json
{
  "skill_name": "enterprise-organization",
  "version": "1.0.0",
  "installed_at": "2026-06-13T12:34:56Z",
  "source": "https://github.com/drdeeks/skills",
  "checksum": "sha256:abc123...",
  "files": ["SKILL.md", "scripts/validate.py", "scripts/enterprise-org.py"],
  "validation": {
    "format_detected": "yaml",
    "checks_passed": 12,
    "warnings": 0
  }
}
```

## Registry Update

```python
def update_registry(skill_name, receipt):
    registry_path = os.path.join(SKILLS_DIR, '.registry.json')
    registry = load_json(registry_path) or {}
    registry[skill_name] = {
        'version': receipt['version'],
        'installed_at': receipt['installed_at'],
        'path': skill_path,
        'checksum': receipt['checksum']
    }
    save_json(registry_path, registry)
```

## Uninstall with Rollback

```python
def uninstall_skill(skill_name, backup=True):
    # 1. Read receipt
    receipt = load_receipt(skill_name)
    
    # 2. Backup if requested
    if backup:
        backup_path = f"/tmp/skill-backup-{skill_name}-{timestamp}"
        shutil.move(skill_path, backup_path)
    
    # 3. Remove from registry
    update_registry(skill_name, None)
    
    # 4. Return backup path for manual restore
    return backup_path if backup else None
```

## Installation Logs

```bash
# Installation log format
[2026-06-13 12:34:56] INFO: Installing enterprise-organization v1.0.0
[2026-06-13 12:34:56] INFO: Format detected: yaml
[2026-06-13 12:34:57] INFO: Validation passed (12 checks)
[2026-06-13 12:34:57] INFO: Installing to /skills/enterprise-organization
[2026-06-13 12:34:58] INFO: Registry updated
[2026-06-13 12:34:58] INFO: Installation complete
```

## Verification Commands

```bash
# Verify installed skill
skill-installer verify enterprise-organization
# ✅ enterprise-organization v1.0.0 - valid

# List all skills
skill-installer list
# enterprise-organization  v1.0.0  /skills/enterprise-organization
# skill-installer        v1.2.3  /skills/skill-installer

# Check for updates
skill-installer check-updates
# enterprise-organization: 1.0.0 → 1.1.0 available

# Uninstall with backup
skill-installer uninstall enterprise-organization --backup
# Backup saved to /tmp/skill-backup-enterprise-organization-1700000000
```

## Continuous Validation

```bash
# Add to cron for daily validation
0 3 * * * /usr/local/bin/skill-validator --all --report /var/log/skill-validation.log
```