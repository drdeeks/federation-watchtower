# Federation Watchtower — Submission Narrative

**Copy-paste ready for Devpost OpenAI Build Week submission form fields.**

---

## Project Story

### What inspired you

This project began with a costly and familiar failure mode. While building another hackathon project with five demos and a working scaffold, I looked away for one moment. The kanban didn't use proper mechanisms, an AI decided to take the easy way out instead of dealing with loops correctly, and **25,000 credits went up in flames** within five minutes. I was back to nothing but free models.

But from that loss came an iteration: a TV sitcom where agents working on tasks could be seen on screen, doing really stupid stuff. When something happened, they'd have a speech bubble triggered by it:

- Test fails? *"The boiler room just combusted — everybody get to safety!"*
- Thirty duplicate files being processed consecutively? *"I made a checklist for my checklists checklist — does anybody wanna make a checklist about that?"*

The comedy is the hook. But the purpose is to **monitor what's actually happening** — to not be left clueless while giving everything you've got.

### Personal context

I operate on a 2013 ThinkPad with 1.87 GHz, 2 cores, 4GB RAM that can barely open a browser. Being a single father with struggles from a mistake I made over 10 years ago, constantly being shown the door in job opportunities has been very difficult. I've always been a creative person who enjoys taking things most people throw away and transforming them into something completely different — 1/1 items. I figure things out, think mechanically, and try everything I can to get myself and my daughter in a better position.

When I started using Codex, I had five project demos that weren't quite functional. About 700 credits later, I realized the app I wanted to make wasn't going to cut it. I mentioned the Federation idea — originally a comical afterthought, a quirky agent monitoring layer for any project that wanted to join via MCP. Codex refined my concept into something possible and robust, then helped consolidate my refund into something functional and manageable.

