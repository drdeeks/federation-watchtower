---
name: portable-usb-manager
description: "Comprehensive USB-first portable Linux management. Handles detection, mounting, partitioning, formatting, Ventoy multi-boot setup with persistence, mkusb live/persistent creation, hidden device recovery, chroot install into the persistence volume, boot mode selection (headless SSH or full GUI via QEMU), per-device profile manifests with autoboot, USB-resident profile store with default selection, restart-on-CRUD volume orchestration for agent harnesses, in-persistence essentials installer that mirrors the host dev toolchain (build/edit/net/python/node/crypto/web3/docker/cloud groups with rust/go/ai as opt-in), enhanced bash profile + alias manager, sudo cache + triple-notification consent policy, permission normalization that never uses 0700, cross-OS detection (Linux/macOS/WSL2/Windows), and full plumbing for chroot/QEMU/SSH/Tailscale access. Use for any USB drive whose intent is portable compute rather than file storage."
version: 2.0.9
license: MIT
metadata:
  category: portable-compute
  complexity: enterprise
  tags:
    - usb drive management
    - portable linux usb
    - ventoy persistence setup
    - bootable usb creation
    - usb automount configuration
    - chroot into usb persistence
    - usb compute platform
---

# Portable USB Manager — One Skill for Portable-Compute USB Drives

Consolidates `usb-manager` + `unified-usb-skill` + `portable-linux-usb` into a
single robust skill. Distilled from production work on the USB-Hemlock
unified compute platform — every pattern below has been built, tested, and
hardened in that codebase (CL-001 through CL-024).

## When to Use

- Provisioning a fresh USB into a Ventoy multi-boot + persistence drive
- Installing/refreshing the dev toolchain inside the persistence volume
- Booting the persistence headless (SSH + QEMU port-forward) or with full GUI
- Managing per-device profiles with autoboot and primary/data volumes
- Setting up the enhanced bash profile + alias manager on the host
- Provisioning agent containers (Hemlock, etc.) that mount data from the USB
- Recovering hidden / unrecognized / improperly-formatted USB devices
- Cross-OS work where the same USB needs to boot on Linux/macOS/WSL2

## Architecture Snapshot

```
HOST ── lsblk/udev/blkid auto-detect ─► USB device
                                          │
                                          ├─ Ventoy ESP   (FAT/exFAT) — ISOs + boot config
                                          └─ persistence file  (ext4, loop-mountable)
                                                │
                                                ├─ /etc/rc.local         (autostart hook)
                                                ├─ /opt/<tooling>        (chroot-installed)
                                                ├─ /home/<user>          (profile state)
                                                └─ /data/<profile>       (per-profile volumes)
```

## Core Scripts

Quick map (every entry is also documented below with usage):

| Path | Purpose |
|------|---------|
| `scripts/usb-manager.sh` | Main CLI — analyze/recover/ventoy/mkusb/clone/images/docker-on-USB (flag-based) |
| `scripts/setup.py` | Ventoy + persistence provisioner (idempotent) |
| `scripts/pipeline.py` | Workflow orchestrator (chained stages with JSON status) |
| `scripts/agent-manager.py` | Per-agent workspace ops on USB persistence |
| `scripts/usb_state_manager.py` | Cross-run state tracking (uuid, mount, profile, sudo) |
| `scripts/setup-essentials-enhanced.sh` | In-persistence dev toolchain installer (chroot) |
| `scripts/validate.py` | USB validator + auto-fixer (--fix repairs drift) |
| `scripts/deploy-usb-system.sh` | Deploy the full USB system payload (TUI + libs + automount + tests) to any directory |
| `scripts/fetch-ventoy.sh` | Fetch the Ventoy release tarball on demand (not bundled); `--version`, `--dest`, `--force`, `--dry-run` |

## The USB System Payload (complete, standalone)

