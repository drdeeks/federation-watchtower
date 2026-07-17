# Federation TV Package — Agent Operations Command Center

A complete, production-ready system for exposing a multi-agent fleet as a
**live TV wall**, a **REST/WebSocket API**, and an **MCP server** — so any
external business can watch, query, and register agents with zero custom code.

Everything in this package stems from one core function: the **Federation
Gateway** (`federation-core/server.js`). The TV UI and the MCP skill are both
thin clients on top of it.

---

## 1. What's in the box

```
federation-tv-package/
├── README.md                  ← this file
├── federation-core/           ← THE CORE: federation gateway (Node/Express)
│   ├── server.js              ← gateway: REST + WebSocket + plugin system
│   ├── package.json           ← deps (npm install required)
│   ├── package-lock.json
│   ├── seed-agents.json       ← 20 crew agents auto-registered on boot
│   └── start-federation.sh    ← start + auto-seed + health-wait wrapper
├── shared/                    ← modules the gateway imports
│   ├── agent-plugins.js       ← avatar / room / federation / health / TV plugins
│   ├── agent-registry.js      ← in-memory agent + room registry (per project)
│   ├── memory-manager.js      ← SOUL/MEMORY/daily-note/knowledge-graph API
│   ├── ProviderFactory.js      ← LLM provider abstraction
│   ├── DashScopeProvider.js    └─ provider impls
│   ├── MockDashScopeProvider.js
│   └── package.json
├── tv-command-center/         ← retro CRT web UI (static HTML + JS)
│   └── index.html             ← fetches /api/agents + opens ws://…/ws
└── mcp-skill/                 ← TV Sitcom MCP Server (enterprise-validated)
    └── tv-sitcom-mcp/         ← Skill: live MCP gateway to the federation
        ├── SKILL.md
        ├── __init__.py
        ├── scripts/tv_mcp_server.py   ← FastMCP server (port 41208)
        ├── scripts/start-tv-mcp.sh
        ├── scripts/test_tv_mcp.py     ← validation suite
        ├── references/*.md            ← architecture, api, integration, deploy…
        └── tv-sitcom-mcp.skill        ← packaged artifact
```

> **Note:** `federation-core/node_modules` is excluded to keep the archive small.
> Run `npm install` inside `federation-core/` before first launch.

---

## 2. Architecture — one core, three faces

```
                         ┌─────────────────────────────┐
   External Business  →  │   TV Sitcom MCP Server 41208 │  ← MCP clients
                         └──────────────┬──────────────┘
                                        │  REST calls
                                        ▼
                         ┌─────────────────────────────┐
   Browser / iframe   →  │   Federation Gateway 41207   │  ← THE CORE
                         │  REST + WebSocket + plugins  │
                         └──────────────┬──────────────┘
                                        │  reads/writes
                                        ▼
                         ┌─────────────────────────────┐
   Agents (any org)   →  │   Agent Registry (in memory) │  ← 5 projects × rooms
                         │   projects: mnemosyne, agora,│
                         │   aires, autopilot, edgewalker│
                         └─────────────────────────────┘

   TV Command Center (8081) is a 4th client: static HTML that calls the same
   REST + WS endpoints and renders the CRT wall.
```

The **federation gateway** is the single source of truth. The MCP skill and the
web UI are stateless clients — if you kill either, the data is untouched.

---

## 3. The federation core function (what it actually does)

`server.js` is a Node HTTP server that:

1. **Registers agents** — `POST /api/agents/register` with
   `{projectId, agentId, name, role, capabilities}`. Auto-generates an SVG
   avatar, assigns the agent to a room (35/room, auto-overflow), and broadcasts
   the event over WebSocket.
2. **Serves agent state** — `GET /api/agents` returns
   `{agents: {projectId: [...]}}` for all 5 projects.
3. **Manages rooms** — `GET /api/rooms` returns room assignments per project.
4. **Streams live events** — `ws://host:41207/ws?projectId=<id|all>` pushes
   `agentRegistered`, `agentUpdated`, `heartbeat`, `roomChanged` messages.
5. **Exposes memory** — `GET /api/memory/*` serves SOUL.md, MEMORY.md, daily
   notes, knowledge-graph entities, and hybrid semantic search.
6. **Loads plugins** — avatar-generation, room-management, federation-sync,
   health-monitoring, tv-room-integration (from `shared/agent-plugins.js`).

Projects are **namespaced by `projectId`**. An agent in `acme-corp` never sees
or affects agents in `mnemosyne`. This is the mechanism that makes multi-org
tenancy free.

---

## 4. Quick start (fresh machine)

```bash
# 1. Federation gateway
cd federation-core
npm install                 # pulls express, ws, etc.
./start-federation.sh       # starts on :41207, waits for health, seeds 20 agents

# 2. TV Command Center (optional web UI)
cd ../tv-command-center
python3 -m http.server 8081 # serves index.html → http://localhost:8081/index.html

# 3. MCP gateway (optional, for MCP clients)
cd ../mcp-skill/tv-sitcom-mcp
pip install fastmcp         # once
python3 scripts/tv_mcp_server.py --federation http://localhost:41207
                              # listens on :41208/mcp
```

Verify:
```bash
curl http://localhost:41207/health      # {status: healthy, agents: 20, ...}
curl http://localhost:41207/api/agents  # 20 agents across 5 projects
```

---

## 5. Data model

| Concept | Key | Notes |
|---------|-----|-------|
| **Project** | `mnemosyne`, `agora`, `aires`, `autopilot`, `edgewalker` | Hardcoded in `server.js` `PROJECTS`. Add your own here. |
| **Agent** | `{agentId, name, role, projectId, capabilities, status, roomId, avatar}` | Registered via API. |
| **Room** | `{id, projectId, agents[], capacity:35}` | Auto-created per project; overflow rooms as needed. |
| **Feed event** | `{timestamp, event_type, agent_id, project, message, priority}` | Emitted on register/update/heartbeat. |

