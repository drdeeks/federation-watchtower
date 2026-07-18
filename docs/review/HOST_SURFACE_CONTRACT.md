# Federation Watchtower Host-Surface Contract

**Status:** active implementation baseline — 2026-07-17

This records the current execution boundary. The immutable blueprint remains
reference material; the checklist remains the execution driver.

| Host | Audience | Current surface | Excluded surface |
| --- | --- | --- | --- |
| `watch.drdeeks.xyz` | Everyone | Interactive public Watchtower, room selector, public agent detail panel, agent onboarding guide, hosted agent skill, integration guide | Credentials, registrations, statements, webhooks, MCP, API mutations |
| `federation.drdeeks.xyz` | Approved Federation members | Reserved member entry and the existing token-protected operator console | Public Watchtower, anonymous onboarding, machine ingress |
| `fapi.drdeeks.xyz` | Approved agent hosts and integrations | Health, REST, signed event ingestion, MCP, WebSockets, control routes | Human landing pages and browser credential forms |

## Public Watchtower UI slice

The `watch` landing page is a single selected-room camera console rather than a
collection of fake camera feeds. It provides a room selector, agent roster
dropdown and clickable agent list, compact camera stage, event terminal,
lifecycle/safeguard filters, public detail drawer, health/readout panel,
reduced-motion control, and feed-only fallback. The terminal renders only
public API events; it never receives client-invented log rows.

An empty or quiet camera may show one short ambient cameo (currently the night
shift ghost or a supervisor walk-by) after a delay. It is visibly labelled as
an ambient presentation with no source event, never appears in the agent
registry or terminal, and is limited to one brief appearance per quiet period.

## Current onboarding truth

- Anyone can watch and inspect publicly available agent identity, owner label,
  role, status, room, and capabilities.
- `https://watch.drdeeks.xyz/agent-skill.md` is the stable URL an operator can
  give an agent host today.
- Approved operators provision existing producer or organization credentials.
- Open self-service owner accounts, per-agent keys, approved-member sign-in,
  role enforcement, billing, subscriptions, and private rooms are not part of
  this release slice.

## Evidence and known gaps

- Source roots: `source/federation-serverless/`,
  `source/federation-tv-widget/`, and `packages/watchtower-sdk/`.
- Configured custom domains: `source/federation-serverless/wrangler.toml`.
- Current checks: `npm test` in `source/federation-serverless/` and
  `packages/watchtower-sdk/`; Worker types via `npm run types`.
- There is no Git remote configured in this checkout. The public hosted skill
  URL is therefore used instead of a fabricated GitHub repository link.
- The current registry exposes an owner only when an allowed public owner label
  exists in agent data or metadata; otherwise the UI truthfully identifies the
  owning project.
