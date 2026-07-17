# Source packages

The source tree contains three complementary runtimes:

| Package | Role | Start here |
| --- | --- | --- |
| `federation-serverless/` | Production Cloudflare Worker with Durable Objects, D1, R2, WebSockets, and static Watchtower assets. | [`README.md`](federation-serverless/README.md) |
| `federation-tv-widget/` | Dependency-free browser widget and public Watchtower bundle. | `public/index.html` and `src/tv-widget.js` |
| `federation-tv-package/` | Local Node gateway, command center, shared registry, and MCP skill package. | [`README.md`](federation-tv-package/README.md) |

The Worker and widget are the current public path. The Node package remains useful for offline demos, integration tests, and MCP development.
