# Federation Ecosystem Hardening — ENTERPRISE BLUEPRINT
## Version: 1.0 | Document Class: MASTER SPECIFICATION
## Scope: PROJECT
### Generated: 2026-08-14

> **READ FIRST — DOCUMENT AUTHORITY**
> This document is the single source of truth. No feature may be built,
> no schema migrated, and no API changed without this document as the
> authoritative reference. All contributors MUST read Part V (Change
> Control Protocol) before touching any file. This document's change
> log is APPEND-ONLY. Prior sections may only be updated via a formal
> amendment with a corresponding CL entry.
>
> **Relationship to `docs/blueprint/federation-watchtower/blueprint.md`:**
> that document governs the original Federation Watchtower build (still
> live, still being amended). This document is a separate, later-stage
> initiative — hardening the credential model, completing the adapter,
> and building a genuinely new product surface (the Agent Control
> Console) on top of what that build shipped. It does not supersede or
> duplicate that blueprint; where this document references existing
> Federation code, it cites `docs/review/COMPLETE_SPEC.md` (a
> source-verified audit of the shipped system) as ground truth, not
> assumption.

---

## TABLE OF CONTENTS

```
PART I    — SYSTEM OVERVIEW & ARCHITECTURE
PART II   — MODULE REGISTRY
PART III  — SCREEN & FEATURE SPECIFICATIONS
PART IV   — DATA ARCHITECTURE
PART V    — CHANGE CONTROL PROTOCOL
PART VI   — MASTER IMPLEMENTATION CHECKLIST
PART VII  — QUALITY & COMPLIANCE STANDARDS
```

---

---

# PART I — SYSTEM OVERVIEW & ARCHITECTURE

> **Rollback Tag:** `[SYS-OVERVIEW-v1]`

## 1.1 Vision Statement

Three independent primitives already exist and already work in isolation:
Character Kit (local, fail-closed behavioral enforcement, one daemon per
agent workspace), the Character Kit ⇄ Watchtower bridge (a disposable
translator, Phase 2 of its own blueprint just completed), and Federation
Watchtower (federation/control/observability, live in production at
`fapi.drdeeks.xyz`/`watch.drdeeks.xyz`/`federation.drdeeks.xyz`). This
project does three things: (1) hardens Federation's credential model so
organizations and agent owners get real, non-shared identity instead of a
single admin token; (2) finishes the adapter's canonical wiring so agent
identity flows through the whole stack on real per-agent credentials, not
a shared HMAC secret; (3) builds the **Agent Control Console** — a new
Federation UI surface giving an agent owner direct, real-time visibility
and control (live feed, kill switch, `/steer`, memory/log viewing, habit
and command policy configuration, task mapping) over their own agents,
replacing today's admin-only, all-or-nothing management surface. The
defining principle, carried over from every existing rules file in this
ecosystem: **verify first, fail closed, keep primitives independent, and
never build a forceful control that the local enforcement primitive
cannot actually honor.**

## 1.2 High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              ENTRY LAYER                                  │
│                                                                            │
│  watch.drdeeks.xyz          federation.drdeeks.xyz         fapi.drdeeks   │
│  (public, read-only)        (member/operator space)        (API/MCP/WS)  │
│  ┌────────────┐             ┌────────────────────┐        ┌───────────┐ │
│  │ index.html │             │ onboarding.html     │        │  index.ts │ │
│  │ (Watch)    │             │ operator.html       │        │  (Worker) │ │
│  │ join.html  │             │ manage.html         │        │  mcp.ts   │ │
│  │ integrate  │             │ NEW: control.html ──┼───┐    │           │ │
│  │ .html      │             │ (Agent Control       │  │    └─────┬─────┘ │
│  └────────────┘             │  Console)             │  │          │       │
│                              └───────────────────────┘  │          │       │
└──────────────────────────────────────────────────────────┼──────────┼──────┘
                                                             │          │
