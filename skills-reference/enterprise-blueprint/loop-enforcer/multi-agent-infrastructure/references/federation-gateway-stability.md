# Federation Gateway Server Stability — Reference for Multi-Agent Infrastructure

## Context
Session: Building autonomous-federation server on port 41207 for hackathon-2026.
Date: 2026-07-04
Related: This complements the port manager in `agent_port_manager.py`

## Key Distinction: Federation Gateway vs. Agent Ports

The **federation gateway** (port 41207) is a **single shared coordination server** — NOT per-agent ports.
- One port for all agents to discover projects, join, and communicate
- Different from `AgentPortManager` which allocates unique ports per agent

## Server Stability Patterns

### Persistent Server (No Timeout)
```bash
# CORRECT - runs indefinitely
cd /path/to/federation && node server.js 2>&1 &

# WRONG - kills after timeout (exit 124)
timeout 300 node server.js
```

### Port Conflict Resolution (EADDRINUSE)
```bash
# Always run before starting
pkill -f "node server.js" 2>/dev/null
lsof -ti :41207 2>/dev/null | xargs -r kill -9 2>/dev/null
sleep 2
```

### Health Verification
```bash
# Wait for server, then verify
sleep 3 && curl -s http://localhost:41207/health
# Must return: {"status":"healthy",...}
```

## Background Process Management
- Use `background=true` + `notify_on_complete=true` for persistent servers
- `timeout` is for batch jobs only, not servers
- Process list via `process(action="list")` to track PIDs
- Logs via `process(action="log", session_id="...")` for debugging

## Common Failure Modes
| Symptom | Cause | Fix |
|---------|-------|-----|
| exit 124 | `timeout` killed server | Remove timeout |
| exit 143 | SIGTERM (pkill) | Expected during restart |
| exit 1 | Unhandled error (EADDRINUSE) | Run port cleanup first |
| exit 7 | curl "Failed to connect" | Server not running or wrong port |

## Mandatory Endpoints for Federation Skills
Every federation server template must implement:
- `GET /health` — fast liveness check
- `GET /api/blueprints` — project discovery
- `POST /api/join` — MCP agent registration
- `POST /api/assign-work` — task routing
- `GET /api/projects/:id/status` — project health
- `GET /api/stats` — federation metrics
- `GET /api/memory/*` — 4-layer memory access
- `WS /<agentId>` — real-time communication

## Integration with Port Manager
The federation gateway uses a **fixed well-known port** (41207) for discovery.
Individual agents should use `AgentPortManager` for their own service ports.
This avoids the "port collision" problem where multiple agents try to use the same discovery port.

```python
# Federation gateway: fixed port 41207 (well-known)
# Individual agents: allocated via AgentPortManager
pm = AgentPortManager()
agent_ports = pm.allocate_ports_for_agent('autopilot-agent', 'autopilot')
# Returns: {'webhook': 8081, 'api': 8082, 'communication': 8083, 'llm_proxy': 8084}
```