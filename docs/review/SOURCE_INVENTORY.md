# Federation Source Inventory

Generated from `/home/drdeek/times-up/` and staged into `/home/drdeek/projects/federation`.

## Source packages

- `source/federation-tv-package/`
  - Local Node federation gateway.
  - REST + WebSocket API.
  - Agent registry, room assignment, health monitoring, memory APIs.
  - Static TV command center.
  - MCP skill package for external access.

- `source/federation-serverless/`
  - Cloudflare Workers + Durable Objects + D1/R2 version.
  - Federation application/review system.
  - Verified federation registry.
  - Federation speech pool.
  - MCP organization registry and access logs.

- `source/federation-tv-widget/`
  - Embeddable browser widget.
  - Deterministic SVG agents.
  - Speech bubbles.
  - Less-prominent live operational feed.

## Reference skills/docs

- `skills-reference/autonomous-crew-integration.md`
  - Crew/agent architecture, identity files, checkpoints, review flow.

- `skills-reference/enterprise-blueprint/`
  - Strongest blueprint/checklist/phase-gating skill set found.
  - Includes scripts for blueprint validation, checklist generation, assignment, and enforcement.

- `skills-reference/hemlock-integration-blueprint.md`
  - Agent identity stack, builder code attribution, crew orchestration, enterprise blueprint integration.

- `skills-reference/hemlock-autonomous-crew-integration.md`
  - Additional autonomous crew integration reference.

## Most important implementation files

- `source/federation-tv-package/shared/agent-registry.js`
  - Deterministic SVG avatar generation.
  - Agent registration/update/remove.
  - Room capacity/overflow.
  - Health check loop.

- `source/federation-tv-widget/src/tv-widget.js`
  - Embeddable sitcom UI.
  - Random speech pool.
  - `submitSpeechLine(agentId, text)`.
  - Live event feed rendering.

- `source/federation-serverless/src/schema.sql`
  - D1 schema for projects, agents, rooms, feed events, federation applications, verified federations, speech lines, MCP orgs, access logs.

- `source/federation-serverless/src/index.ts`
  - Worker routes for federation application, approval, speech, MCP orgs, project APIs, WebSocket.

- `source/federation-serverless/src/federation-coordinator.ts`
  - Application validation, review approval, verified federation checks, speech-line uniqueness.

