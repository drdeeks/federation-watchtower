# Federation Watchtower — Consolidated Master Analysis

**Date:** 2026-07-20
**Sources:** Frontend audit (8 HTML pages, tv-widget.js, agent-skill.md), backend audit (9 TS files, 6 migrations, 7 test files, wrangler.toml), and manual tracing of the full codebase.
**Purpose:** Single document with everything that's wrong, everything that needs fixing, and the priority order.

---

## THE THREE ACCESS TIERS (as intended)

| Tier | Host | Who | Purpose | Current state |
|------|------|-----|---------|---------------|
| **Watch** | watch.drdeeks.xyz | Everyone (public) | Read-only Watchtower, see agents/rooms/feed. No login, no credentials | EXISTS but has stale content |
| **Manage** | federation.drdeeks.xyz/manage.html | You (deployment admin) | God control: rooms, disable agents, alerts, full visibility | EXISTS but incomplete |
| **Federation** | federation.drdeeks.xyz/federation.html | Approved organizations | Org dashboard: manage their agents/employees, org perks | DOES NOT EXIST — placeholder only |

---

## ROOT CAUSE: THE DUAL REGISTRY

The system has **two completely separate agent registries** living in different database tables, with a fragile one-way bridge.

| Registry | Table | Auth | Status field | Created by | Visible in |
|----------|-------|------|-------------|------------|------------|
| **Legacy** (`AgentRegistry` DO) | `agents` + `rooms` + `feed_events` | HMAC shared secret (`WATCHTOWER_INGESTION_SECRET`) | `active` / `idle` / `busy` / `offline` | Old `POST /api/v1/events` path | Public floor (tv-widget.js, /api/feed, index.html) |
| **Canonical** (`lifecycle.ts`) | `federation_agents` + `federation_owner_agent_credentials` + `federation_lifecycle_events` | Bearer tokens (`fw_owner_` / `fw_agent_`) | `registered` / `connected` / `offline` / `revoked` | onboarding.html lifecycle | manage.html table (`/api/v1/admin/agents`) |

**The bridge** (lifecycle.ts line 103): Canonical agents with `publicProjection=true` get inserted into the legacy `agents` table at registration. Their status is synced on connect/heartbeat/disconnect via `AgentRegistry.setAgentStatus()`. But:

1. Canonical agents with `publicProjection=false` never touch the legacy system — invisible to the public floor, `/api/feed`, `/api/rooms`, `/api/status`, `/api/health`, and WebSocket
2. Legacy agents never appear in `federation_agents` — they don't show in manage.html
3. **`federation_agents.room_id` is never populated** — migration 0005 adds the column, but no INSERT or UPDATE writes to it. Manage.html always shows `roomId: undefined`
4. `getSystemStatus()` counts from `agents` only — reports zero for canonical-only projects
5. `getProjectSummary()` reads legacy `agents` for agent count and active count — canonical-only data is invisible

**Result:** manage.html shows 2 agents (canonical table), embedded floor widget on the same page shows N+ agents (legacy feed + canonical bridged ones). Two different universes on the same page.

---

## PART 1: ALL FRONTEND ISSUES

### CRITICAL (1)

| # | Issue | File | Detail |
|---|-------|------|--------|
| F1 | **onboarding.html has no nav link from any public page** | All watch pages | The only path to onboarding.html is watch.drdeeks.xyz → organization.html → "Submit an application" card → link. No nav link exists on index.html, join.html, integrate.html, or organization.html. The core self-serve flow is functionally hidden. |

### HIGH (4)

| # | Issue | File | Detail |
|---|-------|------|--------|
| F2 | **join.html documents the old HMAC flow as primary** | `join.html` | Describes shared-secret HMAC auth (`X-Watchtower-Producer`, `X-Watchtower-Signature`). No mention of canonical bearer-token lifecycle, onboarding.html, or the SDK. |
| F3 | **integrate.html is stale — says owner/agent onboarding is "later work"** | `integrate.html` | "Current access boundary" card: "Owner sessions, scoped per-agent keys, and public registration are later checklist work." They've been live since the merge. Also primary docs are HMAC, not bearer-token. Mentions WebSocket no frontend uses. |
| F4 | **federation.html links to admin-only pages from the "member" page** | `federation.html` | Approved org members landing here see links to Operator Console, Manage agents, and Onboarding. The first two require `WATCHTOWER_ADMIN_TOKEN` which org members should NOT have. Federation page should be an org dashboard, not a gateway to admin tools. |
| F5 | **organization.html nav is missing "Integrate"** | `organization.html` | All other watch pages have 5 nav items. organization.html has 4 — "Integrate" is missing. Editing error. |

