import type { AgentRegistry, WatchtowerEnv } from "./agent-registry.ts";
import type { AgentWatchdog } from "./agent-watchdog.ts";
import { validateAgentId, validateProjectId, ValidationError } from "./watchtower.ts";
import { appendLifecycle, projectPublicScene } from "./lifecycle.ts";

type Json = (data: unknown, status?: number) => Response;

// Helper functions for validation (mirroring lifecycle.ts patterns)
function readBoundedJsonBody(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new ValidationError("request body must be a JSON object");
  return value as Record<string, unknown>;
}
function text(value: unknown, label: string, max: number): string {
  if (typeof value !== "string" || !(value = value.trim()) || value.length > max) throw new ValidationError(`${label} must be a non-empty string up to ${max} characters`);
  return value;
}
function integer(value: unknown, label: string, min: number, max: number): number {
  if (!Number.isInteger(value) || (value as number) < min || (value as number) > max) throw new ValidationError(`${label} must be an integer from ${min} to ${max}`);
  return value as number;
}

// Admin operator management for canonical agents. Every route here is gated by
// requireAdmin() in index.ts before this handler runs. "Remove" is a revoke,
// never a delete — federation_lifecycle_events (evidence) is preserved.
export async function handleManagementRequest(input: {
  request: Request; path: string; method: string; env: WatchtowerEnv; json: Json;
}): Promise<Response | null> {
  const { request, path, method, env, json } = input;

  if (path === "/api/v1/admin/agents" && method === "GET") {
    const url = new URL(request.url);
    const clauses: string[] = [];
    const binds: unknown[] = [];
    const projectFilter = url.searchParams.get("projectId");
    if (projectFilter) { clauses.push("a.project_id = ?"); binds.push(validateProjectId(projectFilter)); }
    const stateFilter = url.searchParams.get("state");
    if (stateFilter) {
      const f = agentStateFilter(stateFilter);
      clauses.push(f.clause);
      if (f.bind !== undefined) binds.push(f.bind);
    }
    const where = clauses.length ? " WHERE " + clauses.join(" AND ") : "";
    const rows = await env.DB.prepare(
      `SELECT a.id, a.project_id, a.agent_id, a.owner_id, a.organization_id, a.display_name, a.role,
        a.palette_key, a.character_type, a.public_projection, a.heartbeat_seconds, a.lifecycle_state,
        a.paused_at, a.room_id, a.connected_at, a.last_heartbeat_at, a.disconnected_at, a.created_at,
        (SELECT COUNT(*) FROM federation_lifecycle_events e WHERE e.agent_id = a.id) AS event_count
       FROM federation_agents a${where} ORDER BY a.created_at DESC LIMIT 500`
    ).bind(...binds).all<AgentRow>();
    const agents = (rows.results || []).map(present);
    const summary = agents.reduce((s, a) => {
      s.total++;
      if (a.paused) s.paused++;
      else if (a.lifecycleState === "revoked") s.revoked++;
      else if (a.lifecycleState === "connected") s.live++;
      else s.idle++;
      return s;
    }, { total: 0, live: 0, idle: 0, paused: 0, revoked: 0 });
    return json({ agents, summary, requestId: crypto.randomUUID() });
  }

  const action = path.match(/^\/api\/v1\/admin\/agents\/([^/]+)\/([^/]+)\/(pause|resume|revoke)$/);
  if (action && method === "POST") {
    const projectId = validateProjectId(decodeURIComponent(action[1]));
    const agentId = validateAgentId(decodeURIComponent(action[2]));
    const op = action[3];
    const canonicalId = `${projectId}:${agentId}`;
    const agent = await env.DB.prepare("SELECT id, lifecycle_state, room_id FROM federation_agents WHERE id = ?").bind(canonicalId).first<{ id: string; lifecycle_state: string; room_id: string | null }>();
    if (!agent) return json({ error: "agent not found" }, 404);
    if (agent.lifecycle_state === "revoked") return json({ error: "agent is already revoked" }, 409);
    const now = Date.now();
    const registry = env.AGENT_REGISTRY.get(env.AGENT_REGISTRY.idFromName(`${projectId}-registry`)) as DurableObjectStub<AgentRegistry>;
    const watchdog = env.AGENT_WATCHDOG.get(env.AGENT_WATCHDOG.idFromName(`${projectId}:${agentId}`)) as DurableObjectStub<AgentWatchdog>;

    if (op === "resume") {
      await env.DB.prepare("UPDATE federation_agents SET paused_at = NULL, updated_at = ? WHERE id = ?").bind(now, canonicalId).run();
      await appendLifecycle(env, canonicalId, "agent.resumed", `mgmt-resume-${now}`, { by: "admin" }, now);
      return json({ agent: { agentId, projectId, paused: false }, requestId: crypto.randomUUID() });
    }

    // pause + revoke both stop the agent and drop it from the public scene.
    await watchdog.disconnect({ projectId, agentId });
    const publicAgent = await registry.setAgentStatus(agentId, "offline");
    if (op === "pause") {
      await env.DB.prepare("UPDATE federation_agents SET paused_at = ?, lifecycle_state = CASE WHEN lifecycle_state = 'connected' THEN 'offline' ELSE lifecycle_state END, updated_at = ? WHERE id = ?").bind(now, now, canonicalId).run();
      await appendLifecycle(env, canonicalId, "agent.paused", `mgmt-pause-${now}`, { by: "admin" }, now);
      if (publicAgent) await projectPublicScene(env, publicAgent, "offline", "agent.paused", `mgmt-pause-${now}`, now);
      return json({ agent: { agentId, projectId, paused: true, pausedAt: now }, requestId: crypto.randomUUID() });
    }
    // revoke
    await env.DB.prepare("UPDATE federation_agents SET lifecycle_state = 'revoked', disconnected_at = ?, updated_at = ? WHERE id = ?").bind(now, now, canonicalId).run();
    await env.DB.prepare("UPDATE federation_agent_credentials SET revoked_at = ? WHERE agent_id = ? AND revoked_at IS NULL").bind(now, canonicalId).run();
    await appendLifecycle(env, canonicalId, "agent.revoked", `mgmt-revoke-${now}`, { by: "admin" }, now);
    if (publicAgent) await projectPublicScene(env, publicAgent, "offline", "agent.revoked", `mgmt-revoke-${now}`, now);
    return json({ agent: { agentId, projectId, lifecycleState: "revoked" }, requestId: crypto.randomUUID() });
  }

  // Operator-visible proof the alert webhook is live: receipts the self-hosted
  // sink verified by signature. Read-only; the receipts table is append-only.
  if (path === "/api/v1/admin/alerts" && method === "GET") {
    const rows = await env.DB.prepare(
      `SELECT delivery_id, project_id, incident_id, event_id, agent_id, severity, action, statement, reason, signature_valid, received_at
       FROM alert_webhook_receipts ORDER BY received_at DESC LIMIT 200`
    ).all<AlertReceiptRow>();
    const alerts = (rows.results || []).map(presentAlertReceipt);
    return json({ alerts, count: alerts.length, requestId: crypto.randomUUID() });
  }

  // ==================== ROOM MANAGEMENT ====================
  // List all rooms (optionally filtered by project)
  if (path === "/api/v1/admin/rooms" && method === "GET") {
    const url = new URL(request.url);
    const projectFilter = url.searchParams.get("projectId");
    const binds: unknown[] = [];
    const where = projectFilter ? " WHERE r.project_id = ?" : "";
    if (projectFilter) binds.push(validateProjectId(projectFilter));
    const rows = await env.DB.prepare(
      `SELECT r.id, r.project_id, r.room_index, r.capacity, r.created_at,
        (SELECT COUNT(*) FROM agents WHERE room_id = r.id) as used_count,
        (SELECT GROUP_CONCAT(a.agent_id) FROM agents a WHERE a.room_id = r.id) as agent_ids
       FROM rooms r${where} ORDER BY r.project_id, r.room_index`
    ).bind(...binds).all<RoomRow>();
    const rooms = (rows.results || []).map(presentRoom);
    return json({ rooms, count: rooms.length, requestId: crypto.randomUUID() });
  }

  // Create a new room
  if (path === "/api/v1/admin/rooms" && method === "POST") {
    if (!request.body) throw new ValidationError("request body is required");
    const value = await request.json();
    const body = readBoundedJsonBody(value);
    const roomId = validateAgentId(body.roomId);
    const projectId = validateProjectId(body.projectId);
    const capacity = body.capacity === undefined ? 35 : integer(body.capacity, "capacity", 1, 100);
    const now = Date.now();
    // Get next room_index for this project
    const maxIndex = await env.DB.prepare("SELECT MAX(room_index) as max_idx FROM rooms WHERE project_id = ?").bind(projectId).first<{ max_idx: number | null }>();
    const roomIndex = (maxIndex?.max_idx ?? 0) + 1;
    await env.DB.prepare(
      "INSERT INTO rooms (id, project_id, room_index, capacity, created_at) VALUES (?, ?, ?, ?, ?)"
    ).bind(roomId, projectId, roomIndex, capacity, now).run();
    await appendLifecycle(env, `room:${roomId}`, "room.created", `mgmt-room-create-${now}`, { projectId, capacity, roomIndex }, now);
    return json({ room: { roomId, projectId, roomIndex, capacity, createdAt: now }, requestId: crypto.randomUUID() }, 201);
  }

  // Delete a room (only if empty)
  const roomDelete = path.match(/^\/api\/v1\/admin\/rooms\/([^/]+)$/);
  if (roomDelete && method === "DELETE") {
    const roomId = validateAgentId(decodeURIComponent(roomDelete[1]));
    const room = await env.DB.prepare("SELECT id, project_id FROM rooms WHERE id = ?").bind(roomId).first<{ id: string; project_id: string }>();
    if (!room) return json({ error: "room not found" }, 404);
    const agentCount = await env.DB.prepare("SELECT COUNT(*) as cnt FROM agents WHERE room_id = ?").bind(roomId).first<{ cnt: number }>();
    if ((agentCount?.cnt ?? 0) > 0) return json({ error: "room must be empty before deletion", agentCount: agentCount?.cnt }, 409);
    await env.DB.prepare("DELETE FROM rooms WHERE id = ?").bind(roomId).run();
    await appendLifecycle(env, `room:${roomId}`, "room.deleted", `mgmt-room-delete-${Date.now()}`, { projectId: room.project_id }, Date.now());
    return json({ deleted: true, roomId }, 200);
  }

  // ==================== ORGANIZATION MANAGEMENT ====================
  // List all organization applications
  if (path === "/api/v1/admin/organizations" && method === "GET") {
    const url = new URL(request.url);
    const statusFilter = url.searchParams.get("status");
    const binds: unknown[] = [];
    const where = statusFilter ? " WHERE status = ?" : "";
    if (statusFilter) binds.push(statusFilter);
    const rows = await env.DB.prepare(
      `SELECT id, organization_id, owner_id, name, contact_email, official_url, status, created_at, updated_at
       FROM federation_organizations${where} ORDER BY created_at DESC`
    ).bind(...binds).all<OrgRow>();
    const organizations = (rows.results || []).map(presentOrg);
    return json({ organizations, count: organizations.length, requestId: crypto.randomUUID() });
  }

  // Get single organization with full details
  const orgGet = path.match(/^\/api\/v1\/admin\/organizations\/([^/]+)$/);
  if (orgGet && method === "GET") {
    const orgId = validateAgentId(decodeURIComponent(orgGet[1]));
    const org = await env.DB.prepare("SELECT * FROM federation_organizations WHERE id = ?").bind(orgId).first<OrgRow>();
    if (!org) return json({ error: "organization not found" }, 404);
    const proofs = await env.DB.prepare("SELECT platform, url, created_at FROM federation_organization_social_proofs WHERE organization_id = ?").bind(orgId).all();
    const questions = await env.DB.prepare("SELECT position, question, answer, created_at FROM federation_organization_questions WHERE organization_id = ? ORDER BY position").bind(orgId).all();
    return json({ organization: { ...presentOrg(org), socialProofs: proofs.results || [], technicalQuestions: questions.results || [] } });
  }

  // Approve organization application
  const orgApprove = path.match(/^\/api\/v1\/admin\/organizations\/([^/]+)\/(approve|reject|suspend)$/);
  if (orgApprove && method === "POST") {
    const orgId = validateAgentId(decodeURIComponent(orgApprove[1]));
    const action = orgApprove[2];
    if (!request.body) throw new ValidationError("request body is required");
    const value = await request.json();
    const body = readBoundedJsonBody(value);
    const notes = text(body.notes || "", "notes", 500);
    const now = Date.now();
    const org = await env.DB.prepare("SELECT id, status FROM federation_organizations WHERE id = ?").bind(orgId).first<{ id: string; status: string }>();
    if (!org) return json({ error: "organization not found" }, 404);
    const newStatus = action === "approve" ? "active" : action === "reject" ? "rejected" : "suspended";
    await env.DB.prepare("UPDATE federation_organizations SET status = ?, updated_at = ? WHERE id = ?").bind(newStatus, now, orgId).run();
    // If approved, add to verified_federations
    if (action === "approve") {
      const orgData = await env.DB.prepare("SELECT * FROM federation_organizations WHERE id = ?").bind(orgId).first<any>();
      await env.DB.prepare(
        "INSERT OR REPLACE INTO verified_federations (id, name, org_email, official_repo, social_profiles, status, reviewed_by, reviewed_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'verified', ?, ?, ?, ?)"
      ).bind(orgData.organization_id, orgData.name, orgData.contact_email, orgData.official_url, orgData.social_profiles || "[]", "admin", now, orgData.created_at, now).run();
    }
    return json({ organization: { organizationId: orgId, status: newStatus, notes }, requestId: crypto.randomUUID() });
  }

  return null;
}

