# Git Control Reference

## Overview

Robust git operations for enterprise workflows including commits, branching, merging, hooks, and synchronization.

## CLI Usage

All commands available via `git_control.py` or `enterprise-org.py git`.

### Status
```bash
# Show git status with branch info
python3 scripts/git_control.py status --workspace .
```

### Stage Files
```bash
# Stage specific files
python3 scripts/git_control.py add --paths "scripts/*.py" "README.md" --workspace .

# Stage all changes
python3 scripts/git_control.py add --all --workspace .
```

### Commit
```bash
# Basic commit
python3 scripts/git_control.py commit --message "feat: add new feature" --workspace .

# With author
python3 scripts/git_control.py commit --message "fix: bug" --author "Agent <agent@example.com>" --workspace .

# Amend last commit
python3 scripts/git_control.py commit --amend --message "updated message" --workspace .

# Signed commit
python3 scripts/git_control.py commit --sign --message "feat: signed" --workspace .
```

### Push
```bash
# Push current branch
python3 scripts/git_control.py push --workspace .

# Push specific branch
python3 scripts/git_control.py push --branch main --workspace .

# Force push (with caution)
python3 scripts/git_control.py push --force --workspace .

# Push tags
python3 scripts/git_control.py push --tags --workspace .
```

### Pull
```bash
# Pull with merge (default)
python3 scripts/git_control.py pull --workspace .

# Pull with rebase
python3 scripts/git_control.py pull --rebase --workspace .

# Pull specific branch
python3 scripts/git_control.py pull --branch feature/auth --workspace .
```

### Branch Management
```bash
# List all branches
python3 scripts/git_control.py branch --list --workspace .

# Create and switch to branch
python3 scripts/git_control.py branch --name feature/auth --create --workspace .

# Switch to existing branch
python3 scripts/git_control.py branch --name feature/auth --workspace .

# Delete branch
python3 scripts/git_control.py branch --name feature/auth --delete --workspace .
```

### Merge
```bash
# Merge with fast-forward (default)
python3 scripts/git_control.py merge --source feature/auth --workspace .

# Merge with no fast-forward (preserves history)
python3 scripts/git_control.py merge --source feature/auth --no-ff --workspace .

# Squash merge (single commit)
python3 scripts/git_control.py merge --source feature/auth --squash --workspace .

# Merge into specific target
python3 scripts/git_control.py merge --source feature/auth --target main --workspace .
```

### Log
```bash
# Last 20 commits (oneline)
python3 scripts/git_control.py log --workspace .

# Last 50 commits
python3 scripts/git_control.py log --limit 50 --workspace .

# Since date
python3 scripts/git_control.py log --since "2026-06-01" --workspace .

# By author
python3 scripts/git_control.py log --author "enterprise-agent" --workspace .
```

### Diff
```bash
# Unstaged changes
python3 scripts/git_control.py diff --workspace .

# Staged changes
python3 scripts/git_control.py diff --staged --workspace .

# Specific file
python3 scripts/git_control.py diff --file "scripts/enterprise-org.py" --workspace .
```

### Stash
```bash
# Stash current changes
python3 scripts/git_control.py stash push --name "wip-feature" --workspace .

# Pop latest stash
python3 scripts/git_control.py stash pop --workspace .

# List stashes
python3 scripts/git_control.py stash list --workspace .

# Drop stash
python3 scripts/git_control.py stash drop --name "stash@{0}" --workspace .
```

### Git Hooks Setup
```bash
# Install enterprise hooks (pre-commit, commit-msg, pre-push)
python3 scripts/git_control.py hooks --workspace .
```

Installs:
- **pre-commit**: Runs placeholder scanner + security check
- **commit-msg**: Validates conventional commit format
- **pre-push**: Runs full validation suite

### Sync (Pull + Push + Tags)
```bash
# Full synchronization
python3 scripts/git_control.py sync --workspace .

# Sync specific branch
python3 scripts/git_control.py sync --branch main --workspace .
```

## Integration with enterprise-org.py

```bash
# All git operations via unified interface
python3 scripts/enterprise-org.py git --git-action status
python3 scripts/enterprise-org.py git --git-action commit --commit-message "feat: add feature"
python3 scripts/enterprise-org.py git --git-action push --tags
python3 scripts/enterprise-org.py git --git-action sync
python3 scripts/enterprise-org.py git --git-action hooks
```

## Enterprise Git Hooks

### Pre-commit Hook
Runs before each commit:
```bash
# Checks:
1. Placeholder scanner (fails on TODO/FIXME/TBD/WIP)
2. Security hardening check

# Bypass: git commit --no-verify
```

### Commit-msg Hook
Validates commit message format:
```bash
# Required format:
type(scope): description

# Examples:
feat(auth): add OAuth2 login
fix: resolve memory leak
BREAKING CHANGE: remove deprecated API

# Invalid: "fixed bug" - will warn but not block
```

### Pre-push Hook
Runs before push:
```bash
# Runs full validation:
python3 scripts/enterprise-org.py validate --workspace .

# Bypass: git push --no-verify
```

## Branch Strategy

### Main Branch
- Protected: `main`
- Only accepts merges via PR/review
- Contains production-ready code

### Feature Branches
- Naming: `feature/<short-description>`
- Created from `main`
- Merged with `--no-ff` to preserve history

### Release Branches
- Naming: `release/<version>`
- Created for release stabilization
- Only bug fixes allowed

### Hotfix Branches
- Naming: `hotfix/<issue>`
- Created from `main` for urgent fixes
- Merged back to `main` and `develop`

## Merge Strategies

| Strategy | Use Case | Command |
|----------|----------|---------|
| Fast-forward | Simple linear history | `merge --source feature` |
| No fast-forward | Preserve branch topology | `merge --source feature --no-ff` |
| Squash | Single commit for feature | `merge --source feature --squash` |

## Conventional Commits

Format enforced by commit-msg hook:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation
- `style` - Formatting
- `refactor` - Code restructuring
- `perf` - Performance
- `test` - Tests
- `chore` - Maintenance
- `revert` - Revert previous commit

### Breaking Changes
```
feat(api)!: remove deprecated endpoint

BREAKING CHANGE: endpoint /v1/users removed
```

## Best Practices

1. **Commit early, commit often** - Small, focused commits
2. **Write clear messages** - Follow conventional format
3. **Pull before push** - Avoid conflicts
4. **Use branches** - Isolate work
5. **Review before merge** - PRs for team workflows
6. **Sign important commits** - GPG signing for releases
7. **Keep history clean** - Rebase feature branches before merge
8. **Tag releases** - Annotated tags for all versions

## Troubleshooting

### Hook Not Running
```bash
# Check hook exists and is executable
ls -la .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### Merge Conflicts
```bash
# Resolve manually, then:
git add <resolved-files>
git commit --no-verify
```

### Detached HEAD
```bash
# Create branch from current commit
git branch recovery-branch
git checkout recovery-branch
```

### Lost Commits
```bash
# Use reflog
git reflog
git checkout <commit-hash>
```