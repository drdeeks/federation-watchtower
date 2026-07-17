# Hemlock Minimal Deployment Package

## Overview
Complete self-contained deployment package for Hemlock Minimal - a single-container OpenClaw Gateway + Hermes MCP runtime with USB deployment support.

## Package Contents

```
hemlock-minimal/
├── docker-compose.yml          # Container orchestration
├── Dockerfile.runtime          # Base runtime image (multi-stage)
├── entrypoint.sh               # Container PID 1 + initialization
├── mcp_bridge.py               # Hermes MCP bridge server (stdio)
├── .gitignore                  # Enterprise exclusions (150+ patterns)
├── README.md                   # Documentation
├── CHANGELOG.md                # Append-only history
├── TODO.md                     # Phase-based tasks with validation timestamps
├── blueprint/                  # Project blueprints
├── scripts/                    # 20+ management scripts
│   ├── hemlock                 # Main CLI (agent/crew lifecycle, gateway, doctor)
│   ├── hemlock-tui             # Interactive TUI (full management console)
│   ├── mcp_proxy_manager.py    # Self-healing MCP proxy (systemd)
│   ├── pull-drdeeks-daily.sh   # Daily skills git pull (cron)
│   ├── container-init.sh       # Container startup (cron setup)
│   ├── create-usb-image.sh     # Ventoy USB creation
│   ├── deploy.sh               # One-command USB deploy
│   ├── usb_safe_startup.sh     # USB disconnect handling
│   ├── runtime.sh              # TUI/entrypoint wrapper
│   ├── mcp_bridge.py (symlink) # Alias for scripts/mcp_bridge.py
│   └── mcp_proxy_manager.py    # MCP proxy manager
├── docker/                     # Build contexts
│   ├── Dockerfile.runtime      # Multi-stage runtime build
│   └── Dockerfile (symlink)    # Alias for Dockerfile.runtime
├── skills/                     # 180+ skills
│   ├── drdeeks/                # 131 skills cloned from github.com/drdeeks/skills
│   ├── enterprise-blueprint/   # Enterprise standards skill
│   └── openclaw/               # 137 OpenClaw built-in skills
├── blueprint/                  # Project blueprints
│   ├── blueprint.md
│   ├── checklist.md
│   ├── project.json
├── tests/                      # Playwright test suite
│   ├── health.spec.ts          # Gateway health tests (9 tests)
│   ├── gateway.spec.ts         # Gateway endpoint tests (6 tests)
│   ├── minimal.spec.ts         # Basic test (3 tests)
│   └── playwright.config.js    # Multi-browser config
├── docker/                     # OpenClaw runtime (embedded)
│   ├── hermes-agent/           # Hermes agent source
│   └── openclaw-runtime/       # OpenClaw gateway runtime
└── .hermes/                    # Hermes skills registry
    └── skills/                 # 350+ additional skills
```

## Key Scripts

| Script | Purpose | Critical |
|--------|---------|----------|
| `hemlock` | Main CLI: agent/crew lifecycle, gateway, doctor | ✅ |
| `hemlock-tui` | Interactive TUI (full management) | ✅ |
| `mcp_proxy_manager.py` | Self-healing MCP proxy (systemd) | ✅ |
| `pull-drdeeks-daily.sh` | Daily skills git pull (cron) | ✅ |
| `container-init.sh` | Container startup (cron setup) | ✅ |
| `create-usb-image.sh` | Ventoy USB creation | ✅ |
| `deploy.sh` | One-command USB deploy | ✅ |
| `usb_safe_startup.sh` | USB disconnect handling | ✅ |
| `runtime.sh` | TUI/entrypoint wrapper | ✅ |
| `entrypoint.sh` | Container PID 1 + init | ✅ |

## Skills Included

| Source | Count | Location |
|--------|-------|----------|
| DrDeeks (cloned from GitHub) | 131 | `skills/drdeeks/` |
| OpenClaw Built-in | 137 | `skills/openclaw/` |
| Enterprise Blueprint | 19 | `skills/enterprise-blueprint/` |
| Blueprints | 4 | `blueprint/` |
| .hermes/skills | 350+ | `.hermes/skills/` |

## Core Architecture

```
OpenClaw Gateway (PID 1, port 18789)
    ├── Channel Adapters: Telegram, iMessage (via SSH)
    ├── MCP Provider: spawns stdio servers
            ↓
Hermes Agent Runtime (Cognition Plane)
    ├── AIAgent Loop, Memory, Tools
    └── MCP Server (stdio) → mcp_bridge.py
            ↓
Agent Volumes (Isolation Plane)
    ├── hemlock-agent-<id>/
    ├── hemlock-crew-<name>/
    └── hemlock-shared-skills/ → /skills (read-only)
```

