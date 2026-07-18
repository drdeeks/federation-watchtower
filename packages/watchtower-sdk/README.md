# @federation-watchtower/sdk

Small, dependency-free ESM client for the signed Federation Watchtower producer API.

It is designed for server-side agents, Workers, and Node.js services that need to emit operational events and honor cooperative control decisions. It does **not** provide browser authentication, administrator APIs, agent registration, billing, x402 payments, or the prototype access/monetization roadmap.

## Install

```bash
npm install @federation-watchtower/sdk
```

The package is scaffolded in this repository and has not been published yet.

## Use

Keep `WATCHTOWER_INGESTION_SECRET` on the server or in a Worker secret. Never send it to browsers, public widgets, client-side bundles, logs, or event metadata.

```js
import { WatchtowerClient, sha256Hex } from "@federation-watchtower/sdk";

const watchtower = new WatchtowerClient({
  gateway: "https://fapi.drdeeks.xyz", // optional; this is the default
  ingestionSecret: process.env.WATCHTOWER_INGESTION_SECRET,
  producer: "deploy-agent",
});

const lease = await watchtower.requestLease({
  projectId: "autopilot",
  agentId: "deploy-01",
  runId: "release-42",
  ttlSeconds: 120,
  scopes: ["deploy", "tool:deploy"],
});

if (lease.status !== "active") throw new Error("Watchtower denied the work lease");

await watchtower.heartbeat({ projectId: "autopilot", agentId: "deploy-01", runId: "release-42" });

const gate = await watchtower.submitValidationGate({
  projectId: "autopilot", agentId: "deploy-01", runId: "release-42", leaseId: lease.leaseId,
  gateId: "pre-deploy", requestId: "gate-release-42", passed: true,
  statement: "Release validation passed.", metadata: { build: "42" },
});
if (!gate.allowed) throw new Error("Watchtower denied the validation gate");

const authorization = await watchtower.authorizeAction({
  projectId: "autopilot", agentId: "deploy-01", leaseId: lease.leaseId,
  toolName: "deploy", action: "production", requestId: "deploy-release-42",
  inputDigest: await sha256Hex("only-the-local-input-is-hashed"),
});
if (authorization.status !== "authorized") throw new Error("Watchtower denied the action");
```

The client signs the exact UTF-8 JSON body with HMAC-SHA-256 and sends `X-Watchtower-Timestamp`, `X-Watchtower-Signature`, and `X-Watchtower-Producer`. The hosted Worker accepts events at `https://fapi.drdeeks.xyz/api/v1/events` and signed cooperative-control calls below `/api/v1/projects/{projectId}`.

## API

- `emitEvent(event)` — emit a signed, idempotent operational event.
- `heartbeat(input)` — emit a heartbeat and arm the Watchtower watchdog.
- `requestLease(input)` / `validateLease(input)` — request and check a cooperative work lease.
- `submitValidationGate(input)` — record a pass/fail gate; a failed gate can block the run.
- `authorizeAction(input)` — ask Watchtower before a consequential tool action. Provide only an input digest, never the raw tool input.
- `getCommands(input)` / `acknowledgeCommand(input)` — read and acknowledge containment commands.
- `sha256Hex(value)` — calculate a local input digest suitable for `authorizeAction`.

`WatchtowerApiError` exposes `status` and a parsed `body` for denied or malformed responses.

## Publishing checklist

```bash
cd packages/watchtower-sdk
npm test
npm run pack:check
npm login
npm publish --access public
```

Before publishing, confirm that `@federation-watchtower/sdk` is available in the organization, use npm 2FA, and publish from a clean, reviewed commit. The package contains no secret, token, `.env`, test fixture, or Worker deployment configuration.

## License

MIT. See [LICENSE](LICENSE).
