import type { WatchtowerEnv } from "./agent-registry.ts";
import { alertWebhookFormat, type AlertWebhookFormat } from "./alert-webhook.ts";
import { ValidationError } from "./watchtower.ts";

// MOD-003 / FEAT-003: per-organization and per-agent webhook destinations.
// scope_id for 'agent' is the canonical composite id (federation_agents.id,
// i.e. "projectId:agentId") -- the same value used everywhere else in this
// codebase as an agent's canonical identity, so no separate id scheme is
// introduced here.
export interface WebhookDestinationInput { url: string; format: AlertWebhookFormat; }
export interface WebhookDestination { url: string; format: AlertWebhookFormat; secret?: string; updatedAt: number; }

export function validateWebhookDestinationBody(value: unknown): WebhookDestinationInput {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new ValidationError("webhook body must be a JSON object");
  const body = value as Record<string, unknown>;
  if (typeof body.url !== "string" || body.url.length > 2048) throw new ValidationError("url must be a non-empty string up to 2048 characters");
  let parsed: URL;
  try { parsed = new URL(body.url); } catch { throw new ValidationError("url must be a valid URL"); }
  if (parsed.protocol !== "https:") throw new ValidationError("url must use HTTPS");
  const format = alertWebhookFormat(typeof body.format === "string" ? body.format : undefined);
  return { url: parsed.toString(), format };
}

// Upsert (create-or-replace, matching webhook_destinations' UNIQUE(scope_type,
// scope_id)). Auto-generates a fresh per-destination secret for format "json"
// -- callers never get to supply their own low-entropy signing secret -- and
// returns it exactly once in the response, the same one-time-reveal pattern
// used for every other generated credential in this codebase.
export async function upsertWebhookDestination(env: WatchtowerEnv, scopeType: "organization" | "agent", scopeId: string, input: WebhookDestinationInput): Promise<WebhookDestination> {
  const now = Date.now();
  const secret = input.format === "json" ? issueSecret() : null;
  await env.DB.prepare(
    `INSERT INTO webhook_destinations (id, scope_type, scope_id, url, format, secret, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(scope_type, scope_id) DO UPDATE SET url = excluded.url, format = excluded.format, secret = excluded.secret, updated_at = excluded.updated_at`
  ).bind(`webhook-${crypto.randomUUID()}`, scopeType, scopeId, input.url, input.format, secret, now, now).run();
  return { url: input.url, format: input.format, secret: secret ?? undefined, updatedAt: now };
}

interface DestinationRow { url: string; format: AlertWebhookFormat; secret: string | null; }

// Resolution order: agent-level override (most specific -- the word
// "override" in FEAT-003 implies it takes precedence) -> the agent's
// organization's destination -> null (caller falls back to the global
// WATCHTOWER_ALERT_WEBHOOK_URL). Amendment to the blueprint's literal prose,
// which listed org-then-agent; "override" only makes sense if it's checked
// first, and PROJECT tier Part V permits recording drift here rather than
// silently reinterpreting it.
export async function resolveWebhookDestination(env: WatchtowerEnv, projectId: string, agentId: string): Promise<DestinationRow | null> {
  const canonicalAgentId = `${projectId}:${agentId}`;
  const agentDestination = await env.DB.prepare(
    "SELECT url, format, secret FROM webhook_destinations WHERE scope_type = 'agent' AND scope_id = ?"
  ).bind(canonicalAgentId).first<DestinationRow>();
  if (agentDestination) return agentDestination;

  const agent = await env.DB.prepare("SELECT organization_id FROM federation_agents WHERE id = ?").bind(canonicalAgentId).first<{ organization_id: string | null }>();
  if (!agent?.organization_id) return null;

  return env.DB.prepare(
    "SELECT url, format, secret FROM webhook_destinations WHERE scope_type = 'organization' AND scope_id = ?"
  ).bind(agent.organization_id).first<DestinationRow>();
}

function issueSecret(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
}
