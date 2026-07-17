# Container Integration

> **Mount variable:** examples use `$USB_MOUNT` for the USB mount point — set it once, e.g. `export USB_MOUNT="$(findmnt -no TARGET LABEL=Ventoy 2>/dev/null || echo /media/$USER/Ventoy)"`.
## Table of Contents

- [Docker Integration](#docker-integration)
- [LXC/LXD Integration](#lxc/lxd-integration)
- [Podman Integration](#podman-integration)
- [Container Security](#container-security)
- [Container Backup and Restore](#container-backup-and-restore)


Docker, LXC/LXD, and Podman integration patterns for portable Linux USB.

## Docker Integration

### Installation on Persistent USB

```bash
# After booting into persistent USB:
sudo apt update
sudo apt install docker.io docker-compose docker-compose-plugin -y
sudo systemctl enable docker
sudo systemctl start docker

# Add user to docker group:
sudo usermod -aG docker $USER
newgrp docker

# Verify installation:
docker --version
docker run hello-world
```

### Persistent Docker Storage

```bash
# Create dedicated Docker partition:
sudo dd if=/dev/zero of=$USB_MOUNT/docker-storage.dat \
    bs=1M count=20000 status=progress
sudo mkfs.ext4 -F -L docker-storage $USB_MOUNT/docker-storage.dat

# Mount as Docker data directory:
sudo mkdir -p /var/lib/docker
sudo mount -o loop $USB_MOUNT/docker-storage.dat /var/lib/docker

# Add to /etc/fstab for automatic mounting:
echo "$USB_MOUNT/docker-storage.dat /var/lib/docker ext4 loop,nofail 0 0" | sudo tee -a /etc/fstab
```

### Container Patterns

#### Basic Ubuntu Container

```bash
# Run interactive Ubuntu container:
docker run -it --rm ubuntu:24.04 bash

# With persistent workspace:
docker run -it --rm \
    -v $USB_MOUNT/workspace:/workspace \
    ubuntu:24.04 bash

# With GUI forwarding (X11):
docker run -it --rm \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v $HOME/.Xauthority:${HOME}/.Xauthority:ro \
    ubuntu:24.04 bash
```

#### Agent-Specific Containers

```bash
# Create agent containers with isolation:
for agent in alpha beta gamma; do
    docker run -d \
        --name agent-${agent} \
        -v $USB_MOUNT/agents/${agent}-data:/workspace \
        -e AGENT_NAME=${agent} \
        -e AGENT_HOME=/workspace \
        --memory=512m \
        --cpus=1 \
        ubuntu:24.04 sleep infinity
    
    # Enter container:
    docker exec -it agent-${agent} bash
done
```

#### Development Environment Container

```bash
# Create development container:
docker run -it --rm \
    --name dev-env \
    -v $USB_MOUNT/workspace:/workspace \
    -v $USB_MOUNT/global-deps:/global:ro \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -p 8080:80 \
    -p 3000:3000 \
    -p 5000:5000 \
    node:20 bash

# Or with Dockerfile:
cat > $USB_MOUNT/Dockerfile.dev << 'EOF'
FROM ubuntu:24.04

RUN apt update && apt install -y \
    python3 python3-pip \
    nodejs npm \
    git curl wget \
    vim nano

WORKDIR /workspace

CMD ["/bin/bash"]
EOF

docker build -f $USB_MOUNT/Dockerfile.dev -t dev-env .
docker run -it --rm -v $USB_MOUNT/workspace:/workspace dev-env
```

### Docker Compose

```yaml
# $USB_MOUNT/docker-compose.yml
version: '3.8'

services:
  agent-alpha:
    image: ubuntu:24.04
    container_name: agent-alpha
    volumes:
      - ./agents/alpha:/workspace
      - ./global-deps:/global:ro
    environment:
      - AGENT_NAME=alpha
      - AGENT_HOME=/workspace
    mem_limit: 512m
    cpus: 1
    restart: unless-stopped

  agent-beta:
    image: ubuntu:24.04
    container_name: agent-beta
    volumes:
      - ./agents/beta:/workspace
      - ./global-deps:/global:ro
    environment:
      - AGENT_NAME=beta
      - AGENT_HOME=/workspace
    mem_limit: 512m
    cpus: 1
    restart: unless-stopped

  redis:
    image: redis:alpine
    container_name: message-queue
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: reverse-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped

volumes:
  redis-data:
```

```bash
# Start all services:
cd /media/ventoy-usb
docker-compose up -d

# View logs:
docker-compose logs -f

# Stop all services:
docker-compose down
```

## LXC/LXD Integration

### Installation

```bash
# Install LXD:
sudo snap install lxd
sudo lxd init  # Accept defaults

# Add user to lxd group:
sudo usermod -aG lxd $USER
newgrp lxd
```

### Container Management

```bash
# Create agent containers:
for agent in alpha beta gamma; do
    lxc launch ubuntu:24.04 agent-${agent}
    
    # Configure resource limits:
    lxc config set agent-${agent} limits.memory 512MB
    lxc config set agent-${agent} limits.cpu 1
    
    # Add storage device:
    lxc storage create agent-${agent}-storage dir \
        source=$USB_MOUNT/agents/${agent}
    lxc config device add agent-${agent} workspace disk \
        source=agent-${agent}-storage path=/workspace
done

# List containers:
lxc list

# Enter container:
lxc exec agent-alpha bash

# Stop container:
lxc stop agent-alpha

# Delete container:
lxc delete agent-alpha --force
```

### LXC Profiles

```bash
# Create agent profile:
lxc profile create agent-profile

# Configure profile:
lxc profile set agent-profile limits.memory 512MB
lxc profile set agent-profile limits.cpu 1

# Apply to container:
lxc profile add agent-alpha agent-profile
```

### LXC Networking

```bash
# Create isolated network for agents:
lxc network create agent-net bridge=true

# Attach containers to network:
for agent in alpha beta gamma; do
    lxc network attach agent-net agent-${agent} eth0
done
```

## Podman Integration

### Installation

```bash
# Install Podman (rootless Docker replacement):
sudo apt install podman podman-compose -y

# Verify installation:
podman --version
podman info
```

### Rootless Containers

```bash
# Run containers without root:
podman run -it --rm ubuntu:24.04 bash

# With user namespace mapping:
podman unshare cat /proc/self/uid_map

# Persistent storage:
podman run -it --rm \
    -v $USB_MOUNT/podman-storage:/storage \
    ubuntu:24.04 bash
```

### Podman Compose

```bash
# Use docker-compose.yml with Podman:
podman-compose up -d

# Or create podman-specific compose:
cat > $USB_MOUNT/podman-compose.yml << 'EOF'
version: '3.8'

services:
  agent-alpha:
    image: ubuntu:24.04
    container_name: agent-alpha
    volumes:
      - ./agents/alpha:/workspace
    environment:
      - AGENT_NAME=alpha
    command: sleep infinity

  agent-beta:
    image: ubuntu:24.04
    container_name: agent-beta
    volumes:
      - ./agents/beta:/workspace
    environment:
      - AGENT_NAME=beta
    command: sleep infinity
EOF

podman-compose up -d
```

## Container Security

### Resource Limits

```bash
# Docker:
docker run -d \
    --name secure-agent \
    --memory=512m \
    --cpus=1 \
    --pids-limit=100 \
    --read-only \
    --tmpfs /tmp:size=100M \
    ubuntu:24.04 sleep infinity

# LXC:
lxc config set secure-agent limits.memory 512MB
lxc config set secure-agent limits.cpu 1
lxc config set secure-agent security.nesting false
```

### Network Policies

```bash
# Docker network isolation:
docker network create --internal agent-net

# Run containers in isolated network:
docker run -d --name agent-alpha --network agent-net ubuntu:24.04 sleep infinity
docker run -d --name agent-beta --network agent-net ubuntu:24.04 sleep infinity

# Containers can communicate internally but not externally
```

### Image Scanning

```bash
# Scan images for vulnerabilities:
docker scout cves ubuntu:24.04

# Or use Trivy:
trivy image ubuntu:24.04
```

## Container Backup and Restore

### Docker Backup

```bash
# Backup container:
docker commit agent-alpha agent-alpha-backup
docker save agent-alpha-backup | gzip > agent-alpha-backup.tar.gz

# Restore container:
docker load < agent-alpha-backup.tar.gz
docker run -d --name agent-alpha agent-alpha-backup sleep infinity
```

### LXC Backup

```bash
# Backup container:
lxc export agent-alpha agent-alpha-backup.tar.gz

# Restore container:
lxc import agent-alpha-backup.tar.gz agent-alpha-restored
lxc start agent-alpha-restored
```

### Volume Backup

```bash
# Backup Docker volumes:
docker run --rm \
    -v agent-alpha-data:/data \
    -v $(pwd):/backup \
    ubuntu tar czf /backup/agent-alpha-data.tar.gz -C /data .

# Restore Docker volumes:
docker run --rm \
    -v agent-alpha-data:/data \
    -v $(pwd):/backup \
    ubuntu tar xzf /backup/agent-alpha-data.tar.gz -C /data
```
