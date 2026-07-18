# Federation Watchtower Enforcement Implementation Plan

## Decision

Federation Watchtower becomes an **event-sourced agent operations control plane**.
It must not only render a failure after the fact. A signed operational event is
validated, evaluated against a versioned policy, recorded in an auditable chain,
turned into an incident when necessary, and then either alerts an owner or
blocks the next controlled action.

The product has three honest operating modes:

| Mode | What Watchtower can do | When to use it |
| --- | --- | --- |
| Observe | Record, deduplicate, correlate, show status, and alert. | Existing systems that cannot yet integrate a control client. |
| Cooperative containment | Issue a pause/quarantine command which the Watchtower SDK or agent runner must acknowledge before its next step. | Existing agents that can add a small client or wrapper. |
| Enforced containment | Deny a tool call or work lease at the gateway before work begins. | New or high-risk agents whose tools run through the Watchtower gateway. |

An HTTP event alone cannot terminate an arbitrary remote process. For a
non-cooperating process, the safe truthful result is an incident plus a
notification/webhook to its owning system. "Enforced" is reserved for work
leases and tool calls that Watchtower actually controls.

## Audit Baseline (before Release 1)

The deployed Worker has a useful base: projects, agents, heartbeat timestamps,
Durable Object registries, D1 feed history, public Watchtower assets, and
federation/MCP tables. The local demo also defines a small statement-packet
contract.

It is not yet an enforcement system:

- The production Worker has no statement/telemetry ingestion route. The local
  demo's `POST /api/federation/statement` is not implemented in the Worker.
- `feed_events` is a display feed, not an immutable event ledger. It has no
  event ID supplied by the producer, idempotency key, schema version,
  correlation/run ID, actor identity, payload digest, or hash chain.
- Heartbeats update a timestamp but are never evaluated for lateness. There is
  no alarm, scheduled reconciliation, incident, or owner notification.
- There are no policies for loop depth, repeated attempts, fan-out, budget,
  rate, timeout, validation failure, or restricted tools.
- There is no incident state machine, acknowledgement, escalation, resolution,
  containment command, or evidence trail of a control action.
- API mutations, federation review, project registration, and MCP-org
  administration are public. CORS is permissive; the MCP-org tables are not
  connected to request authentication, scope checks, rate limits, or audit
  writes.
- The WebSocket implementation polls from an interval in the request handler;
  it is a snapshot convenience rather than durable pub/sub.
- No queue, DLQ, scheduled handler, notification destination, test suite, or
  custom operational metric exists.

These gaps are also visible in the current source:

- `source/federation-serverless/src/index.ts` exposes the open mutation routes
  and has no packet ingestion or authorization middleware.
- `source/federation-serverless/src/agent-registry.ts` stores heartbeats and
  feed rows only.
- `source/federation-serverless/src/schema.sql` contains no policy, incident,
  command, notification, or immutable audit-event tables.
- `docs/review/SUPER_STATEMENT_PACKET_SPEC.md` defines the intended event seam,
  while `source/federation-tv-package/federation-core/demo-gateway.js` is the
only implementation of it.

### Release 1 implementation and production status — 2026-07-17

The first safe control-loop slice is implemented and deployed. Production D1
has the additive enforcement migration, and the Worker has the required
ingestion and administrative secrets:

- `POST /api/v1/events` accepts a bounded, HMAC-signed, replay-limited,
  idempotent operational event and redacts sensitive metadata before storage.
- A per-project `ProjectGuardrail` Durable Object applies deterministic depth,
  repeated-validation-failure, budget, and duplicate-chain policies; it creates
  advisory incidents, control-command records, public feed projections, and a
  per-project audit hash chain.
- Administrative and legacy mutation routes require a production admin secret;
  the Worker has structured observability enabled.
- The additive D1 migration, generated Worker binding types, standalone policy
  tests, and deployment documentation are included.

Notifications, owner acknowledgement, watchdog alarms, cooperative leases,
per-agent credentials, queues/DLQs, and actual tool-call denial remained
Release 2/3 work at that point.

## Product Capabilities to Build

### 1. A canonical signed operational event

Replace the display-only "statement" with a versioned `OperationalEvent`.
Every producer supplies a stable `eventId`, `occurredAt`, `projectId`,
`agentId`, `runId`, `eventType`, `severity`, a short human statement, and
bounded metadata. `idempotencyKey` makes retries safe. `parentRunId` and
`chainDepth` make nested/duplicate loops detectable.

