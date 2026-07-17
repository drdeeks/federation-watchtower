# CHANGELOG Protocol

## Table of Contents

- [Overview](#overview)
- [Format Specification](#format-specification)
- [Entry Structure](#entry-structure)
- [Rationale Requirements](#rationale-requirements)
- [Append-Only Enforcement](#append-only-enforcement)
- [Query & Audit](#query--audit)
- [Integrity Verification](#integrity-verification)

## Overview

The CHANGELOG.md is an **append-only, immutable ledger** of all changes to the workspace. Every entry must include: datetime, author, changes, method, validation, and reasoning. This provides complete auditability and decision traceability.

## Format Specification

Based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

### File Structure

```markdown
# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### phase-name - YYYY-MM-DD HH:MM:SS
**Author:** agent-name
**Reason:** Human-readable reason for the change
**Method:** Tool/script used (e.g., enterprise-org.py validate)
**Validation:** Validation artifact and result (e.g., structure-validation.json: valid=true)
**Reasoning:** Detailed explanation of why this approach was chosen, what alternatives were considered, how validation was performed, and why this method ensures accuracy

---

## [1.0.0] - YYYY-MM-DD

### Added
- Feature descriptions

### Changed
- Change descriptions

### Fixed
- Fix descriptions

### Security
- Security-related changes
```

### Version Format

| Version | When |
|---------|------|
| `[Unreleased]` | Current development |
| `[1.0.0]` | Major release |
| `[1.1.0]` | Minor release |
| `[1.1.1]` | Patch release |

## Entry Structure

### Required Fields (Every Entry)

```markdown
### phase-name - YYYY-MM-DD HH:MM:SS
**Author:** agent-name
**Reason:** Why this change was necessary
**Method:** enterprise-org.py validate --strict
**Validation:** structure-validation.json: valid=true, 0 issues
**Reasoning:** Chose strict validation because enterprise policy requires evidence for every completion. Used enterprise-org.py which orchestrates all sub-validators. Validated by checking JSON output 'valid=true' and zero issues. This ensures no structural deviation exists before deployment.
```

### Field Specifications

| Field | Format | Required | Description |
|-------|--------|----------|-------------|
| `phase-name` | kebab-case | ✅ | Logical grouping (setup, security, validation, ops) |
| `datetime` | YYYY-MM-DD HH:MM:SS | ✅ | UTC timezone preferred |
| `Author` | string | ✅ | Agent identifier (hermes, titan, avery, allman, system) |
| `Reason` | string | ✅ | Business/technical justification |
| `Method` | string | ✅ | Exact command/tool used |
| `Validation` | string | ✅ | Validation artifact + result |
| `Reasoning` | string | ✅ | Why this method, alternatives, validation details |

### Optional Fields

| Field | When to Include |
|-------|-----------------|
| `Rollback` | If rollback was tested |
| `Impact` | Scope of change (files, agents, systems) |
| `Dependencies` | New/updated dependencies |
| `Breaking` | Breaking changes marker |

## Rationale Requirements

### The "Reasoning" Field Must Answer:

1. **What alternatives were considered?**
   - "Considered manual validation but chose automated for consistency"

2. **Why was this method chosen?**
   - "enterprise-org.py orchestrates all sub-validators in correct order"

3. **How was validation performed?**
   - "Ran validate_structure.py --strict, checked JSON 'valid=true'"

4. **What makes this accurate in your assessment?**
   - "Zero issues across 5 validators, rollback tested, evidence artifacts produced"

### Reasoning Quality Levels

| Level | Example | Score |
|-------|---------|-------|
| **Minimal** | "Fixed structure" | ❌ Reject |
| **Basic** | "Ran validation, passed" | ⚠️ Marginal |
| **Standard** | "Used enterprise-org.py validate --strict. All 5 validators passed. Evidence in logs/." | ✅ Acceptable |
| **Detailed** | "Chose strict mode because policy requires evidence. Ran validate_structure.py (0 issues), security_hardening.py (0 issues), todo_validator.py (2 tasks validated), placeholder_scanner.py (clean), self_validator.py (rollback tested). All JSON outputs show valid=true. Artifacts in logs/. This ensures no deviation before deploy." | ✅ Enterprise |

## Append-Only Enforcement

### Rules

1. **Never edit existing entries** - Only append new ones
2. **Never delete entries** - Immutable history
3. **Never reorder entries** - Chronological integrity
4. **Never modify timestamps** - Original time preserved

### Enforcement Mechanisms

```bash
# Verify integrity
python3 scripts/changelog_manager.py --workspace . --action verify --json

# Check git history for CHANGELOG edits
git log --oneline -- CHANGELOG.md | head -20
```

### Git Integration

```bash
# Every changelog entry should have a corresponding commit
git add CHANGELOG.md
git commit -m "changelog: phase-name - reason"
```

### Integrity Checks

| Check | Tool | Frequency |
|-------|------|-----------|
| No deleted entries | `changelog_manager.py verify` | Every operation |
| Chronological order | `changelog_manager.py verify` | Every operation |
| Required fields present | `changelog_manager.py verify` | Every operation |
| Git history matches | `git log -- CHANGELOG.md` | Manual audit |

## Query & Audit

### List Entries

```bash
# All entries
python3 scripts/changelog_manager.py --workspace . --action list

# Filter by phase
python3 scripts/changelog_manager.py --workspace . --action list --phase-filter security

# Filter by author
python3 scripts/changelog_manager.py --workspace . --action list --author-filter titan

# Filter by date
python3 scripts/changelog_manager.py --workspace . --action list --since 2026-01-01

# Limit results
python3 scripts/changelog_manager.py --workspace . --action list --limit 10
```

### Audit Report

```json
{
  "workspace": "/path",
  "total_entries": 42,
  "filtered_entries": 5,
  "entries": [
    {
      "phase": "security",
      "timestamp": "2026-01-15 10:30:00",
      "author": "titan-agent",
      "reason": "Security hardening",
      "method": "security_hardening.py --fix",
      "validation": "security-audit.json: valid=true, 0 issues",
      "reasoning": "Enterprise policy requires zero security issues before deploy..."
    }
  ]
}
```

### Compliance Queries

| Query | Purpose |
|-------|---------|
| Entries without validation | Find incomplete entries |
| Entries by phase | Audit specific phase completion |
| Author activity | Track agent contributions |
| Time range | Period compliance reports |
| Missing reasoning | Quality gate |

## Integrity Verification

### Verification Script

```bash
python3 scripts/changelog_manager.py --workspace . --action verify
```

### Checks Performed

| Check | Pass Criteria |
|-------|---------------|
| Has [Unreleased] section | Present in file |
| Keep a Changelog reference | URL present |
| Semantic Versioning reference | URL present |
| Entry count > 0 | At least one entry |
| All entries have Author | No missing Author |
| All entries have Reason | No missing Reason |
| All entries have timestamp | Format YYYY-MM-DD HH:MM:SS |
| No duplicate timestamps | Unique timestamps |

### Failed Integrity = Block

| Failure | Action |
|---------|--------|
| Missing [Unreleased] | Block deploy |
| Deleted entries detected | Block deploy, investigate |
| Modified timestamps | Block deploy |
| Missing required fields | Block deploy |
| Non-chronological | Block deploy |

## Automation

### Auto-Entry on Successful Operations

```bash
# enterprise-org.py automatically creates entries on:
# - init (phase: initialization)
# - validate (phase: validation)
# - enforce (phase: enforcement)
# - audit (phase: audit)

# Manual entry when needed:
python3 scripts/changelog_manager.py --workspace . --action add \
  --phase "custom-phase" \
  --author "agent-name" \
  --reason "Custom reason" \
  --method "manual" \
  --validation "validation-artifact.json: valid=true"
```

### CI/CD Integration

```yaml
# .github/workflows/changelog.yml
- name: Verify CHANGELOG Integrity
  run: python3 scripts/changelog_manager.py --workspace . --action verify --json

- name: Require CHANGELOG entry for deploy
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  run: |
    # Check last commit touched CHANGELOG
    git diff HEAD~1 --name-only | grep -q CHANGELOG.md || exit 1
```

## Retention & Archival

| Period | Action |
|---------|--------|
| Active | In CHANGELOG.md |
| 90 days | Archive to `backups/changelog/` |
| 1 year | Compress, cold storage |
| 7 years | Legal/compliance archive |

### Archive Format

```bash
# Monthly archive
cp CHANGELOG.md backups/changelog/CHANGELOG-$(date +%Y%m).md
```

## Quick Reference

```bash
# Add entry
python3 scripts/changelog_manager.py --workspace . --action add \
  --phase "phase" --author "agent" --reason "reason" \
  --method "method" --validation "validation"

# List entries
python3 scripts/changelog_manager.py --workspace . --action list \
  --phase-filter "security" --author-filter "titan" --since "2026-01-01"

# Verify integrity
python3 scripts/changelog_manager.py --workspace . --action verify

# All output JSON for automation
python3 scripts/changelog_manager.py --workspace . --action list --json
```

**Every change has a reason. Every reason is recorded. Every record is immutable.**