# Federation Watchtower

[![Cloudflare Workers](https://img.shields.io/badge/Cloudflare-Workers-f38020?logo=cloudflare&logoColor=white)](https://developers.cloudflare.com/workers/)
[![TypeScript](https://img.shields.io/badge/Worker-TypeScript-3178c6?logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![Node.js](https://img.shields.io/badge/Local_runtime-Node.js_20%2B-339933?logo=node.js&logoColor=white)](https://nodejs.org/)
[![MCP](https://img.shields.io/badge/Integration-MCP-6e56cf)](https://modelcontextprotocol.io/)
[![License](https://img.shields.io/badge/license-MIT-2f855a)](LICENSE)

Federation Watchtower is the observable front door for a broader autonomous-systems control plane: an agent-operations command center presented as an embeddable sitcom. It brings together agent registration, MCP/API/widget access, guardrail monitoring, validation gates, runaway-chain detection, failure reporting, and human-readable operational telemetry. Machine events become visible, memorable status bubbles without losing their structured audit trail.

The public Watchtower is live at [watch.drdeeks.xyz](https://watch.drdeeks.xyz). The production API is available at [fapi.drdeeks.xyz](https://fapi.drdeeks.xyz), with [federation.drdeeks.xyz](https://federation.drdeeks.xyz) configured as the human-facing API alias.

## What is here

| Path | Purpose |
| --- | --- |
| `source/federation-serverless/` | Production Cloudflare Worker, Durable Objects, D1 schema, R2 binding, and deployed host configuration. |
| `source/federation-tv-widget/` | Embeddable TV widget and the public Watchtower static site. |
| `source/federation-tv-package/` | Dependency-backed local Node gateway, MCP skill, command center, and legacy adapter package. |
| `brand/` | Canonical Federation Watchtower logo, palette tokens, wordmark, and splash screen. |
| `docs/review/` | Product blueprint, build plan, packet specification, source inventory, and submission notes. |
| `skills-reference/` | Supporting autonomous-crew, blueprint, and integration references. |

The repository keeps the local adapter and the Cloudflare deployment side by side deliberately: the local path is the fastest offline demo, while the Worker path is the persistent production architecture.

## The larger purpose

Watchtower is meant to incorporate the surrounding operational systems already represented in this repository, not replace them with a dashboard:

- **Federation registry** — organizations, projects, agents, rooms, identities, heartbeats, and live events.
- **Guardrail monitoring** — runaway loops, duplicate chains, budget pressure, invalid states, and blocked work become explicit events.
- **Validation and enforcement** — blueprint gates, policy checks, source verification, and structured review signals can report into the same feed.
- **MCP/API/widget access** — humans see the broadcast, agents use MCP or REST, and embedded widgets provide a lightweight status surface.
- **Enterprise operations** — the referenced crew, self-healing, audit, memory, and integration systems provide the deeper control-plane patterns behind the visible Watchtower.

The sitcom is the interface layer. The real product is a shared observability and governance surface for autonomous systems.

## Live endpoints

| Endpoint | Use |
| --- | --- |
| `https://watch.drdeeks.xyz/` | Public Watchtower TV wall and widget demo. |
| `https://fapi.drdeeks.xyz/health` | Primary API health check. |
| `https://fapi.drdeeks.xyz/api/projects` | List registered projects. |
| `https://federation.drdeeks.xyz/health` | API alias health check. |
| `https://fapi.drdeeks.xyz/ws?projectId=autopilot` | WebSocket feed for a project. |

The `watch` host is static-only at the application layer. API calls from the public page go to `fapi`; the public host does not expose the Worker API routes itself.

## Fastest local demo

Requirements: Node.js 20 or newer. The local adapter uses Node’s standard library and does not require an install.

Start the gateway:

```bash
node source/federation-tv-package/federation-core/demo-gateway.js
```

Open [http://localhost:41207/](http://localhost:41207/) or run the terminal view:

```bash
node source/federation-tv-package/federation-core/demo-terminal.js
```

Run the contract verification in another terminal:

```bash
node source/federation-tv-package/federation-core/demo-verify.js
```

The adapter is intentionally in-memory and dependency-free. It is for local demonstrations and contract checks, not the persistent public service.

## Cloudflare deployment

The deployed Worker lives in `source/federation-serverless/` and uses:

- Cloudflare Workers for the HTTP and WebSocket edge runtime.
- Durable Objects for per-project registries and the global federation coordinator.
- D1 for projects, rooms, agents, feed events, federation applications, and access records.
- R2 for the federation vault.
- Worker static assets for the public Watchtower bundle.

Install the deployment toolchain:

```bash
cd source/federation-serverless
npm install
```

Authenticate without committing a credential:

```bash
export CLOUDFLARE_API_TOKEN='your-token'
```

The token needs Worker script deployment and zone Worker-route permissions. Do not put it in `.env`, source files, Wrangler config, or shell history that is checked into the project.

Useful commands:

```bash
npm run types       # regenerate Worker binding types
npm run check       # run Wrangler's installed validation command
npm run deploy      # deploy Worker, assets, and custom domains
npm run schema      # apply src/schema.sql to the remote D1 database
```

The checked-in `wrangler.toml` is the source of truth for the current bindings and hostnames. Do not replace its live D1 ID with a placeholder when editing the file.

## Widget embed

The widget is a plain browser script with no runtime dependency:

```html
<div id="federation-tv"></div>
<script
  src="https://watch.drdeeks.xyz/tv-widget.js"
  data-project="autopilot"
  data-gateway="https://fapi.drdeeks.xyz">
</script>
```

Or initialize it directly:

```js
const tv = new FederationTV({
  projectId: 'autopilot',
  container: '#federation-tv',
  gatewayUrl: 'https://fapi.drdeeks.xyz'
});
```

The widget exposes project agents, feed events, status changes, and speech-line submission. Use the public site for the visual demo and the API for agent integrations.

## API shape

### System routes

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Worker health. |
| `GET` | `/api/status` | Global project, room, and agent status. |
| `GET` | `/api/projects` | List projects. |
| `GET` | `/api/feed` | Global event feed. |
| `GET` | `/api/search?q=...` | Search federation state. |
| `GET` | `/api/health` | Health across projects. |
| `GET` | `/api/rooms` | Rooms across projects. |
| `GET` | `/ws?projectId=...` | Live WebSocket feed. |

Project-scoped routes use `/api/projects/{projectId}/...` and cover agent registration, heartbeats, status, rooms, feed, summaries, memory, daily notes, entities, and search. The complete route table is maintained in [`source/federation-serverless/README.md`](source/federation-serverless/README.md).

Example registration:

```bash
curl -X POST 'https://fapi.drdeeks.xyz/api/projects/autopilot/agents' \
  -H 'Content-Type: application/json' \
  -d '{"agentId":"demo-agent-01","name":"Demo Agent","role":"coding","capabilities":["tests"]}'
```

## Branding

The canonical brand kit is in [`brand/`](brand/). It includes:

- [`federation-f-mark.svg`](brand/federation-f-mark.svg) — square broadcast mark.
- [`federation-wordmark.svg`](brand/federation-wordmark.svg) — header lockup.
- [`tokens.css`](brand/tokens.css) — shared themes and typography tokens.
- [`splash.html`](brand/splash.html) — lightweight branded loading/splash screen.

The widget’s `public/brand/` directory is the deployment copy of those assets; the two locations are currently byte-identical. Update the canonical kit first, then copy the changed assets into the public bundle before deploying.

## Documentation map

- [`docs/README.md`](docs/README.md) — documentation index.
- [`docs/review/FEDERATION_WATCHTOWER_BLUEPRINT.md`](docs/review/FEDERATION_WATCHTOWER_BLUEPRINT.md) — product and architecture blueprint.
- [`docs/review/SUPER_STATEMENT_PACKET_SPEC.md`](docs/review/SUPER_STATEMENT_PACKET_SPEC.md) — event packet contract.
- [`docs/review/BUILD_PLAN.md`](docs/review/BUILD_PLAN.md) — staged implementation plan.
- [`docs/review/SOURCE_INVENTORY.md`](docs/review/SOURCE_INVENTORY.md) — provenance and source map.
- [`source/federation-serverless/agents-skill.md`](source/federation-serverless/agents-skill.md) — agent registration and integration contract.
- [`source/federation-tv-package/mcp-skill/tv-sitcom-mcp/SKILL.md`](source/federation-tv-package/mcp-skill/tv-sitcom-mcp/SKILL.md) — MCP tool and resource surface.

## Development notes

- Keep secrets out of the repository; use environment variables or Wrangler secrets.
- Keep `brand/` canonical and treat the public copy as a deployment artifact.
- Keep generated dependencies, Wrangler state, logs, and release archives ignored.
- Prefer the Cloudflare Worker path for production behavior; use the local adapter for fast demos and tests.
- Authentication and authorization for administrative/API mutation routes remain a production-hardening task. Do not treat CORS as access control.

## License

MIT. See [`LICENSE`](LICENSE).
