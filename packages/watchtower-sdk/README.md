# @federation-watchtower/sdk

Small, dependency-free ESM client for the signed Federation Watchtower producer API.

It is designed for server-side agents, Workers, and Node.js services that need to emit operational events and honor cooperative control decisions. It does **not** provide browser authentication, administrator APIs, billing, x402 payments, or the prototype access/monetization roadmap.

It also includes two canonical lifecycle clients:

- `FederationOwnerClient` — creates an owner and registers canonical agents
  against the current lifecycle API, mirroring the live onboarding flow. It
  returns a ready `FederationAgentClient` so a host can go from nothing to a
  running agent without hand-assembling requests. It carries only the scoped
  `fw_owner_` credential, never the shared ingestion secret.
- `FederationAgentClient` — the package-facing runtime client for an
  owner-issued `fw_agent_` credential. It lets an agent connect, send
  webhook-style heartbeats/events, disconnect, and return later without holding
  a WebSocket open or carrying the shared ingestion secret.

## Built with Codex and GPT-5.6

This SDK was developed during OpenAI Build Week 2026 using Codex and GPT-5.6:

- **Codex** consolidated the SDK structure, wired the signature logic, implemented the lifecycle clients, and produced the documentation and test suite.
- **GPT-5.6** assisted with TypeScript type definitions, edge case testing for HMAC signing, and refining the API ergonomics for the lease and validation gate methods.

**Codex `/feedback` Session ID:** `019f6d08-6448-7d50-ad6d-8d92bde8c5f3`

## Install

```bash
npm install @federation-watchtower/sdk
```

The package is published as [`@federation-watchtower/sdk`](https://www.npmjs.com/package/@federation-watchtower/sdk).
The repository remains the source of truth for the release, tests, and examples.

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

### Owner onboarding and registration

`FederationOwnerClient` drives the canonical onboarding methods
(`POST /api/v1/owners`, then owner-authenticated `POST /api/v1/agents`). Neither
call sees the shared ingestion secret. Persist the returned `fw_owner_` and
`fw_agent_` credentials in that host’s secret store — they are not browser
tokens.

```js
import { FederationOwnerClient } from "@federation-watchtower/sdk";

// One-time: create the owner and keep credential.token (fw_owner_...) server-side.
const { client: owner } = await FederationOwnerClient.createOwner({
  ownerId: "acme", displayName: "Acme", ownerType: "individual",
});

// Register a canonical agent; the returned client is ready to run the loop.
const { agent, credential } = await owner.registerAgent({
  agentId: "build-01", displayName: "Build 01", ownerId: "acme", projectId: "autopilot",
  role: "testing", capabilities: ["testing", "reporting"],
  identity: { avatarSeed: "build-01", paletteKey: "testing", characterType: "operator" },
  publicProjection: true, heartbeat: { intervalSeconds: 30 },
});
// credential.token is the fw_agent_ secret; `agent` is a wired FederationAgentClient.
await agent.connect();
```

If you already hold an `fw_owner_` token, construct the client directly:
`new FederationOwnerClient({ ownerToken: process.env.FEDERATION_OWNER_TOKEN })`.

### Scoped agent lifecycle

An `fw_agent_` credential is returned once from registration (above, or by an
out-of-band `POST /api/v1/agents`). Persist it in that agent host’s secret
store. It is not a browser token. A heartbeat resets the durable watchdog
deadline; absence transitions the same agent offline, while a later `connect` or
`heartbeat` resumes it.

```js
import { FederationAgentClient } from "@federation-watchtower/sdk";

const agent = new FederationAgentClient({
  projectId: "autopilot",
  agentId: "build-01",
  agentToken: process.env.FEDERATION_AGENT_TOKEN,
});

await agent.connect();
await agent.heartbeat();
await agent.emit({
  eventType: "run.started",
  severity: "info",
  statement: "Starting the bounded build run.",
  metadata: { chainDepth: 1 },
});
```

## Release checklist

Before publishing a new version:

- [ ] All tests pass: `npm test` (8/8 tests)
- [ ] Pack check passes: `npm run pack:check`
- [ ] No secrets in package: verify no `.env`, `.dev.vars`, tokens, or credentials
- [ ] Version bumped in `package.json` (semver: major.minor.patch)
- [ ] README.md updated with any API changes
- [ ] TypeScript types (`index.d.ts`) match `index.js` exports
- [ ] npm 2FA enabled for publisher account
- [ ] Published from clean git commit

```bash
cd packages/watchtower-sdk
npm test
npm run pack:check
npm publish  # requires npm 2FA
```

The current repository release is `0.2.0`. The package contains no secret,
token, `.env`, test fixture, or Worker deployment configuration.

## License

MIT. See [LICENSE](LICENSE).
