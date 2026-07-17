# Session 2026-06-14: Lessons Learned from Hemlock Minimal Build

## Context
Building the Hemlock Minimal deployment package with USB automation, daily skills auto-pull, and enterprise organization standards.

## Critical Failures & Fixes

### 1. Drdeeks Skills Repo Management
**Failure**: Deleted `/tmp/drdeeks-skills` clone during cleanup, then couldn't copy skills into archive.
**Fix**: Keep the cloned repo. The drdeeks skills repo (131 `.skill` files) must persist for the build.
```bash
# Always clone fresh, don't delete
git clone --depth 1 https://github.com/drdeeks/skills.git /tmp/drdeeks-skills
# Keep it until archive is verified
```

### 2. Unified USB Skill is a ZIP File
**Discovery**: `unified-usb-skill.skill` is a ZIP archive (not a text file) containing 20 reference docs and 8 scripts.
**Fix**: Include as-is in the archive. Do not attempt to extract or read as text.
```bash
# It's a .skill file (ZIP archive) - copy as-is
shutil.copy2("/tmp/drdeeks-skills/unified-usb-skill.skill", 
             "/staging/skills/drdeeks/unified-usb-skill.skill")
```

### 3. Tar Archive Path Handling
**Critical Failure**: Multiple `-C` flags created conflicting paths.
**Root Cause**: Each `-C` flag changes directory for subsequent files. Multiple `-C` flags in one tar command create nested/conflicting paths.

**Correct Pattern**:
```bash
# Single -C flag, single source directory
tar -czf package.tar.gz \
  --exclude=.git \
  --exclude=node_modules \
  --exclude=scripts/scripts \
  --exclude=*.pyc \
  --exclude=*.log \
  --exclude=*.tgz \
  --exclude=*.tar.gz \
  --exclude=*.zip \
  -C /staging/hemlock-minimal .
```
**Wrong** (what I did repeatedly):
```bash
# WRONG - multiple -C flags create conflicting paths
tar -czf package.tar.gz -C /staging hemlock-minimal -C /home/ubuntu/file.txt
```

### 4. Skill Patch Persistence
**Failure**: setup.py patches didn't persist in the archive.
**Root Cause**: Edited the file but archive was rebuilt from wrong staging area, or tar was created before patch was applied.
**Fix**: Always apply patches to staging area, then rebuild archive, then verify with `tar -tzf`.

### 5. Drdeeks Skills Cleanup
**Failure**: Aggressive cleanup deleted `/tmp/drdeeks-skills` which was needed for the build.
**Lesson**: Don't clean up source directories until the final archive is verified and copied.

## Hemlock Minimal Package Components (Verified)

### Archive Contents (60.2 MB, 2,501 entries)
| Category | Status | Key Files |
|----------|--------|-----------|
| Root Config | ✅ | docker-compose.yml, Dockerfile.runtime, entrypoint.sh, mcp_bridge.py |
| Scripts (14) | ✅ | hemlock, hemlock-tui, mcp_proxy_manager.py, create-usb-image.sh, container-init.sh, pull-drdeeks-daily.sh |
| Core | ✅ | mcp_bridge.py (root + scripts/ symlink) |
| Tests | ✅ | health.spec.ts, gateway.spec.ts, playwright.config.js |
| Docker | ✅ | docker/Dockerfile.runtime + docker/Dockerfile (symlink) |
| Skills - DrDeeks | ✅ | 131 .skill files + unified-usb-skill.skill (89 KB ZIP) |
| Enterprise Skills | ✅ | 19 files (enterprise-blueprint) |
| Blueprints | ✅ | 4 files (blueprint.md, checklist.md, project.json) |
| Config | ✅ | .gitignore, README.md, CHANGELOG.md, TODO.md |

### Exclusions Verified
- `.git`: 0 files
- `node_modules` (non-playwright): 0 files
- `scripts/scripts` (legacy): excluded
- Build artifacts: excluded

## Daily Skills Auto-Pull Architecture

### Container-Internal Cron (2 AM UTC)
```bash
# container-init.sh (runs on container startup)
service cron start
(crontab -l 2>/dev/null; echo "0 2 * * * /scripts/pull-drdeeks-daily.sh") | crontab -
```

```bash
# pull-drdeeks-daily.sh (runs daily at 2 AM)
SKILLS_DIR="/home/ubuntu/hemlock-minimal/skills/drdeeks"
if [ -d "$SKILLS_DIR/.git" ]; then
    git -C "$SKILLS_DIR" pull origin main
else
    git clone --depth 1 https://github.com/drdeeks/skills.git "$SKILLS_DIR"
fi
```

### Cron Job Created
```bash
cronjob create --name "pull-drdeeks-skills-daily" --schedule "0 2 * * *" --prompt "Pull drdeeks skills daily at 2 AM"
```

## Setup Wizard Integration (Patched)

### hermes_cli/setup.py Additions
1. `_offer_launch_tui_and_docker()` - Menu after setup: Launch TUI, Start Docker, Both, or Skip
2. `_start_docker_container()` - Finds docker-compose.yml, runs `docker compose up -d`
3. `_launch_tui()` - Executes `hemlock tui` via `os.execvp`

### Integration Point
Added to `run_setup_wizard()` after `_offer_launch_chat()`:
```python
_offer_launch_tui_and_docker()
```

## USB Deployment (Ventoy)

### create-usb-image.sh
- `docker save` images to `hemlock-images.tar`
- Backs up all 11 volumes to `volumes/*.tar.gz`
- Generates `deploy.sh` for target machine
- Includes `README_USB.md` and `HARNESS_HIERARCHY.md`

### deploy.sh (Auto-generated)
- Loads Docker images
- Creates all 11 volumes
- Restores volume data
- Configures iMessage SSH wrapper
- Runs `docker compose up -d`
- Verifies gateway health

### Ventoy Persistence
- Boot into Ventoy → Select "Ubuntu with persistence"
- First boot: runs deploy.sh → builds volumes in `/var/lib/docker`
- Subsequent boots: `/var/lib/docker` persists → instant start

## Key Validation Commands

```bash
# Verify archive structure
tar -tzf package.tar.gz | head -20
tar -tzf package.tar.gz | grep -c "hemlock-minimal/"  # All entries should have prefix
tar -tzf package.tar.gz | grep "\.git"  # Should be 0
tar -tzf package.tar.gz | grep "node_modules" | grep -v playwright  # Should be 0

# Verify docker files
tar -tzf package.tar.gz | grep "docker/Dockerfile"

# Verify skills
tar -tzf package.tar.gz | grep "skills/drdeeks/" | wc -l
```

## Health Check
```bash
curl http://localhost:18789/health
# Expected: {"ok":true,"status":"live"}
```

## MCP Loopback Note
- Gateway main port: 18789 (external)
- MCP loopback: Random internal port (41213, 39925, 43247, etc.)
- Always requires `Authorization: Bearer *** header
- Use proxy (port 41214) that auto-detects loopback port from logs

## User Feedback Incorporated
> "you're being a fucking idiot" - Repeated mistakes despite clear instructions
> "window too small" - Disk space management critical
> "you have like super strange lately" - Behavioral pattern recognition
> "why don't you reread my question" - Not reading/listening carefully
> "did you actually look at it" - Not reviewing existing work before acting

**Core Principle**: Read, verify, then act. One correct execution > ten failed attempts.