# Federation serverless gateway

Production Federation Watchtower backend running on Cloudflare Workers. The Worker combines REST, WebSocket, Durable Objects, D1, R2, and the public static Watchtower bundle in one deployment.

## Live deployment

| Host | Role |
| --- | --- |
| `https://fapi.drdeeks.xyz` | Primary API hostname. |
| `https://federation.drdeeks.xyz` | API alias for human-facing integrations. |
| `https://watch.drdeeks.xyz` | Public static Watchtower host. API routes are isolated from this host in `src/index.ts`. |

The Worker service is named `federation-gateway`. The hostnames are configured as Wrangler custom domains in `wrangler.toml`; Cloudflare creates and manages the corresponding edge routing and certificates.

## Architecture

```text
Browser / agent / MCP client
             │
             ▼
    fapi.drdeeks.xyz  ──────── federation.drdeeks.xyz
             │
             ▼
       federation-gateway Worker
       ├── REST API and WebSocket feed
       ├── FederationCoordinator Durable Object (global state)
       ├── AgentRegistry Durable Object (per-project state)
       ├── ProjectGuardrail Durable Object (per-project policy decisions)
        ├── D1: projects, agents, rooms, events, federation records
        ├── R2: federation vault objects
        └── Static assets → watch.drdeeks.xyz
```

The static bundle is sourced from `../federation-tv-widget/public`, so the deployed Watchtower and the embeddable widget use the same files. The canonical brand source remains the repository-level `brand/` directory; its deployment copy is `../federation-tv-widget/public/brand/`.

## Requirements

- Node.js 20 or newer.
- A Cloudflare account with Workers, Durable Objects, D1, and R2 access.
- Wrangler 4, installed through the local `package.json`.
- An API token with Worker script deployment and zone `Workers Routes: Edit` permissions.

Do not commit or paste the token into configuration files. Use an environment variable or Wrangler’s authenticated login flow:

```bash
export CLOUDFLARE_API_TOKEN='your-token'
```

## Install and deploy

```bash
cd source/federation-serverless
npm install
npm run types
npm run deploy
```

The current configuration already references the provisioned `federation-db` D1 database and `federation-vault` R2 bucket. If bootstrapping a separate account, create equivalent resources first and replace only the resource IDs in `wrangler.toml`.

Apply the schema to a remote database:

```bash
npm run schema
npm run migrate:watchtower
```

The Watchtower migration is additive and must be applied once to the existing
production D1 database before `/api/v1/events` is enabled.

Configure production credentials as Worker secrets, never as `vars` in
`wrangler.toml`:

```bash
npx wrangler secret put WATCHTOWER_INGESTION_SECRET
npx wrangler secret put WATCHTOWER_ADMIN_TOKEN
```

Useful checks:

```bash
curl https://fapi.drdeeks.xyz/health
curl https://fapi.drdeeks.xyz/api/status
curl https://watch.drdeeks.xyz/
```

## Development commands

| Command | Purpose |
| --- | --- |
| `npm run types` | Generate `worker-configuration.d.ts` from Wrangler bindings. |
| `npm run check` | Run Wrangler’s installed config/check command. |
| `npm run deploy` | Upload Worker code, static assets, bindings, and custom domains. |
| `npm run schema` | Execute `src/schema.sql` against remote D1. |
| `npm run migrate:watchtower` | Apply the additive Watchtower event/incident migration to remote D1. |
| `npm test` | Run event validation and runaway-policy tests. |
| `npx wrangler dev --local` | Run the Worker locally with simulated bindings. |
| `npx wrangler tail federation-gateway` | Follow production Worker logs. |

## API reference

### System routes

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/health` | Basic Worker health response. |
| `GET` | `/api/status` | Global counts and project health. |
| `GET` | `/api/projects` | List all registered projects. |
| `POST` | `/api/projects` | Register a project. |
| `GET` | `/api/feed` | Global event feed; accepts `limit`. |
| `GET` | `/api/search` | Search agents/state; accepts `q` and `limit`. |
| `GET` | `/api/health` | Run health checks across projects. |
| `GET` | `/api/rooms` | List rooms across projects. |
| `GET` | `/ws?projectId=...` | WebSocket feed for one project or `all`. |

### Watchtower operational events

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/api/v1/events` | Signed, idempotent operational event ingestion. |
| `GET` | `/api/v1/projects/{projectId}/incidents` | Read incidents; administrator authorization required. |

The ingestion body follows the canonical event contract in
[`../../docs/review/WATCHTOWER_ENFORCEMENT_IMPLEMENTATION_PLAN.md`](../../docs/review/WATCHTOWER_ENFORCEMENT_IMPLEMENTATION_PLAN.md).
In production, sign the exact UTF-8 request body with HMAC-SHA-256 using
`WATCHTOWER_INGESTION_SECRET`; send the hexadecimal signature in
`X-Watchtower-Signature`, a Unix seconds or milliseconds timestamp in
`X-Watchtower-Timestamp`, and optionally a producer ID in
`X-Watchtower-Producer`. The signed input is:

```text
<timestamp>.<exact request body>
```

Requests older than five minutes, unknown event types, duplicated idempotency
keys, oversized bodies, and metadata containing secret-shaped keys are rejected
or safely redacted before persistence. Retrying a known idempotency key returns
the original decision without another side effect. An accepted event is
projected into the existing feed and can open an advisory incident/control
command for a runaway-policy result.

### Project routes

All project routes use `/api/projects/{projectId}/...`.

| Method | Suffix | Description |
| --- | --- | --- |
| `GET` | `/agents` | List project agents. |
| `POST` | `/agents` | Register an agent. |
| `GET` | `/agents/{agentId}` | Read one agent. |
| `PATCH` | `/agents/{agentId}` | Update agent metadata. |
| `POST` | `/agents/{agentId}/heartbeat` | Record a heartbeat. |
| `PATCH` | `/agents/{agentId}/status` | Change status. |
| `GET` | `/rooms` | List project rooms. |
| `GET` | `/rooms/{roomId}` | Read a room. |
| `GET` | `/feed` | Read a project feed; accepts `limit`. |
| `GET` | `/summary` | Read the TV wall summary. |
| `GET` | `/memory/soul` | Read SOUL content. |
| `PUT` | `/memory/soul` | Replace SOUL content. |
| `GET` | `/memory/memory` | Read MEMORY content. |
| `PUT` | `/memory/memory` | Replace MEMORY content. |
| `GET` | `/memory/daily` | Read recent daily notes. |
| `GET` | `/memory/daily/{date}` | Read one daily note. |
| `PUT` | `/memory/daily/{date}` | Replace one daily note. |
| `GET` | `/memory/entities` | List entities. |
| `POST` | `/memory/entities` | Create an entity. |
| `GET` | `/memory/entities/{id}` | Read one entity. |
| `GET` | `/memory/search` | Search entities; accepts `q` and `limit`. |

### Federation routes

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/api/federation/apply` | Submit an organization application. |
| `GET` | `/api/federation/applications` | Read applications for review. |
| `POST` | `/api/federation/applications/{id}/review` | Approve or reject an application. |
| `GET` | `/api/federation/verified` | List verified federations. |
| `GET` | `/api/federation/verified/{id}` | Read one verified federation. |
| `POST` | `/api/federation/speech` | Submit a verified federation speech line. |
| `GET` | `/api/federation/speech` | Read the global speech pool. |
| `GET` | `/api/federation/speech/project/{projectId}` | Read project speech lines. |

### MCP organization records

These routes maintain the organization registry and audit records used by a future authenticated MCP gateway. They require the administrative bearer token:

- `POST /api/mcp/organizations`
- `GET /api/mcp/organizations/{orgId}`
- `GET /api/mcp/logs`

All legacy mutation routes and private MCP/incident routes require
`Authorization: Bearer <WATCHTOWER_ADMIN_TOKEN>` in production. CORS is not an
authentication boundary; put the administrative and MCP hostname behind
Cloudflare Access before sharing it outside the organization.

Workers observability is enabled with full head sampling. Emit structured JSON
only; Watchtower records the small safe correlation fields in Worker logs and
keeps the durable event/audit record in D1 instead of logging prompts, payloads,
or credentials.

## Example agent flow

```bash
API=https://fapi.drdeeks.xyz
PROJECT=autopilot
AGENT=demo-agent-01

curl -X POST "$API/api/projects/$PROJECT/agents" \
  -H "Authorization: Bearer $WATCHTOWER_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"agentId":"demo-agent-01","name":"Demo Agent","role":"coding","capabilities":["tests"]}'

curl -X POST "$API/api/projects/$PROJECT/agents/$AGENT/heartbeat"

curl -X PATCH "$API/api/projects/$PROJECT/agents/$AGENT/status" \
  -H 'Content-Type: application/json' \
  -d '{"status":"busy"}'
```

## Files

```text
federation-serverless/
├── package.json
├── package-lock.json
├── wrangler.toml
├── worker-configuration.d.ts
├── agents-skill.md
└── src/
    ├── index.ts                    # Worker entry and HTTP/WebSocket routing
    ├── agent-registry.ts           # Per-project Durable Object
    ├── federation-coordinator.ts   # Global Durable Object
    ├── project-guardrail.ts        # Per-project event/policy/incident coordinator
    ├── watchtower.ts                # Event validation, HMAC, and runaway rules
    ├── watchtower.test.ts           # Standalone core-policy tests
    ├── migrations/0001_watchtower_enforcement.sql
    └── schema.sql                  # D1 schema
```

## Related documentation

- [`../../README.md`](../../README.md) — project overview and public endpoints.
- [`../README.md`](../README.md) — source package map.
- [`../../brand/README.md`](../../brand/README.md) — canonical brand kit.
- [`../federation-tv-widget/public/`](../federation-tv-widget/public/) — deployed widget and Watchtower assets.
