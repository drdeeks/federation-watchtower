#!/usr/bin/env bash
# Start the federation gateway. No agents are seeded -- this is a harness,
# not a demo cast; register real or test agents via POST /api/agents/register
# (or /api/join) once the server is up, the same way any real agent would.
set -u
PORT=41207
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1

# 1) Free the port if something stale is holding it
if command -v fuser >/dev/null 2>&1; then
  fuser -k "${PORT}/tcp" 2>/dev/null || true
else
  pid=$(ss -tlnp "sport = :${PORT}" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1)
  [ -n "${pid:-}" ] && kill -9 "$pid" 2>/dev/null || true
fi
sleep 1

# 2) Launch the server
node server.js > /tmp/federation.log 2>&1 &
SRV=$!
echo "federation server pid=$SRV"

# 3) Wait for health
for i in $(seq 1 30); do
  curl -s -m 2 "http://localhost:${PORT}/health" >/dev/null 2>&1 && break
  sleep 1
done

echo "federation ready on :${PORT} (empty -- no agents registered yet)"
wait "$SRV"
