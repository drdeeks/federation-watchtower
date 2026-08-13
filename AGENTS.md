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
  only): full god-view control over agents, rooms, and organizations.
  - **Agents**: list/filter/search, pause/resume/revoke any agent in any project.
    Pause is reversible (keeps the scene row). Revoke is the kill switch: it kills
    the agent's credentials, marks the canonical record revoked, and removes it
    from the live scene — records are preserved, but the agent must re-register to
    return.
  - **Rooms**: create rooms for organizations; delete any room (never blocked).
    Deleting a room never harms occupants — each agent still inside is **evicted**
    (relocated to the first available room in its project, which is the always-on
    HQ once temporary test rooms are gone), never revoked; credentials and records
    are always preserved. Killing credentials is only ever the explicit agent
    revoke action, never a side effect of a room operation. The WatchDog is
    presentation-only and is never an occupant, so it never blocks deletion.
  - **Organizations**: review applications (5 Q&A + social proofs), approve/reject/suspend.
    Approve/suspend were broken in production until migration 0010 (see
    "Validation before handoff") widens `federation_organizations.status`'s
    CHECK constraint — `reject` worked by coincidence, but the original code
    wrote the `mcp_organizations` vocabulary (`active`/`suspended`) into a
    column whose 0004 CHECK only allowed `draft/submitted/approved/rejected`,
    so every approve/suspend call threw a CHECK constraint violation. Do not
    describe organization approve/suspend as working until migration 0010 has
    actually run against `federation-db` — confirm via `wrangler d1 execute
    federation-db --remote --command "SELECT sql FROM sqlite_master WHERE
    name='federation_organizations'"` before relying on it.
  - **Alerts**: view all webhook delivery receipts with HMAC verification
  - **Evidence**: export project evidence to R2 with configurable retention
  Backed by `/api/v1/admin/*` endpoints (`src/management.ts`). All mutations logged via `federation_lifecycle_events`.
- Mandatory registration statement: every canonical agent manifest must include
  a `statement` (≤120 chars, required, not optional); it is written once into
  `federation_speech_lines` at registration alongside the five Q&A answers an
  organization application submits. This is the only way the public speech
  pool grows — there is still no free-form public chat/statement endpoint.
- React `OfficeStage` room diorama (the primary Watchtower visual, with a
  vanilla-widget fallback): renders the real registered roster per room (never
  a fictional cast), draws tone-matched speech-pool lines on character speech
  bubbles (never the event's own text — the event/feed caption is the
  operational record, the bubble is presentation), and keeps a permanent
  `WatchDog` mascot patrolling every room's floor. WatchDog is drawn outside
  the `agents` array from its own exclusive line list and can never enter the
  roster, feed, audit record, or state machine; ambient cameos (e.g. night
  shift) are similarly presentation-only and labelled
  `ambient presentation · no event`.
- Room creation (`POST /api/v1/admin/rooms`) returns a ready-to-paste embed
  snippet (`<script>` + container) scoped to that exact room; a single-project
  embed paints the project's registered name/emoji/color onto the office wall
  board so an approved organization's room reads as their own branded space.
- Operator console (`federation.drdeeks.xyz/operator.html`, admin-token only)
  can be locked to one project via `?project=<id>` — the project picker is
  hidden and every fetch stays scoped to that project's budget/sessions/
  incidents/tools. This is a front-end convenience for handing a
  single-project link to one organization's contact; it is not a credential
  boundary. There is still no separate per-organization operator credential —
  see the "important work that is not done" list.
- Provable outbound alert webhook. When a guardrail rule fires, the Worker
  signs the alert and POSTs it to the configured `WATCHTOWER_ALERT_WEBHOOK_URL`
  (opt-in; unset means deliveries are recorded `suppressed`). A self-hosted
  receiver `POST /api/v1/alert-sink` verifies the HMAC signature and appends an
  immutable receipt (`alert_webhook_receipts`, migration 0006); the operator
  console reads them via admin `GET /api/v1/admin/alerts` so alert delivery is
  visible rather than assumed. The delivery payload is destination-aware via
  `WATCHTOWER_ALERT_WEBHOOK_FORMAT`: `slack` and `discord` post a readable
  channel message to a free incoming-webhook URL (the URL is the secret; no
  signature), while `json` (default) posts the generic HMAC-signed envelope that
  a custom receiver such as `POST /api/v1/alert-sink` verifies. The format set is
  intentionally small so more destinations (PagerDuty, Teams, email relay) can be
  added later behind the same switch. Per-owner webhook destinations remain a
  separate, unbuilt increment.

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
- A separate per-organization operator credential. `operator.html`'s
  `?project=<id>` lock (see above) narrows the UI but still authenticates with
  the shared `WATCHTOWER_ADMIN_TOKEN`; it is not organization-scoped RBAC.
  **Owner's explicit directive (2026-08-13): organizations must never share
  the platform admin key.** This is not optional polish — it's the
  prerequisite for the next two items to work correctly, since neither
  branding nor webhook attribution can be scoped to "this org" without a
  real, distinct identity for that org to hold.