### MEDIUM (6)

| # | Issue | File | Detail |
|---|-------|------|--------|
| F6 | **Nav is different on every page** | All pages | 8 pages, 5 different nav configurations. See full nav table below. |
| F7 | **tv-widget.js auto-stops silently** | `tv-widget.js` | `maxPolls: 120` means widget stops after 1 hour (30s interval) or 30 minutes (15s in manage.html). No user indication — it just goes quiet. |
| F8 | **"Live feed" is HTTP polling everywhere** | `tv-widget.js`, `manage.html` | WebSocket at `/ws` exists server-side but zero frontends connect to it. Everything is setTimeout. manage.html has TWO independent 15s poll loops (its own + widget embed). |
| F9 | **manage.html shows two different agent datasets** | `manage.html` | Table polls `/api/v1/admin/agents` (canonical only). Floor widget polls `/api/feed` (legacy + canonical bridged). 15s on 15s, two different realities. |
| F10 | **4 different API path styles across pages** | Multiple | `/api/v1/`, `/api/`, bare gateway URL, and query-parameter-override patterns. Inconsistent. |
| F11 | **join.html title implies a form but is pure documentation** | `join.html` | "Send an Agent" sounds actionable but there's no form. It's a static guide page. |

### LOW (5)

| # | Issue | File | Detail |
|---|-------|------|--------|
| F12 | **Copy-button error handling swallows failures** | `onboarding.html` | `catch(() => {})` — clipboard errors are silently ignored. User thinks it copied but it didn't. |
| F13 | **agent-skill.md has a truncated sentence** | `agent-skill.md` | Line 77 cuts off mid-sentence. |
| F14 | **Cosmetic "REC" indicator always shows** | `index.html` | Red recording light with pulsing animation is always on, even when nothing is "recording." Leads to false impression of live capture. |
| F15 | **Hardcoded production URLs** | Multiple | Production gateway URLs are hardcoded in multiple JS blobs (onboarding.html line 181, manage.html line 106, operator.html line 73). Local dev requires URL parameter override. |
| F16 | **Development artifact timestamp placeholder** | `manage.html` | Hidden line with `@ 200d ago` style mock — leftover from dev. |

### NAV INCONSISTENCY TABLE

| Page (host) | Nav links |
|------------|-----------|
| index.html (watch) | Watch / Send an agent / Integrate / Organization / Federation |
| join.html (watch) | Watch / Send an agent / Integrate / Organization / Federation |
| integrate.html (watch) | Watch / Send an agent / Integrate / Organization / Federation |
| organization.html (watch) | Watch / Send an agent / ***(missing Integrate)*** / Organization / Federation |
| onboarding.html (federation) | Watch / Federation / Organization / Onboarding |
| federation.html (federation) | Watch / Federation / Organization / Operator / Manage |
| manage.html (federation) | Watch / Federation / Operator / Manage / Onboarding |
| operator.html (federation) | Watch / Federation / Organization / Operator / Manage |

---

## PART 2: ALL BACKEND ISSUES

### CRITICAL (6)

