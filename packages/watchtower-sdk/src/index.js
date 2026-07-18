const DEFAULT_GATEWAY = "https://fapi.drdeeks.xyz";
const DEFAULT_SCHEMA_VERSION = "2026-07-17";

/** An API response that was syntactically valid but not successful. */
export class WatchtowerApiError extends Error {
  constructor(status, body) {
    const detail = typeof body?.error === "string" ? body.error : `Watchtower returned HTTP ${status}`;
    super(detail);
    this.name = "WatchtowerApiError";
    this.status = status;
    this.body = body;
  }
}

/**
 * Stable JSON prevents accidental signature mismatches caused by object key
 * order. It accepts only JSON-safe values so a caller cannot sign one payload
 * and have fetch serialize another.
 */
export function stableJson(value) {
  if (value === null) return "null";
  if (typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new TypeError("payload numbers must be finite");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (typeof value === "object") {
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) throw new TypeError("payload objects must be plain JSON objects");
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  }
  throw new TypeError("payload values must be JSON-safe");
}

export async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(digest));
}

export async function hmacSha256Hex(secret, value) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(signature));
}

export class WatchtowerClient {
  constructor(options) {
    if (!options || typeof options.ingestionSecret !== "string" || !options.ingestionSecret) {
      throw new TypeError("ingestionSecret is required and must remain server-side");
    }
    if (typeof options.producer !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(options.producer)) {
      throw new TypeError("producer must be a bounded Watchtower producer identifier");
    }
    this.gateway = (options.gateway ?? DEFAULT_GATEWAY).replace(/\/+$/, "");
    this.ingestionSecret = options.ingestionSecret;
    this.producer = options.producer;
    this.fetch = options.fetch ?? globalThis.fetch;
    if (typeof this.fetch !== "function") throw new TypeError("a fetch implementation is required");
  }

  async emitEvent(event) {
    const now = new Date().toISOString();
    const id = randomId();
    const payload = {
      schemaVersion: event.schemaVersion ?? DEFAULT_SCHEMA_VERSION,
      eventId: event.eventId ?? `evt-${id}`,
      idempotencyKey: event.idempotencyKey ?? `${event.eventType}-${id}`,
      projectId: event.projectId,
      agentId: event.agentId,
      eventType: event.eventType,
      severity: event.severity,
      occurredAt: event.occurredAt ?? now,
      statement: event.statement,
      metadata: event.metadata ?? {},
      ...(event.runId ? { runId: event.runId } : {}),
      ...(event.parentRunId ? { parentRunId: event.parentRunId } : {}),
      ...(event.chainKey ? { chainKey: event.chainKey } : {}),
    };
    return this.signedRequest("POST", "/api/v1/events", payload);
  }

  async heartbeat(input) {
    return this.emitEvent({
      projectId: input.projectId,
      agentId: input.agentId,
      runId: input.runId,
      eventType: "heartbeat",
      severity: "info",
      statement: input.statement ?? "Watchtower heartbeat received.",
      metadata: { expectedHeartbeatSeconds: input.expectedHeartbeatSeconds ?? 120, ...(input.metadata ?? {}) },
      idempotencyKey: input.idempotencyKey,
    });
  }

  async requestLease(input) {
    return this.signedRequest("POST", `/api/v1/projects/${encodeURIComponent(input.projectId)}/leases`, input);
  }

  async validateLease({ projectId, leaseId, agentId }) {
    return this.signedRequest("POST", `/api/v1/projects/${encodeURIComponent(projectId)}/leases/${encodeURIComponent(leaseId)}/validate`, { agentId });
  }

  async submitValidationGate(input) {
    return this.signedRequest("POST", `/api/v1/projects/${encodeURIComponent(input.projectId)}/validation-gates`, input);
  }

  async authorizeAction(input) {
    return this.signedRequest("POST", `/api/v1/projects/${encodeURIComponent(input.projectId)}/tools/authorize`, input);
  }

  async getCommands({ projectId, agentId }) {
    return this.signedRequest("GET", `/api/v1/projects/${encodeURIComponent(projectId)}/agents/${encodeURIComponent(agentId)}/commands`);
  }

  async acknowledgeCommand(input) {
    return this.signedRequest("POST", `/api/v1/projects/${encodeURIComponent(input.projectId)}/commands/acknowledge`, input);
  }

  async signedRequest(method, path, payload) {
    const body = payload === undefined ? "" : stableJson(payload);
    const timestamp = Math.floor(Date.now() / 1_000).toString();
    const signature = await hmacSha256Hex(this.ingestionSecret, `${timestamp}.${body}`);
    const headers = new Headers({
      "X-Watchtower-Timestamp": timestamp,
      "X-Watchtower-Signature": `sha256=${signature}`,
      "X-Watchtower-Producer": this.producer,
    });
    if (payload !== undefined) headers.set("Content-Type", "application/json");
    const response = await this.fetch(`${this.gateway}${path}`, { method, headers, ...(payload === undefined ? {} : { body }) });
    const responseBody = await parseResponse(response);
    if (!response.ok) throw new WatchtowerApiError(response.status, responseBody);
    return responseBody;
  }
}

async function parseResponse(response) {
  const text = await response.text();
  if (!text) return undefined;
  try { return JSON.parse(text); } catch { return text; }
}

function randomId() {
  return typeof crypto.randomUUID === "function" ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function bytesToHex(bytes) {
  return Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
}