```json
{
  "schemaVersion": "2026-07-17",
  "eventId": "evt_01J...",
  "idempotencyKey": "run_7:attempt_4:validation_failed",
  "projectId": "watchtower",
  "agentId": "build-goblin-01",
  "runId": "run_7",
  "parentRunId": "run_4",
  "eventType": "validation.failed",
  "severity": "error",
  "occurredAt": "2026-07-17T16:00:00Z",
  "statement": "The gate said no in YAML.",
  "metadata": { "attempt": 4, "chainDepth": 7, "gate": "deploy" }
}
```

Initial approved event families:

- Lifecycle: `run.started`, `run.completed`, `run.failed`, `heartbeat`.
- Guardrails: `validation.passed`, `validation.failed`, `policy.blocked`,
  `tool.denied`, `lease.denied`.
- Runaway signals: `loop.depth_exceeded`, `loop.duplicate_detected`,
  `attempt.threshold_exceeded`, `fanout.threshold_exceeded`,
  `heartbeat.missed`, `duration.threshold_exceeded`.
- Resources: `budget.warning`, `budget.exceeded`, `rate.threshold_exceeded`.
- Control and recovery: `incident.opened`, `incident.acknowledged`,
  `containment.requested`, `containment.acknowledged`, `incident.resolved`.

The Worker accepts bounded JSON only, rejects unknown types, clamps strings and
metadata depth/size, removes known secret fields, verifies the request signature
over the raw body plus timestamp, and rejects stale/replayed timestamps. Each
agent receives only the project and capability scopes assigned to it.

### 2. Policies, not hard-coded opinions

Policies are versioned per project, with an optional agent override. They use
deterministic conditions and explicit actions; model output never changes a
policy or grants itself an exception.

```json
{
  "policyId": "default-build-v1",
  "rules": [
    { "signal": "chainDepth", "operator": ">", "value": 5,
      "action": "pause", "severity": "critical" },
    { "signal": "failedAttempts", "windowSeconds": 900, "operator": ">=", "value": 3,
      "action": "require_approval", "severity": "high" },
    { "signal": "budgetUsd", "operator": ">=", "value": 10,
      "action": "quarantine", "severity": "critical" },
    { "signal": "heartbeatAgeSeconds", "operator": ">", "value": 120,
      "action": "alert", "severity": "high" }
  ]
}
```

Supported actions are `observe`, `alert`, `require_approval`, `pause`,
`quarantine`, and `deny`. The action is constrained by the integration mode:
observe-only agents never claim to have been paused; they receive an advisory
incident and a configured owner webhook.

### 3. Incident and evidence lifecycle

One or more related signals open a de-duplicated incident. Incidents move only
through `open -> acknowledged -> contained -> resolved` (or `dismissed` with a
reason). Every policy decision and control command is linked to the original
events, rule version, actor, time, and result.

`audit_events` is append-only. A per-project coordinator serializes its hash
chain: `hash(previous_hash + canonical_event_digest + decision_digest)`. Large
raw evidence belongs in R2; D1 stores the object key and digest. This keeps the
TV feed friendly while preserving a reliable private record.

### 4. Work leases and the Loop Enforcer adapter

The existing Loop Enforcer and Guardrail Enforcement tools already model the
important local controls: ordered steps, pre/loop/post validation, a signed
audit log, locks, and retry states. They must become **producers**, not a
separate source of truth.

Add a tiny SDK/CLI adapter that:

1. requests `POST /api/v1/projects/{projectId}/leases` before a run or a
   consequential tool call;
2. wraps the local gate's pre-check, loop, and post-check with `run.*` and
   `validation.*` events;
3. reports `parentRunId`, step number, retry/attempt, and local audit-log
   digest;
4. checks the lease before each next step; a pause/quarantine/expired lease
   stops the cooperative runner; and
5. acknowledges a control command so Watchtower reports confirmed containment,
   not merely a request.

This provides the bridge for existing systems: wrap their current runner first,
then move high-risk tools behind the lease/tool gateway when they are ready.

### 5. Alerting and escalation

