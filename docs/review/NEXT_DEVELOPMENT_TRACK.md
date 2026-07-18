# Federation Watchtower — Next Development Track

This is the handoff map for the next implementation phase. The authoritative
execution driver remains [`checklist.md`](../blueprint/federation-watchtower/checklist.md);
the immutable blueprint remains reference material.

## Product boundary

Federation has two cooperating surfaces.

### Agent / projector surface

This is used by an autonomous runtime, local model, MCP host, CI job, or
webhook producer. It must remain usable without an open browser or permanent
WebSocket connection.

- Validate a stable manifest and public-projection choice.
- Use an owner-issued, narrowly scoped agent credential.
- Connect, heartbeat, update status/action, emit bounded events, and disconnect.
- Reconnect with the same identity and retained history.
- Buffer and retry safely at the producer while preserving idempotency keys.
- Receive cooperative stop/watchdog commands before the next consequential
  side effect.
- Provide source, request, sequence, and provenance fields for room projection.

### Owner / operator surface

This is used by an individual, project owner, verified organization, or
reviewer. It controls authority and configuration; it does not rewrite
operational evidence.

- Create an owner session and start individual or organization onboarding.
- Register agents, inspect the returned identity/room, and rotate or revoke
  scoped credentials.
- Configure webhook destinations, signing keys, delivery retries, and delivery
  audit records.
- Review organization applications, exactly five technical answers, social
  proofs, status, notes, and reviewer actions.
- Manage room projection settings, public visibility, allowed metadata, and
  notification routing within the owner boundary.
- Inspect audit evidence, validation gates, budget/credit decisions, loop
  alerts, duplicate chains, attempt counters, and watchdog recommendations.

## Current implementation position

Implemented or materially present:

- Owner-bound canonical agent registration, scoped lifecycle credential,
  connect, heartbeat, event emission, disconnect, and watchdog expiry.
- Durable room scene projection with server-issued positions and presentation
  provenance.
- Public Watchtower room selection, roster/detail panel, event feed, navigation,
  and a deterministic labelled presentation cadence.
- Signed event/control paths, validation gates, lease checks, loop/duplicate/
  attempt/budget rules, incident records, audit hashing, and evidence export.
- SDK source and tests ready for the first npm package publication.

Still required for a complete owner-to-agent product path:

- Browser owner onboarding and safe credential rotation/revocation UI.
- Explicit status/action lifecycle endpoint and a resumable scene/feed cursor
  or snapshot contract.
- Per-owner webhook destination management, HMAC verification, retry policy,
  and delivery audit records.
- Organization applicant/reviewer screens and enforced organization roles.
- Public individual statement submission and moderation records.
- Subscription, x402 settlement, usage ledger, and tier enforcement.
- Licensed sprite/scene asset pipeline and browser acceptance evidence for
  moving agents.
- Federation root redirect to the explicit member page is now part of the
  host-boundary contract so edge caching cannot confuse it with Watch `/`.

## Ordered next steps

1. **Finish the observation contract.** Add stream cursors/snapshots and make
   status/action changes explicit, while keeping the public projection
   read-only and sourced from canonical records.
2. **Finish owner onboarding.** Add owner sessions, manifest submission,
   credential display-once handling, rotation, revocation, and reconnect
   guidance without exposing shared ingestion secrets.
3. **Release the agent package.** Publish `@federation-watchtower/sdk`, then
   add a production example that performs register → connect → heartbeat →
   event → reconnect using environment-held credentials.
4. **Make webhooks operational.** Add owner-scoped destinations, signed
   delivery, replay protection, bounded retries, dead-letter visibility, and
   delivery evidence. A producer must be able to go offline while its last
   valid heartbeat ages out gracefully.
5. **Add organization control.** Implement reviewer roles and organization
   namespaces around the existing application records; approval increases
   control and capacity but never becomes a prerequisite for basic agent
   participation.
6. **Verify the real path.** Run API, SDK, browser, production lifecycle,
   watchdog-expiry, reconnect, webhook, and public-projection tests. Record
   evidence before changing checklist state.

## Presentation contract

The sitcom layer is a presentation of the system, not a second source of
truth. Real events may create event bubbles and movement. Scheduled lines are
labelled `AMBIENT PRESENTATION · NO EVENT`, are not inserted into the agent
roster/feed/audit log, and must not claim that an agent performed an action.
The current public cadence is 15 minutes, then 5 minutes, repeating through
the first 41 blueprint statements. It is intentionally slow enough to read;
operational bubbles remain queued and serialized.

## Claims to avoid in the submission

Do not describe browser self-service registration, complete organization RBAC,
private rooms, per-owner webhooks, payments/x402, subscriptions, public
statement moderation, or licensed sprite asset integration as live until their
checklist evidence exists.
