# Persistence Package Installation

## Overview

Install build tools, development environments, and applications directly INTO the USB persistence image via chroot. This makes them permanently available when booting from USB or accessing via chroot.

## Architecture

```
Host System
  └─► USB Setup Assistant (sudo)
        └─► Mount Ventoy partition
              └─► Mount persistence image (/persistence/ubuntu-persistence.dat)
                    └─► Chroot into persistence
                          └─► apt-get install / pip install / etc.
                            └─► Changes persist in ubuntu-persistence.dat
```

## Implementation in USB Setup Assistant

The `install_essentials()` function (Option 4) performs this automatically:

```bash
install_essentials() {
    # 1. Select USB device
    # 2. Mount Ventoy partition
    # 3. Verify persistence exists
    
    # 4. Mount persistence image
    local persist_mnt="/tmp/usb-persist-$$"
    mkdir -p "$persist_mnt"
    mount -o loop "$persist_file" "$persist_mnt"
    
    # 5. Prepare chroot environment
    mount --bind /dev "$persist_mnt/dev"
    mount --bind /proc "$persist_mnt/proc"
    mount --bind /sys "$persist_mnt/sys"
    mount --bind /dev/pts "$persist_mnt/dev/pts"
    mount --bind /tmp "$persist_mnt/tmp"
    cp /etc/resolv.conf "$persist_mnt/etc/resolv.conf"
    
    # 6. Build install script inside persistence
    local install_script="$persist_mnt/tmp/usb-install.sh"
    cat > "$install_script" << 'EOF'
    #!/bin/bash
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y build-essential git curl wget vim nano htop
    apt-get install -y python3 python3-pip python3-venv python3-dev nodejs npm
    # ... optional components based on user selection
    apt-get clean
    EOF
    
    # 7. Execute inside chroot
    chroot "$persist_mnt" /bin/bash /tmp/usb-install.sh
    
    # 8. Cleanup chroot mounts
    umount "$persist_mnt/dev/pts" /dev /proc /sys "$persist_mnt"
    
    # 8. Copy install script to USB for future updates
    cp "$persist_mnt/../tmp/usb-install.sh" "$VENTOY_MOUNT/setup-essentials.sh"
    chmod +x "$VENTOY_MOUNT/setup-essentials.sh"
}
```

## Component Selection Menu

Users choose what to install:

```
Choose components to install:
  [1] Build essentials (gcc, make, cmake, git, python3, nodejs) - ALWAYS INCLUDED
  [2] System utilities (htop, vim, curl, wget, net-tools)
  [3] Python dev tools (pip, venv, ipython, jupyter)
  [4] Container tools (docker, podman)
  [5] LLM engine: ollama
  [6] LLM engine: llama.cpp
  [7] Agent harness: AutoGen
  [8] Agent harness: CrewAI
  [9] Agent harness: LangChain
  [D] Database tools (mysql-client, postgresql-client, sqlite3)
  [M] Modern CLI tools (ripgrep, fd-find, btop, ncdu, tmux, jq, nala, bat, fzf, zsh)
  [A] All of the above
  [N] None — just base essentials
  [Q] Cancel
```

## What Gets Installed

### Base (Always)
- `build-essential` (gcc, g++, make)
- `cmake`, `pkg-config`, `git`
- `python3`, `python3-pip`, `python3-venv`, `python3-dev`
- `nodejs`, `npm` (via NodeSource LTS repo)

### Optional Components

| Component | Packages |
|---|---|
| System Utilities | `htop`, `vim`, `curl`, `wget`, `net-tools`, `make`, `cmake`, `pkg-config`, `libssl-dev`, `zlib1g-dev`, `sqlite3`, `unzip`, `p7zip-full`, `rsync`, `ssh`, `net-tools`, `dnsutils` |
| Python Dev | `ipython`, `jupyter`, `black`, `flake8`, `pytest` |
| Containers | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`, `podman` |
| Ollama | `zstd`, then `curl -fsSL https://ollama.com/install.sh \| sh` |
| llama.cpp | `git clone https://github.com/ggerganov/llama.cpp /opt/llama.cpp` + hardware-aware build |
| AutoGen | `pip3 install --break-system-packages autogen-agentchat` |
| CrewAI | `pip3 install --break-system-packages crewai` |
| LangChain | `pip3 install --break-system-packages langchain langchain-community` |
| Databases | `mysql-client`, `postgresql-client`, `sqlite3` |
| Modern CLI | `ripgrep`, `fd-find`, `btop`, `ncdu`, `tmux`, `jq`, `nala`, `bat`, `fzf`, `zsh` |

