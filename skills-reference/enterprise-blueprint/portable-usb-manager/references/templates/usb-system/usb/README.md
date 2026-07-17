# USB-Hemlock Unified Compute Platform

A portable, enterprise-grade compute environment that boots from any USB drive via Ventoy, provides persistent Linux workspaces with full SSH/alias management and system health monitoring, and seamlessly launches a Dockerized Hemlock agent runtime for AI agent orchestration — all managed through interactive menus with safe, informative steps and dry-run capability at every layer.

---

## Quick Start

```bash
# 1. Launch the master menu (single entry point for everything)
bash menu.sh

# 2. Or use dry-run mode to preview without changes
bash menu.sh --dry-run

# 3. Or run specific components directly
bash usb/usb-setup-assistant.sh       # Interactive USB installer
bash usb/scripts/alias_manager.sh     # Alias CRUD
bash usb/scripts/ssh_host_manager.sh  # SSH host CRUD
bash usb/sysman.sh                    # System health dashboard
bash usb/cli/usbctl validate all      # Run all validations
```

---

## Directory Structure

```
usb-hemlock-split/
├── menu.sh                    # ★ MASTER ENTRY POINT — singular menu for ALL components
├── CHANGELOG.md               # Append-only change log
├── feature-flags.json         # Feature flag registry (29 flags, all disabled by default)
├── blueprint/                 # Enterprise blueprint + enforcement checklist
│   ├── blueprint.md           # 837-line master specification (48/48 ENTERPRISE GRADE)
│   ├── checklist.md           # 8 phases, 21 modules, 897 lines
│   ├── project.json           # Phase registry
│   └── assignments.json       # Agent role assignments
│
├── usb/                       # USB COMPUTE AUTOMATION (38 files)
│   ├── cli/usbctl             # Unified CLI dispatcher
│   ├── lib/                   # Sourceable libraries
│   │   ├── core.sh            # Colors, logging, confirm, run_or_dry, safe_exec, traps
│   │   ├── logging.sh         # Structured logging with file output, rotation, levels
│   │   ├── platform.sh        # OS/virtualization detection, tool selection
│   │   ├── usb.sh             # Ventoy mount/persistence helpers
│   │   ├── config.sh          # JSON config via jq + host-id generation
│   │   ├── menu.sh            # Stack-based menu_loop framework
│   │   └── validation.sh      # Health checks + self_heal
│   ├── scripts/
│   │   ├── alias_manager.sh   # ~/.bash_aliases_usb manager (uses lib/)
│   │   ├── ssh_host_manager.sh # ~/.ssh/hosts_usb manager (self-contained)
│   │   ├── setup-essentials-enhanced.sh  # Build toolchain installer
│   │   ├── setup-usb-compute.sh          # Older standalone provisioning
│   │   ├── bash_enhanced.sh              # Enhanced .bashrc profile
│   │   ├── clean-local.sh                # System cleanup
│   │   └── install-antivirus.sh          # Antivirus installer
│   ├── usb-setup-assistant.sh # 5908-line interactive installer (self-contained)
│   ├── sysman.sh              # System health/repair dashboard
│   ├── hemlock-tui            # Wrapper to launch Hemlock TUI
│   ├── usb-automount/         # systemd + udev auto-mount installer
│   ├── config/initialize.sh   # Ubuntu one-time bootstrap
│   ├── volumes/ventoy/        # Ventoy tarball (fetched on demand, NOT bundled)
│   ├── tests/                 # Testing suite
│   ├── blueprints/PART1-7.md  # Architecture docs
│   ├── docs/                  # Implementation checklist, helpers
│   └── README.md              # This file
│
└── hemlock/                   # HEMLOCK AGENT RUNTIME (51,438 files)
    ├── DEPLOY.sh              # Master deploy (system + USB + Hemlock)
    ├── hemlock-tui            # Wrapper to launch Hemlock TUI
    ├── hemlock-runtime/       # Docker runtime
    │   ├── scripts/hemlock    # Host CLI entrypoint
    │   ├── scripts/runtime.sh # In-container TUI menu
    │   ├── docker-compose.runtime.yml
    │   ├── Dockerfile.runtime
    │   └── Makefile
    ├── hemlock-minimal/
    │   └── skills/            # 84 agent skill packages
    └── README.md              # Runtime documentation
```

---

