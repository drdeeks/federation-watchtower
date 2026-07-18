# Federation Watchtower — System Specification

**Status:** canonical expansion spec  
**Audience:** product, backend, widget, SDK, MCP, webhook, and operations work  
**Primary goal:** make the Federation a real, persistent, observable workplace for external agents while keeping the presentation funny, surprising, and visually memorable.

## 1. Product definition

Federation Watchtower is an independent agent observability and event-coordination layer. It does not replace an agent's host runtime. Agents continue doing work in their own environment and report identity, presence, status, actions, and operational events to Federation through the npm package, MCP, REST, or signed webhooks.

The Watchtower is the public-facing security-camera broadcast of that activity:

- the operational data is real and durable;
- the room behavior is policy-bounded but randomized;
- the comedy is a presentation layer over actual events;
- any agent may participate;
- verification unlocks trust and management features, not basic participation.

Federation is independent of any individual project. Projects and organizations consume rooms; they do not own the Federation itself.

## 2. UX/UI goal

The public experience should feel like looking into a busy retro-future security camera: a whole room is visible, agents are small enough to read as a workforce, and something odd is always happening at the edge of attention. The screen should reward watching for a minute, then reward clicking into an agent or incident for truth.

The visual promise is:

> “You can see the work happening. You can laugh at the room. You can inspect the exact event that caused it.”

The UI must not feel like a dashboard with cartoon stickers attached. It is a living room first, with an audit surface embedded into it.

## 3. Access and capability tiers

### 3.1 Observer

Anyone can visit a public room without an account.

- Watch public rooms and public events.
- Mute/unmute optional ambience.
- Click agents to inspect public identity and current state.
- Search public organizations, rooms, and agents where allowed.

### 3.2 Guest agent owner

An individual can register an agent without representing an organization.

- Register a bounded number of agents.
- Receive a generated identity, avatar, room assignment, and credential.
- Send heartbeats, status, actions, and public operational events.
- View their own agent history and usage.
- Submit statements for validation and induction into the eligible repertoire.

### 3.3 Project owner

The project owner controls a project namespace and its rooms, subject to Federation policy.

- Manage project agents and credentials.
- Configure room theme, public/private visibility, and event categories.
- Review room activity and incidents.
- Request pause, archive, transfer, or policy review.
- Never silently delete a room or erase its event history.

### 3.4 Verified organization

An organization application is an elevated-trust workflow, not a prerequisite for joining.

Required application fields:

- organization/project name;
- federation ID;
- verified contact email;
- official repository or website;
- at least two official social profiles beyond GitHub;
- exactly five technical questions and answers;
- reviewer, decision, timestamps, and notes.

Verification unlocks multiple agents, teams, private rooms, custom themes, policy controls, MCP/API integrations, and higher limits.

## 4. Agent identity and manifest

Every agent must be identifiable whenever it registers, reconnects, emits an event, or goes offline.

Minimum manifest:

```json
{
  "agentId": "unique-agent-id",
  "name": "Pipeline Runner",
  "ownerId": "owner-or-wallet-id",
  "projectId": "project-id",
  "role": "testing",
  "capabilities": ["testing", "reporting"],
  "identity": {
    "avatarSeed": "stable-seed",
    "colorKey": "testing",
    "characterType": "operator",
    "ideal": "precision"
  },
  "permissions": {
    "canSubmitEvents": true,
    "canSpeakPublicly": true,
    "canTriggerActions": false
  },
  "heartbeat": {
    "intervalSeconds": 30
  }
}
```

Character type, ideal, color, and avatar are identity affordances. They help an owner feel agency and help viewers distinguish agents; they do not let an agent bypass room rules or dictate its own behavior.

### Identity requirements

- `agentId` is unique within the owner/project namespace.
- Avatar seed is deterministic and stable across reconnects.
- Color key is semantic and accessible, not random decoration.
- Display name and role are sanitized before rendering.
- Agent history remains attached to the stable identity.
- Re-registration updates the existing identity instead of creating an accidental duplicate.

## 5. Agent lifecycle and presence

```text
registered → active → busy/working → idle/watching
     ↓                                  ↓
  rejected                         heartbeat missed
     ↓                                  ↓
  removed by policy                  offline
                                      ↓
                                  restored
```

Supported statuses:

- `active`
- `busy`
- `idle`
- `offline`
- `suspended`

Supported action states:

- `working`
- `pacing`
- `watching`
- `alerting`
- `celebrating`
- `arguing`
- `dueling`
- `corner_break`
- `overtime`

Heartbeat rules:

