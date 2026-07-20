---
name: tv-sitcom-mcp
description: MCP server exposing the agent TV room as an external API. Provides real-time
  agent/room/feed access for any company integrating agent TV into their business.
version: 1.1.2
license: MIT
metadata:
  category: devops
  tags:
  - monitoring
  - live-data
  - mcp
  - tv-room
  - agent-monitoring
  - external-api
  - federation
  depends_on:
  - autonomous-crew
  provides:
  - tv-room-mcp
  - agent-feed-api
  - room-status-api
  - project-summary-api
  - system-status-api
  compatible_with:
  - openclaw-gateway
  - hermes-agent
  - any-mcp-client
---

# TV Sitcom Show MCP Server

## Overview

Exposes the agent TV room as an MCP (Model Context Protocol) server. Any company can connect via standard MCP clients to get **real-time** agent feeds, room status, project summaries, and system health — backed by the live Hemlock Enterprise Federation Gateway (port 41207).

**Data is live:** All tools query the federation REST API (`/api/agents`, `/api/rooms`, `/health`) and WebSocket feed. No synthetic/mock data.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL COMPANY                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  MCP Client │  │  MCP Client │  │  MCP Client │             │
│  │ (Dashboard) │  │ (Alerting)  │  │ (Analytics) │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          ▼                                        │
│              ┌─────────────────────────┐                         │
│              │      MCP Transport      │                         │
│              │  (Streamable-HTTP/WS)   │                         │
│              └───────────┬─────────────┘                         │
└──────────────────────────┼──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              TV Sitcom Show MCP Server (41208)                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  FastMCP + FederationClient → Federation Gateway (41207) │   │
│  └─────────────────────────────────────────────────────────┘   │
└──────────────────────────┼──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              Hemlock Enterprise Federation Gateway              │
│  5 Projects | 5+ Rooms | 20+ Agents | Real-time WebSocket      │
└─────────────────────────────────────────────────────────────────┘
```

## MCP Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `get_all_rooms` | All production rooms across 5 projects with agent counts | — |
| `get_room` | Detailed room view with all agents | `room_id: string` |
| `get_tv_feed` | Live agent activity feed (registration + heartbeats) | `limit?`, `project?`, `priority?` |
| `get_agent` | Agent profile by ID | `agent_id: string` |
| `get_project_summary` | Project stats (rooms, agents, utilization) | `project: string` |
| `get_system_status` | Global health & stats | — |
| `search_agents` | Search by name/role/project | `query: string` |
| `register_agent` | Register new agent with federation | `project_id`, `agent_id`, `name`, `role`, `capabilities?` |

## MCP Resources

| Resource | Description |
|----------|-------------|
| `config://projects` | Project metadata (name, emoji, color) |
| `config://rooms` | Room schema (max 35/room, 5 projects) |
| `status://federation` | Live federation health |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/tv_mcp_server.py` | Main MCP server (FastMCP + live federation client) |
| `scripts/start-tv-mcp.sh` | Production launcher (waits for federation, seeds agents) |
| `scripts/test_tv_mcp.py` | Validation suite (federation client, room manager, MCP tools) |

## References

| Document | Description |
|----------|-------------|
| `references/architecture.md` | Data flow, tool→endpoint mapping |
| `references/api-reference.md` | Full federation REST + WS API |
| `references/integration.md` | External org integration guide |
| `references/deployment.md` | Docker, systemd, env vars |
| `references/mcp-protocol.md` | MCP compliance, tools, resources, notifications |
| `references/troubleshooting.md` | Common issues & fixes |

## External Integration Examples

### Dashboard via MCP (Python)

```python
from mcp.client import Client

async def get_live_feed():
    async with Client("http://localhost:41208/mcp") as client:
        return await client.call_tool("get_tv_feed", {"limit": 100, "priority": "high"})
```

### Alerting System

```python
async def check_critical_errors():
    feed = await get_tv_feed(priority="high", limit=50)
    errors = [f for f in feed if f["event_type"] == "error"]
    if errors:
        await send_alert(errors)
```

### Direct REST (No MCP)

```bash
# Federation health
curl http://federation:41207/health

# All agents
curl http://federation:41207/api/agents

# Register agent
curl -X POST http://federation:41207/api/agents/register \
  -H 'Content-Type: application/json' \
  -d '{"projectId":"my-project","agentId":"my-agent","name":"My Agent","role":"worker"}'

# WebSocket real-time
ws = new WebSocket('ws://federation:41207/ws?projectId=my-project')
ws.onmessage = (e) => console.log(JSON.parse(e.data))
```

## Multi-Org Deployment

Each organization gets their own `projectId` namespace. Projects are isolated — agents in project A never see project B's rooms or feeds. The federation gateway enforces this at the registry level.

## Deployment

### Docker

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 41208
CMD ["python", "scripts/tv_mcp_server.py", "--federation", "http://federation:41207"]
```

### Systemd

```ini
[Unit]
Description=TV Sitcom MCP Server
After=network.target

[Service]
Type=simple
User=agent
WorkingDirectory=/opt/tv-sitcom-mcp
ExecStart=/opt/tv-sitcom-mcp/.venv/bin/python scripts/tv_mcp_server.py --federation http://localhost:41207
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TV_MCP_PORT` | 41208 | MCP server port |
| `TV_MCP_HOST` | 0.0.0.0 | Bind host |
| `FEDERATION_URL` | http://localhost:41207 | Federation gateway |

## Security

- No authentication built-in (add reverse proxy for auth)
- Read-mostly API (`register_agent` is the only mutating operation)
- Rate limit at reverse proxy level
- Internal network only by default

## Free-First

| Tier | Cost | Stack |
|------|------|-------|
| Free | $0/mo | Python 3.12+ stdlib + fastmcp (pip install) |
| Paid | None required | — |

## Verification

Run the test suite against a live federation:

```bash
cd ${TV_VAULT_PATH:-$HOME}/.hermes/skills/devops/tv-sitcom-mcp
python3 scripts/test_tv_mcp.py
```

Expected: all tests pass against the 20 real agents across 5 projects.