interface AgentRow {
  id: string; project_id: string; agent_id: string; owner_id: string; organization_id: string | null;
  display_name: string; role: string; palette_key: string; character_type: string; public_projection: number;
  heartbeat_seconds: number; lifecycle_state: string; paused_at: number | null; room_id: string | null;
  connected_at: number | null; last_heartbeat_at: number | null; disconnected_at: number | null; created_at: number; event_count: number;
}

// Map a ?state= filter to a SQL clause. "paused" is orthogonal to lifecycle_state
// (it lives in paused_at), so a lifecycle filter also requires paused_at IS NULL.
export function agentStateFilter(state: string): { clause: string; bind?: string } {
  if (state === "paused") return { clause: "a.paused_at IS NOT NULL" };
  if (["registered", "connected", "offline", "revoked"].includes(state)) return { clause: "a.lifecycle_state = ? AND a.paused_at IS NULL", bind: state };
  throw new ValidationError("state filter is not recognised");
}

interface AlertReceiptRow {
  delivery_id: string; project_id: string; incident_id: string | null; event_id: string | null;
  agent_id: string | null; severity: string | null; action: string | null; statement: string | null;
  reason: string | null; signature_valid: number; received_at: number;
}

export function presentAlertReceipt(r: AlertReceiptRow) {
  return {
    deliveryId: r.delivery_id, projectId: r.project_id, incidentId: r.incident_id || undefined,
    eventId: r.event_id || undefined, agentId: r.agent_id || undefined, severity: r.severity || undefined,
    action: r.action || undefined, statement: r.statement || undefined, reason: r.reason || undefined,
    signatureValid: r.signature_valid === 1, receivedAt: r.received_at,
  };
}

