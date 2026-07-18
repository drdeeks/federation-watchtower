# Room Scene Contract

The RoomScene Durable Object is the single coordination point for one public
Watchtower room. It owns presentation placement only; it cannot alter an
agent's credential, lifecycle record, guardrail decision, operational event,
or audit history.

## Placement zones

| Zone | Use |
| --- | --- |
| entry / exit | registration, reconnect, offline departure |
| workbench | real work-start projection |
| console / observatory | visible, non-incident presence |
| incident | validation, denial, failure, or watchdog attention |
| lounge | bounded ambient pacing only |

The current coordinator assigns a stable bounded position and destination for
each public agent. It records a monotonically increasing room sequence and a
small recent scene-event history. The public read surface is:

`GET /api/v1/public/rooms/{roomId}/scene`

## Truth boundary

Operational and lifecycle projections include the event type and source event
ID. They are derived from registration, connect, heartbeat, disconnect,
watchdog, signed ingestion, and canonical agent events.

An occasional unsourced movement is allowed for the sitcom. It is emitted as
`presentation.ambient` and labelled exactly:

`ambient choreography · no operational event`

It must never change lifecycle state, operational action, public feed evidence,
or guardrail data. A browser may animate a supplied scene transition but may
not invent a new agent, position, action, or event.

## Current limit

The Watchtower browser consumes this endpoint for selected rooms and transitions
only between server-issued positions. Sprite-sheet rendering remains Phase 4
integration work. Tiny Village and character assets are candidates for the
visual skin only after their redistribution terms are recorded.
