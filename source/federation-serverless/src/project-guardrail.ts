import { DurableObject } from "cloudflare:workers";
import type { WatchtowerEnv } from "./agent-registry";
import { evaluateRunawayRules, type GuardrailDecision, type OperationalEvent, severityToPriority, sha256Hex, stableJson } from "./watchtower";

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
    if (existing?.result) return { ...JSON.parse(existing.result) as IngestResult, duplicate: true };

    const [failedRow, chainRow] = await Promise.all([
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
    ]);

    // Include this event in the values seen by the deterministic rule engine.
    const decisions = evaluateRunawayRules(event, {
      failedAttempts: (failedRow?.count ?? 0) + (event.eventType === "validation.failed" ? 1 : 0),
      matchingChainStarts: (chainRow?.count ?? 0) + (event.eventType === "run.started" && event.chainKey ? 1 : 0),
    });
    const incidentIds: string[] = [];
    const result: IngestResult = { accepted: true, duplicate: false, eventId: event.eventId, incidentIds, decisions };
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

    for (const decision of decisions) {
      const dedupeKey = `${decision.ruleId}:${event.agentId}:${event.runId ?? event.chainKey ?? "project"}`;
      const existingIncident = await this.db.prepare(
        "SELECT id FROM incidents WHERE project_id = ? AND dedupe_key = ? AND status IN ('open', 'acknowledged', 'contained')"
      ).bind(event.projectId, dedupeKey).first<ExistingIncident>();
      const incidentId = existingIncident?.id ?? `inc_${crypto.randomUUID()}`;
      if (!existingIncident) {
        statements.push(this.db.prepare(`
          INSERT INTO incidents (id, project_id, dedupe_key, agent_id, run_id, rule_id, severity, status, title, opened_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?)
        `).bind(incidentId, event.projectId, dedupeKey, event.agentId, event.runId ?? null, decision.ruleId, decision.severity, decision.reason, input.receivedAt, input.receivedAt));
        statements.push(this.db.prepare(
          "INSERT INTO incident_transitions (incident_id, from_status, to_status, actor, reason, created_at) VALUES (?, NULL, 'open', ?, ?, ?)"
        ).bind(incidentId, "policy-engine", decision.reason, input.receivedAt));
      } else {
        statements.push(this.db.prepare("UPDATE incidents SET updated_at = ? WHERE id = ?").bind(input.receivedAt, incidentId));
      }
      incidentIds.push(incidentId);
      statements.push(this.db.prepare(
        "INSERT OR IGNORE INTO incident_events (incident_id, operational_event_id, created_at) VALUES (?, ?, ?)"
      ).bind(incidentId, `${event.projectId}:${event.eventId}`, input.receivedAt));
      statements.push(this.db.prepare(`
        INSERT INTO control_commands (id, project_id, incident_id, agent_id, action, mode, status, requested_at, expires_at, reason)
        VALUES (?, ?, ?, ?, ?, 'advisory', 'requested', ?, ?, ?)
      `).bind(`cmd_${crypto.randomUUID()}`, event.projectId, incidentId, event.agentId, decision.action, input.receivedAt, input.receivedAt + 15 * 60 * 1_000, decision.reason));
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

  async getIncidents(limit = 50): Promise<unknown[]> {
    const rows = await this.db.prepare(`
      SELECT id, project_id AS projectId, agent_id AS agentId, run_id AS runId, rule_id AS ruleId,
        severity, status, title, opened_at AS openedAt, acknowledged_at AS acknowledgedAt,
        resolved_at AS resolvedAt, updated_at AS updatedAt
      FROM incidents WHERE project_id = ? ORDER BY updated_at DESC LIMIT ?
    `).bind(this.ctx.id.name, Math.min(Math.max(limit, 1), 100)).all();
    return rows.results;
  }
}
