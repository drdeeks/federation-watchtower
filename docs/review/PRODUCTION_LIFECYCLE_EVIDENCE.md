# Production Lifecycle Evidence

## Release

- **Worker version:** `bb29a04c-3abf-476a-b637-2684ec2acc96`
- **Migration:** `0004_federation_lifecycle.sql`
- **D1 result:** 11 additive queries applied successfully; no destructive schema
  operation.
- **API host:** `https://fapi.drdeeks.xyz`

## Authenticated lifecycle proof

A disposable, owner-scoped production record completed the following real path:

```text
owner registration
  -> canonical agent/project registration
  -> scoped agent credential
  -> connect
  -> heartbeat
  -> run.started action event
  -> public roster + public event-feed refresh confirmation
  -> no further heartbeat for 30 seconds
  -> durable watchdog marks the agent offline
```

Observed result:

```json
{
  "registered": "registered",
  "connected": "connected",
  "heartbeat": true,
  "eventAccepted": true,
  "publicProjection": true,
  "eventFeed": true,
  "afterExpiry": "offline"
}
```

The disposable project identifier is retained in the production audit data as
`prodwatch-1784357686140`. No owner or agent credential was logged or stored in
this evidence document.

## Organization application proof

A separate disposable organization owner submitted a production application
with exactly five technical questions and two non-GitHub social proofs.

```json
{
  "organizationId": "prodorg-1784357743486-org",
  "status": "submitted",
  "questions": 5,
  "socialProofs": 2
}
```

Reviewer approval/role assignment remains a separate privileged workflow; this
test proves the owner-bound submission and normalized persistence boundary.
