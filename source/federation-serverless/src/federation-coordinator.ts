import { DurableObject } from "cloudflare:workers";
import type { WatchtowerEnv } from "./agent-registry";
import { evaluateRunawayRules, sha256Hex, stableJson, type OperationalEvent } from "./watchtower";

export interface ProjectSummary {
  projectId: string; name: string; track: string; color: string; emoji: string; prefix: string;
  agentCount: number; roomCount: number; activeAgents: number; lastActivity: number;
}

export interface SystemStatus {
  totalProjects: number; totalAgents: number; totalRooms: number; healthyProjects: number; timestamp: number;
}

export interface SearchResult {
  agents: Array<{ projectId: string; agentId: string; name: string; role?: string }>;
  rooms: Array<{ projectId: string; roomId: string; capacity: number; used: number }>;
}

export interface FeedEvent {
  id?: number; projectId: string; eventType: string; agentId?: string; message: string;
  priority: 'low' | 'normal' | 'high' | 'critical'; metadata?: Record<string, unknown>; timestamp: number;
}

// Federation verification types
export interface FederationApplication {
  id?: number;
  federationId: string; name: string; orgEmail: string; officialRepo: string;
  socialProfiles: string; techQuestions: string;
  status: 'submitted' | 'under_review' | 'approved' | 'rejected';
  submittedAt: number; reviewedAt?: number; reviewedBy?: string; reviewNotes?: string;
}

export interface VerifiedFederation {
  id: string; name: string; orgEmail: string; officialRepo: string;
  socialProfiles: string; status: 'pending' | 'verified' | 'rejected' | 'suspended';
  reviewNotes?: string; reviewedBy?: string; reviewedAt?: number;
  createdAt: number; updatedAt: number;
}

export interface FederationSpeechLine {
  id?: number; federationId: string; agentId: string; projectId: string;
  statement: string; isUnique: boolean; submittedAt: number;
}

export interface MCPOrg {
  id: string; name: string; contactEmail: string; apiKeyHash: string;
  scopes: string; rateLimit: number; ipAllowlist: string;
  status: 'active' | 'suspended' | 'revoked'; createdAt: number; lastAccessAt?: number; metadata: string;
}

interface OperationalEventRow {
  schema_version: string;
  event_id: string;
  idempotency_key: string;
  project_id: string;
  agent_id: string;
  run_id: string | null;
  parent_run_id: string | null;
  chain_key: string | null;
  event_type: string;
  severity: OperationalEvent["severity"];
  statement: string;
  metadata: string;
  occurred_at: number;
  received_at: number;
}

export class FederationCoordinator extends DurableObject<WatchtowerEnv> {
  private db: D1Database;

  constructor(ctx: DurableObjectState, env: WatchtowerEnv) { super(ctx, env); this.db = env.DB; }

  async getProjects(): Promise<ProjectSummary[]> {
    const projects = await this.db.prepare(`SELECT * FROM projects ORDER BY id`).all<any>();
    const summaries: ProjectSummary[] = [];
    for (const p of projects.results) {
      const [agentCount, roomCount, activeCount, lastEvent] = await Promise.all([
        this.db.prepare(`SELECT COUNT(*) as cnt FROM agents WHERE project_id = ?`).bind(p.id).first<{ cnt: number }>(),
        this.db.prepare(`SELECT COUNT(*) as cnt FROM rooms WHERE project_id = ?`).bind(p.id).first<{ cnt: number }>(),
        this.db.prepare(`SELECT COUNT(*) as cnt FROM agents WHERE project_id = ? AND status = 'active'`).bind(p.id).first<{ cnt: number }>(),
        this.db.prepare(`SELECT timestamp FROM feed_events WHERE project_id = ? ORDER BY timestamp DESC LIMIT 1`).bind(p.id).first<{ timestamp: number }>(),
      ]);
      summaries.push({
        projectId: p.id, name: p.name, track: p.track, color: p.color, emoji: p.emoji, prefix: p.prefix,
        agentCount: agentCount?.cnt || 0, roomCount: roomCount?.cnt || 0, activeAgents: activeCount?.cnt || 0,
        lastActivity: lastEvent?.timestamp || 0,
      });
    }
    return summaries;
  }

