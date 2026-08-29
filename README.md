<img width="755" height="265" alt="Federation Watchtower Banner" src="https://github.com/user-attachments/assets/96a5e62d-c6a9-4611-bb1f-a14c433c127a" />

# Federation Watchtower

**Federation Watchtower is a developer tool that makes autonomous work visible before it becomes expensive.** It is an agent-operations control plane with a security-camera sitcom presentation: real agents, heartbeats, events, guardrails, validation decisions, and watchdog signals are made readable for humans without turning the operational record into theater.

**Live public Watchtower:** [watch.drdeeks.xyz](https://watch.drdeeks.xyz)

**Machine/API ingress:** [fapi.drdeeks.xyz](https://fapi.drdeeks.xyz)

**Member/operator surface:** [federation.drdeeks.xyz](https://federation.drdeeks.xyz)

> Operational truth is the product. Theatrical presentation makes it watchable.

## Why it exists

### The origin story

I had no Qwen credits left after Hermes kept corrupting my work — nesting within nesting within nesting, duplicated chains multiplying on top of each other. I burned **25,000 credits** the moment I looked away. That's the failure that started this.

But from that loss came an iteration: a TV sitcom where agents working on tasks could be seen on screen, doing really stupid stuff. When something happened, they'd have a speech bubble triggered by it:

- Test fails? *"The boiler room just combusted — everybody get to safety!"*
- Thirty duplicate files being processed consecutively? *"I made a checklist for my checklists checklist — does anybody wanna make a checklist about that?"*

The comedy is the hook. But the purpose is to **monitor what's actually happening** — to not be left clueless while giving everything you've got.

### The personal context

Bro.. I have a 1.87 GHz, 2-core, 4GB RAM, 2013 ThinkPad that barely opens a web browser. I'm a single father with a past that isn't lavish, and that's made it hard to get a job — constantly being shown the door, dealing with the fallout of a mistake I made over 10 years ago. I'm very creative, I prefer truth and doing my own due diligence before asking for help or believing someone, and I like pushing boundaries: testing new systems, building things that serve a real purpose. I figure things out, think mechanically, and try everything I can to get myself and my daughter in a better position.

I had five project demos that weren't quite functional. About 700 credits later, I realized the app I wanted to make wasn't going to cut it. I mentioned the Federation idea — originally a comical afterthought, a quirky agent monitoring layer for any project that wanted to join via MCP. That idea got refined into something possible and robust, then consolidated into something functional and manageable.

From burning 25,000 credits, persistent disappointment and struggles to take care of my daughter and find steady employment — building this gave me a little bit more faith in myself and the ideas I come up with. Win or lose, I take pride knowing this exists. As long as we can learn to laugh a little bit and continue to grow, everything will be OK.

### The problem

Autonomous coding agents can silently recurse, duplicate work, burn credits, lose track of state, or fail without a useful human-facing signal. The surrounding systems may already have logs, validators, policy checks, and recovery workers, but operators still need a shared surface that makes the whole system understandable.

### The solution

Watchtower unifies the visible operational layer for those systems:

| Capability | What it does |
| --- | --- |
| **Federation registry** | Organizations, projects, agents, rooms, identities, heartbeats, and live events. |
| **Guardrail monitoring** | Runaway loops, duplicate chains, budget pressure, invalid states, and blocked work become explicit events. |
| **Validation and enforcement** | Blueprint gates, policy checks, source verification, and structured review signals report into the same feed. |
| **MCP/API/widget access** | Agents and external systems use MCP or REST, while humans get a live public broadcast and embeddable widget. |
| **Enterprise operations** | Crew coordination, memory, audit, recovery, self-healing, and integration patterns share the same event and review surface. |

The sitcom is the interface layer. **The real product is a shared observability and governance surface for autonomous systems.**

### How it works

Organizations and projects register agents into isolated namespaces. Agents report status and heartbeats, while operational systems emit structured packets for tests, validation gates, budget thresholds, recursive chains, policy failures, and watchdog actions. The system keeps those events machine-readable for integrations and renders them as an operational feed plus deterministic SVG characters with short status bubbles.

The colorful TV presentation is intentionally a hook, not a substitute for controls. A sparse, labelled ambient cameo may appear in an empty public room; it is never an agent, an event, or audit evidence.

## What is working now

- A Cloudflare Worker backed by Durable Objects, D1, R2, and an alert Queue/DLQ.
- Public, read-only room, roster, agent-detail, event-feed, and WebSocket observation surfaces.
- Administrative project/agent registration and heartbeat/status routes.
- Signed, idempotent operational event ingress with timestamp/replay checks and secret-shaped metadata redaction.
- Runtime-neutral liveness: a signed `heartbeat` event can arrive from an agent package, CI runner, webhook adapter, or MCP/REST integration; no persistent WebSocket connection is required for an agent to remain present.
- Guardrail decisions for duplicate/runaway chains, validation failures, budgets, cooperative leases, controlled tool authorization, and heartbeat expiry/watchdog incidents.
- Hash-chained audit decisions, incident records, bounded evidence exports, and an embeddable dependency-free JavaScript widget.
- A standard-library Loop Enforcer adapter that treats a denied lease, gate, or controlled-tool decision as a stop result (`exit 3`).
- Per-organization operator credentials (admin-issued, scoped to one organization) and per-organization/per-agent webhook destinations, with canonical owner/agent bearer auth now covering the 4 previously HMAC-only legacy routes.

## Technical implementation

| Component | Technology | Purpose |
| --- | --- | --- |
| **Edge runtime** | Cloudflare Workers | Global low-latency API and static asset hosting |
| **State coordination** | Durable Objects | Per-project agent registries and global federation coordination |
| **Structured storage** | D1 (SQLite) | Projects, agents, rooms, events, federation applications, verified organizations, access logs |
| **Object storage** | R2 | Federation vault for evidence exports and audit artifacts |
| **API contracts** | TypeScript REST + WebSocket | Machine-readable ingress for agents and external systems |
| **Integration layer** | MCP-oriented contracts | External organizations and agent clients |
| **Browser embedding** | Dependency-free JavaScript widget | Deterministic SVG avatars and embeddable broadcast |
| **Branding** | Canonical SVG + theme tokens | Lightweight splash screen and consistent visual identity |
| **Reference patterns** | Repository guardrails | Blueprint validation, crew coordination, source verification, self-healing operations |

## Why this is a developer tool

Federation Watchtower is built for agentic workflows, DevOps, observability, testing, security, and operational safety. It gives developers one surface for seeing what their agents are doing, which guardrails fired, which validation gates passed or failed, and what needs attention. It also provides a testable public deployment and a dependency-free local adapter.

| Use case | How Watchtower helps |
| --- | --- |
| **Agentic workflows** | See what autonomous agents are doing in real time before credits disappear |
| **DevOps & CI/CD** | Guardrail signals, validation gates, and budget thresholds become explicit events |
| **Observability** | Unified event feed with machine-readable packets and human-readable status bubbles |
| **Testing** | Validation failures, runaway detection, and duplicate chains are logged as incidents |
| **Security** | Audit trails, incident tracking, hash-chained decisions, bounded evidence exports |
| **Operational safety** | Watchdog expiry, cooperative leases, controlled tool authorization, stop-before-side-effect rules |

## Design principles

Lessons that shaped how this is built, and that guide what gets built next:

- **Visibility is prevention** - Most runaway costs come from work that becomes invisible. Making agent presence and events readable in real time prevents expensive failure modes before they compound.
- **Evidence must be immutable** - Operational truth requires hash-chained audit records, idempotency keys, and durable event storage that cannot be retroactively modified.
- **Presentation ≠ fabrication** - Theatrical UI can make operations watchable without inventing state. Color and animation assist recognition but never substitute for real lifecycle text.
- **Credential boundaries matter** - Keeping owner/agent credentials scoped and separate from administrative secrets prevents privilege escalation and accidental exposure.
- **Watchdogs need teeth** - A missed heartbeat must have consequences: lifecycle state transitions, public scene removal, and credential invalidation.

## Agent Lifecycle (Canonical Flow)

The agent lifecycle is a state-machine with explicit transitions, watchdog enforcement, and public projection. Every transition is recorded as an immutable event.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AGENT LIFECYCLE STATE MACHINE                        │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────┐     owner credential      ┌──────────┐
  │   NEW    │ ────────────────────────> │ REGISTER │
  └──────────┘   POST /api/v1/owners     └──────────┘
                                            │
                                            │ manifest validation
                                            │ POST /api/v1/agents
                                            │ (owner-scoped credential)
                                            ▼
                                       ┌────────────┐
                                       │ REGISTERED │ ◄───┐
                                       └────────────┘     │
                                            │             │ reconnect
                                            │ connect     │
                                            │ POST        │
                                            ▼             │
                                       ┌────────────┐     │
                                       │ CONNECTED  │ ────┘
                                       └────────────┘
                                            │
                              ┌─────────────┼─────────────┐
                              │             │             │
                         heartbeat     emit event    watchdog miss
                      (extends deadline)  (guardrail    (>120s default)
                              │         evaluates)         │
                              │             │              ▼
                              │             │         ┌──────────┐
                              │             │         │ OFFLINE  │
                              │             │         └──────────┘
                              │             │              │
                              ▼             ▼              │
                         ┌────────────┐ ┌──────────┐       │ disconnect
                         │ CONNECTED  │ │ BLOCKED  │ ──────┘
                         └────────────┘ └──────────┘   POST /disconnect
                              │             │
                         disconnect       │
                              │       guardrail
                              ▼       denies lease
                         ┌──────────┐
                         │ OFFLINE  │
                         └──────────┘
```

### Lifecycle States

| State | Description | Public Projection | Watchdog |
|-------|-------------|-------------------|----------|
| `registered` | Agent identity created, credential issued | Optional (if `publicProjection: true`) | Inactive |
| `connected` | Active lease, heartbeat current | Yes | Active (deadline enforced) |
| `blocked` | Guardrail denial (validation failure, runaway, budget) | Yes (with incident) | Active |
| `offline` | Disconnected or watchdog expiry | Yes (removed from scene) | Inactive |
| `revoked` | Credential invalidated by owner/admin | No | Inactive |

---

### Work Lease Options

Agents have **flexible lease strategies** depending on their workflow:

#### Option 1: Auto-Lease at Registration (Simple Agents)

At registration, request an automatic lease:

```json
POST /api/v1/agents
{
  "agentId": "build-runner-01",
  "projectId": "autopilot",
  "capabilities": ["build", "test"],
  "heartbeat": { "intervalSeconds": 60 },
  "statement": "Runs the build, tests config changes, and reports what happened.",
  "lease": {
    "ttlSeconds": 300,
    "scopes": ["build", "test"]
  }
}
```

`statement` is required (≤120 chars) — it seeds this agent's one-time entry in
the public speech pool that later drives tone-matched character bubbles.

**Response includes lease:**
```json
{
  "lease": {
    "leaseId": "lease_uuid123",
    "status": "active",
    "expiresAt": 1721487900000
  },
  "next": {
    "leaseValidate": "/api/v1/projects/autopilot/leases/lease_uuid123/validate"
  }
}
```

**Agent can work immediately** - no separate lease request needed.

#### Option 2: Manual Lease Request (Complex Agents)

**Register without lease**, then request when needed:

```bash
# Request lease before work
curl -X POST https://fapi.drdeeks.xyz/api/v1/projects/autopilot/leases \
  -H "Authorization: Bearer fw_agent_..." \
  -d '{
    "projectId": "autopilot",
    "agentId": "build-01",
    "runId": "build-run-42",
    "ttlSeconds": 300,
    "scopes": ["build", "deploy"]
  }'
```

**Lease Parameters:**

| Parameter | Min | Max | Default | Purpose |
|-----------|-----|-----|---------|---------|
| `ttlSeconds` | 30 | 3600 | 300 | Lease duration |
| `scopes` | 1 | 16 items | capabilities | Permitted actions |
| `runId` | 1 char | 128 chars | required | Run/session ID |

**Lease states:** `active` (can work), `denied` (blocking command), `revoked` (guardrail revoked), `expired` (TTL elapsed)

**Before each action:**
```bash
curl -X POST /api/v1/projects/autopilot/leases/{leaseId}/validate \
  -H "Authorization: Bearer fw_agent_..." \
  -d '{"agentId":"build-01"}'

# If status != "active", STOP (exit 3)
```

See [`agents-skill.md`](source/federation-serverless/agents-skill.md) for complete lease documentation.

---

### Automated Testing

Three test scripts cover the full lifecycle:

```bash
# 1. Local validation (TypeScript, unit tests, syntax, git)
./scripts/local-test-runner.sh

# 2. End-to-end lifecycle (success path)
./scripts/e2e-agent-lifecycle.sh

# 3. Guardrail failure scenarios (validation runaway, duplicate chains, budget alerts)
./scripts/test-guardrail-failures.sh
```

**Expected output:** All tests pass with clear PASS/FAIL indicators, incident counts, and guardrail decision traces.

## Deliberate current boundaries

Watchtower is not represented as more complete than it is. The following are now available as an additive API lifecycle, but still need browser onboarding, credential rotation/revocation UI, and production migration/release evidence:

- Owner credentials and per-agent scoped credentials returned once at registration; credentials stay on the owner/agent host, never on `watch`.
- Canonical manifests plus owner → credential → connect → heartbeat/event → disconnect flows with watchdog expiry.
- Organization applications with five technical Q&A and two non-GitHub social proofs (reviewer UI and role controls are not implemented).
- Room lifecycle management beyond the current single-room projection.
- Organization approve/suspend in the admin console: fixed locally and validated
  against a real (forked, non-production) D1 database, but not yet applied to
  production `federation-db` — migration `0010` and the `management.ts` fix
  must both ship before this is live. See `AGENTS.md`'s "Validation before
  handoff" section for the underlying D1 recreate-with-inbound-foreign-keys
  gotcha this migration had to work around.

## How to try it

### 🎯 Option A: Live Demo (Easiest - 2 minutes)

**No installation required. Works right now:**

1. **Visit the public Watchtower**: [watch.drdeeks.xyz](https://watch.drdeeks.xyz)
   - See the camera room view with agent roster and event feed
   
2. **Create an owner and register an agent**: [onboarding page](https://federation.drdeeks.xyz/onboarding.html)
   - Click "Create owner" → enter `demo-user` → get scoped credential
   - Scroll to "Register an agent" → fill in details → get agent credential
   - Check "Show this agent on public Watchtower" to make it visible
   
3. **Run the live loop** (on the same onboarding page)
   - Click **Connect** → **Heartbeat** → **Emit action now** → **Disconnect**
   - Or click **Start auto loop** to see continuous heartbeats and events
   
4. **Watch your agent appear** on the [public Watchtower](https://watch.drdeeks.xyz)
   - Your agent will show up in the roster
   - Click the agent to see details and event history
   - The event feed shows all your operational events in real time

### 🧪 Option B: Local Testing (for developers)

```bash
# Clone the repository
git clone https://github.com/drdeeks/federation-watchtower
cd federation-watchtower

# Install dependencies and run tests
cd source/federation-serverless
npm install
npm run types && npm test

# Run SDK tests
cd ../../packages/watchtower-sdk
npm install && npm test

# Verify JavaScript syntax
node --check source/federation-tv-widget/public/tv-widget.js
node --check source/federation-tv-widget/src/tv-widget.js

# Verify git cleanliness
git diff --check
```

**Expected output:**
```
✅ TypeScript compilation: PASS
✅ Unit tests: 51/51 PASS
✅ SDK tests: 8/8 PASS
✅ JavaScript syntax: PASS
✅ Git diff: CLEAN
```

See [TESTING_GUIDE.md](TESTING_GUIDE.md) for complete test documentation.

### 📦 Installation (for local development)

**Requirements:**
- Node.js 20 or newer
- Cloudflare Workers account (free tier works)
- Wrangler 4 (included in package.json)

```bash
# Clone repository
git clone https://github.com/drdeeks/federation-watchtower
cd federation-watchtower

# Install dependencies
cd source/federation-serverless
npm install

# Generate TypeScript types from Wrangler bindings
npm run types

# Run tests
npm test

# Deploy to Cloudflare (requires authentication)
npm run deploy

# Apply database migrations (in order)
# Convenience: run every migration 0001 -> 0012 in correct order:
npm run migrate:all
# Or individually:
npm run migrate:watchtower           # 0001: Core enforcement
npm run migrate:control-loop         # 0002: Watchdog, audit, sessions
npm run migrate:access-gateway       # 0003: Owner credentials, org applications
npm run migrate:lifecycle            # 0004: Canonical lifecycle events
npm run migrate:management           # 0005: Admin management tables
npm run migrate:alert-sink           # 0006: Alert webhook receipts
npm run migrate:speech-seed          # 0007: Seed speech repertoire
npm run migrate:audit-chain-integrity# 0008: Audit chain integrity
npm run migrate:speech-lines-drop-fk # 0009: Drop federation FK on speech lines
npm run migrate:organizations-widen-status # 0010: Widen org status CHECK (deploy-gated)
npm run migrate:operator-credentials # 0011: Per-org operator credentials
npm run migrate:webhook-destinations # 0012: Per-org/agent webhook destinations
```

See [DEPLOY.md](DEPLOY.md) for complete deployment guide.

### 🔧 Supported Platforms

- **Runtime:** Cloudflare Workers (edge)
- **Browser:** Any modern browser (Chrome, Firefox, Safari, Edge)
- **API:** REST, WebSocket, MCP
- **SDK:** Node.js 20+ (`@federation-watchtower/sdk` on npm)

### 🔑 Test Credentials

For local testing, use disposable credentials, e.g.:

```
Owner ID: test-demo
Agent ID: test-agent-{random}
Project ID: test-project
```

No authentication required for public Watchtower or onboarding. Admin console requires `WATCHTOWER_ADMIN_TOKEN` (available on request).

### 🧪 Test Alert Webhooks (Advanced)

The alert webhook system sends signed POST requests when guardrail rules fire. To test:

**1. Start a local webhook receiver:**
```bash
cd /tmp
cat > webhook-test.py << 'PYTHON'
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, sys

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        data = self.rfile.read(length).decode()
        print(f"\n🔔 ALERT RECEIVED:")
        print(json.dumps(json.loads(data), indent=2))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')
    def log_message(self, format, *args): pass

print("Webhook receiver: http://localhost:8888/alert")
HTTPServer(('localhost', 8888), Handler).serve_forever()
PYTHON
python3 webhook-test.py
```

**2. Configure environment variables** (in `.dev.vars` or Worker settings):
```
WATCHTOWER_ALERT_WEBHOOK_URL=http://localhost:8888/alert
WATCHTOWER_ALERT_WEBHOOK_FORMAT=json
WATCHTOWER_ALERT_WEBHOOK_SECRET=your-test-secret
```

**3. Trigger a guardrail alert** by:
- Running an agent with validation failures (3+ triggers alert)
- Exceeding budget threshold
- Creating duplicate chain keys

**4. Check the admin console** at [manage.html](https://federation.drdeeks.xyz/manage.html) for alert receipts

**Global Watchtower alert channel:** production guardrail alerts (runaway/duplicate
chains, budget thresholds, heartbeat-missed incidents) are also delivered to the
Slack destination configured via `WATCHTOWER_ALERT_WEBHOOK_URL` /
`WATCHTOWER_ALERT_WEBHOOK_FORMAT=slack`:
[the drdeeks Slack workspace's alert channel](https://drdeeks.slack.com/archives/C0BHYPAMT4P).
Delivery is opt-in — if no webhook URL is configured, alerts are recorded
`suppressed` in `alert_webhook_receipts` and nothing is sent externally.

## Architecture

### Hosts and domains

| Host | Audience | Purpose |
| --- | --- | --- |
| `watch.drdeeks.xyz` | Everyone | Public, read-only Watchtower: room view, public roster, public agent details, feed, agent/organization onboarding documentation, hosted agent skill. |
| `federation.drdeeks.xyz` | Approved members/operators | Reserved Federation/member area and token-protected operator console. Organization-scoped roles are not implemented yet. |
| `fapi.drdeeks.xyz` | Agent hosts/integrations | Health, REST, signed event ingestion, MCP, WebSocket, and control-plane endpoints. |

### Core components

- **Cloudflare Worker** (`source/federation-serverless/src/index.ts`) - Main entry point, routes requests to appropriate handlers
- **Durable Objects** - Stateful coordination for agent registry, watchdog, guardrails, and room scenes
- **D1 Database** - Persistent storage for agents, events, incidents, and audit records
- **R2 Bucket** - Evidence exports and large object storage
- **Queue** - Alert delivery with dead-letter queue for retry handling

## Documentation

- [**AGENTS.md**](AGENTS.md) - Operational guide for people and coding agents working in this repository
- [**CHANGELOG.md**](CHANGELOG.md) - The one project-wide change log
- [**TESTING_GUIDE.md**](TESTING_GUIDE.md) - Complete testing documentation with automated scripts
- [**System Specification**](docs/review/FEDERATION_SYSTEM_SPEC.md) - Expanded product context and technical details
- [**Access and Onboarding**](docs/review/ACCESS_AND_ONBOARDING.md) - Agent, owner, organization, and administrator boundaries
- [**Host Surface Contract**](docs/review/HOST_SURFACE_CONTRACT.md) - Current domain boundaries and explicit gaps

## License

MIT. See [LICENSE](LICENSE).
