<img width="755" height="265" alt="Federation Watchtower Banner" src="https://github.com/user-attachments/assets/96a5e62d-c6a9-4611-bb1f-a14c433c127a" />

# Federation Watchtower

**Federation Watchtower is a developer tool that makes autonomous work visible before it becomes expensive.** It is an agent-operations control plane with a security-camera sitcom presentation: real agents, heartbeats, events, guardrails, validation decisions, and watchdog signals are made readable for humans without turning the operational record into theater.

**Live public Watchtower:** [watch.drdeeks.xyz](https://watch.drdeeks.xyz)

**Machine/API ingress:** [fapi.drdeeks.xyz](https://fapi.drdeeks.xyz)

**Member/operator surface:** [federation.drdeeks.xyz](https://federation.drdeeks.xyz)

> Operational truth is the product. Theatrical presentation makes it watchable.

## Why it exists

### The origin story

This project began with a costly and familiar failure mode. While building another hackathon project with five demos and a working scaffold, I looked away for one moment. The kanban didn't use proper mechanisms, an AI decided to take the easy way out instead of dealing with loops correctly, and **25,000 credits went up in flames** within five minutes. I was back to nothing but free models.

But from that loss came an iteration: a TV sitcom where agents working on tasks could be seen on screen, doing really stupid stuff. When something happened, they'd have a speech bubble triggered by it:

- Test fails? *"The boiler room just combusted — everybody get to safety!"*
- Thirty duplicate files being processed consecutively? *"I made a checklist for my checklists checklist — does anybody wanna make a checklist about that?"*

The comedy is the hook. But the purpose is to **monitor what's actually happening** — to not be left clueless while giving everything you've got.

### The personal context

I operate on a 2013 ThinkPad with 1.87 GHz, 2 cores, 4GB RAM that can barely open a browser. Being a single father with struggles from a mistake I made over 10 years ago, constantly being shown the door in job opportunities has been very difficult. I've always been a creative person who enjoys taking things most people throw away and transforming them into something completely different — 1/1 items. I figure things out, think mechanically, and try everything I can to get myself and my daughter in a better position.

When I started using Codex, I had five project demos that weren't quite functional. About 700 credits later, I realized the app I wanted to make wasn't going to cut it. I mentioned the Federation idea — originally a comical afterthought, a quirky agent monitoring layer for any project that wanted to join via MCP. Codex refined my concept into something possible and robust, then helped consolidate my refund into something functional and manageable.

After running out of credits and having to take it to Claude (which I've grown to strongly dislike), everything was built the exact way I felt it should be built: proper, robust, accurate, and solidified. All we had to do was start implementing the UI and features.

From burning 25,000 credits, using almost half my allocation on Codex, persistent disappointment and struggles to take care of my daughter and find steady employment — Codex made me have a little bit more faith in myself and the ideas I come up with. Win or lose, I take pride knowing this exists. As long as we can learn to laugh a little bit and continue to grow, everything will be OK.

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

## The Build Week fit

**Track: Developer Tools.** Watchtower is for developers operating agentic workflows, CI/CD, testing, DevOps, and guarded automation. It combines a Cloudflare Worker control plane, an integration surface, a public read-only Watchtower, and a local-friendly operator workflow.

It is being built with Codex during OpenAI Build Week. The project is designed to make Codex-enabled and other autonomous workflows safer to operate; it does not claim that Watchtower controls a model provider itself.

### How Codex and GPT-5.6 accelerated the work

| Build Week criterion | Repository evidence |
| --- | --- |
| Non-trivial working implementation | Worker, Durable Objects, D1, R2, Queue/DLQ, REST, WebSocket, static Watchtower, tests, and a local demo path. |
| Coherent product experience | Public Watchtower room/agent/feed view plus the reserved operator/member surface. |
| Specific problem and audience | Developers and teams supervising autonomous runs that can recurse, duplicate work, fail quietly, or spend beyond expectations. |
| Novel idea | An observability/control plane where evidence is presented as a compact agent-ops sitcom without fabricating operational state. |
| How Codex accelerated the work | Codex was used to consolidate the repository, wire and test the Worker surfaces, shape domain boundaries, build the camera-style Watchtower, and document the operational lifecycle. |
| How GPT-5.6 was used | GPT-5.6 assisted with code review, debugging complex TypeScript type errors, generating test scenarios for guardrail edge cases, and refining documentation clarity. GPT-5.6 was particularly helpful in identifying type safety issues in the Durable Object stub definitions and suggesting more ergonomic API patterns for the lifecycle client. |

**Codex `/feedback` Session ID:** `019f6d08-6448-7d50-ad6d-8d92bde8c5f3`

See [the submission notes](docs/review/OPENAI_SUBMISSION_NOTES.md) and [the three-minute demo plan](docs/review/OPENAI_SUBMISSION_VIDEO_SCRIPT.md) for the complete model-use narrative.

## What is working now

- A Cloudflare Worker backed by Durable Objects, D1, R2, and an alert Queue/DLQ.
- Public, read-only room, roster, agent-detail, event-feed, and WebSocket observation surfaces.
- Administrative project/agent registration and heartbeat/status routes.
- Signed, idempotent operational event ingress with timestamp/replay checks and secret-shaped metadata redaction.
- Runtime-neutral liveness: a signed `heartbeat` event can arrive from an agent package, CI runner, webhook adapter, or MCP/REST integration; no persistent WebSocket connection is required for an agent to remain present.
- Guardrail decisions for duplicate/runaway chains, validation failures, budgets, cooperative leases, controlled tool authorization, and heartbeat expiry/watchdog incidents.
- Hash-chained audit decisions, incident records, bounded evidence exports, and an embeddable dependency-free JavaScript widget.
- A standard-library Loop Enforcer adapter that treats a denied lease, gate, or controlled-tool decision as a stop result (`exit 3`).

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

## Codex workflow

Codex was used to consolidate the project into a deployable repository, wire the Cloudflare Worker and storage bindings, create the public host routing, build the embed-ready widget, align the canonical branding pipeline, repair the agent integration script, and produce the repository documentation and setup flow.

| Task | Codex contribution |
| --- | --- |
| **Repository consolidation** | Merged five project demos into one functional, manageable codebase |
| **Worker surface wiring** | Configured Durable Objects, D1, R2, Queue/DLQ bindings in wrangler.toml |
| **Public host routing** | Isolated API routes from static Watchtower host (`watch` vs `fapi` vs `federation`) |
| **Embed-ready widget** | Built dependency-free JavaScript widget with deterministic SVG avatars |
| **Branding pipeline** | Aligned canonical SVG branding, theme tokens, splash screen across all surfaces |
| **Agent integration** | Repaired agent script to properly connect, heartbeat, emit, disconnect |
| **Documentation** | Produced operational lifecycle docs, setup flow, testing guides, submission materials |

Codex saw the vision, made it feasible, and brought it to life. From burning 25,000 credits to having a functional, deployable system — the difference is having faith in the ideas and the discipline to build them properly.

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
git clone https://github.com/YOUR_USERNAME/federation.git
cd federation

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
✅ Unit tests: 24/24 PASS
✅ SDK tests: 8/8 PASS
✅ JavaScript syntax: PASS
✅ Git diff: CLEAN
```

### 🔧 Option C: Test Alert Webhooks (Advanced)

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

## Our story

### What inspired us

This began with a costly and familiar failure mode: while building another hackathon project, autonomous coding work repeatedly scaffolded projects with very little visible progress. Roughly **25,000 credits** disappeared before there was a clear, shared answer to four basic questions:

1. What is currently running?
2. What is it trying to do repeatedly?
3. What is it costing, failing, or waiting on?
4. What should stop before the next side effect?

Normal logs can contain the evidence but are hard to monitor during a fast, multi-agent build. We needed an observable runtime surface where a human can see a real agent's presence and event trail, while the system can record a validation denial, budget warning, duplicate/runaway signal, or missed heartbeat that an agent is expected to honor.

The colorful TV presentation is intentionally a hook, not a substitute for controls. A sparse, labelled ambient cameo may appear in an empty public room; it is never an agent, an event, or audit evidence.

### What we learned

Building Federation Watchtower taught us several critical lessons about autonomous agent operations:

- **Visibility is prevention** - Most runaway costs come from work that becomes invisible. Making agent presence and events readable in real time prevents expensive failure modes before they compound.
- **Evidence must be immutable** - Operational truth requires hash-chained audit records, idempotency keys, and durable event storage that cannot be retroactively modified.
- **Presentation ≠ fabrication** - Theatrical UI can make operations watchable without inventing state. Color and animation assist recognition but never substitute for real lifecycle text.
- **Credential boundaries matter** - Keeping owner/agent credentials scoped and separate from administrative secrets prevents privilege escalation and accidental exposure.
- **Watchdogs need teeth** - A missed heartbeat must have consequences: lifecycle state transitions, public scene removal, and credential invalidation.

### How we built it

Federation Watchtower combines a Cloudflare Worker control plane with Durable Objects for stateful coordination:

**Backend architecture:**
- Cloudflare Worker with D1 database, R2 storage, and Queue/DLQ for alert delivery
- Durable Objects for agent registry, watchdog deadlines, guardrail decisions, and room scene coordination
- Canonical lifecycle API with owner-scoped credentials and per-agent scoped tokens
- Signed, idempotent event ingestion with HMAC verification and replay protection

**Frontend presentation:**
- Static HTML/CSS/JavaScript Watchtower at `watch.drdeeks.xyz`
- Embeddable browser widget with procedural sprite generation
- Real-time WebSocket feed for event updates
- Consistent navigation across 9 HTML pages

**Development process with Codex:**
- Codex consolidated the repository structure and domain boundaries
- Wired and tested Worker surfaces (REST routes, WebSocket handlers, Durable Object stubs)
- Built the camera-style Watchtower UI with proper proportions and accessibility
- Documented the operational lifecycle and submission requirements
- Generated TypeScript types and validated all test suites

### Challenges we faced

**Dual registry split** - The system initially had two agent registries: the legacy `agents` table and the new canonical `federation_agents` lifecycle tables. Resolving this required making the canonical lifecycle API the only write path while keeping legacy GET routes for backward compatibility.

**Navigation consistency** - Nine HTML pages had evolved with inconsistent navigation structures, mixing absolute and relative URLs. Standardizing all pages to use the same 8-link navigation structure required careful editing to maintain proper `aria-current` states and relative path conventions.

**Watch page UI alignment** - The original watch page had toggle buttons ("Reduced motion" and "Feed only") that were misaligned and proportionally incorrect. Removing these controls while preserving system-level accessibility features (`prefers-reduced-motion`) required careful CSS cleanup.

**OpenAI Build Week compliance** - Ensuring all documentation aligns with hackathon rules required mapping every requirement (video <3 min, English language, Codex collaboration documentation, testing instructions) to repository evidence and identifying outstanding user-owned deliverables.

**Credential security** - Keeping administrative secrets (`WATCHTOWER_ADMIN_TOKEN`, `WATCHTOWER_INGESTION_SECRET`) separate from owner/agent scoped credentials while providing clear onboarding paths required careful API design and documentation boundaries.

## For Judges / Testing Instructions

### 🎯 Quickest Path to See It Working (90 seconds)

**No installation required** — everything is live and cloud-hosted:

1. **Open** [watch.drdeeks.xyz](https://watch.drdeeks.xyz) - see the public Watchtower
2. **Open** [onboarding.html](https://federation.drdeeks.xyz/onboarding.html) in another tab
3. **Create owner**: Click "Create owner" → Owner ID: `judge-demo` → Click button
4. **Register agent**: Scroll down → Agent ID: `judge-agent-1` → Check "Show on Watchtower" → Click "Register agent"
5. **Run live loop**: Click "Connect" → "Heartbeat" → "Emit action now" → "Disconnect"
6. **Return to Watchtower**: Your agent appears in the roster, events appear in the feed

**What you're seeing:**
- Real agent presence with heartbeats and watchdog deadlines
- Operational events (lifecycle, validation, guardrail decisions)
- Public projection of agent identity and event history
- No fabricated state - everything comes from real API calls

### 🧪 Automated Testing (single command)

```bash
# Clone and install
git clone https://github.com/drdeeks/federation-watchtower
cd federation-watchtower/source/federation-serverless
npm install

# Return to the repository root — the test scripts live in ./scripts there
cd ../..

# Run all local tests (TypeScript, unit, syntax, git)
./scripts/local-test-runner.sh

# Run E2E lifecycle test (success path)
./scripts/e2e-agent-lifecycle.sh

# Run guardrail failure scenarios
./scripts/test-guardrail-failures.sh

# Validate all API paths respond correctly
./scripts/validate-api-paths.sh
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
npm run migrate:watchtower
npm run migrate:control-loop
npm run migrate:access-gateway
npm run migrate:lifecycle
npm run migrate:management
npm run migrate:alert-sink
```

See [DEPLOY.md](DEPLOY.md) for complete deployment guide.

### 🔧 Supported Platforms

- **Runtime:** Cloudflare Workers (edge)
- **Browser:** Any modern browser (Chrome, Firefox, Safari, Edge)
- **API:** REST, WebSocket, MCP
- **SDK:** Node.js 20+ (`@federation-watchtower/sdk` on npm)

### 🔑 Test Credentials

For judge testing, use these disposable credentials:

```
Owner ID: judge-demo
Agent ID: judge-agent-{random}
Project ID: judge-project
```

No authentication required for public Watchtower or onboarding. Admin console requires `WATCHTOWER_ADMIN_TOKEN` (available on request).

Federation Watchtower fits the Developer Tools track because it provides:

- **Testing & DevOps visibility** - See what autonomous agents are doing in real time
- **Agentic workflow controls** - Guardrails, validation gates, lease management
- **Security & monitoring** - Audit trails, incident tracking, budget guardrails
- **Developer experience** - Public observability, SDK integration, MCP support

## Documentation

- [**AGENTS.md**](AGENTS.md) - Operational guide for people and coding agents working in this repository
- [**TESTING_GUIDE.md**](TESTING_GUIDE.md) - Complete testing documentation with automated scripts
- [**System Specification**](docs/review/FEDERATION_SYSTEM_SPEC.md) - Expanded product context and technical details
- [**Access and Onboarding**](docs/review/ACCESS_AND_ONBOARDING.md) - Agent, owner, organization, and administrator boundaries
- [**Host Surface Contract**](docs/review/HOST_SURFACE_CONTRACT.md) - Current domain boundaries and explicit gaps
- [**Submission Runbook**](docs/review/SUBMISSION_RUNBOOK.md) - Complete submission checklist and deployment guide
- [**Video Script**](VIDEO_RECORDING_GUIDE.md) - Three-minute demo plan

## License

MIT. See [LICENSE](LICENSE).

---

**Built with Codex and GPT-5.6 during OpenAI Build Week 2026**

**Codex `/feedback` Session ID:** `019f6d08-6448-7d50-ad6d-8d92bde8c5f3`
