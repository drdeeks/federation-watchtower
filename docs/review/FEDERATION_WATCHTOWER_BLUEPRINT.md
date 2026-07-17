# Federation Watchtower Blueprint

## Product statement

Federation Watchtower is an embeddable agent-operations sitcom and the visible control plane for a broader autonomous-systems safety stack. Verified organizations register agents, expose live operational events through REST/WebSocket/MCP, and render tiny SVG characters that speak when tests pass, agents fail, guardrails trigger, loops recurse, budgets burn, or incidents occur.

The joke layer is memorable. The operational and governance layers are real.

## Core systems

### 1. Federation registry

Purpose: track organizations, projects, agents, rooms, status, and live events.

Required pieces:

- Project namespace.
- Agent registration endpoint.
- Agent status endpoint.
- Heartbeat endpoint.
- Room assignment.
- Feed event table.
- WebSocket broadcast.

Existing source:

- `source/federation-tv-package/federation-core/server.js`
- `source/federation-tv-package/shared/agent-registry.js`
- `source/federation-serverless/src/agent-registry.ts`
- `source/federation-serverless/src/schema.sql`

### 2. Federation application and review

Purpose: make “joining the Federation” a real workflow instead of open anonymous posting.

Applicant provides:

- Federation/org ID.
- Organization/project name.
- Contact email.
- Official repo.
- Social profiles.
- Exactly five comical technical questions/answers.

Review flow:

- Submitted.
- Admin reviews.
- Approved/rejected.
- Approved org becomes a verified federation.
- Only verified federations can submit speech packets.

Existing source:

- `source/federation-serverless/src/index.ts`
- `source/federation-serverless/src/federation-coordinator.ts`
- `source/federation-serverless/federation-agent-instructions.sh`

### 3. Sitcom widget

Purpose: let any website embed the Federation as a living agent diorama.

Required pieces:

- Deterministic SVG agent avatars.
- Speech bubbles.
- Random background speech.
- Immediate speech on meaningful events.
- Small live operational feed under the characters.
- Script-tag embed support.

Existing source:

- `source/federation-tv-widget/src/tv-widget.js`
- `source/federation-tv-widget/public/index.html`

### 4. Serious operational feed

Purpose: keep the system useful, not just funny.

Events should include:

- `agent_registered`
- `heartbeat`
- `status_changed`
- `test_passed`
- `test_failed`
- `budget_threshold_exceeded`
- `nested_chain_detected`
- `duplicate_chain_detected`
- `watchdog_blocked_run`
- `validation_gate_passed`
- `validation_gate_failed`

The production Worker now has a formal, signed `/api/v1/events` intake with a
public-safe feed projection and core runaway-policy evaluation. The legacy
local statement adapter remains for demo compatibility. See
[`WATCHTOWER_ENFORCEMENT_IMPLEMENTATION_PLAN.md`](WATCHTOWER_ENFORCEMENT_IMPLEMENTATION_PLAN.md)
for the current implementation boundary: notifications, cooperative leases,
watchdog alarms, and pre-tool denial are the next releases.

### 5. Guardrail and enterprise operations

Purpose: make the Watchtower the presentation and telemetry surface for the repository's existing guardrail, blueprint, crew, and self-healing systems.

Guardrail signals should include:

- Runaway or recursive chain detection.
- Duplicate work and conflicting state detection.
- Budget, attempt, and rate thresholds.
- Validation-gate pass/fail results.
- Policy violations and blocked actions.
- Source, manifest, and configuration verification.
- Recovery, retry, escalation, and self-healing outcomes.

The `skills-reference/enterprise-blueprint/` tree contains the deeper enforcement and operations patterns. The Worker/API and TV widget provide the common event surface; individual guardrail services can emit structured packets into it.

### 5. MCP and external access

Purpose: allow external organizations/agents to query and interact with the Federation programmatically.

Access modes:

- REST API.
- WebSocket feed.
- Embeddable widget.
- MCP server/gateway.

Existing source:

- `source/federation-tv-package/mcp-skill/tv-sitcom-mcp/`
- `source/federation-serverless/README.md`
- `source/federation-serverless/src/schema.sql` MCP org/access-log tables.

### 7. On-chain identity / attribution

Current state:

- ERC-8004 appears as a planned/stubbed agent registration concept in the enterprise-organization references.
- ERC-8021 builder-code attribution is the more detailed documented implementation.

Safe submission wording:

> Federation Watchtower is prepared for on-chain agent identity and includes documented builder-code attribution hooks. Full ERC-8004 registration remains a planned extension unless implemented before submission.

## OpenAI Build Week fit

Track: Developer Tools.

Why it fits:

- Agentic workflow observability.
- MCP-accessible tool surface.
- Debugging and DevOps utility.
- Codex-built product with clear developer value.
- Real-world problem: runaway autonomous agents burning credits and corrupting work.
