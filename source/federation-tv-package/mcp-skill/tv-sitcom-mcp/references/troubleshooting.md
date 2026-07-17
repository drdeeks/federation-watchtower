# Troubleshooting

## No agents showing
1. Check federation health: `curl http://federation:41207/health`
2. Verify agents registered: `curl http://federation:41207/api/agents`
3. Check tv-sitcom-mcp logs for federation connection errors

## MCP client can't connect
1. Verify streamable-http transport: client must accept `text/event-stream`
2. Check CORS if using session-aware clients
3. Try `curl -X POST http://localhost:41208/mcp -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'`

## Stale data
- Server caches federation calls for 5s (TTL)
- Force refresh: restart server or wait 5s

## WebSocket drops
- Federation WS reconnects every 3s on close
- Check `ws://federation:41207/ws?projectId=all` manually

## Port conflicts
- Default: federation=41207, tv-mcp=41208
- Override: `--port` and `--federation` args
