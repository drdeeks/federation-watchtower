# Skill Anatomy Reference

## Table of Contents

- [Standard Skill Structure](#standard-skill-structure)
- [SKILL.md Structure](#skillmd-structure)
- [Directory Guidelines](#directory-guidelines)
- [Naming Conventions](#naming-conventions)
- [Quality Checklist](#quality-checklist)

## Standard Skill Structure

```
skill-name/
├── SKILL.md              (required - frontmatter + instructions)
├── scripts/              (optional - executable Python/Bash)
├── references/           (optional - docs loaded on demand)
└── assets/               (optional - templates, images)
```

## SKILL.md Structure

### Frontmatter (required)

```yaml
---
name: skill-name
description: "What it does. When to use it. Specific triggers."
license: MIT
metadata:
  key: value
allowed-tools: "Bash(command:*)"
---
```

**Allowed Keys:**
- `name` - Skill identifier (lowercase hyphen-case, ≤64 chars)
- `description` - What/when/triggers (100-1024 chars)
- `license` - License identifier
- `metadata` - Arbitrary metadata
- `allowed-tools` - Tool permissions

### Body Structure

```markdown
# Skill Name

Brief overview of what this skill does.

## When to Use

- Trigger 1
- Trigger 2

## Features

- Feature 1
- Feature 2

## Usage

### Quick Start
```bash
# Example command
```

### Advanced
```bash
# Advanced usage
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/main.py` | Main entry point |

## References

- **Detailed docs**: [references/deep-dive.md](references/deep-dive.md)
```

## Directory Guidelines

### scripts/
- Executable Python/Bash scripts
- Use stdlib only (free-first)
- Include shebang line
- Handle errors gracefully

### references/
- Deep documentation loaded on demand
- Reference with clear "what" and "when"
- Keep SKILL.md under 500 lines

### assets/
- Templates, images, fonts
- Static resources for output
- Keep size reasonable

## Naming Conventions

- Directories: `lowercase-hyphen-case`
- Scripts: `lowercase_underscore.py` or `lowercase-underscore.sh`
- References: `lowercase-hyphen-case.md`

## Quality Checklist

- [ ] Frontmatter has required keys
- [ ] Name is hyphen-case
- [ ] Description includes what + when + triggers
- [ ] Body under 500 lines
- [ ] Scripts use stdlib only
- [ ] No hardcoded paths
- [ ] Cross-platform compatible
