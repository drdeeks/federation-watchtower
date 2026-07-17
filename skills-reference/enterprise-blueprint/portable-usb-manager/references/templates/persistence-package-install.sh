#!/usr/bin/env bash
# Persistence Package Install Template
# Install packages directly INTO USB persistence via chroot

set -euo pipefail

# Configuration
USB_DEVICE="${1:-}"
if [[ -z "$USB_DEVICE" ]]; then
    echo "Usage: $0 <usb-device> [component-list]"
    echo "Components: base utils python containers ollama llama autogen crewai langchain db modern all"
    exit 1
fi

COMPONENTS="${2:-base}"

# Detect OS
if [[ "$(uname)" == "Darwin" ]]; then
    PART="${USB_DEVICE}s1"
else
    PART="${USB_DEVICE}1"
fi

# Mount Ventoy partition
VENTOY_MOUNT="/mnt/ventoy-install-$$"
mkdir -p "$VENTOY_MOUNT"
if ! mount "$PART" "$VENTOY_MOUNT"; then
    echo "Failed to mount Ventoy partition: $PART"
    exit 1
fi

PERSIST_FILE="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
if [[ ! -f "$PERSIST_FILE" ]]; then
    echo "No persistence file found: $PERSIST_FILE"
    umount "$VENTOY_MOUNT"
    rmdir "$VENTOY_MOUNT"
    exit 1
fi

# Mount persistence image
PERSIST_MNT="/tmp/usb-persist-install-$$"
mkdir -p "$PERSIST_MNT"
mount -o loop "$PERSIST_FILE" "$PERSIST_MNT"

# Prepare chroot
mount --bind /dev "$PERSIST_MNT/dev"
mount --bind /proc "$PERSIST_MNT/proc"
mount --bind /sys "$PERSIST_MNT/sys"
mount --bind /dev/pts "$PERSIST_MNT/dev/pts"
mount --bind /tmp "$PERSIST_MNT/tmp"
cp /etc/resolv.conf "$PERSIST_MNT/etc/resolv.conf"

# Build install script
INSTALL_SCRIPT="$PERSIST_MNT/tmp/usb-install.sh"
cat > "$INSTALL_SCRIPT" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== USB Compute Essentials Install ===" | tee /var/log/usb-essentials.log

echo "Updating package lists..." | tee -a /var/log/usb-essentials.log
apt-get update 2>&1 | tee -a /var/log/usb-essentials.log

echo "Installing base tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y build-essential git curl wget vim nano htop 2>&1 | tee -a /var/log/usb-essentials.log
apt-get install -y python3 python3-pip python3-venv python3-dev 2>&1 | tee -a /var/log/usb-essentials.log

# NodeSource repository for Node.js LTS
echo "Adding NodeSource repository for Node.js LTS..." | tee -a /var/log/usb-essentials.log
apt-get install -y ca-certificates curl gnupg 2>&1 | tee -a /var/log/usb-essentials.log
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_lts.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update 2>&1 | tee -a /var/log/usb-essentials.log

echo "Installing base tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y build-essential git curl wget vim nano htop 2>&1 | tee -a /var/log/usb-essentials.log
apt-get install -y python3 python3-pip python3-venv python3-dev nodejs npm 2>&1 | tee -a /var/log/usb-essentials.log
EOF

