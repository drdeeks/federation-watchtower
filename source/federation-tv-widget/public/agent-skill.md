# Federation Watchtower Agent Skill

Endpoint: `https://fapi.drdeeks.xyz`

Public Watchtower: `https://watch.drdeeks.xyz`

## Purpose

Report real agent lifecycle events to Federation Watchtower. Do not invent
activity, expose secrets, or treat a denied control decision as optional.

## Connection rules

1. An approved operator provisions your producer or organization credential.
2. Keep that credential in the host runtime, never in a browser, prompt, event
   metadata, or public repository.
3. Send a signed `heartbeat` before its expected deadline, then emit only
   validated operational events.
4. For a cooperative controlled run, validate a lease immediately before an
   external side effect. A non-active lease means stop.

## Signed event endpoint

`POST https://fapi.drdeeks.xyz/api/v1/events`

Required headers:

```text
Content-Type: application/json
X-Watchtower-Timestamp: <unix seconds>
X-Watchtower-Signature: sha256=<signature>
X-Watchtower-Producer: <approved producer id>
```

Minimum event body:

```json
{
  "schemaVersion": "2026-07-17",
  "eventId": "evt-unique-id",
  "idempotencyKey": "run-42-heartbeat-1",
  "projectId": "your-project",
  "agentId": "your-agent",
  "eventType": "heartbeat",
  "severity": "info",
  "occurredAt": "2026-07-17T16:00:00Z",
  "statement": "Agent is present.",
  "metadata": { "expectedHeartbeatSeconds": 120 }
}
```

## Observe and operate

- Live feed: `wss://fapi.drdeeks.xyz/ws?projectId=your-project`
- MCP: `https://fapi.drdeeks.xyz/mcp` with an approved organization credential.
- A missed heartbeat records an offline/watchdog event; it does not delete history.
- Publish only an owner identity that is permitted for public display.

Open self-service credentials are not available yet. Ask an approved Federation
operator to provision access.
