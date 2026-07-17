# Semantic Versioning Reference

## Overview

Semantic versioning (SemVer) provides a formal convention for specifying compatibility using a three-part version number: MAJOR.MINOR.PATCH.

## Version Format

```
MAJOR.MINOR.PATCH[-prerelease][+build]
```

Examples:
- `1.0.0` - First stable release
- `1.2.3` - Patch release
- `2.0.0` - Major breaking release
- `1.0.0-alpha.1` - Prerelease
- `1.0.0+build.123` - Build metadata

## Version Bumping Rules

| Change Type | Bumps | Example |
|-------------|-------|---------|
| Breaking changes | MAJOR | 1.2.3 → 2.0.0 |
| New features (backward compatible) | MINOR | 1.2.3 → 1.3.0 |
| Bug fixes (backward compatible) | PATCH | 1.2.3 → 1.2.4 |
| Pre-release | Prerelease | 1.2.3 → 1.2.4-alpha.1 |

## Version Storage

The skill checks version in this priority order:

1. **Git tags** (`v*` pattern) - `git describe --tags --abbrev=0 --match v*`
2. **VERSION file** - Simple text file with version
3. **pyproject.toml** - `[project] version = "..."`
4. **package.json** - `"version": "..."`
5. **setup.py** - `version="..."`

## CLI Usage

### Get Current Version
```bash
python3 scripts/version_manager.py get --workspace .
```

### Set Version
```bash
python3 scripts/version_manager.py set 1.2.3 --workspace .
```

### Bump Version
```bash
# Patch bump (bug fixes)
python3 scripts/version_manager.py bump patch --workspace .

# Minor bump (new features)
python3 scripts/version_manager.py bump minor --workspace .

# Major bump (breaking changes)
python3 scripts/version_manager.py bump major --workspace .

# With prerelease
python3 scripts/version_manager.py bump minor --prerelease alpha.1 --workspace .
```

### Create Release Tag
```bash
python3 scripts/version_manager.py release 1.2.3 --message "Release 1.2.3" --push --workspace .
```

### Generate Release Notes
```bash
python3 scripts/version_manager.py notes 1.2.3 --workspace .

# From specific tag
python3 scripts/version_manager.py notes 1.2.3 --from-tag v1.2.0 --workspace .
```

### List All Versions
```bash
python3 scripts/version_manager.py list --workspace .
```

## Integration with enterprise-org.py

```bash
# Bump and get new version
python3 scripts/enterprise-org.py version --action bump --bump-type patch

# Create release
python3 scripts/enterprise-org.py version --action release --version-arg 1.2.3 --push

# Generate notes
python3 scripts/enterprise-org.py version --action notes --version-arg 1.2.3

# List versions
python3 scripts/enterprise-org.py version --action list
```

## Combined Release Workflow

```bash
# Full release in one command
python3 scripts/enterprise-org.py release --bump patch --release-message "Bug fix release"
```

This will:
1. Get current version
2. Bump according to type (major/minor/patch)
3. Update VERSION file and other config files
4. Create annotated git tag
5. Generate release notes
6. Add CHANGELOG entry
7. Push (if --push flag)

## Release Note Format

Generated release notes include:

```markdown
# Release 1.2.3

**Date:** 2026-06-10

## Changes
- Entry 1 from CHANGELOG
- Entry 2 from CHANGELOG

## Commits
- abc1234 feat(auth): add JWT support (author)
- def5678 fix: resolve memory leak (author)
```

## Prerelease Versions

Use prerelease for:
- Alpha: `1.0.0-alpha.1` (internal testing)
- Beta: `1.0.0-beta.1` (external testing)
- RC: `1.0.0-rc.1` (release candidate)

Bumping from prerelease:
- `1.0.0-alpha.1` → `bump patch` → `1.0.0-alpha.2`
- `1.0.0-rc.1` → `bump patch` (no prerelease) → `1.0.0`

## Version File Updates

When setting/bumping version, these files are updated:
- `VERSION` - Always created/updated
- `pyproject.toml` - If exists
- `package.json` - If exists
- `setup.py` - If exists

## Best Practices

1. **Default to patch** - Most releases are patches
2. **Document breaking changes** - In CHANGELOG and release notes
3. **Tag commits, not branches** - Release tags on specific commits
4. **Use conventional commits** - Enables automated changelog
5. **Test before release** - Run full validation suite
6. **Sign tags** - Use `git tag -s` for GPG-signed releases

## Conventional Commits Mapping

| Commit Type | Version Bump |
|-------------|--------------|
| `feat:` | MINOR |
| `fix:` | PATCH |
| `BREAKING CHANGE:` | MAJOR |
| `refactor:` | PATCH |
| `perf:` | PATCH |
| `docs:` | None (or PATCH) |
| `chore:` | None (or PATCH) |