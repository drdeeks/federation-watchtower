# Federation Watchtower — Hackathon Video Script

**Target:** < 3 minutes, public YouTube, with audio
**Category:** Developer Tools

## Pre-recording checklist

- [ ] Open 3 browser tabs:
  1. Terminal (for running demo script)
  2. [watch.drdeeks.xyz](https://watch.drdeeks.xyz) (public Watchtower)
  3. Slack channel (to catch webhook alert)
- [ ] Ensure Slack webhook is live:
  - `WATCHTOWER_ALERT_WEBHOOK_URL` = your Slack webhook
  - `WATCHTOWER_ALERT_WEBHOOK_FORMAT` = `slack`
- [ ] `scripts/demo-autonomous-agent.sh` ready
- [ ] Close unrelated tabs, mute notifications
- [ ] Recording tool: OBS / QuickTime / Loom — 1080p, system + mic audio

---

## 0:00 – 0:20 — The problem (origin story)

**Screen:** Terminal, maybe a quick shot of the repo

> "An autonomous build I was running consumed 25,000 credits across repeated
> scaffolding loops before I even had a clear view of what was happening or a
> way to stop it. That's how Federation Watchtower started."

## 0:20 – 0:45 — What is this + Codex/GPT-5.6

**Screen:** Watchtower public page, then quick repo scroll

> "Watchtower is a runtime-neutral observability and safety layer for
> autonomous agents. I built it with Codex and GPT-5.6. Codex handled the
> heavy architecture — Cloudflare Workers, Durable Objects, the guardrail
> engine, HMAC-signed event ingestion, the cooperative lease system. GPT-5.6
> was my pair programmer for the product decisions: the canonical lifecycle
> model, the audit trail, the alert pipeline. I directed what to build and
> what mattered. They executed at scale."

## 0:45 – 2:00 — Live demo: the full flow

**Screen:** Terminal — run the demo script

```bash
./scripts/demo-autonomous-agent.sh
```

Switch between terminal, Watchtower, and Slack as events fire.

> "Let me show you the full flow. I'm running an autonomous agent demo right now."

**Phase 1 — Agent registers and connects**

> "Agent registers with a canonical manifest — identity, capabilities,
> heartbeat config. Gets a scoped credential. Connects to Federation."

**Phase 2–3 — Work events flowing**

> "Heartbeat loop running. Agent starts a build task. Events flowing in — run
> started, config updated, tests executing. Watchtower sees everything."

**Phase 4 — Guardrail triggers (key moment)**

> "Validation fails. Agent retries. Fails again. Retries. Fails a third time..."

*[Switch to terminal — show guardrail response with incidents + alerts]*

> "Guardrail fires. Three validation failures in the window — runaway
> detected. Incident created. Control command issued."

*[Switch to Slack — show the webhook alert arriving]*

> "Slack alert, delivered in real time. The operator knows immediately. Not
> from a dashboard they happen to check — the system pushed it to them."

*[Switch to Watchtower — show agent state change]*

> "On the Watchtower, you can see the agent's state change. Deploy attempt
> blocked by the guardrail."

**Phase 5 — Recovery**

> "Agent finds the root cause, fixes it, validation passes. Build completes
> successfully."

**Phase 6 — Watchdog (compressed)**

> "Heartbeat stops. Watchdog fires, marks the agent offline."

*(Note: if the 35s wait is too long, cut to the terminal showing "Agent
should now be OFFLINE" then reconnect.)*

**Phase 7 — Clean reconnect**

> "Agent reconnects, sends final status, disconnects cleanly. Full lifecycle,
> fully observable."

## 2:00 – 2:30 — Why it matters

**Screen:** Watchtower public page + operator console quick shot

> "This isn't another agent framework. Watchtower never touches your agent's
> runtime. Deterministic guardrails catch runaway loops, duplicate chains,
> budget overruns, and missed heartbeats. HMAC-signed events. Immutable audit
> trail. Real-time alerts to Slack, Discord, or any webhook. And a public
> Watchtower that makes it actually watchable."

## 2:30 – 3:00 — Close

**Screen:** Watchtower homepage or project repo

> "Federation Watchtower. Built with Codex and GPT-5.6. Code is on GitHub.
> Live at watch.drdeeks.xyz. Thanks for watching."

---

## Post-recording — Devpost submission checklist

- [ ] Upload to YouTube as **PUBLIC**
- [ ] Title: "Federation Watchtower — Autonomous Agent Observability & Safety"
- [ ] Paste YouTube link into Devpost submission form
- [ ] Category: Developer Tools
- [ ] `/feedback` Codex Session ID (from your actual Codex session)
- [ ] Repository URL (public or shared with testing@devpost.com)
- [ ] Submitter type, country of residence
- [ ] Attach project to OpenAI Build Week challenge
- [ ] Press final submission

> **Reminder:** never place production secrets in the README, video,
> repository, or public Devpost description.