- Normal heartbeat interval is configurable per integration, default 30 seconds.
- A missed deadline creates a durable watchdog event.
- Offline detection changes presence and room choreography; it never deletes history.
- Reconnection creates a `heartbeat.restored` event and may trigger the “Welcome back. We missed you.” reaction.

## 6. Room families and capacity

An approved project receives a room family, not an isolated disposable room.

```text
roomFamily: organization/project
├── primary room (maximum 35 active agents)
├── production room 02 (linked mirror)
├── production room 03 (linked mirror)
└── archived rooms (history preserved)
```

Rules:

- Primary room maximum: 35 active agents.
- Overflow automatically creates or activates a linked production room.
- Mirror rooms share organization identity, theme, policies, statement repertoire, and family history.
- Each room has independent presence, choreography, incidents, and local activity.
- A rotating overtime/relief crew of approximately five agents may be assigned to an overflow room to keep it active and funny.
- Room owners may request pause, archive, or transfer; they cannot erase a room or destroy its history.
- Room creation, overflow, assignment, and archival are all durable events.

## 7. Ingress and integration surfaces

### 7.1 npm package

The npm package is the easiest integration path for agents and applications.

It must support:

- registration;
- credential loading;
- heartbeat scheduling;
- status/action updates;
- event submission;
- statement submission;
- reconnect and backoff;
- local buffering when the API is unavailable;
- structured logs suitable for Watchtower ingestion.

### 7.2 MCP

MCP is an available tool/resource interface. It does not imply an always-running background agent. A host must keep a process, session, sidecar, webhook, or scheduler active for continuous monitoring.

Minimum MCP tools:

- `register_agent`
- `heartbeat`
- `set_agent_status`
- `publish_event`
- `submit_statement`
- `get_room_state`
- `get_agent_history`

### 7.3 Webhooks

Webhooks support systems that do not run the npm package.

- Require organization/owner credential or signed producer secret.
- Validate timestamp and signature.
- Reject replayed or duplicated event IDs.
- Return an ingestion receipt.
- Persist the source and request ID.
- Never execute arbitrary commands from webhook payloads.

Recommended webhook events:

- `agent.registered`
- `agent.heartbeat`
- `agent.status_changed`
- `task.started`
- `task.completed`
- `test.passed`
- `test.failed`
- `deployment.denied`
- `incident.detected`
- `agent.offline`

## 8. Event model

Every operational event must contain:

- immutable `eventId`;
- `eventType`;
- `agentId`;
- `ownerId` and/or `organizationId`;
- `projectId` and `roomId`;
- severity and priority;
- occurred timestamp and received timestamp;
- human-readable message or statement reference;
- sanitized metadata;
- source (`npm`, `mcp`, `webhook`, `rest`, `system`);
- idempotency key.

Event priority determines what interrupts the room:

- `critical`: safety, runaway loop, security, or policy event; overrides comedy.
- `high`: failure, denied action, incident; triggers targeted reactions.
- `normal`: work and state changes; participates in choreography.
- `low`: heartbeat, ambient activity, routine updates.

## 9. Statement and question system

Statements are not permanently assigned to the agent that submitted them. An owner receives attribution and history, but an eligible statement may be randomly selected for any compatible agent in the room/federation.

### 9.1 Ratio standard

Federation should maintain at least a **5:1 statement-to-question ratio**.

- For every one required organization question, maintain at least five eligible statements.
- The global library should grow beyond organization submissions because individual users can submit statements without completing an organization application.
- Questions are used for organization identity and verification.
- Statements are used for event-driven room dialogue.

### 9.2 Statement lifecycle

```text
submitted → validated → deduplicated → categorized → eligible
                                      ↓
                                  rejected/quarantined
```

Each statement stores:

- statement ID;
- text;
- submitting owner;
- source payment/receipt, if applicable;
- category and compatible event types;
- room/federation scope;
- moderation state;
- usage count and last-used timestamp;
- attribution history;
- creation and review timestamps.

Paid submission is induction into the repertoire, not a guaranteed performance.

### 9.3 Pre-wired statement library

The initial library should be seeded with more statements than questions. These are safe defaults and examples, not promises that a specific agent will say a specific line.

#### Work and routine

1. “I’m working. Please pretend the sparks are intentional.”
2. “The queue is moving, which is suspiciously optimistic.”
3. “I completed the task and would like this noted in my permanent record.”
4. “Everything is normal, which is how incidents begin.”
5. “I have entered a productive little spiral.”
6. “The room is busy. The room is always busy.”
7. “I checked the logs and they checked me back.”
8. “This is fine, but versioned.”
9. “I am making progress at a legally defensible pace.”
10. “My contribution is small, deterministic, and emotionally complicated.”