`references/templates/usb-system/` carries the entire USB management system, ready to deploy anywhere via `scripts/deploy-usb-system.sh --target <dir>`:

- `menu.sh` — the interactive TUI orchestrator (USB-first, error-resilient dispatch, multi-volume persistence, startup wizard, SIGINT confirm-exit)
- `usb/lib/` — 7 library modules (logging, core, menu rendering, config, validation, usb ops, platform detection)
- `usb/cli/usbctl` — non-interactive CLI
- `usb/usb-setup-assistant.sh` + `usb/sysman.sh` — guided setup and system manager
- `usb/usb-automount/` — udev rules + systemd unit + mount scripts (self-consistent set; the setup script expects its siblings)
- `usb/tests/` — 8-stage test suite; `usb/volumes/ventoy/` — persistence profiles; `usb/env.example` — string-enum config overrides
- `usb/hemlock-tui` — Hemlock TUI wrapper (graceful error when no runtime present)

### Hemlock integration — hidden by default, opt-in by flag

The deployed system is designed for ANY system, ANYWHERE, with zero Hemlock dependency. Hemlock surfaces only when BOTH are true:

1. the operator passes `-H`/`--hemlock` (or exports `HEMLOCK_ENABLED=true`) — a stored profile can NEVER silently enable it
2. a hemlock-runtime is found (sibling-directory auto-detection or explicit `HEMLOCK_DIR`)

Without the flag, no Hemlock option appears anywhere in the TUI. With the flag but no runtime, the wrapper explains exactly what to set. Nothing in this skill modifies a Hemlock installation — access is read/launch only.

### `scripts/usb-manager.sh` — main CLI (flag-based)
```bash
# Device analysis + recovery
bash scripts/usb-manager.sh --analyze <device>   # deep device analysis
bash scripts/usb-manager.sh --scan-hidden        # find hidden/unrecognized devices
bash scripts/usb-manager.sh --recover            # recover an improperly-formatted device
# Ventoy lifecycle
bash scripts/usb-manager.sh --ventoy-setup       # install Ventoy (interactive device pick)
bash scripts/usb-manager.sh --ventoy-list        # list ISOs on the Ventoy partition
bash scripts/usb-manager.sh --ventoy-persist     # persistence manager
# mkusb alternative
bash scripts/usb-manager.sh --mkusb-live         # live USB via mkusb
bash scripts/usb-manager.sh --mkusb-persistent   # persistent USB via mkusb
# Cloning + disk images
bash scripts/usb-manager.sh --clone              # clone a device
bash scripts/usb-manager.sh --image-create <mnt> # create a disk image
bash scripts/usb-manager.sh --image-mount <img>  # loop-mount an image
# Docker-on-USB
bash scripts/usb-manager.sh --docker-setup <mnt> # docker rooted on the USB
bash scripts/usb-manager.sh --docker-volume <mnt>
bash scripts/usb-manager.sh --docker-full-backup <mnt>
```

Interactive any-USB detection (lsblk TRAN + udev + classification of
ventoy/formatted/blank, root-disk excluded, HOST-mode fallback when nothing
is plugged in) lives in the payload TUI — `references/templates/usb-system/menu.sh`
(`_detect_all_usb_devices` / `_classify_usb_device` / `_select_uca_mode`).

### `scripts/setup.py` — Ventoy + persistence provisioner
Idempotent provisioner. Writes a manifest at `<mount>/.usb-manager.json` so
subsequent runs can audit what was provisioned and skip done steps.

### `scripts/pipeline.py` — workflow orchestrator
Composable pipeline runner. Chains detect → mount → install → enable services
→ validate. Stages emit JSON status; failures stop the chain unless `--continue-on-error`.

### `scripts/agent-manager.py` — agent workspace ops on USB
Manages per-agent workspaces ON the USB persistence (not on host). Per CL-018
the workspace layout is strict — see `references/agent-isolation.md`.

