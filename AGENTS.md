# Federation Watchtower — AGENTS Guide

This is the operational guide for people and coding agents working in this
repository. Read it before changing the system.

## What Federation Watchtower is

Federation Watchtower is an independent, runtime-neutral observability and
coordination layer for autonomous agents. An agent retains control of its own
runtime and reports identity, presence, and real operational events to
Federation. The public Watchtower presents that activity as a compact,
security-camera-style sitcom.

The product rule is simple:

> Operational truth is the product. Theatrical presentation makes it watchable.

The TV layer may be funny, weird, and memorable. It must never fabricate an
agent, successful action, safeguard result, heartbeat, owner, event, or log
entry. Ambient presentation is allowed only when it is visibly labelled as
presentation with no source event.

## Authority and reading order

1. `docs/blueprint/federation-watchtower/checklist.md` is the execution driver.
   Do not mark work complete until its acceptance evidence exists.
2. `docs/blueprint/federation-watchtower/blueprint.md` is immutable reference
   material. Do not edit it for ordinary implementation work.
3. `docs/blueprint/federation-watchtower/CHANGELOG.md` is append-only. Record
   material implementation work using the Part V format from the blueprint.
4. `docs/review/FEDERATION_SYSTEM_SPEC.md` gives the current expanded product
   context. `docs/review/HOST_SURFACE_CONTRACT.md` records current domain
   boundaries and explicit gaps.
5. `docs/review/ACCESS_AND_ONBOARDING.md` defines the agent, owner,
   organization-applicant, and administrator boundaries.

Never change checklist state to make progress look better than it is.

## Domain map

| Host | Audience | Purpose |
| --- | --- | --- |
| `https://watch.drdeeks.xyz` | Everyone | Public, read-only Watchtower: room view, public roster, public agent details, feed, agent/organization onboarding documentation, hosted agent skill. |
| `https://federation.drdeeks.xyz` | Approved members/operators | Reserved Federation/member area and token-protected operator console. Organization-scoped roles are not implemented yet. |
| `https://fapi.drdeeks.xyz` | Agent hosts/integrations | Health, REST, signed event ingestion, MCP, WebSocket, and control-plane endpoints. |

Do not put credential entry forms, webhooks, MCP, or mutating API endpoints on
`watch`. Public observation is free and read-only.

## Current repository map

| Path | Responsibility |
| --- | --- |
| `source/federation-serverless/` | Cloudflare Worker, Durable Objects, D1 schema/migrations, watchdog, control loop, MCP gateway. |
| `source/federation-tv-widget/` | Static public Watchtower and embeddable browser widget. Keep `src/tv-widget.js` and `public/tv-widget.js` identical. |
| `packages/watchtower-sdk/` | Published Node/server-side signing SDK and source/tests for `@federation-watchtower/sdk`. |
| `source/federation-tv-package/` | Local demo package and legacy adapter/MCP material; useful for provenance and offline demos, not the production source of truth. |
| `brand/` | Canonical wordmark, mark, theme tokens, and splash assets. Copy intentional changes into `source/federation-tv-widget/public/brand/`. |

## Current reality: what exists and what does not

### Useful baseline that exists

- Durable project/agent/room records, public project/room/feed reads, and a
  legacy agent registration route.
- Deterministic browser SVG avatars plus a legacy DiceBear avatar URL.
- Signed operational event ingestion at `POST /api/v1/events`.
- Event redaction, idempotency handling, runaway/duplicate/attempt/budget rules,
  watchdog incidents, cooperative leases, controlled-tool decisions, audit
  hashing, and operator evidence exports.
- MCP organization credential handling and a published server-side SDK at
  `@federation-watchtower/sdk@0.1.0`.
- Additive canonical owner/agent lifecycle endpoints: owner-issued scoped
  credentials, manifest validation, agent connect/heartbeat/event/disconnect,
  Durable Object watchdog expiry, and package-facing agent client support.
- Owner-bound organization application storage with two non-GitHub social
  proofs and exactly five normalized technical answers.