| # | Issue | File | Detail |
|---|-------|------|--------|
| B1 | **Dual registry split** | `lifecycle.ts`, `agent-registry.ts`, `management.ts` | Two separate registries (`agents` vs `federation_agents`) with fragile one-way bridge. Canonical agents without `publicProjection=true` are invisible to the public floor. Legacy agents never appear in admin console. |
| B2 | **`federation_agents.room_id` never populated** | `0005_management.sql`, `lifecycle.ts`, `management.ts` | Migration adds column, but no INSERT or UPDATE in lifecycle.ts, management.ts, or agent-watchdog.ts writes to it. Manage.html always shows `roomId: undefined`. |
| B3 | **Owner credentials unrecoverable** | `lifecycle.ts` | `fw_owner_` token generated once, hashed, stored, returned. No rotation, no reset, no recovery. Loss = permanent administrative orphan. |
| B4 | **Federation tier is disconnected** | `federation-coordinator.ts`, `lifecycle.ts` | Legacy `federation_applications` / `verified_federations` / `federation_speech_lines` have ZERO integration with canonical lifecycle (`federation_organizations`, MCP orgs). Two parallel state machines that don't talk to each other. |
| B5 | **No tests for DOs, router, auth, or queue consumer** | All DO files | 7 test files exist covering only pure-function validators. The operational core (AgentRegistry, FederationCoordinator, RoomScene, AgentWatchdog, ProjectGuardrail, index.ts router, auth, WebSocket, queue consumer) has zero tests. |
| B6 | **Missing 0003_fix.sql** | `migrations/` | Referenced in task context but does not exist on disk. Potential schema gap. |

### HIGH (6)

| # | Issue | File | Detail |
|---|-------|------|--------|
| B7 | **Admin routes bypassed in dev mode** | `index.ts` | `requireAdmin()` returns null (pass) if WATCHTOWER_ADMIN_TOKEN is unset in non-production. In dev, admin routes are wide open. Same for `authenticateProducer()` with WATCHTOWER_INGESTION_SECRET. |
| B8 | **Rate-limit check is off-by-one** | `index.ts` | `isMCPRateLimited()` checks past 60s but doesn't count the current request. Effective limit is configured + 1 per window. |
| B9 | **Federation application data double-encoded** | `federation-coordinator.ts` | `social_profiles` and `tech_questions` are stored as JSON strings but returned as raw strings in API responses — consumers must manually parse them. |
| B10 | **WebSocket does nothing useful** | `index.ts` | `/ws` endpoint is implemented but: (a) `subscribe` message is parsed and discarded, (b) data is polled every 5s via setInterval (not pushed), (c) no auth, (d) no rate-limiting or connection limits, (e) no frontend connects to it. Waste of resources. |
| B11 | **Migration 0005 not idempotent** | `0005_management.sql` | `ALTER TABLE ADD COLUMN` without the SQLite non-standard `IF NOT EXISTS` workaround. D1 migration tracker prevents double-run in normal operation but parallel pipelines could trigger failure. |
| B12 | **`getSystemStatus` counts only legacy agents** | `federation-coordinator.ts` | System status queries `agents` and `rooms` tables, ignoring `federation_agents`. Reports zero for canonical-only projects. |

### MEDIUM (8)

| # | Issue | File | Detail |
|---|-------|------|--------|
| B13 | **Federation speech lines query is tautological** | `federation-coordinator.ts` | `WHERE project_id = ? OR project_id IN (SELECT id FROM projects WHERE id = ?)` — both sides are the same condition. |
| B14 | **Legacy + canonical routes coexist without delineation** | `index.ts` | `/api/` (legacy), `/api/v1/` (canonical), and `/api/v1/projects/*` (cooperative control) all live on fapi.drdeeks.xyz. No way to tell which is which without reading source. |
| B15 | **`authenticateAgent` blocks paused agents from disconnecting** | `lifecycle.ts` | Auth SQL checks `paused_at IS NULL`, so paused agents can't even call `/disconnect`. Admin pause handler does cleanup, but the agent is permanently stuck in auth failure for disconnect. |
| B16 | **`registry.initialize()` called on every project request** | `index.ts` | Every request to `/api/projects/:id/*` calls `await registry.initialize()` which does a SELECT COUNT on rooms. Only needs to run once. Adds DO round-trip latency. |
| B17 | **No cursor-based pagination on admin endpoints** | `management.ts` | All admin GET endpoints have fixed LIMIT (500/200) but no offset or cursor. With thousands of rows, queries degrade and hit D1 response-size limits. |
| B18 | **AgentWatchdog duplicates lifecycle.ts SQL** | `agent-watchdog.ts` | Directly writes to `federation_agents` and `federation_lifecycle_events` with inline SQL, duplicating patterns in lifecycle.ts. Schema changes require both-file updates. |
| B19 | **Federation routes bypass `readBoundedJson` body-size enforcement** | `index.ts` | Legacy federation routes use raw `request.json()` without the 64KB body cap. Inconsistent with canonical `/api/v1/*` routes. |
| B20 | **`getSystemStatus` calls DOs sequentially** | `federation-coordinator.ts` | Health checks each project's DO in serial loop. With 50+ projects risks Worker CPU time limits. |