  async getProjectSummary(projectId: string): Promise<ProjectSummary | null> {
    const p = await this.db.prepare(`SELECT * FROM projects WHERE id = ?`).bind(projectId).first<any>();
    if (!p) return null;
    const [agentCount, roomCount, activeCount, lastEvent] = await Promise.all([
      this.db.prepare(`SELECT COUNT(*) as cnt FROM agents WHERE project_id = ?`).bind(projectId).first<{ cnt: number }>(),
      this.db.prepare(`SELECT COUNT(*) as cnt FROM rooms WHERE project_id = ?`).bind(projectId).first<{ cnt: number }>(),
      this.db.prepare(`SELECT COUNT(*) as cnt FROM agents WHERE project_id = ? AND status = 'active'`).bind(projectId).first<{ cnt: number }>(),
      this.db.prepare(`SELECT timestamp FROM feed_events WHERE project_id = ? ORDER BY timestamp DESC LIMIT 1`).bind(projectId).first<{ timestamp: number }>(),
    ]);
    return { projectId: p.id, name: p.name, track: p.track, color: p.color, emoji: p.emoji, prefix: p.prefix,
      agentCount: agentCount?.cnt || 0, roomCount: roomCount?.cnt || 0, activeAgents: activeCount?.cnt || 0,
      lastActivity: lastEvent?.timestamp || 0 };
  }

  async getSystemStatus(): Promise<SystemStatus> {
    const [projects, totalAgents, totalRooms] = await Promise.all([
      this.db.prepare(`SELECT COUNT(*) as cnt FROM projects`).first<{ cnt: number }>(),
      this.db.prepare(`SELECT COUNT(*) as cnt FROM agents`).first<{ cnt: number }>(),
      this.db.prepare(`SELECT COUNT(*) as cnt FROM rooms`).first<{ cnt: number }>(),
    ]);
    let healthyProjects = 0;
    const projectList = await this.db.prepare(`SELECT id FROM projects`).all<{ id: string }>();
    for (const p of projectList.results) {
      try {
        const registryId = this.env.AGENT_REGISTRY.idFromName(`${p.id}-registry`);
        const stub = this.env.AGENT_REGISTRY.get(registryId);
        const health = await stub.healthCheck() as { healthy: boolean; agents: number; rooms: number };
        if (health.healthy) healthyProjects++;
      } catch {}
    }
    return { totalProjects: projects?.cnt || 0, totalAgents: totalAgents?.cnt || 0, totalRooms: totalRooms?.cnt || 0, healthyProjects, timestamp: Date.now() };
  }

  async searchAgents(query: string, limit = 20): Promise<SearchResult> {
    const lowerQuery = query.toLowerCase();
    const agentRows = await this.db.prepare(`
      SELECT project_id, agent_id, name, role FROM agents
      WHERE LOWER(name) LIKE ? OR LOWER(agent_id) LIKE ? OR LOWER(role) LIKE ?
      LIMIT ?`).bind(`%${lowerQuery}%`, `%${lowerQuery}%`, `%${lowerQuery}%`, limit).all<{ project_id: string; agent_id: string; name: string; role: string | null }>();
    const roomRows = await this.db.prepare(`
      SELECT r.project_id, r.id, r.capacity, (SELECT COUNT(*) FROM agents WHERE room_id = r.id) as used
      FROM rooms r WHERE r.project_id IN (SELECT DISTINCT project_id FROM agents WHERE LOWER(name) LIKE ? OR LOWER(agent_id) LIKE ?) LIMIT ?`).bind(`%${lowerQuery}%`, `%${lowerQuery}%`, limit).all<{ project_id: string; id: string; capacity: number; used: number }>();
    return { agents: agentRows.results.map(r => ({ projectId: r.project_id, agentId: r.agent_id, name: r.name, role: r.role || undefined })), rooms: roomRows.results.map(r => ({ projectId: r.project_id, roomId: r.id, capacity: r.capacity, used: r.used })) };
  }