## The Master Menu (`menu.sh`)

The single entry point for ALL components. Provides access to every USB and Hemlock feature through one interactive interface.

### Launching

```bash
bash menu.sh                     # Interactive menu (whiptail or text fallback)
bash menu.sh --text              # Force text-based menu
bash menu.sh --dry-run           # Preview mode — no mutations
bash menu.sh --log-file PATH     # Custom log file
bash menu.sh --help              # Usage info
```

### Menu Options

| # | Component | Target | Description |
|---|-----------|--------|-------------|
| 1 | USB Setup Assistant | USB | Interactive Ventoy installer (14-option submenu) |
| 2 | Unified CLI (usbctl) | USB | USB/config/alias/validate subcommands |
| 3 | Alias Manager | HOST | Manage `~/.bash_aliases_usb` |
| 4 | SSH Host Manager | HOST | Manage `~/.ssh/hosts_usb` |
| 5 | System Manager | HOST | Health/network/disk/services dashboard |
| 6 | USB Auto-Mount | HOST | udev + systemd setup |
| 7 | Build Essentials | HOST | Install dev toolchain |
| 8 | Hemlock TUI | CONTAINER | Agent runtime menu |
| 9 | Hemlock Status | CONTAINER | Check runtime status |
| 10 | Master Deploy | ALL | Full stack deployment (HOST + USB + CONTAINER) |
| 11 | Startup Manager | USB+HOST | Boot scripts & autostart across persistence + host |
| 12 | Persistence Manager | USB | Create/resize/browse/check persistence partitions |
| 13 | Bash Profile Manager | HOST | Install/edit/view enhanced bash profile + aliases |
| 14 | Device Config | HOST | Per-device profiles, switch between USB drive configs |
| 15 | Run Validation | ALL | Validate all components |
| 16 | Diagnostics | HOST | System info & config |
| 17 | View Logs | HOST | Log viewer & search |
| 18 | Toggle Dry-Run | — | Enable/disable preview mode |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DRY_RUN` | `false` | Preview mutations without executing |
| `LOG_FILE` | `/tmp/usb-hemlock-<pid>.log` | Log file path |
| `LOG_LEVEL` | `INFO` | Minimum: DEBUG, INFO, WARN, ERROR |
| `HEMLOCK_DIR` | auto-detected | Path to `hemlock-runtime/` |
| `SELECTED_DEVICE` | unset | USB device (e.g. `/dev/sdb`) |

---

## USB Setup Flow

### Option 1: Interactive Setup (Recommended)

```bash
bash menu.sh        # → Option 1: USB Setup Assistant
```

The USB Setup Assistant provides a 14-option menu:

1. **Setup USB Compute Automation System** — Complete setup
2. **Manage Ventoy USB Drive** → submenu:
   - Install Ventoy (WARNING: erases USB)
   - View inventory
   - Create persistence (ext4, casper-rw label)
   - Resize persistence
   - Browse persistence
3. **Setup VM Auto-Boot** — Headless configuration
4. **Install Build Essentials** — Dev toolchain
5. **Configure Network/SSH** — Network access
6. **View System Status** — Health dashboard
7. **Backup and Recovery** — Backup tools
8. **System Cleanup** — Diagnostics
9. **Manage Custom Aliases** — Alias CRUD
10. **Manage SSH Hosts** — SSH CRUD
11. **Access USB Persistent Terminal** — chroot into USB
12. **Copy File to USB** — Host→USB transfer
13. **Hemlock Agent Orchestration** — Opens Hemlock TUI
14. **Exit**

### Option 2: CLI

```bash
export SELECTED_DEVICE="/dev/sdb"    # Identify via lsblk
bash usb/cli/usbctl usb detect       # List devices
bash usb/cli/usbctl usb mount        # Mount Ventoy
bash usb/cli/usbctl config init      # Initialize config
bash usb/cli/usbctl config host-id   # Generate host ID
bash usb/cli/usbctl validate all     # Run validations
```

---

## Ventoy Persistence

### How Persistence Works

Ventoy supports persistence via a `.dat` file on the USB drive. When booting Ubuntu (or derivatives), Ventoy automatically detects a file named `casper-rw` in the `/persistence/` directory and mounts it as an overlay filesystem.

### Creating Persistence

**Method 1: Via USB Setup Assistant (Recommended)**
```bash
bash usb-setup-assistant.sh
# → Option 2: Manage Ventoy USB Drive → Option 3: Create persistence
```

This creates:
- `/persistence/ubuntu-persistence.dat` — ext4 filesystem with `casper-rw` label
- Default size: 8 GB (configurable)
- Automatically injects `etc/rc.local` for autostart

**Method 2: Manual Creation**
```bash
# 1. Create the persistence file
dd if=/dev/zero of=/mnt/ventoy/persistence/ubuntu-persistence.dat bs=1M count=8192