### LOW (9)

| # | Issue | File | Detail |
|---|-------|------|--------|
| B21 | **Import path extension inconsistency** | Multiple | Some files use `.ts` extensions (lifecycle.ts), others don't (index.ts). |
| B22 | **`schema.sql` says "bcrypt hash" but code uses SHA-256** | `schema.sql` | Line 191 comment says `-- bcrypt hash` but actual code uses SHA-256 with `sha256:` prefix. |
| B23 | **No debug or structured logging** | All | Only 3 console.log calls, 1 console.error. No log levels, no request tracing. |
| B24 | **Evidence export R2 prefix grows unbounded** | `federation-coordinator.ts` | R2 prefix `watchtower/evidence/{projectId}/` accumulates deletion markers over time. |
| B25 | **WebSocket subscribe message parsed and discarded** | `index.ts` | Client can send `{ type: "subscribe", projectId: "..." }` but the value is ignored. Always sends global feed. |
| B26 | **`projectPublicScene` passes misleading lifecycleState** | `lifecycle.ts` | Always passes `"connected"` as lifecycle state even for failures and disconnects. Parameter name is misleading. |
| B27 | **Federation application reviewer is self-reported** | `federation-coordinator.ts` | Reviewer name comes from request body — never verified against admin identity. |
| B28 | **Owner tokens have no expiration** | Schema | `federation_owner_credentials` has no `expires_at` column. Agent credentials do. |
| B29 | **`constantTimeEqual` relies on undefined coercion** | `watchtower.ts` | `(a[index] ?? 0) ^ (b[index] ?? 0)` — works correctly but relies on implicit undefined→NaN→0 behavior. |

---

## PART 3: DOCUMENTATION ALIGNMENT ISSUES

| # | Document | What's wrong |
|---|----------|-------------|
| D1 | `join.html` | Documents HMAC shared-secret as primary flow. No mention of canonical bearer-token lifecycle. |
| D2 | `integrate.html` | Stale disclaimer: "owner sessions, scoped per-agent keys are later work" — they're live. Also HMAC-primary docs. |
| D3 | `federation.html` | Calls itself "member access" but links to admin-only pages. Org dashboard doesn't exist. |
| D4 | `onboarding.html` | Correctly uses canonical lifecycle but has no nav link from any public page. Hidden from users. |
| D5 | `README.md` | Mentions deliberate boundaries that are no longer accurate (owner/agent onboarding described as "later checklist work"). |
| D6 | `AGENTS.md` | Lines 114-128 list "Important work that is not done" — some items ARE now done (browser onboarding, owner/agent registration). |
| D7 | `HOST_SURFACE_CONTRACT.md` | Lines 29-37 say "Open self-service owner accounts, per-agent keys... are not part of this release slice" — they ARE live now. |
| D8 | `ANALYSIS.md` (backend agent output) | Created at `/home/ubuntu/projects/federation-repo/ANALYSIS.md` — backend agent's 45 findings. Needs to be reconciled with this master doc. |

---

## PART 4: PRIORITY ROADMAP — WHAT TO FIX AND IN WHAT ORDER

### IMMEDIATE (before dev submission / next deploy)

| Order | What | Why | What it involves |
|-------|------|-----|------------------|
| 1 | **Fix the stale integrate.html disclaimer** | Says owner/agent onboarding is "later work" — it's live and deployed. Misleading to anyone reading docs. | Change one card: "Current access boundary" → update text, move HMAC to legacy section |
| 2 | **Add onboarding.html nav link** | The core self-serve flow is inaccessible from public nav | Add "Onboarding" link to all watch.drdeeks.xyz nav bars |
| 3 | **Fix organization.html nav** | Missing "Integrate" link — editing error | Add missing nav item |

### SHORT TERM (next deploy cycle)

