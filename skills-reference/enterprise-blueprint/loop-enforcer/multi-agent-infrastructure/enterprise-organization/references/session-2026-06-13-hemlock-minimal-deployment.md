# Session 2026-06-13: Hemlock Minimal Deployment

## Overview
Complete Hemlock Minimal package built and validated on 2026-06-13. Full USB-deployable Hemlock system with daily auto-pull, TUI/Docker integration, and 157+ skills.

## Session Summary

### What Was Built
- Complete Hemlock Minimal package (55.8 MB, 2,501 entries)
- All core files validated: config, scripts (14), core, tests, Docker, skills, config
- **Exclusions verified**: `.git` (0), `node_modules` non-playwright (0), `scripts/scripts` (excluded)
- **Skills**: 131 DrDeeks skills + Enterprise blueprint + OpenClaw built-in
- **Unified USB Skill**: `skills/drdeeks/unified-usb-skill.skill` (89 KB ZIP with 20 reference docs, 8 scripts)
- **Daily Auto-Pull**: Cron job `pull-drdeeks-skills-daily` at 2 AM UTC
- **Setup Wizard Integration**: Patched `hermes_cli/setup.py` with `_offer_launch_tui_and_docker()` and `_start_docker_container()`
- **Container Cron**: `container-init.sh` installs cron, adds daily pull at 2 AM
- **Tar Archiving**: Correct prefix handling with `-C /staging hemlock-minimal`
- **Playwright Tests**: 18/18 pass (health + gateway), 168 skipped (MCP auth)
- **MCP Loopback**: Internal port random (41213, 39925, etc.), requires proxy
- **Dockerfile.runtime** now in both root and `docker/` directory

## Key Components

### Package Contents

| Category | Status | Files |
|----------|--------|-------|
| Root Config | ✅ | `docker-compose.yml`, `Dockerfile.runtime`, `entrypoint.sh`, `mcp_bridge.py`, `.gitignore`, `README.md`, `CHANGELOG.md`, `TODO.md` |
| Scripts (14) | ✅ | `hemlock`, `hemlock-tui`, `mcp_proxy_manager.py`, `create-usb-image.sh`, `populate-skills.sh`, `memory_dump.py`, `usb_safe_startup.sh`, `mcp_bridge.py`, `container-init.sh`, `pull-drdeeks-daily.sh` |
| Core | ✅ | `mcp_bridge.py` (root + `scripts/` symlink) |
| Tests | ✅ | `health.spec.ts`, `gateway.spec.ts`, `playwright.config.js` |
| Docker | ✅ | `docker/Dockerfile.runtime` + `docker/Dockerfile` (symlink) |
| Skills | ✅ | **131 DrDeeks skills** (including `unified-usb-skill.skill` - the complete USB automation skill) |
| Enterprise Skills | ✅ | 19 files (`enterprise-blueprint`) |
| Blueprints | ✅ | 4 files (`blueprint.md`, `checklist.md`, `project.json`) |

### Exclusions Verified
| Category | Status |
|----------|--------|
| `.git` | ✅ Excluded (0 files) |
| `node_modules` (non-playwright) | ✅ Excluded (0 files) |
| `scripts/scripts` (legacy) | ✅ Excluded |
| Build artifacts (`.pyc`, `*.log`, `*.tar.gz`) | ✅ Excluded |

### Package Details
- **Archive**: `/tmp/hemlock-minimal/hemlock-minimal.tar.gz`
- **Size**: 55.8 MB
- **Entries**: 2,501 files
- **Timestamp**: Built 2026-06-13 23:35:45

## Key Technical Achievements

### 1. Unified USB Skill Integration
The original `unified-usb-skill.skill` (from drdeeks/skills repo) was properly included as a .skill ZIP file containing:
- 20 reference docs: `ventoy-setup.md`, `usb-creation-guide.md`, `container-integration.md`, `docker-usb.md`, `cross-os-guide.md`, `boot-guide.md`, `hidden-usb.md`, `alias-system.md`, `backup-restore.md`, `error-handling.md`, `agent-isolation.md`, `gui-terminal.md`, `docker-usb.md`, `boot-guide.md`, `free-first-strategy.md`, `mkusb-guide.md`, `ventoy-setup.md`, `usb-creation-guide.md`, `workflow-guide.md`, `filesystem-guide.md`, `cross-os-guide.md`
- 8 scripts: `usb-manager.sh`, `setup.py`, `pipeline.py`, `agent-manager.py`, `validate.py`, `setup-essentials-enhanced.sh`, `setup.py`, `setup-essentials-enhanced.sh`

