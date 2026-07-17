# TV Sitcom MCP Architecture

This MCP server exposes the Hemlock Enterprise Agent TV Room as a standard MCP service.

## Data Flow
```
External MCP Client → tv-sitcom-mcp (41208) → Federation Gateway (41207) → Agent Registries
```

## Tool Mapping
| MCP Tool | Federation Endpoint |
|----------|---------------------|
| get_all_rooms | GET /api/agents + GET /api/rooms |
| get_room | GET /api/rooms |
| get_tv_feed | GET /api/agents (computed) |
| get_agent | GET /api/agents |
| get_project_summary | GET /api/agents (aggregated) |
| get_system_status | GET /health + GET /api/agents |
| search_agents | GET /api/agents (filtered) |
| register_agent | POST /api/agents/register |

