import { AgentRegistry } from "./agent-registry";
import { FederationCoordinator } from "./federation-coordinator";
import type { WatchtowerEnv } from "./agent-registry";
import { AgentWatchdog } from "./agent-watchdog";
import { ProjectGuardrail, type AlertDispatch } from "./project-guardrail";
import {
  constantTimeEqual, hmacSha256Hex, sha256Hex, stableJson, validateAgentId,
  validateCommandAcknowledgement, validateLeaseRequest, validateLeaseValidationRequest,
  validateOperationalEvent, validateProjectId,
} from "./watchtower";

export { AgentRegistry } from "./agent-registry";
export { FederationCoordinator } from "./federation-coordinator";
export { ProjectGuardrail } from "./project-guardrail";
export { AgentWatchdog } from "./agent-watchdog";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Watchtower-Producer, X-Watchtower-Signature, X-Watchtower-Timestamp",
};

function json(data: any, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json", ...corsHeaders } });
}

function error(message: string, status = 400): Response {
  return json({ error: message }, status);
}

const MAX_EVENT_BYTES = 64 * 1024;
const SIGNATURE_WINDOW_MS = 5 * 60 * 1_000;

class HttpError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

async function readBoundedJson(request: Request, maxBytes = MAX_EVENT_BYTES): Promise<{ raw: string; value: unknown }> {
  const contentLength = request.headers.get("Content-Length");
  if (contentLength && (!/^\d+$/.test(contentLength) || Number(contentLength) > maxBytes)) throw new HttpError(413, "request body exceeds the allowed size");
  if (!request.body) throw new HttpError(400, "request body is required");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) throw new HttpError(413, "request body exceeds the allowed size");
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  const raw = new TextDecoder().decode(bytes);
  try { return { raw, value: JSON.parse(raw) }; } catch { throw new HttpError(400, "request body must be valid JSON"); }
}

async function authenticateProducer(request: Request, rawBody: string, env: WatchtowerEnv): Promise<string> {
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

function requireAdmin(request: Request, env: WatchtowerEnv): Response | null {
  const token = env.WATCHTOWER_ADMIN_TOKEN;
  if (!token) return env.ENVIRONMENT === "production" ? error("administrative access is not configured", 503) : null;
  const supplied = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") || "";
  return constantTimeEqual(token, supplied) ? null : error("administrative authorization is required", 401);
}

function validated<T>(operation: () => T): T {
  try {
    return operation();
  } catch (cause) {
    throw new HttpError(400, cause instanceof Error ? cause.message : "request is invalid");
  }
}

function heartbeatDeadline(event: { metadata: Record<string, unknown> }): number {
  const requested = event.metadata.expectedHeartbeatSeconds;
  const seconds = typeof requested === "number" && Number.isInteger(requested) && requested >= 30 && requested <= 900
    ? requested
    : 120;
  return Date.now() + seconds * 1_000;
}

async function enqueueAlerts(env: WatchtowerEnv, alerts: AlertDispatch[]): Promise<void> {
  if (alerts.length > 0) await env.WATCHTOWER_ALERTS.sendBatch(alerts.map(alert => ({ body: alert })));
}

function alertWebhookUrl(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "https:") throw new Error("WATCHTOWER_ALERT_WEBHOOK_URL must use HTTPS");
  return url.toString();
}

function externalErrorDetail(cause: unknown): string {
  const message = cause instanceof Error ? cause.message : "unknown delivery failure";
  return message.replace(/[\r\n]/g, " ").slice(0, 240);
}