## Hardware-Aware Builds

### Ollama

```bash
# Auto-detects architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    echo "Apple Silicon / ARM64 — Ollama will use Metal acceleration"
elif [[ "$ARCH" == "x86_64" ]]; then
    echo "x86_64 — Ollama will use CPU/GPU based on availability"
fi
```

### llama.cpp

```bash
# Hardware-aware build
ARCH=$(uname -m)
OS=$(uname -s)

if [[ "$OS" == "Darwin" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
        make -j$(sysctl -n hw.ncpu) LLAMA_METAL=1      # Apple Silicon
    else
        make -j$(sysctl -n hw.ncpu) LLAMA_ACCELERATE=1  # Intel Mac
    fi
elif [[ "$OS" == "Linux" ]]; then
    if command -v nvidia-smi &>/dev/null; then
        make -j$(nproc) LLAMA_CUDA=1                    # NVIDIA GPU
    elif command -v rocm-smi &>/dev/null || [[ -d "/opt/rocm" ]]; then
        make -j$(nproc) LLAMA_HIPBLAS=1                 # AMD GPU
    else
        make -j$(nproc) LLAMA_BLAS=1                    # CPU with BLAS
    fi
fi
```

## Post-Installation

### Automatic rc.local Injection

The installer injects an auto-run script into persistence:

```bash
# /etc/rc.local (inside persistence)
#!/bin/bash
# USB Compute Automation - Auto-install build essentials on first boot

SETUP_MARKER="/opt/.essentials-installed"
SETUP_LOG="/var/log/usb-essentials-setup.log"

if [[ ! -f "$SETUP_MARKER" ]]; then
    echo "=== First Boot: Installing Build Essentials ===" | tee -a "$SETUP_LOG"
    
    # Find setup script on USB
    SCRIPT_PATH=""
    for path in /media/*/Ventoy /mnt/ventoy /run/media/*/Ventoy; do
        if [[ -f "$path/setup-essentials.sh" ]]; then
            SCRIPT_PATH="$path/setup-essentials.sh"
            break
        fi
    done
    
    if [[ -n "$SCRIPT_PATH" ]]; then
        bash "$SCRIPT_PATH" 2>&1 | tee -a "$SETUP_LOG"
        touch "$SETUP_MARKER"
        echo "=== Build Essentials Installed! ===" | tee -a "$SETUP_LOG"
    else
        echo "Setup script not found" | tee -a "$SETUP_LOG"
    fi
fi

exit 0
```

### Profile.d Entry

```bash
# /etc/profile.d/usb-essentials.sh
# USB Compute Automation - Check for essentials on login

if [[ ! -f /opt/.essentials-installed ]]; then
    echo ""
    echo "=== USB Compute: Build essentials not yet installed ==="
    echo "Run: sudo bash /media/*/Ventoy/setup-essentials.sh"
    echo ""
fi

# Load enhanced bash profile if available
if [[ -f /media/*/Ventoy/bash_enhanced.sh ]]; then
    source /media/*/Ventoy/bash_enhanced.sh 2>/dev/null || true
fi

# Load SSH host aliases if available
if [[ -f ~/.ssh/hosts_usb ]]; then
    if [[ -f /media/*/Ventoy/ssh_host_manager.sh ]]; then
        source /media/*/Ventoy/ssh_host_manager.sh 2>/dev/null || true
    fi
fi
```

## Usage

### From USB Setup Assistant (Option 4)

```bash
# Select Option 4: Install Build Essentials and Dependencies
# → Choose components
# → System builds and installs into persistence
# → Tools available on next boot or chroot access
```

### From Host CLI

```bash
# The setup-essentials.sh is copied to USB for manual runs
sudo bash /media/$USER/Ventoy/setup-essentials.sh
```

### From Chroot (Option 11)

```bash
# Access persistence terminal
sudo bash ~/usb-setup-assistant.sh
# Select Option 11
# Inside chroot:
apt-get update && apt-get install -y <package>
```

## Verification

```bash
# Check installed packages
chroot /mnt/usb-persist /bin/bash -c "dpkg -l | grep -E 'gcc|python3|node|docker'"

# Check setup log
cat /mnt/usb-persist/var/log/usb-essentials-setup.log

# Verify marker
ls -la /mnt/usb-persist/opt/.essentials-installed
```

## Best Practices

1. **Run as root** - Required for chroot and package installation
2. **Internet required** - apt and pip need connectivity
3. **Run once** - Marker file prevents re-installation
4. **Use Option 4** for full interactive selection
5. **Backup first** - Option 7 before major changes
6. **Test in chroot** - Option 11 to verify before reboot