## Docker Compose

```yaml
version: '3.8'
services:
  hemlock-gateway:
    image: hemlock/runtime:latest
    container_name: hemlock-runtime
    restart: "no"
    command:
      - /opt/openclaw/bin/openclaw-container
      - gateway
      - run
      - --allow-unconfigured
      - --auth
      - none
      - --token
      - test-token-12345
      - --port
      - "18789"
      - --bind
      - lan
    ports:
      - "18789:18789"
    volumes:
      - hemlock-gateway:/workspace/gateway
      - hemlock-agents:/agents
      - hemlock-crews:/crews
      - hemlock-projects:/projects
      - hemlock-config:/config
      - hemlock-logs:/logs
      - hemlock-memory:/memory
      - hemlock-backups:/backups
      - hemlock-plugins:/plugins
      - hemlock-models:/models
    environment:
      - OPENCLAW_GATEWAY_TOKEN=***
      - IMRSG_REMOTE_HOST=${IMRSG_REMOTE_HOST}
      - SSH_AUTH_SOCK=***
    healthcheck:
      test: ["CMD", "bash", "-c", "timeout 5 bash -c '</dev/tcp/localhost/18789'"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s

volumes:
  hemlock-gateway:
    external: true
  hemlock-agents:
    external: true
  hemlock-crews:
    external: true
  hemlock-shared-skills:
    external: true
  hemlock-projects:
    external: true
  hemlock-config:
    external: true
  hemlock-logs:
    external: true
  hemlock-memory:
    external: true
  hemlock-backups:
    external: true
  hemlock-plugins:
    external: true
  hemlock-models:
    external: true
```

## Key Features

### 1. Self-Healing MCP Proxy
- Auto-detects internal loopback port from gateway logs
- Forwards external `/mcp` requests to internal loopback
- Systemd service with auto-restart on failure
- Health endpoint at `/mcp/health`

### 2. Daily Skills Auto-Pull
- Cron job at 2 AM inside container
- Clones/clones from `github.com/drdeeks/skills`
- Persists to `hemlock-shared-skills` volume

### 3. Setup Wizard → TUI/Docker Integration
- After `hermes setup`, offers to launch TUI, start Docker, or both
- Auto-detects Docker availability
- Seamless transition from config to operation

### 4. Ventoy USB Deployment
- Complete USB package with `create-usb-image.sh`
- One-command deploy with `deploy.sh`
- Persistence support via Ventoy

### 5. Enterprise Standards
- Full enterprise-organization compliance
- 150+ .gitignore patterns
- Todo-driven with validation timestamps
- Zero-placeholder policy
- CHANGELOG with rationale

## Deployment

### Local
```bash
tar -xzf hemlock-minimal.tar.gz
cd hemlock-minimal
./scripts/hemlock gateway start
curl http://localhost:18789/health
```

### USB
```bash
# Create
./scripts/create-usb-image.sh /media/usb/hemlock-deploy

# Deploy on target
cd /media/usb/hemlock-deploy && sudo ./deploy.sh
```

### Tests
```bash
cd tests
npx playwright test --config=playwright.config.js
# 18/18 tests pass
```

## Exclusions (Not in Archive)

| Category | Reason |
|----------|--------|
| `.git` | History not needed for deployment |
| `node_modules` (non-playwright) | Rebuilt on target |
| `scripts/scripts` | Legacy nested directory |
| `*.pyc`, `*.log`, `*.tar.gz` | Build artifacts |
| `.pytest_cache`, `__pycache__` | Cache |
| `tests/node_modules` | Excluded |
| `tests/playwright-report` | Report artifacts |

## Package Stats

| Metric | Value |
|--------|-------|
| Size | 60.2 MB |
| Entries | 2,626 |
| Skills | 300+ |
| Scripts | 22 |
| Tests | 12 files, 18 passing |

## Validation

```bash
# Verify archive
tar -tzf hemlock-minimal.tar.gz | head -20

# Check key files
tar -tzf hemlock-minimal.tar.gz | grep -E "(docker-compose|Dockerfile|entrypoint|hemlock|mcp_)"

# Check skills
tar -tzf hemlock-minimal.tar.gz | grep -c "skills/drdeeks/.*\.skill$"
```