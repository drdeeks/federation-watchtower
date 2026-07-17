# Skill Updates Summary - Session 2024-06-14

## Overview

This session significantly enhanced the Unified USB Skill with deep Hemlock Agent Orchestration integration and container-native model management.

## Major Updates

### 1. Hemlock Agent Orchestration Integration

**Reference**: `references/hemlock-integration.md` (NEW)

- **Container-native architecture**: Host deploys, container manages all agent/skill/MCP/model operations
- **157+ skills** in read-only shared volume
- **OpenClaw Gateway + Hermes MCP Bridge** with MCP stdio bridge
- **Agent workspaces** as isolated Docker volumes (hemlock-agent-{alpha,beta,gamma})
- **Gateway** on port 18789, **MCP Proxy** on 41214
- **Compute resource ports**: 8080 (llama-server), 11434 (Ollama), 8888 (Jupyter), 8000/5000/3000 (custom)

### 2. Hardware-Aware llama.cpp Build

**Dockerfile.runtime** updates:
- Auto-detects: NVIDIA CUDA, Apple Metal, AMD HIPBLAS/ROCm, Intel OpenCL/SYCL, Vulkan
- Builds with all backends enabled; cmake selects at runtime
- Binaries at `/usr/local/bin/` (llama-server, llama-cli, llama-quantize, etc.)

```dockerfile
cmake .. -DLLAMA_CUDA=ON -DLLAMA_METAL=ON -DLLAMA_HIPBLAS=ON \
         -DLLAMA_BLAS=ON -DLLAMA_OPENCL=ON -DLLAMA_VULKAN=ON
```

### 3. Model Management Inside Container

**New script**: `/scripts/model-manager.sh` (1,200+ lines)

| Command | Description |
|---|---|
| `model-manager.sh list` | List models with metadata |
| `model-manager.sh download` | Download from HF with quant selection |
| `model-manager.sh load` | Load model (auto-ejects current) |
| `model-manager.sh unload` | Graceful unload (SIGTERM + timeout) |
| `model-manager.sh handoff` | Efficient swap: preload → signal → swap |
| `model-manager.sh quantize` | Quantize GGUF |
| `model-manager.sh monitor` | Live VRAM/RAM/GPU monitor |
| `model-manager.sh optimize` | Quantize/split/convert/prune/benchmark |
| `model-manager.sh mcp_register` | Register model as MCP tool |

**Host CLI delegates to container**:
```bash
hemlock model-list
hemlock model-load
hemlock model-handoff
hemlock model-mcp llama-model
```

### 4. Model Policy

- **Singleton**: Only one model loaded at a time (`MODEL_SINGLETON=true`)
- **Graceful Handoff**: Pre-load next → SIGUSR1 wind-down → swap
- **Resource Monitor**: Live VRAM/RAM/GPU tracking
- **Auto-scan**: Detects models on startup

### 5. Auto-Start Services

**Linux (systemd)**:
- `hemlock-gateway.service` - Container with Restart=always
- `hemlock-usb-detect.service` - Monitors Ventoy USB via blkid every 10s
  - Detects Ventoy USB
  - Ensures gateway running
  - Auto-attaches agents (alpha, beta, gamma)
  - Starts QEMU VM headless if USB present

**macOS (LaunchAgent)**:
- `com.hemlock.gateway.plist` - KeepAlive, RunAtLoad, RestartInterval=10

### 6. Cross-Platform Tool Selection

**New in usb-setup-assistant.sh**:
```bash
select_best_tool() {
    # Auto-detects best tool per category per OS
    # Categories: terminal_emulator, virtualization, container_runtime, usb_imager, network_tool, editor
}

select_tool_interactive() {
    # Shows available tools, lets user choose or auto-select
}
```

**Priority by platform**:
| Category | Linux | macOS | WSL2 |
|---|---|---|---|
| Terminal | gnome-terminal/konsole/terminator | Terminal.app/Alacritty | Windows Terminal/wt.exe |
| Virtualization | QEMU/KVM/VirtualBox | UTM/VMware Fusion | Hyper-V/WSL2 |
| Container | Docker/Podman | Docker/Podman | Docker Engine |

### 7. WSL2 Optimizations

**Reference**: `references/wsl2-optimization.md` (NEW)

- usbipd for USB passthrough
- systemd=true in /etc/wsl.conf
- Native Docker Engine (no Desktop needed)
- usbipd attach --wsl --busid <BUSID>
- GPU passthrough for llama.cpp CUDA

### 8. USB Location Safety Check

**Reference**: `references/usb-location-safety.md` (NEW)

**Mandatory first operation** in `initialize()`:
```bash
check_script_location() {
    # Detects if script runs from USB mount points
    # Blocks execution with clear copy-to-host instructions
    # Must run from HOST, not USB
}
```

### 9. Popout Terminal Launch

**Reference**: `references/popout-terminal-launch.md` (NEW)

Auto-detects terminal: gnome-terminal, konsole, xterm, terminator, alacritty, kitty, wezterm, tmux, wt.exe, macOS Terminal.app (osascript)

### 10. Chroot Persistence Access

**Reference**: `references/chroot-persistence-access.md` (NEW)

Direct terminal access to USB persistence via chroot (Option 11 in USB Setup Assistant)

### 11. Persistence Package Install

**Reference**: `references/persistence-package-install.md` (NEW)

Install build tools, dev environments, llama.cpp, Ollama, agent harnesses DIRECTLY into USB persistence via chroot.

## Files Modified

| File | Changes |
|---|---|
| `usb-setup-assistant.sh` | +2,100 lines: Hemlock integration, tool selection, WSL2 support, auto-start services, Hemlock TUI popout, container-native architecture |
| `Dockerfile.runtime` | +30 lines: llama.cpp hardware-aware build, model-manager.sh copy |
| `scripts/hemlock` | +50 lines: model-* commands delegating to container |
| `scripts/model-manager.sh` | NEW (1,200 lines): Full model management inside container |
| `scripts/hemlock-tui` | Existing (21K lines): Interactive TUI |

## New References Added

1. `references/hemlock-integration.md` - Complete Hemlock integration guide
2. `references/wsl2-optimization.md` - WSL2-specific optimizations
3. `references/usb-location-safety.md` - Mandatory USB location check
4. `references/popout-terminal-launch.md` - Multi-platform terminal launcher
5. `references/chroot-persistence-access.md` - Chroot access to USB persistence
6. `references/persistence-package-install.md` - Install tools into USB persistence

## Backward Compatibility

- All existing USB management features preserved
- Ventoy, mkusb, persistence, automount unchanged
- Agent isolation, backup/restore, aliases, SSH hosts unchanged
- New features additive only

## Testing

```bash
# Syntax validation
bash -n usb-setup-assistant.sh
bash -n scripts/hemlock
bash -n scripts/model-manager.sh
bash -n Dockerfile.runtime

# All pass
```