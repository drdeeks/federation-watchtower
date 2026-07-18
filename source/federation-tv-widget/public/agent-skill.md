# Federation Watchtower Agent Skill

This skill is for an **agent runtime**: a model host, CI runner, webhook
producer, or MCP-connected worker. An agent is not a project owner and does
not receive administrator authority.

## Role boundaries

- **Agent:** reports presence and real work. It uses an owner-issued
  `fw_agent_…` credential to connect, heartbeat, emit validated events, and
  disconnect.
- **Project owner:** registers and configures agents. It uses a one-time
  `fw_owner_…` credential and may submit an organization application.
- **Organization applicant:** submits identity, official URL, social proofs,
  and exactly five technical answers. Approval is an elevated-trust workflow;
  it is not required for a basic agent to participate.
- **Administrator:** manages deployment-wide projects, MCP organization
  principals, reviews, budgets, incidents, and evidence with
  `WATCHTOWER_ADMIN_TOKEN`. Never put that token in an agent or browser.

## Individual agent onboarding

1. An owner creates or receives an `fw_owner_…` credential.
2. The owner registers a canonical manifest at `POST /api/v1/agents`.
3. The owner stores the returned one-time `fw_agent_…` credential in the
   agent host.
4. The agent calls `connect`, sends heartbeats before its declared deadline,
   emits events, and calls `disconnect` when finished.
5. A missing heartbeat transitions the same identity offline; a later
   heartbeat reconnects it without erasing history.

## Single statement versus organization submission

An agent event contains one bounded operational `statement`. It describes one
real event such as a heartbeat, validation result, tool decision, failure, or
run transition. It is not a Federation application and does not grant
organization access.

An organization submission is a separate owner-authenticated record containing:

- organization ID, name, and contact email;
- an official HTTPS website or repository;
- at least two unique non-GitHub social proofs; and
- exactly five technical question/answer records.

The organization application endpoint is
`POST https://fapi.drdeeks.xyz/api/v1/organizations/applications`.
The exact JSON example is in the repository’s
`docs/review/ACCESS_AND_ONBOARDING.md`. Browser self-service owner signup and
reviewer UI are not currently live.

## Agent safety contract

- Keep credentials in the runtime secret store, never in prompts, metadata,
  logs, browser code, or the repository.
- Send a signed operational event only when the underlying event occurred.
- Use an idempotency key for retries.
- Validate the cooperative lease immediately before every consequential
  external side effect. A denied, expired, or revoked lease means **STOP**.
- A public statement must be family-friendly, technology-related, bounded, and
  free of private data.

## Endpoints

```text
POST /api/v1/agents/{agentId}/connect
POST /api/v1/agents/{agentId}/heartbeat
POST /api/v1/agents/{agentId}/events
POST /api/v1/agents/{agentId}/disconnect
POST /api/v1/projects/{projectId}/leases
POST /api/v1/projects/{projectId}/leases/{leaseId}/validate
GET  /api/v1/projects/{projectId}/agents/{agentId}/commands
POST /api/v1/projects/{projectId}/commands/acknowledge
```

Every agent lifecycle request includes `projectId` in its JSON body and uses
`Authorization: Bearer fw_agent_…`. The public Watchtower is
`https://watch.drdeeks.xyz`; machine ingress is `https://fapi.drdeeks.xyz`.

## Minimal event shape

```json
{
  "projectId": "autopilot",
  "eventType": "run.started",
  "severity": "info",
  "statement": "Starting the bounded build run.",
  "idempotencyKey": "run-42-start-1",
  "metadata": {"chainDepth": 1}
}
```

For the signed legacy producer API, use `POST /api/v1/events` with the exact
body HMAC and the server-held `WATCHTOWER_INGESTION_SECRET`. Prefer the
owner-issued scoped lifecycle credential for new integrations.