  async registerProject(config: { id: string; name: string; track: string; color: string; emoji: string; prefix: string }): Promise<void> {
    const now = Date.now();
    await this.db.prepare(`INSERT OR REPLACE INTO projects (id, name, track, color, emoji, prefix, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).bind(config.id, config.name, config.track, config.color, config.emoji, config.prefix, now, now).run();
    const registryId = this.env.AGENT_REGISTRY.idFromName(`${config.id}-registry`);
    const stub = this.env.AGENT_REGISTRY.get(registryId);
    await stub.initialize();
  }

  async getGlobalFeed(limit = 100): Promise<Array<FeedEvent & { projectName: string }>> {
    const rows = await this.db.prepare(`SELECT fe.*, p.name as project_name FROM feed_events fe JOIN projects p ON fe.project_id = p.id ORDER BY fe.timestamp DESC LIMIT ?`).bind(limit).all<{ id: number; project_id: string; project_name: string; event_type: string; agent_id: string | null; message: string; priority: string; metadata: string; timestamp: number }>();
    return rows.results.map(r => ({ id: r.id, projectId: r.project_id, projectName: r.project_name, eventType: r.event_type, agentId: r.agent_id || undefined, message: r.message, priority: r.priority as FeedEvent['priority'], metadata: JSON.parse(r.metadata || '{}'), timestamp: r.timestamp }));
  }

  async getAllRooms(): Promise<any[]> {
    const rows = await this.db.prepare(`SELECT r.*, p.name as project_name, p.color as project_color, p.emoji as project_emoji, (SELECT COUNT(*) FROM agents WHERE room_id = r.id) as used FROM rooms r JOIN projects p ON r.project_id = p.id ORDER BY p.id, r.room_index`).all();
    return rows.results as any[];
  }

  async healthCheckAll(): Promise<{ healthy: boolean; details: Record<string, any> }> {
    const projects = await this.db.prepare(`SELECT id FROM projects`).all<any>();
    const details: Record<string, any> = {}; let allHealthy = true;
    for (const project of projects.results) {
      try {
        const registryId = this.env.AGENT_REGISTRY.idFromName(`${project.id}-registry`);
        const registryStub = this.env.AGENT_REGISTRY.get(registryId);
        const health = await registryStub.healthCheck() as { healthy: boolean; agents: number; rooms: number };
        details[project.id] = health; if (!health.healthy) allHealthy = false;
      } catch (e) { details[project.id] = { healthy: false, error: String(e) }; allHealthy = false; }
    }
    return { healthy: allHealthy, details };
  }

  // ============================================================
  // FEDERATION VERIFICATION ENDPOINTS
  // ============================================================

  // Submit federation application
  async submitFederationApplication(data: {
    federationId: string; name: string; orgEmail: string; officialRepo: string;
    socialProfiles: Array<{ platform: string; url: string }>;
    techQuestions: Array<{ question: string; answer: string }>;
  }): Promise<{ success: boolean; application?: FederationApplication; error?: string }> {
    // Validate: min 2 social profiles beyond GitHub
    const nonGithub = data.socialProfiles.filter(p => p.platform.toLowerCase() !== 'github');
    if (nonGithub.length < 2) {
      return { success: false, error: 'Must provide at least 2 social profiles beyond GitHub (e.g., Twitter, LinkedIn, Discord)' };
    }
    // Validate: exactly 5 tech questions
    if (data.techQuestions.length !== 5) {
      return { success: false, error: 'Must provide exactly 5 comical technical questions' };
    }
    // Check for existing
    const existing = await this.db.prepare(`SELECT id FROM federation_applications WHERE federation_id = ? OR org_email = ?`).bind(data.federationId, data.orgEmail).first();
    if (existing) {
      return { success: false, error: 'Application already exists for this federation ID or email' };
    }
    // Check if already verified
    const verified = await this.db.prepare(`SELECT id FROM verified_federations WHERE id = ?`).bind(data.federationId).first();
    if (verified) {
      return { success: false, error: 'Federation already verified' };
    }

    const now = Date.now();
    await this.db.prepare(`
      INSERT INTO federation_applications (federation_id, name, org_email, official_repo, social_profiles, tech_questions, status, submitted_at)
      VALUES (?, ?, ?, ?, ?, ?, 'submitted', ?)
    `).bind(data.federationId, data.name, data.orgEmail, data.officialRepo, JSON.stringify(data.socialProfiles), JSON.stringify(data.techQuestions), now).run();

    const app = await this.db.prepare(`SELECT * FROM federation_applications WHERE federation_id = ?`).bind(data.federationId).first<any>();
    return { success: true, application: app };
  }

  // Get federation applications (admin)
  async getFederationApplications(status?: string): Promise<any[]> {
    let query = `SELECT * FROM federation_applications`;
    if (status) query += ` WHERE status = ?`;
    query += ` ORDER BY submitted_at DESC`;
    const rows = await this.db.prepare(query).bind(status).all();
    return rows.results as any[];
  }

  // Review federation application (admin)
  async reviewFederationApplication(id: number, decision: 'approved' | 'rejected', reviewer: string, notes?: string): Promise<{ success: boolean; federation?: any }> {
    const app = await this.db.prepare(`SELECT * FROM federation_applications WHERE id = ?`).bind(id).first<any>();
    if (!app) return { success: false };

    const now = Date.now();
    await this.db.prepare(`UPDATE federation_applications SET status = ?, reviewed_at = ?, reviewed_by = ?, review_notes = ? WHERE id = ?`).bind(decision, now, reviewer, notes || '', id).run();

    if (decision === 'approved') {
      await this.db.prepare(`
        INSERT INTO verified_federations (id, name, org_email, official_repo, social_profiles, status, reviewed_by, reviewed_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'verified', ?, ?, ?, ?)
      `).bind(app.federation_id, app.name, app.org_email, app.official_repo, app.social_profiles, reviewer, now, now, now).run();

      const fed = await this.db.prepare(`SELECT * FROM verified_federations WHERE id = ?`).bind(app.federation_id).first<any>();
      return { success: true, federation: fed };
    }

    return { success: true };
  }

  // Get verified federations
  async getVerifiedFederations(): Promise<any[]> {
    const rows = await this.db.prepare(`SELECT * FROM verified_federations WHERE status = 'verified' ORDER BY name`).all<any>();
    return rows.results;
  }

  // Get single verified federation
  async getVerifiedFederation(id: string): Promise<any | null> {
    return this.db.prepare(`SELECT * FROM verified_federations WHERE id = ? AND status = 'verified'`).bind(id).first<any>();
  }

  // Submit speech line from verified federation agent
  async submitSpeechLine(federationId: string, agentId: string, projectId: string, statement: string): Promise<{ success: boolean; speechLine?: any; error?: string }> {
    // Verify federation exists and is verified
    const fed = await this.db.prepare(`SELECT id FROM verified_federations WHERE id = ? AND status = 'verified'`).bind(federationId).first();
    if (!fed) return { success: false, error: 'Federation not verified' };

    // Check uniqueness
    const existing = await this.db.prepare(`SELECT id FROM federation_speech_lines WHERE statement = ?`).bind(statement).first();
    if (existing) return { success: false, error: 'Statement already exists in federation speech pool' };

    const now = Date.now();
    await this.db.prepare(`
      INSERT INTO federation_speech_lines (federation_id, agent_id, project_id, statement, is_unique, submitted_at)
      VALUES (?, ?, ?, ?, 1, ?)
    `).bind(federationId, agentId, projectId, statement, now).run();

    const line = await this.db.prepare(`SELECT * FROM federation_speech_lines WHERE statement = ?`).bind(statement).first<any>();
    return { success: true, speechLine: line };
  }

  // Get federation speech lines for a project (for TV widget)
  async getFederationSpeechLines(projectId: string, limit = 200): Promise<any[]> {
    const rows = await this.db.prepare(`
      SELECT * FROM federation_speech_lines
      WHERE project_id = ? OR project_id IN (SELECT id FROM projects WHERE id = ?)
      ORDER BY submitted_at DESC LIMIT ?
    `).bind(projectId, projectId, limit).all<any>();
    return rows.results;
  }

  // Get all speech lines (for TV widget global pool)
  async getAllFederationSpeechLines(limit = 500): Promise<any[]> {
    const rows = await this.db.prepare(`SELECT * FROM federation_speech_lines ORDER BY submitted_at DESC LIMIT ?`).bind(limit).all<any>();
    return rows.results;
  }

  // MCP Organization management
  async registerMCPOrg(data: { id: string; name: string; contactEmail: string; apiKeyHash: string; scopes?: string[]; rateLimit?: number; ipAllowlist?: string[] }): Promise<any> {
    const now = Date.now();
    await this.db.prepare(`
      INSERT INTO mcp_organizations (id, name, contact_email, api_key_hash, scopes, rate_limit, ip_allowlist, status, created_at, last_access_at, metadata)
      VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, '{}')
    `).bind(data.id, data.name, data.contactEmail, data.apiKeyHash, JSON.stringify(data.scopes || ['org:read']), data.rateLimit || 100, JSON.stringify(data.ipAllowlist || []), now, now).run();
    return this.db.prepare(`SELECT * FROM mcp_organizations WHERE id = ?`).bind(data.id).first<any>() as Promise<any>;
  }

  async getMCPOrg(id: string): Promise<any | null> {
    return this.db.prepare(`SELECT * FROM mcp_organizations WHERE id = ?`).bind(id).first<any>();
  }

  async getActiveMCPOrg(id: string): Promise<any | null> {
    return this.db.prepare(`SELECT * FROM mcp_organizations WHERE id = ? AND status = 'active'`).bind(id).first<any>();
  }

  async updateMCPOrgLastAccess(id: string): Promise<void> {
    await this.db.prepare(`UPDATE mcp_organizations SET last_access_at = ? WHERE id = ?`).bind(Date.now(), id).run();
  }

  async rotateMCPOrgCredential(id: string, apiKeyHash: string, actor: string): Promise<any | null> {
    const now = Date.now();
    await this.db.batch([
      this.db.prepare("UPDATE mcp_organizations SET api_key_hash = ?, last_access_at = ? WHERE id = ?").bind(apiKeyHash, now, id),
      this.db.prepare("INSERT INTO mcp_token_history (org_id, action, scopes, issued_by, timestamp) SELECT id, 'rotated', scopes, ?, ? FROM mcp_organizations WHERE id = ?").bind(actor, now, id),
    ]);
    return this.getMCPOrg(id);
  }

  async setMCPOrgStatus(id: string, status: "active" | "suspended" | "revoked", actor: string): Promise<any | null> {
    const now = Date.now();
    await this.db.batch([
      this.db.prepare("UPDATE mcp_organizations SET status = ? WHERE id = ?").bind(status, id),
      this.db.prepare("INSERT INTO mcp_token_history (org_id, action, scopes, issued_by, timestamp) SELECT id, ?, scopes, ?, ? FROM mcp_organizations WHERE id = ?")
        .bind(status === "active" ? "issued" : status, actor, now, id),
    ]);
    return this.getMCPOrg(id);
  }

  async isMCPRateLimited(orgId: string, rateLimit: number, now = Date.now()): Promise<boolean> {
    const row = await this.db.prepare(`
      SELECT COUNT(*) AS count FROM mcp_access_logs
      WHERE org_id = ? AND tool_name = 'mcp.request' AND timestamp >= ?
    `).bind(orgId, now - 60_000).first<{ count: number }>();
    return (row?.count ?? 0) >= rateLimit;
  }

  // Log MCP access
  async logMCPAccess(data: { orgId: string; toolName: string; params?: any; projectId?: string; agentId?: string; status?: string; errorMessage?: string; ipAddress?: string; userAgent?: string; requestId: string }): Promise<void> {
    await this.db.prepare(`
      INSERT INTO mcp_access_logs (org_id, tool_name, params, project_id, agent_id, status, error_message, ip_address, user_agent, request_id, timestamp)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(data.orgId, data.toolName, JSON.stringify(redactMcpAuditValue(data.params || {})), data.projectId || null, data.agentId || null, data.status || 'success', data.errorMessage || null, data.ipAddress || null, data.userAgent || null, data.requestId, Date.now()).run();
  }

