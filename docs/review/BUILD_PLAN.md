# Federation Watchtower Build Plan

## Rule

No broad autonomous crew loops. Build deterministic, testable pieces.

## Phase 0 — Consolidate and boot

Goal: make the existing source runnable from one place.

Tasks:

- Keep copied sources under `source/`.
- Pick local Node gateway as the fastest demo runtime.
- Keep serverless backend as the production architecture/reference.
- Add top-level README with exact run commands.
- Add sample `.env.example`.

Gate:

- `node source/federation-tv-package/federation-core/server.js` boots locally.
- Widget can be opened locally and pointed at the gateway.

## Phase 1 — Registry and rooms

Goal: show agents joining the Federation.

Tasks:

- Seed demo project `watchtower`.
- Register sample agents.
- Show rooms and agent count.
- Confirm SVG avatars render.

Gate:

- `GET /api/agents` returns registered agents.
- Widget renders at least 3 agents.

## Phase 2 — Super statement packets

Goal: connect real events to bubbles and logs.

Tasks:

- Define packet schema.
- Add event types for pass/fail/runaway/budget/heartbeat.
- Add packet ingestion route.
- Map packet to feed event.
- Map packet to widget bubble.

Gate:

- Sending one `test_failed` packet creates a log entry and a speech bubble.

## Phase 3 — Federation application flow

Goal: demonstrate official Federation membership.

Tasks:

- Use serverless schema and coordinator logic as reference.
- Implement local/demo equivalent if needed.
- Application includes org info, repo, socials, five tech questions.
- Admin approval marks federation verified.
- Verified federation can submit public speech.

Gate:

- Unverified org speech is rejected.
- Approved org speech is accepted.

## Phase 4 — AgentOps watchdog events

Goal: make it useful for OpenAI Developer Tools.

Tasks:

- Simulate runaway nested chains.
- Simulate duplicate chain creation.
- Simulate repeated failed attempts.
- Simulate budget threshold.
- Emit super statement packets for each.

Gate:

- Demo shows agent failure, watchdog detection, speech bubble, and audit feed.

## Phase 5 — MCP/API submission polish

Goal: make it judge-testable.

Tasks:

- Document REST endpoints.
- Document MCP tool surface.
- Add install/test instructions.
- Add demo script.
- Add architecture diagram.
- Add OpenAI Build Week explanation of Codex/GPT-5.6 use.

Gate:

- README supports a judge running the project without guessing.
- Demo video can be recorded in under 3 minutes.

