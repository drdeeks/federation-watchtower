#!/usr/bin/env bash
# Start TV Sitcom MCP server with federation wiring
set -euo pipefail

PORT="${TV_MCP_PORT:-41208}"
HOST="${TV_MCP_HOST:-0.0.0.0}"
FEDERATION_URL="${FEDERATION_URL:-http://localhost:41207}"

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Starting TV Sitcom Show MCP Server"
echo "  MCP port: $PORT"
echo "  Federation: $FEDERATION_URL"

# Verify federation is reachable
for i in {1..10}; do
  if curl -s -m 2 "$FEDERATION_URL/health" >/dev/null 2>&1; then
    echo "  ✓ Federation gateway reachable"
    break
  fi
  echo "  Waiting for federation gateway... ($i/10)"
  sleep 1
done

# Launch MCP server
cd "$DIR" || exit 1
exec python3 -m tv_mcp_server \
  --host "$HOST" \
  --port "$PORT" \
  --federation "$FEDERATION_URL"