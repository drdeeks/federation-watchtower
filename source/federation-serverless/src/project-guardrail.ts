import { DurableObject } from "cloudflare:workers";
import type { WatchtowerEnv } from "./agent-registry";
import { evaluateRunawayRules, type CommandAcknowledgement, type ControlledToolAuthorizationRequest, type GuardrailDecision, type LeaseRequest, type OperationalEvent, type ValidationGateRequest, severityToPriority, sha256Hex, stableJson } from "./watchtower";

export interface IngestedEvent {
  event: OperationalEvent;
  producerId: string;
  payloadDigest: string;
  receivedAt: number;
}

export interface IngestResult {
  accepted: boolean;
  duplicate: boolean;
  eventId: string;
  incidentIds: string[];
  decisions: GuardrailDecision[];
  alerts: AlertDispatch[];
}

export interface AlertDispatch {
  deliveryId: string;
  projectId: string;
  incidentId: string;
  eventId: string;
  agentId: string;
  severity: string;
  action: string;
  statement: string;
  reason: string;
}

export interface LeaseResult {
  leaseId: string;
  status: "active" | "denied" | "revoked" | "expired";
  expiresAt: number;
  reason?: string;
}

export interface PendingCommand {
  id: string;
  incidentId?: string;
  action: string;
  reason: string;
  requestedAt: number;
  expiresAt: number;
  status: "requested" | "rejected" | "failed";
}

export interface ControlledToolAuthorization {
  authorizationId: string;
  status: "authorized" | "denied";
  leaseId: string;
  expiresAt: number;
  reason?: string;
}

export interface ValidationGateResult {
  allowed: boolean;
  gateId: string;
  eventId: string;
  reason?: string;
  incidentIds: string[];
}

interface StoredResult {
  result: string;
}

interface CountRow {
  count: number;
}

interface ExistingIncident {
  id: string;
}

interface PreviousAudit {
  hash: string;
}

interface BlockingCommand {
  id: string;
  action: string;
  reason: string;
  expires_at: number;
}

interface ExistingLease {
  id: string;
  status: LeaseResult["status"];
  expires_at: number;
  reason: string | null;
}

interface CommandRow extends BlockingCommand {
  incident_id: string | null;
  status: string;
}

interface PendingCommandRow extends CommandRow {
  requested_at: number;
}

interface IncidentStatusRow {
  status: string;
}

interface ControlledToolInvocationRow {
  id: string;
  status: "authorized" | "denied";
  lease_id: string;
  created_at: number;
  expires_at: number | null;
  reason: string | null;
}

interface LeaseScopesRow {
  scopes: string;
}

interface BudgetConfigRow {
  limit_usd: number;
  warning_usd: number;
}

interface BudgetSpendRow {
  total: number | null;
}

export class ProjectGuardrail extends DurableObject<WatchtowerEnv> {
  private db: D1Database;

  constructor(ctx: DurableObjectState, env: WatchtowerEnv) {
    super(ctx, env);
    this.db = env.DB;
  }

