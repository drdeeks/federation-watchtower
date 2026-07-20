# Federation Gateway + TV Command Center Integration

## Architecture (Validated 2026-07-09)

The Hemlock Enterprise system has a complete **live agent TV wall** that was shadowed by a stale server:

```
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL INTEGRATION                         │
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

## The Blocker (Fixed)
**Port 41207 conflict** — the old `hackathon-2026/federation-server` (1 test-agent, 3 stale blueprints) was holding the port, preventing the correct `qwen-cloud-2026/federation/server.js` from starting.

**Fix**: Kill stale server → start correct federation → serve `index.html` static.

## Components

### 1. Federation Gateway (`qwen-cloud-2026/federation/server.js`)
- **Port**: 41207
- **API**: REST + WebSocket (`ws://localhost:41207/ws?projectId=<project>`)
- **Projects**: mnemosyne, autopilot, aires, agora, edgewalker (pre-configured)
- **Auto-seed**: `start-federation.sh` registers 20 crew agents on startup

### 2. TV Command Center (`qwen-cloud-2026/index.html`)
- **Port**: 8081 (static serve)
- **Connects**: `ws://localhost:41207/ws?projectId=all`
- **Features**: CRT retro UI, 6 tabs (Master + 5 projects), live feed, room view

### 3. tv-sitcom-mcp (`$HOME/.hermes/skills/devops/tv-sitcom-mcp`)
- **Port**: 41208 (MCP Streamable-HTTP)
- **Tools**: 8 live tools backed by federation REST
- **Resources**: 3 (projects config, rooms schema, federation status)
- **v1.1.1**: Rewired from synthetic mock → live federation client

## Agent Registration
```bash
# POST /api/agents/register
{
  "projectId": "mnemosyne",
  "agentId": "mnemosyne-lead-1",
  "name": "MemoryAgent Lead",
  "role": "lead",
  "capabilities": ["orchestration", "memory"]
}
```
Auto-generates SVG avatar, assigns to room (35/room overflow), broadcasts via WebSocket.

## Multi-Org Pattern
Each org gets their own `projectId` namespace. Projects are isolated — agents in project A never see project B's rooms/feeds. Federation enforces this at registry level.

## Deployment
```bash
# Federation (auto-seeds agents)
cd $HOME/qwen-cloud-2026/federation && ./start-federation.sh

# TV UI
cd $HOME/qwen-cloud-2026 && python3 -m http.server 8081

# MCP Gateway
cd $HOME/.hermes/skills/devops/tv-sitcom-mcp && python3 scripts/tv_mcp_server.py --federation http://localhost:41207
```

## Files
- `qwen-cloud-2026/federation/start-federation.sh` — federation + seed
- `qwen-cloud-2026/federation/seed-agents.json` — 20 crew agents
- `qwen-cloud-2026/index.html` — TV UI (patched live)
- `.hermes/skills/devops/tv-sitcom-mcp/scripts/tv_mcp_server.py` — MCP gateway