  // Get MCP access logs
  async getMCPAccessLogs(orgId?: string, limit = 100): Promise<any[]> {
    let query = `SELECT * FROM mcp_access_logs`;
    const params = [];
    if (orgId) { query += ` WHERE org_id = ?`; params.push(orgId); }
    query += ` ORDER BY timestamp DESC LIMIT ?`; params.push(limit);
    const rows = await this.db.prepare(query).bind(...params).all();
    return rows.results as any[];
  }

  async simulatePolicy(projectId: string, eventId: string): Promise<unknown> {
    const row = await this.db.prepare(`
      SELECT schema_version, event_id, idempotency_key, project_id, agent_id, run_id, parent_run_id,
        chain_key, event_type, severity, statement, metadata, occurred_at, received_at
      FROM operational_events WHERE project_id = ? AND event_id = ?
    `).bind(projectId, eventId).first<OperationalEventRow>();
    if (!row) throw new Error("historical event not found");
    const event: OperationalEvent = {
      schemaVersion: row.schema_version, eventId: row.event_id, idempotencyKey: row.idempotency_key,
      projectId: row.project_id, agentId: row.agent_id, runId: row.run_id ?? undefined,
      parentRunId: row.parent_run_id ?? undefined, chainKey: row.chain_key ?? undefined,
      eventType: row.event_type, severity: row.severity, statement: row.statement,
      occurredAt: new Date(row.occurred_at).toISOString(), metadata: parseJsonRecord(row.metadata),
    };
    const [failedRow, chainRow] = await Promise.all([
      event.eventType === "validation.failed"
        ? this.db.prepare("SELECT COUNT(*) AS count FROM operational_events WHERE project_id = ? AND agent_id = ? AND event_type = 'validation.failed' AND received_at >= ? AND received_at <= ?")
          .bind(projectId, event.agentId, row.received_at - 15 * 60 * 1_000, row.received_at).first<{ count: number }>()
        : Promise.resolve({ count: 0 }),
      event.eventType === "run.started" && event.chainKey
        ? this.db.prepare("SELECT COUNT(*) AS count FROM operational_events WHERE project_id = ? AND event_type = 'run.started' AND chain_key = ? AND received_at >= ? AND received_at <= ?")
          .bind(projectId, event.chainKey, row.received_at - 15 * 60 * 1_000, row.received_at).first<{ count: number }>()
        : Promise.resolve({ count: 0 }),
    ]);
    const decisions = evaluateRunawayRules(event, {
      failedAttempts: failedRow?.count ?? 0,
      matchingChainStarts: chainRow?.count ?? 0,
    });
    return { simulated: true, projectId, eventId, receivedAt: row.received_at, decisions };
  }

