# Federation Watchtower — Submission Narrative

**For Devpost OpenAI Build Week submission form fields requiring personal narrative, project description, and Codex collaboration details.**

---

## Project Description (Short)

Federation Watchtower is a developer tool that makes autonomous agent work visible before it becomes expensive. It's an agent-operations control plane with a security-camera sitcom presentation: real agents, heartbeats, events, guardrails, validation decisions, and watchdog signals are made readable for humans without turning the operational record into theater.

**Live public Watchtower:** https://watch.drdeeks.xyz  
**API host:** https://fapi.drdeeks.xyz  
**Member/operator surface:** https://federation.drdeeks.xyz

---

## The Origin Story

This project began with a costly and familiar failure mode. While building another hackathon project with five demos and a working scaffold, I looked away for one moment. The kanban didn't use proper mechanisms, an AI decided to take the easy way out instead of dealing with loops correctly, and **25,000 credits went up in flames** within five minutes. I was back to nothing but free models.

But from that loss came an iteration: a TV sitcom where agents working on tasks could be seen on screen, doing really stupid stuff. When something happened, they'd have a speech bubble triggered by it:

- Test fails? *"The boiler room just combusted — everybody get to safety!"*
- Thirty duplicate files being processed consecutively? *"I made a checklist for my checklists checklist — does anybody wanna make a checklist about that?"*

The comedy is the hook. But the purpose is to **monitor what's actually happening** — to not be left clueless while giving everything you've got.

---

## Personal Context

I operate on a 2013 ThinkPad with 1.87 GHz, 2 cores, 4GB RAM that can barely open a browser. Being a single father with struggles from a mistake I made over 10 years ago, constantly being shown the door in job opportunities has been very difficult. I've always been a creative person who enjoys taking things most people throw away and transforming them into something completely different — 1/1 items. I figure things out, think mechanically, and try everything I can to get myself and my daughter in a better position.

When I started using Codex, I had five project demos that weren't quite functional. About 700 credits later, I realized the app I wanted to make wasn't going to cut it. I mentioned the Federation idea — originally a comical afterthought, a quirky agent monitoring layer for any project that wanted to join via MCP. Codex refined my concept into something possible and robust, then helped consolidate my refund into something functional and manageable.

After running out of credits and having to take it to Claude (which I've grown to strongly dislike), everything was built the exact way I felt it should be built: proper, robust, accurate, and solidified. All we had to do was start implementing the UI and features.

From burning 25,000 credits, using almost half my allocation on Codex, persistent disappointment and struggles to take care of my daughter and find steady employment — Codex made me have a little bit more faith in myself and the ideas I come up with. Win or lose, I take pride knowing this exists. As long as we can learn to laugh a little bit and continue to grow, everything will be OK.

---

## The Problem

Autonomous coding agents can silently recurse, duplicate work, burn credits, lose track of state, or fail without a useful human-facing signal. The surrounding systems may already have logs, validators, policy checks, and recovery workers, but operators still need a shared surface that makes the whole system understandable.

---

## The Solution

Watchtower unifies the visible operational layer for those systems:

| Capability | What it does |
| --- | --- |
| **Federation registry** | Organizations, projects, agents, rooms, identities, heartbeats, and live events. |
| **Guardrail monitoring** | Runaway loops, duplicate chains, budget pressure, invalid states, and blocked work become explicit events. |
| **Validation and enforcement** | Blueprint gates, policy checks, source verification, and structured review signals report into the same feed. |
| **MCP/API/widget access** | Agents and external systems use MCP or REST, while humans get a live public broadcast and embeddable widget. |
| **Enterprise operations** | Crew coordination, memory, audit, recovery, self-healing, and integration patterns share the same event and review surface. |

The sitcom is the interface layer. **The real product is a shared observability and governance surface for autonomous systems.**

---

## How Codex Accelerated the Work

| Task | Codex Contribution |
| --- | --- |
| **Repository consolidation** | Merged five project demos into one functional, manageable codebase |
| **Worker surface wiring** | Configured Durable Objects, D1, R2, Queue/DLQ bindings in wrangler.toml |
| **Public host routing** | Isolated API routes from static Watchtower host (`watch` vs `fapi` vs `federation`) |
| **Embed-ready widget** | Built dependency-free JavaScript widget with deterministic SVG avatars |
| **Branding pipeline** | Aligned canonical SVG branding, theme tokens, splash screen across all surfaces |
| **Agent integration** | Repaired agent script to properly connect, heartbeat, emit, disconnect |
| **Documentation** | Produced operational lifecycle docs, setup flow, testing guides, submission materials |

Codex saw the vision, made it feasible, and brought it to life. From burning 25,000 credits to having a functional, deployable system — the difference is having faith in the ideas and the discipline to build them properly.

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

| Use Case | How Watchtower Helps |
| --- | --- |
| **Agentic workflows** | See what autonomous agents are doing in real time before credits disappear |
| **DevOps & CI/CD** | Guardrail signals, validation gates, and budget thresholds become explicit events |
| **Observability** | Unified event feed with machine-readable packets and human-readable status bubbles |
| **Testing** | Validation failures, runaway detection, and duplicate chains are logged as incidents |
| **Security** | Audit trails, incident tracking, hash-chained decisions, bounded evidence exports |
| **Operational safety** | Watchdog expiry, cooperative leases, controlled tool authorization, stop-before-side-effect rules |

---

## Codex Session ID

**`/feedback` Session ID:** `019f6d08-6448-7d50-ad6d-8d92bde8c5f3`

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