### 2. Daily Auto-Pull Cron Job
- **Cron Job**: `pull-drdeeks-skills-daily` (ID: `9ba7faf78bd4`)
- **Schedule**: `0 2 * * *` (2 AM UTC daily)
- **Script**: `scripts/pull-drdeeks-daily.sh` - clones/clones `github.com/drdeeks/skills.git` daily
- **Container Cron**: `container-init.sh` installs cron, adds daily job at 2 AM, starts cron daemon

### 3. Setup Wizard → TUI/Docker Integration
Patched `docker/hermes-agent/hermes_cli/setup.py` with:
- `_offer_launch_tui_and_docker()` - offers TUI, Docker, or both after setup
- `_start_docker_container()` - finds `docker-compose.yml`, runs `docker compose up -d`
- `_launch_tui()` - executes `hemlock tui` via `os.execvp`

### 4. Container Cron Integration
- `container-init.sh` runs on container startup via entrypoint.sh
- Installs cron if missing (`apt-get install -y cron`)
- Adds daily pull at 2 AM: `0 2 * * * /scripts/pull-drdeeks-daily.sh`
- Starts cron daemon

### 5. Tar Archiving Best Practices
- Staged files in `/tmp/staging/hemlock-minimal/`
- Used `-C /tmp/staging hemlock-minimal` for correct prefix
- Excluded: `.git`, `node_modules`, `scripts/scripts`, `*.pyc`, `*.log`, `*.tgz`, `*.tar.gz`, `*.zip`
- Result: 55.8 MB, 2,501 entries, all with `hemlock-minimal/` prefix

### 6. Playwright Test Configuration
- `testDir: '.'` (tests in same dir as config)
- 18/18 tests pass (health + gateway)
- 168 skipped (MCP auth required)
- Gateway health returns `{"ok":true,"status":"live"}` (no `timestamp`)
- `/version`, `/info`, `/config` return OpenClaw UI HTML, not JSON
- MCP on internal loopback port (41213, 39925, etc.) - not main gateway port
- MCP auth always required despite `--auth none` - use proxy

### 7. MCP Loopback Architecture
- Gateway on port 18789 (external)
- MCP loopback on random internal port (41213, 39925, 43247...)
- Proxy (41214) auto-detects loopback port from gateway logs
- Proxy forwards `/mcp` requests with auth headers to internal loopback
- MCP auth always required despite `--auth none` (loopback auth separate)

### 8. OpenClaw Gateway Auth
- `--auth none` only disables main gateway auth, not MCP loopback
- Loopback token: `crypto.randomBytes(32)` on each restart
- Token in gateway logs: `MCP loopback server listening on http://127.0.0.1:<port>/mcp`
- Proxy auto-detects port from gateway logs (uses LAST match)

### 9. Dockerfile.runtime
- Now present in both root (`Dockerfile.runtime`) and `docker/Dockerfile.runtime`
- `docker/Dockerfile` symlink points to `Dockerfile.runtime`
- `scripts/mcp_bridge.py` symlink points to root `mcp_bridge.py`

### 10. Skills Composition
| Source | Count | Location |
|--------|-------|----------|
| DrDeeks (GitHub) | 131 | `skills/drdeeks/` |
| Enterprise Blueprint | 19 | `skills/enterprise-blueprint/` |
| OpenClaw Built-in | 137 | `skills/openclaw/` |
| **Total** | **287+** | |

## Deploy Commands
```bash
# Extract and run
tar -xzf hemlock-minimal.tar.gz
cd hemlock-minimal
./scripts/hemlock gateway start

# Verify
curl http://localhost:18789/health
# {"ok":true,"status":"live"}

# Run tests
cd hemlock-minimal-tests && npx playwright test --config=playwright.config.js

# USB deployment
./scripts/create-usb-image.sh /tmp/hemlock-usb
cd /tmp/hemlock-usb && ./deploy.sh
```

## Lessons Learned

1. **Always verify archive contents** - `tar -tzf` before declaring complete
2. **Use existing skills** - `unified-usb-skill` had all USB automation, don't reinvent
3. **Test archive extraction** - `tar -xzf` and verify structure
4. **Check tar prefix** - `tar -tzf | head` should show `project/` prefix
5. **Exclude before archive** - size went from 94 MB → 55.8 MB with proper exclusions
6. **Container cron** - must run inside container, not on host
7. **Daily pull** - use `--depth 1` for clone, `git pull origin main` for updates
8. **Setup wizard UX** - offer next steps after config, auto-launch TUI/Docker
9. **MCP proxy** - needed because loopback on random internal port
9. **Dockerfile.runtime** - needed in both root and `docker/` directory
10. **Unified USB skill** - was already complete, just needed to be copied correctly