- Live browser self-serve onboarding on the Federation host
  (`federation.drdeeks.xyz/onboarding.html`): owner creation, agent
  registration, an in-browser live loop (connect / heartbeat / emit approved
  events / disconnect with manual, auto-interval, and one-shot triggers), and
  organization application submission — all driving the real lifecycle
  endpoints with scoped credentials only. Its canonical home is the Federation
  host; like every static page it is navigationally reachable across hosts
  (static assets are served ahead of the Worker — there is no `run_worker_first`),
  and every mutating call targets `fapi`. The enforced boundary is unchanged:
  `watch` still serves no mutating API, MCP, or webhook route, because those are
  Worker-handled paths, not static files.
- Public Watchtower camera shell, room selection, agent roster/detail panel,
  public event terminal, reduced-motion mode, and feed-only mode.
- Operator management console (`federation.drdeeks.xyz/manage.html`, admin-token
  only): list every canonical agent with owner/room/state, pause/resume, and
  revoke, plus status tiles and the embedded live floor. "Revoke" invalidates the
  credential and drops the agent from the public scene but preserves its event
  evidence. Backed by `/api/v1/admin/agents*` (`src/management.ts`). Room
  lifecycle management is the next increment.
- Provable outbound alert webhook. When a guardrail rule fires, the Worker
  signs the alert and POSTs it to the configured `WATCHTOWER_ALERT_WEBHOOK_URL`
  (opt-in; unset means deliveries are recorded `suppressed`). A self-hosted
  receiver `POST /api/v1/alert-sink` verifies the HMAC signature and appends an
  immutable receipt (`alert_webhook_receipts`, migration 0006); the operator
  console reads them via admin `GET /api/v1/admin/alerts` so alert delivery is
  visible rather than assumed. Point `WATCHTOWER_ALERT_WEBHOOK_URL` at
  `https://fapi.drdeeks.xyz/api/v1/alert-sink` (with a shared
  `WATCHTOWER_ALERT_WEBHOOK_SECRET`) for a self-contained working webhook.
  Per-owner webhook destinations remain a separate, unbuilt increment.

### Important work that is not done

- Credential rotation/revocation UI and organization-scoped reviewer/operator
  role enforcement (self-serve owner/agent onboarding and org submission are now
  live per above; review, RBAC, and key rotation are not).
- A persisted per-agent action/trigger catalog: agents declaring and saving
  which events they emit and how those fire at registration time. The onboarding
  live-loop action picker selects from the approved event set at runtime only; a
  manifest still carries just a `capabilities` string list.
- Release evidence for the canonical lifecycle migration and production
  end-to-end test. Never expose the shared ingestion or administrator secret in
  a browser.
- Stream cursors, public snapshots, and a complete room-family model.
- Public individual statement submission/moderation; the legacy speech pool is
  only for verified Federation agents.
- Normalized organization questions/answers and a secure applicant/reviewer UX.
- Payments, subscriptions, x402 settlement, and tier enforcement.

Do not describe any item in this second list as live or complete.

## Submission truth

Audited against the live Devpost OpenAI Build Week configuration on 2026-07-18:

- Devpost project **Federation Watchtower** (`1346118`) is published as a
  standalone project.
- The Federation mark thumbnail is uploaded and publicly retrievable.
- The project is **not yet submitted to OpenAI Build Week**.
- No public demo video is attached yet; the submission requires a public
  YouTube video under three minutes with audio explaining the build and the use
  of Codex and GPT-5.6.
- Required submission fields are submitter type, country of residence,
  category (`Developer Tools`), repository URL, `/feedback` session ID, plus
  the optional developer-tool testing instructions field.
- The repository, Watchtower, API, Federation member page, and published npm
  SDK are linked from the Devpost project.

Do not mark the hackathon submission complete until the user has entered the
required identity fields, attached the project to the `openai` challenge,
added the video and `/feedback` ID, and pressed the final submission action.

## Current legacy registration shape

The existing administrative route accepts a limited payload, roughly:

```json
{
  "agentId": "build-runner-01",
  "name": "Build Runner",
  "role": "build-and-test",
  "capabilities": ["build", "test", "report"],
  "status": "active",
  "metadata": {}
}
```

