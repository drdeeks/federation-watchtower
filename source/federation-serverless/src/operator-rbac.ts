import type { WatchtowerEnv } from "./agent-registry.ts";
import { constantTimeEqual, sha256Hex } from "./watchtower.ts";

// Per-organization operator credential (MOD-001 / FEAT-001). Distinct from
// federation_owners' fw_owner_* (an individual's own agents) and from
// mcp_organizations' MCP gateway API key (tool-call access) -- this is the
// credential operator.html accepts to manage one organization's own
// projection/webhook settings without the platform-wide WATCHTOWER_ADMIN_TOKEN.
const OPERATOR_PREFIX = "fw_operator_";
const DEFAULT_SCOPES = ["operator:read", "operator:write"];

export interface OperatorCredential {
  id: string;
  organization_id: string;
  scopes: string;
  issued_at: number;
}

export async function issueOperatorCredential(env: WatchtowerEnv, organizationId: string): Promise<{ token: string; scopes: string[]; issuedAt: number }> {
  const token = issue(OPERATOR_PREFIX);
  const now = Date.now();
  await env.DB.prepare(
    "INSERT INTO federation_operator_credentials (id, organization_id, credential_hash, scopes, issued_at) VALUES (?, ?, ?, ?, ?)"
  ).bind(`opcred-${crypto.randomUUID()}`, organizationId, await sha256Hex(token), JSON.stringify(DEFAULT_SCOPES), now).run();
  return { token, scopes: DEFAULT_SCOPES, issuedAt: now };
}

// Revocation is immediate: the hash is flagged, so the very next request
// authenticated against it 401s (authenticateOperator filters revoked_at IS NULL).
export async function revokeOperatorCredentials(env: WatchtowerEnv, organizationId: string): Promise<number> {
  const now = Date.now();
  const result = await env.DB.prepare(
    "UPDATE federation_operator_credentials SET revoked_at = ? WHERE organization_id = ? AND revoked_at IS NULL"
  ).bind(now, organizationId).run();
  return result.meta.changes ?? 0;
}

// Scoped hard-server-side to organizationId -- every caller passes the
// organizationId the route path claims, never trusts a client-supplied
// project param alone. A credential issued for org A can never authenticate
// against org B's routes, regardless of what the request body/query claims.
export async function authenticateOperator(request: Request, env: WatchtowerEnv, organizationId: string): Promise<OperatorCredential | null> {
  const token = bearer(request, OPERATOR_PREFIX);
  if (!token) return null;
  return env.DB.prepare(
    "SELECT id, organization_id, scopes, issued_at FROM federation_operator_credentials WHERE organization_id = ? AND credential_hash = ? AND revoked_at IS NULL"
  ).bind(organizationId, await sha256Hex(token)).first<OperatorCredential>();
}

// The dual-auth gate every org-scoped route (webhook config, and future
// Agent Control Console routes) is built on: platform admin token OR an
// operator credential scoped to exactly this org. Unlike requireAdmin()'s
// dev-mode bypass when WATCHTOWER_ADMIN_TOKEN is unset, this never bypasses --
// an org-scoping boundary that silently opens in dev would defeat the point.
export async function authenticateOperatorOrAdmin(request: Request, env: WatchtowerEnv, organizationId: string): Promise<{ isAdmin: boolean } | null> {
  const adminToken = env.WATCHTOWER_ADMIN_TOKEN;
  const supplied = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") || "";
  if (adminToken && supplied && constantTimeEqual(adminToken, supplied)) return { isAdmin: true };
  const operator = await authenticateOperator(request, env, organizationId);
  return operator ? { isAdmin: false } : null;
}

function bearer(request: Request, prefix: string): string | null {
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") || "";
  return token.startsWith(prefix) ? token : null;
}

function issue(prefix: string): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return `${prefix}${Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("")}`;
}
