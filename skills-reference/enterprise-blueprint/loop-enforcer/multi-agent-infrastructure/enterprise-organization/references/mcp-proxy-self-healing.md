# MCP Proxy Manager with Self-Healing

## Overview
Self-healing HTTP proxy that bridges external MCP requests to OpenClaw's internal MCP loopback server. Auto-detects loopback port changes and restarts on failure.

## Architecture

### Components
```
External Client (port 41214)
         ↓
MCP Proxy Manager (Python aiohttp)
         ↓
OpenClaw Gateway MCP Loopback (random port: 41000-42000)
         ↓
MCP Bridge (stdio) → Hermes Agent Runtime
```

### Port Allocation
| Component | Port | Notes |
|-----------|------|-------|
| Gateway | 18789 | External access |
| MCP Proxy | 41214 | Fixed, external access |
| MCP Loopback | 41000-42000 | Random, per-restart |
| Gateway Health | 18789 | `/health` endpoint |

## Implementation

### mcp_proxy_manager.py (Systemd Service)
```python
#!/usr/bin/env python3
"""MCP Proxy Manager - Self-healing, auto-starting MCP proxy with graceful shutdown."""

import asyncio
import json
import logging
import re
import sys
from pathlib import Path
import aiohttp
from aiohttp import web

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
MCP_PROXY_PORT = 41214

async def find_mcp_port():
    """Find the MCP loopback port from gateway logs."""
    log_dir = Path("/tmp/openclaw")
    log_files = sorted(log_dir.glob("openclaw-*.log"), key=lambda f: f.stat().st_mtime, reverse=True)
    
    for log_file in log_files[:10]:
        try:
            content = log_file.read_text()
            matches = re.findall(r'MCP loopback server listening on http://127\.0\.0\.1:(\d+)/mcp', content)
            if matches:
                return int(matches[-1])  # LAST match = most recent
        except:
            pass
    
    # Fallback: port scan
    for port in range(41000, 42000):
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(f'http://127.0.0.1:{port}/mcp',
                    json={"jsonrpc": "2.0", "method": "tools/list", "params": {}, "id": 1},
                    timeout=aiohttp.ClientTimeout(total=0.5)) as resp:
                    if resp.status in (200, 401):
                        return port
        except:
            pass
    return None

class MCPProxy:
    def __init__(self, target_port):
        self.target_port = target_port
        self.target_url = f'http://127.0.0.1:{target_port}/mcp'
    
    async def handle_mcp(self, request):
        try:
            body = await request.read()
            headers = dict(request.headers)
            headers.pop('host', None)
            async with aiohttp.ClientSession() as session:
                async with session.post(self.target_url, data=body, headers=headers,
                    timeout=aiohttp.ClientTimeout(total=30)) as resp:
                    return web.Response(body=await resp.read(), status=resp.status,
                        headers=dict(resp.headers))
        except Exception as e:
            logger.error(f"Proxy error: {e}")
            return web.Response(text=json.dumps({"error": "proxy_error", "message": str(e)}),
                status=502, content_type='application/json')
    
    async def health(self, request):
        return web.json_response({"ok": True, "status": "proxy_ready", "target": self.target_url})

async def main():
    mcp_port = await find_mcp_port()
    if not mcp_port:
        sys.exit(1)
    
    proxy = MCPProxy(mcp_port)
    app = web.Application()
    app.router.add_post('/mcp', proxy.handle_mcp)
    app.router.add_get('/mcp/health', proxy.health)
    app.router.add_post('/mcp/', proxy.handle_mcp)
    
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '0.0.0.0', 41214)
    await site.start()
    logger.info(f"MCP Proxy running on port 41214, forwarding to port {mcp_port}")
    
    try:
        while True:
            await asyncio.sleep(60)
            new_port = await find_mcp_port()
            if new_port and new_port != proxy.target_port:
                proxy.target_port = new_port
                proxy.target_url = f'http://127.0.0.1:{new_port}/mcp'
                logger.info(f"MCP port changed to {new_port}")
    except KeyboardInterrupt:
        pass
    finally:
        await runner.cleanup()

if __name__ == '__main__':
    asyncio.run(main())
```

### Systemd Service
```ini
[Unit]
Description=Hemlock MCP Proxy Manager
After=docker.service
Requires=docker.service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/ubuntu/hemlock-minimal/scripts/mcp_proxy_manager.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Container Init Integration
```bash
# In entrypoint.sh - call container-init.sh before gateway startup
# ============================================================================
# CONTAINER INITIALIZATION
# ============================================================================
/home/ubuntu/hemlock-minimal/scripts/container-init.sh

# ============================================================================
# GATEWAY INITIALIZATION (Hemlock Gateway)
# ============================================================================
```

### container-init.sh
```bash
#!/bin/bash
# Container initialization - sets up daily cron job for drdeeks skills pull

set -e

# Install cron if not present
if ! command -v cron &> /dev/null; then
    apt-get update && apt-get install -y cron 2>/dev/null | tail -5
fi

# Create crontab entry for daily pull at 2 AM
CRON_JOB="0 2 * * * /home/ubuntu/hemlock-minimal/scripts/pull-drdeeks-daily.sh >> /var/log/drdeeks-cron.log 2>&1"

if ! crontab -l 2>/dev/null | grep -q "pull-drdeeks-daily.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Added daily drdeeks pull cron job (2 AM daily)"
fi

# Start cron daemon
service cron start 2>/dev/null || cron

echo "Container initialization complete - drdeeks daily pull scheduled"
```

## Self-Healing Features

### 1. Auto-Detection of Port Changes
- Monitors gateway logs for new MCP loopback port
- Uses LAST log match (most recent gateway restart)
- Updates target URL without restarting proxy

### 2. Auto-Restart on Failure
- Systemd `Restart=on-failure` with `RestartSec=5`
- Logs to journald for debugging
- Health endpoint `/mcp/health` for monitoring

### 3. Graceful Shutdown
- Saves state on SIGTERM
- Closes aiohttp connections cleanly
- Flushes logs

### 4. Port Re-Detection
```python
while True:
    await asyncio.sleep(60)
    new_port = await find_mcp_port()
    if new_port and new_port != proxy.target_port:
        proxy.target_port = new_port
        proxy.target_url = f'http://127.0.0.1:{new_port}/mcp'
```

## Systemd Service Management

```bash
# Install service
sudo cp hemlock-mcp-proxy-manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable hemlock-mcp-proxy-manager
sudo systemctl start hemlock-mcp-proxy-manager

# Check status
systemctl status hemlock-mcp-proxy-manager

# View logs
journalctl -u hemlock-mcp-proxy-manager -f
```

## Health Check
```bash
# Proxy health
curl http://localhost:41214/mcp/health
# {"ok":true,"status":"proxy_ready","target":"http://127.0.0.1:43247/mcp"}

# MCP via proxy
curl -X POST http://localhost:41214/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer *** \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}'
```

## Log Rotation
```
/var/log/mcp-proxy.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
```

## Key Learnings (Session 2026-06-13)

1. **Gateway logs are the source of truth** for MCP port detection
2. **LAST log match** = most recent gateway restart
3. **Proxy port fixed** (41214) for stable external access
3. **Loopback port random** (41000-42000) per gateway restart
4. **Auto-detection** uses gateway logs (LAST match) + fallback port scan
5. **Systemd restart** handles crashes gracefully
6. **Health endpoint** for monitoring
7. **Log to journald** for systemd integration
8. **60-second re-check** for port changes
8. **Log to journald** for systemd integration (not file)
9. **60-second re-check** for port changes after gateway restart