  async exportProjectEvidence(projectId: string, requestedBy: string, retentionDays = 30): Promise<unknown> {
    if (!await this.getProjectSummary(projectId)) throw new Error("project not found");
    const now = Date.now();
    const expiresAt = now + Math.min(Math.max(retentionDays, 1), 365) * 24 * 60 * 60 * 1_000;
    const exportId = `evidence_${crypto.randomUUID()}`;
    const [events, audits, incidents, transitions] = await Promise.all([
      this.db.prepare("SELECT event_id AS eventId, idempotency_key AS idempotencyKey, producer_id AS producerId, agent_id AS agentId, run_id AS runId, parent_run_id AS parentRunId, chain_key AS chainKey, event_type AS eventType, severity, statement, metadata, occurred_at AS occurredAt, received_at AS receivedAt, payload_digest AS payloadDigest, decision FROM operational_events WHERE project_id = ? ORDER BY received_at ASC LIMIT 5000").bind(projectId).all(),
      this.db.prepare("SELECT sequence, id, operational_event_id AS operationalEventId, previous_hash AS previousHash, hash, decision, evidence_r2_key AS evidenceR2Key, created_at AS createdAt FROM audit_events WHERE project_id = ? ORDER BY sequence ASC LIMIT 5000").bind(projectId).all(),
      this.db.prepare("SELECT id, dedupe_key AS dedupeKey, agent_id AS agentId, run_id AS runId, rule_id AS ruleId, severity, status, title, opened_at AS openedAt, acknowledged_at AS acknowledgedAt, resolved_at AS resolvedAt, updated_at AS updatedAt FROM incidents WHERE project_id = ? ORDER BY opened_at ASC LIMIT 1000").bind(projectId).all(),
      this.db.prepare("SELECT t.incident_id AS incidentId, t.from_status AS fromStatus, t.to_status AS toStatus, t.actor, t.reason, t.created_at AS createdAt FROM incident_transitions t JOIN incidents i ON i.id = t.incident_id WHERE i.project_id = ? ORDER BY t.created_at ASC LIMIT 5000").bind(projectId).all(),
    ]);
    const evidence = {
      schemaVersion: "2026-07-17", exportId, projectId, requestedBy, createdAt: new Date(now).toISOString(),
      expiresAt: new Date(expiresAt).toISOString(), events: events.results, auditEvents: audits.results,
      incidents: incidents.results, incidentTransitions: transitions.results,
    };
    const payload = stableJson(evidence);
    if (new TextEncoder().encode(payload).byteLength > 5 * 1024 * 1024) throw new Error("evidence export exceeds the 5 MiB release limit");
    const digest = await sha256Hex(payload);
    const r2Key = `watchtower/evidence/${projectId}/${now}-${exportId}.json`;
    await this.env.VAULT.put(r2Key, payload, { httpMetadata: { contentType: "application/json" }, customMetadata: { exportId, projectId, sha256: digest } });
    await this.db.prepare(`
      INSERT INTO evidence_exports (id, project_id, requested_by, r2_key, sha256, status, event_count, audit_count, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, 'ready', ?, ?, ?, ?)
    `).bind(exportId, projectId, requestedBy, r2Key, digest, events.results.length, audits.results.length, now, expiresAt).run();
    return { exportId, projectId, sha256: digest, eventCount: events.results.length, auditCount: audits.results.length, expiresAt };
  }

