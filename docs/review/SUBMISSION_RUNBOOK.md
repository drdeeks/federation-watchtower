# Federation Watchtower — Submission Runbook

Use this exact order. Do not publish credentials, raw signed requests, `.dev.vars`,
or private production evidence.

## 1. Release the reviewed build

From `source/federation-serverless/`:

```bash
npm run types
npm test
npx wrangler deploy
```

Then confirm all three public surfaces:

```text
https://watch.drdeeks.xyz/
https://fapi.drdeeks.xyz/health
https://federation.drdeeks.xyz/
```

For this room-scene release, register or reconnect one disposable public agent,
send `run.started`, and refresh the selected Watchtower room. The agent must
appear at a supplied scene position; a watchdog expiry must transition it
offline. The browser may show `AMBIENT` only with the exact label
`ambient choreography · no operational event`.

## 2. Commit and publish source

Review `git status`, keep `.dev.vars` ignored, and do not add art whose license
has not been recorded. Commit the Worker, public widget, generated Worker types,
room-scene contract, and submission documents. Push the branch that contains
the deployed commit, then use that repository URL in Devpost.

## 3. Record one real public demo — under three minutes

Follow [the demo script](OPENAI_SUBMISSION_VIDEO_SCRIPT.md), updated with this
order of proof:

1. Open `watch.drdeeks.xyz` and select one room.
2. Register/connect a disposable public agent through the API or package.
3. Send a real `run.started` event and show its sourced room movement/log.
4. Trigger a validation failure or watchdog expiry and show the alert/offline
   state plus its underlying feed/evidence.
5. Point out an `AMBIENT` label only if it appears; never call it agent work.
6. State accurately how Codex and GPT-5.6 were used.

Upload the recording publicly to YouTube. Do not use an unlisted/private video
if the event requires a public link.

## 4. Complete the Devpost form manually

- Select **Developer Tools**.
- Attach the existing Federation Watchtower project to **OpenAI Build Week**;
  publishing the standalone project alone is not submission.
- Add the public repository URL and public YouTube link.
- Use the project description in [OPENAI_SUBMISSION_NOTES.md](OPENAI_SUBMISSION_NOTES.md),
  revising claims to match the deployed build.
- State submitter type, country/residence, and any team information truthfully.
- Add the Codex `/feedback` session ID from the session containing the primary
  implementation work. Do not invent an ID.
- Supply only public judge instructions. If a private repository is used, share
  it with the two event-required review addresses listed in
  [OPENAI_BUILD_WEEK_READINESS.md](OPENAI_BUILD_WEEK_READINESS.md).

## 5. Final truth check

Before pressing Submit, verify each claim says either **implemented** or
**planned** correctly. In particular, do not claim that payments, subscription
tier enforcement, reviewer RBAC, private rooms, per-organization webhook
configuration, public statement moderation, or complete sprite-asset use are
live.

The only remaining human-only work is license confirmation for optional art,
the video, Devpost identity/form fields, `/feedback` session ID, and pressing
the submission action.
