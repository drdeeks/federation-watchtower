# Federation/Coordination Gateway Skills — Lessons Learned

## Context
Session: Building the autonomous-federation skill for hackathon-2026 workspace consolidation.
Date: 2026-07-04

## Key Learnings

### 1. Federation Server ≠ Project Implementation
The federation server (port 41207) is a **coordination gateway** — it provides:
- MCP join endpoint for agent registration
- Project discovery (blueprints listing)
- Shared 4-layer memory bus (SOUL, MEMORY, Daily, Knowledge Graph)
- Work assignment routing
- WebSocket hub for real-time communication

**It does NOT replace individual project implementations.** Each hackathon track (autopilot, aires, mnemosyne, agora, edgewalker) still needs its own agent logic. The federation just lets agents *find* and *join* them.

### 2. Server Stability Patterns
- **Don't use `timeout` for persistent servers** — it kills them (exit 124). Run `node server.js` directly in background with `notify_on_complete=true`.
- **Port conflicts (EADDRINUSE) are routine** — always `pkill -f "node server.js"` + `lsof -ti :41207 | xargs -r kill -9` before restart.
- **Health endpoint is mandatory** — `/health` must return fast for orchestration to verify liveness.

### 3. Skill Scaffolding for Federation
When creating a federation skill:
- Template `server.js` must include: health, blueprints, join, assign-work, project status, stats, WebSocket, memory endpoints
- Template `package.json` needs `express`, `ws` dependencies
- Include `templates/SOUL.md` and `templates/MEMORY.md` with federation identity
- Scaffold script should create `memory/{daily,entities,templates}` dirs

### 4. Sub-Agent Spawning is Separate Work
The federation skill enables agents to *join* projects. Actually *implementing* the 5 projects and spawning sub-agents for each is a separate delegation task — not part of the federation skill itself.

### 5. Memory Architecture Integration
The 4-layer memory (Knowledge Graph + Daily Notes + Long-term + Identity) must be:
- Seeded with autonomous agent entities
- Accessible via mandatory search (recall discipline)
- Indexed for semantic search (BM25 + vector hybrid)
- Loadable via morning routine (context conservation)