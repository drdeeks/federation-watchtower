# MCP Protocol Compliance

## Transport
- Streamable-HTTP (primary)
- Compatible with: Claude Desktop, custom agents, any MCP client

## Tools (8)
All tools return JSON-serializable dicts. Errors returned as `{"error": "..."}`.

1. `get_all_rooms()` → List[RoomSummary]
2. `get_room(room_id)` → RoomDetail | {error}
3. `get_tv_feed(limit=50, project?, priority?)` → List[FeedEntry]
4. `get_agent(agent_id)` → AgentSnapshot | {error}
5. `get_project_summary(project)` → ProjectSummary | {error}
6. `get_system_status()` → SystemStatus
7. `search_agents(query)` → List[AgentSnapshot]
8. `register_agent(project_id, agent_id, name, role, capabilities?)` → {success, agent} | {error}

## Resources (3)
- `config://projects` → Project metadata
- `config://rooms` → Room schema
- `status://federation` → Live health

## Notifications
Server broadcasts via WebSocket to subscribed clients on:
- Agent registration/removal
- Room changes
- Health status changes