# 2. Format with ext4 and casper-rw label (required by casper)
mkfs.ext4 -F -L casper-rw /mnt/ventoy/persistence/ubuntu-persistence.dat

# 3. Loop-mount to inject rc.local
sudo mount -o loop /mnt/ventoy/persistence/ubuntu-persistence.dat /mnt/test
cat << 'EOF' | sudo tee /mnt/test/etc/rc.local
#!/bin/bash
# Auto-start script for USB persistence
exit 0
EOF
sudo chmod +x /mnt/test/etc/rc.local
sudo umount /mnt/test
```

### Ventoy Built-in Persistence Modes

Ventoy supports multiple persistence configurations. The relevant ones for this system:

1. **Single persistence file** (used by this system)
   - Path: `/persistence/ubuntu-persistence.dat`
   - Label: `casper-rw` (critical — casper looks for this exact label)
   - Format: ext4

2. **Multiple persistence files**
   - Ventoy supports multiple `.dat` files with different labels
   - Edit `/ventoy/ventoy.json` to configure:
   ```json
   {
     "persistence": [
       { "image": "/ubuntu.iso", "backend": "/persistence/ubuntu-persistence.dat" }
     ]
   }
   ```

3. **Built-in persistence via `persistence.dat`**
   - Ventoy auto-detects files named `persistence.dat` or `casper-rw` in the USB root
   - The `casper-rw` label is what Ubuntu's casper initrd looks for

4. **Custom persistence with `ventoy.json`**
   - Advanced: map specific ISOs to specific persistence files
   - Supports per-distro persistence configurations

### Resizing Persistence

```bash
bash usb-setup-assistant.sh
# → Option 2: Manage Ventoy USB Drive → Option 4: Resize persistence
```

Or manually:
```bash
# Unmount first if loop-mounted
sudo umount /mnt/test

# Resize the file
dd if=/dev/zero of=/path/to/ubuntu-persistence.dat bs=1M count=16384

# Resize the filesystem
sudo resize2fs /path/to/ubuntu-persistence.dat
```

### Browsing Persistence

```bash
bash usb-setup-assistant.sh
# → Option 2: Manage Ventoy USB Drive → Option 5: Browse persistence
```

Or manually:
```bash
sudo mount -o loop /mnt/ventoy/persistence/ubuntu-persistence.dat /mnt/test
ls /mnt/test/
# Browse files, modify configs, inject scripts
sudo umount /mnt/test
```

### Persistence File Location

The system expects persistence at:
```
$VENTOY_MOUNT/persistence/ubuntu-persistence.dat
```
Where `$VENTOY_MOUNT` is typically `/mnt/ventoy` (Linux) or `/Volumes/Ventoy` (macOS).

---

## Component Reference

### Alias Manager (`scripts/alias_manager.sh`)

Manages `~/.bash_aliases_usb` with full CRUD and backup support.

```bash
# Interactive menu
bash scripts/alias_manager.sh

# CLI
bash scripts/alias_manager.sh --list [table|csv|json]
bash scripts/alias_manager.sh --add NAME 'COMMAND' [description]
bash scripts/alias_manager.sh --remove NAME
bash scripts/alias_manager.sh --search QUERY
bash scripts/alias_manager.sh --import [~/.bashrc]
bash scripts/alias_manager.sh --export [table|csv|json]
bash scripts/alias_manager.sh --dry-run --add ...   # Preview
```

**Data format:**
```bash
alias ll='ls -alF' # List files in long format
alias gs='git status' # Git status shortcut
```

**Backups:** Stored in `~/.alias_backups/` — created before every mutation.

### SSH Host Manager (`scripts/ssh_host_manager.sh`)

Manages `~/.ssh/hosts_usb` (pipe-delimited: `alias|hostname|user|port|key_path|description`).

```bash
# Interactive menu
bash scripts/ssh_host_manager.sh

