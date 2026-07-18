import { AgentRegistry } from "./agent-registry";
import { FederationCoordinator } from "./federation-coordinator";
import type { WatchtowerEnv } from "./agent-registry";
import { AgentWatchdog } from "./agent-watchdog";
import { RoomScene } from "./room-scene";
import { ProjectGuardrail, type AlertDispatch } from "./project-guardrail";
import { createMcpHandler } from "agents/mcp";
import { createWatchtowerMcpServer, isIpAllowed, parseMcpCredential, toMcpPrincipal, verifyMcpApiKey } from "./mcp";
import { handleLifecycleRequest } from "./lifecycle";
import {
  constantTimeEqual, hmacSha256Hex, sha256Hex, stableJson, validateAgentId,
  validateCommandAcknowledgement, validateControlledToolAuthorizationRequest, validateLeaseRequest, validateLeaseValidationRequest,
  validateOperationalEvent, validateProjectId, validateValidationGateRequest,
} from "./watchtower";

export { AgentRegistry } from "./agent-registry";
export { FederationCoordinator } from "./federation-coordinator";
export { ProjectGuardrail } from "./project-guardrail";
export { AgentWatchdog } from "./agent-watchdog";
export { RoomScene } from "./room-scene";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Watchtower-Producer, X-Watchtower-Signature, X-Watchtower-Timestamp, Mcp-Session-Id, Mcp-Protocol-Version, Last-Event-ID",
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

async function authenticateMcpPrincipal(request: Request, coordinator: FederationCoordinator): Promise<{ principal?: ReturnType<typeof toMcpPrincipal>; denied?: Response }> {
  const credential = parseMcpCredential(request.headers.get("Authorization"));
  const requestId = crypto.randomUUID();
  if (!credential) return { denied: mcpUnauthorized("an organization bearer credential is required") };
  const org = await coordinator.getMCPOrg(credential.orgId);
  const access = (status: string, errorMessage?: string) => coordinator.logMCPAccess({
    orgId: credential.orgId, toolName: "mcp.request", params: { method: request.method, path: new URL(request.url).pathname },
    status, errorMessage, ipAddress: request.headers.get("CF-Connecting-IP") || undefined,
    userAgent: request.headers.get("User-Agent")?.slice(0, 240), requestId,
  });
  if (!org || org.status !== "active" || !await verifyMcpApiKey(org.api_key_hash, credential.apiKey)) {
    if (org) await access("unauthorized", "organization credential rejected");
    return { denied: mcpUnauthorized("organization credential rejected") };
  }
  const principal = toMcpPrincipal(org);
  const clientIp = request.headers.get("CF-Connecting-IP");
  if (!isIpAllowed(clientIp, principal.ipAllowlist)) {
    await access("unauthorized", "source IP is not allowed for this organization");
    return { denied: mcpUnauthorized("source IP is not allowed") };
  }
  if (await coordinator.isMCPRateLimited(principal.orgId, principal.rateLimit)) {
    await access("rate_limited", "per-organization rate limit exceeded");
    return { denied: json({ error: "MCP organization rate limit exceeded" }, 429) };
  }
  await Promise.all([coordinator.updateMCPOrgLastAccess(principal.orgId), access("success")]);
  return { principal };
}

