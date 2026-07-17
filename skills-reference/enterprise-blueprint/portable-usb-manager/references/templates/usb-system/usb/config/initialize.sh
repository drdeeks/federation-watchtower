#!/usr/bin/env bash
set -euo pipefail
# One-time bootstrap for Ubuntu dev environment (minimal + optional lightweight GUI)
# Edit variables below before running
USER_NAME="${SUDO_USER:-$USER}"
HOME_DIR="/home/$USER_NAME"
LOCAL_BIN="$HOME_DIR/.local/bin"
VENTOY_PERSISTENCE="/mnt/ventoy/persistence"  # adjust if needed

# Basic system update and essentials
apt update
apt -y upgrade
apt -y install --no-install-recommends ca-certificates curl wget gnupg lsb-release build-essential \
  unzip tar git ca-certificates sudo pkg-config jq openssh-client apt-transport-https

# Create local bin
mkdir -p "$LOCAL_BIN"
chown -R "$USER_NAME:$USER_NAME" "$LOCAL_BIN"

# Node.js (use NodeSource LTS)
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt -y install nodejs
# npm is bundled; install yarn minimal (corepack can enable yarn/bun)
corepack enable
corepack prepare yarn@stable --activate

# Bun (minimal binary install)
if ! command -v bun >/dev/null 2>&1; then
  curl -fsSL https://bun.sh/install | bash
  # bun installs to ~/.bun; optionally add to PATH for all sessions
fi

# Python (minimal) + pip, venv
apt -y install --no-install-recommends python3 python3-venv python3-distutils python3-pip
python3 -m pip install --upgrade pip setuptools wheel

# Docker
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  usermod -aG docker "$USER_NAME"
fi

# Foundry (forge) - minimal install
if ! command -v forge >/dev/null 2>&1; then
  curl -L https://foundry.paradigm.xyz | bash
  "$HOME_DIR/.foundry/bin/foundryup" || true
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.foundry"
fi

# Hardhat (global minimal)
npm install --location=global hardhat

# Ethers.js
npm install --location=global ethers

# Llama-cpp python + minimal runtime (assumes you will build with minimal flags)
apt -y install --no-install-recommends cmake g++ build-essential libopenblas-dev
python3 -m pip install --user --no-warn-script-location cython
# Building llama.cpp bindings is project specific; leave placeholder
echo "NOTE: build llama-cpp-python manually in a venv; see project docs."

# Tailscale (for secure access)
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.gpg | gpg --dearmour -o /usr/share/keyrings/tailscale-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu focal main" \
  | tee /etc/apt/sources.list.d/tailscale.list
apt update
apt -y install tailscale

# SSH server
apt -y install openssh-server
systemctl enable --now ssh

# TTYS / TTS simple tool (tts-cli)
python3 -m pip install --user TTS

# SQLite cli
apt -y install sqlite3

# curl done earlier; git installed earlier
# Install unzip/tar done earlier

# Chromium (minimal)
apt -y install --no-install-recommends chromium-browser

# Lightweight GUI: install LXQt or XFCE minimal, and a tiny file viewer with drag-drop support (pcmanfm-qt)
apt -y install --no-install-recommends xorg xinit lxqt-core pcmanfm-qt
# Optional compositor/tinting: picom (tinted)
apt -y install picom

# Tauri dependencies (for building apps)
apt -y install libssl-dev libgtk-3-dev libayatana-appindicator3-dev build-essential curl

# uTorrent: not recommended; if you need a torrent client, install transmission-cli (lightweight)
apt -y install transmission-daemon transmission-cli

# Hugging Face CLI
python3 -m pip install --user huggingface-hub

# dotenv, mcp (if you mean mop?), and other small npm packages install per-project; create global minimal tools folder
npm install --location=global dotenv-cli

# SSH keys helper: generate if missing
if [ ! -f "$HOME_DIR/.ssh/id_ed25519" ]; then
  sudo -u "$USER_NAME" ssh-keygen -t ed25519 -f "$HOME_DIR/.ssh/id_ed25519" -N ""
fi

# Docker: install docker-compose plugin (if desired)
apt -y install docker-compose-plugin

# Optional: install VirtualBox for hosting macOS VM (macOS VM on Linux is legally and technically tricky).
# We will install libvirt + QEMU which are common; hosting a macOS VM requires additional steps and images.
apt -y install qemu-kvm libvirt-daemon-system libvirt-clients virtinst virt-manager
usermod -aG libvirt "$USER_NAME"

# Small utilities
apt -y install htop neovim

# Configure environment (append to user's .profile)
cat >> "$HOME_DIR/.profile" <<'EOF'
# Local bin
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.foundry/bin:$PATH"
# Python user bin
export PATH="$HOME/.local/bin:$PATH"
EOF
chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.profile"

echo "Initial setup complete. Log out/in or source ~/.profile. Review llama.cpp, macVM, and any proprietary tools manually."
