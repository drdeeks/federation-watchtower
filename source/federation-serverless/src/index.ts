import { AgentRegistry } from "./agent-registry";
import { FederationCoordinator } from "./federation-coordinator";
import { Env } from "./agent-registry";

export { AgentRegistry } from "./agent-registry";
export { FederationCoordinator } from "./federation-coordinator";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function json(data: any, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json", ...corsHeaders } });
}

function error(message: string, status = 400): Response {
  return json({ error: message }, status);
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // Public Watch host: serve the static TV and keep API/admin routes off this hostname.
    if (url.hostname.toLowerCase() === "watch.drdeeks.xyz") {
      if (method !== "GET" && method !== "HEAD") {
        return new Response("Method Not Allowed", { status: 405 });
      }
      const assetRequest = path === "/"
        ? new Request(new URL("/index.html", request.url), request)
        : request;
      return env.ASSETS.fetch(assetRequest);
    }

    if (method === "OPTIONS") return new Response(null, { headers: corsHeaders });

    try {
      const coordinatorId = env.FEDERATION_COORDINATOR.idFromName("global");
      const coordinator = env.FEDERATION_COORDINATOR.get(coordinatorId);

      // ==================== HEALTH ====================
      if (path === "/health") return json({ status: "healthy", timestamp: Date.now() });

      // ==================== SYSTEM ROUTES (before project routes) ====================
      if (path === "/api/status" && method === "GET") return json(await coordinator.getSystemStatus());
      if (path === "/api/projects" && method === "GET") return json(await coordinator.getProjects());
      if (path === "/api/projects" && method === "POST") { const cfg = await request.json(); await coordinator.registerProject(cfg); return json({ success: true }); }
      if (path === "/api/feed" && method === "GET") { const limit = parseInt(url.searchParams.get("limit") || "100"); return json({ events: await coordinator.getGlobalFeed(limit) }); }
      if (path === "/api/search" && method === "GET") { const q = url.searchParams.get("q") || ""; const limit = parseInt(url.searchParams.get("limit") || "20"); return json({ results: await coordinator.searchAgents(q, limit) }); }
      if (path === "/api/health" && method === "GET") return json(await coordinator.healthCheckAll());
      if (path === "/api/rooms" && method === "GET") return json(await coordinator.getAllRooms());

      // ==================== FEDERATION VERIFICATION ROUTES ====================
      // Submit federation application (public)
      if (path === "/api/federation/apply" && method === "POST") {
        const data = await request.json();
        return json(await coordinator.submitFederationApplication(data));
      }

      // Get federation applications (admin)
      if (path === "/api/federation/applications" && method === "GET") {
        const status = url.searchParams.get("status") || undefined;
        return json(await coordinator.getFederationApplications(status));
      }

      // Review federation application (admin)
      if (path.match(/^\/api\/federation\/applications\/(\d+)\/review$/) && method === "POST") {
        const id = parseInt(path.match(/\/applications\/(\d+)\/review$/)?.[1] || "0");
        const { decision, reviewer, notes } = await request.json();
        return json(await coordinator.reviewFederationApplication(id, decision, reviewer, notes));
      }

      // Get verified federations (public)
      if (path === "/api/federation/verified" && method === "GET") {
        return json(await coordinator.getVerifiedFederations());
      }

      // Get single verified federation
      if (path.match(/^\/api\/federation\/verified\/([^/]+)$/) && method === "GET") {
        const id = path.match(/\/verified\/([^/]+)$/)?.[1];
        return json(await coordinator.getVerifiedFederation(id!));
      }

      // Submit speech line from verified federation agent
      if (path === "/api/federation/speech" && method === "POST") {
        const { federationId, agentId, projectId, statement } = await request.json();
        return json(await coordinator.submitSpeechLine(federationId, agentId, projectId, statement));
      }

      // Get federation speech lines for project
      if (path.match(/^\/api\/federation\/speech\/project\/([^/]+)$/) && method === "GET") {
        const projectId = path.match(/\/speech\/project\/([^/]+)$/)?.[1];
        const limit = parseInt(url.searchParams.get("limit") || "200");
        return json(await coordinator.getFederationSpeechLines(projectId!, limit));
      }

      // Get all federation speech lines (global pool for TV)
      if (path === "/api/federation/speech" && method === "GET") {
        const limit = parseInt(url.searchParams.get("limit") || "500");
        return json(await coordinator.getAllFederationSpeechLines(limit));
      }

      // ==================== MCP ORG ROUTES ====================
      // Register MCP org (admin)
      if (path === "/api/mcp/organizations" && method === "POST") {
        const data = await request.json();
        return json(await coordinator.registerMCPOrg(data));
      }

      // Get MCP org
      if (path.match(/^\/api\/mcp\/organizations\/([^/]+)$/) && method === "GET") {
        const id = path.match(/\/organizations\/([^/]+)$/)?.[1];
        return json(await coordinator.getMCPOrg(id!));
      }

      // Get MCP access logs
      if (path === "/api/mcp/logs" && method === "GET") {
        const orgId = url.searchParams.get("org_id") || undefined;
        const limit = parseInt(url.searchParams.get("limit") || "100");
        return json(await coordinator.getMCPAccessLogs(orgId, limit));
      }

      // ==================== PROJECT-SPECIFIC ROUTES ====================
      const projectMatch = path.match(/^\/api\/projects\/([^/]+)\/(.*)$/);
      if (projectMatch) {
        const [, projectId, rest] = projectMatch;
        return handleProjectRoutes(request, env, projectId, rest, corsHeaders);
      }

      // ==================== WEBSOCKET ====================
      if (path === "/ws" && request.headers.get("Upgrade") === "websocket") return handleWebSocket(request, env);

      // ==================== STATIC ASSETS (TV Widget) ====================
      if (path === "/" || path === "/index.html") {
        const asset = await env.ASSETS.fetch(new Request(new URL("/index.html", request.url)));
        return new Response(asset.body, { headers: { ...corsHeaders, "Content-Type": "text/html" } });
      }
      if (path.startsWith("/assets/") || path.startsWith("/static/") || path === "/tv-widget.js") {
        return env.ASSETS.fetch(request);
      }

      return error("Not found", 404);
    } catch (e) {
      console.error("Worker error:", e);
      return json({ error: String(e) }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

async function handleProjectRoutes(request: Request, env: Env, projectId: string, restPath: string, corsHeaders: Record<string, string>): Promise<Response> {
  const registryId = env.AGENT_REGISTRY.idFromName(`${projectId}-registry`);
  const registry = env.AGENT_REGISTRY.get(registryId);
  const url = new URL(request.url);

  await registry.initialize();

  // Agents
  if (restPath === "agents" && request.method === "GET") return json({ agents: await registry.getAllAgents() });
  if (restPath === "agents" && request.method === "POST") {
    const data = await request.json();
    return json({ agent: await registry.registerAgent({ agentId: data.agentId, name: data.name, role: data.role, capabilities: data.capabilities || [], status: data.status || "active", metadata: data.metadata || {} }) });
  }
  if (restPath.startsWith("agents/") && request.method === "GET") {
    const agentId = restPath.split("/")[1];
    const agent = await registry.getAgent(agentId);
    return agent ? json({ agent }) : error("Not found", 404);
  }
  if (restPath.startsWith("agents/") && request.method === "PATCH") {
    const agentId = restPath.split("/")[1];
    const updates = await request.json();
    return json({ agent: await registry.updateAgent(agentId, updates) });
  }
  if (restPath.endsWith("/heartbeat") && request.method === "POST") {
    const agentId = restPath.split("/")[1];
    return json({ agent: await registry.heartbeat(agentId) });
  }
  if (restPath.endsWith("/status") && request.method === "PATCH") {
    const agentId = restPath.split("/")[1];
    const { status } = await request.json();
    return json({ agent: await registry.setAgentStatus(agentId, status) });
  }

  // Rooms
  if (restPath === "rooms" && request.method === "GET") return json({ rooms: await registry.getRooms() });
  if (restPath.startsWith("rooms/") && request.method === "GET") {
    const roomId = restPath.split("/")[1];
    const room = await registry.getRoom(roomId);
    return room ? json({ room }) : error("Not found", 404);
  }

  // Feed
  if (restPath === "feed" && request.method === "GET") {
    const limit = parseInt(url.searchParams.get("limit") || "50");
    return json({ events: await registry.getFeed(limit) });
  }

  // Memory
  if (restPath === "memory/soul" && request.method === "GET") return json({ projectId, content: await registry.getSoul() });
  if (restPath === "memory/soul" && request.method === "PUT") { const { content } = await request.json(); await registry.setSoul(content); return json({ success: true }); }
  if (restPath === "memory/memory" && request.method === "GET") return json({ projectId, content: await registry.getMemory() });
  if (restPath === "memory/memory" && request.method === "PUT") { const { content } = await request.json(); await registry.setMemory(content); return json({ success: true }); }
  if (restPath.startsWith("memory/daily/") && request.method === "GET") { const date = restPath.split("/")[2]; return json({ projectId, date, content: await registry.getDailyNote(date) }); }
  if (restPath.startsWith("memory/daily/") && request.method === "PUT") { const date = restPath.split("/")[2]; const { content } = await request.json(); await registry.setDailyNote(date, content); return json({ success: true }); }
  if (restPath === "memory/daily" && request.method === "GET") { const days = parseInt(url.searchParams.get("days") || "7"); return json({ projectId, notes: await registry.getRecentDailyNotes(days) }); }
  if (restPath === "memory/entities" && request.method === "GET") return json({ projectId, entities: await registry.getAllEntities() });
  if (restPath === "memory/entities" && request.method === "POST") { const data = await request.json(); return json(await registry.createEntity(data)); }
  if (restPath.startsWith("memory/entities/") && request.method === "GET") { const entityId = restPath.split("/")[2]; const entity = await registry.getEntity(entityId); return entity ? json({ entity }) : error("Not found", 404); }
  if (restPath === "memory/search" && request.method === "GET") { const q = url.searchParams.get("q") || ""; const limit = parseInt(url.searchParams.get("limit") || "10"); return json({ projectId, entities: await registry.searchEntities(q, limit) }); }

  // Project summary (for TV wall)
  if (restPath === "summary" && request.method === "GET") {
    const coordinatorId = env.FEDERATION_COORDINATOR.idFromName("global");
    const coordinator = env.FEDERATION_COORDINATOR.get(coordinatorId);
    const summary = await coordinator.getProjectSummary(projectId);
    return summary ? json(summary) : error("Project not found", 404);
  }

  return error("Not found", 404);
}

async function handleWebSocket(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const projectId = url.searchParams.get("projectId") || "all";

  const [client, server] = Object.values(new WebSocketPair());
  server.accept();

  server.addEventListener("message", async (event) => {
    try { const msg = JSON.parse(event.data as string); if (msg.type === "subscribe") {} } catch {}
  });

  const coordinatorId = env.FEDERATION_COORDINATOR.idFromName("global");
  const coordinator = env.FEDERATION_COORDINATOR.get(coordinatorId);

  try {
    if (projectId === "all") {
      const feed = await coordinator.getGlobalFeed(50);
      server.send(JSON.stringify({ type: "feed_snapshot", events: feed }));
    } else {
      const registryId = env.AGENT_REGISTRY.idFromName(`${projectId}-registry`);
      const registry = env.AGENT_REGISTRY.get(registryId);
      await registry.initialize();
      const feed = await registry.getFeed(50);
      server.send(JSON.stringify({ type: "feed_snapshot", events: feed }));
    }
  } catch (e) { console.error("WS init error:", e); }

  const interval = setInterval(async () => {
    try {
      if (projectId === "all") {
        const feed = await coordinator.getGlobalFeed(20);
        if (server.readyState === WebSocket.OPEN) server.send(JSON.stringify({ type: "feed_update", events: feed }));
      } else {
        const registryId = env.AGENT_REGISTRY.idFromName(`${projectId}-registry`);
        const registry = env.AGENT_REGISTRY.get(registryId);
        const feed = await registry.getFeed(20);
        if (server.readyState === WebSocket.OPEN) server.send(JSON.stringify({ type: "feed_update", events: feed }));
      }
    } catch {}
  }, 5000);

  server.addEventListener("close", () => clearInterval(interval));

  return new Response(null, { status: 101, webSocket: client });
}
