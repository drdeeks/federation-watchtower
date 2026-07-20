# Federation Gateway + TV Command Center Integration

## Overview

The `qwen-cloud-2026/federation/server.js` is the production federation gateway that serves as the central nervous system for all 5 hackathon projects. It runs on port 41207 and provides:

- **Agent Registry** — Auto-registration with deterministic avatars (35 agents/room, auto-overflow to production rooms)
- **Room Management** — 3 rooms per project (1 main + 2 production overflow)
- **Plugin System** — 5 built-in plugins (avatar, room, federation, health, TV-room)
- **WebSocket Live Updates** — Real-time agent activity streaming via `ws://localhost:41207/ws?projectId=<project>`
- **4-Layer Memory API** — 15 endpoints for identity, daily, knowledge-graph, semantic search
- **TV Command Center** — Retro CRT visualization of all agents (served at `/` via `index.html`)

## TV Command Center (Visual Dashboard)

**File:** `qwen-cloud-2026/index.html` (served from project root)

**Features:**
- CRT retro TV frame with scanlines/static noise
- 6 tabs: Master (all 175 agents) + 5 project-specific (mnemosyne/aires/agora/autopilot/edgewalker)
- Max 35 agents/room, auto-production rooms on overflow
- Live feed ticker showing real-time agent activity
- Per-project color coding: mnemosyne(#3b82f6), autopilot(#22c55e), aires(#a855f7), agora(#f59e0b), edgewalker(#ef4444)
- Agent avatars with deterministic generation

**Access:** Serve `index.html` via static server (e.g., `python3 -m http.server 8081` from `qwen-cloud-2026/`) → open `http://localhost:8081/index.html` in browser. Connects to federation WebSocket at `ws://localhost:41207/ws`.

## Federation Server Deployment

```bash
# Kill stale server if port occupied
pkill -f 'hackathon-2026/federation-server'

# Start correct federation server
cd $HOME/qwen-cloud-2026/federation
node server.js

# Start TV Command Center static server
cd $HOME/qwen-cloud-2026
python3 -m http.server 8081
# Open http://localhost:8081/index.html
```

## Bug Fix (July 2026)

**Issue:** Federation server crashed on startup with `ReferenceError: createHash is not defined`

**Root cause:** `createHash` used directly instead of `crypto.createHash()` in three locations:
- Line 175: `createHash('sha256').update(entity.name || '').digest('hex')`
- Line 292: `createHash('sha256').update(text).digest()`
- Line 554: `crypto.createHash('sha1')...` (this one was correct)

**Fix:** Replace all bare `createHash` calls with `crypto.createHash`:

```javascript
const id = entity.id || crypto.createHash('sha256').update(entity.name || '').digest('hex').slice(0, 12);
const hash = crypto.createHash('sha256').update(text).digest();
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check with agent/project counts |
| `/api/agents/register` | POST | Register a new agent (auto-assigns avatar/room) |
| `/api/agents` | GET | List all agents across projects |
| `/api/rooms` | GET | List all rooms |
| `/api/blueprints` | GET | List project blueprints |
| `/api/memory/knowledge-graph` | GET | Query knowledge graph |
| `/api/memory/semantic-search` | POST | Hybrid semantic search |
| `/api/memory/daily` | GET | Daily notes access |
| `/api/memory/long-term` | GET | Long-term memory access |
| `/ws` | WS | WebSocket for real-time updates (`?projectId=<project>`) |

## Integration with Crew Orchestration

The federation gateway is **separate** from the kanban/chain system:
- Crew pollers execute checklist-driven work (phases, deliverables)
- Agents **must explicitly register** with federation to appear in TV UI
- Registration: `POST /api/agents/register` with `{agentId, projectId, role, capabilities}`
- After registration, agent heartbeats and activity stream to TV feed automatically

## Project Definitions

```javascript
const PROJECTS = {
  autopilot: { name: 'Autopilot', track: 'Track 4', color: '#22c55e', emoji: '⚙️', prefix: 'AP' },
  mnemosyne: { name: 'Mnemosyne', track: 'Track 1', color: '#3b82f6', emoji: '🧠', prefix: 'MN' },
  aires: { name: 'Aires', track: 'Track 2', color: '#a855f7', emoji: '🎬', prefix: 'AI' },
  agora: { name: 'Agora', track: 'Track 3', color: '#f59e0b', emoji: '🏛️', prefix: 'AG' },
  edgewalker: { name: 'Edgewalker', track: 'Track 5', color: '#ef4444', emoji: '⚡', prefix: 'EW' }
};
```