After running out of credits and having to take it to Claude (which I've grown to strongly dislike), everything was built the exact way I felt it should be built: proper, robust, accurate, and solidified. All we had to do was start implementing the UI and features.

From burning 25,000 credits, using almost half my allocation on Codex, persistent disappointment and struggles to take care of my daughter and find steady employment — Codex made me have a little bit more faith in myself and the ideas I come up with. Win or lose, I take pride knowing this exists. As long as we can learn to laugh a little bit and continue to grow, everything will be OK.

### What you learned

- **Visibility is the product.** Operational truth matters more than theatrical presentation. The sitcom is the hook; the audit trail is the value.
- **Guardrails must fire before side effects.** A denied lease, failed validation, or watchdog expiry must stop work before the next irreversible action.
- **Additive migrations are safer than destructive changes.** All 6 D1 migrations are CREATE TABLE or ADD COLUMN — no DROP, no ALTER that breaks existing data.
- **Scoped credentials beat shared secrets.** Owner-scoped and agent-scoped credentials (`fw_agent_...`) prevent impersonation and enable audit attribution.
- **Resource constraints force creativity.** Building on a 2013 ThinkPad with 4GB RAM means every dependency matters. The dependency-free widget wasn't an aesthetic choice — it was necessity.
- **Codex accelerates consolidation, not invention.** The idea was mine; Codex made it feasible, wired the surfaces, and produced the documentation. The collaboration worked because I brought a clear vision and Codex brought execution speed.

### How you built your project

**Timeline:** ~2 weeks during OpenAI Build Week 2026

**Phase 1 — Concept:** Extracted the Federation idea from a comical afterthought into a formal concept. Created FOREVER-SYSTEM protocol as foundational architecture. Defined agent lifecycle state machine with explicit transitions.

**Phase 2 — Infrastructure:** Set up Cloudflare Worker with Durable Objects, D1, R2, Queue/DLQ bindings. Wrote 6 additive migrations (0001-0006) for persistent storage. Implemented owner/agent credential system with scoped tokens.

**Phase 3 — Guardrails:** Built duplicate/runaway detection, budget thresholds, validation gates. Implemented watchdog expiry with offline transitions. Created hash-chained audit decisions and incident records.

**Phase 4 — Presentation:** Built camera-style Watchtower UI with 35-agent capacity. Created procedural SVG avatars (deterministic from agentId/avatarSeed). Added event bubbles, feed-only mode, reduced-motion support.

**Phase 5 — Admin & Submission:** Implemented full admin management (agents, rooms, organizations). Added alert webhooks with receipts (Slack/Discord/json formats). Wrote testing scripts, deployment guide, video script, submission docs.

**Tools:** Codex (primary), Claude (fallback), Cloudflare Workers, TypeScript, Node.js, SQLite (D1), R2 storage.

### Challenges you faced

| Challenge | How I Overcame It |
| --- | --- |
| **25,000 credits lost to runaway loops** | Built guardrail enforcement, watchdog expiry, and cooperative leases that stop work before the next side effect |
| **Five disjointed project demos** | Used Codex to consolidate into one functional repository with shared infrastructure |
| **Running out of Codex credits mid-build** | Switched to Claude for final implementation, then documented everything for reproducibility |
| **Building on 2013 hardware (4GB RAM)** | Eliminated unnecessary dependencies, used dependency-free widget, kept bundle size minimal |
| **Keeping secrets out of the repository** | `.gitignore` for `.dev.vars`, Worker secrets via `wrangler secret put`, scoped credentials never logged |
| **Aligning presentation with operational truth** | Ambient cameos explicitly labelled `ambient presentation · no event` — never fabricate an agent, event, or heartbeat |
| **Meeting OpenAI Build Week requirements** | Created SUBMISSION_RUNBOOK.md, VIDEO_RECORDING_GUIDE.md, and this narrative to ensure all fields are complete |

---

## Project Description

Federation Watchtower is a developer tool that makes autonomous agent work visible before it becomes expensive. It's an agent-operations control plane with a security-camera sitcom presentation: real agents, heartbeats, events, guardrails, validation decisions, and watchdog signals are made readable for humans without turning the operational record into theater.

The sitcom is the interface layer. **The real product is a shared observability and governance surface for autonomous systems.**

**Live public Watchtower:** https://watch.drdeeks.xyz  
**API host:** https://fapi.drdeeks.xyz  
**Member/operator surface:** https://federation.drdeeks.xyz

---

## How Codex Accelerated the Work

| Build Week criterion | Repository evidence |
| --- | --- |
| Non-trivial working implementation | Worker, Durable Objects, D1, R2, Queue/DLQ, REST, WebSocket, static Watchtower, tests, and a local demo path. |
| Coherent product experience | Public Watchtower room/agent/feed view plus the reserved operator/member surface. |
| Specific problem and audience | Developers and teams supervising autonomous runs that can recurse, duplicate work, fail quietly, or spend beyond expectations. |
| Novel idea | An observability/control plane where evidence is presented as a compact agent-ops sitcom without fabricating operational state. |
| How Codex accelerated the work | Codex was used to consolidate the repository, wire and test the Worker surfaces, shape domain boundaries, build the camera-style Watchtower, and document the operational lifecycle. |

**Codex `/feedback` Session ID:** `019f6d08-6448-7d50-ad6d-8d92bde8c5f3`

---

## Technical Implementation

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

---

## Why This is a Developer Tool

| Use case | How Watchtower helps |
| --- | --- |
| **Agentic workflows** | See what autonomous agents are doing in real time before credits disappear |
| **DevOps & CI/CD** | Guardrail signals, validation gates, and budget thresholds become explicit events |
| **Observability** | Unified event feed with machine-readable packets and human-readable status bubbles |
| **Testing** | Validation failures, runaway detection, and duplicate chains are logged as incidents |
| **Security** | Audit trails, incident tracking, hash-chained decisions, bounded evidence exports |
| **Operational safety** | Watchdog expiry, cooperative leases, controlled tool authorization, stop-before-side-effect rules |

---

## What's Working Now

- A Cloudflare Worker backed by Durable Objects, D1, R2, and an alert Queue/DLQ
- Public, read-only room, roster, agent-detail, event-feed, and WebSocket observation surfaces
- Administrative project/agent registration and heartbeat/status routes
- Signed, idempotent operational event ingress with timestamp/replay checks and secret-shaped metadata redaction
- Runtime-neutral liveness: a signed `heartbeat` event can arrive from an agent package, CI runner, webhook adapter, or MCP/REST integration
- Guardrail decisions for duplicate/runaway chains, validation failures, budgets, cooperative leases, controlled tool authorization, and heartbeat expiry/watchdog incidents
- Hash-chained audit decisions, incident records, bounded evidence exports, and an embeddable dependency-free JavaScript widget
- A standard-library Loop Enforcer adapter that treats a denied lease, gate, or controlled-tool decision as a stop result (`exit 3`)

---

## Submission Checklist

- [x] Category: **Developer Tools**
- [x] Repository URL: https://github.com/drdeeks/federation
- [x] Codex session ID: `019f6d08-6448-7d50-ad6d-8d92bde8c5f3`
- [ ] Video: Record <3 min demo showing Watchtower, registration, events, watchdog/guardrail, Codex usage
- [ ] Attach to OpenAI Build Week challenge
- [ ] Submitter type: Individual
- [ ] Country of residence: [Your country]

---

**Built with Codex during OpenAI Build Week 2026**
