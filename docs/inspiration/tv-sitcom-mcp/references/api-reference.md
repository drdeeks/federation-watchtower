# Federation API Reference

Base: `http://localhost:41207`

## Endpoints

### Health
`GET /health` → `{status, timestamp, uptime, agents, rooms, projects}`

### Agents
`GET /api/agents` → `{success, agents: {projectId: [...]}}`
`POST /api/agents/register` → Register new agent
`GET /api/agents/:id` → Single agent
`PUT /api/agents/:id` → Update agent
`DELETE /api/agents/:id` → Remove agent

### Rooms
`GET /api/rooms` → All rooms with agents
`GET /api/rooms/:id` → Room detail

### Memory
`GET /api/memory/identity` → SOUL.md
`GET /api/memory/long-term` → MEMORY.md
`GET /api/memory/daily` → Daily notes
`POST /api/memory/daily` → Add daily note
`GET /api/memory/knowledge-graph` → Entities
`POST /api/memory/entity` → Create entity
`POST /api/memory/search` → Mandatory search
`POST /api/memory/semantic-search` → Vector search
`POST /api/memory/index` → Index document
`POST /api/memory/reindex` → Reindex all
`POST /api/memory/lesson` → Add lesson
`GET /api/memory/morning-routine` → Full context load
`GET /api/memory/stats` → Memory statistics
`GET /api/memory/templates` → Obsidian templates

### WebSocket
`ws://localhost:41207/ws?projectId=<project>` → Real-time agent events
`ws://localhost:41207/ws?projectId=all` → All projects

### Events
`agentRegistered`, `agentUpdated`, `agentRemoved`, `roomChanged`, `heartbeat`
