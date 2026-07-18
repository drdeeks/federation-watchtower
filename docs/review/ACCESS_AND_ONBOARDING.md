# Federation Watchtower — Access and Onboarding

This is the operational guide for deciding who does what. The public
Watchtower is open to observation; the Federation member surface and machine
control plane require the appropriate credential.

## The four identities

| Identity | What it is | Credential / authority |
| --- | --- | --- |
| Agent | A runtime, model, CI job, webhook producer, or MCP-connected worker doing the actual work. | `fw_agent_…`; can connect, heartbeat, emit events, and disconnect for one registered agent. |
| Individual project owner | The person responsible for one or more personal agents/projects. | `fw_owner_…`; can register agents and submit an organization application owned by that account. |
| Organization owner | The owner identity attached to an organization application and its agents. | The same owner lifecycle applies today; verification is an elevated-trust workflow, not a prerequisite for basic agent participation. |
| Administrator | The deployment operator who holds `WATCHTOWER_ADMIN_TOKEN`. | Can create projects, review legacy Federation applications, create MCP organization principals, manage budgets/incidents, and export evidence. Never put this token in a browser or agent. |

An agent is not an owner. An agent reports work. An owner registers and
configures agents. An administrator manages deployment-wide records and
review. The public Watchtower only observes public projections.

## Individual agent path

An individual does not need organization verification to send an agent:

1. Create an owner once with `POST /api/v1/owners`.
2. Store the returned one-time `fw_owner_…` credential in a local secret
   store.
3. Register a canonical agent with `POST /api/v1/agents` and a validated
   manifest.
4. Store the returned one-time `fw_agent_…` credential in the agent host.
5. Connect, heartbeat, emit events, and disconnect through the agent routes.

An operational event has one bounded `statement`. It is evidence from that
agent, not an organization application and not a free-form public chat room.
Use `publicProjection: true` only when the owner permits the identity/status/
event projection to appear in Watchtower.

## Organization application path

An organization application is separate from an agent event. The owner submits:

- organization ID, name, and verified contact email;
- official HTTPS website or repository;
- at least two unique non-GitHub social proofs; and
- exactly five attributable technical question/answer records.

Submit it with the owner credential:

```bash
curl -X POST https://fapi.drdeeks.xyz/api/v1/organizations/applications \
  -H "Authorization: Bearer $FEDERATION_OWNER_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "organizationId": "acme-labs",
    "name": "Acme Labs",
    "contactEmail": "ops@acme.example",
    "officialUrl": "https://acme.example",
    "socialProofs": [
      {"platform":"linkedin","url":"https://www.linkedin.com/company/acme-labs"},
      {"platform":"discord","url":"https://discord.gg/example"}
    ],
    "technicalQuestions": [
      {"question":"What does the system monitor?","answer":"Bounded operational events."},
      {"question":"How does the agent prove presence?","answer":"Signed heartbeats."},
      {"question":"What stops a runaway action?","answer":"A denied lease or gate."},
      {"question":"How are duplicate events handled?","answer":"Idempotency keys and durable evidence."},
      {"question":"What should remain private?","answer":"Credentials and private metadata."}
    ]
  }'
```

This currently stores the application and its five answers. Reviewer UI,
organization RBAC, and an automatic promotion from application approval to a
fully managed namespace are not complete. Do not describe this as browser
self-service Federation access yet.

## Administrator: create and add organizations

There are two administrator operations and they should not be confused:

### 1. Create a machine organization principal for MCP

Use this when an organization needs service-to-service MCP access. Generate a
high-entropy API key outside the repository, send it once over TLS, and keep
the raw key. Watchtower stores only its SHA-256 verifier.

```bash
export API_KEY="generate-and-store-a-32-plus-character-secret"
curl -X POST https://fapi.drdeeks.xyz/api/mcp/organizations \
  -H "Authorization: Bearer $WATCHTOWER_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"id\":\"acme-labs\",\"name\":\"Acme Labs\",\"contactEmail\":\"ops@acme.example\",\"apiKey\":\"$API_KEY\",\"scopes\":[\"watchtower:read\",\"project:autopilot:read\"],\"rateLimit\":100,\"ipAllowlist\":[]}" \
  | jq
```

The resulting MCP principal connects with
`Authorization: Bearer acme-labs.<API_KEY>`. The administrator can inspect,
rotate, suspend, revoke, and audit it through the documented MCP organization
routes. This does not by itself approve a public Federation application.

### 2. Review a Federation application

The legacy review routes are administrator-only:

```bash
curl -H "Authorization: Bearer $WATCHTOWER_ADMIN_TOKEN" \
  https://fapi.drdeeks.xyz/api/federation/applications?status=submitted

curl -X POST https://fapi.drdeeks.xyz/api/federation/applications/42/review \
  -H "Authorization: Bearer $WATCHTOWER_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"decision":"approved","reviewer":"admin","notes":"Reviewed official proofs and five answers."}'
```

The administrator token is deployment-wide. Use the private operator console
at `https://federation.drdeeks.xyz/operator.html` for incidents, budgets,
sessions, and evidence; it is not an organization applicant portal.

## Federation access checklist

Before granting an organization or integration elevated access:

1. Confirm the owner identity and organization ID are attributable.
2. Confirm the application has exactly five technical answers and two or more
   non-GitHub proofs.
3. Create or verify the required project and room boundary.
4. Issue only the minimum MCP scopes or agent credential required.
5. Store raw credentials only in the owner/agent secret store.
6. Test connect → heartbeat → event → watchdog expiry → reconnect.
7. Confirm public projection consent and owner metadata are safe to display.
8. Record the review, credential, and lifecycle evidence; never erase the
   operational history.

## Current boundary

The safe, working path is authenticated API/package onboarding plus a
read-only public Watchtower. Browser owner signup, credential rotation/revocation
UI, organization role enforcement, per-owner webhook configuration, and
payments remain follow-up work.
