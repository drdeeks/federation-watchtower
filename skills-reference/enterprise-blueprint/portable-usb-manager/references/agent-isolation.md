# Agent Isolation

> **Mount variable:** examples use `$USB_MOUNT` for the USB mount point — set it once, e.g. `export USB_MOUNT="$(findmnt -no TARGET LABEL=Ventoy 2>/dev/null || echo /media/$USER/Ventoy)"`.
## Table of Contents

- [Architecture](#architecture)
- [Creating Agent Workspaces](#creating-agent-workspaces)
- [Global Read-Only Dependencies](#global-read-only-dependencies)
- [Agent Isolation Enforcement](#agent-isolation-enforcement)
- [Agent Manager Script](#agent-manager-script)
- [Inter-Agent Communication](#inter-agent-communication)
- [Monitoring and Management](#monitoring-and-management)


Multi-agent partition architecture for isolated AI agent workspaces on USB.

## Architecture

### Isolation Levels

| Level | Method | Isolation | Shared | Use Case |
|---|---|---|---|---|
| L0: None | Same filesystem | None | Everything | Single agent |
| L1: Directory | Separate home dirs | User data | System | Basic separation |
| L2: Partition | Separate ext4 | Full filesystem | Boot image | Standard isolation |
| L3: Container | Docker/LXC | System + network | Kernel | High isolation |
| L4: VM | QEMU/KVM | Complete | Hardware | Maximum isolation |

### Default Architecture (L2: Partition)

```
USB Drive (/dev/sdX)
├── Ventoy Partition (exfat, read-write)
│   ├── ISOs (read-only by design)
│   ├── Global Dependencies (ext4, read-only)
│   │   ├── /usr/lib (shared libraries)
│   │   ├── /usr/share (shared data)
│   │   └── /opt/global (shared tools)
│   ├── Agent Workspaces (ext4, per-agent)
│   │   ├── agent-alpha-home.dat (isolated)
│   │   ├── agent-beta-home.dat (isolated)
│   │   └── agent-gamma-home.dat (isolated)
│   └── Shared Data (exfat, read-write)
│       ├── common-files/
│       └── exchange/
└── EFI Partition (vfat)
```

## Creating Agent Workspaces

### Manual Creation

```bash
# Create directory structure:
sudo mkdir -p $USB_MOUNT/agents/{alpha,beta,gamma}

# Create isolated partitions for each agent:
for agent in alpha beta gamma; do
    echo "Creating workspace for agent: $agent"
    
    # Create 5GB persistent storage
    sudo dd if=/dev/zero of=$USB_MOUNT/agents/${agent}-home.dat \
        bs=1M count=5000 status=progress
    
    # Format as ext4 with agent-specific label
    sudo mkfs.ext4 -F -L "${agent}-home" $USB_MOUNT/agents/${agent}-home.dat
    
    # Mount and initialize home directory
    sudo mkdir -p /tmp/agent-init
    sudo mount -o loop $USB_MOUNT/agents/${agent}-home.dat /tmp/agent-init
    
    # Create standard home structure
    sudo mkdir -p /tmp/agent-init/{bin,lib,share,workspace,config,cache}
    
    # Create agent info file
    sudo tee /tmp/agent-init/agent-info.json > /dev/null << EOF
{
    "name": "$agent",
    "created": "$(date -Iseconds)",
    "version": "1.0",
    "isolation_level": "L2",
    "storage_size": "5G"
}
EOF
    
    # Set permissions
    sudo chown -R 1000:1000 /tmp/agent-init
    
    # Unmount
    sudo umount /tmp/agent-init
done
```

### Automated Setup

```bash
# Use the agent manager script:
python3 scripts/agent-manager.py create --name alpha --size 5G --usb /dev/sdX
python3 scripts/agent-manager.py create --name beta --size 5G --usb /dev/sdX
python3 scripts/agent-manager.py create --name gamma --size 3G --usb /dev/sdX
```

### Update Ventoy Configuration

```bash
sudo tee $USB_MOUNT/ventoy/ventoy.json > /dev/null << 'EOF'
{
    "persistence": [
        {
            "image": "/ubuntu-24.04.4-desktop-amd64.iso",
            "backend": "/persistence/ubuntu-persistence.dat"
        }
    ],
    "agent_isolation": {
        "alpha": {
            "backend": "/agents/alpha-home.dat",
            "description": "Primary research agent",
            "storage_size": "5G"
        },
        "beta": {
            "backend": "/agents/beta-home.dat",
            "description": "Development agent",
            "storage_size": "5G"
        },
        "gamma": {
            "backend": "/agents/gamma-home.dat",
            "description": "Testing agent",
            "storage_size": "3G"
        }
    }
}
EOF
```

## Global Read-Only Dependencies

### Purpose

Shared libraries and tools that all agents can read but not modify. Prevents version conflicts and ensures consistency.

### Creation

```bash
# Create global dependencies partition:
sudo dd if=/dev/zero of=$USB_MOUNT/global-deps.dat \
    bs=1M count=10000 status=progress
sudo mkfs.ext4 -F -L global-deps $USB_MOUNT/global-deps.dat

# Mount and populate:
sudo mkdir -p /tmp/global-deps
sudo mount -o loop $USB_MOUNT/global-deps.dat /tmp/global-deps

# Method 1: Copy from current system
sudo rsync -av --progress /usr/lib/ /tmp/global-deps/usr/lib/
sudo rsync -av --progress /usr/share/ /tmp/global-deps/usr/share/
sudo rsync -av --progress /usr/bin/ /tmp/global-deps/usr/bin/

# Method 2: Install fresh packages
sudo debootstrap focal /tmp/global-deps http://archive.ubuntu.com/ubuntu/

# Method 3: Copy specific applications
sudo cp -r /opt/someapp /tmp/global-deps/opt/

# Create mount points for agents:
sudo mkdir -p /tmp/global-deps/{mnt/shared,etc/agents}

# Mark as read-only:
sudo umount /tmp/global-deps
sudo tune2fs -O ro $USB_MOUNT/global-deps.dat
```

### Mounting in Agent Sessions

```bash
# Mount global deps as read-only in agent session:
sudo mount -o ro,loop $USB_MOUNT/global-deps.dat /mnt/global

# Or add to /etc/fstab for automatic mounting:
echo "$USB_MOUNT/global-deps.dat /mnt/global ext4 ro,loop,nofail 0 0" | sudo tee -a /etc/fstab
```

## Agent Isolation Enforcement

### Filesystem Isolation

```bash
# Mount agent home as separate partition:
sudo mount -o loop $USB_MOUNT/agents/alpha-home.dat /home/alpha

# Verify isolation:
mount | grep alpha
df -h /home/alpha
```

### User Isolation

```bash
# Create agent-specific users:
for agent in alpha beta gamma; do
    sudo useradd -m -s /bin/bash ${agent}-agent
    sudo mkdir -p /home/${agent}-agent/.ssh
    sudo cp $USB_MOUNT/agents/${agent}-key.pub /home/${agent}-agent/.ssh/authorized_keys
    sudo chown -R ${agent}-agent:${agent}-agent /home/${agent}-agent
done
```

### Network Isolation

```bash
# Create isolated network namespaces for agents:
for agent in alpha beta gamma; do
    sudo ip netns add ${agent}-net
    sudo ip link add veth-${agent}-host type veth peer name veth-${agent}-ns
    sudo ip link set veth-${agent}-ns netns ${agent}-net
    sudo ip addr add 10.0.${agent_num}.1/24 dev veth-${agent}-host
    sudo ip link set veth-${agent}-host up
    sudo ip netns exec ${agent}-net ip link set lo up
    sudo ip netns exec ${agent}-net ip addr add 10.0.${agent_num}.2/24 dev veth-${agent}-ns
    sudo ip netns exec ${agent}-net ip link set veth-${agent}-ns up
    sudo ip netns exec ${agent}-net ip route add default via 10.0.${agent_num}.1
done
```

## Agent Manager Script

### Commands

```bash
# Create new agent:
python3 scripts/agent-manager.py create --name <name> --size <size> --usb /dev/sdX

# List agents:
python3 scripts/agent-manager.py list --usb /dev/sdX

# Enter agent workspace:
python3 scripts/agent-manager.py enter --name <name>

# Backup agent:
python3 scripts/agent-manager.py backup --name <name> --dest ~/backups/

# Restore agent:
python3 scripts/agent-manager.py restore --name <name> --src ~/backups/<name>.tar.gz

# Delete agent:
python3 scripts/agent-manager.py delete --name <name> --usb /dev/sdX

# Resize agent storage:
python3 scripts/agent-manager.py resize --name <name> --size <new-size> --usb /dev/sdX

# Check agent health:
python3 scripts/agent-manager.py health --name <name>

# Clone agent:
python3 scripts/agent-manager.py clone --source <source> --dest <dest> --usb /dev/sdX
```

### Script Features

- Automatic backup before destructive operations
- Health checks (filesystem integrity, space usage)
- Cloning with UUID regeneration
- Resize with data preservation
- Network namespace creation
- User account management

## Inter-Agent Communication

### Shared Exchange Directory

```bash
# Create shared exchange (read-write for all agents):
sudo mkdir -p $USB_MOUNT/exchange

# Agents can read/write to exchange:
echo "Hello from alpha" > $USB_MOUNT/exchange/alpha-msg.txt
cat $USB_MOUNT/exchange/alpha-msg.txt
```

### Named Pipes (FIFO)

```bash
# Create communication channel between agents:
mkfifo $USB_MOUNT/exchange/alpha-to-beta

# Agent alpha writes:
echo "Task complete" > $USB_MOUNT/exchange/alpha-to-beta

# Agent beta reads:
cat $USB_MOUNT/exchange/alpha-to-beta
```

### Message Queue (Redis)

```bash
# Install Redis for message passing:
sudo apt install redis-server -y

# Start Redis:
redis-server --daemonize yes

# Agent alpha sends message:
redis-cli lpush agent:beta:queue '{"task": "process_data", "status": "complete"}'

# Agent beta receives message:
redis-cli brpop agent:beta:queue 0
```

## Monitoring and Management

### Agent Status

```bash
# Check all agents:
for agent in alpha beta gamma; do
    echo "=== Agent: $agent ==="
    sudo mount -o loop $USB_MOUNT/agents/${agent}-home.dat /tmp/agent-check
    df -h /tmp/agent-check
    cat /tmp/agent-check/agent-info.json
    sudo umount /tmp/agent-check
    echo
done
```

### Resource Limits

```bash
# Set disk quotas per agent:
sudo quotacheck -c $USB_MOUNT/agents/
sudo quotaon $USB_MOUNT/agents/

# Set memory limits (cgroups):
for agent in alpha beta gamma; do
    sudo cgcreate -g memory:/agent-${agent}
    echo "512M" | sudo tee /sys/fs/cgroup/memory/agent-${agent}/memory.limit_in_bytes
done
```

### Cleanup

```bash
# Remove unused agents:
python3 scripts/agent-manager.py cleanup --usb /dev/sdX

# Compact agent partitions:
for agent in alpha beta gamma; do
    sudo e2fsck -f $USB_MOUNT/agents/${agent}-home.dat
    sudo resize2fs $USB_MOUNT/agents/${agent}-home.dat
done
```
