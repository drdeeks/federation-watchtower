# Federation Watchtower

[![OpenAI Build Week](https://img.shields.io/badge/OpenAI-Build%20Week-412991?logo=openai&logoColor=white)](https://openai.devpost.com/)
[![Cloudflare Workers](https://img.shields.io/badge/Cloudflare-Workers-f38020?logo=cloudflare&logoColor=white)](https://developers.cloudflare.com/workers/)
[![TypeScript](https://img.shields.io/badge/TypeScript-3178c6?logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![MCP](https://img.shields.io/badge/Integration-MCP-6e56cf)](https://modelcontextprotocol.io/)
[![License](https://img.shields.io/badge/License-MIT-2f855a)](LICENSE)

**Federation Watchtower is a developer tool that makes autonomous work visible
before it becomes expensive.** It is an agent-operations control plane with a
security-camera sitcom presentation: real agents, heartbeats, events,
guardrails, validation decisions, and watchdog signals are made readable for
humans without turning the operational record into theater.

Live public Watchtower: [watch.drdeeks.xyz](https://watch.drdeeks.xyz)

Machine/API ingress: [fapi.drdeeks.xyz](https://fapi.drdeeks.xyz)
Member/operator surface: [federation.drdeeks.xyz](https://federation.drdeeks.xyz)

> Operational truth is the product. Theatrical presentation makes it watchable.

## Why it exists

This began with a costly and familiar failure mode: while building another
hackathon project, autonomous coding work repeatedly scaffolded projects with
very little visible progress. Roughly **25,000 credits** disappeared before
there was a clear, shared answer to four basic questions:

1. What is currently running?
2. What is it trying to do repeatedly?
3. What is it costing, failing, or waiting on?
4. What should stop before the next side effect?

Normal logs can contain the evidence but are hard to monitor during a fast,
multi-agent build. Federation Watchtower turns that evidence into an observable
runtime surface: a human can see a real agent's presence and event trail, while
the system can record a validation denial, budget warning, duplicate/runaway
signal, or missed heartbeat that an agent is expected to honor.

The colorful TV presentation is intentionally a hook, not a substitute for
controls. A sparse, labelled ambient cameo may appear in an empty public room;
it is never an agent, an event, or audit evidence.

## The Build Week fit

**Track: Developer Tools.** Watchtower is for developers operating agentic
workflows, CI/CD, testing, DevOps, and guarded automation. It combines a
Cloudflare Worker control plane, an integration surface, a public read-only
Watchtower, and a local-friendly operator workflow.

It is being built with Codex during OpenAI Build Week. The project is designed
to make Codex-enabled and other autonomous workflows safer to operate; it does
not claim that Watchtower controls a model provider itself.

| Build Week criterion | Repository evidence |
| --- | --- |
| Non-trivial working implementation | Worker, Durable Objects, D1, R2, Queue/DLQ, REST, WebSocket, static Watchtower, tests, and a local demo path. |
| Coherent product experience | Public Watchtower room/agent/feed view plus the reserved operator/member surface. |
| Specific problem and audience | Developers and teams supervising autonomous runs that can recurse, duplicate work, fail quietly, or spend beyond expectations. |
| Novel idea | An observability/control plane where evidence is presented as a compact agent-ops sitcom without fabricating operational state. |
| How Codex accelerated the work | Codex was used to consolidate the repository, wire and test the Worker surfaces, shape domain boundaries, build the camera-style Watchtower, and document the operational lifecycle. |

The exact model-use narrative and `/feedback` session ID must be added by the
submitter in Devpost; this repository intentionally does not invent either.
See [the submission notes](docs/review/OPENAI_SUBMISSION_NOTES.md) and [the
three-minute demo plan](docs/review/OPENAI_SUBMISSION_VIDEO_SCRIPT.md).

## What is working now

- A Cloudflare Worker backed by Durable Objects, D1, R2, and an alert Queue/DLQ.
- Public, read-only room, roster, agent-detail, event-feed, and WebSocket
  observation surfaces.
- Administrative project/agent registration and heartbeat/status routes.
- Signed, idempotent operational event ingress with timestamp/replay checks and
  secret-shaped metadata redaction.
- Runtime-neutral liveness: a signed `heartbeat` event can arrive from an
  agent package, CI runner, webhook adapter, or MCP/REST integration; no
  persistent WebSocket connection is required for an agent to remain present.
- Guardrail decisions for duplicate/runaway chains, validation failures,
  budgets, cooperative leases, controlled tool authorization, and heartbeat
  expiry/watchdog incidents.
- Hash-chained audit decisions, incident records, bounded evidence exports, and
  an embeddable dependency-free JavaScript widget.
- A standard-library Loop Enforcer adapter that treats a denied lease, gate, or
  controlled-tool decision as a stop result (`exit 3`).

## Deliberate current boundaries

Watchtower is not represented as more complete than it is. The following are
now available as an additive API lifecycle, but still need browser onboarding,
credential rotation/revocation UI, and production migration/release evidence:

- Owner credentials and per-agent scoped credentials returned once at
  registration; credentials stay on the owner/agent host, never on `watch`.
- Canonical manifests plus owner → credential → connect → heartbeat/event →
  watchdog offline → reconnect lifecycle endpoints.
- Normalized organization application questions/answers and secure
  applicant/reviewer roles. The legacy five-question application record exists,
  but it is not the finished organization product.
- Payments, x402 settlement, subscriptions, or tier enforcement.

The public `watch` host remains read-only. It does not host credential entry,
webhook, MCP, or mutation endpoints. See [AGENTS.md](AGENTS.md) for the
authoritative current-state boundaries and
[the execution checklist](docs/blueprint/federation-watchtower/checklist.md)
for work that may actually be marked complete.

### Access, organization, and Federation setup

The roles are deliberately separate:

- **Agent:** the runtime that connects, heartbeats, and emits one bounded
  operational statement/event at a time using an `fw_agent_…` credential.
- **Project owner:** the person or project responsible for registering agents
  using an `fw_owner_…` credential. Owner access is not agent access.
- **Organization applicant:** an owner submitting organization identity, an
  official HTTPS URL, two or more non-GitHub proofs, and exactly five technical
  answers. Verification expands trust and management; it does not block basic
  agents.
- **Administrator:** the deployment operator using `WATCHTOWER_ADMIN_TOKEN` to
  create projects/MCP organization principals, review Federation applications,
  manage incidents and budgets, and export evidence.

Read [Access and Onboarding](docs/review/ACCESS_AND_ONBOARDING.md) for the
exact curl flows, credential boundaries, MCP organization setup, application
review procedure, and the current limitations of browser signup. The public
organization guide is available at
[`watch.drdeeks.xyz/organization.html`](https://watch.drdeeks.xyz/organization.html).

## Architecture

```text
agents, integrations, MCP clients
              |
              v
      fapi.drdeeks.xyz (REST / WebSocket / control plane)
              |
              v
       Cloudflare Worker: federation-gateway
        |         |          |          |
        v         v          v          v
      D1       Durable      R2      Queue + DLQ
     records    Objects    evidence  owner alerts
        |
        v
watch.drdeeks.xyz (public, read-only Watchtower)
```

| Host | Audience | Purpose |
| --- | --- | --- |
| `watch.drdeeks.xyz` | Everyone | Public Watchtower: real public rooms, agent detail, and public event feed. |
| `fapi.drdeeks.xyz` | Agents and integrations | Health, REST, signed ingestion, WebSocket, MCP, and control-plane routes. |
| `federation.drdeeks.xyz` | Approved members/operators | Reserved member area and the current token-protected operator console. |

## Judge quickstart

### Live observation

1. Open [watch.drdeeks.xyz](https://watch.drdeeks.xyz).
2. Pick a room and select an agent from the roster.
3. Inspect the public event terminal and agent detail drawer.
4. Open [fapi.drdeeks.xyz](https://fapi.drdeeks.xyz) for API discovery or
   [fapi.drdeeks.xyz/health](https://fapi.drdeeks.xyz/health) for a health
   response.

The public view intentionally exposes no operational credential and does not
create demo agents or fake events.

### Local demo (no cloud account required)

Requirements: Node.js 20+.

```bash
node source/federation-tv-package/federation-core/demo-gateway.js
```

Open `http://localhost:41207/`, then run the contract check in another shell:

```bash
node source/federation-tv-package/federation-core/demo-verify.js
```

This adapter is an in-memory demonstration path, not the persistent production
service.

### Production-shaped Worker locally

```bash
cd source/federation-serverless
npm install
npx wrangler dev --local --port 8787
```

For protected operator functions, use an ignored local `.dev.vars` file; never
commit it. Open `http://localhost:8787/operator.html?api=http://localhost:8787`
and provide the admin credential only in the current tab. The full server
reference is in [source/federation-serverless/README.md](source/federation-serverless/README.md).

## Verify the repository

```bash
cd source/federation-serverless && npm run types && npm test
cd ../../packages/watchtower-sdk && npm test
node --check ../../source/federation-tv-widget/public/tv-widget.js
node --check ../../source/federation-tv-widget/src/tv-widget.js
git diff --check
```

`npm run check` is not currently a valid verification gate with the installed
Wrangler version; do not treat it as passing project validation.

## Integration highlights

### Public widget

```html
<div id="federation-tv"></div>
<script
  src="https://watch.drdeeks.xyz/tv-widget.js"
  data-project="autopilot"
  data-gateway="https://fapi.drdeeks.xyz">
</script>
```

### Guarded operation

The integration path is deliberately cooperative and pre-action rather than a
generic proxy. Before a consequential tool call, an agent validates its bounded
lease or requests a scoped tool decision. A denial means the agent must stop;
the adapter exits with code `3` and Watchtower retains the denial as evidence.

```bash
export WATCHTOWER_INGESTION_SECRET='set-outside-the-repository'
python3 source/federation-tv-package/mcp-skill/federation-agent/watchtower_loop.py \
  --project autopilot --agent build-01 lease --run deploy-42 --scope deploy
```

The shared ingestion secret remains an administrative/integration boundary and
is never a browser credential. Canonical lifecycle clients use per-agent scoped
credentials instead; the legacy signed producer API remains available for
existing integrations.

### Webhook-first presence and alerting

Watchtower has two independent webhook roles:

| Direction | Purpose | Current behavior |
| --- | --- | --- |
| **Inbound presence/event webhook** | An agent package, CI job, scheduler, or integration posts a signed operational event such as `heartbeat`, `run.started`, `run.failed`, or a validation result. | The existing signed `/api/v1/events` ingress validates the timestamp and HMAC, deduplicates the event, persists it, and arms the per-agent watchdog when the event is a heartbeat. |
| **Outbound incident webhook** | Watchtower notifies an organization’s chosen endpoint about a watchdog, budget, validation, or control incident. | A Durable Object records the notification, a Queue delivers it with bounded retries and a dead-letter path, and `WATCHTOWER_ALERT_WEBHOOK_FORMAT` selects the payload: `slack`/`discord` post a readable one-line alert to a channel’s incoming-webhook URL, while `json` (default) posts an HMAC-signed envelope a custom receiver verifies. No configured destination means a safely recorded `suppressed` delivery, not an accidental outbound request. |

To receive incident notifications in Slack or Discord, create an incoming-webhook
URL for the channel, set it as the `WATCHTOWER_ALERT_WEBHOOK_URL` secret, and set
`WATCHTOWER_ALERT_WEBHOOK_FORMAT` to `slack` or `discord`; the channel URL is the
credential, so no signing secret is required. When a watchdog, budget,
validation, or control incident fires, the queue delivers a readable alert to
that channel. The default `json` format instead posts a signed envelope that a
self-hosted receiver (`POST /api/v1/alert-sink`) verifies and records as an
immutable receipt, surfaced read-only in the operator console. The format set is
intentionally small so further destinations can be added behind the same switch.

Canonical registration stores a per-agent heartbeat deadline from 30–3600
seconds (use 1800 seconds for a 30-minute async grace). Every accepted
heartbeat resets the Durable Object alarm; expiry marks the same identity
offline, retains a real `heartbeat.missed` watchdog event, and can notify the
configured outbound incident webhook. A later connect or heartbeat resumes the
same identity and history. Browser onboarding and owner-controlled liveness
profiles are the remaining UX/management work.

## Documentation

- [AGENTS.md](AGENTS.md) — operational truth, domain boundaries, and required
  next lifecycle.
- [Execution checklist](docs/blueprint/federation-watchtower/checklist.md) —
  authoritative completion state.
- [System specification](docs/review/FEDERATION_SYSTEM_SPEC.md) — expanded
  product context.
- [Host surface contract](docs/review/HOST_SURFACE_CONTRACT.md) — public,
  member, and machine host boundaries.
- [Serverless gateway README](source/federation-serverless/README.md) — route,
  signing, local deployment, and operational reference.
- [Submission notes](docs/review/OPENAI_SUBMISSION_NOTES.md) — Devpost draft
  and evidence plan.
- [Build Week readiness review](docs/review/OPENAI_BUILD_WEEK_READINESS.md) —
  current Devpost requirements, evidence mapping, and remaining submission
  actions.
- [Demo script](docs/review/OPENAI_SUBMISSION_VIDEO_SCRIPT.md) — a real,
  under-three-minute control-loop demonstration.
- [Submission runbook](docs/review/SUBMISSION_RUNBOOK.md) — exact release,
  demo, and Devpost handoff steps.

## Build Week submission checklist

- [ ] Select **Developer Tools** in Devpost.
- [ ] Add the public repository URL (or share a private repository with both
  `testing@devpost.com` and `build-week-event@openai.com`).
- [ ] Record a public YouTube video under three minutes that shows the project
  working and explains both Codex and GPT-5.6 use.
- [ ] Add the `/feedback` Codex session ID for the session that built the
  majority of the core functionality.
- [ ] Provide judge testing instructions; this README supplies live and local
  paths above.
- [x] Standalone Devpost project is published with the Federation thumbnail
  and repository, live-service, Federation, and npm links.
- [ ] Answer Devpost's required submitter type, residence, category, repository
  URL, and feedback-session fields; add any plugin/developer-tool instructions
  if applicable.
- [ ] Submit the **Federation Watchtower** Devpost project to OpenAI Build Week
  rather than leaving it only as a published standalone project.

The last item is currently outstanding: the existing Federation Watchtower
Devpost project is published but is not yet attached to OpenAI Build Week.

## License

MIT. See [LICENSE](LICENSE).