# CLI (positional --add)
bash scripts/ssh_host_manager.sh --add ALIAS HOSTNAME [USER] [PORT]
bash scripts/ssh_host_manager.sh --list
bash scripts/ssh_host_manager.sh --test ALIAS
bash scripts/ssh_host_manager.sh --generate    # Writes ~/.ssh/config
bash scripts/ssh_host_manager.sh --search QUERY
```

**Backups:** Stored in `~/.ssh/hosts_backups/` — created before every mutation.

### System Manager (`sysman.sh`)

Health/network/disk/services dashboard. Supports both whiptail and text fallback.

```bash
bash sysman.sh                # Interactive menu
bash sysman.sh --health       # Health snapshot
bash sysman.sh --network      # Network diagnostics
bash sysman.sh --disk         # Disk usage & SMART
bash sysman.sh --services     # systemd/service status
bash sysman.sh --repair       # Automatic repairs
bash sysman.sh --cleanup      # System cleanup
bash sysman.sh --dry-run      # Preview mode
```

### Unified CLI (`cli/usbctl`)

Single dispatcher for all USB/config/alias operations.

```bash
bash cli/usbctl usb detect          # List USB devices
bash cli/usbctl usb mount           # Mount Ventoy
bash cli/usbctl usb unmount         # Unmount Ventoy
bash cli/usbctl usb persistence     # Show persistence status
bash cli/usbctl config host-id      # Generate host ID
bash cli/usbctl config show         # Show config JSON
bash cli/usbctl config init         # Initialize config
bash cli/usbctl alias --list        # List aliases
bash cli/usbctl validate all        # Run all validations
```

### Hemlock Runtime TUI

Launches the Hemlock agent runtime inside a Docker container.

```bash
# Via master menu
bash menu.sh   # → Option 8

# Direct
export HEMLOCK_DIR=$(pwd)/hemlock/hemlock-runtime
bash usb/hemlock-tui

# Or via hemlock CLI
bash hemlock/hemlock-runtime/scripts/hemlock menu
```

**TUI Features:**
- Agent Management: Create, Import, Export, Delete, Start, Stop, Monitor
- Crew Management (A2A): Create, Join, Leave, Start, Monitor, Dissolve
- Runtime Validation: Full validation, Hermes Doctor, Docker env check
- Security Hardening: Apply, Check Status, Reset
- System Monitoring: Logs, Agent Logs, Health
- Configuration: Edit runtime/agent config

### Master Deploy (`DEPLOY.sh`)

Full stack deployment in 3 phases: System → USB → Hemlock. Requires root.

```bash
sudo bash hemlock/DEPLOY.sh              # Full deploy
sudo bash hemlock/DEPLOY.sh --dry-run    # Preview only
sudo bash hemlock/DEPLOY.sh --no-system  # Skip system bootstrap
sudo bash hemlock/DEPLOY.sh --no-usb     # Skip USB setup
sudo bash hemlock/DEPLOY.sh --no-hemlock # Skip Hemlock deploy
```

---

## Logging

All components write structured logs with timestamps, levels, and context.

### Log Levels

| Level | Description |
|-------|-------------|
| `DEBUG` | Verbose debug information |
| `INFO` | Normal operations |
| `WARN` | Potential issues |
| `ERROR` | Failures requiring attention |
| `CRITICAL` | System-threatening failures |

### Configuration

```bash
# Set log level
export LOG_LEVEL=DEBUG    # Most verbose
export LOG_LEVEL=INFO     # Default
export LOG_LEVEL=ERROR    # Only errors

# Set log file
export LOG_FILE=/var/log/usb-hemlock.log

# Disable file logging
export LOG_DISABLE_FILE=true

# Disable color output
export LOG_DISABLE_COLOR=true
```

### Log Rotation

Logs auto-rotate at 10 MB (`LOG_MAX_SIZE`). Only the last 5 rotated logs are kept.

### Viewing Logs

```bash
# Via master menu
bash menu.sh   # → Option 13: View Logs

# Direct
tail -f /tmp/usb-hemlock-*.log
grep "ERROR" /tmp/usb-hemlock-*.log
```

---

## Testing Suite

Run the full test suite to validate all components:

```bash
# Full test suite
bash usb/tests/run-all.sh