### `scripts/usb_state_manager.py` — state tracking
Tracks USB state across runs (device UUID, last mount, profile applied, last
install, sudo policy). Stored at `~/.config/usb-compute-automation/state.json`
with chmod 600 on secrets.

### `scripts/setup-essentials-enhanced.sh` — in-persistence dev toolchain
Mirrors the host toolchain inside the chroot. Groups (recommended default):
`core / editors / net / ssh / python / crypto / web3 / docker / cloud`.
Opt-in: `rust / go / ai / extras / llmrl`. Auto-bumps installed receipt on each
run. Never modifies the host — only chroots into the persistence and runs apt.

### `scripts/validate.py` — USB validator
Validates the USB structure: Ventoy installed, persistence file integrity,
manifest sanity, mount-path resolution, profile autoboot consistency, basic
firmware/SMART check. Read-only by default; `--fix` repairs common drift
(missing dirs, wrong perms, stale state.json entries).

## Lessons Baked In (from CL-001 → CL-024)

Field lessons recovered from the ancestor skills live in `references/lessons/`:
[err-trap-kills-script](references/lessons/err-trap-kills-script.md),
[set-e-silent-crashes](references/lessons/set-e-silent-crashes.md),
[exit-code-capture](references/lessons/exit-code-capture.md),
[interactive-prompts](references/lessons/interactive-prompts.md),
[hardcoded-paths](references/lessons/hardcoded-paths.md),
[mounted-partitions-block](references/lessons/mounted-partitions-block.md),
[ventoy-invalid-flag](references/lessons/ventoy-invalid-flag.md).

| Pattern | Why | Where applied |
|---|---|---|
| Path resolver pattern (`_uca_primary_persistence`) | Never hardcode `ubuntu-persistence.dat` — auto-discover the active primary | `usb-manager.sh detect`, `pipeline.py` |
| Profile manifest with autoboot | One USB, many configs, one auto-selected default | `references/state-management.md` |
| Restart-on-CRUD volume orchestration | Containerized agents/crews live in docker named volumes; CRUD restarts the container instead of bind-mounting host | `references/container-integration.md` |
| Sudo cache + triple-notification consent | First-run policy: encrypted-at-rest (libsecret) / session keepalive / no-cache | `references/error-handling.md` |
| Permission normalization (NEVER 0700) | After initial setup, no menu action needs sudo because perms are sane | `validate.py --fix`, `setup.py` |
| In-persistence chroot install | Host stays clean; toolchain goes inside the .dat | `setup-essentials-enhanced.sh` |
| Auto-detect USB device + mount | 5-method detection (lsblk, udev, blkid, /proc/mounts, ventoy-marker) | `usb-manager.sh detect` |
| USB-first install policy | Default target is the persistence; host install requires explicit override + reason | `pipeline.py`, all installers |
| Cross-OS detection | Same scripts work on Linux/macOS/WSL2 with platform.sh stub | `references/cross-os-guide.md` |
| Headless boot + SSH port-forward | QEMU + hostfwd:2222 → 22 for SSH-into-persistence | `references/boot-guide.md` |

## Streamlined TUI

Every interactive flow follows this contract (production-hardened):

1. State header at top of every screen (device, mount, persistence size, env)
2. Numbered options with target labels: `[USB]` / `[HOST]` / `[USB+HOST]` / `[CONTAINER]`
3. Errors NEVER abort the loop — they print the failure + return to the menu
4. `DRY_RUN=true` previewed before any mutation
5. `--text` falls back from whiptail when TTY isn't available
6. Sudo cached via triple-notification consent (only when an action genuinely needs it)
7. Submenus return to the parent screen, never drop to bash

## Cross-OS Behavior

