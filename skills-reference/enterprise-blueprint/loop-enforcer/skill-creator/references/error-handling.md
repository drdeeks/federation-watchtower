# Skill Creator — Error Handling

Error catalog and recovery procedures for skill creation, validation, and packaging operations.

## Table of Contents

1. [Error Categories](#error-categories)
2. [Recovery Procedures](#recovery-procedures)
3. [Common Validation Failures](#common-validation-failures)

---

## Error Categories

| Category | Examples | Response |
|---|---|---|
| **Filesystem** | Permission denied, disk full, path too long | Check permissions, free space, shorten paths |
| **YAML Parsing** | Invalid frontmatter, missing delimiters | Validate YAML syntax, check `---` delimiters |
| **Naming** | Invalid characters, name too long, consecutive hyphens | Normalize to hyphen-case, enforce 64-char max |
| **Validation** | Missing required sections, stale templates | Run `validate_enterprise.py --verbose`, fix each FAIL |
| **Packaging** | Symlinks present, file escapes skill root, missing SKILL.md | Remove symlinks, verify directory structure |
| **Script Execution** | Python not found, missing dependencies, encoding errors | Check Python 3.8+, install deps, use UTF-8 |

## Recovery Procedures

### Validation Failure Recovery

1. Run `validate_enterprise.py /path/to/skill --verbose` to see all checks
2. Fix all FAIL items first (these block enterprise rating)
3. Fix WARN items to reach zero warnings
4. Re-run validation after each batch of fixes
5. Target: 0 FAIL, 0 WARN = Enterprise Grade

### Packaging Failure Recovery

| Symptom | Cause | Fix |
|---|---|---|
| "Validation failed" | SKILL.md has errors | Fix validation errors first |
| "Symlink detected" | Symlink in skill directory | Replace symlinks with real files |
| "File escapes root" | Path traversal attempt | Remove `../` references |
| "SKILL.md not found" | Wrong directory path | Point to the skill root dir |

### YAML Frontmatter Issues

| Error | Example | Fix |
|---|---|---|
| Missing delimiter | No closing `---` | Add `---` after frontmatter |
| Unquoted special chars | `description: Use for: X` | Wrap in quotes: `"Use for: X"` |
| Extra fields | `version: 1.0` in frontmatter | Remove; only `name` and `description` allowed |
| Description too long | >1024 characters | Shorten; move detail to SKILL.md body |

## Common Validation Failures

### Enterprise Standard FAILs

| FAIL | Root Cause | Quick Fix |
|---|---|---|
| scripts/ has <2 scripts | Missing operational scripts | Add at minimum setup.py + one domain script |
| references/ has <3 files | Missing reference docs | Add workflow-guide.md, error-handling.md, free-first-strategy.md |
| No Provider Compatibility | Section missing from SKILL.md | Add table with 5+ providers |
| No Free-First Strategy | No cost tier documentation | Add Tier 0/1/2 table |
| No Output Statistics | No output format spec | Add JSON format block |
| No Error Handling | No error documentation | Add error table or reference link |
| No Scripts table | Scripts not listed in SKILL.md | Add `## Scripts` with table |
| No Key References | References not linked | Add `## Key References` with links |

### Warning Prevention

| WARN | Prevention |
|---|---|
| Body >500 lines | Move detail to references/ files |
| <6 sections | Ensure all enterprise sections present |
| No Workflow section | Add at least one `## Workflow:` header |
| Stale templates | Delete `example.py`, `api_reference.md`, `example_asset.txt` |
| Orphan files | Mention every script/reference in SKILL.md |