export default {
  async fetch(request: Request, env: WatchtowerEnv, ctx: ExecutionContext): Promise<Response> {
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

      // ==================== WATCHTOWER EVENT INGESTION ====================
      if (path === "/api/v1/events" && method === "POST") {
        const { raw, value } = await readBoundedJson(request);
        const producerId = await authenticateProducer(request, raw, env);
        const event = validated(() => validateOperationalEvent(value));
        if (!await coordinator.getProjectSummary(event.projectId)) return error("project not found", 404);
        const guardrailId = env.PROJECT_GUARDRAIL.idFromName(event.projectId);
        const guardrail = env.PROJECT_GUARDRAIL.get(guardrailId) as DurableObjectStub<ProjectGuardrail>;
        const result = await guardrail.ingest({ event, producerId, payloadDigest: await sha256Hex(raw), receivedAt: Date.now() });
        if (event.eventType === "heartbeat") {
          const watchdog = env.AGENT_WATCHDOG.get(env.AGENT_WATCHDOG.idFromName(`${event.projectId}:${event.agentId}`)) as DurableObjectStub<AgentWatchdog>;
          await watchdog.recordHeartbeat({ projectId: event.projectId, agentId: event.agentId, deadlineAt: heartbeatDeadline(event) });
        }
        // Queue redelivery is intentionally idempotent by delivery ID. Re-queueing on an event retry closes
        // the small failure window between the durable D1 decision and the durable Queue write.
        await enqueueAlerts(env, result.alerts);
        console.log({ event: "watchtower.event.accepted", projectId: event.projectId, agentId: event.agentId, eventType: event.eventType, duplicate: result.duplicate, incidentCount: result.incidentIds.length });
        return json(result, result.duplicate ? 200 : 201);
      }
      const incidentMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/incidents$/);
      if (incidentMatch && method === "GET") {
        const denied = requireAdmin(request, env);
        if (denied) return denied;
        const projectId = incidentMatch[1];
        if (!await coordinator.getProjectSummary(projectId)) return error("project not found", 404);
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        const limit = parseInt(url.searchParams.get("limit") || "50");
        return json({ incidents: await guardrail.getIncidents(limit) });
      }

      // ==================== WATCHTOWER COOPERATIVE CONTROL LOOP ====================
      const leaseRequestMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/leases$/);
      if (leaseRequestMatch && method === "POST") {
        const projectId = validated(() => validateProjectId(leaseRequestMatch[1]));
        const { raw, value } = await readBoundedJson(request);
        const producerId = await authenticateProducer(request, raw, env);
        const leaseRequest = validated(() => validateLeaseRequest(value));
        if (leaseRequest.projectId !== projectId) return error("projectId must match the request path", 400);
        if (!await coordinator.getProjectSummary(projectId)) return error("project not found", 404);
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        const result = await guardrail.requestLease(leaseRequest, producerId);
        return json(result, result.status === "active" ? 201 : 409);
      }

      const leaseValidationMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/leases\/([^/]+)\/validate$/);
      if (leaseValidationMatch && method === "POST") {
        const projectId = validated(() => validateProjectId(leaseValidationMatch[1]));
        const leaseId = validated(() => validateAgentId(leaseValidationMatch[2]));
        const { raw, value } = await readBoundedJson(request);
        await authenticateProducer(request, raw, env);
        const { agentId } = validated(() => validateLeaseValidationRequest(value));
        if (!await coordinator.getProjectSummary(projectId)) return error("project not found", 404);
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        const result = await guardrail.validateLease(projectId, leaseId, agentId);
        return json(result, result.status === "active" ? 200 : 409);
      }

      const commandListMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/agents\/([^/]+)\/commands$/);
      if (commandListMatch && method === "GET") {
        const projectId = validated(() => validateProjectId(commandListMatch[1]));
        const agentId = validated(() => validateAgentId(commandListMatch[2]));
        await authenticateProducer(request, "", env);
        if (!await coordinator.getProjectSummary(projectId)) return error("project not found", 404);
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        return json({ commands: await guardrail.getPendingCommands(projectId, agentId) });
      }

      const commandAcknowledgementMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/commands\/acknowledge$/);
      if (commandAcknowledgementMatch && method === "POST") {
        const projectId = validated(() => validateProjectId(commandAcknowledgementMatch[1]));
        const { raw, value } = await readBoundedJson(request);
        await authenticateProducer(request, raw, env);
        const acknowledgement = validated(() => validateCommandAcknowledgement(value));
        if (!await coordinator.getProjectSummary(projectId)) return error("project not found", 404);
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        const result = await guardrail.acknowledgeCommand(projectId, acknowledgement);
        return json(result, result.success ? 200 : 404);
      }

      // ==================== SYSTEM ROUTES (before project routes) ====================
      if (path === "/api/status" && method === "GET") return json(await coordinator.getSystemStatus());
      if (path === "/api/projects" && method === "GET") return json(await coordinator.getProjects());
      if (path === "/api/projects" && method === "POST") { const denied = requireAdmin(request, env); if (denied) return denied; const cfg = await request.json(); await coordinator.registerProject(cfg); return json({ success: true }); }
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
        const denied = requireAdmin(request, env); if (denied) return denied;
        const status = url.searchParams.get("status") || undefined;
        return json(await coordinator.getFederationApplications(status));
      }

      // Review federation application (admin)
      if (path.match(/^\/api\/federation\/applications\/(\d+)\/review$/) && method === "POST") {
        const denied = requireAdmin(request, env); if (denied) return denied;
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
        const denied = requireAdmin(request, env); if (denied) return denied;
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
        const denied = requireAdmin(request, env); if (denied) return denied;
        const data = await request.json();
        return json(await coordinator.registerMCPOrg(data));
      }

      // Get MCP org
      if (path.match(/^\/api\/mcp\/organizations\/([^/]+)$/) && method === "GET") {
        const denied = requireAdmin(request, env); if (denied) return denied;
        const id = path.match(/\/organizations\/([^/]+)$/)?.[1];
        return json(await coordinator.getMCPOrg(id!));
      }

      // Get MCP access logs
      if (path === "/api/mcp/logs" && method === "GET") {
        const denied = requireAdmin(request, env); if (denied) return denied;
        const orgId = url.searchParams.get("org_id") || undefined;
        const limit = parseInt(url.searchParams.get("limit") || "100");
        return json(await coordinator.getMCPAccessLogs(orgId, limit));
      }

      // ==================== PROJECT-SPECIFIC ROUTES ====================
      const projectMatch = path.match(/^\/api\/projects\/([^/]+)\/(.*)$/);
      if (projectMatch) {
        if (method !== "GET") { const denied = requireAdmin(request, env); if (denied) return denied; }
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
      if (e instanceof HttpError) return error(e.message, e.status);
      return json({ error: "internal server error" }, 500);
    }
  },

  async queue(batch: MessageBatch<AlertDispatch>, env: WatchtowerEnv): Promise<void> {
    for (const message of batch.messages) {
      const alert = message.body;
      const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(alert.projectId)) as DurableObjectStub<ProjectGuardrail>;

      if (batch.queue === "watchtower-alerts-dlq") {
        await guardrail.updateNotification(alert.deliveryId, "failed", "alert delivery exhausted its retry budget");
        message.ack();
        continue;
      }

      const configuredUrl = env.WATCHTOWER_ALERT_WEBHOOK_URL;
      if (!configuredUrl) {
        await guardrail.updateNotification(alert.deliveryId, "suppressed", "no alert webhook is configured");
        message.ack();
        continue;
      }

      try {
        const webhookUrl = alertWebhookUrl(configuredUrl);
        const body = stableJson(alert);
        const timestamp = Math.floor(Date.now() / 1_000).toString();
        const headers: Record<string, string> = {
          "Content-Type": "application/json",
          "X-Watchtower-Delivery": alert.deliveryId,
          "X-Watchtower-Timestamp": timestamp,
        };
        if (env.WATCHTOWER_ALERT_WEBHOOK_SECRET) {
          headers["X-Watchtower-Signature"] = `sha256=${await hmacSha256Hex(env.WATCHTOWER_ALERT_WEBHOOK_SECRET, `${timestamp}.${body}`)}`;
        }
        const response = await fetch(webhookUrl, { method: "POST", headers, body });
        if (!response.ok) throw new Error(`webhook returned HTTP ${response.status}`);
        await guardrail.updateNotification(alert.deliveryId, "delivered");
        message.ack();
      } catch (cause) {
        const detail = externalErrorDetail(cause);
        console.error({ event: "watchtower.alert.delivery_retry", deliveryId: alert.deliveryId, detail });
        await guardrail.updateNotification(alert.deliveryId, "retrying", detail);
        message.retry({ delaySeconds: Math.min(60, 2 ** Math.min(message.attempts, 5)) });
      }
    }
  },
} satisfies ExportedHandler<WatchtowerEnv, AlertDispatch>;

async function handleProjectRoutes(request: Request, env: WatchtowerEnv, projectId: string, restPath: string, corsHeaders: Record<string, string>): Promise<Response> {
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

async function handleWebSocket(request: Request, env: WatchtowerEnv): Promise<Response> {
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
