# USB Deployment with Ventoy

## Overview
Hemlock Minimal includes a complete Ventoy-compatible USB deployment package. Ventoy is a multiboot USB tool that lets you boot multiple ISOs from a single USB drive — perfect for deploying Hemlock on any target machine.

## USB Structure

```
/media/usb/hemlock-deploy/
├── hemlock-images.tar              # docker save: base + runtime images
├── volumes/
│   ├── hemlock-gateway.tar.gz      # Gateway config + token
│   ├── hemlock-agents.tar.gz       # All agent volumes
│   ├── hemlock-crews.tar.gz        # All crew volumes
│   ├── hemlock-config.tar.gz       # Shared config
│   ├── hemlock-shared-skills.tar.gz # /skills volume (100+ skills)
│   ├── hemlock-projects.tar.gz
│   ├── hemlock-memory.tar.gz
│   ├── hemlock-backups.tar.gz
│   ├── hemlock-plugins.tar.gz
│   ├── hemlock-models.tar.gz
│   └── hemlock-logs.tar.gz
├── deploy.sh                        # One-command deploy script
├── docker-compose.yml               # Runtime compose
├── entrypoint.sh                    # Entrypoint for inspection
├── README_USB.md                    # USB-specific instructions
├── HARNESS_HIERARCHY.md             # Architecture preservation guide
└── skills-source/                   # Optional: .skill files for re-population
    ├── skill-installer.skill
    ├── enterprise-blueprint.skill
    └── ... (all .skill files)
```

## Creating the USB Package

```bash
# On builder machine (where Hemlock is running)
cd /home/ubuntu/hemlock-minimal
./scripts/create-usb-image.sh /media/usb/hemlock-deploy
```

## deploy.sh (Auto-generated)

```bash
#!/usr/bin/env bash
# 1. Load Docker images
docker load -i hemlock-images.tar

# 2. Create all volumes
for vol in hemlock-gateway hemlock-agents hemlock-crews hemlock-shared-skills \
           hemlock-projects hemlock-config hemlock-logs hemlock-memory \
           hemlock-backups hemlock-plugins hemlock-models; do
    docker volume create "$vol"
    docker run --rm -v "$vol:/dst" -v "$(pwd)/volumes:/src" alpine \
        tar -xzf "/src/${vol}.tar.gz" -C /dst
done

# 3. iMessage (if configured)
if [[ -n "${IMRSG_REMOTE_HOST}" ]]; then
    mkdir -p /workspace/scripts
    cat > /workspace/scripts/imsg-ssh <<'EOF'
#!/usr/bin/env bash
exec ssh -T "$IMRSG_REMOTE_HOST" imsg "$@"
EOF
    chmod +x /workspace/scripts/imsg-ssh
    mkdir -p /home/agent/.ssh
    touch /home/agent/.ssh/known_hosts
fi

# 4. Deploy
docker compose up -d

# 5. Verify
timeout 5 bash -c '</dev/tcp/localhost/18789'
```

## Ventoy Persistence (Instant Restart)

For instant Hemlock restarts across reboots:

1. **Ventoy USB** → Select "Ubuntu with persistence" at boot menu
2. **First boot**: Runs `deploy.sh` → builds volumes in `/var/lib/docker`
3. **Subsequent boots**: `/var/lib/docker` persists → Hemlock starts instantly

**Persistence file**: `/ventoy/persistence.img` mounted at `/var/lib/docker`

## Target Machine Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Linux with Docker 24+ |
| **Docker Compose** | `docker-compose-plugin` or standalone |
| **RAM** | 4GB+ recommended |
| **Disk** | 20GB+ free for volumes |
| **iMessage (optional)** | Mac host with `imsg` + SSH access |

## create-usb-image.sh Details

The script:
1. `docker save hemlock/base:latest hemlock/runtime:latest -o hemlock-images.tar`
2. Backs up ALL 12 volumes to `volumes/*.tar.gz`
3. Copies `docker-compose.yml`, `entrypoint.sh`, `deploy.sh`, `README_USB.md`, `HARNESS_HIERARCHY.md`
4. Optional: Copies `.skill` files to `skills-source/` for re-population

## HARNESS_HIERARCHY.md

The USB package includes `HARNESS_HIERARCHY.md` documenting the architecture invariant:

```
OpenClaw Gateway (PID 1, Control Plane)
    ├── Channel Adapters: Telegram, iMessage (via SSH), etc.
    ├── MCP Provider: spawns stdio servers
            ↓
Hermes Agent Runtime (Cognition Plane) — ONLY as MCP servers
    ├── AIAgent Loop, Memory, Tools
    └── MCP Server (stdio)
            ↓
Agent Volumes (Isolation Plane)
    ├── hemlock-agent-<id>/
    ├── hemlock-crew-<name>/
    └── hemlock-shared-skills/ → /skills (read-only)
```

**Validation Commands**:
```bash
# Verify Gateway PID
docker exec hemlock-runtime ps -p 1 -o comm=

# Verify MCP servers = agents
docker exec hemlock-runtime ps aux | grep mcp_bridge

# Verify no bind mounts
docker inspect hemlock-runtime | jq '.[0].Mounts[] | select(.Type=="bind")'
```

## Customization

To customize the USB build, edit `create-usb-image.sh` or add files to the project root before running it.

## Emergency Manual Deploy

If `deploy.sh` fails:
```bash
docker load -i hemlock-images.tar
for vol in ...; do
    docker volume create "$vol"
    docker run --rm -v "$vol:/dst" -v "$PWD/volumes:/src" alpine \
        tar -xzf "/src/${vol}.tar.gz" -C /dst
done
docker compose up -d
```

## Reference

- **Ventoy**: https://www.ventoy.net
- **Ventoy Persistence**: https://www.ventoy.net/en/doc_persistence.html