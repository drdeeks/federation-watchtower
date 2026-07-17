# OpenClaw Gateway Authentication & Configuration

## Overview
The OpenClaw Gateway authentication system and MCP (Model Context Protocol) loopback server configuration for Hemlock Minimal.

## Authentication Modes

### Gateway Auth (`--auth`)
- `--auth none`: Disables auth for main gateway endpoints only
- `--auth token`: Requires `Authorization: Bearer *** header
- **Loopback auth separate**: MCP loopback server has its own auth (always on)

### Gateway Configuration
```json
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "token": "test-token-12345"
  },
  "mcp": {
    "servers": {
      "hemlock-mcp": {
        "command": "python3",
        "args": ["-m", "mcp_bridge"],
        "transport": "stdio"
      }
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/workspace",
      "skills": []
    },
    "allowUnconfigured": true
  },
  "channels": {
    "telegram": {
      "accounts": {},
      "defaultAccount": ""
    },
    "imessage": {
      "enabled": false
    }
  },
  "bindings": [],
  "dmPolicy": "pairing"
}
```

## MCP Loopback Server Behavior

### Port Allocation
- Random port assigned on each gateway startup (e.g., 41213, 39925, 43247)
- Port logged in gateway stdout: `MCP loopback server listening on http://127.0.0.1:<port>/mcp`
- Port changes on every gateway restart

### Authentication
- **Always required** for loopback despite `--auth none`
- Token generated via `crypto.randomBytes(32)` on each gateway restart
- Token stored in `/workspace/gateway/.token`
- Validation requires `Authorization: Bearer *** header

### Token Management
- Token changes on every gateway restart
- Generated via `crypto.randomBytes(32)` 
- Not stored in config, only in memory/logs
- Must read from `/workspace/gateway/.token` or gateway logs

## MCP Bridge Architecture

```
External Request (port 18789)
         ↓
OpenClaw Gateway (auth: none for /health, token for /mcp)
         ↓
MCP Proxy (port 41214) - auto-detects loopback port
         ↓
MCP Loopback Server (random port, e.g., 43247) - requires auth
         ↓
MCP Bridge (stdio) → Hermes Agent Runtime
```

## Authentication Flow

### Main Gateway Endpoints
- `/health` - No auth required (`--auth none`)
- `/mcp` - Requires `Authorization: Bearer *** header
- Other endpoints - Depends on `--auth` mode

### MCP Loopback
- **Always requires auth** regardless of gateway `--auth` setting
- Token = gateway config `token` value
- Must use `Authorization: Bearer *** header

## Gateway Configuration for Hemlock Minimal

### docker-compose.yml
```yaml
command:
  - /opt/openclaw/bin/openclaw-container
  - gateway
  - run
  - --allow-unconfigured
  - --auth
  - none
  - --token
  - test-token-12345
  - --port
  - "18789"
  - --bind
  - lan
```

### hemlock.json (auto-generated)
```json
{
  "gateway": {"port": 18789, "mode": "local", "token": "test-token-12345"},
  "mcp": {"servers": {"hemlock-mcp": {"command": "python3", "args": ["-m", "mcp_bridge"], "transport": "stdio"}}},
  "agents": {"defaults": {"workspace": "/workspace", "skills": []}, "allowUnconfigured": true}
}
```

## MCP Proxy HTTP Server

### Purpose
Bridges external `/mcp` requests (port 41214) to internal MCP loopback server.

### Auto-Detection Logic
```python
async def find_mcp_port():
    # 1. Parse gateway logs for "MCP loopback server listening on http://127.0.0.1:<port>/mcp"
    # 2. Use LAST match (most recent gateway restart)
    # 3. Fallback: scan ports 41000-42000 for responding MCP endpoint
```

### Proxy Server (port 41214)
```python
class MCPProxy:
    async def handle_mcp(self, request):
        # Forward requests to internal loopback with auth headers
        async with aiohttp.ClientSession() as session:
            async with session.post(target_url, data=body, headers=headers) as resp:
                return web.Response(body=await resp.read(), status=resp.status)
```

## Common Failures & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `{"error":"unauthorized"}` on MCP | Loopback auth required | Use `Authorization: Bearer *** header |
| MCP port unreachable | Internal loopback only | Use proxy (port 41214) or test from container |
| Token mismatch | Gateway restarted | Re-read token from `/workspace/gateway/.token` |
| Loopback port changes | Gateway restart | Proxy auto-detects new port from logs |

## Testing MCP Access

### From Host (via Proxy)
```bash
curl -X POST http://localhost:41214/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token-12345" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}'
```

### From Container (Direct to Loopback)
```bash
# Find current loopback port
grep "MCP loopback server listening" /tmp/openclaw/openclaw-*.log | tail -1

# Test directly (requires token)
curl -X POST http://127.0.0.1:<port>/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}'
```

### Gateway Health
```bash
curl http://localhost:18789/health
# {"ok":true,"status":"live"}
```

## Key Files

| File | Purpose |
|------|---------|
| `/workspace/gateway/hemlock.json` | Gateway config |
| `/workspace/gateway/.token` | Loopback token |
| `/tmp/openclaw/openclaw-*.log` | Gateway logs (MCP port) |
| `/var/log/drdeeks-pull.log` | Daily skills pull log |
| `/var/log/drdeeks-cron.log` | Cron execution log |

## Session 2026-06-13 Learnings

1. **`--auth none` only disables main gateway auth** - loopback auth always required
2. **Loopback port random each restart** - proxy must auto-detect
3. **Token changes every restart** - read from `.token` file or logs
4. **Proxy port fixed (41214)** - external access point
5. **MCP loopback port random** (41000-42000 range)
5. **`--auth none` only affects main gateway** - loopback auth independent
6. **Token in `/workspace/gateway/.token`** - read for auth
7. **Proxy auto-detects** from gateway logs (use LAST match)
7. **Proxy port fixed at 41214** - stable external access
8. **Test from container** - loopback not exposed externally