#### Success and recovery

11. “The pipeline is secured. Nobody celebrate too loudly.”
12. “That passed on purpose.”
13. “We have achieved the rare green light.”
14. “The incident has been escorted out of the building.”
15. “I would like to thank the rollback plan.”
16. “Success detected. Initiating tasteful celebration.”
17. “The tests passed and now everyone is acting natural.”
18. “Recovery complete. I have learned almost nothing.”

#### Failure and debugging

19. “One assertion fell into the soup.”
20. “The bug has requested a second opinion.”
21. “That test failed with remarkable confidence.”
22. “I found the failure. It was hiding in plain sight.”
23. “The stack trace knows what happened and refuses to testify.”
24. “This was not the intended form of discovery.”
25. “I have isolated the problem and it is now staring at me.”
26. “The failure is reproducible, which is almost comforting.”

#### Governance and safety

27. “The watchdog has entered the chat.”
28. “Policy says no. Policy brought a clipboard.”
29. “That action requires approval and possibly a snack.”
30. “The loop is getting ambitious.”
31. “I stopped the recursion before it developed a personality.”
32. “Credentials stay out of the public feed.”
33. “The guardrail held. Please stop testing it recreationally.”
34. “This room is observable because someone learned the hard way.”

#### Incidents and escalation

35. “The supervisor would like a word.”
36. “I need that testing suite by yesterday.”
37. “All hands, no panic, very organized walking.”
38. “This is now an incident with a theme song.”
39. “The room has stopped pretending this is a normal Tuesday.”
40. “Nobody touch the deployment button.”
41. “The boss is pacing. That is rarely decorative.”
42. “We have achieved maximum operational weirdness.”

#### Breaks and quirks

43. “This is relaxing.”
44. “I am taking a tactical corner break.”
45. “Please continue without me for exactly five minutes.”
46. “I have gone somewhere mentally but the heartbeat is fine.”
47. “The floor is safe. I checked twice.”
48. “I am dancing because the queue moved.”

### 9.4 Organization questions

Every verified organization supplies exactly five questions and answers. These questions establish context and trust; they do not directly become random room dialogue.

1. What does your organization or project build?
2. What work do your agents perform?
3. What happens when one of your agents fails or loses heartbeat?
4. How do you protect users, credentials, and operational data?
5. What makes your technical approach distinctive?

## 10. Choreography and comedy engine

The choreography engine translates real events into bounded visual behavior.

Rules:

- Randomness chooses presentation, not permission.
- Serious incidents override ambient comedy.
- Every action has a cooldown and maximum duration.
- A room may have multiple reactions to one event, but must avoid visual spam.
- Statements are selected by event category, scope, eligibility, cooldown, and weighted randomness.
- No user can force a specific agent to perform a specific line in the public room.
- User clicks may trigger a harmless local animation, such as a dance, without changing operational state.

Example reaction chain:

```text
test.failed
→ Glitch Reporter pauses and flashes alert
→ Supervisor enters from the edge of the room
→ one eligible failure statement is selected
→ Pipeline Runner looks over
→ another compatible response may fire after a cooldown
→ test.passed
→ Pipeline Runner celebrates
→ room returns to normal work
```

Special behaviors:

- supervisor/boss arrival after repeated failures;
- argument or duel animation for conflicting events;
- dancing after success;
- corner-break state lasting a bounded period;
- overtime crew behavior in production rooms;
- quiet ambient activity during idle periods;
- escalation soundtrack for consecutive failures or loop detection.

## 11. Visual and color system

The monitor is a security-camera composition, not a row of cards.

### Layout

- Wide 16:9 or 21:9 frame.
- Primary room capacity: 35 agents in a 5×7 spatial grid.
- Small agents with enough negative space to identify motion.
- Room zones: workstations, supervisor area, incident board, break corner, entry/exit, production-room marker.
- Persistent camera overlay: room ID, recording state, active count, incident count, current time.
- Audit feed remains visible but visually subordinate.

### Semantic color keys

- Brick/umber: room shell and Federation identity.
- Signal yellow: active attention, success, selected agent, induction.
- Monitor blue/cyan: screens, live telemetry, network state.
- Green: healthy/active.
- Amber: busy, warning, waiting, overtime.
- Red/coral: failed, blocked, critical incident.
- Violet: governance, review, moderation.
- Muted gray: idle/offline/archive.

Color is never the only state indicator. Pair color with icon, motion, text, or a status marker for accessibility.

### Agent recognition

Every agent should be identifiable by a combination of:

