# Rollback Procedures

## Table of Contents

- [Overview](#overview)
- [Rollback Types](#rollback-types)
- [Pre-Rollback Checklist](#pre-rollback-checklist)
- [Git Rollback](#git-rollback)
- [Backup Rollback](#backup-rollback)
- [Full Workspace Restore](#full-workspace-restore)
- [Post-Rollback Validation](#post-rollback-validation)
- [Rollback Testing](#rollback-testing)
- [Incident Response](#incident-response)

## Overview

Rollback capability is **mandatory** for enterprise operations. Every phase must have a verified rollback path before deployment. This document defines the procedures, testing, and validation.

## Rollback Types

### 1. Git Rollback (Primary)
- **Scope**: Code, config, scripts, documentation
- **Speed**: Seconds
- **Granularity**: Commit-level
- **Use case**: Bad deploy, broken code, config error

### 2. Backup Rollback (Secondary)
- **Scope**: Data, databases, large files, state
- **Speed**: Minutes
- **Granularity**: Snapshot-level (hourly/daily)
- **Use case**: Data corruption, deleted files, git history insufficient

### 3. Full Workspace Restore (Emergency)
- **Scope**: Entire workspace
- **Speed**: Minutes to hours
- **Granularity**: Complete
- **Use case**: Catastrophic failure, compromised workspace

## Pre-Rollback Checklist

Before any deployment, verify:

```bash
# 1. Clean git state
git status --porcelain
# Should be empty

# 2. Current commit tagged
git tag -l "pre-deploy-*"
# Should have recent tag

# 3. Backups current
ls -la backups/
# Should have recent snapshots

# 4. CHANGELOG updated
grep -q "## \[Unreleased\]" CHANGELOG.md

# 5. Rollback tested (this phase)
python3 scripts/self_validator.py --workspace . --verify-rollback --json
# Must show valid=true
```

### Deployment Gate

**No deployment proceeds without:**
- [ ] Clean git working tree
- [ ] Pre-deploy tag created: `git tag pre-deploy-$(date +%Y%m%d-%H%M%S)`
- [ ] Backup snapshot created: `python3 scripts/enterprise-org.py backup`
- [ ] Rollback test passed: `python3 scripts/self_validator.py --verify-rollback`
- [ ] CHANGELOG entry for deployment phase

## Git Rollback

### Soft Reset (Keep Changes)

```bash
# Undo last commit, keep changes staged
git reset --soft HEAD~1

# Undo last N commits
git reset --soft HEAD~N

# Check what will be reset
git log --oneline -5
```

### Hard Reset (Discard Changes)

```bash
# WARNING: Discards all uncommitted changes!
git reset --hard HEAD~1

# Reset to specific commit
git reset --hard <commit-hash>

# Reset to tag
git reset --hard pre-deploy-20260115-103000
```

### Reflog Recovery (If Reset Goes Wrong)

```bash
# View reflog
git reflog

# Reset to previous state
git reset --hard HEAD@{1}

# Or specific reflog entry
git reset --hard <reflog-hash>
```

### Branch-Based Rollback (Recommended)

```bash
# Create deployment branch
git checkout -b deploy/$(date +%Y%m%d-%H%M%S)

# Deploy from branch
# If issues: delete branch, stay on main
git checkout main
git branch -D deploy/...

# If success: merge or fast-forward
git checkout main
git merge deploy/...
```

### Verify Rollback

```bash
# After rollback, verify:
# 1. Correct commit
git log --oneline -1

# 2. Files restored
ls -la

# 3. Tests pass
python3 scripts/validate_structure.py --workspace .
python3 scripts/security_hardening.py --workspace . --check-only
python3 scripts/placeholder_scanner.py --workspace . --fail-on-found

# 4. CHANGELOG entry for rollback
python3 scripts/changelog_manager.py --add \
  --phase "rollback" \
  --author "agent" \
  --reason "Rolled back to commit $(git rev-parse --short HEAD)" \
  --method "git reset --hard HEAD~1" \
  --validation "post-rollback validation passed"
```

## Backup Rollback

### Create Backup

```bash
# Automated backup (runs via cron + pre-deploy)
python3 scripts/enterprise-org.py backup --workspace .

# Manual backup
tar -czf backups/manual-$(date +%Y%m%d-%H%M%S).tar.gz \
  --exclude=.git \
  --exclude=backups \
  --exclude=logs \
  --exclude=tmp \
  --exclude=data/local \
  .
```

### Backup Structure

```
backups/
├── auto-20260115-100000.tar.gz    # Automated hourly
├── auto-20260115-140000.tar.gz
├── pre-deploy-20260115-103000.tar.gz  # Pre-deploy snapshot
├── daily-20260115.tar.gz          # Daily snapshot
└── weekly-20260115.tar.gz         # Weekly snapshot
```

### Restore from Backup

```bash
# List available backups
ls -la backups/

# Restore specific backup
RESTORE_DIR="${TMPDIR:-/tmp}/restore-$$"
mkdir -p "$RESTORE_DIR"
tar -xzf backups/pre-deploy-20260115-103000.tar.gz -C "$RESTORE_DIR"
rsync -av "$RESTORE_DIR"/ /workspace/ --delete
rm -rf "$RESTORE_DIR"

# Verify restore
python3 scripts/validate_structure.py --workspace .
python3 scripts/security_hardening.py --workspace . --check-only
```

### Backup Retention

| Frequency | Retention | Count |
|-----------|-----------|-------|
| Hourly | 48 hours | 48 |
| Daily | 30 days | 30 |
| Weekly | 12 weeks | 12 |
| Monthly | 12 months | 12 |
| Pre-deploy | 90 days | Unlimited |

## Full Workspace Restore

### When to Use

- Git history corrupted
- Workspace compromised (secrets exposed)
- Filesystem corruption
- Ransomware/malware

### Procedure

```bash
# 1. Isolate workspace
sudo chmod -R 700 /compromised/workspace

# 2. Get latest clean backup
LATEST=$(ls -t backups/pre-deploy-*.tar.gz | head -1)

# 3. Create fresh workspace
FRESH_DIR="${TMPDIR:-/tmp}/fresh-workspace-$$"
mkdir -p "$FRESH_DIR"
cd "$FRESH_DIR"

# 4. Restore
tar -xzf "$LATEST" -C .

# 5. Verify integrity
python3 scripts/validate_structure.py --workspace .
python3 scripts/security_hardening.py --workspace . --check-only
python3 scripts/placeholder_scanner.py --workspace . --fail-on-found
python3 scripts/self_validator.py --workspace . --verify-rollback

# 6. Rotate all secrets (CRITICAL)
# - Generate new SSH keys
# - Rotate API keys
# - Rotate wallet keys
# - Update .secrets/

# 7. Deploy fresh
rsync -av "$FRESH_DIR"/ /production/workspace/
```

## Post-Rollback Validation

### Mandatory Checks

```bash
# 1. Structure
python3 scripts/validate_structure.py --workspace . --json

# 2. Security
python3 scripts/security_hardening.py --workspace . --check-only --json

# 3. Placeholders
python3 scripts/placeholder_scanner.py --workspace . --fail-on-found --json

# 4. Todos
python3 scripts/todo_validator.py --workspace . --strict --json

# 5. Self-validation
python3 scripts/self_validator.py --workspace . --verify-rollback --json

# 6. All must pass
python3 -c "
import json, glob, sys
for f in glob.glob('logs/*-validation.json'):
    with open(f) as fp:
        d = json.load(fp)
        if not d.get('details', {}).get('valid', False):
            print(f'FAILED: {f}')
            sys.exit(1)
print('ALL PASSED')
"
```

### CHANGELOG Entry

```markdown
### rollback - 2026-01-15 14:30:00
**Author:** hermes-agent
**Reason:** Rolled back deployment v1.2.3 due to critical bug in trading strategy
**Method:** git reset --hard pre-deploy-20260115-103000
**Validation:** All 6 post-rollback validators passed (structure, security, placeholders, todos, self, rollback-test)
**Reasoning:** Used git tag for precise rollback point. Verified all validators pass post-rollback. Rotated all secrets as precaution. This rollback was tested in staging 2 hours prior with identical procedure.
```

## Rollback Testing

### Automated Test (Self-Validator)

```bash
# Tests actual rollback capability
python3 scripts/self_validator.py --workspace . --verify-rollback
```

**Test Procedure:**
1. Records current HEAD
2. Creates test file `.rollback_test`
3. Commits test file
4. Resets `HEAD~1`
5. Verifies test file removed
6. Restores original HEAD

**Pass = Rollback verified**

### Test in CI/CD

```yaml
# .github/workflows/rollback-test.yml
on:
  push:
    branches: [main]
  schedule:
    - cron: '0 3 * * *'  # Daily

jobs:
  rollback-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Need full history for reflog
      - name: Test Rollback
        run: |
          python3 scripts/self_validator.py --workspace . --verify-rollback --json
          python3 -c "import json, sys; d=json.load(open('/tmp/result.json')); sys.exit(0 if d['details']['valid'] else 1)"
```

### Manual Rollback Drill (Quarterly)

```bash
#!/bin/bash
# Quarterly rollback exercise
set -e

echo "=== ROLLBACK DRILL $(date) ==="

# 1. Tag current state
git tag drill-$(date +%Y%m%d-%H%M%S)

# 2. Create test change
echo "drill test" > .drill-test
git add .drill-test
git commit -m "drill: test change"

# 3. Time the rollback
START=$(date +%s)
git reset --hard HEAD~1
END=$(date +%s)
DURATION=$((END - START))

# 4. Verify
if [[ ! -f .drill-test ]]; then
    echo "✓ Rollback successful in ${DURATION}s"
else
    echo "✗ Rollback failed"
    exit 1
fi

# 5. Log drill
python3 scripts/changelog_manager.py --add \
  --phase "rollback-drill" \
  --author "system" \
  --reason "Quarterly rollback drill - ${DURATION}s" \
  --method "git reset --hard HEAD~1" \
  --validation "drill test file removed in ${DURATION}s"

echo "=== DRILL COMPLETE ==="
```

## Incident Response

### Rollback Decision Matrix

| Severity | Trigger | Action | Timeline |
|----------|---------|--------|----------|
| **Critical** | Production down, data loss, security breach | Immediate git rollback + backup restore | <5 min |
| **High** | Major bug, failed validation | Git rollback to pre-deploy tag | <15 min |
| **Medium** | Minor bug, performance regression | Git rollback or hotfix | <1 hour |
| **Low** | Cosmetic issue, documentation | Hotfix or next deploy | Next window |

### Incident Commander Checklist

```markdown
## Incident: [ID] - [Date]

- [ ] Alert team (pager/slack)
- [ ] Assess severity
- [ ] Execute rollback (git/backup/full)
- [ ] Verify post-rollback validation
- [ ] Rotate secrets if exposure suspected
- [ ] Document in CHANGELOG
- [ ] Root cause analysis (within 24h)
- [ ] Process improvement (within 1 week)
```

### Communication

```markdown
# Rollback Notification Template

**Incident:** [ID]
**Time:** [UTC timestamp]
**Severity:** [Critical/High/Medium/Low]
**Rollback Method:** [Git/Backup/Full]
**Rollback Point:** [commit/tag/backup-name]
**Validation:** [All validators passed/Failed: X]

**Impact:**
- Users affected: [count/description]
- Data affected: [description]
- Services down: [duration]

**Next Steps:**
1. Root cause analysis
2. Fix implementation
3. Re-deploy with fix
4. Process improvement
```

## Quick Reference

```bash
# Emergency git rollback (most common)
git reset --hard pre-deploy-20260115-103000

# With verification
git reset --hard pre-deploy-20260115-103000 && \
python3 scripts/validate_structure.py --workspace . && \
python3 scripts/security_hardening.py --workspace . --check-only && \
echo "Rollback verified"

# Backup restore
tar -xzf backups/pre-deploy-20260115-103000.tar.gz -C /tmp && \
rsync -av /tmp/ /workspace/ --delete

# Full drill
./scripts/rollback-drill.sh

# Test capability
python3 scripts/self_validator.py --workspace . --verify-rollback
```

**Rollback is not a failure. Failed rollback is. Test yours today.**