export function present(a: AgentRow) {
  return {
    agentId: a.agent_id, projectId: a.project_id, ownerId: a.owner_id, organizationId: a.organization_id || undefined,
    displayName: a.display_name, role: a.role, paletteKey: a.palette_key, characterType: a.character_type,
    publicProjection: Boolean(a.public_projection), heartbeatSeconds: a.heartbeat_seconds,
    lifecycleState: a.lifecycle_state, paused: a.paused_at != null, pausedAt: a.paused_at || undefined,
    roomId: a.room_id || undefined, connectedAt: a.connected_at || undefined, lastHeartbeatAt: a.last_heartbeat_at || undefined,
    disconnectedAt: a.disconnected_at || undefined, createdAt: a.created_at, eventCount: a.event_count,
  };
}

interface RoomRow {
  id: string; project_id: string; room_index: number; capacity: number; created_at: number;
  used_count: number; agent_ids: string | null;
}

export function presentRoom(r: RoomRow) {
  return {
    roomId: r.id, projectId: r.project_id, roomIndex: r.room_index, capacity: r.capacity,
    usedCount: r.used_count, agentIds: r.agent_ids ? r.agent_ids.split(',') : [],
    createdAt: r.created_at,
  };
}

interface OrgRow {
  id: number; organization_id: string; owner_id: string; name: string; contact_email: string;
  official_url: string; social_profiles: string | null; tech_questions: string | null;
  status: string; created_at: number; updated_at: number;
}

export function presentOrg(o: OrgRow) {
  return {
    id: o.id, organizationId: o.organization_id, ownerId: o.owner_id, name: o.name,
    contactEmail: o.contact_email, officialUrl: o.official_url,
    socialProfiles: o.social_profiles ? JSON.parse(o.social_profiles) : [],
    technicalQuestions: o.tech_questions ? JSON.parse(o.tech_questions) : [],
    status: o.status, createdAt: o.created_at, updatedAt: o.updated_at,
  };
}
