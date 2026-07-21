export type EventSeverity = "info" | "success" | "warning" | "error" | "critical";
export type OperationalEventType =
  | "run.started" | "run.completed" | "run.failed" | "heartbeat"
  | "validation.passed" | "validation.failed" | "policy.blocked" | "tool.authorized" | "tool.denied" | "lease.denied"
  | "loop.depth_exceeded" | "loop.duplicate_detected" | "attempt.threshold_exceeded" | "fanout.threshold_exceeded"
  | "heartbeat.missed" | "duration.threshold_exceeded" | "budget.warning" | "budget.exceeded" | "rate.threshold_exceeded"
  | "incident.opened" | "incident.acknowledged" | "containment.requested"
  | "containment.acknowledged" | "incident.resolved";

export interface WatchtowerClientOptions {
  /** Hosted gateway URL. Defaults to https://fapi.drdeeks.xyz. */
  gateway?: string;
  /** Server-side ingestion secret. Never provide it to a browser or public widget. */
  ingestionSecret: string;
  producer: string;
  fetch?: typeof globalThis.fetch;
}

export interface OperationalEvent {
  schemaVersion?: string;
  eventId?: string;
  idempotencyKey?: string;
  projectId: string;
  agentId: string;
  runId?: string;
  parentRunId?: string;
  chainKey?: string;
  eventType: OperationalEventType;
  severity: EventSeverity;
  occurredAt?: string;
  statement: string;
  metadata?: Record<string, unknown>;
}

export interface LeaseRequest { projectId: string; agentId: string; runId: string; ttlSeconds: number; scopes: string[]; }
export interface LeaseValidationRequest { projectId: string; leaseId: string; agentId: string; }
export interface ValidationGateRequest { projectId: string; agentId: string; runId: string; leaseId?: string; gateId: string; requestId: string; passed: boolean; statement: string; metadata?: Record<string, unknown>; }
export interface ControlledActionRequest { projectId: string; agentId: string; leaseId: string; toolName: string; action: string; requestId: string; inputDigest: string; }
export interface CommandAcknowledgement { projectId: string; commandId: string; agentId: string; outcome: "contained" | "rejected" | "failed"; note?: string; }
export interface HeartbeatInput { projectId: string; agentId: string; runId?: string; statement?: string; expectedHeartbeatSeconds?: number; metadata?: Record<string, unknown>; idempotencyKey?: string; }

export class WatchtowerApiError extends Error { readonly status: number; readonly body: unknown; }
export function stableJson(value: unknown): string;
export function sha256Hex(value: string): Promise<string>;
export function hmacSha256Hex(secret: string, value: string): Promise<string>;

export class WatchtowerClient {
  constructor(options: WatchtowerClientOptions);
  emitEvent(event: OperationalEvent): Promise<unknown>;
  heartbeat(input: HeartbeatInput): Promise<unknown>;
  requestLease(input: LeaseRequest): Promise<unknown>;
  validateLease(input: LeaseValidationRequest): Promise<unknown>;
  submitValidationGate(input: ValidationGateRequest): Promise<unknown>;
  authorizeAction(input: ControlledActionRequest): Promise<unknown>;
  getCommands(input: Pick<LeaseValidationRequest, "projectId" | "agentId">): Promise<unknown>;
  acknowledgeCommand(input: CommandAcknowledgement): Promise<unknown>;
}

export interface FederationAgentClientOptions {
  gateway?: string;
  /** Scoped `fw_agent_` credential returned once from canonical registration. Keep it server-side. */
  agentToken: string;
  projectId: string;
  agentId: string;
  fetch?: typeof globalThis.fetch;
}
export interface AgentLifecycleEvent {
  eventId?: string;
  idempotencyKey?: string;
  eventType: OperationalEventType;
  severity: EventSeverity;
  occurredAt?: string;
  statement: string;
  metadata?: Record<string, unknown>;
}
export class FederationAgentClient {
  constructor(options: FederationAgentClientOptions);
  connect(input?: { idempotencyKey?: string }): Promise<unknown>;
  heartbeat(input?: { idempotencyKey?: string }): Promise<unknown>;
  disconnect(input?: { idempotencyKey?: string }): Promise<unknown>;
  emit(input: AgentLifecycleEvent): Promise<unknown>;
}

/**
 * Canonical agent identity manifest submitted at registration. Mirrors the
 * shape validated by the Worker's `validateLifecycleManifest` and the live
 * onboarding flow — not the legacy administrative registration payload.
 */
export interface AgentManifest {
  agentId: string;
  displayName: string;
  ownerId: string;
  projectId: string;
  role: string;
  capabilities: string[];
  identity: { avatarSeed: string; paletteKey: string; characterType: string };
  publicProjection: boolean;
  heartbeat: { intervalSeconds: number };
  organizationId?: string;
  /** Required (≤120 chars) — seeds this agent's entry in the public speech pool. */
  statement: string;
}

export interface CreateOwnerInput {
  gateway?: string;
  ownerId: string;
  displayName: string;
  ownerType: "individual" | "organization";
  fetch?: typeof globalThis.fetch;
}

export interface FederationOwnerClientOptions {
  gateway?: string;
  /** Scoped `fw_owner_` credential returned once from owner creation. Keep it server-side. */
  ownerToken: string;
  ownerId?: string;
  fetch?: typeof globalThis.fetch;
}

export interface RegisteredAgent {
  agent: { agentId: string; projectId: string; roomId?: string; [key: string]: unknown };
  credential: { token: string; scopes?: string[]; issuedAt?: number };
  next?: Record<string, string>;
  /** A ready-to-use lifecycle client bound to the new `fw_agent_` credential. */
  client: FederationAgentClient;
}

export interface CreatedOwner {
  owner: { ownerId: string; [key: string]: unknown };
  credential: { token: string; scopes?: string[]; issuedAt?: number };
  /** An owner client bound to the new `fw_owner_` credential. */
  client: FederationOwnerClient;
}

/**
 * Owner-scoped registration client. Creates an owner and registers canonical
 * agents against the current lifecycle API, returning a wired
 * `FederationAgentClient` so a host can go from nothing to a running agent
 * without hand-assembling requests. Never carries the shared ingestion secret.
 */
export class FederationOwnerClient {
  constructor(options: FederationOwnerClientOptions);
  static createOwner(input: CreateOwnerInput): Promise<CreatedOwner>;
  registerAgent(manifest: AgentManifest): Promise<RegisteredAgent>;
}