  async ingest(input: IngestedEvent): Promise<IngestResult> {
    const { event } = input;
    const existing = await this.db.prepare(
      "SELECT decision AS result FROM operational_events WHERE project_id = ? AND idempotency_key = ?"
    ).bind(event.projectId, event.idempotencyKey).first<StoredResult>();
    if (existing?.result) {
      const previous = JSON.parse(existing.result) as IngestResult;
      return { ...previous, alerts: previous.alerts ?? [], duplicate: true };
    }

    const eventCostUsd = creditCostUsd(event.metadata);
    const [failedRow, chainRow, budgetConfig, budgetSpend] = await Promise.all([
      event.eventType === "validation.failed"
        ? this.db.prepare(
          "SELECT COUNT(*) AS count FROM operational_events WHERE project_id = ? AND agent_id = ? AND event_type = 'validation.failed' AND received_at >= ?"
        ).bind(event.projectId, event.agentId, input.receivedAt - 15 * 60 * 1_000).first<CountRow>()
        : Promise.resolve({ count: 0 }),
      event.eventType === "run.started" && event.chainKey
        ? this.db.prepare(
          "SELECT COUNT(*) AS count FROM operational_events WHERE project_id = ? AND event_type = 'run.started' AND chain_key = ? AND received_at >= ?"
        ).bind(event.projectId, event.chainKey, input.receivedAt - 15 * 60 * 1_000).first<CountRow>()
        : Promise.resolve({ count: 0 }),
      this.db.prepare("SELECT limit_usd, warning_usd FROM project_budgets WHERE project_id = ?").bind(event.projectId).first<BudgetConfigRow>(),
      this.db.prepare("SELECT COALESCE(SUM(amount_usd), 0) AS total FROM budget_ledger WHERE project_id = ?").bind(event.projectId).first<BudgetSpendRow>(),
    ]);

    // Include this event in the values seen by the deterministic rule engine.
    const decisions = evaluateRunawayRules(event, {
      failedAttempts: (failedRow?.count ?? 0) + (event.eventType === "validation.failed" ? 1 : 0),
      matchingChainStarts: (chainRow?.count ?? 0) + (event.eventType === "run.started" && event.chainKey ? 1 : 0),
      projectBudgetUsd: Number(budgetSpend?.total ?? 0) + eventCostUsd,
      budgetLimitUsd: budgetConfig?.limit_usd ?? 10,
      budgetWarningUsd: budgetConfig?.warning_usd ?? 8,
    });
    const incidentIds: string[] = [];
    const alerts: AlertDispatch[] = [];
    const result: IngestResult = { accepted: true, duplicate: false, eventId: event.eventId, incidentIds, decisions, alerts };
    const metadataJson = JSON.stringify(event.metadata);
    const previousAudit = await this.db.prepare(
      "SELECT hash FROM audit_events WHERE project_id = ? ORDER BY sequence DESC LIMIT 1"
    ).bind(event.projectId).first<PreviousAudit>();
    const previousHash = previousAudit?.hash ?? "GENESIS";

    const statements: D1PreparedStatement[] = [
      this.db.prepare(`
        INSERT INTO operational_events (
          id, project_id, event_id, idempotency_key, schema_version, producer_id, agent_id,
          run_id, parent_run_id, chain_key, event_type, severity, statement, metadata,
          occurred_at, received_at, payload_digest, decision
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).bind(
        `${event.projectId}:${event.eventId}`, event.projectId, event.eventId, event.idempotencyKey,
        event.schemaVersion, input.producerId, event.agentId, event.runId ?? null, event.parentRunId ?? null,
        event.chainKey ?? null, event.eventType, event.severity, event.statement, metadataJson,
        Date.parse(event.occurredAt), input.receivedAt, input.payloadDigest, "{}",
      ),
      this.db.prepare(
        "INSERT INTO feed_events (project_id, event_type, agent_id, message, priority, metadata, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)"
      ).bind(event.projectId, event.eventType, event.agentId, event.statement, severityToPriority(event.severity), JSON.stringify({ eventId: event.eventId, runId: event.runId, incidentIds }), input.receivedAt),
    ];

    const sessionStatus = sessionStatusForEvent(event.eventType);
    if (event.runId && sessionStatus) {
      statements.push(this.db.prepare(`
        INSERT INTO agent_sessions (id, project_id, agent_id, run_id, status, started_at, last_heartbeat_at, ended_at, updated_at, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(project_id, agent_id, run_id) DO UPDATE SET
          status = CASE WHEN agent_sessions.status = 'blocked' AND excluded.status = 'active' THEN agent_sessions.status ELSE excluded.status END,
          last_heartbeat_at = COALESCE(excluded.last_heartbeat_at, agent_sessions.last_heartbeat_at),
          ended_at = COALESCE(excluded.ended_at, agent_sessions.ended_at),
          updated_at = excluded.updated_at,
          metadata = excluded.metadata
      `).bind(
        sessionId(event.projectId, event.agentId, event.runId), event.projectId, event.agentId, event.runId,
        sessionStatus, input.receivedAt, event.eventType === "heartbeat" ? input.receivedAt : null,
        ["completed", "failed"].includes(sessionStatus) ? input.receivedAt : null, input.receivedAt,
        JSON.stringify({ lastEventId: event.eventId, lastEventType: event.eventType }),
      ));
    }
    if (eventCostUsd > 0) {
      statements.push(this.db.prepare(`
        INSERT OR IGNORE INTO budget_ledger (id, project_id, agent_id, run_id, operational_event_id, amount_usd, source, recorded_at)
        VALUES (?, ?, ?, ?, ?, ?, 'event.creditCostUsd', ?)
      `).bind(`budget_${event.projectId}_${event.eventId}`, event.projectId, event.agentId, event.runId ?? null, `${event.projectId}:${event.eventId}`, eventCostUsd, input.receivedAt));
    }

    for (const decision of decisions) {
      const dedupeKey = `${decision.ruleId}:${event.agentId}:${event.runId ?? event.chainKey ?? "project"}`;
      const existingIncident = await this.db.prepare(
        "SELECT id FROM incidents WHERE project_id = ? AND dedupe_key = ? AND status IN ('open', 'acknowledged')"
      ).bind(event.projectId, dedupeKey).first<ExistingIncident>();
      const incidentId = existingIncident?.id ?? `inc_${crypto.randomUUID()}`;
      const commandId = `cmd_${crypto.randomUUID()}`;
      if (!existingIncident) {
        statements.push(this.db.prepare(`
          INSERT INTO incidents (id, project_id, dedupe_key, agent_id, run_id, rule_id, severity, status, title, opened_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?)
        `).bind(incidentId, event.projectId, dedupeKey, event.agentId, event.runId ?? null, decision.ruleId, decision.severity, decision.reason, input.receivedAt, input.receivedAt));
        statements.push(this.db.prepare(
          "INSERT INTO incident_transitions (incident_id, from_status, to_status, actor, reason, created_at) VALUES (?, NULL, 'open', ?, ?, ?)"
        ).bind(incidentId, "policy-engine", decision.reason, input.receivedAt));
        const deliveryId = `notify_${crypto.randomUUID()}`;
        const alert: AlertDispatch = {
          deliveryId, projectId: event.projectId, incidentId, eventId: event.eventId,
          agentId: event.agentId, severity: decision.severity, action: decision.action,
          statement: event.statement, reason: decision.reason,
        };
        alerts.push(alert);
        statements.push(this.db.prepare(`
          INSERT INTO notification_deliveries (id, project_id, incident_id, operational_event_id, channel, status, payload, attempts, queued_at)
          VALUES (?, ?, ?, ?, 'webhook', 'queued', ?, 0, ?)
        `).bind(deliveryId, event.projectId, incidentId, `${event.projectId}:${event.eventId}`, JSON.stringify(alert), input.receivedAt));
      } else {
        statements.push(this.db.prepare("UPDATE incidents SET updated_at = ? WHERE id = ?").bind(input.receivedAt, incidentId));
      }
      incidentIds.push(incidentId);
      statements.push(this.db.prepare(
        "INSERT OR IGNORE INTO incident_events (incident_id, operational_event_id, created_at) VALUES (?, ?, ?)"
      ).bind(incidentId, `${event.projectId}:${event.eventId}`, input.receivedAt));
      statements.push(this.db.prepare(`
        INSERT INTO control_commands (id, project_id, incident_id, agent_id, action, mode, status, requested_at, expires_at, reason)
        VALUES (?, ?, ?, ?, ?, 'cooperative', 'requested', ?, ?, ?)
      `).bind(commandId, event.projectId, incidentId, event.agentId, decision.action, input.receivedAt, input.receivedAt + 15 * 60 * 1_000, decision.reason));
    }

    // The audit hash includes the event digest and decision result; the DO serializes each project chain.
    // Re-serialize now that incident IDs are known; duplicate retries must return the exact first result.
    const finalized = { ...result, incidentIds };
    const finalizedJson = stableJson(finalized);
    const auditHash = await sha256Hex(`${previousHash}:${input.payloadDigest}:${finalizedJson}`);
    statements[1] = this.db.prepare(
      "INSERT INTO feed_events (project_id, event_type, agent_id, message, priority, metadata, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)"
    ).bind(event.projectId, event.eventType, event.agentId, event.statement, severityToPriority(event.severity), JSON.stringify({ eventId: event.eventId, runId: event.runId, incidentIds }), input.receivedAt);
    statements.push(this.db.prepare(
      "INSERT INTO audit_events (id, project_id, operational_event_id, previous_hash, hash, decision, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
    ).bind(`audit_${crypto.randomUUID()}`, event.projectId, `${event.projectId}:${event.eventId}`, previousHash, auditHash, finalizedJson, input.receivedAt));
    statements[0] = this.db.prepare(`
      INSERT INTO operational_events (
        id, project_id, event_id, idempotency_key, schema_version, producer_id, agent_id,
        run_id, parent_run_id, chain_key, event_type, severity, statement, metadata,
        occurred_at, received_at, payload_digest, decision
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      `${event.projectId}:${event.eventId}`, event.projectId, event.eventId, event.idempotencyKey,
      event.schemaVersion, input.producerId, event.agentId, event.runId ?? null, event.parentRunId ?? null,
      event.chainKey ?? null, event.eventType, event.severity, event.statement, metadataJson,
      Date.parse(event.occurredAt), input.receivedAt, input.payloadDigest, finalizedJson,
    );
    await this.db.batch(statements);
    return finalized;
  }

  async requestLease(request: LeaseRequest, producerId: string, now = Date.now()): Promise<LeaseResult> {
    const existing = await this.db.prepare(`
      SELECT id, status, expires_at, reason FROM work_leases
      WHERE project_id = ? AND agent_id = ? AND run_id = ? AND status = 'active' AND expires_at > ?
      ORDER BY issued_at DESC LIMIT 1
    `).bind(request.projectId, request.agentId, request.runId, now).first<ExistingLease>();
    if (existing) return this.validateLease(request.projectId, existing.id, request.agentId, now);

    const blocking = await this.getBlockingCommand(request.projectId, request.agentId, now);
    const leaseId = `lease_${crypto.randomUUID()}`;
    const expiresAt = now + request.ttlSeconds * 1_000;
    const status: LeaseResult["status"] = blocking ? "denied" : "active";
    const reason = blocking ? `${blocking.action}: ${blocking.reason}` : undefined;
    await this.db.batch([
      this.db.prepare(`
        INSERT INTO work_leases (id, project_id, agent_id, run_id, producer_id, scopes, status, reason, issued_at, expires_at, command_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).bind(leaseId, request.projectId, request.agentId, request.runId, producerId, JSON.stringify(request.scopes), status, reason ?? null, now, expiresAt, blocking?.id ?? null),
      this.db.prepare(`
        INSERT INTO agent_sessions (id, project_id, agent_id, run_id, lease_id, status, control_state, started_at, updated_at, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(project_id, agent_id, run_id) DO UPDATE SET
          lease_id = excluded.lease_id, status = excluded.status, control_state = excluded.control_state,
          updated_at = excluded.updated_at, metadata = excluded.metadata
      `).bind(
        sessionId(request.projectId, request.agentId, request.runId), request.projectId, request.agentId, request.runId,
        leaseId, status === "active" ? "active" : "blocked", reason ?? null, now, now,
        JSON.stringify({ leaseScopes: request.scopes, leaseStatus: status }),
      ),
    ]);
    return { leaseId, status, expiresAt, reason };
  }

  async validateLease(projectId: string, leaseId: string, agentId: string, now = Date.now()): Promise<LeaseResult> {
    const lease = await this.db.prepare(`
      SELECT id, status, expires_at, reason FROM work_leases WHERE id = ? AND project_id = ? AND agent_id = ?
    `).bind(leaseId, projectId, agentId).first<ExistingLease>();
    if (!lease) return { leaseId, status: "denied", expiresAt: now, reason: "lease not found" };
    if (lease.status !== "active") return { leaseId, status: lease.status, expiresAt: lease.expires_at, reason: lease.reason ?? undefined };
    if (lease.expires_at <= now) {
      await this.db.prepare("UPDATE work_leases SET status = 'expired', reason = 'lease expired' WHERE id = ?").bind(leaseId).run();
      await this.db.prepare("UPDATE agent_sessions SET status = 'blocked', control_state = 'lease expired', updated_at = ? WHERE project_id = ? AND agent_id = ? AND lease_id = ?").bind(now, projectId, agentId, leaseId).run();
      return { leaseId, status: "expired", expiresAt: lease.expires_at, reason: "lease expired" };
    }
    const blocking = await this.getBlockingCommand(projectId, agentId, now);
    if (blocking) {
      const reason = `${blocking.action}: ${blocking.reason}`;
      await this.db.prepare("UPDATE work_leases SET status = 'revoked', reason = ?, command_id = ? WHERE id = ?").bind(reason, blocking.id, leaseId).run();
      await this.db.prepare("UPDATE agent_sessions SET status = 'blocked', control_state = ?, updated_at = ? WHERE project_id = ? AND agent_id = ? AND lease_id = ?").bind(reason, now, projectId, agentId, leaseId).run();
      return { leaseId, status: "revoked", expiresAt: lease.expires_at, reason };
    }
    return { leaseId, status: "active", expiresAt: lease.expires_at, reason: lease.reason ?? undefined };
  }

  async getPendingCommands(projectId: string, agentId: string, now = Date.now()): Promise<PendingCommand[]> {
    const rows = await this.db.prepare(`
      SELECT id, incident_id, action, reason, requested_at, expires_at, status
      FROM control_commands WHERE project_id = ? AND agent_id = ? AND status IN ('requested', 'rejected', 'failed') AND expires_at > ?
      ORDER BY requested_at ASC LIMIT 20
    `).bind(projectId, agentId, now).all<PendingCommandRow>();
    return rows.results.map(row => ({
      id: row.id, incidentId: row.incident_id ?? undefined, action: row.action,
      reason: row.reason, requestedAt: row.requested_at, expiresAt: row.expires_at,
      status: row.status as PendingCommand["status"],
    }));
  }

  async acknowledgeCommand(projectId: string, acknowledgement: CommandAcknowledgement, now = Date.now()): Promise<{ success: boolean; status: string }> {
    const command = await this.db.prepare(`
      SELECT id, incident_id, action, reason, expires_at, status FROM control_commands
      WHERE id = ? AND project_id = ? AND agent_id = ?
    `).bind(acknowledgement.commandId, projectId, acknowledgement.agentId).first<CommandRow>();
    if (!command) return { success: false, status: "not_found" };
    if (command.status === "acknowledged") return { success: true, status: command.status };
    const status = acknowledgement.outcome === "contained" ? "acknowledged" : acknowledgement.outcome;
    const statements: D1PreparedStatement[] = [
      this.db.prepare("UPDATE control_commands SET status = ?, acknowledged_at = ? WHERE id = ?").bind(status, now, command.id),
      this.db.prepare(`
        INSERT INTO control_command_receipts (id, command_id, project_id, agent_id, outcome, note, received_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).bind(`receipt_${crypto.randomUUID()}`, command.id, projectId, acknowledgement.agentId, acknowledgement.outcome, acknowledgement.note ?? null, now),
    ];
    if (acknowledgement.outcome === "contained" && command.incident_id) {
      const incident = await this.db.prepare("SELECT status FROM incidents WHERE id = ?").bind(command.incident_id).first<IncidentStatusRow>();
      if (incident && (incident.status === "open" || incident.status === "acknowledged")) {
        statements.push(
          this.db.prepare("UPDATE incidents SET status = 'contained', updated_at = ? WHERE id = ?").bind(now, command.incident_id),
          this.db.prepare("INSERT INTO incident_transitions (incident_id, from_status, to_status, actor, reason, created_at) VALUES (?, ?, 'contained', ?, ?, ?)").bind(command.incident_id, incident.status, acknowledgement.agentId, acknowledgement.note ?? command.reason, now),
        );
      }
    }
    await this.db.batch(statements);
    return { success: true, status };
  }

  async authorizeControlledTool(
    request: ControlledToolAuthorizationRequest,
    producerId: string,
    orgId?: string,
    now = Date.now(),
  ): Promise<ControlledToolAuthorization> {
    const existing = await this.db.prepare(`
      SELECT i.id, i.status, i.lease_id, i.created_at, i.reason, l.expires_at
      FROM controlled_tool_invocations i LEFT JOIN work_leases l ON l.id = i.lease_id
      WHERE i.project_id = ? AND i.request_id = ?
    `).bind(request.projectId, request.requestId).first<ControlledToolInvocationRow>();
    if (existing) {
      return {
        authorizationId: existing.id, status: existing.status, leaseId: existing.lease_id,
        expiresAt: existing.expires_at ?? existing.created_at, reason: existing.reason ?? undefined,
      };
    }

    const lease = await this.validateLease(request.projectId, request.leaseId, request.agentId, now);
    let status: ControlledToolAuthorization["status"] = lease.status === "active" ? "authorized" : "denied";
    let reason = lease.reason;
    if (status === "authorized") {
      const scopeRow = await this.db.prepare(`
        SELECT scopes FROM work_leases WHERE id = ? AND project_id = ? AND agent_id = ?
      `).bind(request.leaseId, request.projectId, request.agentId).first<LeaseScopesRow>();
      const scopes = parseScopes(scopeRow?.scopes);
      const allowed = scopes.includes("*") || scopes.includes(request.toolName) || scopes.includes(request.action)
        || scopes.includes(`tool:${request.toolName}`) || scopes.includes(`action:${request.action}`);
      if (!allowed) {
        status = "denied";
        reason = `lease does not grant ${request.toolName} or ${request.action}`;
      }
    }

    const authorizationId = `tool_${crypto.randomUUID()}`;
    const eventHash = (await sha256Hex(`${request.projectId}:${request.requestId}`)).slice(0, 40);
    const eventId = `evt-tool-${eventHash}`;
    const event: OperationalEvent = {
      schemaVersion: "2026-07-17",
      eventId,
      idempotencyKey: `tool-gate-${eventHash}`,
      projectId: request.projectId,
      agentId: request.agentId,
      eventType: status === "authorized" ? "tool.authorized" : "tool.denied",
      severity: status === "authorized" ? "info" : "warning",
      occurredAt: new Date(now).toISOString(),
      statement: status === "authorized"
        ? `Watchtower authorized ${request.toolName}:${request.action}.`
        : `Watchtower denied ${request.toolName}:${request.action}.`,
      metadata: {
        toolName: request.toolName, action: request.action, requestId: request.requestId,
        leaseId: request.leaseId, inputDigest: request.inputDigest, reason: reason ?? null,
      },
    };
    const payload = stableJson(event);
    await this.ingest({ event, producerId, payloadDigest: await sha256Hex(payload), receivedAt: now });
    await this.db.prepare(`
      INSERT INTO controlled_tool_invocations (
        id, project_id, org_id, producer_id, agent_id, lease_id, tool_name, action,
        request_id, input_digest, status, reason, operational_event_id, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      authorizationId, request.projectId, orgId ?? null, producerId, request.agentId, request.leaseId,
      request.toolName, request.action, request.requestId, request.inputDigest, status, reason ?? null,
      `${request.projectId}:${eventId}`, now,
    ).run();
    if (status === "denied") {
      await this.db.prepare("UPDATE agent_sessions SET status = 'blocked', control_state = ?, updated_at = ? WHERE project_id = ? AND agent_id = ? AND lease_id = ?")
        .bind(reason ?? "controlled tool authorization denied", now, request.projectId, request.agentId, request.leaseId).run();
    }
    return { authorizationId, status, leaseId: request.leaseId, expiresAt: lease.expiresAt, reason };
  }

  async getControlledToolInvocations(limit = 50): Promise<unknown[]> {
    const rows = await this.db.prepare(`
      SELECT id, org_id AS orgId, producer_id AS producerId, agent_id AS agentId, lease_id AS leaseId,
        tool_name AS toolName, action, request_id AS requestId, input_digest AS inputDigest,
        status, reason, operational_event_id AS operationalEventId, created_at AS createdAt
      FROM controlled_tool_invocations WHERE project_id = ? ORDER BY created_at DESC LIMIT ?
    `).bind(this.ctx.id.name, Math.min(Math.max(limit, 1), 100)).all();
    return rows.results;
  }

  async transitionIncident(
    projectId: string,
    incidentId: string,
    action: "acknowledge" | "resolve" | "dismiss",
    actor: string,
    reason: string,
    now = Date.now(),
  ): Promise<{ success: boolean; status: string; error?: string }> {
    const incident = await this.db.prepare("SELECT status FROM incidents WHERE id = ? AND project_id = ?").bind(incidentId, projectId).first<IncidentStatusRow>();
    if (!incident) return { success: false, status: "not_found", error: "incident not found" };
    const next = action === "acknowledge" ? "acknowledged" : action === "resolve" ? "resolved" : "dismissed";
    const allowed = (action === "acknowledge" && incident.status === "open")
      || (action === "resolve" && incident.status === "contained")
      || (action === "dismiss" && ["open", "acknowledged", "contained"].includes(incident.status));
    if (!allowed) return { success: false, status: incident.status, error: `cannot ${action} an incident in ${incident.status}` };
    await this.db.batch([
      this.db.prepare("UPDATE incidents SET status = ?, updated_at = ?, acknowledged_at = CASE WHEN ? = 'acknowledged' THEN ? ELSE acknowledged_at END, resolved_at = CASE WHEN ? IN ('resolved', 'dismissed') THEN ? ELSE resolved_at END WHERE id = ?")
        .bind(next, now, next, now, next, now, incidentId),
      this.db.prepare("INSERT INTO incident_transitions (incident_id, from_status, to_status, actor, reason, created_at) VALUES (?, ?, ?, ?, ?, ?)")
        .bind(incidentId, incident.status, next, actor, reason, now),
    ]);
    return { success: true, status: next };
  }

  async evaluateValidationGate(request: ValidationGateRequest, producerId: string, now = Date.now()): Promise<ValidationGateResult> {
    const eventHash = (await sha256Hex(`${request.projectId}:${request.requestId}`)).slice(0, 40);
    const eventId = `evt-gate-${eventHash}`;
    const event: OperationalEvent = {
      schemaVersion: "2026-07-17", eventId, idempotencyKey: `validation-gate-${eventHash}`,
      projectId: request.projectId, agentId: request.agentId, runId: request.runId,
      eventType: request.passed ? "validation.passed" : "validation.failed",
      severity: request.passed ? "success" : "error", occurredAt: new Date(now).toISOString(),
      statement: request.statement, metadata: { ...request.metadata, gateId: request.gateId, requestId: request.requestId },
    };
    const payload = stableJson(event);
    const ingest = await this.ingest({ event, producerId, payloadDigest: await sha256Hex(payload), receivedAt: now });
    if (!request.passed) {
      const reason = `validation gate ${request.gateId} failed`;
      const statements: D1PreparedStatement[] = [
        this.db.prepare("UPDATE agent_sessions SET status = 'blocked', control_state = ?, updated_at = ? WHERE project_id = ? AND agent_id = ? AND run_id = ?")
          .bind(reason, now, request.projectId, request.agentId, request.runId),
      ];
      if (request.leaseId) {
        statements.push(this.db.prepare("UPDATE work_leases SET status = 'revoked', reason = ? WHERE id = ? AND project_id = ? AND agent_id = ? AND status = 'active'")
          .bind(reason, request.leaseId, request.projectId, request.agentId));
      }
      await this.db.batch(statements);
      return { allowed: false, gateId: request.gateId, eventId, reason: "validation gate failed", incidentIds: ingest.incidentIds };
    }
    if (!request.leaseId) {
      await this.db.prepare("UPDATE agent_sessions SET status = 'blocked', control_state = 'validation passed but no lease is present', updated_at = ? WHERE project_id = ? AND agent_id = ? AND run_id = ?")
        .bind(now, request.projectId, request.agentId, request.runId).run();
      return { allowed: false, gateId: request.gateId, eventId, reason: "validation passed but an active lease is required", incidentIds: ingest.incidentIds };
    }
    const lease = await this.validateLease(request.projectId, request.leaseId, request.agentId, now);
    if (lease.status !== "active") {
      await this.db.prepare("UPDATE agent_sessions SET status = 'blocked', control_state = ?, updated_at = ? WHERE project_id = ? AND agent_id = ? AND run_id = ?")
        .bind(lease.reason ?? `lease is ${lease.status}`, now, request.projectId, request.agentId, request.runId).run();
      return { allowed: false, gateId: request.gateId, eventId, reason: lease.reason ?? `lease is ${lease.status}`, incidentIds: ingest.incidentIds };
    }
    return { allowed: true, gateId: request.gateId, eventId, incidentIds: ingest.incidentIds };
  }

  async getSessions(limit = 100): Promise<unknown[]> {
    const rows = await this.db.prepare(`
      SELECT id, agent_id AS agentId, run_id AS runId, lease_id AS leaseId, status, control_state AS controlState,
        started_at AS startedAt, last_heartbeat_at AS lastHeartbeatAt, ended_at AS endedAt, updated_at AS updatedAt, metadata
      FROM agent_sessions WHERE project_id = ? ORDER BY updated_at DESC LIMIT ?
    `).bind(this.ctx.id.name, Math.min(Math.max(limit, 1), 200)).all();
    return rows.results;
  }

  async getBudget(): Promise<{ limitUsd: number; warningUsd: number; spentUsd: number; remainingUsd: number }> {
    const [config, spent] = await Promise.all([
      this.db.prepare("SELECT limit_usd, warning_usd FROM project_budgets WHERE project_id = ?").bind(this.ctx.id.name).first<BudgetConfigRow>(),
      this.db.prepare("SELECT COALESCE(SUM(amount_usd), 0) AS total FROM budget_ledger WHERE project_id = ?").bind(this.ctx.id.name).first<BudgetSpendRow>(),
    ]);
    const limitUsd = config?.limit_usd ?? 10;
    const warningUsd = config?.warning_usd ?? 8;
    const spentUsd = Number(spent?.total ?? 0);
    return { limitUsd, warningUsd, spentUsd, remainingUsd: Math.max(0, limitUsd - spentUsd) };
  }

  async setBudget(projectId: string, budget: { limitUsd: number; warningUsd: number }, actor: string, now = Date.now()): Promise<void> {
    await this.db.prepare(`
      INSERT INTO project_budgets (project_id, limit_usd, warning_usd, updated_by, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(project_id) DO UPDATE SET limit_usd = excluded.limit_usd, warning_usd = excluded.warning_usd, updated_by = excluded.updated_by, updated_at = excluded.updated_at
    `).bind(projectId, budget.limitUsd, budget.warningUsd, actor, now).run();
  }

  async raiseHeartbeatMissed(input: { projectId: string; agentId: string; deadlineAt: number }): Promise<IngestResult> {
    const occurredAt = new Date(input.deadlineAt).toISOString();
    const event: OperationalEvent = {
      schemaVersion: "2026-07-17", eventId: `evt-heartbeat-${input.agentId}-${input.deadlineAt}`,
      idempotencyKey: `heartbeat-missed-${input.agentId}-${input.deadlineAt}`,
      projectId: input.projectId, agentId: input.agentId, eventType: "heartbeat.missed", severity: "warning",
      occurredAt, statement: "Agent missed its Watchtower heartbeat deadline.", metadata: { deadlineAt: input.deadlineAt },
    };
    const payload = stableJson(event);
    return this.ingest({ event, producerId: "watchtower-watchdog", payloadDigest: await sha256Hex(payload), receivedAt: Date.now() });
  }

  async getIncidents(limit = 50): Promise<unknown[]> {
    const rows = await this.db.prepare(`
      SELECT id, project_id AS projectId, agent_id AS agentId, run_id AS runId, rule_id AS ruleId,
        severity, status, title, opened_at AS openedAt, acknowledged_at AS acknowledgedAt,
        resolved_at AS resolvedAt, updated_at AS updatedAt
      FROM incidents WHERE project_id = ? ORDER BY updated_at DESC LIMIT ?
    `).bind(this.ctx.id.name, Math.min(Math.max(limit, 1), 100)).all();
    return rows.results;
  }

  async updateNotification(deliveryId: string, status: "delivered" | "retrying" | "suppressed" | "failed", detail?: string, now = Date.now()): Promise<void> {
    await this.db.prepare(`
      UPDATE notification_deliveries
      SET status = ?, attempts = attempts + 1, completed_at = CASE WHEN ? IN ('delivered', 'suppressed', 'failed') THEN ? ELSE completed_at END, last_error = ?
      WHERE id = ?
    `).bind(status, status, now, detail ?? null, deliveryId).run();
  }

  private async getBlockingCommand(projectId: string, agentId: string, now: number): Promise<BlockingCommand | null> {
    return this.db.prepare(`
      SELECT id, action, reason, expires_at FROM control_commands
      WHERE project_id = ? AND agent_id = ? AND status IN ('requested', 'rejected', 'failed') AND expires_at > ?
        AND action IN ('require_approval', 'pause', 'quarantine', 'deny')
      ORDER BY requested_at ASC LIMIT 1
    `).bind(projectId, agentId, now).first<BlockingCommand>();
  }
}

function parseScopes(value: string | undefined): string[] {
  try {
    const parsed = JSON.parse(value || "[]");
    return Array.isArray(parsed) ? parsed.filter((scope): scope is string => typeof scope === "string") : [];
  } catch {
    return [];
  }
}

function creditCostUsd(metadata: Record<string, unknown>): number {
  const value = metadata.creditCostUsd;
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 100_000 ? value : 0;
}

function sessionStatusForEvent(eventType: string): "active" | "completed" | "failed" | null {
  if (eventType === "run.started" || eventType === "heartbeat") return "active";
  if (eventType === "run.completed") return "completed";
  if (eventType === "run.failed") return "failed";
  return null;
}

function sessionId(projectId: string, agentId: string, runId: string): string {
  return `session:${projectId}:${agentId}:${runId}`;
}
