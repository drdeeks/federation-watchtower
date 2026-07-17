# Zero-Placeholder Policy

## Table of Contents

- [Overview](#overview)
- [Prohibited Patterns](#prohibited-patterns)
- [Allowed Patterns](#allowed-patterns)
- [Detection](#detection)
- [Enforcement](#enforcement)
- [Remediation](#remediation)

## Overview

**Zero-Placeholder Policy**: No TODO, FIXME, TBD, WIP, STUB, or placeholder code in production. Every line must be real, wholesome, valid code with purpose.

This policy is enforced automatically by `placeholder_scanner.py` on every operation.

## Prohibited Patterns

### Code Markers

| Pattern | Example | Severity |
|---------|---------|----------|
| `TODO` | `# TODO: implement this` | **Critical** |
| `FIXME` | `# FIXME: broken logic` | **Critical** |
| `TBD` | `# TBD: decide later` | **Critical** |
| `WIP` | `# WIP: not done` | **Critical** |
| `STUB` | `def func(): STUB` | **Critical** |
| `XXX` | `# XXX: hack` | **Critical** |
| `HACK` | `# HACK: temporary` | **Critical** |

### Implementation Placeholders

| Pattern | Example | Severity |
|---------|---------|----------|
| `pass  # TODO` | `def func(): pass  # TODO` | **Critical** |
| `raise NotImplementedError` | `raise NotImplementedError()` | **Critical** |
| `return None  # TODO` | `return None  # temporary` | **Critical** |
| `return {}` | `return {}  # placeholder` | **Critical** |
| `...` | `def func(): ...` | **Critical** |
| `...` (Ellipsis) | `if condition: ...` | **Critical** |

### Template Variables

| Pattern | Example | Severity |
|---------|---------|----------|
| `{{variable}}` | `{{YOUR_API_KEY}}` | **Critical** |
| `[[YOUR_` | `[[YOUR_TOKEN]]` | **Critical** |
| `your_*` | `your_api_key = ""` | **Critical** |
| `INSERT_` | `INSERT_CODE_HERE` | **Critical** |
| `REPLACE_` | `REPLACE_THIS` | **Critical** |

### Filler Content

| Pattern | Example | Severity |
|---------|---------|----------|
| `lorem ipsum` | `lorem ipsum dolor sit amet` | **Critical** |
| `placeholder` | `placeholder_value = "test"` | **Critical** |
| `coming soon` | `# Coming soon` | **Critical** |
| `TODO list` | `# todo list` (legitimate) | **Allowed** |

## Allowed Patterns

These are **legitimate uses** that are NOT flagged:

### Variable/Function Names

```python
todo_list = []           # Variable name
todo_item = "task"       # Variable name  
def get_todo_items():    # Function name
    pass
```

### String Literals (Not Comments)

```python
status = "todo"          # Status value
tag = "TODO"             # Tag constant
message = "TODO: review" # User message
```

### Documentation References

```markdown
See [TODO.md](TODO.md)   # File reference
Tag: todo                # Tag in table
```

### Test/Example Code

```python
# In test files only
def test_todo_creation():
    todo = create_todo("test")
```

### Explicit Allow Comments

```python
# ALLOW: todo_list variable
todo_list = []
```

## Detection

### Scanner Tool

```bash
# Scan workspace
python3 scripts/placeholder_scanner.py --workspace /path

# Fail on any finding (CI/CD)
python3 scripts/placeholder_scanner.py --workspace /path --fail-on-found
```

### Output Format

```json
{
  "operation": "scan_placeholders",
  "status": "failed",
  "details": {
    "files_scanned": 42,
    "total_findings": 5,
    "by_type": {
      "TODO marker": 2,
      "FIXME marker": 1,
      "STUB implementation": 1,
      "NotImplementedError raised": 1
    },
    "findings": [
      {
        "file": "scripts/processor.py",
        "line": 42,
        "type": "TODO marker",
        "pattern": "TODO",
        "content": "# TODO: add retry logic"
      }
    ]
  }
}
```

### Scan Coverage

- **Included**: All `.py`, `.sh`, `.md`, `.yaml`, `.yml`, `.json`, `.toml`, `.txt`
- **Excluded**: `.git/`, `node_modules/`, `__pycache__/`, `.venv/`, `backups/`, `logs/`, `data/`, `tmp/`, `.secrets/`
- **Binary files**: Skipped (by extension and size >500KB)
- **Large files**: Skipped (>500KB)

## Enforcement

### Blocking Policy

| Context | Enforcement |
|---------|-------------|
| Pre-commit | Block commit if placeholders found |
| Pre-push | Block push if placeholders found |
| CI/CD | Fail build if placeholders found |
| Release | Block release if placeholders found |
| Audit | Report all placeholders |

### Integration

```bash
# Pre-commit hook
#!/bin/bash
python3 scripts/placeholder_scanner.py --workspace . --fail-on-found --json
```

```yaml
# GitHub Actions
- name: Zero-Placeholder Check
  run: python3 scripts/placeholder_scanner.py --workspace . --fail-on-found
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | No placeholders found (success) |
| 1 | Placeholders found with `--fail-on-found` |
| 2 | Scanner error |

## Remediation

### For Each Prohibited Pattern

| Pattern | Remediation |
|---------|-------------|
| `TODO` | Implement the feature now, or create a tracked task in TODO.md |
| `FIXME` | Fix the issue immediately |
| `TBD` | Make the decision now, document in CHANGELOG |
| `WIP` | Complete the work or revert |
| `STUB` | Replace with real implementation |
| `NotImplementedError` | Implement the method |
| `pass  # TODO` | Write the actual code |
| `return None  # temp` | Return proper value |
| `{{VAR}}` | Replace with actual value from config/secrets |
| `your_key = ""` | Load from `.secrets/` or environment |

### Remediation Workflow

```bash
# 1. Find all placeholders
python3 scripts/placeholder_scanner.py --workspace . --json > logs/placeholders.json

# 2. Review each finding
cat logs/placeholders.json | jq '.details.findings[] | "\(.file):\(.line) \(.type) - \(.content)"'

# 3. Fix each one
# Edit files to replace placeholders with real code

# 4. Verify clean
python3 scripts/placeholder_scanner.py --workspace . --fail-on-found

# 5. Add CHANGELOG entry
python3 scripts/changelog_manager.py --add --phase "placeholder-remediation" \
  --author "agent" --reason "Removed all placeholders" \
  --method "placeholder_scanner.py --fix" \
  --validation "placeholder-scan.json: valid=true"
```

### Exception Process (Rare)

If a placeholder is genuinely needed (e.g., interface definition):

1. **Document rationale** in CHANGELOG
2. **Add explicit allow comment**: `# ALLOW: interface stub for type checking`
3. **Create tracked task** in TODO.md with deadline
4. **Review weekly** - no exceptions persist >7 days

```python
# ALLOW: Abstract base class stub for type checking
class BaseProcessor:
    def process(self, data):  # pragma: no cover
        raise NotImplementedError("Subclasses must implement")
```

## Quick Reference

```bash
# Scan (no fail)
python3 scripts/placeholder_scanner.py --workspace .

# Scan (fail on found) - for CI
python3 scripts/placeholder_scanner.py --workspace . --fail-on-found

# JSON output for parsing
python3 scripts/placeholder_scanner.py --workspace . --json
```

**Zero tolerance. No placeholders in production. Ever.**