# OpenAI Build Week — Federation Watchtower Readiness Review

_Reviewed against the live Devpost OpenAI Build Week configuration on 2026-07-17._

## Submission positioning

- **Project:** Federation Watchtower
- **Recommended category:** Developer Tools
- **Audience:** developers and teams operating autonomous coding, testing,
  DevOps, and guarded automation workflows
- **Core problem:** autonomous work can keep creating scaffolds, duplicate a
  chain, fail silently, or spend credits while nobody has a coherent view of
  what is active or what should stop. The project’s origin was an actual build
  that consumed roughly 25,000 credits across repeated autonomous scaffolding
  before a clear stop signal existed.
- **Core claim:** Watchtower preserves operational evidence and presents it as
  a human-readable security-camera sitcom. The presentation never fabricates an
  agent, event, owner, outcome, or safeguard result.

## Required Devpost deliverables

| Requirement | Evidence/status |
| --- | --- |
| Working project made with Codex and GPT-5.6 | Working Worker, public Watchtower, local demonstration, and integration code exist. The submitter must accurately state how GPT-5.6 was used; no documentation should invent model use. |
| One category | Select **Developer Tools**. |
| Project description | Draft exists in `docs/review/OPENAI_SUBMISSION_NOTES.md`; revise it against the actual deployed/lifecycle state before publishing. |
| Public YouTube demo under three minutes | Required. The voiceover must explain what was built and how both Codex and GPT-5.6 were used. Use `OPENAI_SUBMISSION_VIDEO_SCRIPT.md` only after a real lifecycle demonstration has been prepared. |
| Source repository URL | Required. A private repository must be shared with `testing@devpost.com` and `build-week-event@openai.com`; otherwise use the public repository URL and license. |
| README | Required. Root `README.md` supplies live observation, local demo, Worker setup, security boundaries, and test commands. |
| `/feedback` Codex session ID | Required in the submission form for the session that contains most of the core implementation work. Obtain it from Codex; do not invent one. |
| Dev tool testing path | Required when relevant. Judges can use the live Watchtower and API discovery endpoint, or run the in-memory local demo. Protected control-plane behavior requires locally supplied secrets and must not be demoed with production credentials. |

The standalone `Federation Watchtower` Devpost project is currently published
but not attached to the OpenAI Build Week challenge. Attaching/submitting it is
a separate user-authorized Devpost action.

## Judging alignment

| Criterion | What the submission must demonstrate |
| --- | --- |
| Technological implementation | A genuine, non-trivial control loop: signed event → persistence/guardrail decision → visibility → real stop recommendation or control denial. Show Codex’s concrete contribution and explain GPT-5.6 usage accurately. |
| Design | Public Watchtower room, roster, agent detail, and terminal form a coherent read-only experience; reserve privileged controls for the appropriate host. Do not show fake event data as product evidence. |
| Potential impact | Connect the 25,000-credit failure story to developers who need to catch loops, duplicates, silent failure, missed heartbeats, and spend before a run becomes wasteful. |
| Quality of idea | Lead with the unusual but functional idea: a security-camera sitcom is the attention layer for a serious, evidence-preserving agent control plane. |

## Webhook and liveness proof to include

The product is not a “keep a tab open” monitor. The submission should show this
runtime-neutral lifecycle:

```text
agent package / CI runner / scheduler
  -> signed heartbeat or operational webhook
  -> durable presence + immutable event record
  -> visible public projection (if opted in)
  -> no heartbeat before declared deadline
  -> offline transition + watchdog evidence
  -> outbound incident webhook / notification delivery
  -> later heartbeat reconnects the same agent identity
```

Current implementation evidence:

- `POST /api/v1/events` accepts signed, idempotent operational events;
  `heartbeat` arms an `AgentWatchdog` Durable Object alarm.
- The watchdog marks the legacy agent record offline and emits a
  `heartbeat.missed` event if the deadline elapses.
- Guardrail alerts are recorded before being queued. `WATCHTOWER_ALERT_WEBHOOK_URL`
  enables an HTTPS destination; `WATCHTOWER_ALERT_WEBHOOK_SECRET` optionally
  HMAC-signs the delivery.
- Queue retry/DLQ behavior and delivery status preserve the fact that a
  notification was delivered, failed, retried, or safely suppressed.

Necessary next lifecycle work before claiming public self-service webhook
support:

- issue per-agent scoped credentials instead of relying on the shared ingestion
  secret;
- make an owner-selected liveness profile explicit (30-minute default, bounded
  30–60 minute asynchronous grace where appropriate);
- make webhook destinations organization/owner-scoped, encrypted/secret-backed,
  and independently verifiable;
- document the package call for `connect`, `heartbeat`, `emit`, `disconnect`,
  and reconnect with idempotency keys;
- expose an auditable public projection that never leaks an owner’s private
  webhook configuration.

## Submission-form fields to prepare

The OpenAI Build Week form requires answers for:

1. Submitter type: Individual, Team of Individuals, or Organization.
2. Country of residence.
3. Category: Developer Tools.
4. Public/private code repository URL.
5. `/feedback` Codex session ID.

It also provides optional fields for judge-access instructions and developer
tool/plugin installation/testing instructions. Fill those with the live URL,
the local demo command, platform support (Cloudflare Worker plus Node.js 20+
local demo), and any credentials only through Devpost’s private judge field.
Never place production secrets in the README, video, repository, or public
Devpost description.

## Final pre-submit gate

- [ ] Repository is accessible and its README commands are tested.
- [ ] The demo is real, public, under three minutes, and includes working
  Watchtower evidence rather than a mock.
- [ ] Voiceover accurately describes Codex and GPT-5.6 use.
- [ ] `/feedback` session ID has been retrieved.
- [ ] The published Devpost project is attached to OpenAI Build Week and all
  required form fields are complete.
- [ ] All product claims distinguish current behavior from the planned
  owner/agent lifecycle.