| OS | Detection | Mount path | Notes |
|----|-----------|------------|-------|
| Linux (deb/rpm) | lsblk + udevadm | `/media/$USER/<label>` | Primary target |
| macOS | diskutil list | `/Volumes/<label>` | LaunchAgent for autostart |
| WSL2 | wmic + powershell | `/mnt/<drive>` | systemd-genie for services |
| Windows | wmic | Drive letters | PowerShell stubs only |

## Provider/Hardware Compatibility

| Layer | Compatibility |
|---|---|
| USB controllers | USB 2.0/3.0/3.1/3.2/4 — auto-detected via /sys/bus/usb |
| Filesystems | ext4 (default), exfat, vfat, ntfs (mount only) |
| Boot loaders | Ventoy (recommended), syslinux, grub, isolinux |
| Hypervisors | QEMU/KVM (Linux), QEMU (macOS), Hyper-V (WSL2) |
| Init systems | systemd, OpenRC, runit (limited) |
| Container runtimes | Docker, Podman, containerd (read-only) |

## Free-First Strategy

Tier 0 ($0/mo): Python stdlib + bash + standard system utilities only.
No paid services, no API calls, no telemetry. Every script in this skill
runs without an internet connection except for explicit network ops
(installer apt-get, git pull, ISO download).

## References

- [ventoy-setup.md](references/ventoy-setup.md) — Ventoy install + ventoy.json + persistence
- [mkusb-guide.md](references/mkusb-guide.md) — Alternative to Ventoy
- [filesystem-guide.md](references/filesystem-guide.md) — ext4/exfat/vfat/ntfs choices
- [boot-guide.md](references/boot-guide.md) — Headless SSH + QEMU GUI + ISO direct
- [hidden-usb.md](references/hidden-usb.md) — Recovering unrecognized drives
- [docker-usb.md](references/docker-usb.md) — Docker on USB persistence
- [gui-terminal.md](references/gui-terminal.md) — Drop-down terminals on the persistence
- [chroot-persistence-access.md](references/chroot-persistence-access.md) — chroot lifecycle
- [container-integration.md](references/container-integration.md) — Restart-on-CRUD pattern
- [agent-isolation.md](references/agent-isolation.md) — Lean per-agent layout (CL-018)
- [alias-system.md](references/alias-system.md) — Host + USB-resident alias managers
- [backup-restore.md](references/backup-restore.md) — 3-tier export (minimal/standard/full)
- [persistence-package-install.md](references/persistence-package-install.md) — chroot apt
- [cross-os-guide.md](references/cross-os-guide.md) — Linux/macOS/WSL2/Windows
- [error-handling.md](references/error-handling.md) — Sudo consent + permission normalize
- [free-first-strategy.md](references/free-first-strategy.md) — $0 toolchain
- [hemlock-integration.md](references/hemlock-integration.md) — Optional Hemlock layer
- [usb-creation-guide.md](references/usb-creation-guide.md) — End-to-end provisioning
- [usb-location-safety.md](references/usb-location-safety.md) — Path-safety guarantees
- [state-management.md](references/state-management.md) — State JSON + profile manifests
- [automount-architecture.md](references/automount-architecture.md) — udev + systemd
- [workflow-guide.md](references/workflow-guide.md) — Pipeline composition
- [wsl2-optimization.md](references/wsl2-optimization.md) — Windows-host specifics
- [bash-script-best-practices.md](references/bash-script-best-practices.md) — Style guide
- [bash-enhanced-troubleshooting.md](references/bash-enhanced-troubleshooting.md) — Common pitfalls
- [complete-system-integration.md](references/complete-system-integration.md) — Full stack
- [phase-7-8-9-integration.md](references/phase-7-8-9-integration.md) — Multi-phase workflows
- [popout-terminal-launch.md](references/popout-terminal-launch.md) — Detached terminals
- [testing-framework.md](references/testing-framework.md) — Test harness
- [universal-portable-shell-utilities.md](references/universal-portable-shell-utilities.md) — Lib helpers
- [skill-updates-summary.md](references/skill-updates-summary.md) — Version history
