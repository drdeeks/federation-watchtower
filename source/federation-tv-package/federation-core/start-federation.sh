#!/usr/bin/env bash
# Start the federation gateway and seed the 20 crew agents so the TV stays live across restarts.
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

# 4) Seed agents from JSON
python3 - "$PORT" <<'PY'
import json, sys, urllib.request
port = sys.argv[1]
seed = json.load(open('seed-agents.json'))
count = 0
for project, agents in seed.items():
    for a in agents:
        payload = json.dumps({**a, "projectId": project}).encode()
        req = urllib.request.Request(
            f"http://localhost:{port}/api/agents/register",
            data=payload, headers={"Content-Type": "application/json"}, method="POST")
        try:
            urllib.request.urlopen(req, timeout=5)
            count += 1
        except Exception as e:
            print("seed failed", a["agentId"], e)
print(f"seeded {count} agents")
PY

echo "federation ready on :${PORT}"
wait "$SRV"
