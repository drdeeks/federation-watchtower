# Docker Management on USB Drives
## Table of Contents

- [Overview](#overview)
- [Use Cases](#use-cases)
- [Prerequisites](#prerequisites)
- [Docker Installation on USB](#docker-installation-on-usb)
- [Docker Volume Management on USB](#docker-volume-management-on-usb)
- [Docker Container Management on USB](#docker-container-management-on-usb)
- [Docker Compose on USB](#docker-compose-on-usb)
- [Docker Networking with USB](#docker-networking-with-usb)
- [Docker Security on USB](#docker-security-on-usb)
- [Docker Backup Strategies on USB](#docker-backup-strategies-on-usb)
- [Troubleshooting](#troubleshooting)
- [Performance Optimization](#performance-optimization)
- [References](#references)


## Overview

This guide covers using Docker containers and volumes on USB drives, including portable Docker installations, container management, and volume persistence.

## Use Cases

1. **Portable Docker Environment**: Run Docker containers from USB on any machine
2. **Development Workspace**: Persistent development containers on USB
3. **Data Processing**: Portable data pipelines with Docker
4. **Testing Lab**: Carry your test environment anywhere
5. **Backup Containers**: Portable backup solutions using Docker

## Prerequisites

- Docker installed on host system
- USB drive with sufficient space (32GB+ recommended)
- ext4 filesystem (recommended) or xfs
- Root/sudo access

## Docker Installation on USB

### Method 1: Portable Docker Installation

```bash
# Create Docker directory on USB
sudo mkdir -p /mnt/usb/docker/{bin,lib,etc,var}

# Download Docker static binaries
DOCKER_VERSION="24.0.7"
wget "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"
tar -xzf docker-*.tgz

# Copy binaries to USB
sudo cp docker/* /mnt/usb/docker/bin/
sudo chmod +x /mnt/usb/docker/bin/*

# Set up Docker daemon directory
sudo mkdir -p /mnt/usb/docker/var/lib/docker
```

### Method 2: Docker Data Directory on USB

```bash
# Stop Docker if running
sudo systemctl stop docker

# Move Docker data directory to USB
sudo mkdir -p /mnt/usb/docker-data
sudo rsync -avx /var/lib/docker/ /mnt/usb/docker-data/

# Create bind mount
sudo mkdir -p /var/lib/docker
sudo mount --bind /mnt/usb/docker-data /var/lib/docker

# Add to /etc/fstab for persistence
echo '/mnt/usb/docker-data /var/lib/docker none bind 0 0' | sudo tee -a /etc/fstab

# Start Docker
sudo systemctl start docker
```

### Method 3: Docker Desktop on USB

For Windows/Mac with Docker Desktop:
1. Install Docker Desktop on USB drive
2. Configure data directory to USB
3. Launch Docker Desktop from USB

## Docker Volume Management on USB

### Creating Volumes on USB

```bash
# Create volume with specific driver options
docker volume create \
  --driver local \
  --opt type=none \
  --opt device=/mnt/usb/docker-volumes/mydata \
  --opt o=bind \
  usb-volume

# List volumes
docker volume ls

# Inspect volume
docker volume inspect usb-volume
```

### Using Volumes in Containers

```bash
# Run container with USB volume
docker run -d \
  --name mycontainer \
  -v usb-volume:/data \
  nginx:latest

# Run with bind mount (direct USB path)
docker run -d \
  --name mycontainer \
  -v /mnt/usb/data:/data \
  nginx:latest
```

### Volume Backup and Restore

```bash
# Backup volume to USB
docker run --rm \
  -v usb-volume:/source:ro \
  -v /mnt/usb/backups:/backup \
  alpine tar czf /backup/volume-backup.tar.gz -C /source .

# Restore volume from backup
docker run --rm \
  -v usb-volume:/target \
  -v /mnt/usb/backups:/backup \
  alpine tar xzf /backup/volume-backup.tar.gz -C /target
```

## Docker Container Management on USB

### Running Containers from USB

```bash
# Run container with USB storage
docker run -d \
  --name portable-app \
  -v /mnt/usb/app-data:/app/data \
  -p 8080:80 \
  myapp:latest

# Run with multiple USB mounts
docker run -d \
  --name multi-storage \
  -v /mnt/usb/data1:/data1 \
  -v /mnt/usb/data2:/data2 \
  -v /mnt/usb/config:/config \
  myapp:latest
```

### Portable Container Management

```bash
# Save container state to USB
docker commit mycontainer /mnt/usb/containers/mycontainer-backup.tar

# Load container from USB
docker load -i /mnt/usb/containers/mycontainer-backup.tar

# Export container filesystem
docker export mycontainer > /mnt/usb/containers/mycontainer-export.tar

# Import container from USB
docker import /mnt/usb/containers/mycontainer-export.tar mycontainer:restored
```

### Container Lifecycle on USB

```bash
# Start stopped container
docker start mycontainer

# Stop container
docker stop mycontainer

# Restart container
docker restart mycontainer

# Remove container
docker rm mycontainer

# List all containers (including stopped)
docker ps -a
```

## Docker Compose on USB

### Portable Docker Compose Files

```yaml
# docker-compose.yml on USB at /mnt/usb/docker-compose.yml
version: '3.8'

services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
    volumes:
      - /mnt/usb/web-content:/usr/share/nginx/html
    restart: unless-stopped

  db:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: example
    volumes:
      - /mnt/usb/postgres-data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:alpine
    volumes:
      - /mnt/usb/redis-data:/data
    restart: unless-stopped
```

### Running Compose from USB

```bash
# Run compose stack from USB
cd /mnt/usb
docker-compose up -d

# Stop compose stack
docker-compose down

# View logs
docker-compose logs -f
```

## Docker Networking with USB

### Custom Network for USB Containers

```bash
# Create network for USB containers
docker network create usb-network

# Run containers on network
docker run -d \
  --name app1 \
  --network usb-network \
  -v /mnt/usb/app1-data:/data \
  myapp:latest

docker run -d \
  --name app2 \
  --network usb-network \
  -v /mnt/usb/app2-data:/data \
  myapp:latest

# Containers can now communicate via container names
docker exec app1 ping app2
```

### Exposing USB Container Services

```bash
# Expose service on host
docker run -d \
  --name webapp \
  -v /mnt/usb/webapp-data:/app/data \
  -p 8080:80 \
  -p 8443:443 \
  mywebapp:latest

# Access via http://localhost:8080
```

## Docker Security on USB

### Container Isolation

```bash
# Run with read-only filesystem (except volumes)
docker run -d \
  --name secure-container \
  --read-only \
  -v /mnt/usb/data:/data:rw \
  -v /tmp:/tmp:rw \
  myapp:latest

# Run with resource limits
docker run -d \
  --name limited-container \
  --memory=512m \
  --cpus=1.0 \
  -v /mnt/usb/data:/data \
  myapp:latest
```

### Volume Permissions

```bash
# Set ownership for container user
sudo chown -R 1000:1000 /mnt/usb/data

# Set permissions
sudo chmod -R 755 /mnt/usb/data

# Run container with specific user
docker run -d \
  --name user-container \
  --user 1000:1000 \
  -v /mnt/usb/data:/data \
  myapp:latest
```

## Docker Backup Strategies on USB

### Full Backup

```bash
# Backup all Docker data
tar -czf /mnt/usb/docker-backup-$(date +%Y%m%d).tar.gz \
  -C /var/lib/docker \
  .

# Backup specific volumes
for vol in $(docker volume ls -q); do
  docker run --rm \
    -v "$vol":/source:ro \
    -v /mnt/usb/backups:/backup \
    alpine tar czf "/backup/$vol-$(date +%Y%m%d).tar.gz" -C /source .
done
```

### Incremental Backup

```bash
# Using rsync for incremental backup
rsync -av --delete \
  /var/lib/docker/ \
  /mnt/usb/docker-backup/

# Backup Docker images
docker images -q | while read img; do
  docker save "$img" | gzip > "/mnt/usb/images/$img-$(date +%Y%m%d).tar.gz"
done
```

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Container won't start | Insufficient space | Check USB space with `df -h` |
| Slow performance | USB 2.0 or slow drive | Use USB 3.0+ with fast drive |
| Permission denied | Wrong ownership | `chown` USB directories |
| Volume not mounting | Wrong path | Verify mount point exists |
| Container can't access USB | Missing mount | Add `-v` flag with USB path |
| Docker daemon won't start | Corrupted installation | Reinstall Docker on USB |

## Performance Optimization

### USB Drive Selection
- Use USB 3.1/3.2 drives for best performance
- SSD-based USB drives recommended
- Avoid cheap, slow USB drives

### Docker Configuration
```bash
# Optimize Docker daemon
cat > /etc/docker/daemon.json <<EOF
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
```

### Container Optimization
- Use multi-stage builds to reduce image size
- Minimize layers
- Use `.dockerignore` to exclude unnecessary files
- Use Alpine-based images when possible

## References

- Docker Documentation: https://docs.docker.com
- Docker Volumes: https://docs.docker.com/storage/volumes/
- Docker Compose: https://docs.docker.com/compose/
- Docker Security: https://docs.docker.com/engine/security/
