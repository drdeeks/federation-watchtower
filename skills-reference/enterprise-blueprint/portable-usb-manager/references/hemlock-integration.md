# Hemlock Agent Orchestration Integration

## Overview

The Hemlock Agent Orchestration Platform provides a complete agent orchestration system with OpenClaw Gateway + Hermes MCP Brain. It delivers:

- **OpenClaw Gateway**: Multi-channel messaging (Telegram, iMessage) with agent routing
- **Hermes MCP Bridge**: Stdio-based MCP server for agent cognition
- **Agent Workspaces**: Isolated Docker volumes per agent/crew with persistent storage
- **Skills System**: 157+ skills in read-only shared volume
- **TUI/CLI Management**: Interactive TUI (`hemlock-tui`) and Host CLI (`hemlock`)

## Architecture: Container-Native Management

**Core Principle**: Host deploys, Container manages.

| Layer | Responsibility |
|-------|---------------|
| **Host** | USB prep (Ventoy + persistence), VM auto-boot, Docker deployment, auto-start services |
| **Container** | All model/agent/skill/MCP/plugin management via TUI/CLI |

The host setup script (`usb-setup-assistant.sh`) only:
1. Prepares USB (Ventoy + persistence)
2. Configures VM auto-boot + SSH
3. Deploys Hemlock container with volumes & port forwarding
4. Sets up auto-start services (systemd/LaunchAgent)