function mcpUnauthorized(message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status: 401,
    headers: { "Content-Type": "application/json", "WWW-Authenticate": 'Bearer realm="Federation Watchtower MCP"', ...corsHeaders },
  });
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
    const hostname = url.hostname.toLowerCase();
    const isWatchHost = hostname === "watch.drdeeks.xyz";
    const isFederationHost = hostname === "federation.drdeeks.xyz";
    const isApiHost = hostname === "fapi.drdeeks.xyz";
    const isDevelopmentHost = env.ENVIRONMENT !== "production" && (hostname === "localhost" || hostname === "127.0.0.1");

    // watch is the universal human-facing access point. It never accepts a
    // webhook, MCP request, API mutation, or credential-bearing browser form.
    if (isWatchHost) {
      const allowed = path === "/" || path === "/index.html" || path === "/join.html" || path === "/integrate.html" || path === "/agent-skill.md" || path === "/tv-widget.js" || path.startsWith("/brand/");
      if ((method !== "GET" && method !== "HEAD") || !allowed) return error("not found", 404);
      const assetPath = path === "/" ? "/index.html" : path;
      return env.ASSETS.fetch(new Request(new URL(assetPath, request.url), request));
    }

    // federation is reserved for approved members and elevated roles. The
    // actual role model is a later checklist phase; meanwhile the only live
    // privileged surface is the token-protected operator console.
    if (isFederationHost) {
      const allowed = path === "/" || path === "/federation.html" || path === "/operator.html" || path.startsWith("/brand/");
      if ((method !== "GET" && method !== "HEAD") || !allowed) return error("not found", 404);
      const assetPath = path === "/" ? "/federation.html" : path;
      return env.ASSETS.fetch(new Request(new URL(assetPath, request.url), request));
    }

    if (!isApiHost && !isDevelopmentHost) return error("unknown Federation host", 404);

    if (method === "OPTIONS") return new Response(null, { headers: corsHeaders });

    try {
      const coordinatorId = env.FEDERATION_COORDINATOR.idFromName("global");
      const coordinator = env.FEDERATION_COORDINATOR.get(coordinatorId);

      // ==================== HEALTH ====================
      if (path === "/health") return json({ status: "healthy", timestamp: Date.now() });

      // fapi is a machine-only origin. Its discovery response directs people
      // to watch without turning the API hostname into a second public site.
      if (path === "/" && method === "GET") {
        return json({
          service: "Federation Watchtower API",
          version: "v1",
          health: "/health",
          eventIngestion: "/api/v1/events",
          mcp: "/mcp",
          websocket: "/ws?projectId={projectId}",
          publicRoomScene: "/api/v1/public/rooms/{roomId}/scene",
          universalAccess: "https://watch.drdeeks.xyz/",
          integrationGuide: "https://watch.drdeeks.xyz/integrate.html",
        });
      }

      const lifecycleResponse = await handleLifecycleRequest({ request, path, method, env, coordinator, json, readBoundedJson });
      if (lifecycleResponse) return lifecycleResponse;

      // A public scene is a read-only projection. It contains location and
      // presentation provenance, never a credential or mutation capability.
      const sceneMatch = path.match(/^\/api\/v1\/public\/rooms\/([^/]+)\/scene$/);
      if (sceneMatch && method === "GET") {
        const roomId = decodeURIComponent(sceneMatch[1]);
        const room = await env.DB.prepare("SELECT id FROM rooms WHERE id = ?").bind(roomId).first<{ id: string }>();
        if (!room) return error("room not found", 404);
        const scene = env.ROOM_SCENE.get(env.ROOM_SCENE.idFromName(roomId)) as DurableObjectStub<RoomScene>;
        return json(await scene.snapshot());
      }

      // ==================== REMOTE MCP GATEWAY ====================
      if (path === "/mcp") {
        const authentication = await authenticateMcpPrincipal(request, coordinator);
        if (authentication.denied) return authentication.denied;
        const principal = authentication.principal!;
        const server = createWatchtowerMcpServer(principal, {
          env, coordinator,
          guardrail: projectId => env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>,
        });
        return createMcpHandler(server, {
          route: "/mcp",
          authContext: { props: { organizationId: principal.orgId, scopes: principal.scopes } },
          corsOptions: { origin: "*", headers: "Authorization, Content-Type, Mcp-Session-Id, Mcp-Protocol-Version, Last-Event-ID" },
        })(request, env, ctx);
      }

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
        const registry = env.AGENT_REGISTRY.get(env.AGENT_REGISTRY.idFromName(`${event.projectId}-registry`)) as DurableObjectStub<AgentRegistry>;
        const publicAgent = await registry.getAgent(event.agentId);
        if (publicAgent?.roomId && !result.duplicate) {
          await registry.recordPublicEvent({ eventType: event.eventType, agentId: event.agentId, message: event.statement, priority: event.severity === "critical" ? "critical" : event.severity === "error" ? "high" : "normal", metadata: { source: "signed-ingestion", eventId: event.eventId } });
          const scene = env.ROOM_SCENE.get(env.ROOM_SCENE.idFromName(publicAgent.roomId)) as DurableObjectStub<RoomScene>;
          await scene.project({ roomId: publicAgent.roomId, agentId: publicAgent.agentId, displayName: publicAgent.name, role: publicAgent.role || undefined, paletteKey: typeof publicAgent.metadata.paletteKey === "string" ? publicAgent.metadata.paletteKey : undefined, lifecycleState: publicAgent.status, eventType: event.eventType, sourceEventId: event.eventId, occurredAt: Date.now() });
        }
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
      const incidentActionMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/incidents\/([^/]+)\/(acknowledge|resolve|dismiss)$/);
      if (incidentActionMatch && method === "POST") {
        const denied = requireAdmin(request, env);
        if (denied) return denied;
        const projectId = validated(() => validateProjectId(incidentActionMatch[1]));
        const incidentId = validated(() => validateAgentId(incidentActionMatch[2]));
        const action = incidentActionMatch[3] as "acknowledge" | "resolve" | "dismiss";
        const { value } = await readBoundedJson(request);
        const reason = validated(() => incidentActionReason(value));
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        const result = await guardrail.transitionIncident(projectId, incidentId, action, "admin", reason);
        return json(result, result.success ? 200 : result.status === "not_found" ? 404 : 409);
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

      const controlledToolMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/tools\/authorize$/);
      if (controlledToolMatch && method === "POST") {
        const projectId = validated(() => validateProjectId(controlledToolMatch[1]));
        const { raw, value } = await readBoundedJson(request);
        const producerId = await authenticateProducer(request, raw, env);
        const authorization = validated(() => validateControlledToolAuthorizationRequest(value));
        if (authorization.projectId !== projectId) return error("projectId must match the request path", 400);
        if (!await coordinator.getProjectSummary(projectId)) return error("project not found", 404);
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        const result = await guardrail.authorizeControlledTool(authorization, producerId);
        return json(result, result.status === "authorized" ? 201 : 409);
      }

      const validationGateMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/validation-gates$/);
      if (validationGateMatch && method === "POST") {
        const projectId = validated(() => validateProjectId(validationGateMatch[1]));
        const { raw, value } = await readBoundedJson(request);
        const producerId = await authenticateProducer(request, raw, env);
        const gate = validated(() => validateValidationGateRequest(value));
        if (gate.projectId !== projectId) return error("projectId must match the request path", 400);
        if (!await coordinator.getProjectSummary(projectId)) return error("project not found", 404);
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        const result = await guardrail.evaluateValidationGate(gate, producerId);
        return json(result, result.allowed ? 200 : 409);
      }

      const controlledToolAuditMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/tools\/invocations$/);
      if (controlledToolAuditMatch && method === "GET") {
        const denied = requireAdmin(request, env);
        if (denied) return denied;
        const projectId = validated(() => validateProjectId(controlledToolAuditMatch[1]));
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        const limit = parseInt(url.searchParams.get("limit") || "50");
        return json({ invocations: await guardrail.getControlledToolInvocations(limit) });
      }

      const sessionMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/sessions$/);
      if (sessionMatch && method === "GET") {
        const denied = requireAdmin(request, env);
        if (denied) return denied;
        const projectId = validated(() => validateProjectId(sessionMatch[1]));
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        const limit = parseInt(url.searchParams.get("limit") || "100");
        return json({ sessions: await guardrail.getSessions(limit) });
      }

      const budgetMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/budget$/);
      if (budgetMatch && method === "GET") {
        const denied = requireAdmin(request, env);
        if (denied) return denied;
        const projectId = validated(() => validateProjectId(budgetMatch[1]));
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        return json({ budget: await guardrail.getBudget() });
      }
      if (budgetMatch && method === "PUT") {
        const denied = requireAdmin(request, env);
        if (denied) return denied;
        const projectId = validated(() => validateProjectId(budgetMatch[1]));
        const { value } = await readBoundedJson(request);
        const budget = validated(() => validateBudgetSettings(value));
        const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
        await guardrail.setBudget(projectId, budget, "admin");
        return json({ budget: await guardrail.getBudget() });
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

      const evidenceExportMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/evidence\/exports$/);
      if (evidenceExportMatch && method === "POST") {
        const denied = requireAdmin(request, env);
        if (denied) return denied;
        const projectId = validated(() => validateProjectId(evidenceExportMatch[1]));
        const { value } = await readBoundedJson(request);
        const retentionDays = validated(() => evidenceRetentionDays(value));
        return json(await coordinator.exportProjectEvidence(projectId, "admin", retentionDays), 201);
      }
      const evidenceDownloadMatch = path.match(/^\/api\/v1\/projects\/([^/]+)\/evidence\/exports\/([^/]+)$/);
      if (evidenceDownloadMatch && method === "GET") {
        const denied = requireAdmin(request, env);
        if (denied) return denied;
        const projectId = validated(() => validateProjectId(evidenceDownloadMatch[1]));
        const exportId = validated(() => validateAgentId(evidenceDownloadMatch[2]));
        const evidence = await coordinator.getEvidenceExport(projectId, exportId);
        if (!evidence || evidence.status !== "ready") return error("evidence export not found or no longer retained", 404);
        const object = await env.VAULT.get(evidence.r2Key);
        if (!object) return error("evidence object is unavailable", 404);
        return new Response(object.body, { headers: { "Content-Type": "application/json", "Content-Disposition": `attachment; filename=\"${exportId}.json\"`, ...corsHeaders } });
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
      // Register MCP org (admin). Raw organization API keys are accepted only over
      // this authenticated TLS route, hashed immediately, and never returned.
      if (path === "/api/mcp/organizations" && method === "POST") {
        const denied = requireAdmin(request, env); if (denied) return denied;
        const { value } = await readBoundedJson(request);
        const data = await validateMcpOrganizationRegistration(value);
        return json({ organization: sanitizeMcpOrganization(await coordinator.registerMCPOrg(data)) }, 201);
      }

      // Get MCP org
      if (path.match(/^\/api\/mcp\/organizations\/([^/]+)$/) && method === "GET") {
        const denied = requireAdmin(request, env); if (denied) return denied;
        const id = path.match(/\/organizations\/([^/]+)$/)?.[1];
        const organization = await coordinator.getMCPOrg(id!);
        return organization ? json({ organization: sanitizeMcpOrganization(organization) }) : error("organization not found", 404);
      }

      // Rotate a caller-provided high-entropy organization key. The raw key is
      // deliberately absent from both the response and the audit log.
      const mcpCredentialMatch = path.match(/^\/api\/mcp\/organizations\/([^/]+)\/credentials$/);
      if (mcpCredentialMatch && method === "POST") {
        const denied = requireAdmin(request, env); if (denied) return denied;
        const id = validated(() => validateAgentId(mcpCredentialMatch[1]));
        const { value } = await readBoundedJson(request);
        const apiKey = validated(() => organizationApiKey(value));
        const organization = await coordinator.rotateMCPOrgCredential(id, `sha256:${await sha256Hex(apiKey)}`, "admin");
        return organization ? json({ organization: sanitizeMcpOrganization(organization), rotated: true }) : error("organization not found", 404);
      }

      const mcpStatusMatch = path.match(/^\/api\/mcp\/organizations\/([^/]+)\/status$/);
      if (mcpStatusMatch && method === "POST") {
        const denied = requireAdmin(request, env); if (denied) return denied;
        const id = validated(() => validateAgentId(mcpStatusMatch[1]));
        const { value } = await readBoundedJson(request);
        const status = validated(() => organizationStatus(value));
        const organization = await coordinator.setMCPOrgStatus(id, status, "admin");
        return organization ? json({ organization: sanitizeMcpOrganization(organization) }) : error("organization not found", 404);
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

  async scheduled(_controller: ScheduledController, env: WatchtowerEnv): Promise<void> {
    const coordinator = env.FEDERATION_COORDINATOR.get(env.FEDERATION_COORDINATOR.idFromName("global"));
    const purged = await coordinator.purgeExpiredEvidence();
    console.log({ event: "watchtower.evidence.retention", purged });
  },
} satisfies ExportedHandler<WatchtowerEnv, AlertDispatch>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function incidentActionReason(value: unknown): string {
  if (!isRecord(value) || typeof value.reason !== "string" || !value.reason.trim() || value.reason.length > 240) throw new Error("reason must be a non-empty string up to 240 characters");
  return value.reason.trim();
}

function evidenceRetentionDays(value: unknown): number {
  if (!isRecord(value) || value.retentionDays === undefined) return 30;
  if (!Number.isInteger(value.retentionDays) || value.retentionDays < 1 || value.retentionDays > 365) throw new Error("retentionDays must be an integer between 1 and 365");
  return value.retentionDays;
}

function validateBudgetSettings(value: unknown): { limitUsd: number; warningUsd: number } {
  if (!isRecord(value) || typeof value.limitUsd !== "number" || typeof value.warningUsd !== "number") throw new Error("limitUsd and warningUsd must be numbers");
  if (!Number.isFinite(value.limitUsd) || value.limitUsd <= 0 || value.limitUsd > 1_000_000) throw new Error("limitUsd must be greater than zero and at most 1000000");
  if (!Number.isFinite(value.warningUsd) || value.warningUsd < 0 || value.warningUsd > value.limitUsd) throw new Error("warningUsd must be between zero and limitUsd");
  return { limitUsd: value.limitUsd, warningUsd: value.warningUsd };
}

async function validateMcpOrganizationRegistration(value: unknown): Promise<{ id: string; name: string; contactEmail: string; apiKeyHash: string; scopes: string[]; rateLimit: number; ipAllowlist: string[] }> {
  if (!isRecord(value)) throw new Error("organization body must be a JSON object");
  const id = validateAgentId(value.id);
  if (typeof value.name !== "string" || !value.name.trim() || value.name.length > 120) throw new Error("name must be a non-empty string up to 120 characters");
  const contactEmail = typeof value.contactEmail === "string" && value.contactEmail.length <= 254 ? value.contactEmail.trim() : "";
  const scopes = value.scopes === undefined ? ["watchtower:read"] : validateMcpScopes(value.scopes);
  const rateLimit = value.rateLimit === undefined ? 100 : value.rateLimit;
  if (!Number.isInteger(rateLimit) || rateLimit < 1 || rateLimit > 1_000) throw new Error("rateLimit must be an integer between 1 and 1000");
  const ipAllowlist = value.ipAllowlist === undefined ? [] : validateIpAllowlist(value.ipAllowlist);
  const apiKey = organizationApiKey(value);
  return { id, name: value.name.trim(), contactEmail, apiKeyHash: `sha256:${await sha256Hex(apiKey)}`, scopes, rateLimit, ipAllowlist };
}

function organizationApiKey(value: unknown): string {
  if (!isRecord(value) || typeof value.apiKey !== "string" || value.apiKey.length < 32 || value.apiKey.length > 512) throw new Error("apiKey must be a high-entropy value between 32 and 512 characters");
  return value.apiKey;
}

function validateMcpScopes(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 32) throw new Error("scopes must contain 1 to 32 entries");
  const scopePattern = /^(\*|watchtower:\*|watchtower:[a-z:]+|project:\*|project:[a-z0-9-]{1,64}(?::(?:read|control))?)$/;
  const scopes = value.map(scope => {
    if (typeof scope !== "string" || !scopePattern.test(scope)) throw new Error("scope is not supported");
    return scope;
  });
  return [...new Set(scopes)];
}

function validateIpAllowlist(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 64) throw new Error("ipAllowlist must contain at most 64 entries");
  return value.map(entry => {
    if (typeof entry !== "string" || !entry.trim() || entry.length > 64) throw new Error("ip allowlist entry is invalid");
    return entry.trim();
  });
}

function organizationStatus(value: unknown): "active" | "suspended" | "revoked" {
  if (!isRecord(value) || (value.status !== "active" && value.status !== "suspended" && value.status !== "revoked")) throw new Error("status must be active, suspended, or revoked");
  return value.status;
}

function sanitizeMcpOrganization(organization: any): Record<string, unknown> {
  return {
    id: organization.id, name: organization.name, contactEmail: organization.contact_email,
    scopes: safeJsonArray(organization.scopes), rateLimit: organization.rate_limit,
    ipAllowlist: safeJsonArray(organization.ip_allowlist), status: organization.status,
    createdAt: organization.created_at, lastAccessAt: organization.last_access_at,
  };
}

function safeJsonArray(value: unknown): unknown[] {
  try { const parsed = typeof value === "string" ? JSON.parse(value) : value; return Array.isArray(parsed) ? parsed : []; } catch { return []; }
}

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