Notification delivery is asynchronous and idempotent. Each project has owners
and destinations (initially generic signed webhooks; Slack/Teams/email adapters
can follow). Critical incidents notify immediately; lower severity incidents
batch/dedupe. Escalation happens when an incident remains unacknowledged or a
cooperative containment command is not acknowledged before its deadline.

The notifier always includes the incident ID, severity, implicated agent/run,
policy decision, public-safe statement, and a signed Watchtower detail URL. It
never includes raw prompts, tokens, or secrets.

### 6. Authentic MCP and administrative access

Public Watchtower read routes stay public and static. Every mutation and every
private operational route requires a principal and scope. The first deployment
uses:

- signed producer credentials for ingestion;
- an `ADMIN` Worker secret for break-glass/admin operations, compared with Web
  Crypto timing-safe semantics; and
- Cloudflare Access in front of the admin/MCP hostname, using service tokens
  for machine clients.

MCP organisations become real principals: issue/rotate/revoke credentials,
enforce their stored scopes and project allow-list, record every call in
`mcp_access_logs`, and rate-limit per principal. Do not expose the existing
MCP-org registration/review/log routes publicly.

## Cloudflare Architecture

```text
Agent / Loop Enforcer adapter
  -> signed POST /events
  -> Worker: authenticate + validate + idempotency
  -> Project Guardrail Durable Object: evaluate policy, append audit decision,
       schedule lease/heartbeat deadlines
  -> D1: events, policies, incidents, commands, durable query model
  -> Queue: notifications and external containment webhooks
       -> retry + dead-letter queue
  -> R2: large/redacted evidence and immutable audit exports
  -> public feed / widget / read-only MCP
```

- Use one **Project Guardrail Durable Object per project** for the coordination
  atom: counters, budgets, idempotency decisions, policy version, and audit
  hash-chain head. Avoid a single global enforcement DO.
- Use one **Agent Watchdog Durable Object per agent** only where dynamic
  heartbeat deadlines are needed. Its one alarm is rescheduled on heartbeat;
  on expiry it raises `heartbeat.missed`. Durable Object alarms do not repeat,
  so the implementation must reschedule only when a real deadline remains.
- Add a scheduled Worker reconciliation job for missed external telemetry,
  stuck notification commands, retention/export, and reports. It is the safety
  net, not the low-latency enforcement path.
- Use a Queue for notification and external controller work. Consumers must be
  idempotent and configured with retries plus a dead-letter queue, so a broken
  destination is visible rather than silently discarded.
- Enable Workers observability and structured JSON logs; add Analytics Engine
  dimensions for project, agent, event family, policy result, incident
  severity, and containment outcome. Do not place prompts, event payloads, or
  credentials in logs.

## Data Model Additions

Add an additive `src/migrations/0001_watchtower_enforcement.sql`, never edit a
deployed schema by assumption:

- `operational_events`: producer event ID/idempotency key, actor, run and
  correlation IDs, normalized event, redacted metadata, payload digest,
  received timestamp; unique `(project_id, idempotency_key)`.
- `guardrail_policies` and `policy_rules`: immutable versions and effective
  state per project/agent.
- `incidents`, `incident_events`, and `incident_transitions`: lifecycle and
  evidence joins.
- `control_commands` and `work_leases`: requested action, expiry, result,
  acknowledgment, and requester/agent identity.
- `audit_events`: append-only event/decision hashes and R2 evidence references.
- `notification_destinations` and `notification_deliveries`: destination
  reference, de-duplication key, delivery status, and retry history. Credentials
  remain Worker secrets or a Secrets Store reference, never D1 plaintext.
- `agent_credentials` and `mcp_credentials`: public key IDs, one-way verifier,
  scopes, lifecycle, last-use; never a stored raw token.

The existing `feed_events` stays as a projection of public-safe events. It is
not the source of truth.

## Delivery Order

### Release 1 — make the signal real and safe

1. Add request validation, bounded body handling, structured errors, and
   authentication middleware. **Implemented in source.**
2. Implement `POST /api/v1/events` and the formal event schema. **Implemented
   in source; the local demo adapter remains a legacy demo.**
3. Add operational events, policies, incidents, and audit tables plus migration
   runner documentation. **Implemented in source; migration not yet applied.**
4. Add `ProjectGuardrail` policy evaluation for loop depth, repeated failures,
   budget thresholds, and duplicate chain starts. **Implemented in source.**