┌────────────────────────────────────────────────────────────┼──────────┼──────┐
│                          APPLICATION LAYER                  │          │      │
│                                                              ▼          ▼      │
│  ┌───────────────────────┐   ┌──────────────────────────────────────────┐   │
│  │ src/lifecycle.ts        │   │ src/management.ts (admin, existing)      │   │
│  │ (canonical owner/agent, │   │ + NEW: src/operator-rbac.ts              │   │
│  │  existing)               │   │   (per-org operator credential, scoped  │   │
│  │                          │   │    to that org's own agents only)       │   │
│  └───────────┬──────────────┘   └───────────────┬──────────────────────┘   │
│              │                                    │                          │
│  ┌───────────▼────────────────────────────────────▼───────────────────┐    │
│  │ src/index.ts — request router                                       │    │
│  │  existing: /api/v1/events, /leases, /leases/{id}/validate,           │    │
│  │            /tools/authorize, /validation-gates, /commands[...]       │    │
│  │  NEW:      bearer-auth accepted on the 4 routes above (MOD-002)      │    │
│  │  NEW:      /api/v1/agents/{id}/{memory,logs,habits,commands-live}    │    │
│  │            (MOD-005, proxied through the adapter to the local daemon)│    │
│  │  NEW:      /api/v1/agents/{id}/steer, /api/v1/agents/{id}/kill       │    │
│  │            (MOD-006 — cooperative signal, see FEAT-006 fallback)     │    │
│  │  NEW:      /api/v1/{orgs,agents}/{id}/webhook (MOD-003)              │    │
│  │  NEW:      /api/v1/tasks[...] (MOD-007)                              │    │
│  └───────────┬──────────────────────────────┬──────────────────────────┘    │
│              │                                │                               │
│  ┌───────────▼──────────┐        ┌────────────▼─────────────┐               │
│  │ AgentRegistry DO      │        │ watchtower-alerts Queue    │               │
│  │ (rooms, agents,       │        │ + NEW: per-recipient       │               │
│  │  existing)            │        │   routing (MOD-003)        │               │
│  └───────────────────────┘        └────────────────────────────┘             │
└─────────────────────────────────────────┬──────────────────────────────────┘
                                            │ HTTP (canonical fw_agent_* bearer,
                                            │ MOD-004) + WebSocket (live feed)
┌───────────────────────────────────────────▼─────────────────────────────────┐
│                    ADAPTER LAYER — watchtower-ack-adapter                    │
│                                                                                │
│  ┌──────────────────┐   ┌───────────────────────┐   ┌──────────────────┐   │
│  │ character-kit.ts   │   │ adapter.ts (orchestr.) │   │ watchtower.ts      │   │
│  │ (Phase 2 DONE —    │◄──┤                        ├──►│ MOD-004: add        │   │
│  │  real socket RPC)  │   │                        │   │ FederationOwnerClient│   │
│  │ NEW: memory/logs/  │   │                        │   │ FederationAgentClient│   │
│  │ habit-config RPCs  │   │                        │   │ alongside legacy    │   │
│  │ (MOD-005)          │   │                        │   │ WatchtowerClient     │   │
│  └─────────┬──────────┘   └───────────────────────┘   └──────────────────┘   │
└────────────┼──────────────────────────────────────────────────────────────────┘
             │ Unix socket / TCP, newline-delimited JSON (verified protocol)
┌────────────▼──────────────────────────────────────────────────────────────────┐
│                    LOCAL LAYER — agent_enforcer_daemon.js                     │
│                                                                                 │
│  ┌────────────────┐  ┌──────────────────┐  ┌─────────────────┐  ┌─────────┐ │
│  │ enforcer.yaml    │  │ habits/*.yaml      │  │ memory/daily/    │  │ enforcer│ │
│  │ (allow/deny —    │  │ (existing, CLI-    │  │ *.yaml (existing,│  │ -audit  │ │
│  │  existing)        │  │  editable only)     │  │  DailyNotes)      │  │ .jsonl  │ │
│  │ NEW: remote        │  │ NEW: remote          │  │ NEW: remote        │  │ (exist.)│ │
│  │ edit RPC           │  │ CRUD RPC             │  │ read RPC            │  │ NEW:    │ │
│  │ (MOD-005)           │  │ (MOD-005)             │  │ (MOD-005)            │  │ tail RPC│ │
│  └────────────────┘  └──────────────────┘  └─────────────────┘  └─────────┘ │
│                                                                                 │
│  Fail-closed gate (executeTool) — the ONLY thing that can actually stop an    │
│  agent's next tool call. A remote "kill switch" (MOD-006) is a cooperative    │
│  signal relayed to THIS gate, not a forceful process kill — see FEAT-006.     │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 1.3 Tech Stack

| Layer | Technology | Rationale |
|---|---|---|
| Federation API/Worker | Cloudflare Workers, TypeScript, Durable Objects, D1 | Existing production stack (`source/federation-serverless`) — no change, extend in place |
| Federation UI (new: Agent Control Console) | Static HTML/vanilla JS, served via Workers Assets binding | Matches every existing page (`onboarding.html`, `operator.html`, `manage.html`) — no framework, no build step, consistent with `run_worker_first`/host-routing model already in place |
| Live feed transport | WebSocket (`wss://fapi.drdeeks.xyz/ws?projectId=...`, existing endpoint per `COMPLETE_SPEC.md` §2.8) | Already exists for self-hosted alert receiving; extend the same self-hosted-alert-receiver pattern for a per-agent live event stream instead of building new transport |
| Adapter | TypeScript, `node:net`, `@federation-watchtower/sdk` | Existing repo (`watchtower-ack-adapter`) — extend, don't replace |
| Character Kit daemon protocol | Newline-delimited JSON over Unix socket / TCP | Existing verified wire protocol (`agent_enforcer_daemon.js`) — extend with new RPC methods, same envelope |
| New Federation tables | Cloudflare D1 (SQLite dialect), migration-numbered `.sql` files | Matches existing `source/federation-serverless/src/migrations/000N_*.sql` convention exactly |

---

---

# PART II — MODULE REGISTRY

> **Rollback Tag:** `[MODULE-REGISTRY-v1]`
> **Rule:** Every change log entry MUST reference at least one Module ID
> (unless this Part is N/A for this scope).

| Module ID | Name | Description | Feature Flag |
|---|---|---|---|
| MOD-001 | Federation Identity & RBAC Foundation | Real per-organization operator credential, distinct from the shared `WATCHTOWER_ADMIN_TOKEN`; owner-facing self-service (list/pause/revoke own agents); credential rotation/revocation UI for `fw_owner_*`/`fw_agent_*`. Explicit prerequisite for MOD-003 and the Agent Control Console (MOD-006) per the owner's own directive recorded in `AGENTS.md`. | `FEAT_ORG_RBAC` |
| MOD-002 | Canonical Route Completion | Extend `fw_agent_*` bearer auth to the four routes still producer-signed-HMAC-only: lease validate, tool authorize, validation gates, commands (get + acknowledge). | `FEAT_CANONICAL_ROUTES` |
| MOD-003 | Per-Organization & Per-Agent Webhooks | Replace the single global `WATCHTOWER_ALERT_WEBHOOK_URL` with per-org and per-agent destinations, correctly attributing notifications. Depends on MOD-001. | `FEAT_SCOPED_WEBHOOKS` |
| MOD-004 | Adapter Canonical Client | Wire `FederationOwnerClient`/`FederationAgentClient` into `watchtower-ack-adapter`'s `watchtower.ts`, alongside (not replacing) the legacy `WatchtowerClient` — the four MOD-002 routes still need the legacy path until MOD-002 ships. | `FEAT_ADAPTER_CANONICAL` |
| MOD-005 | Character Kit Remote Bridge Surface | New daemon RPC methods (`get_memory`, `tail_audit`, `get_policy`, `set_policy`) exposed through the adapter, so a remote, authorized caller can read memory/logs and read/write habit + allow/deny + interval configuration — today these exist only as local files/CLI. | `FEAT_CK_REMOTE_BRIDGE` |
| MOD-006 | Agent Control Console | New Federation UI (`control.html`) + supporting API: live feed terminal per agent, kill switch, `/steer`, memory viewer, log viewer, habit/command/interval config editor — built entirely on MOD-005's new RPCs and existing Watchtower primitives (leases, commands, incidents). No new forceful-control primitive invented; see FEAT-006 for the kill-switch honesty constraint. | `FEAT_AGENT_CONSOLE` |
| MOD-007 | Task Mapping & Management | New primitive — Federation has no first-class "task" concept today (only incidents/leases/events, verified by grep against `source/federation-serverless`). Agent-scoped task registry: create/assign/track/complete, surfaced in the Agent Control Console. | `FEAT_TASK_MGMT` |
| MOD-008 | Documentation & Hackathon Alignment | Fix `agents-skill.md` doc drift (documents nonexistent `POST`/`PATCH` agent routes), fix `federation/AGENTS.md`'s stale adapter reference (wrong path, wrong status), and reconcile this whole blueprint's scope against the actual OpenAI Build Week submission requirements recorded in `AGENTS.md`'s "Submission truth" section. | `FEAT_DOCS_HACKATHON` |

---

---

# PART III — SCREEN & FEATURE SPECIFICATIONS

> **Rollback Tag:** `[SPECS-v1]`

## FEAT-001 — Per-Organization Operator Credential

- **Feature ID:** FEAT-001
- **Module Ref:** MOD-001
- **Rollback Tag:** `[FEAT-001-v1]`
- **Feature Flag:** `FEAT_ORG_RBAC`
- **Purpose:** Give each approved organization its own operator credential, scoped to only its own agents/rooms/incidents — replacing today's situation where `operator.html?project=<id>` is a UI convenience layered on the same `WATCHTOWER_ADMIN_TOKEN` as full platform admin.
- **Components:** New `federation_operator_credentials` table (Part IV); `POST /api/v1/organizations/{id}/operator-credential` (admin-issued, one-time reveal, same pattern as `fw_owner_*`); `authenticateOperator()` middleware mirroring `authenticateAgent()`'s hash-compare + active/non-revoked check; `operator.html` updated to accept this credential instead of the admin token when present.
- **Rules:** An operator credential's scope is hard-limited server-side to `organizationId` — every query in `operator-rbac.ts` filters by it, never trusts a client-supplied `project` param alone (today's `?project=` is client-side only). Revocation is immediate (hash removed/flagged, next request 401s).
- **Error States:** Expired/revoked credential → `401` with a message distinguishing "revoked" from "never existed" only in logs, not the response (avoid enumeration). Attempt to access another org's project → `403`.
- **Fallback:** Until MOD-001 ships, `operator.html` continues to accept `WATCHTOWER_ADMIN_TOKEN` — no regression, additive only.

## FEAT-002 — Canonical Bearer Auth on the Four Legacy-Only Routes

- **Feature ID:** FEAT-002
- **Module Ref:** MOD-002
- **Rollback Tag:** `[FEAT-002-v1]`
- **Feature Flag:** `FEAT_CANONICAL_ROUTES`
- **Purpose:** Close the credential asymmetry documented in `watchtower-ack-adapter/docs/FEDERATION_ROUTE_MAP.md` — today `POST /api/v1/projects/{id}/leases` already accepts `fw_agent_*`, but lease *validate*, tool *authorize*, validation *gates*, and *commands* (get + acknowledge) do not.
- **Components:** Extend `authenticateProducer`'s call sites in `index.ts` for these four routes to try `authenticateAgent()` (canonical bearer) first, falling back to HMAC producer-signature — same dual-auth pattern the lease-request route already uses successfully.
- **Rules:** A request authenticated via `fw_agent_*` must still resolve to the SAME `projectId`/`agentId` the route body claims — reuse `lifecycle.ts`'s existing agent-to-project binding check, don't write a second one.
- **Error States:** Bearer token valid but for a different `agentId` than the body claims → `403`, not silently accepted.
- **Fallback:** Producer-signed HMAC continues to work unchanged — this is additive auth, not a breaking migration.

## FEAT-003 — Per-Org / Per-Agent Webhook Destinations

- **Feature ID:** FEAT-003
- **Module Ref:** MOD-003
- **Rollback Tag:** `[FEAT-003-v1]`
- **Feature Flag:** `FEAT_SCOPED_WEBHOOKS`
- **Purpose:** Route `AlertDispatch` deliveries to the actual recipient's own destination instead of one shared global URL.
- **Components:** New `webhook_destinations` table (Part IV, keyed by `scope_type` + `scope_id`); `queue()` consumer in `index.ts` looks up destination by `alert.projectId`'s owning org first, falls back to that specific `agentId`'s own override if set, falls back to `WATCHTOWER_ALERT_WEBHOOK_URL` (global) only if neither exists — preserves today's behavior for anyone who hasn't configured a scoped destination yet.
- **Rules:** Same HMAC-signing scheme as today (`buildAlertDelivery`) applied per-destination-secret, not one shared `WATCHTOWER_ALERT_WEBHOOK_SECRET` — each destination gets its own secret at creation.
- **Error States:** Destination URL unreachable → existing retry/DLQ behavior (`max_retries: 3`, then DLQ), unchanged, just applied per-destination now instead of globally.
- **Fallback:** Global `WATCHTOWER_ALERT_WEBHOOK_URL` remains the last-resort default — nobody's notifications silently stop.

## FEAT-004 — Adapter Canonical Watchtower Client

- **Feature ID:** FEAT-004
- **Module Ref:** MOD-004
- **Rollback Tag:** `[FEAT-004-v1]`
- **Feature Flag:** `FEAT_ADAPTER_CANONICAL`
- **Purpose:** `watchtower-ack-adapter`'s `watchtower.ts` currently only constructs `WatchtowerClient` (legacy HMAC) — verified in `FEDERATION_ROUTE_MAP.md`. Add the canonical path for the routes that already support it.
- **Components:** `contracts.ts`/`config.ts` gain `watchtowerOwnerToken`/`watchtowerAgentToken` (or a bootstrap flow that calls `FederationOwnerClient.createOwner()`/`registerAgent()` once and persists the returned `fw_agent_*` the same way any generated secret is handled — one-time plaintext, then encrypted); `watchtower.ts` gains a second internal client using `FederationAgentClient` for connect/heartbeat/events/disconnect/lease-request, used when canonical credentials are configured, falling back to `WatchtowerClient` otherwise.
- **Rules:** The four MOD-002 routes (until MOD-002 ships) still route through the legacy `WatchtowerClient` even in canonical mode — this is a real, documented hybrid, not a bug (matches `FEDERATION_ROUTE_MAP.md`'s own conclusion).
- **Error States:** Canonical token rejected (revoked/expired) → same fail-closed treatment as any other Watchtower-unavailable case in `failure.ts` — queue/retry, never infer permission from delivery failure.
- **Fallback:** If no canonical token is configured, adapter behaves exactly as it does today (legacy-only) — zero regression.

## FEAT-005 — Character Kit Remote Read/Write Bridge (Memory, Logs, Policy)

- **Feature ID:** FEAT-005
- **Module Ref:** MOD-005
- **Rollback Tag:** `[FEAT-005-v1]`
- **Feature Flag:** `FEAT_CK_REMOTE_BRIDGE`
- **Purpose:** Character Kit already has memory (`DailyNotes` → `<workspace>/memory/daily/*.yaml`), an audit trail (`enforcer-audit.jsonl`), and policy config (`enforcer.yaml` allow/deny, `habits/*.yaml`, `ACK_VALIDATION_INTERVAL_MS`) — verified by reading the real source. None of it is reachable remotely today; only the local CLI (`ack manage`) can see it. This feature adds the daemon RPCs and adapter passthrough to make it reachable, without changing what's authoritative (the local files stay authoritative; this is read/write access, not a second copy).
- **Components:** New daemon wire methods `get_memory` (date range → `DailyNotes.getRange`), `tail_audit` (line-limited tail of `enforcer-audit.jsonl`), `get_policy`/`set_policy` (read/write `enforcer.yaml`'s `allow`/`deny`/`validation_interval_ms` — validated against the same shape the daemon already loads on `reload`), `list_habits`/`create_habit`/`delete_habit` (wrapping the exact logic `ack.js`'s `listHabitsForWorkspace`/`createHabitInteractive` already implement, not reimplementing it). Adapter's `character-kit.ts` gains matching client methods, translating raw daemon responses the same way `gateAction` already does.
- **Rules:** `set_policy`/`create_habit`/`delete_habit` require the daemon's `ACK_AUTH_TOKEN` (already enforced by the daemon for every non-`status` method) — this bridge does not weaken that gate, it's just another authenticated caller. Writes go through the daemon's existing `reload()` path so `characterHash` stays consistent — no direct file writes from the adapter that bypass the daemon's own validation.
- **Error States:** Malformed policy write (fails the daemon's own YAML/shape validation) → daemon returns `{error: "..."}`, adapter surfaces it as a rejected promise, console shows the real validation error — never silently partial-applied.
- **Fallback:** Local `ack manage` CLI keeps working unchanged — this is a second, remote-capable interface onto the same data, not a replacement.

## FEAT-006 — Kill Switch (Cooperative Signal, Not a Forceful Process Kill)

- **Feature ID:** FEAT-006
- **Module Ref:** MOD-006
- **Rollback Tag:** `[FEAT-006-v1]`
- **Feature Flag:** `FEAT_AGENT_CONSOLE`
- **Purpose:** Give an owner a one-click "stop this agent" control in the Agent Control Console — **honestly scoped**. Verified during Phase 0 research: Watchtower's own documented design principle is that it "never proxies, executes, or blocks a tool call itself" (`watchtower_authorize_action`'s own MCP tool description) — it only records allow/deny decisions the calling system is trusted to honor. A genuinely forceful kill (terminating the agent's OS process) can only happen where the agent's process actually runs, which Federation does not control. Building a UI button that implies force when the backend is cooperative would be the exact kind of doc-vs-reality gap this whole project has been catching all session — this feature spec exists specifically to prevent that gap from being built into the product itself.
- **Components:** `POST /api/v1/agents/{id}/kill` issues a `control_commands` row (mode: `cooperative`, existing table/mechanism) that the next `GET .../commands` poll returns, AND — new, via MOD-005 — relays the same signal to the local daemon's fail-closed gate (`character-kit.ts`'s new `signal_stop` RPC → daemon sets a per-session `HOLD_STATE` flag `executeTool` checks first, denying every subsequent call unconditionally until cleared). This is the closest thing to a real kill that respects the existing architecture: the daemon (colocated with the agent) is what can actually stop it, by refusing every tool call, not Watchtower reaching in remotely.
- **Rules:** The UI must NOT describe this as force-killing a process. Copy: "Stops this agent's next action and every action after it, until cleared — the agent must still be running the enforcement daemon for this to take effect" (or equivalent honest phrasing) — a documentation requirement, not just a code one.
- **Error States:** Agent's daemon unreachable (offline, no socket) → the Watchtower-side `control_commands` row still gets written (so it applies retroactively if the agent reconnects — matches existing containment-command semantics), but the console must surface "not confirmed delivered" distinctly from "confirmed stopped."
- **Fallback:** Credential revocation (MOD-001, already exists in `management.ts`) remains the actual hard stop for API access — the kill switch is a faster, gentler cooperative signal layered on top, not a replacement for revocation.

## FEAT-007 — `/steer`

- **Feature ID:** FEAT-007
- **Module Ref:** MOD-006
- **Rollback Tag:** `[FEAT-007-v1]`
- **Feature Flag:** `FEAT_AGENT_CONSOLE`
- **Purpose:** Let an owner inject a mid-run instruction to a live agent — confirmed net-new: zero references to "steer" anywhere in Character Kit, the adapter, or Federation source (grepped all three repos).
- **Components:** `POST /api/v1/agents/{id}/steer {message}` — writes a `control_commands` row of a new kind (`steer`, alongside existing `cooperative` containment commands), delivered the same way containment commands already are (poll + acknowledge). New daemon RPC `inject_prompt` (MOD-005) so the message can reach the agent's actual context via the same mechanism `pickPrompt`/`toolTick` already use for habit-prompt injection — reusing existing daemon-side prompt-delivery machinery instead of inventing a second one.
- **Rules:** Steering messages are logged to the audit trail (`_audit`) exactly like any other daemon decision — an owner steering their own agent is not a silent, unaccountable action.
- **Error States:** Steer command delivered but agent doesn't act on it within one poll cycle → command stays pending, visible in the console, not silently dropped.
- **Fallback:** None — this is genuinely new capability with no existing equivalent to fall back to. Ship behind `FEAT_AGENT_CONSOLE`, default off.

## FEAT-008 — Habit / Interval / Command-Policy Configuration UI

- **Feature ID:** FEAT-008
- **Module Ref:** MOD-006
- **Rollback Tag:** `[FEAT-008-v1]`
- **Feature Flag:** `FEAT_AGENT_CONSOLE`
- **Purpose:** All three config primitives named in the ask already exist as local YAML (habits, `enforcer.yaml` allow/deny, `ACK_VALIDATION_INTERVAL_MS`) — verified by reading the real files. This feature is a UI on top of FEAT-005's new RPCs, not new policy logic.
- **Components:** `control.html` panel: habit list (create/delete, backed by `list_habits`/`create_habit`/`delete_habit`), allow/deny list editor (backed by `get_policy`/`set_policy`), interval field (same). Diffs are shown before submit (current vs. proposed), matching the existing daemon's own "belt-and-suspenders" caution around policy changes.
- **Rules:** Every write requires the operator credential (FEAT-001) or owner's `fw_owner_*`, scoped to only that owner's own agents — never a platform-wide policy editor.
- **Error States:** Same as FEAT-005 (daemon-side validation failure surfaces verbatim, no silent partial apply).
- **Fallback:** Direct YAML file editing via SSH/local access always remains available — this UI is additive.

## FEAT-009 — Task Mapping & Management

- **Feature ID:** FEAT-009
- **Module Ref:** MOD-007
- **Rollback Tag:** `[FEAT-009-v1]`
- **Feature Flag:** `FEAT_TASK_MGMT`
- **Purpose:** Confirmed net-new (grepped for `task`/`taskId` across `source/federation-serverless` — no first-class task concept exists; only incidents, leases, and events). Give an owner a place to define what an agent should be doing, distinct from the enforcement/observability data that already exists.
- **Components:** New `agent_tasks` table (Part IV); `POST/GET/PATCH /api/v1/agents/{id}/tasks`; console panel listing tasks per agent with status (`pending`/`in_progress`/`done`/`blocked`); an agent's own event stream (`run.started`/`run.completed`) can optionally reference a `taskId` via `metadata`, linking observability data to the task without changing the existing approved `EVENT_TYPES` set.
- **Rules:** Tasks are advisory data, not enforcement — completing/failing a task has no effect on lease/gate decisions. Keeps this feature from becoming a second policy engine (matches the adapter's own "the bridge owns no policy" rule, applied here too).
- **Error States:** Task referencing a nonexistent `agentId` → `404` at creation, not a silent orphan row.
- **Fallback:** None needed — purely additive, no existing behavior to preserve.

## FEAT-010 — Live Feed Terminal UI (Per Agent)

- **Feature ID:** FEAT-010
- **Module Ref:** MOD-006
- **Rollback Tag:** `[FEAT-010-v1]`
- **Feature Flag:** `FEAT_AGENT_CONSOLE`
- **Purpose:** Give an owner a real-time, per-agent terminal-style view of what their agent is actually doing — distinct from `watch.drdeeks.xyz`'s existing public TV-diorama widget (`OfficeStage`), which is a visual room representation for observers, not a text feed for the owner. Verified during Phase 0 research: no such per-agent text feed exists anywhere in the current page map (`COMPLETE_SPEC.md` §1) — the closest analogues are the room diorama (visual, not textual, not per-agent) and `operator.html`'s read-only session list (a table snapshot, not a live stream).
- **Components:** `control.html`'s terminal panel subscribes to the existing self-hosted-alert-receiver WebSocket pattern (`wss://fapi.drdeeks.xyz/ws?projectId=...`, `COMPLETE_SPEC.md` §2.8) filtered to one `agentId`; each `OperationalEvent` ingested for that agent (`run.started`, `tool.authorized`/`tool.denied`, `validation.passed`/`failed`, `heartbeat`, etc. — the same fixed `EVENT_TYPES` set every other Watchtower consumer already respects) renders as one terminal line, timestamped, color-coded by severity. No new transport is invented — this reuses the existing WebSocket endpoint with a narrower subscription filter.
- **Rules:** The terminal is read-only. It never becomes an input surface for arbitrary commands to the agent — that boundary belongs to FEAT-007 (`/steer`), which is explicit, logged, and daemon-mediated, not a raw terminal injection point. Keeping these separate is deliberate: a "terminal" that both displays and executes would collapse Watchtower's cooperative-observability boundary (`COMPLETE_SPEC.md` §8's own stated principle) into something it was never designed to be.
- **Error States:** WebSocket disconnect → visible "reconnecting..." state in the console, automatic reconnect with backoff, never a silent gap that looks like agent inactivity.
- **Fallback:** `GET /api/v1/agents/{id}/events` (polling, if such a route doesn't already exist as a filtered view of the existing events table, add it as a fallback) for environments where WebSocket is blocked — degrades to a manual-refresh feed rather than failing outright.

## FEAT-011 — Memory & Log Viewer UI

- **Feature ID:** FEAT-011
- **Module Ref:** MOD-006
- **Rollback Tag:** `[FEAT-011-v1]`
- **Feature Flag:** `FEAT_AGENT_CONSOLE`
- **Purpose:** Surface FEAT-005's new `get_memory`/`tail_audit` RPCs as an actual owner-facing UI, not just an API. Verified during Phase 0 research: Character Kit's `DailyNotes` class (`node/src/memory/index.js`) already writes real per-day YAML memory entries, and `_audit()` already writes a real `enforcer-audit.jsonl` audit trail — both exist today, both are local-file-only, neither has ever been remotely viewable. This is a UI-only feature; FEAT-005 already specifies the RPC/proxy plumbing this depends on.
- **Components:** `control.html` panel with two tabs: Memory (date-range picker, calls `GET /api/v1/agents/{id}/memory?from=&to=`, renders each day's entries with their `tags`/`category` fields — the exact shape `DailyNotes.getRange` already returns, no reshaping needed) and Logs (tail view, calls `GET /api/v1/agents/{id}/logs?lines=`, auto-refreshing, filterable by `tool`/`denied` — matching the fields `_audit()` already writes to every `enforcer-audit.jsonl` line).
- **Rules:** Read-only. Memory and audit-log data are never editable through this UI — they are a record, not a config surface (config is FEAT-008's separate, explicitly-write-capable panel). This distinction matters: an owner should never be able to retroactively edit their own agent's audit trail through a "viewer."
- **Error States:** Daemon unreachable when a memory/log request comes in → the proxy route returns a clear "agent's enforcement daemon is offline, historical data unavailable until it reconnects" — never silently returns empty and lets the owner mistake "no data" for "nothing happened."
- **Fallback:** Local file access (SSH to the workspace, read `memory/daily/*.yaml` or `enforcer-audit.jsonl` directly) always remains available — this UI is a remote convenience on top of files that stay the source of truth, not a replacement for them.

---

> **PROJECT tier requires 3+ feature specifications** — 11 provided above,
> covering all four requested components (Federation, adapter, Character
> Kit, and the new Agent Control Console), including every one of the ten
> "Federation component" items from the request as either its own full
> spec (FEAT-006 kill switch, FEAT-007 `/steer`, FEAT-008 habit/interval/
> command config, FEAT-009 task mapping, FEAT-010 live feed terminal,
> FEAT-011 memory/log viewing) or as the shared backend plumbing those UI
> specs depend on (FEAT-005 covers "local control of agent(s)" and
> "management" at the RPC layer; hackathon alignment is MOD-008/PHASE-6.2,
> a checklist item rather than a feature spec since it's a compliance
> verification task, not a build).

---

---

# PART IV — DATA ARCHITECTURE

> **Rollback Tag:** `[DATA-ARCH-v1]`
> **Rule:** All schema changes require a migration file named
> `YYYYMMDD_NNN_description.sql` with a corresponding rollback file,
> and must be referenced in the Global Change Log (where applicable).
> Naming here follows the existing convention verified in
> `source/federation-serverless/src/migrations/000N_*.sql` — this
> project's migrations continue that sequence starting at `0011`.

## 4.1 Core Database Schemas

### `0011_operator_credentials.sql` (MOD-001 / FEAT-001)

```sql
CREATE TABLE IF NOT EXISTS federation_operator_credentials (
    id TEXT PRIMARY KEY,
    organization_id TEXT NOT NULL,
    credential_hash TEXT NOT NULL UNIQUE,   -- SHA-256 hex, same pattern as federation_owners.credential_hash
    scopes TEXT NOT NULL DEFAULT '["operator:read","operator:write"]',
    issued_at INTEGER NOT NULL,
    revoked_at INTEGER,
    FOREIGN KEY(organization_id) REFERENCES federation_organizations(id)
);
CREATE INDEX IF NOT EXISTS idx_operator_cred_org ON federation_operator_credentials(organization_id);
```

### `0012_webhook_destinations.sql` (MOD-003 / FEAT-003)

```sql
CREATE TABLE IF NOT EXISTS webhook_destinations (
    id TEXT PRIMARY KEY,
    scope_type TEXT NOT NULL CHECK(scope_type IN ('organization', 'agent')),
    scope_id TEXT NOT NULL,                  -- organization_id or agent_id depending on scope_type
    url TEXT NOT NULL,
    format TEXT NOT NULL DEFAULT 'json' CHECK(format IN ('slack', 'discord', 'json')),
    secret TEXT,                              -- per-destination HMAC secret, NULL only for slack/discord (URL is the secret there)
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(scope_type, scope_id)
);
```

### `0013_agent_tasks.sql` (MOD-007 / FEAT-009)

```sql
CREATE TABLE IF NOT EXISTS agent_tasks (
    id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'in_progress', 'done', 'blocked')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(agent_id) REFERENCES federation_agents(id)
);
CREATE INDEX IF NOT EXISTS idx_agent_tasks_agent ON agent_tasks(agent_id, status);
```

### `0014_control_command_kinds.sql` (MOD-006 / FEAT-006, FEAT-007)

```sql
-- control_commands already exists (migration 0002) with mode IN ('cooperative', ...).
-- This migration widens it (same detach/rebuild pattern already proven necessary
-- for CHECK-constraint changes on a table with inbound FKs — see the real D1
-- gotcha documented in fix/rooms-agents-migrations's 0010 migration, reuse that
-- exact technique rather than a naive ALTER).
CREATE TABLE control_commands_new (
    id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'cooperative' CHECK(kind IN ('cooperative', 'kill', 'steer')),
    payload TEXT,                             -- JSON: {message} for steer, empty for kill
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    acknowledged_at INTEGER,
    outcome TEXT CHECK(outcome IN ('contained', 'rejected', 'failed', NULL))
);
-- (detach children, copy, drop, rename, reattach — full sequence in Part VI PHASE-3 deliverable)
```

> **PROJECT tier requires 3+ `CREATE TABLE` schemas** — 4 provided
> (one is a widen-migration on an existing table, included because it's
> new structural surface, not cosmetic).

## 4.2 API Contract Specifications

All new endpoints follow the existing envelope convention verified across
`index.ts`: success responses carry the resource directly (not a wrapped
`{success,data}` envelope — that is NOT this codebase's real convention,
confirmed by reading `index.ts`'s actual response shapes rather than
assuming a generic template), errors carry `{error: string}` with the
appropriate HTTP status.

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/v1/organizations/{id}/operator-credential` | `WATCHTOWER_ADMIN_TOKEN` (issuance is admin-gated; usage isn't) | Issue a new operator credential for an org (FEAT-001). One-time reveal. |
| `PUT` | `/api/v1/organizations/{id}/webhook` | Operator credential (own org) | Set/update this org's webhook destination (FEAT-003). |
| `PUT` | `/api/v1/agents/{id}/webhook` | `fw_owner_*` (owning agent's owner) | Set/update this agent's own webhook override (FEAT-003). |
| `POST` | `/api/v1/agents/{id}/kill` | Operator credential or `fw_owner_*` | Issue a cooperative kill signal (FEAT-006). |
| `POST` | `/api/v1/agents/{id}/steer` | Operator credential or `fw_owner_*` | Issue a steering message (FEAT-007). |
| `GET` | `/api/v1/agents/{id}/memory?from=&to=` | Operator credential or `fw_owner_*` | Proxy to the adapter's `get_memory` RPC (FEAT-005/FEAT-008 UI consumer). |
| `GET` | `/api/v1/agents/{id}/logs?lines=` | Operator credential or `fw_owner_*` | Proxy to the adapter's `tail_audit` RPC. |
| `GET`/`PUT` | `/api/v1/agents/{id}/policy` | Operator credential or `fw_owner_*` | Proxy to `get_policy`/`set_policy` (FEAT-008). |
| `POST`/`GET`/`PATCH` | `/api/v1/agents/{id}/tasks[/{taskId}]` | Operator credential or `fw_owner_*` | Task CRUD (FEAT-009). |

> **PROJECT tier requires 3+ documented endpoints** — 9 provided.

---

---

# PART V — CHANGE CONTROL PROTOCOL

> **Rollback Tag:** `[CHANGE-CONTROL-v1]`
> **This section is permanent and non-negotiable.**
> Every contributor must read this section before making any change.

## Change Log Entry Format

Every entry MUST include all fields below. Entries are permanent.
No entry may be modified or deleted after writing.

```
Date        : YYYY-MM-DD HH:MM UTC
Contributor : [name/handle]
Modules     : [MOD-XXX, ...]
Section Tags: [[TAG-NAME-v1], ...]
Files Changed: [every file changed]
Description : [What changed and why — minimum 3 sentences]
Tests Passing: [test names, or 'none — pre-build']
Phase       : [PHASE-N]
Rollback Ref: [git commit hash or migration rollback filename]
```

## Contributor Rules

1. No work merged without a change log entry in the same PR.
2. No database migration without a rollback migration file.
3. Feature flags required for every Phase 2+ feature.
4. Minimum: 1 unit test per new function, 1 integration test per endpoint.
5. `CHANGELOG.md` CI append-only check must pass on every PR.
6. No contributor may modify or delete an existing change log entry.
7. **Repo-specific:** any change touching `~/projects/federation` also
   requires a dated status line in that repo's own `AGENTS.md` §
   (matching that repo's pre-existing maintenance rule); any change
   touching `watchtower-ack-adapter` requires the same in its `AGENTS.md`
   §8/§10 and `CHANGELOG.md` (matching that repo's own established
   discipline from this session). This blueprint does not relax either
   repo's own rules — it sits on top of them.
8. **FEAT-006 specific:** no UI copy or documentation may describe the
   kill switch as force-terminating a process. Any PR touching FEAT-006
   must be reviewed against this rule explicitly, not just functionally.

---

---

# PART VI — MASTER IMPLEMENTATION CHECKLIST

### PHASE-0: Verified Source Inventory

**Section Tag:** `[PHASE-0-v1]`
**Feature Flag:** `FEAT_PRE_BUILD`
**Assigned Agent:** _unassigned_
**Reviewer Agent:** _unassigned_ — must differ from Assigned Agent (Creative Orchestration Doctrine Principle V)

### Prerequisites

None — this phase IS the prerequisite for all others. Its findings are
already captured in this blueprint (Parts I, III) and in
`watchtower-ack-adapter/docs/FEDERATION_ROUTE_MAP.md`, but the checklist
item below formalizes re-verification immediately before Phase 1 begins,
since these are live, actively-changing repos.

### Deliverables

- [ ] **PHASE-0.1** Type: file — Re-run the source checks this blueprint's Part I/III relied on (grep for `webhook`/`task` in migrations, confirm `character-kit.ts`'s current Phase 2 state, confirm no new commits landed on `fix/rooms-agents-migrations` that change the credential model assumed here) and record any drift as a Part I amendment, not a silent rewrite.
- [ ] **PHASE-0.2** Type: file — Decide and record the `fix/rooms-agents-migrations` push: this blueprint assumes it will be pushed before Phase 1's schema work begins (new migrations 0011+ need to land on top of that branch's 0010, not diverge from it). If it is not pushed, Phase 1 must branch from it directly instead of `main`.
- [ ] **PHASE-0.3** review-phase0.md Type: review

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
### PHASE-1: Identity & RBAC Foundation

**Section Tag:** `[PHASE-1-v1]`
**Feature Flag:** `FEAT_ORG_RBAC`
**Assigned Agent:** _unassigned_
**Reviewer Agent:** _unassigned_ — must differ from Assigned Agent (Creative Orchestration Doctrine Principle V)

### Prerequisites

All Phase 0 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] **PHASE-1.1** `0011_operator_credentials.sql` + rollback file Type: file (MOD-001, Part IV schema)
- [ ] **PHASE-1.2** `src/operator-rbac.ts` (`authenticateOperator`, credential issuance) Type: file (FEAT-001)
- [ ] **PHASE-1.3** `operator.html` updated to accept operator credential Type: file (FEAT-001)
- [ ] **PHASE-1.4** Unit tests: operator credential hash/scope/revocation Type: file
- [ ] **PHASE-1.5** review-phase1.md Type: review

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
### PHASE-2: Canonical Auth Completion

**Section Tag:** `[PHASE-2-v1]`
**Feature Flag:** `FEAT_CANONICAL_ROUTES`
**Assigned Agent:** _unassigned_
**Reviewer Agent:** _unassigned_ — must differ from Assigned Agent (Creative Orchestration Doctrine Principle V)

### Prerequisites

All Phase 1 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] **PHASE-2.1** `index.ts`: dual-auth (`authenticateAgent` fallback to `authenticateProducer`) on the 4 routes Type: file (FEAT-002)
- [ ] **PHASE-2.2** `watchtower-ack-adapter/src/bridge/watchtower.ts`: `FederationOwnerClient`/`FederationAgentClient` wiring Type: file (MOD-004/FEAT-004)
- [ ] **PHASE-2.3** `watchtower-ack-adapter/src/config.ts`/`contracts.ts`: canonical token fields Type: file (FEAT-004)
- [ ] **PHASE-2.4** Integration tests: all 4 routes accept both auth modes Type: file
- [ ] **PHASE-2.5** `watchtower-ack-adapter` `AGENTS.md`/`CHANGELOG.md` updated (repo's own rule) Type: file
- [ ] **PHASE-2.6** review-phase2.md Type: review

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
### PHASE-3: Character Kit Remote Bridge

**Section Tag:** `[PHASE-3-v1]`
**Feature Flag:** `FEAT_CK_REMOTE_BRIDGE`
**Assigned Agent:** _unassigned_
**Reviewer Agent:** _unassigned_ — must differ from Assigned Agent (Creative Orchestration Doctrine Principle V)

### Prerequisites

All Phase 2 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] **PHASE-3.1** `agent_enforcer_daemon.js`: new wire methods `get_memory`/`tail_audit`/`get_policy`/`set_policy`/`list_habits`/`create_habit`/`delete_habit`/`signal_stop`/`inject_prompt` Type: file (FEAT-005, FEAT-006, FEAT-007)
- [ ] **PHASE-3.2** `character-kit.ts`: matching client methods + raw-response translation Type: file (FEAT-005)
- [ ] **PHASE-3.3** `0014_control_command_kinds.sql` + rollback (detach/rebuild pattern) Type: file (FEAT-006/007, Part IV)
- [ ] **PHASE-3.4** `0013_agent_tasks.sql` + rollback Type: file (FEAT-009, Part IV)
- [ ] **PHASE-3.5** New daemon-protocol tests (extend `tests/character-kit.test.ts`'s fake-daemon pattern with the new methods) Type: file
- [ ] **PHASE-3.6** review-phase3.md Type: review

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
### PHASE-4: Agent Control Console + Webhooks + Tasks

**Section Tag:** `[PHASE-4-v1]`
**Feature Flag:** `FEAT_AGENT_CONSOLE`
**Assigned Agent:** _unassigned_
**Reviewer Agent:** _unassigned_ — must differ from Assigned Agent (Creative Orchestration Doctrine Principle V)

### Prerequisites

All Phase 3 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] **PHASE-4.1** `0012_webhook_destinations.sql` + rollback Type: file (FEAT-003, Part IV)
- [ ] **PHASE-4.2** `queue()` consumer: scoped destination lookup with global fallback Type: file (FEAT-003)
- [ ] **PHASE-4.3** `control.html` (live feed terminal via existing WebSocket endpoint, kill switch with FEAT-006-mandated honest copy, `/steer` input, memory viewer, log viewer, habit/policy editor, task list) Type: file (FEAT-005 through FEAT-009 UI)
- [ ] **PHASE-4.4** New API routes from Part IV §4.2 wired in `index.ts` Type: file
- [ ] **PHASE-4.5** `agents-skill.md` doc-drift fix (remove documented-but-nonexistent `POST`/`PATCH` routes or implement them — decide explicitly, don't leave ambiguous) Type: file (MOD-008)
- [ ] **PHASE-4.6** `federation/AGENTS.md` stale adapter reference fixed (correct path + Phase 2 status) Type: file (MOD-008)
- [ ] **PHASE-4.7** review-phase4.md Type: review

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
### PHASE-5: Testing & Hardening

**Section Tag:** `[PHASE-5-v1]`
**Feature Flag:** `FEAT_TESTING_HARDENING`
**Assigned Agent:** _unassigned_
**Reviewer Agent:** _unassigned_ — must differ from Assigned Agent (Creative Orchestration Doctrine Principle V)

### Prerequisites

All Phase 4 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] **PHASE-5.1** Integration test against a REAL running `agent_enforcer_daemon.js` process (not the fake — closes the gap `watchtower-ack-adapter/AGENTS.md` §10 already flags) Type: external-check
- [ ] **PHASE-5.2** Live delivery test against a real (staging) Watchtower instance Type: external-check
- [ ] **PHASE-5.3** Security review of FEAT-006/FEAT-007 specifically (kill/steer are the highest-blast-radius new capabilities) Type: review
- [ ] **PHASE-5.4** RBAC boundary tests: operator credential cannot read/write another org's agents Type: file
- [ ] **PHASE-5.5** review-phase5.md Type: review

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
### PHASE-6: Launch & Hackathon Alignment

**Section Tag:** `[PHASE-6-v1]`
**Feature Flag:** `FEAT_LAUNCH_LIVE_OPS`
**Assigned Agent:** _unassigned_
**Reviewer Agent:** _unassigned_ — must differ from Assigned Agent (Creative Orchestration Doctrine Principle V)

### Prerequisites

All Phase 5 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] **PHASE-6.1** Push `fix/rooms-agents-migrations` (if not already done in Phase 0) and this project's branch, per explicit go-ahead (standing rule: push needs separate consent from commit) Type: approval
- [ ] **PHASE-6.2** Cross-check this blueprint's shipped scope against `AGENTS.md`'s "Submission truth" section — identity fields, category, repo URL, `/feedback` session ID, video, final submission action — confirm what's actually still needed for OpenAI Build Week, don't assume this blueprint's work alone completes it Type: review (MOD-008)
- [ ] **PHASE-6.3** Deploy Agent Control Console behind `FEAT_AGENT_CONSOLE`, default off, staged rollout Type: external-check
- [ ] **PHASE-6.4** review-phase6.md Type: review

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---

---

---

# PART VII — QUALITY & COMPLIANCE STANDARDS

> **Rollback Tag:** `[QUALITY-v1]`

## Error Handling Standards

1. Graceful degradation for all non-critical services — a webhook delivery failure never blocks the underlying incident/event from being recorded.
2. User-facing messages: friendly, non-technical, no stack traces exposed. **Exception, deliberately:** FEAT-006's kill-switch copy must be precise and technical about what it does NOT do (cooperative, not forceful) — clarity there outranks friendliness.
3. Internal logging: full context — requestId, agentId, error code, stack. Every new daemon RPC (MOD-005) writes through the existing `_audit()` path, not a parallel log.
4. Retry: exponential backoff on external calls (3 retries: 1s, 2s, 4s) — matches the existing webhook queue's own `min(60, 2^attempts)` pattern; new code should reuse that function, not reimplement it.
5. Circuit breaker: 10 failures in 60s opens circuit for 5 minutes, for the new `/memory`/`/logs`/`/policy` proxy routes specifically (they're the ones making a live socket call to a potentially-offline daemon on every request).

## Testing Requirements

- Unit tests: 80% line coverage on all new modules (MOD-001 through MOD-007).
- Integration tests: every new API endpoint has success + error case, including auth-boundary cases (wrong org, revoked credential, expired token).
- E2E tests: kill switch, `/steer`, and policy-write flows each have a passing automated test that exercises the full path — console → Federation API → adapter → real daemon (Phase 5), not mocked at every layer.
- Character Kit protocol tests: every new daemon RPC gets a `tests/character-kit.test.ts`-style fake-daemon test before Phase 3 is considered complete (matches this session's own established pattern).

## Performance Budgets

| Metric | Budget |
|---|---|
| Agent Control Console page load LCP (3G) | < 2.0 seconds |
| API response time p95 (existing routes, unaffected) | < 500ms |
| `/memory`, `/logs`, `/policy` proxy routes p95 (live socket round-trip to daemon) | < 2000ms — higher budget, honestly, because these hit a live local process, not a cache |
| Live feed terminal WebSocket event latency | < 1000ms from daemon event to console render |
| Kill switch: command visible in console → written to `control_commands` | < 500ms |
| Kill switch: `control_commands` row → next daemon poll picks it up | < 30s (bounded by existing poll interval, not a new SLA invented here) |
| Background job (webhook delivery) completion | < 60 seconds |

> **PROJECT tier requires 6+ concrete metrics with units** — 7 provided.

---

---

# CHANGE LOG

> This section is append-only. No entry may be modified or deleted.

## CL-0000 — Document Initialization

```
Date        : 2026-08-14
Contributor : [author]
Modules     : [MOD-001]
Section Tags: [[PHASE-0-v1]]
Files Changed: [blueprint.md, checklist.md]
Description : Initial blueprint created via enterprise-blueprint skill.
              Project: Federation Ecosystem Hardening. Scope: PROJECT. All sections
              pre-populated with required structure awaiting content population.
Tests Passing: none — pre-build
Phase       : PHASE-0
Rollback Ref: N/A — initial document creation
```

## CL-0001 — Full Content Population from Verified Source Research

```
Date        : 2026-08-14 01:20 UTC
Contributor : Claude (session continuing from watchtower-ack-adapter Phase 2/route-map work)
Modules     : [MOD-001, MOD-002, MOD-003, MOD-004, MOD-005, MOD-006, MOD-007, MOD-008]
Section Tags: [[SYS-OVERVIEW-v1], [MODULE-REGISTRY-v1], [SPECS-v1], [DATA-ARCH-v1], [QUALITY-v1]]
Files Changed: [blueprint.md]
Description : Populated all seven parts with content grounded in this session's
              verified findings (FEDERATION_ROUTE_MAP.md's canonical-vs-legacy
              route audit, direct source reads of agent_enforcer_daemon.js,
              node/bin/ack.js, node/src/memory/index.js, and
              source/federation-serverless's migrations/index.ts/AGENTS.md) plus
              targeted Phase-0-style research done specifically for this
              blueprint: confirmed Character Kit already has memory, audit
              logging, and habit/policy config (all local-only, no remote
              surface); confirmed no existing "/steer" or "task" concept
              anywhere across all three repos; confirmed Watchtower's
              cooperative-only design principle, which directly shaped
              FEAT-006's honesty constraint on the kill switch. 9 feature
              specs, 4 new D1 schemas (plus one widen-migration), 9 new API
              endpoints, 7 phases with real deliverables mapped to specific
              files across all three repos.
Tests Passing: none — pre-build (this is planning, not implementation)
Phase       : PHASE-0
Rollback Ref: N/A — documentation-only change, no code touched
```
