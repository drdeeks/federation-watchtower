# Release Workflow Reference

## Overview

Complete release workflow combining version management, phase tagging, CHANGELOG updates, git tagging, and push operations.

## Release Command

```bash
# Full release workflow
python3 scripts/enterprise-org.py release [options]

# Options:
#   --bump TYPE          major|minor|patch (default: patch)
#   --release-message    Custom release message
#   --no-push            Don't push to remote
```

## What Happens During Release

```
1. Get current version from git tags / VERSION file
2. Bump version (major/minor/patch)
3. Update VERSION file, pyproject.toml, package.json, setup.py
4. Create annotated git tag: v<version>
5. Generate release notes from commits + CHANGELOG
6. Add CHANGELOG entry for release
7. Push commits and tags to origin (if --push)
```

## Release Output

### Files Updated
- `VERSION` - New version number
- `pyproject.toml` - If present
- `package.json` - If present
- `setup.py` - If present
- `CHANGELOG.md` - New release entry

### Git Artifacts
- Annotated tag: `v<major>.<minor>.<patch>`
- Release commit with version bump
- Optional: Phase completion tag for release phase

### Release Notes
Generated as Markdown:
```markdown
# Release 1.2.3

**Date:** 2026-06-10

## Changes
- Release version 1.2.3
- Version bumped from 1.2.2 to 1.2.3

## Commits
- abc1234 feat(auth): add JWT support (author)
- def5678 fix: resolve memory leak (author)
```

## Release Types

### Patch Release (Default)
```bash
python3 scripts/enterprise-org.py release --bump patch
```
- Bug fixes
- Security patches
- Dependency updates
- Documentation fixes

### Minor Release
```bash
python3 scripts/enterprise-org.py release --bump minor
```
- New features (backward compatible)
- New APIs
- Enhanced functionality

### Major Release
```bash
python3 scripts/enterprise-org.py release --bump major
```
- Breaking changes
- API removals
- Architecture changes
- Minimum version bumps

### Prerelease
```bash
# Alpha
python3 scripts/enterprise-org.py version --action bump --bump-type minor --prerelease alpha.1

# Beta
python3 scripts/enterprise-org.py version --action bump --bump-type minor --prerelease beta.1

# Release Candidate
python3 scripts/enterprise-org.py version --action bump --bump-type minor --prerelease rc.1
```

### Stabilize Prerelease
```bash
# RC to final
python3 scripts/enterprise-org.py version --action bump --bump-type patch
# Removes prerelease suffix
```

## Complete Release Process

### 1. Prepare
```bash
# Ensure clean working tree
python3 scripts/enterprise-org.py git --git-action status

# Run full validation
python3 scripts/enterprise-org.py validate --strict

# Complete current phase
python3 scripts/enterprise-org.py phase --action complete --phase "release-prep" --summary "Ready for release"
```

### 2. Release
```bash
# Patch release
python3 scripts/enterprise-org.py release --bump patch --release-message "Patch release with security fixes"

# Or with specific version
python3 scripts/enterprise-org.py version --action release --version-arg 1.2.3 --message "Release 1.2.3" --push
```

### 3. Verify
```bash
# Check version
python3 scripts/enterprise-org.py version --action get

# Check tags
python3 scripts/enterprise-org.py git --git-action log --limit 5

# Verify release notes
python3 scripts/enterprise-org.py version --action notes --version-arg 1.2.3
```

## Release Checklist

- [ ] Working tree clean
- [ ] All tests pass
- [ ] Validation passes (strict mode)
- [ ] CHANGELOG updated
- [ ] Version bumped correctly
- [ ] Tag created and pushed
- [ ] Release notes generated
- [ ] Deployment triggered (if CI/CD)

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      bump:
        type: choice
        options: [patch, minor, major]
        default: patch

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Run release
        run: |
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          python3 scripts/enterprise-org.py release \
            --bump ${{ github.event.inputs.bump }} \
            --release-message "Automated ${{ github.event.inputs.bump }} release"
```

### GitLab CI Example
```yaml
release:
  stage: release
  script:
    - git config user.name "gitlab-ci"
    - git config user.email "ci@gitlab.com"
    - python3 scripts/enterprise-org.py release --bump patch --push
  only:
    - tags
```

## Rollback Release

If release has issues:

```bash
# 1. Revert version bump commit
python3 scripts/enterprise-org.py git --git-action log --limit 3
# Find commit before version bump
python3 scripts/enterprise-org.py git --git-action reset --hard <commit-hash>

# 2. Delete tag locally and remotely
git tag -d v1.2.3
git push origin --delete v1.2.3

# 3. Update VERSION file
echo "1.2.2" > VERSION
git add VERSION
git commit -m "chore: rollback version to 1.2.2"
git push
```

## Version History

List all releases:
```bash
python3 scripts/enterprise-org.py version --action list
```

Output:
```
Current: 1.2.3
Versions:
  1.2.3 (v1.2.3) - 2026-06-10
  1.2.2 (v1.2.2) - 2026-06-08
  1.2.1 (v1.2.1) - 2026-06-05
  1.1.0 (v1.1.0) - 2026-06-01
  1.0.0 (v1.0.0) - 2026-05-28
```

## Best Practices

1. **Automate releases** - Use CI/CD for consistent releases
2. **Tag every release** - Annotated tags with messages
3. **Generate notes** - From commits and CHANGELOG
4. **Test before release** - Full validation suite
5. **Communicate** - Release notes for stakeholders
6. **Rollback plan** - Document rollback procedure
7. **Sign tags** - GPG sign for authenticity
8. **Version in CI** - Pass version as build artifact