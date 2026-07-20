# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Federation Watchtower is an agent-operations control plane: agents report identity, presence,
and real operational events (heartbeats, run lifecycle, validation gates, tool authorization),
and a Cloudflare Worker turns that into a public, security-camera-styled "Watchtower" plus
guardrail/incident tooling. **Operational truth is the product; the TV presentation layer must
never fabricate an agent, event, heartbeat, or safeguard result.** Read [AGENTS.md](AGENTS.md)
before making non-trivial changes — it is the authoritative operational guide (domain map,
current-vs-not-done boundaries, event/control rules, security rules).

Authority/reading order for anything beyond a small fix:
1. `docs/blueprint/federation-watchtower/checklist.md` — the execution driver. Do not mark work
   complete without its acceptance evidence, and never change checklist state to make progress
   look better than it is.
2. `docs/blueprint/federation-watchtower/blueprint.md` — immutable reference; do not edit for
   ordinary implementation work.
3. `docs/blueprint/federation-watchtower/CHANGELOG.md` — append-only, Part V format.
4. `docs/review/FEDERATION_SYSTEM_SPEC.md` and `docs/review/HOST_SURFACE_CONTRACT.md` — expanded
   product context and current domain-boundary gaps.
5. `docs/review/ACCESS_AND_ONBOARDING.md` — agent / owner / organization-applicant / administrator
   credential boundaries.

## Repository layout

| Path | Role |
| --- | --- |
| `source/federation-serverless/` | **Production Cloudflare Worker** — Durable Objects, D1, R2, WebSocket, MCP, static asset host. This is where almost all backend work happens. |
| `source/federation-tv-widget/` | Static public Watchtower site + embeddable browser widget (`public/` is deployed as-is by the Worker; `src/tv-widget.js` and `public/tv-widget.js` must stay identical). |
| `source/federation-tv-package/` | Local Node demo gateway, legacy adapter, and MCP skill material — useful for offline demos/provenance, **not** the production source of truth. |
| `packages/watchtower-sdk/` | Published `@federation-watchtower/sdk` — signed producer client + `FederationAgentClient` lifecycle client. Has its own test suite. |
| `brand/` | Canonical wordmark/mark/theme tokens. Copy intentional brand changes into `source/federation-tv-widget/public/brand/`. |
| `docs/blueprint/` and `docs/review/` | Execution/spec authority — see reading order above. |

## Commands

Backend Worker (`source/federation-serverless/`):
```bash
npm install
npm run types                 # regenerate worker-configuration.d.ts from wrangler bindings
npm test                      # node --experimental-strip-types --test src/*.test.ts
node --experimental-strip-types --test src/watchtower.test.ts   # run a single test file
npx wrangler dev --local --port 8787   # run the Worker locally with simulated bindings
npm run deploy                # wrangler deploy (real Cloudflare deployment)
```
`npm run check` (`wrangler check`) is **not** a valid verification gate with the installed
Wrangler version — don't cite it as passing validation.

D1 migrations (apply in order, additive only, remote only):
```bash
npm run schema               # src/schema.sql
npm run migrate:watchtower   # 0001 — event/incident tables, required before /api/v1/events
npm run migrate:control-loop # 0002 — leases, command receipts, notification delivery
npm run migrate:access-gateway # 0003 — sessions, budget ledger, controlled tools, evidence exports
npm run migrate:lifecycle    # 0004 — owner/agent credentials, canonical lifecycle, org applications
```

