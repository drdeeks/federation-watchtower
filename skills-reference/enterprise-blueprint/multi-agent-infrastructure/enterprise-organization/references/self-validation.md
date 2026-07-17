# Self-Validation Framework

## Table of Contents

- [Overview](#overview)
- [Four Pillars](#four-pillars)
- [Validation Process](#validation-process)
- [Modular Design Checks](#modular-design-checks)
- [Rollback Verification](#rollback-verification)
- [Performance Baselines](#performance-baselines)
- [Cross-Reference Validation](#cross-reference-validation)

## Overview

The Self-Validation Framework provides **rigorous, automated verification** that the workspace meets enterprise standards before any deployment. It runs on every `enforce`, `audit`, and can be triggered independently.

## Four Pillars

### 1. Modular Design
- Separation of concerns (scripts, config, data, secrets)
- No monolithic files
- Clear interfaces between components
- Reusable, testable modules

### 2. Rollback Capability
- Git repository as primary rollback mechanism
- Backups directory for snapshots
- CHANGELOG for audit trail
- Tested rollback procedure

### 3. Performance
- No large files in repo (>10MB)
- Total repo size <500MB
- Efficient scripts (stdlib only)
- No unnecessary dependencies

### 4. Cross-References
- README ↔ CHANGELOG ↔ TODO ↔ .gitignore
- All required files present
- Links resolve correctly
- Documentation consistent

## Validation Process

```bash
# Full self-validation
python3 scripts/self_validator.py --workspace /path --json

# With rollback test (creates temp commit)
python3 scripts/self_validator.py --workspace /path --verify-rollback --json
```

### Output Format

```json
{
  "operation": "self_validation",
  "status": "failed",
  "details": {
    "modular_design": {"valid": true, "issues": []},
    "rollback_capability": {"valid": false, "issues": ["Missing backups/ directory"]},
    "performance": {"valid": true, "issues": []},
    "cross_references": {"valid": true, "issues": []},
    "rollback_test": {"skipped": true},
    "total_issues": 1,
    "valid": false
  }
}
```

## Modular Design Checks

### Required Directories

| Directory | Purpose | Required |
|-----------|---------|----------|
| `scripts/` | Executable management scripts | ✅ |
| `references/` | Deep documentation | ✅ |
| `config/` | Configuration files | ✅ |
| `data/` | Persistent data | ✅ |
| `.secrets/` | Credentials (700 perms) | ✅ |

### Structural Rules

| Rule | Check | Failure = |
|------|-------|-----------|
| Multiple scripts | `scripts/` has >1 .py/.sh file | Monolithic design |
| References exist | `references/` directory exists | Missing deep docs |
| Config separated | `config/` directory exists | Config in root |
| Data separated | `data/` directory exists | Data in code |
| Secrets isolated | `.secrets/` exists, 700 perms | Secrets exposed |

### Code Organization

```
Good (Modular):
scripts/
├── init.py
├── validate.py
├── enforce.py
├── backup.py
└── utils/
    ├── __init__.py
    ├── git.py
    └── fs.py

Bad (Monolithic):
scripts/
└── enterprise-org.py  # 2000+ lines, does everything
```

## Rollback Verification

### Prerequisites

| Prerequisite | Check | Required |
|--------------|-------|----------|
| Git repository | `.git/` exists | ✅ |
| Clean working tree | `git status --porcelain` empty | ✅ |
| Backups directory | `backups/` exists | ✅ |
| CHANGELOG.md | `CHANGELOG.md` exists | ✅ |
| TODO.md | `TODO.md` exists | ✅ |

### Rollback Test (Optional, `--verify-rollback`)

```bash
# Test actual rollback capability
python3 scripts/self_validator.py --workspace . --verify-rollback
```

**Test Procedure:**
1. Record current commit (HEAD)
2. Create test file `.rollback_test`
3. `git add .rollback_test && git commit -m "rollback test"`
4. `git reset --hard HEAD~1`
5. Verify `.rollback_test` is gone
6. Restore to original commit

**Pass Criteria:**
- Test file created and committed
- Reset removes test file
- Original state restored
- No errors during process

### Rollback Failure Modes

| Failure | Cause | Resolution |
|---------|-------|------------|
| Not a git repo | `.git/` missing | `git init` |
| Dirty working tree | Uncommitted changes | Commit or stash |
| Test file persists | `git reset` failed | Check git config |
| Cannot restore | Original commit lost | Reflog recovery |

## Performance Baselines

### Repository Size Limits

| Metric | Warning | Critical | Check |
|--------|---------|----------|-------|
| Single file | >10MB | >50MB | `find . -size +10M` |
| Total repo | >200MB | >500MB | `du -sh .` |
| .git folder | >100MB | >500MB | `du -sh .git` |

### File Count Limits

| Type | Warning | Critical |
|------|---------|----------|
| Total files | >1000 | >5000 |
| Python files | >100 | >500 |
| Config files | >50 | >200 |

### Script Performance

```bash
# Time validation scripts
time python3 scripts/validate_structure.py --workspace .
time python3 scripts/security_hardening.py --workspace . --check-only
time python3 scripts/placeholder_scanner.py --workspace .

# Expected: <5 seconds each on typical workspace
```

### Dependencies

- **Stdlib only** - All scripts use Python standard library
- **No pip install** - Zero external dependencies
- **No compilation** - Pure Python, no C extensions
- **Cross-platform** - Linux, macOS, Windows (WSL)

## Cross-Reference Validation

### Required Files Matrix

| File | References | Referenced By |
|------|------------|---------------|
| `README.md` | CHANGELOG, TODO, .gitignore | All |
| `CHANGELOG.md` | README, phases | README, agents |
| `TODO.md` | phases, validation | README, CHANGELOG |
| `.gitignore` | .secrets, logs, tmp | README, security |

### Link Validation

```bash
# Check internal links in README
grep -oE '\[.+\]\([^)]+\)' README.md | while read link; do
  url=$(echo "$link" | sed -E 's/.*\(([^)]+)\).*/\1/')
  if [[ ! "$url" =~ ^https?:// ]] && [[ ! "$url" =~ ^# ]]; then
    if [[ ! -e "$url" ]]; then
      echo "BROKEN: $link"
    fi
  fi
done
```

### Consistency Checks

| Check | Description |
|-------|-------------|
| Phase names match | TODO phases = CHANGELOG phases |
| Author names consistent | TODO assigned = CHANGELOG author |
| Timestamps ordered | CHANGELOG timestamps chronological |
| No orphan sections | All README sections have content |

## Automation

### Pre-Commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit
set -e
echo "Running self-validation..."
python3 scripts/self_validator.py --workspace . --json > /tmp/self-validation.json
python3 -c "import json, sys; d=json.load(open('/tmp/self-validation.json')); sys.exit(0 if d['details']['valid'] else 1)"
```

### CI/CD Integration

```yaml
# .github/workflows/validate.yml
jobs:
  self-validation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Self Validation
        run: |
          python3 scripts/self_validator.py --workspace . --verify-rollback --json
```

### Scheduled Validation

```bash
# Daily cron
0 2 * * * cd /workspace && python3 scripts/self_validator.py --workspace . --json >> logs/daily-validation.log 2>&1
```

## Compliance Evidence

All validations produce JSON for audit trail:

```bash
python3 scripts/self_validator.py --workspace . --json > logs/self-validation-$(date +%Y%m%d).json
python3 scripts/self_validator.py --workspace . --verify-rollback --json > logs/rollback-test-$(date +%Y%m%d).json
```

**Retention:** 90 days minimum, archived to backups/

## Quick Reference

```bash
# Quick check (no rollback test)
python3 scripts/self_validator.py --workspace .

# Full validation with rollback test
python3 scripts/self_validator.py --workspace . --verify-rollback

# JSON for automation
python3 scripts/self_validator.py --workspace . --verify-rollback --json
```

**Self-validation is not optional. Every deployment must pass.**