# Add component-specific installs
if [[ "$COMPONENTS" == *"utils"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing system utilities..." | tee -a /var/log/usb-essentials.log
apt-get install -y make cmake pkg-config libssl-dev zlib1g-dev libffi-dev libreadline-dev libbz2-dev liblzma-dev sqlite3 libsqlite3-dev tk-dev libgdbm-dev libncursesw5-dev xz-utils libxml2-dev libxslt1-dev libjpeg-dev libpng-dev unzip p7zip-full rsync ssh net-tools dnsutils 2>&1 | tee -a /var/log/usb-essentials.log
EOF
fi

if [[ "$COMPONENTS" == *"python"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing Python dev tools..." | tee -a /var/log/usb-essentials.log
pip3 install --break-system-packages ipython jupyter black flake8 pytest 2>&1 | tee -a /var/log/usb-essentials.log
EOF
fi

if [[ "$COMPONENTS" == *"containers"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing container tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin podman 2>&1 | tee -a /var/log/usb-essentials.log
EOF
fi

if [[ "$COMPONENTS" == *"ollama"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing Ollama..." | tee -a /var/log/usb-essentials.log
apt-get install -y zstd 2>&1 | tee -a /var/log/usb-essentials.log
curl -fsSL https://ollama.com/install.sh | sh 2>&1 | tee -a /var/log/usb-essentials.log
EOF
fi

if [[ "$COMPONENTS" == *"llama"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing llama.cpp..." | tee -a /var/log/usb-essentials.log
git clone https://github.com/ggerganov/llama.cpp /opt/llama.cpp 2>&1 | tee -a /var/log/usb-essentials.log
cd /opt/llama.cpp

ARCH=$(uname -m)
OS=$(uname -s)

if [[ "$OS" == "Darwin" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
        echo "Apple Silicon — building with Metal support" | tee -a /var/log/usb-essentials.log
        make -j$(sysctl -n hw.ncpu) LLAMA_METAL=1 2>&1 | tee -a /var/log/usb-essentials.log
    else
        echo "Intel Mac — building with Accelerate framework" | tee -a /var/log/usb-essentials.log
        make -j$(sysctl -n hw.ncpu) LLAMA_ACCELERATE=1 2>&1 | tee -a /var/log/usb-essentials.log
    fi
elif [[ "$OS" == "Linux" ]]; then
    if command -v nvidia-smi &>/dev/null; then
        echo "NVIDIA GPU — building with CUDA support" | tee -a /var/log/usb-essentials.log
        make -j$(nproc) LLAMA_CUDA=1 2>&1 | tee -a /var/log/usb-essentials.log
    elif command -v rocm-smi &>/dev/null || [[ -d "/opt/rocm" ]]; then
        echo "AMD GPU — building with ROCm support" | tee -a /var/log/usb-essentials.log
        make -j$(nproc) LLAMA_HIPBLAS=1 2>&1 | tee -a /var/log/usb-essentials.log
    else
        echo "No GPU detected — building with CPU optimizations" | tee -a /var/log/usb-essentials.log
        make -j$(nproc) LLAMA_BLAS=1 2>&1 | tee -a /var/log/usb-essentials.log
    fi
fi
EOF
fi

if [[ "$COMPONENTS" == *"autogen"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing AutoGen..." | tee -a /var/log/usb-essentials.log
pip3 install --break-system-packages autogen-agentchat 2>&1 | tee -a /var/log/usb-essentials.log
EOF
fi

if [[ "$COMPONENTS" == *"crewai"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing CrewAI..." | tee -a /var/log/usb-essentials.log
pip3 install --break-system-packages crewai 2>&1 | tee -a /var/log/usb-essentials.log
EOF
fi

if [[ "$COMPONENTS" == *"langchain"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing LangChain..." | tee -a /var/log/usb-essentials.log
pip3 install --break-system-packages langchain langchain-community 2>&1 | tee -a /var/log/usb-essentials.log
EOF
fi

if [[ "$COMPONENTS" == *"db"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing database tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y mysql-client postgresql-client sqlite3 2>&1 | tee -a /var/log/usb-essentials.log
EOF
fi

if [[ "$COMPONENTS" == *"modern"* || "$COMPONENTS" == *"all"* ]]; then
    cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Installing modern CLI tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y ripgrep fd-find btop ncdu tmux jq nala tree bat fzf zsh 2>&1 | tee -a /var/log/usb-essentials.log
ln -sf /usr/bin/fdfind /usr/local/bin/fd 2>/dev/null || true
EOF
fi

# Cleanup
cat >> "$INSTALL_SCRIPT" << 'EOF'
echo "Cleaning up..." | tee -a /var/log/usb-essentials.log
apt-get autoremove -y 2>&1 | tee -a /var/log/usb-essentials.log
apt-get clean 2>&1 | tee -a /var/log/usb-essentials.log

echo "=== Installation Complete ===" | tee -a /var/log/usb-essentials.log
echo "Python: $(python3 --version 2>/dev/null)" | tee -a /var/log/usb-essentials.log
echo "Node.js: $(node --version 2>/dev/null)" | tee -a /var/log/usb-essentials.log
echo "GCC: $(gcc --version 2>/dev/null | head -1)" | tee -a /var/log/usb-essentials.log
EOF

chmod +x "$INSTALL_SCRIPT"

# Execute inside chroot
echo "Installing into USB Persistence..."
chroot "$PERSIST_MNT" /bin/bash /tmp/usb-install.sh 2>&1

# Cleanup chroot
umount "$PERSIST_MNT/dev/pts" "$PERSIST_MNT/dev" "$PERSIST_MNT/proc" "$PERSIST_MNT/sys" "$PERSIST_MNT" 2>/dev/null || true

# Copy install script to USB for future updates
cp "$PERSIST_MNT/../tmp/usb-install.sh" "$VENTOY_MOUNT/setup-essentials.sh" 2>/dev/null || true
chmod +x "$VENTOY_MOUNT/setup-essentials.sh" 2>/dev/null || true

# Cleanup
umount "$PERSIST_MNT" 2>/dev/null || true
rmdir "$PERSIST_MNT"
umount "$VENTOY_MOUNT"
rmdir "$VENTOY_MOUNT"

echo "Installation complete! Run 'hemlock model-list' or 'hemlock tui' to verify."