import type { AgentRegistry, WatchtowerEnv } from "./agent-registry.ts";
import type { AgentWatchdog } from "./agent-watchdog.ts";
import { validateAgentId, validateProjectId, ValidationError } from "./watchtower.ts";
import { appendLifecycle, projectPublicScene } from "./lifecycle.ts";

type Json = (data: unknown, status?: number) => Response;

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