**All management runs INSIDE the container**:
- Model management: `hemlock model-*` (delegates to `/scripts/model-manager.sh`)
- Agent/crew management: `hemlock agent-*`, `hemlock crew-*`
- Skills: `hemlock populate-skills`
- TUI: `hemlock tui` (attaches to container's `/scripts/hemlock-tui`)

## Deployment via USB Setup Assistant

The USB Setup Assistant (Option 13) provides:

```
  1) Launch TUI in NEW terminal window (popout)
  2) Launch TUI in CURRENT terminal
  3) Run Hemlock CLI command
  4) Show Hemlock status (doctor)
  5) Attach to RUNNING CONTAINER (Hemlock TUI/CLI inside container)
     → All model/agent/skill/MCP/plugin management happens HERE
```

**Popout Terminal**: Auto-detects terminal emulator (gnome-terminal, konsole, terminator, alacritty, kitty, wezterm, xterm, tmux, wt.exe, macOS Terminal.app via osascript).

## Container Configuration

### Volumes

| Volume | Mount | Purpose |
|--------|-------|---------|
| `hemlock-gateway` | `/workspace/gateway` | Gateway config, token |
| `hemlock-agents` | `/agents` | Agent workspaces (alpha, beta, gamma) |
| `hemlock-crews` | `/crews` | Crew configs |
| `hemlock-shared-skills` | `/skills` (ro) | 157 skills |
| **`hemlock-models`** | **`/models`** | **GGUF models, cache, KV cache** |

### Port Forwarding (Compute Resources)

```
CONTAINER_COMPUTE_PORTS=(
    "8888:8888"   # Jupyter
    "8080:8080"   # llama-server API
    "11434:11434" # Ollama API
    "8000:8000"   # Custom APIs
    "5000:5000"   # Flask/FastAPI
    "3000:3000"   # Node.js apps
)
```

Plus Gateway (18789) and MCP Proxy (41214).

### Container Isolation

```bash
--security-opt=no-new-privileges:true
--cap-drop=ALL
--cap-add=CAP_DAC_OVERRIDE    # For persistence access
--cap-add=CAP_SYS_RESOURCE    # For resource limits
--pids-limit=1000
--memory=4g
--cpus=2
```

## Model Management (Inside Container)

### Hardware-Aware llama.cpp Build

The Docker image builds llama.cpp with auto-detection:

```bash
# Auto-detection in Dockerfile:
- NVIDIA GPU → CUDA
- Apple Silicon → Metal
- AMD GPU → HIPBLAS/ROCm
- Intel GPU → OpenCL/SYCL
- CPU fallback → BLAS

# All backends enabled, cmake selects at runtime
cmake .. -DLLAMA_CUDA=ON -DLLAMA_METAL=ON -DLLAMA_HIPBLAS=ON \
         -DLLAMA_BLAS=ON -DLLAMA_OPENCL=ON -DLLAMA_VULKAN=ON
```

Binaries at `/usr/local/bin/` (llama-server, llama-cli, llama-quantize, etc.)

### Model Management Commands (via hemlock CLI)

```bash
hemlock model-list       # List models with metadata
hemlock model-download   # Download from HF (TheBloke, bartowski, etc.)
hemlock model-load       # Load model (auto-ejects current)
hemlock model-unload     # Unload current (graceful SIGTERM)
hemlock model-handoff    # Efficient swap: preload → signal → swap
hemlock model-quantize   # Quantize GGUF (Q4_K_M, etc.)
hemlock model-monitor    # Live VRAM/RAM/GPU monitor
hemlock model-optimize   # Quantize/split/convert/prune/benchmark
hemlock model-mcp llama-model  # Register as MCP tool
```

### Model Policy

- **Singleton**: Only one model loaded at a time (`MODEL_SINGLETON=true`)
- **Graceful Handoff**: Pre-load next → SIGUSR1 wind-down → swap
- **Resource Monitor**: Live VRAM/RAM/GPU tracking
- **Auto-scan**: Detects models on startup

### Model Storage

| Path | Purpose |
|------|---------|
| `/models/` | GGUF models (persistent volume) |
| `/models/cache/` | KV cache, temp files |
| `/models/alpha-home.dat` | Agent-isolated model cache (optional) |

## Auto-Start Services

### Linux (systemd)

```ini
# hemlock-gateway.service
[Unit]
Description=Hemlock Agent Orchestration Gateway
After=docker.service network.target
Requires=docker.service
Restart=always
RestartSec=10

[Service]
Type=simple
ExecStart=/entrypoint.sh gateway
Restart=always

[Install]
WantedBy=multi-user.target
```

```ini
# hemlock-usb-detect.service
[Unit]
Description=Hemlock USB Detection and Auto-Start
After=hemlock-gateway.service
Requires=hemlock-gateway.service

[Service]
Type=simple
ExecStart=/scripts/usb-detector.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**usb-detector.sh** monitors Ventoy USB via `blkid` every 10s:
1. Detects Ventoy USB
2. Ensures gateway container running
3. Auto-attaches agents (alpha, beta, gamma)
4. Starts QEMU VM headless if USB present

### macOS (LaunchAgent)

```xml
<!-- com.hemlock.gateway.plist -->
<key>KeepAlive</key>
<dict>
  <key>Crashed</key><true/>
  <key>SuccessfulExit</key><false/>
</dict>
<key>RunAtLoad</key><true/>
<key>RestartInterval</key><integer>10</integer>
```

## Host CLI Model Commands

```bash
hemlock model-list       # List models with metadata
hemlock model-download   # Download from HF (TheBloke, bartowski, etc.)
hemlock model-load       # Load model (auto-ejects current)
hemlock model-unload     # Unload current (graceful SIGTERM)
hemlock model-handoff    # Efficient swap: preload → signal → swap
hemlock model-quantize   # Quantize GGUF (Q4_K_M, etc.)
hemlock model-monitor    # Live VRAM/RAM/GPU monitor
hemlock model-optimize   # Quantize/split/convert/prune/benchmark
hemlock model-mcp llama-model  # Register as MCP tool
```

All delegate to container: `docker exec hemlock-runtime /scripts/model-manager.sh <cmd>`

## MCP Integration

### Gateway Config

`/workspace/gateway/hemlock.json`:
```json
{
  "gateway": { "port": 18789, "mode": "local" },
  "agents": { "list": [{"id": "alpha", "workspace": "/agents/alpha"}] },
  "mcp": {
    "servers": {
      "llama-model": {
        "command": "http",
        "args": ["http://host.docker.internal:8080"]
      }
    }
  }
}
```

### Agent MCP Usage

Agents call llama-server via MCP:
```
Agent → Gateway (stdio) → MCP Server (http://host.docker.internal:8080) → llama-server
```

Register model as MCP tool:
```bash
hemlock model-mcp llama-model
```

## Auto-Start Flow (USB Plug-in → Ready)

```
USB Inserted
    │
    ├─► hemlock-usb-detect.service (systemd) / LaunchAgent (macOS)
    │       │
    │       ├─► Detects Ventoy USB via blkid
    │       │
    │       ├─► Ensures hemlock-gateway container running
    │       │       │
    │       │       └─► Auto-attaches agents (alpha, beta, gamma)
    │       │
    │       └─► Starts QEMU VM headless (SSH 2222)
    │
    └─► User SSH: ssh -p 2222 user@localhost
            │
            ├─► Agents already attached & ready
            ├─► Gateway: http://localhost:18789
            └─► Model management via hemlock model-* or TUI
```

## Persistent Volumes Layout

```
/dev/sdX
├── sdX1  exfat   Ventoy
│   ├── ubuntu-24.04.4-desktop-amd64.iso
│   ├── ventoy/ventoy.json
│   ├── persistence/ubuntu-persistence.dat  (ext4, casper-rw)
│   │   └── /models/                         (bind-mounted from hemlock-models)
│   │       ├── *.gguf                       (downloaded models)
│   │       ├── cache/                       (KV cache)
│   │       └── alpha-home.dat               (agent-isolated)
│   └── agents/                              (agent workspaces)
└── sdX2  vfat    VTOYEFI
```

## Cross-Platform Notes

| Platform | Notes |
|----------|-------|
| **Linux** | Native systemd, KVM, full hardware access |
| **macOS** | LaunchAgent, UTM/QEMU, Metal for llama.cpp |
| **WSL2** | systemd=true in /etc/wsl.conf, usbipd for USB passthrough, native Docker |
| **Windows** | Use WSL2; native Windows support limited |

## Key Scripts

| Script | Purpose |
|--------|---------|
| `/scripts/model-manager.sh` | Model management (list, download, load, unload, handoff, quantize, monitor, optimize) |
| `/scripts/hemlock-tui` | Interactive TUI for agents/crews/skills |
| `/scripts/hemlock` | Host CLI (delegates model-* to container) |
| `/scripts/hemlock` | Host CLI for gateway/agent/crew |
| `/scripts/hemlock-tui` | Attaches to container TUI via `docker exec -it` |
| `/entrypoint.sh` | Container entrypoint (gateway, agent-create, etc.) |
| `/scripts/hemlock` | Container CLI for gateway/agent/crew/mcp |

## Quick Reference

```bash
# Deploy Hemlock
hemlock-minimal/scripts/setup-usb-compute.sh --device /dev/sdX --iso ~/ubuntu.iso --persistence 20G

# From USB Setup Assistant (Option 13)
# → Select 1: Popout TUI
# → Select 5: Attach to container (model/agent/skill management)

# Model management from host
hemlock model-list
hemlock model-download
hemlock model-load
hemlock model-handoff
hemlock model-mcp llama-model

# Or inside container TUI
hemlock tui
# → Navigate to Models section
```