Capacity: 35 agents/room × N rooms. Utilization = agents / (rooms × 35).

---

## 6. External integration — four ways to consume

### A. MCP (recommended for LLM agents / toolchains)
Point any MCP client at `http://host:41208/mcp`.
Tools: `get_all_rooms`, `get_room`, `get_tv_feed`, `get_agent`,
`get_project_summary`, `get_system_status`, `search_agents`, `register_agent`.
Resources: `config://projects`, `config://rooms`, `status://federation`.

### B. REST (any language)
```bash
curl http://host:41207/api/agents
curl http://host:41207/api/rooms
curl -X POST http://host:41207/api/agents/register \
  -H 'Content-Type: application/json' \
  -d '{"projectId":"acme","agentId":"a1","name":"Analyzer","role":"worker"}'
```

### C. WebSocket (real-time)
```js
const ws = new WebSocket('ws://host:41207/ws?projectId=all');
ws.onmessage = e => console.log(JSON.parse(e.data)); // live agent events
```

### D. Iframe (zero-code dashboard)
```html
<iframe src="http://host:8081/index.html" width="100%" height="800"></iframe>
```

---

## 7. Incorporating into an additional business

The system is built for exactly this. Three steps:

**1. Claim a project namespace.**
Add your org's `projectId` to the `PROJECTS` map in `federation-core/server.js`
(name, emoji, color). Your agents are now isolated in their own rooms.

**2. Register your agents.**
From your own backend (cron, CI, agent runtime) call:
```bash
curl -X POST http://<federation-host>:41207/api/agents/register \
  -H 'Content-Type: application/json' \
  -d '{"projectId":"<your-org>","agentId":"<unique>","name":"...","role":"..."}'
```
Or, if your agents speak MCP, call the `register_agent` tool on the MCP server.

**3. Consume the wall.**
- Your ops team: iframe the TV UI on an internal dashboard.
- Your LLM agents: connect via MCP and call `get_tv_feed` / `get_system_status`.
- Your alerting: subscribe to the WebSocket, filter `event_type=="error"`.

**Multi-tenant isolation** is automatic — projects never share rooms or feeds.
**No code changes** to the core are needed to onboard a new business; only a
`projectId` entry (one line) and agent registration calls.

### Example: a second company "Globex" joins
```js
// Globex backend registers its fleet
for (const a of globexAgents)
  await fetch('http://fed:41207/api/agents/register', {
    method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({projectId:'globex', ...a})
  });
// Globex ops sees its wall at http://fed:8081/index.html (filtered to globex)
// Globex LLM agents query via MCP: get_project_summary("globex")
```

---

## 8. Security

- **No auth built-in.** Put a reverse proxy (nginx/Caddy) in front for TLS +
  bearer-token auth before exposing `41207`/`41208` publicly.
- **Read-mostly.** Only `register_agent` (and agent self-update) mutate state.
  Behind a proxy, restrict `POST /api/agents/*` to trusted callers.
- **Internal by default.** Bind to `127.0.0.1` or a private network; expose
  only via the proxy.
- **Rate limit** at the proxy (e.g. `limit_req` in nginx).
- **Data is in-memory.** Agents/rooms reset on gateway restart — the
  `seed-agents.json` re-registers the 5 core crews; external orgs should
  re-register on their own startup (idempotent: re-registering the same
  `agentId` updates in place).

---

## 9. Operations

| Task | Command |
|------|---------|
| Start gateway | `federation-core/start-federation.sh` |
| Start TV UI | `cd tv-command-center && python3 -m http.server 8081` |
| Start MCP | `mcp-skill/tv-sitcom-mcp/scripts/start-tv-mcp.sh` |
| Health | `curl localhost:41207/health` |
| Validate MCP | `python3 mcp-skill/tv-sitcom-mcp/scripts/test_tv_mcp.py` |
| Add project | edit `PROJECTS` in `federation-core/server.js` |
| Register agent | `POST /api/agents/register` |

**Ports:** 41207 (gateway), 8081 (TV UI), 41208 (MCP). Override via env
(`TV_MCP_PORT`, `FEDERATION_URL`) or CLI flags.

---

## 10. File-by-file reference

| File | Role |
|------|------|
| `federation-core/server.js` | Gateway: routes, WS, plugin loader, health |
| `federation-core/seed-agents.json` | 20 crew agents re-registered on boot |
| `federation-core/start-federation.sh` | Boot wrapper (kill stale, start, seed) |
| `shared/agent-registry.js` | Agent/room store, registration, broadcast |
| `shared/agent-plugins.js` | Plugin system (avatar, room, TV, health, federation) |
| `shared/memory-manager.js` | SOUL/MEMORY/daily/knowledge-graph API |
| `tv-command-center/index.html` | CRT wall UI (fetches `/api/agents` + WS) |
| `mcp-skill/tv-sitcom-mcp/scripts/tv_mcp_server.py` | FastMCP server → federation REST |
| `mcp-skill/tv-sitcom-mcp/references/*.md` | Deep-dive docs (api, integration, deploy…) |

---

## 11. License & provenance

- Core gateway + TV UI: MIT (Hemlock Enterprise hackathon build).
- MCP skill: MIT, enterprise-tier validated (11-gate pipeline, v1.1.1).
- No external secrets bundled. Provider keys (DashScope etc.) are read from
  env at runtime and never shipped.

**Status:** live, validated, no mock data. All tools return real registered
agent state from the federation gateway.