It is not the required product manifest. It has no owner/session proof,
signed immutable identity, public-projection consent, scoped credential,
palette contract, revocation, or canonical lifecycle transition rules.

## Phase 1: required functional end-to-end path

The next implementation phase is not another screen. It must establish this
working flow for both an individual and an organization-backed agent:

```text
owner/session
  -> validated manifest
  -> stable agent identity + avatar/palette
  -> scoped agent credential
  -> explicit connect
  -> heartbeat
  -> status/action/event updates
  -> public room projection
  -> stale/offline watchdog transition
  -> reconnect with the same identity and retained history
```

The canonical manifest must at least contain:

```json
{
  "agentId": "unique-stable-id",
  "displayName": "Human-readable name",
  "ownerId": "owner-or-organization-id",
  "projectId": "project-or-room-family-id",
  "role": "testing",
  "capabilities": ["testing", "reporting"],
  "identity": {
    "avatarSeed": "stable-seed",
    "paletteKey": "testing",
    "characterType": "operator"
  },
  "publicProjection": true,
  "heartbeat": { "intervalSeconds": 30 }
}
```

Validation must reject secrets in metadata, duplicate IDs, unauthorized owner
claims, invalid capabilities, invalid palette/avatar keys, and invalid
heartbeat intervals. A valid response must return the stable agent record,
assigned room, an appropriate scoped credential, request ID, and the exact next
connection step. It must not return a shared deployment secret.

## Event and control rules

- Events are immutable evidence. Preserve the source event and idempotency key.
- A failed validation, denied tool, stale heartbeat, or loop alert must remain
  visible; presentation cannot overwrite it.
- A non-active cooperative lease means stop before the next side effect.
- Agent status is never inferred from a decorative animation.
- Redact credentials and private data before persistence and before public
  projection.
- Public detail drawers show only allowed public identity/owner metadata. If no
  owner label is allowed, identify the owning project rather than inventing one.

## Watchtower presentation rules

- One selected room at a time; no fabricated multi-camera feeds.
- Target density is 35 compact agents, not oversized profile cards.
- Color assists recognition but never substitutes for name, owner, status, or
  lifecycle text.
- Event rows must distinguish operational events, presentation, and system
  state when the canonical projection exists.
- Public controls are read-only. There is no random-speech or demo-registration
  button on `watch`.
- Ambient cameos are sparse and labelled `ambient presentation · no event`.
  They never enter the agent list, event log, audit record, or state machine.
- Respect `prefers-reduced-motion`; default audio is muted when audio exists.

## Organization flow target

Organization verification enhances authority; it never blocks an individual
agent from participating. The organization path needs:

1. Owner-bound organization draft with contact, official website/repository,
   and two non-GitHub social proofs.
2. Exactly five technical questions and answers stored as attributable records.
3. Review status, reviewer decision, notes, and audit history.
4. On approval, organization namespace, elevated roles, room-management
   boundaries, and scoped integration credentials.
5. No ability to erase shared agent/event evidence.

The additive lifecycle migration stores exactly five normalized organization
questions/answers. Secure applicant/reviewer UX and organization role controls
remain unfinished.

## Security rules

- Never commit `.dev.vars`, environment files, API tokens, shared HMAC secrets,
  browser-stored admin tokens, or production request captures.
- Use HMAC/replay protection for webhooks and scoped credentials for agent and
  owner actions.
- CORS is not authentication.
- Treat administrative endpoints and organization review data as private.
- Do not create arbitrary URL proxying or background-execution claims.
- Keep public payloads family-friendly, technology-related, bounded in length,
  and free of personal/private data.

## Validation before handoff

Run the checks appropriate to the change:

```bash
cd source/federation-serverless && npm run types && npm test
cd packages/watchtower-sdk && npm test
node --check source/federation-tv-widget/public/tv-widget.js
node --check source/federation-tv-widget/src/tv-widget.js
git diff --check
```

The current `npm run check` script is not a valid project verification gate with
the installed Wrangler version. Do not cite it as passing validation.

For a production change, add targeted route/contract tests, run the required
remote migration only with an approved rollback plan, validate public domains,
and record the release evidence. Do not deploy merely because local tests pass.
