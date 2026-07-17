export const EVENT_TYPES = new Set([
  "run.started", "run.completed", "run.failed", "heartbeat",
  "validation.passed", "validation.failed", "policy.blocked", "tool.denied", "lease.denied",
  "loop.depth_exceeded", "loop.duplicate_detected", "attempt.threshold_exceeded",
  "fanout.threshold_exceeded", "heartbeat.missed", "duration.threshold_exceeded",
  "budget.warning", "budget.exceeded", "rate.threshold_exceeded",
  "incident.opened", "incident.acknowledged", "containment.requested",
  "containment.acknowledged", "incident.resolved",
]);

export type EventSeverity = "info" | "success" | "warning" | "error" | "critical";
export type GuardrailAction = "observe" | "alert" | "require_approval" | "pause" | "quarantine" | "deny";

export interface OperationalEvent {
  schemaVersion: string;
  eventId: string;
  idempotencyKey: string;
  projectId: string;
  agentId: string;
  runId?: string;
  parentRunId?: string;
  chainKey?: string;
  eventType: string;
  severity: EventSeverity;
  occurredAt: string;
  statement: string;
  metadata: Record<string, unknown>;
}

export interface RunawayContext {
  failedAttempts: number;
  matchingChainStarts: number;
}

export interface GuardrailDecision {
  ruleId: string;
  action: GuardrailAction;
  severity: EventSeverity;
  reason: string;
}

const IDENTIFIER = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const PROJECT_IDENTIFIER = /^[a-z0-9][a-z0-9-]{0,63}$/;
const SEVERITIES = new Set<EventSeverity>(["info", "success", "warning", "error", "critical"]);
const SENSITIVE_KEY = /authorization|api[_-]?key|token|secret|password|cookie|credential/i;
const MAX_METADATA_BYTES = 8_192;
const MAX_EVENT_AGE_MS = 90 * 24 * 60 * 60 * 1_000;
const MAX_FUTURE_SKEW_MS = 5 * 60 * 1_000;

export function validateOperationalEvent(value: unknown, now = Date.now()): OperationalEvent {
  if (!isRecord(value)) throw new Error("event body must be a JSON object");
  const event: OperationalEvent = {
    schemaVersion: requiredString(value.schemaVersion, "schemaVersion", 32),
    eventId: requiredIdentifier(value.eventId, "eventId"),
    idempotencyKey: requiredIdentifier(value.idempotencyKey, "idempotencyKey"),
    projectId: requiredProjectId(value.projectId),
    agentId: requiredIdentifier(value.agentId, "agentId"),
    runId: optionalIdentifier(value.runId, "runId"),
    parentRunId: optionalIdentifier(value.parentRunId, "parentRunId"),
    chainKey: optionalIdentifier(value.chainKey, "chainKey"),
    eventType: requiredString(value.eventType, "eventType", 64),
    severity: requiredSeverity(value.severity),
    occurredAt: requiredDate(value.occurredAt, now),
    statement: requiredString(value.statement, "statement", 120),
    metadata: redactMetadata(value.metadata),
  };

  if (!EVENT_TYPES.has(event.eventType)) throw new Error("eventType is not approved");
  if (event.parentRunId && !event.runId) throw new Error("parentRunId requires runId");
  return event;
}

export function evaluateRunawayRules(event: OperationalEvent, context: RunawayContext): GuardrailDecision[] {
  const decisions: GuardrailDecision[] = [];
  const chainDepth = numberMetadata(event.metadata, "chainDepth");
  const budgetUsd = numberMetadata(event.metadata, "budgetUsd");

  if (chainDepth !== undefined && chainDepth > 5) {
    decisions.push({ ruleId: "max-chain-depth-v1", action: "pause", severity: "critical", reason: `chain depth ${chainDepth} exceeds 5` });
  }
  if (event.eventType === "validation.failed" && context.failedAttempts >= 3) {
    decisions.push({ ruleId: "failed-attempts-v1", action: "require_approval", severity: "error", reason: `${context.failedAttempts} validation failures in the retry window` });
  }
  if (budgetUsd !== undefined && budgetUsd >= 10) {
    decisions.push({ ruleId: "budget-limit-v1", action: "quarantine", severity: "critical", reason: `reported budget $${budgetUsd.toFixed(2)} meets or exceeds $10.00` });
  }
  if (event.eventType === "run.started" && event.chainKey && context.matchingChainStarts >= 2) {
    decisions.push({ ruleId: "duplicate-chain-v1", action: "pause", severity: "error", reason: `duplicate chain key ${event.chainKey} has ${context.matchingChainStarts} concurrent starts` });
  }
  return decisions;
}

export function severityToPriority(severity: EventSeverity): "low" | "normal" | "high" | "critical" {
  if (severity === "critical") return "critical";
  if (severity === "error") return "high";
  if (severity === "warning") return "normal";
  return "low";
}

export function stableJson(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  const record = value as Record<string, unknown>;
  return `{${Object.keys(record).sort().map(key => `${JSON.stringify(key)}:${stableJson(record[key])}`).join(",")}}`;
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return bytesToHex(new Uint8Array(digest));
}

export async function hmacSha256Hex(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(signature));
}

export function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index++) difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  return difference === 0;
}

function requiredString(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > maxLength) throw new Error(`${field} must be a non-empty string up to ${maxLength} characters`);
  return value.trim();
}

function requiredIdentifier(value: unknown, field: string): string {
  const identifier = requiredString(value, field, 128);
  if (!IDENTIFIER.test(identifier)) throw new Error(`${field} contains unsupported characters`);
  return identifier;
}

function optionalIdentifier(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  return requiredIdentifier(value, field);
}

function requiredProjectId(value: unknown): string {
  const projectId = requiredString(value, "projectId", 64);
  if (!PROJECT_IDENTIFIER.test(projectId)) throw new Error("projectId must be lowercase letters, digits, or hyphens");
  return projectId;
}

function requiredSeverity(value: unknown): EventSeverity {
  if (typeof value !== "string" || !SEVERITIES.has(value as EventSeverity)) throw new Error("severity is invalid");
  return value as EventSeverity;
}

function requiredDate(value: unknown, now: number): string {
  if (typeof value !== "string") throw new Error("occurredAt must be an ISO-8601 timestamp");
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed) || parsed < now - MAX_EVENT_AGE_MS || parsed > now + MAX_FUTURE_SKEW_MS) throw new Error("occurredAt is outside the accepted window");
  return new Date(parsed).toISOString();
}

function redactMetadata(value: unknown): Record<string, unknown> {
  if (value === undefined) return {};
  if (!isRecord(value)) throw new Error("metadata must be a JSON object");
  const redacted = redactValue(value, 0) as Record<string, unknown>;
  if (new TextEncoder().encode(JSON.stringify(redacted)).byteLength > MAX_METADATA_BYTES) throw new Error("metadata exceeds 8 KiB after redaction");
  return redacted;
}

function redactValue(value: unknown, depth: number): unknown {
  if (depth > 4) throw new Error("metadata may not be nested more than four levels");
  if (value === null || typeof value === "string" || typeof value === "number" || typeof value === "boolean") return value;
  if (Array.isArray(value)) return value.map(item => redactValue(item, depth + 1));
  if (!isRecord(value)) throw new Error("metadata contains a non-JSON value");
  return Object.fromEntries(Object.entries(value).map(([key, nested]) => [key, SENSITIVE_KEY.test(key) ? "[REDACTED]" : redactValue(nested, depth + 1)]));
}

function numberMetadata(metadata: Record<string, unknown>, key: string): number | undefined {
  const value = metadata[key];
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
}