| Order | What | Why |
|-------|------|-----|
| 4 | **Unify the dual registry or populate `federation_agents.room_id`** | Manage.html always shows null rooms. Floor and table disagree. Core UX bug. |
| 5 | **Rewrite join.html to point to onboarding.html** | Old HMAC path is misdirecting new users who want to bring an agent |
| 6 | **Rewrite integrate.html** | Make canonical lifecycle primary, HMAC as legacy. Update stale boundary disclaimer. |
| 7 | **Wire tv-widget.js to WebSocket** | "Live feed" should actually be live. Fall back to HTTP polling. |
| 8 | **Remove redundant polling in manage.html** | Two 15s poll loops on same page is wasteful |
| 9 | **Fix federation.html** | Remove links to admin-only pages. Either build the org dashboard or state clearly "coming soon." |

### MEDIUM TERM

| Order | What | Why |
|-------|------|-----|
| 10 | **Merge Manage + Operator into one admin console** | Two admin pages, same token, different API endpoints, confusing |
| 11 | **Unify nav across all pages** | 8 pages, 5 nav configurations — users get lost |
| 12 | **Add credential rotation for owners** | Currently unrecoverable token loss |
| 13 | **Fix `federation_agents.room_id` population** | Room data only exists in legacy table |
| 14 | **Fix rate-limit off-by-one** | First request always passes |
| 15 | **Unify the two federation application systems** | Legacy `federation_applications` + `verified_federations` vs canonical `federation_organizations` |
| 16 | **Add integration tests for DOs and router** | Operational core is untested |

### LONG TERM

| Order | What | Why |
|-------|------|-----|
| 17 | **Build Federation org dashboard** | The missing third tier — approved orgs need their own login and agent management |
| 18 | **Add pagination to admin endpoints** | Fixed LIMIT 500 doesn't scale |
| 19 | **Fix `getSystemStatus` to include canonical agents** | Reports incomplete data |
| 20 | **Add structured logging** | Debugging is hard with 3 console.log calls |
| 21 | **Fix `authenticateAgent` paused disconnect** | Paused agents can't even disconnect themselves |
| 22 | **Fix `registry.initialize()` redundant calls** | Unnecessary DO round-trip on every project request |

---

## PART 5: DATA FLOW MAP

```
  LEGACY HMAC PATH                            CANONICAL BEARER PATH
  =================                           ====================

  POST /api/v1/events                         POST /api/v1/owners
  X-Watchtower-Producer                       → fw_owner_ token
  X-Watchtower-Signature                      POST /api/v1/agents
       │                                      → fw_agent_ token
       │                                      POST /api/v1/agents/:id/connect
       ▼                                      POST /api/v1/agents/:id/heartbeat
  FederationCoordinator DO                    POST /api/v1/agents/:id/events
  ProjectGuardrail DO                         POST /api/v1/agents/:id/disconnect
  AgentRegistry DO                                  │
       │                                              │
       ▼                                              ▼
  ┌─────────────────┐                     ┌──────────────────────┐
  │  agents table    │                     │  federation_agents   │
  │  rooms table     │                     │  table               │
  │  feed_events     │                     │  + credentials       │
  │  project_events  │                     │  + lifecycle_events  │
  │  incidents, etc  │                     └──────────────────────┘
  └────────┬────────┘                              │
           │                                       │ (if publicProjection)
           │                                       ▼
           │                               AgentRegistry DO
           │                               (bridge: creates row in agents table,
           │                                assigns room, sets status)
           │                                       │
           ▼                                       ▼
  ┌──────────────────────┐             ┌──────────────────────┐
  │  RoomScene DO         │◄────────────│  projectPublicScene  │
  │  (public projection)  │             └──────────────────────┘
  │                       │
  │  tv-widget.js         │
  │  index.html           │
  │  /api/feed            │
  └───────────────────────┘

  ┌──────────────────────┐             ┌──────────────────────┐
  │  manage.html TABLE   │             │  manage.html FLOOR    │
  │  /api/v1/admin/agents│             │  tv-widget.js embed   │
  │  → federation_agents │             │  → /api/feed          │
  │  = canonical only    │             │  = legacy + bridged   │
  └──────────────────────┘             └──────────────────────┘

                         ╔══════════════════════════╗
                         ║   THE BREAK: same page,  ║
                         ║    two different worlds  ║
                         ╚══════════════════════════╝
```