- Normalized organization questions/answers and a secure applicant/reviewer UX.
- Payments, subscriptions, x402 settlement, and tier enforcement.
- **Organization branding (logo + color), gated on approval status.**
  `projects.color`/`projects.emoji` columns already exist in the schema and
  are already read by `getAllRooms()` for room display, but the only writer
  (`lifecycle.ts`'s canonical registration) hardcodes `color: "#4fd1c5",
  emoji: "📡"` for every project unconditionally — no field exists anywhere
  to customize it. A `logo` concept doesn't exist in the schema at all
  (only the single emoji character). Owner's directive: an organization
  gets **no** customization by default — only after being accepted/approved
  should it have the opportunity to upload a logo and choose a color scheme
  for its room. Needs: a logo field/upload path (no image storage wired to
  `federation_organizations` today, though `federation-vault` R2 bucket
  exists for evidence exports and could plausibly serve this), a real color
  picker somewhere in the org's own flow (not admin-only), and an
  approval-status gate in front of both.
- **Per-organization and per-agent designated webhook destinations.**
  Today's alert webhook is global and singular
  (`WATCHTOWER_ALERT_WEBHOOK_URL`/`WATCHTOWER_ALERT_WEBHOOK_FORMAT`, one
  destination for the whole platform — see `alert-webhook.ts` and
  `docs/review/COMPLETE_SPEC.md` §4). Owner wants each organization AND
  each individual agent to have its own webhook, so notifications are
  correctly attributed to the actual recipient instead of all funneling
  through one shared destination. Depends on the real per-org/per-agent
  identity item above — attribution is only meaningful once there's a real
  distinct identity to attribute to.
- **Watch page's "On camera" counter needs a companion global-total stat,
  not a replacement.** `index.html`'s `agent-count` (labeled "On camera")
  is deliberately scoped to whichever room is currently selected — a
  code comment there explains this was a fix for a real prior bug (a
  global count next to a single-room diorama produced "nonsense like '15
  agents live' next to a 3-agent room"). Do not revert that. Owner wants a
  genuinely separate, clearly-labeled total showing every currently
  active/registered agent platform-wide, displayed alongside the existing
  room-scoped count. `GET /api/status` → `FederationCoordinator.getSystemStatus()`
  already computes a real global total (`SELECT COUNT(*) FROM
  federation_agents WHERE lifecycle_state != 'revoked'`) — it's just not
  wired into any page's UI yet. This is additive, not a fix to the existing
  counter.
- **Character Kit ⇄ Watchtower adapter (`~/projects/hackathon/canonical/adapter/`)
  needs review and finalization to become genuinely functional**, not just
  scaffolded. Per that adapter's own README (last checked 2026-08-13):
  12/12 unit tests pass and `tsc --noEmit` is clean, but `character-kit.ts`
  is an explicit boundary stub that throws "unavailable" by design — no live
  Character Kit socket connection, no live delivery to any real Watchtower
  instance has ever been exercised. Not yet reviewed in this repo's context;
  do that review before attempting to wire it up for real.

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
  "heartbeat": { "intervalSeconds": 30 },
  "statement": "One line this agent adds to the public speech pool"
}
```

`statement` is required (≤120 chars, non-empty) — this is how the speech pool
"builds over time," one line per agent at registration plus five Q&A per
organization application. Validation must reject secrets in metadata,
duplicate IDs, unauthorized owner claims, invalid capabilities, invalid
palette/avatar keys, a missing/invalid statement, and invalid heartbeat
intervals. A valid response must return the stable agent record,
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

### D1 migration gotcha: recreating a table with inbound foreign keys

SQLite cannot widen/narrow a `CHECK` constraint or drop a column constraint in
place — the standard recreate pattern is `CREATE new → INSERT SELECT old →
DROP old → RENAME new`, used by migrations 0009 and 0010. That pattern is
safe when nothing else references the table (0009). It is **not** automatically
safe when other tables hold a `FOREIGN KEY` into the table being rebuilt
(0010's `federation_organizations`, referenced by
`federation_organization_social_proofs`, `federation_organization_questions`,
and `federation_agents`):

- D1 runs each `wrangler d1 execute --file` as a single transaction with
  foreign keys enforced (matching `PRAGMA foreign_keys = on`).
- `DROP TABLE` on a referenced parent orphans the child rows for the duration
  of the transaction. SQLite's deferred-FK violation *counter* is incremented
  by that drop and is **not** decremented by the subsequent rename, so
  `PRAGMA defer_foreign_keys = true` does not save you — the `COMMIT` still
  fails with `FOREIGN KEY constraint failed`, even though `PRAGMA
  foreign_key_check` reports no violations and the final data is fully
  consistent. This was verified against a real remote D1 database, not just a
  local SQLite shim — the naive recreate reproducibly failed and rolled back
  cleanly on D1 with exactly that error.
- The working fix (see 0010): detach every child from the parent *before* the
  rebuild — null out nullable child foreign keys (e.g. `federation_agents
  .organization_id`) into a scratch table, and stash+clear NOT-NULL child rows
  into scratch tables — then rebuild the parent, then reinsert/restore the
  children from scratch, then drop the scratch tables. Verify locally with
  `PRAGMA foreign_keys = ON` and the whole file wrapped in one
  `BEGIN; ...; COMMIT;`, matching D1's execution model, before ever running
  `--remote`.
- Prefer proving a risky migration against a disposable forked D1 database
  (`wrangler d1 create <name>-staging`, free on the Workers Free plan — 10 D1
  databases / 5 GB included) rather than production. Load the same migration
  chain, seed representative rows in every inbound-FK child table, and confirm
  the migration succeeds and the CHECK actually rejects invalid values before
  running it against the real database.

### Next steps (handoff — do not re-derive, read this first)

Open threads left in-flight; pick up here instead of re-investigating from
scratch. **Updated 2026-08-13** — items 2 and (partially) 4 below from the
prior version of this section are resolved; see CL-0034/0035/0036.

1. **Org approve/suspend fix — code done, migration proven, still NOT
   deployed.** `management.ts` writes the canonical `'approved'`/`'suspended'`
   enum values; migration `src/migrations/0010_organizations_widen_status.sql`
   widens the CHECK. Verified against the free `federation-db-staging` fork
   (id `929f8ef0-daf9-4e43-b88e-daf226df24ae`) — still not run against
   production. This is now on `fix/rooms-agents-migrations` (merged
   2026-08-13, commit `663b4a6`), not stuck on an isolated worktree branch
   anymore. Next: explicit go-ahead, then `npm run
   migrate:organizations-widen-status` (remote) + deploy.
2. ~~`fix/rooms-agents-migrations` branch is blocked~~ — **RESOLVED
   2026-08-13.** Both orphaned worktree branches
   (`worktree-bridge-cse_011McsXiCUReHKCuBhtdfYQc` org-migration,
   `worktree-bridge-cse_01P91YhKrzoDMTyFfhAsCd32` rooms) merged into
   `fix/rooms-agents-migrations` (commits `663b4a6`, `2eef8f3`). The
   competing `management.ts` room-delete edit mentioned in the old version of
   this note was resolved by taking the eviction-based approach
   (`63acb8e`) wholesale — it fully supersedes the narrower offline-aware
   block it replaced. Both worktree branches kept on disk as backups (not
   deleted). Branch is now 9 commits ahead of `origin/main`, **not pushed**.
3. **Watchtower HQ now has real identity, but is intentionally NOT
   code-blocked from deletion.** `room_index 0` (every project's
   auto-created first room, where `assignToRoom()` always lands
   self-registering agents by construction) is now labeled "Watchtower HQ"
   in the public Watch room picker and the admin console, with an extra
   confirm() warning before deleting it in `manage.html`. Owner's explicit
   call: leave it deletable — `/api/v1/admin/rooms/*` is already
   `requireAdmin()`-gated on the shared token only the owner holds, so a
   hard block would be redundant; organizations never reach this endpoint.
4. **Org-management cascade behavior is unbuilt.** Pause should pause an
   org's agents; delete should evict agents to HQ and remove rooms while
   preserving records. Separate from the CHECK-constraint fix above — not
   started. Related, also unbuilt: real per-organization operator
   credentials — `operator.html`'s `?project=<id>` lock narrows the UI but
   still authenticates with the shared admin token, not org-scoped RBAC (see
   "Important work that is not done" above). The owner's stated intent:
   organizations should ultimately manage only their own room and agents.
5. **`.claude/` + root `CLAUDE.md` git-history cleanup is still paused for
   the history-rewrite part.** The rooms worktree's `9b824d2` (merged
   2026-08-13) untracks `.claude/` and `CLAUDE.md` **going forward only** —
   files stay on disk, just stop being version-controlled from this commit
   on. It does **not** purge them from the old commits already on public
   `origin/main`. That rewrite still needs the hackathon manager's
   permission (user emailed, unconfirmed as of this writing) — do nothing to
   remote history until that's confirmed.
6. **Hardcoded agents/rooms fully removed from code, 2026-08-13 (CL-0036).**
   The live Worker/widget only ever had `'autopilot'` as a single default
   value (never a roster); the real fixed 5-project roster
   (Autopilot/Aires/Agora/Edgewalker/Mnemosyne) lived entirely in
   `federation-tv-package/` — confirmed still required (it's the local
   backend `tv-sitcom-mcp`'s MCP server talks to on :41207), so genericized
   rather than deleted. See CL-0036 for the full file list. Production
   `federation-db` still has the demo/test rows for those 5 project ids
   sitting in several tables (partially cleaned mid-session, then explicitly
   paused by the owner — "don't fuck anything up on the databases" — before
   `rooms`/`agents`/`federation_agents`/`projects`/`operational_events`/
   `audit_events` were touched). That DB cleanup is still open, deliberately
   not resumed without explicit direction.
