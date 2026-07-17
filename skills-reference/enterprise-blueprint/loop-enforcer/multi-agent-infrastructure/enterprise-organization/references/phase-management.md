# Phase Management Reference

## Overview

Phase management provides a structured way to organize development work into discrete, traceable phases. Each phase has metadata, git tags, CHANGELOG entries, and task tracking.

## Phase Structure

### Phase Definition (.phases.json)
```json
{
  "phase-name": {
    "description": "Human-readable description",
    "tags": ["tag1", "tag2"],
    "created": "2026-06-10T10:00:00.000Z",
    "status": "active|completed",
    "completed": "2026-06-10T12:00:00.000Z",
    "summary": "Completion summary",
    "milestones": []
  }
}
```

### Git Tags
- **Start**: `phase-<name>-<YYYYMMDD-HHMMSS>` - Annotated tag marking phase start
- **Complete**: `phase-<name>-complete-<YYYYMMDD-HHMMSS>` - Annotated tag marking phase completion
- **Files**: `phase-<name>-files-<YYYYMMDD-HHMMSS>` - Annotated tag for file snapshots

### CHANGELOG Entries
Each phase creates entries in CHANGELOG.md under `## [Unreleased]`:
```markdown
### phase-name - 2026-06-10 10:00:00
**Author:** enterprise-agent
**Reason:** Phase started: phase-name
**Method:** phase_tagger.py start_phase
**Validation:** Git tag phase-phase-name-20260610-100000 created
**Reasoning:** Starting new development phase

### phase-name (complete) - 2026-06-10 12:00:00
**Author:** enterprise-agent
**Reason:** Phase completed: phase-name
**Method:** phase_tagger.py complete_phase
**Validation:** Git tag phase-phase-name-complete-20260610-120000 created, all tasks verified
**Reasoning:** Implemented feature X with tests
```

### TODO.md Integration
Phases appear as sections in TODO.md:
```markdown
## Phase: phase-name
- [x] Task 1
- [x] Task 2

# Phase phase-name completed: 2026-06-10 12:00:00
```

## CLI Usage

### Define a Phase
```bash
python3 scripts/phase_tagger.py define "feature-auth" "Implement authentication system" --tags auth security
```

### Start a Phase
```bash
# With git tag and commit
python3 scripts/phase_tagger.py start "feature-auth"

# Without commit (for planning)
python3 scripts/phase_tagger.py start "feature-auth" --no-commit --no-tag
```

### Complete a Phase
```bash
python3 scripts/phase_tagger.py complete "feature-auth" --summary "Implemented JWT auth with refresh tokens"
```

### List Phases
```bash
python3 scripts/phase_tagger.py list
```

### Show Phase Details
```bash
python3 scripts/phase_tagger.py show "feature-auth"
```

### Tag Files for Phase
```bash
python3 scripts/phase_tagger.py tag-files "feature-auth" --pattern "scripts/auth_*.py" --message "Auth module files"
```

## Integration with enterprise-org.py

```bash
# Start phase
python3 scripts/enterprise-org.py phase --action start --phase "feature-auth"

# Complete phase
python3 scripts/enterprise-org.py phase --action complete --phase "feature-auth" --summary "Done"

# List all phases
python3 scripts/enterprise-org.py phase --action list
```

## Best Practices

1. **Define before starting** - Use `define` to document phase purpose
2. **One phase at a time** - Complete current phase before starting next
3. **Descriptive summaries** - Include what was done and key decisions
4. **Tag important files** - Snapshot critical files at phase boundaries
5. **Use consistent naming** - Lowercase, hyphenated (e.g., `feature-auth`, `bugfix-memory-leak`)

## Phase Categories

| Category | Prefix | Purpose |
|----------|--------|---------|
| Feature | `feature-` | New functionality |
| Bugfix | `bugfix-` | Bug fixes |
| Refactor | `refactor-` | Code restructuring |
| Security | `security-` | Security improvements |
| Release | `release-` | Release preparation |
| Setup | `setup-` | Initial configuration |
| Migration | `migrate-` | Data/schema migrations |
| Experiment | `experiment-` | R&D work |