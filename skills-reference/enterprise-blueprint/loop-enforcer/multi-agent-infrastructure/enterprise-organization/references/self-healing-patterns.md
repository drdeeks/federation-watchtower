# Self-Healing Patterns Reference

## MCP Proxy Manager (mcp_proxy_manager.py)

### Architecture
- **Auto-detection**: Parses gateway logs for MCP loopback port
- **Proxy forwarding**: Forwards `/mcp` requests to internal loopback
- **Health endpoint**: `/mcp/health` for monitoring
- **Auto-restart**: Restarts on gateway restart (detects port change)

### Key Components

```python
class MCPProxyManager:
    def __init__(self):
        self.proxy_port = 41214
        self.target_port = None
        self.failure_count = 0
        
    async def find_mcp_port(self):
        # 1. Parse gateway logs for "MCP loopback server listening on http://127.0.0.1:<port>/mcp"
        # 2. Use LAST match (most recent gateway restart)
        # 3. Fallback: scan ports 41000-42000
        
    async def start_proxy(self):
        # Generate proxy script with detected port
        # Start aiohttp server on 41214
        # Forward /mcp requests to target_port
        
    async def health_check(self):
        # Check gateway health (port 18789)
        # Check proxy health (port 41214)
        # Restart proxy if >3 failures
```

### Health Checks
```bash
# Gateway health
curl http://localhost:18789/health
# {"ok":true,"status":"live"}

# Proxy health
curl http://localhost:41214/mcp/health
# {"ok":true,"status":"proxy_ready","target":"http://127.0.0.1:43247/mcp"}
```

### Failure Handling
| Failure Type | Detection | Recovery |
|--------------|-----------|----------|
| Proxy crash | Process exit | Restart proxy (max 5/min) |
| Gateway restart | Port change detected | Re-detect port, restart proxy |
| Gateway down | Health check fail | Alert, retry every 5s |
| Port scan fail | No responding MCP port | Scan 41000-42000 range |

## Systemd Service

```ini
[Unit]
Description=Hemlock MCP Proxy Manager
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/ubuntu/hemlock-minimal/scripts/mcp_proxy_manager.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
```

### Service Commands
```bash
# Install
sudo cp mcp-proxy-manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable hemlock-mcp-proxy-manager
sudo systemctl start hemlock-mcp-proxy-manager

# Status
systemctl status hemlock-mcp-proxy-manager
journalctl -u hemlock-mcp-proxy-manager -f

# Logs
journalctl -u hemlock-mcp-proxy-manager --since "1 hour ago"
```

## Container Cron Self-Healing

### Daily Skills Pull (pull-drdeeks-daily.sh)
```bash
#!/bin/bash
# Runs at 2 AM daily via cron
# Clones if missing, otherwise git pull

SKILLS_DIR="/home/ubuntu/hemlock-minimal/hemlock-minimal/skills/drdeeks"
LOG_FILE="/var/log/drdeeks-pull.log"

if [ -d "$SKILLS_DIR/.git" ]; then
    cd "$SKILLS_DIR" && git pull origin main
else
    git clone --depth 1 https://github.com/drdeeks/skills.git "$SKILLS_DIR"
fi
```

### Container Init Script (container-init.sh)
- Runs on container startup via entrypoint.sh
- Installs cron if missing
- Adds daily pull to crontab
- Starts cron daemon

### Crontab Entry (Inside Container)
```bash
0 2 * * * /home/ubuntu/hemlock-minimal/scripts/pull-drdeeks-daily.sh >> /var/log/drdeeks-cron.log 2>&1
```

## Gateway Restart Handling

### Problem
Gateway restarts → MCP loopback port changes → Proxy breaks

### Solution: Auto-reconnect
```python
async def monitor_loop():
    while True:
        await asyncio.sleep(5)
        new_port = await find_mcp_port()
        if new_port and new_port != current_port:
            await restart_proxy(new_port)
```

### Log Detection
```python
# Gateway log pattern
pattern = r'MCP loopback server listening on http://127\.0\.0\.1:(\d+)/mcp'
matches = re.findall(pattern, log_content)
latest_port = int(matches[-1])  # LAST match = most recent
```

## Health Check Endpoints

| Endpoint | Purpose | Expected Response |
|----------|---------|-------------------|
| `GET /health` | Gateway health | `{"ok":true,"status":"live"}` |
| `GET /mcp/health` | Proxy health | `{"ok":true,"status":"proxy_ready"}` |
| `GET /mcp/health?verbose` | Detailed status | Includes target port, uptime |

## Monitoring Commands

```bash
# Check proxy status
systemctl status hemlock-mcp-proxy-manager

# View proxy logs
journalctl -u hemlock-mcp-proxy-manager -f

# Check cron status
systemctl status cron
crontab -l

# View cron logs
tail -f /var/log/drdeeks-cron.log

# Check gateway logs
docker logs hemlock-runtime --tail 50

# Manual port detection
grep "MCP loopback server listening" /tmp/openclaw/openclaw-*.log | tail -1
```