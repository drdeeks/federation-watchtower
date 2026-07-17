# Rollback Procedures Reference

## Table of Contents

- [Rollback Overview](#rollback-overview)
- [Automatic Rollback](#automatic-rollback)
- [Manual Rollback](#manual-rollback)
- [Receipt Management](#receipt-management)
- [Recovery Scenarios](#recovery-scenarios)

## Rollback Overview

Rollback support ensures failed installations can be reverted cleanly.

### When Rollback Occurs

| Scenario | Rollback Trigger |
|----------|------------------|
| Validation failure | Post-install validation fails |
| File copy error | Disk full, permissions |
| Corruption detected | Checksum mismatch |
| User cancellation | Ctrl+C during install |

### Rollback Types

| Type | Description | When to Use |
|------|-------------|-------------|
| **Automatic** | System-triggered rollback | Validation failure |
| **Manual** | User-triggered rollback | Post-install issues |
| **Partial** | Rollback specific files | Selective revert |

## Automatic Rollback

### Process

```
Installation Start
      ↓
  Backup existing (if exists)
      ↓
  Copy new files
      ↓
  Post-install validation
      ↓
  [FAIL] → Rollback to backup
      ↓
  [PASS] → Complete installation
```

### Implementation

```python
def install_with_rollback(skill_dir, target_dir):
    # Step 1: Create backup if exists
    backup_path = None
    if target_dir.exists():
        backup_path = create_backup(target_dir)
    
    try:
        # Step 2: Install new files
        install_files(skill_dir, target_dir)
        
        # Step 3: Validate
        if not validate_installation(target_dir):
            raise ValidationError("Post-install validation failed")
        
        return {"success": True}
    
    except Exception as e:
        # Step 4: Rollback on failure
        if backup_path:
            rollback_installation(target_dir, backup_path)
        
        return {"success": False, "error": str(e)}
```

### Backup Creation

```python
def create_backup(target_dir):
    backup_dir = Path(tempfile.mkdtemp(prefix="skill_backup_"))
    backup_path = backup_dir / target_dir.name
    shutil.copytree(target_dir, backup_path)
    return backup_path
```

### Rollback Execution

```python
def rollback_installation(target_dir, backup_path):
    # Remove failed installation
    if target_dir.exists():
        shutil.rmtree(target_dir)
    
    # Restore from backup
    if backup_path.exists():
        shutil.move(backup_path, target_dir)
```

## Manual Rollback

### Using Receipts

Every installation generates a receipt:

```json
{
  "receipt_id": "uuid",
  "skill_name": "skill-name",
  "installed_at": "2026-06-09T15:53:00Z",
  "source": "/path/to/skill.skill",
  "validation_score": 0.95,
  "files_installed": ["SKILL.md", "scripts/main.py"],
  "rollback_path": "${SKILL_TEMP_DIR:-/tmp}/skill_backup_xxx/skill-name"
}
```

### Rollback Command

```bash
python3 scripts/rollback_install.py "${OPENCODE_SKILLS_DIR}/skill-name/" \
  --receipt /path/to/receipt.json
```

### Rollback Process

1. Read receipt file
2. Locate backup path
3. Remove current installation
4. Restore from backup
5. Verify restoration
6. Clean up backup

## Receipt Management

### Receipt Storage

Receipts stored in:
```
${OPENCODE_SKILLS_DIR}/.receipts/
├── skill-name_abc12345.json
├── skill-name_def67890.json
└── ...
```

### Receipt Lifecycle

| Stage | Action |
|-------|--------|
| **Installation** | Generate receipt |
| **Validation** | Update receipt with score |
| **Rollback** | Reference receipt for restore |
| **Cleanup** | Remove old receipts (30 days) |

### Receipt Cleanup

```python
def cleanup_old_receipts(days=30):
    cutoff = datetime.utcnow() - timedelta(days=days)
    for receipt_file in RECEIPTS_DIR.glob("*.json"):
        receipt = json.loads(receipt_file.read_text())
        installed_at = datetime.fromisoformat(receipt["installed_at"])
        if installed_at < cutoff:
            receipt_file.unlink()
```

## Recovery Scenarios

### Scenario 1: Validation Failure

**Problem**: Skill installed but failed post-install validation.

**Solution**:
```bash
# Automatic rollback handles this
# Or manual rollback:
python3 scripts/rollback_install.py "${OPENCODE_SKILLS_DIR}/skill-name/"
```

### Scenario 2: Disk Full

**Problem**: Installation failed due to insufficient disk space.

**Solution**:
1. Free up disk space
2. Clean temp files: `rm -rf "${SKILL_TEMP_DIR}/skill_"*`
3. Retry installation

### Scenario 3: Permission Denied

**Problem**: Installation failed due to file permissions.

**Solution**:
1. Check ownership: `ls -la "${OPENCODE_SKILLS_DIR}/"`
2. Fix permissions: `chmod -R 755 "${OPENCODE_SKILLS_DIR}/"`
3. Retry installation

### Scenario 4: Network Error (Remote)

**Problem**: Remote package download failed.

**Solution**:
1. Check network connection
2. Retry with exponential backoff
3. Download manually and install locally

### Scenario 5: Corruption Detected

**Problem**: Installed files corrupted (checksum mismatch).

**Solution**:
1. Rollback to backup
2. Re-install from original source
3. Verify checksums

## Best Practices

### Before Installation

1. **Backup existing**: Always backup before overwriting
2. **Verify source**: Check source integrity
3. **Check disk space**: Ensure sufficient space

### During Installation

1. **Validate early**: Check format before extraction
2. **Validate after**: Post-install validation
3. **Handle errors**: Graceful error handling

### After Installation

1. **Verify installation**: Check all files present
2. **Test functionality**: Ensure skill works
3. **Keep receipt**: Store receipt for future rollback

## Error Handling

| Error | Response |
|-------|----------|
| Backup creation failed | Continue without backup (warn user) |
| Rollback failed | Report error, suggest manual restore |
| Receipt missing | Attempt manual rollback |
| Backup corrupted | Report error, suggest re-install |

## References

- **Installation Guide**: [installation-guide.md](installation-guide.md)
- **Validation Rules**: [validation-rules.md](validation-rules.md)
- **Skill Anatomy**: [skill-anatomy.md](skill-anatomy.md)
