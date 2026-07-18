# Federation Watchtower — two-and-a-half-minute control-loop demo

This is a recording plan, not a mock. It uses the deployed Worker or a local
Worker with the same ignored `.dev.vars` credentials. Keep tokens, raw signed
requests, and browser password fields out of the recording.

## Before recording

1. Apply the three Watchtower migrations and deploy the Worker.
2. Register one disposable demo agent in `autopilot`.
3. Open `https://watch.drdeeks.xyz/operator.html`, enter the API endpoint and
   admin token off-screen, then select `autopilot`.
4. In a second terminal, export `WATCHTOWER_INGESTION_SECRET` outside the repo
   and point the Loop Enforcer adapter at the same API.

## 0:00–0:20 — Frame the product

Show the public TV wall, then the Operator Console.

Say: “Federation Watchtower is an agent-operations control plane disguised as a
sitcom. The public wall makes machine state memorable; the private console is
where incidents, sessions, budgets, and evidence become actionable.”

## 0:20–0:55 — Create one bounded session

In a terminal, run the adapter with a unique agent/run and record the returned
lease ID without reading any secret aloud:

```bash
ADAPTER=source/federation-tv-package/mcp-skill/federation-agent/watchtower_loop.py
python3 "$ADAPTER" --project autopilot --agent video-agent --producer video-agent lease \
  --run video-run --scope deploy --scope tool:deploy
```

Refresh the console and point out the durable agent/run session and its bounded
lease.

Say: “A run becomes visible before it takes a consequential step. Its lease is
time-bounded and scope-bounded.”

## 0:55–1:25 — Pass, then fail, a validation gate

Run a pass gate, then a failed gate using the same lease ID:

```bash
python3 "$ADAPTER" --project autopilot --agent video-agent gate --run video-run \
  --lease LEASE_ID --gate-id preflight --passed --statement 'Tests and policy passed.'

python3 "$ADAPTER" --project autopilot --agent video-agent gate --run video-run \
  --lease LEASE_ID --gate-id release-check --statement 'Release validation rejected the plan.'
```

The second command exits `3`. Show the blocked session and the incident/feed
entry.

Say: “This is not a decorative validation event. A failed gate returns a stop
decision to the runner before the next controlled action.”

## 1:25–1:55 — Show enforced tool prevention and budget evidence

Attempt a controlled action after the failed gate:

```bash
python3 "$ADAPTER" --project autopilot --agent video-agent authorize --lease LEASE_ID \
  --tool deploy --action production --input-digest 0000000000000000000000000000000000000000000000000000000000000000
```

It exits `3`; show the denied tool-decision row. Then send one signed event
with `metadata.creditCostUsd` in the configured project budget range and show
the live budget ledger change in the console.

Say: “The external tool is never touched unless the pre-action gateway grants
it. Watchtower also accumulates signed credit cost, rather than trusting a
pretty chart after the money is gone.”

## 1:55–2:20 — Watchdog and audit proof

Show a previously armed demo heartbeat expire, or use the existing lifecycle
agent. Point out that it is `offline`, the watchdog incident is visible, and
the session/control state explains why. Use **Export evidence** in the console
and show only the returned export ID and expiry time.

Say: “Every decision is reconstructed from redacted events, hash-chained audit
records, incident transitions, and a retained R2 evidence export.”

## 2:20–2:30 — Close

Say: “Agents get an API, MCP tools, and a tiny Loop Enforcer adapter. Operators
get a local-friendly dashboard. Everyone gets a clearer answer to: what is
running, what is spending, what is stuck, and what did Watchtower stop?”