Full repo verification (also in AGENTS.md — run what's relevant to the change):
```bash
cd source/federation-serverless && npm run types && npm test
cd packages/watchtower-sdk && npm test
node --check source/federation-tv-widget/public/tv-widget.js
node --check source/federation-tv-widget/src/tv-widget.js
git diff --check
```

Local demo path (no Cloudflare account, Node 20+):
```bash
node source/federation-tv-package/federation-core/demo-gateway.js
node source/federation-tv-package/federation-core/demo-verify.js   # contract check, separate shell
```

Secrets are Worker secrets, never `wrangler.toml` vars, and `.dev.vars` is gitignored and must
never be committed:
```bash
npx wrangler secret put WATCHTOWER_INGESTION_SECRET
npx wrangler secret put WATCHTOWER_ADMIN_TOKEN
npx wrangler deploy --secrets-file .dev.vars   # deploy code + secrets together
```

## Architecture (`source/federation-serverless/`)

Single Worker (`federation-gateway`, entry `src/index.ts`) fronts three custom domains defined in
`wrangler.toml`, each with a distinct audience — never add credential entry, webhooks, MCP, or
mutating endpoints to `watch`:

| Host | Audience | Purpose |
| --- | --- | --- |
| `fapi.drdeeks.xyz` / `federation.drdeeks.xyz` | Agents, integrations, MCP clients | REST, WebSocket, signed event ingestion, MCP, control-plane routes |
| `watch.drdeeks.xyz` | Everyone | Public, read-only static Watchtower (served from `federation-tv-widget/public` via the `ASSETS` binding) |

Durable Objects (all SQLite-backed, declared in `wrangler.toml` `[exports.*]`):
- **AgentRegistry** — per-project agent/room state.
- **FederationCoordinator** — global state, MCP organization principals/access logs.
- **ProjectGuardrail** — per-project event/policy/incident coordinator (runaway/duplicate
  detection, leases, validation gates, controlled-tool authorization, budget ledger).
- **AgentWatchdog** — per-agent heartbeat deadline/alarm; expiry marks the agent offline and emits
  a deduplicated `heartbeat.missed` event.
- **RoomScene** — public room/scene projection.

Data plane: D1 (`federation-db`) for durable records, R2 (`federation-vault`) for evidence
exports, a Queue + DLQ (`watchtower-alerts`) for owner-alert delivery (opt-in — no configured
webhook means alerts are recorded `suppressed`, nothing is sent externally).

Two parallel API surfaces exist and use different auth:
- **Legacy/signed producer API** (`/api/v1/events`, leases, validation gates, tool authorization) —
  HMAC-SHA-256 over `<timestamp>.<exact raw body>` using the shared `WATCHTOWER_INGESTION_SECRET`,
  verified in `authenticateProducer()` in `src/index.ts`. This secret is an
  administrative/integration boundary, never sent to browsers.
- **Canonical lifecycle API** (`/api/v1/owners`, `/api/v1/agents`, `.../connect|heartbeat|events|disconnect`,
  in `src/lifecycle.ts`) — per-owner (`fw_owner_…`) and per-agent (`fw_agent_…`) bearer credentials
  issued once at registration, not the shared secret.

Administrative routes (`/api/v1/projects/{id}/incidents`, sessions, budget, evidence exports, MCP
organization management) require `Authorization: Bearer $WATCHTOWER_ADMIN_TOKEN`, checked via
`requireAdmin()`.

Remote MCP (`POST /mcp`, `src/mcp.ts`) is a Streamable HTTP endpoint gated by a per-organization
`Authorization: Bearer <orgId>.<apiKey>` credential (hashed, never stored/returned in plaintext),
with rate limiting, IP allowlisting, and scoped tools (status/incident/session/budget reads,
lease/gate/authorization operations, evidence export) — deliberately narrow, not a generic proxy.

Event validation, HMAC helpers, and runaway/duplicate policy live in `src/watchtower.ts`; treat it
as the core policy module most route handlers delegate into.

## Domain/security invariants worth knowing before touching code

- Events are immutable evidence — preserve source events and idempotency keys; a denied
  lease/gate/tool-authorization means the agent must stop before its next side effect.
- Redact credentials and secret-shaped metadata before persistence and before any public
  projection; public detail views only show explicitly allowed identity/owner metadata.
- Ambient TV "cameo" presentation must be visibly labelled and must never enter the real agent
  list, event log, audit record, or state machine.
- CORS is not authentication — administrative and MCP routes still require their bearer tokens.
