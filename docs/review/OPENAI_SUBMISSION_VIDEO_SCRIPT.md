# Federation Watchtower — under-three-minute demo script

Use two terminals and one browser window. This is a deterministic local demo; it does not use Qwen, a crew, a worker, or a dependency install.

## 0:00–0:20 — Start the gateway

```bash
node source/federation-tv-package/federation-core/demo-gateway.js
```

Say: “Watchtower is a local Federation gateway with a fixed, inspectable demo state.”

## 0:20–0:35 — Verify the state

In a second terminal:

```bash
node source/federation-tv-package/federation-core/demo-verify.js
```

Say: “The one-command check proves three agents are registered and the feed contains pass, fail, and nested-chain packets.”

## 0:35–1:35 — Show the product

Open [http://localhost:41207/](http://localhost:41207/) in a browser. Point out:

1. The deterministic SVG characters are the registered agents.
2. The speech bubbles are public statements from real event packets.
3. The monospace LIVE FEED is the serious operational/audit view.

Say: “A test pass, a test failure, and a runaway nested chain are represented twice: as an operator-readable event and as a short, family-friendly bubble.”

## 1:35–2:20 — Emit another packet

Run this single command while the page is open:

```bash
curl -s -X POST http://localhost:41207/api/federation/statement -H 'Content-Type: application/json' -d '{"agentId":"watchtower-watchdog-1","eventType":"nested_chain_detected","severity":"critical","statement":"The watchdog stopped a recursive build plan.","metadata":{"chainDepth":5,"action":"blocked"}}'
```

Wait one second for the widget poll. Say: “The packet route is the seam for REST, MCP, or an external CI tool; the local widget picks up the new feed entry and bubble.”

## 2:20–2:50 — Close on developer value

Say: “Federation Watchtower gives agent workflows a visible room, a machine-readable feed, and a bounded place to catch failures, budgets, and recursive chains before they burn credits.”
