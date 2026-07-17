# Tar Archiving Best Practices for USB Deployment

## Overview
Creating portable, minimal tar.gz archives for USB deployment requires careful path handling and exclusion strategies.

## Core Principles

### 1. Always Use Explicit Exclusions
```bash
tar -czf package.tar.gz \
  --exclude=.git \
  --exclude=node_modules \
  --exclude=scripts/scripts \
  --exclude=*.pyc \
  --exclude=*.log \
  --exclude=*.tgz \
  --exclude=*.tar.gz \
  --exclude=*.zip \
  -C /staging/project .
```

### 2. Correct Prefix Handling
The tar archive should have a consistent root prefix:
```bash
# CORRECT: Creates archive with "hemlock-minimal/" prefix
tar -czf package.tar.gz -C /staging/folder project-name

# WRONG: Creates archive with nested paths
tar -czf package.tar.gz -C /staging project-name
```

### 3. Staging Directory Pattern
```bash
# 1. Stage everything in /tmp/staging/project-name
# 2. Run tar from staging parent
tar -czf package.tar.gz -C /tmp/staging project-name
# Result: archive contains "project-name/file1", "project-name/file2", etc.
```

## Common Pitfalls

| Issue | Cause | Fix |
|-------|-------|-----|
| Missing root files | Tar from wrong directory | Stage all files in one directory first |
| Prefix issues | Archive has wrong root | Use `-C /staging project-name` |
| Duplicate files | Nested directories included | Exclude `scripts/scripts` and inner project |
| Archive too large | `.git` or `node_modules` included | Always exclude first |
| Symlinks broken | Absolute paths in symlinks | Use relative paths: `../target` |

## Hemlock Minimal Specific (Session 2026-06-13)

### Source Structure
```
/home/ubuntu/hemlock-minimal/
├── docker-compose.yml          # Outer root files
├── Dockerfile.runtime          # Outer root files
├── entrypoint.sh               # Outer root files
├── mcp_bridge.py               # Outer root files
├── .gitignore                  # Outer root files
├── README.md                   # Outer root files
├── CHANGELOG.md                # Outer root files
├── TODO.md                     # Outer root files
├── blueprint/                  # Outer root dir
├── docker/                     # Outer root dir
├── scripts/                    # Outer root dir (20+ scripts)
├── hemlock-minimal/            # NESTED inner project
│   ├── .gitignore
│   ├── README.md
│   ├── CHANGELOG.md
│   ├── scripts/                # Inner scripts (3 files)
│   ├── tests/                  # Test suite
│   ├── skills/                 # Inner skills
│   └── ...
└── .git/
```

### Staging Strategy
```bash
staging=/tmp/staging/hemlock-minimal

# 1. Copy INNER project (has .git, scripts, tests, skills, etc.)
cp -r hemlock-minimal/hemlock-minimal /tmp/staging/hemlock-minimal

# 2. Overlay OUTER root files
for item in docker-compose.yml Dockerfile.runtime entrypoint.sh mcp_bridge.py .gitignore README.md CHANGELOG.md TODO.md blueprint; do
    cp -r hemlock-minimal/$item /tmp/staging/hemlock-minimal/
done

# 3. Overlay outer docker/
cp -r hemlock-minimal/docker /tmp/staging/hemlock-minimal/docker

# 4. Overlay outer scripts/ over inner scripts/
cp -r hemlock-minimal/scripts /tmp/staging/hemlock-minimal/scripts

# 5. Create tar from staging parent
tar -czf package.tar.gz -C /tmp/staging hemlock-minimal
```

### Key Exclusions
```bash
--exclude=.git \
--exclude=node_modules \
--exclude=scripts/scripts \
--exclude=*.pyc \
--exclude=*.log \
--exclude=*.tgz \
--exclude=*.tar.gz \
--exclude=*.zip \
--exclude=tests/node_modules \
--exclude=tests/playwright-report \
--exclude=tests/test-results
```

## Verification Checklist

```bash
# Verify archive structure
tar -tzf package.tar.gz | head -20  # Should show project/ prefix
tar -tzf package.tar.gz | grep -c "project/"  # All entries should have prefix
tar -tzf package.tar.gz | grep ".git"  # Should be 0
tar -tzf package.tar.gz | grep "node_modules"  # Should be 0 (except playwright)
tar -tzf package.tar.gz | grep "scripts/scripts"  # Should be 0

# Check key files
for f in docker-compose.yml Dockerfile.runtime entrypoint.sh mcp_bridge.py .gitignore README.md; do
    echo "hemlock-minimal/$f: $(tar -tzf package.tar.gz | grep -c \"hemlock-minimal/$f\" && echo FOUND || echo MISSING)"
done
```

## Size Optimization

| Technique | Savings |
|-----------|---------|
| Exclude `.git` | ~50 MB |
| Exclude `node_modules` | ~35 MB |
| Exclude `docker/openclaw-runtime/` | ~15 MB |
| Exclude `.pytest_cache`, `__pycache__` | ~1 MB |
| Shallow git clone (`--depth 1`) | ~5 MB |

## Verification Commands

```bash
# Quick health check
tar -tzf hemlock-minimal.tar.gz | head -5      # Check prefix
tar -tzf hemlock-minimal.tar.gz | wc -l        # Entry count
tar -tzf hemlock-minimal.tar.gz | grep "\.git" # Should be 0
du -h hemlock-minimal.tar.gz                   # Size check

# Extract and test
mkdir /tmp/test && tar -xzf hemlock-minimal.tar.gz -C /tmp/test
/tmp/test/hemlock-minimal/scripts/hemlock gateway start
```