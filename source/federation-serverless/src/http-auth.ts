import type { WatchtowerEnv } from "./agent-registry.ts";
import { authenticateAgent } from "./lifecycle.ts";
import { constantTimeEqual, hmacSha256Hex } from "./watchtower.ts";

// Split out of index.ts on purpose: index.ts transitively imports the
// Durable Object classes (AgentRegistry, FederationCoordinator, ...), which
// import `DurableObject` from `cloudflare:workers` -- a module that only
// exists inside the actual Workers runtime. That makes index.ts itself
// un-importable from any plain-Node *.test.ts file under this repo's real
// `npm test` runner (`node --experimental-strip-types --test`). Every other
// auth helper in this codebase (authenticateAgent, authenticateOperator,
// verifyMcpApiKey) already lives in its own DO-free file for exactly this
// reason; this file follows the same established pattern.
const SIGNATURE_WINDOW_MS = 5 * 60 * 1_000;

export class HttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export async function authenticateProducer(request: Request, rawBody: string, env: WatchtowerEnv): Promise<string> {
  const secret = env.WATCHTOWER_INGESTION_SECRET;
  if (!secret) {
    if (env.ENVIRONMENT === "production") throw new HttpError(503, "event ingestion is not configured");
    return "local-development";
  }
  const timestamp = request.headers.get("X-Watchtower-Timestamp");
  const supplied = request.headers.get("X-Watchtower-Signature")?.replace(/^sha256=/i, "");
  if (!timestamp || !supplied || !/^\d{10,13}$/.test(timestamp) || !/^[a-f0-9]{64}$/i.test(supplied)) throw new HttpError(401, "missing or malformed producer signature");
  const timestampMs = timestamp.length === 10 ? Number(timestamp) * 1_000 : Number(timestamp);
  if (!Number.isSafeInteger(timestampMs) || Math.abs(Date.now() - timestampMs) > SIGNATURE_WINDOW_MS) throw new HttpError(401, "producer signature timestamp is stale");
  const expected = await hmacSha256Hex(secret, `${timestamp}.${rawBody}`);
  if (!constantTimeEqual(expected, supplied.toLowerCase())) throw new HttpError(401, "producer signature is invalid");
  const producer = request.headers.get("X-Watchtower-Producer") || "signed-producer";
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(producer)) throw new HttpError(400, "producer identifier contains unsupported characters");
  return producer;
}

// MOD-002 / FEAT-002: extends canonical fw_agent_* bearer auth to the four
// routes that previously accepted only producer-signed HMAC. A present
// fw_agent_*-prefixed bearer routes exclusively through canonical auth (no
// silent fallback to HMAC on a wrong/expired canonical token -- an
// adversary can't downgrade to the weaker legacy path just by failing the
// strong one). No Authorization bearer at all -- today's adapter's exact
// behavior on these routes -- falls through to producer-signed HMAC
// unchanged, so the existing HMAC-only adapter keeps working with zero
// changes on its side (verified against watchtower-ack-adapter's
// FEDERATION_ROUTE_MAP.md: it never sends an Authorization header on these
// four routes today). Returns a producerId-shaped string either way, same
// contract authenticateProducer already had.
export async function authenticateCanonicalOrProducer(request: Request, rawBody: string, env: WatchtowerEnv, projectId: string, agentId: string): Promise<string> {
  const bearerToken = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") || "";
  if (bearerToken.startsWith("fw_agent_")) {
    const agent = await authenticateAgent(request, env, projectId, agentId);
    if (!agent) throw new HttpError(401, "an active credential for this agent is required");
    return `agent:${agent.id}`;
  }
  return authenticateProducer(request, rawBody, env);
}
