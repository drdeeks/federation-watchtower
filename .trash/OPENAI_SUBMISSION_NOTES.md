# OpenAI Build Week Submission Notes

## Track

Developer Tools.

## Project description draft

Federation Watchtower is the visible control plane for real autonomous systems, disguised as an embeddable sitcom. It lets organizations register verified agent fleets, expose live events through REST/WebSocket/MCP, connect guardrail and validation services, detect runaway loops and failures, and display tiny SVG agents that turn machine events into human-readable, weirdly memorable status bubbles.

Under the humor is a serious developer tool: event logging, heartbeat visibility, attempt and budget tracking, guardrail signals, validation gates, federation membership, MCP access, enterprise blueprint references, and a live operational feed that makes autonomous agent systems observable and governable.

## Demo narrative

1. Open the Federation TV widget.
2. Show empty/live Federation room.
3. Submit an organization application with five technical questions.
4. Approve the organization.
5. Register three agents.
6. Trigger heartbeat/status events.
7. Trigger a failing test event.
8. Show the agent speech bubble and the serious log underneath.
9. Trigger runaway nested-chain/budget event.
10. Show Watchtower blocking/reporting it.

## Required OpenAI items

- Working project.
- Category: Developer Tools.
- Repo URL.
- README with setup/run instructions.
- Demo video under 3 minutes.
- Voiceover explaining:
  - what was built
  - how Codex was used
  - how GPT-5.6 was used
- `/feedback` Codex Session ID.

## Judging angle

This is not a generic dashboard. The product answers a real problem:

> Autonomous coding agents can silently burn credits, recurse into duplicated work chains, and corrupt project state. Federation Watchtower makes those systems visible, funny enough to watch, and strict enough to trust.