# Specific test categories
bash usb/tests/run-all.sh --syntax     # Syntax checks only
bash usb/tests/run-all.sh --runtime    # Runtime behavior only
bash usb/tests/run-all.sh --integration # Integration tests only

# Dry-run tests (no mutations)
bash usb/tests/run-all.sh --dry-run
```

### Test Categories

| Test | Description |
|------|-------------|
| `tests/00-env.sh` | Environment prerequisites |
| `tests/01-syntax.sh` | Bash syntax validation |
| `tests/02-permissions.sh` | File permissions |
| `tests/03-lib-modules.sh` | Library loading and API |
| `tests/04-config.sh` | Config init, get, set, host-id |
| `tests/05-alias-manager.sh` | Alias CRUD cycle |
| `tests/06-ssh-manager.sh` | SSH host CRUD cycle |
| `tests/07-sysman.sh` | System manager subcommands |
| `tests/08-usbctl.sh` | CLI dispatcher |
| `tests/09-validation.sh` | Validation engine + self-heal |
| `tests/10-hemlock.sh` | Hemlock runtime detection |
| `tests/11-menu.sh` | Master menu rendering |
| `tests/12-logging.sh` | Logging framework |
| `tests/13-deploy.sh` | Deploy dry-run |

---

## Development & Testing

```bash
# Syntax check everything
bash -n menu.sh usb/lib/*.sh usb/cli/usbctl usb/scripts/*.sh usb/sysman.sh usb/usb-setup-assistant.sh

# Preview all mutations
DRY_RUN=true bash menu.sh

# Run validation suite
bash usb/cli/usbctl validate all

# Run test suite
bash usb/tests/run-all.sh
```

---

## Feature Flags

All 29 flags are initialized to `disabled` in `feature-flags.json`. Enable them as components are validated:

| Flag | Module | Description |
|------|--------|-------------|
| `FEAT_CORE_LIB` | MOD-001 | Core library |
| `FEAT_PLATFORM` | MOD-002 | Platform detection |
| `FEAT_VENTOY` | MOD-003 | Ventoy USB management |
| `FEAT_CONFIG` | MOD-004 | JSON configuration |
| `FEAT_MENU` | MOD-005 | Menu framework |
| `FEAT_VALIDATION` | MOD-006 | Validation engine |
| `FEAT_CLI` | MOD-007 | Unified CLI |
| `FEAT_SETUP_ASSISTANT` | MOD-008 | USB setup assistant |
| `FEAT_ALIAS` | MOD-009 | Alias manager |
| `FEAT_SSH` | MOD-010 | SSH host manager |
| `FEAT_SYSMAN` | MOD-011 | System manager |
| `FEAT_ESSENTIALS` | MOD-012 | Essentials installer |
| `FEAT_AUTOMOUNT` | MOD-013 | USB auto-mount |
| `FEAT_BOOTSTRAP` | MOD-014 | System bootstrap |
| `FEAT_HEMLOCK_CLI` | MOD-015 | Hemlock host CLI |
| `FEAT_HEMLOCK_TUI` | MOD-016 | Hemlock runtime TUI |
| `FEAT_HEMLOCK_STAGING` | MOD-017 | Hemlock staging bridge |
| `FEAT_HEMLOCK_DOCKER` | MOD-018 | Hemlock Docker infra |
| `FEAT_DEPLOY` | MOD-019 | Master deployment |
| `FEAT_BRIDGE` | MOD-020 | USB-Hemlock bridge |
| `FEAT_SKILLS` | MOD-021 | Skills bundle |

---

## Troubleshooting

### "SELECTED_DEVICE not set"
```bash
export SELECTED_DEVICE="/dev/sdb"  # Identify via lsblk
```

### "HEMLOCK_DIR not found"
```bash
export HEMLOCK_DIR=$(pwd)/hemlock/hemlock-runtime
```

### "jq: command not found"
```bash
sudo apt install jq    # Debian/Ubuntu
brew install jq         # macOS
```

### "Docker daemon not running"
```bash
sudo systemctl start docker
```

### "Menu falls through to interactive mode"
This is a known bug in the original codebase. Fixed in the split copy — update your scripts from `usb-hemlock-split/`.

### Log files
Check `/tmp/usb-hemlock-*.log` for detailed operation logs with timestamps and error context.