5. Project public-safe decisions into the existing feed/widget and add incident
   read endpoints. **Implemented in source.**
6. Add tests for validation and core runaway rules. **Implemented; HMAC and D1
   integration coverage expands with the Release 2 harness.**

Success criterion: a signed `validation.failed` event for attempt 3 opens one
incident, shows a safe bubble, writes an auditable decision, and returns the
same result on retry without duplicating the incident.

### Release 2 — close the cooperative loop

1. Add leases, control commands, and an adapter for the Loop Enforcer/Gate.
   **Implemented in source:** the standard-library adapter acquires and checks
   leases, polls commands, emits heartbeats, and writes containment receipts.
2. Add an agent watchdog alarm and scheduled reconciliation. **Implemented in
   source:** one Agent Watchdog Durable Object per agent reschedules its alarm
   on a signed heartbeat and emits a deduplicated missed-heartbeat event.
   Scheduled reconciliation remains future safety-net work.
3. Add the notification Queue, DLQ, generic signed-webhook delivery, and
   acknowledgement/escalation rules. **Implemented in source:** an incident
   creates a durable notification record, Queue delivery retries via the DLQ,
   and HTTPS webhook delivery is HMAC-signable. Outbound delivery is safely
   suppressed until an owner configures `WATCHTOWER_ALERT_WEBHOOK_URL`.
4. Add owner and policy administration behind Access/admin scopes. Existing
   admin protection remains in place; owner/project policy administration is
   deferred until principal and scope design in Release 3.

Success criterion: a nested-chain event exceeding the policy receives a
quarantine command; the adapter sees the revoked lease before the next step,
stops, acknowledges the command, and the incident becomes `contained`.

### Release 3 — enforce controlled tools and federation access

1. Put high-risk tool calls behind the lease/policy gateway and implement
   allow/deny decisions before execution.
2. Turn MCP organisations into scoped, rate-limited principals with audit logs.
3. Add R2 evidence export/retention, dashboard incident actions, and policy
   simulation (evaluate a policy against historical events without acting).
4. Add load, replay, security, and failure-mode tests; document an emergency
   break-glass runbook.

Success criterion: a denied tool action is prevented before it reaches its
external side effect, and every caller can reconstruct why from its incident
and audit chain.

## Decisions Needed Before External Delivery Is Enabled

The core event/policy/incident work can begin without these choices. Before
notifications or real containment are enabled, decide:

1. The first owner destination: a generic HTTPS webhook is the lowest-friction
   baseline; Slack, Teams, and email each need separate credentials/config.
2. Default action for a critical policy: alert-only, cooperative pause, or
   enforced deny. Start existing systems in alert-only until their adapter is
   confirmed.
3. The first high-risk tools that must pass through the enforcement gateway.
   Without this list, "kill" remains an advisory webhook rather than reliable
   prevention.
4. Budget units and source: USD, provider tokens, tool-call count, execution
   time, or a combination.

## Research Basis

Cloudflare's current guidance supports this design: Durable Object alarms are
appropriate for per-entity deadlines but do not repeat automatically; Queues
provide batching/retries and should use a DLQ; Cron Triggers run a scheduled
handler for reconciliation; and Analytics Engine supports non-blocking,
high-cardinality custom metrics. Workers Logs supports structured JSON logs and
Cloudflare Access service tokens protect machine-to-machine routes. OWASP's
2026 agentic guidance identifies tool misuse/excessive agency, identity and
privilege abuse, memory/context poisoning, and insufficient human oversight as
first-class agent risks. Watchtower's signed events, least-privilege scopes,
deterministic policies, audit trail, owner acknowledgement, and pre-tool gate
are direct controls for those risks.

Sources: [Cloudflare Durable Object alarms](https://developers.cloudflare.com/durable-objects/api/alarms/), [Durable Object rules](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/), [Cloudflare Queues](https://developers.cloudflare.com/queues/), [Queue DLQs](https://developers.cloudflare.com/queues/configuration/dead-letter-queues/), [Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/), [Workers observability](https://developers.cloudflare.com/workers/observability/), [Workers Analytics Engine](https://developers.cloudflare.com/analytics/analytics-engine/), [Cloudflare Access service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/), and [OWASP Top 10 for Agentic Applications 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/).