  async getEvidenceExport(projectId: string, exportId: string): Promise<any | null> {
    return this.db.prepare(`
      SELECT id, project_id AS projectId, r2_key AS r2Key, sha256, status, event_count AS eventCount,
        audit_count AS auditCount, created_at AS createdAt, expires_at AS expiresAt, purged_at AS purgedAt
      FROM evidence_exports WHERE id = ? AND project_id = ?
    `).bind(exportId, projectId).first<any>();
  }

  async purgeExpiredEvidence(now = Date.now()): Promise<number> {
    const rows = await this.db.prepare("SELECT id, r2_key FROM evidence_exports WHERE status = 'ready' AND expires_at <= ? LIMIT 100").bind(now).all<{ id: string; r2_key: string }>();
    for (const row of rows.results) {
      await this.env.VAULT.delete(row.r2_key);
      await this.db.prepare("UPDATE evidence_exports SET status = 'purged', purged_at = ? WHERE id = ?").bind(now, row.id).run();
    }
    return rows.results.length;
  }
}

function parseJsonRecord(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

function redactMcpAuditValue(value: unknown, depth = 0): unknown {
  if (depth > 4) return "[TRUNCATED]";
  if (typeof value === "string") return value.length > 512 ? `${value.slice(0, 512)}…` : value;
  if (value === null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.slice(0, 32).map(entry => redactMcpAuditValue(entry, depth + 1));
  const record = value as Record<string, unknown>;
  return Object.fromEntries(Object.entries(record).map(([key, entry]) => [
    key,
    /authorization|api[_-]?key|token|secret|password|cookie|credential/i.test(key) ? "[REDACTED]" : redactMcpAuditValue(entry, depth + 1),
  ]));
}