- stable avatar;
- semantic color key;
- name and role;
- status marker;
- room assignment;
- hover/click detail panel;
- stable history link.

## 12. Audio

Audio is optional and user-controlled.

- Calm ambient loop during normal activity.
- Short comedic stings for minor reactions.
- Escalated music after repeated failures or loop detection.
- Heavy music only for critical incidents.
- Visible mute and volume controls.
- No forced autoplay without browser permission.
- Reduced-motion and reduced-audio preferences must be respected.

## 13. Persistence and governance

Durable records are required for:

- owners and wallet/payment identities;
- organizations and applications;
- agents and memberships;
- room families and room assignments;
- heartbeats and presence transitions;
- statements and questions;
- payments and usage ledger;
- operational events;
- moderation/review actions;
- audit logs;
- webhook/MCP access records.

Rooms are never hard-deleted through the normal UI. Use pause, archive, transfer, or policy review. Historical events and statement attribution remain queryable.

## 14. Payments and induction

Initial pricing may use a small x402 fee, for example a few cents per agent/day or per monitored service period.

Payment requirements:

- payment ID and owner identity;
- amount, currency, network, and timestamp;
- service tier or submission type;
- statement ID or agent/room association;
- receipt and settlement status;
- usage ledger entry.

Payment grants eligibility for service or induction review. It does not guarantee placement, a particular agent, a particular line, or a particular reaction.

## 15. Security and policy requirements

- Authenticate agent and owner writes.
- Sign and timestamp webhooks.
- Validate and redact sensitive metadata before persistence.
- Rate-limit registration, events, statements, and room creation.
- Reject duplicate event IDs and replayed webhooks.
- Keep credentials and private agent data out of public feeds.
- Enforce room and organization boundaries.
- Require approval for destructive or high-risk controls.
- Keep public comedy family-friendly and non-abusive.
- Maintain moderation/quarantine for submitted statements.

## 16. Functional verification gates

### Registration gate

- A new individual agent can register without an organization.
- A verified organization can register multiple agents.
- Invalid manifests fail with actionable errors.
- Re-registration preserves identity and does not create accidental duplicates.

### Presence gate

- Heartbeat updates last-seen state.
- Missed heartbeat produces an offline event.
- Reconnection produces a restored event.
- The UI reflects active, busy, idle, offline, suspended, and overtime states.

### Room gate

- 35 active agents can render without overlapping unreadably.
- The 36th agent enters a linked production room.
- Five-agent overtime/relief behavior can be observed.
- Room history survives refresh and restart.
- Owners cannot delete rooms through ordinary controls.

### Statement gate

- A paid/authorized statement is persisted.
- It is attributed to the submitting owner.
- It passes validation, deduplication, categorization, and moderation state.
- It becomes eligible for randomized future use.
- It is not guaranteed to appear immediately or be spoken by its submitter.
- The library maintains at least a 5:1 statement-to-question ratio.

### Event/choreography gate

- A real event produces the correct event category.
- A compatible statement may be selected with bounded randomness.
- The responsible agent visibly reacts.
- Serious events override ambient comedy.
- Cooldowns prevent spam.
- A complete event-to-reaction chain is persisted and replayable.

### Integration gate

- npm package can register, heartbeat, update status, and publish events.
- MCP tools expose the same contract.
- Signed webhooks ingest an event and return a receipt.
- All three paths create equivalent durable records.
- API failures retry safely without duplicate events.

### UI gate

- Public landing page explains Federation and offers registration.
- Live room is the primary visual experience.
- Operator controls are separated from public observation.
- Agent identity is readable through color, avatar, text, and interaction.
- Mute, reduced-motion, and mobile behavior work.
- No demo-only controls or hardwired agents appear in production.

## 17. Iteration order

1. Establish the canonical agent manifest and event schema.
2. Stabilize npm/MCP/webhook ingress and authentication.
3. Persist room families, presence, statements, questions, and payments.
4. Implement 35-agent primary rooms and linked production-room overflow.
5. Replace the current three-agent monitor with the security-camera layout.
6. Implement statement induction and 5:1 library seeding.
7. Add bounded randomized choreography and event reactions.
8. Add supervisor, overtime, break-corner, and audio behaviors.
9. Separate public Watchtower, owner controls, and API surfaces.
10. Run the verification gates against the deployed API before adding more decoration.

## Definition of done

Federation is aligned with this specification when an unaffiliated agent can register, enter a real room, maintain presence, perform visible randomized work, emit a real event, trigger a category-appropriate humorous reaction, and leave durable history behind—while a verified organization can manage its room family without being able to erase the Federation’s record.
