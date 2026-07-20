# Federation Watchtower — Submission Runbook

Use this exact order. Do not publish credentials, raw signed requests, `.dev.vars`,
or private production evidence.

## 1. Release the reviewed build

From `source/federation-serverless/`:

```bash
# Step 1: Verify build
npm run types
npm test

# Step 2: Deploy worker (code only - migrations NOT auto-applied)
npx wrangler deploy
```

⚠️ **CRITICAL: Apply migrations manually AFTER deploy**

```bash
# Run these 6 migrations IN ORDER (deploys code, then you migrate DB):
npm run migrate:watchtower      # 0001: Core tables
npm run migrate:control-loop    # 0002: Watchdog, audit
npm run migrate:access-gateway  # 0003: Owners, credentials
npm run migrate:lifecycle       # 0004: Lifecycle events
npm run migrate:management      # 0005: Admin management
npm run migrate:alert-sink      # 0006: Alert receipts

# Or one-liner:
for m in src/migrations/*.sql; do wrangler d1 execute federation-db --remote --file="$m"; done
```

Then confirm all three public surfaces:

```text
https://watch.drdeeks.xyz/
https://fapi.drdeeks.xyz/health
https://federation.drdeeks.xyz/
```

Test the full lifecycle: register/connect a disposable public agent, send
`run.started`, and refresh the Watchtower room. The agent must appear at a
scene position; watchdog expiry must transition it offline. The browser may
show `AMBIENT` only with the exact label `ambient presentation · no event`.

**Test admin management** (new for CL-0025):

```text
https://federation.drdeeks.xyz/manage.html
```

Enter admin token, verify: agent pause/resume/revoke, room create/delete,
organization review/approve/reject, alert receipt viewing, evidence export.

## 2. Commit and publish source

Review `git status`, keep `.dev.vars` ignored, and do not add art whose license
has not been recorded. Commit the Worker, public widget, generated Worker types,
room-scene contract, and submission documents. Push the branch that contains
the deployed commit, then use that repository URL in Devpost.

## 2a. Verify the published npm package

The first package is now published as `@federation-watchtower/sdk` version
`0.1.0`. Verify the public artifact from the package directory:

```bash
cd packages/watchtower-sdk
npm test
npm run pack:check
npm view @federation-watchtower/sdk version
```

The package has public scoped access configured. For future versions, publish
from a clean reviewed commit with npm 2FA enabled. Do not publish from a
machine containing `.dev.vars`, and never put a Worker secret or production
credential in the package.

## 3. Record one real public demo — under three minutes

**Required elements per OpenAI Build Week:**
- ✅ Watchtower camera view
- ✅ Agent registration flow
- ✅ Event feed showing real events
- ✅ Guardrail/watchdog signals (validation failure or offline transition)
- ✅ Codex/GPT-5.6 build workflow explanation

Follow [the demo script](VIDEO_RECORDING_GUIDE.md), with this order:

1. **Intro (15s):** Open `watch.drdeeks.xyz`, state what Federation Watchtower is
2. **Problem (15s):** Explain the 25,000 credits invisibility problem
3. **Live demo (60s):** Register owner → register agent with lease → connect → heartbeat → emit `run.started` → **show watchdog expiry or validation failure** → disconnect
4. **Watchtower (20s):** Show agent live on public camera view, event feed with real events
5. **Admin console (45s):** Open `manage.html`, show agent management, room create/delete, org review/approve
6. **Codex usage (25s):** Show README, explain how Codex + GPT-5.6 accelerated the work
7. **Wrap up (10s):** Call to action

Upload the recording publicly to YouTube (unlisted is OK for hackathon submission).

**Title:** `Federation Watchtower - OpenAI Build Week Demo`  
**Description:** Mention Codex session ID `019f6d08-6448-7d50-ad6d-8d92bde8c5f3`

## 4. Complete the Devpost form manually

- **Project:** Federation Watchtower (ID: `1346118`)
- **Challenge:** Attach to **OpenAI Build Week** (required for submission)
- **Category:** Developer Tools
- **Repository:** Your GitHub fork URL
- **Video:** Public YouTube URL from Step 3
- **Submitter type:** Individual
- **Country:** Your country of residence
- **Codex session ID:** `019f6d08-6448-7d50-ad6d-8d92bde8c5f3`
- **Demo instructions:** Judges can visit `watch.drdeeks.xyz` (public) and test
  agent registration at `federation.drdeeks.xyz/onboarding.html`. Admin features
  at `manage.html` require `WATCHTOWER_ADMIN_TOKEN` (provide on request).
- **Description:** Use [OPENAI_SUBMISSION_NOTES.md](OPENAI_SUBMISSION_NOTES.md),
  revised to match deployed build. Mention: admin management (agents/rooms/orgs),
  signed event ingestion, watchdog expiry, alert webhooks, camera-style UI.

## 5. Final truth check

Before pressing Submit, verify each claim says either **implemented** or
**planned** correctly:

**Implemented (can claim):**
- ✅ Owner/agent lifecycle with scoped credentials
- ✅ Lease authentication (agents prove identity with `fw_agent_`)
- ✅ Auto-lease registration option
- ✅ Admin management: agents (pause/resume/revoke), rooms (create/delete empty), orgs (review/approve/reject/suspend)
- ✅ Signed event ingestion with HMAC
- ✅ Watchdog expiry and offline transitions
- ✅ Alert webhooks with receipts (Slack/Discord/json formats)
- ✅ Evidence exports to R2
- ✅ Camera-style Watchtower UI (35-agent capacity)
- ✅ Procedural sprite generation
- ✅ Reduced-motion and feed-only modes
- ✅ MCP server and published npm SDK (`@federation-watchtower/sdk@0.1.0`)

**Not implemented (do NOT claim):**
- ❌ Payments, subscriptions, x402 settlement
- ❌ Statement moderation queue
- ❌ Per-organization webhook configuration
- ❌ Reviewer RBAC UI (org approval is admin-only)
- ❌ Unix socket CLI
- ❌ Mirror rooms and relief crews

The only remaining human-only work: video recording, Devpost form fields,
and pressing Submit.

**Deadline:** July 21, 2026 @ 5:00pm PDT
