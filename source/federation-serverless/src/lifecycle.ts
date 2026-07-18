import type { AgentRegistry, WatchtowerEnv } from "./agent-registry.ts";
import type { FederationCoordinator } from "./federation-coordinator.ts";
import type { AgentWatchdog } from "./agent-watchdog.ts";
import type { ProjectGuardrail } from "./project-guardrail.ts";
import { sha256Hex, validateAgentId, validateOperationalEvent, validateProjectId } from "./watchtower.ts";

type Json = (data: unknown, status?: number) => Response;
type BoundedJson = (request: Request) => Promise<{ raw: string; value: unknown }>;

const OWNER_PREFIX = "fw_owner_";
const AGENT_PREFIX = "fw_agent_";
const SAFE_PALETTES = new Set(["operator", "build", "testing", "analysis", "security", "support", "observer"]);
const SAFE_CHARACTERS = new Set(["operator", "observer", "runner", "watchdog"]);
const SENSITIVE_KEY = /authorization|api[_-]?key|token|secret|password|cookie|credential/i;

interface Owner { id: string; display_name: string; owner_type: "individual" | "organization"; status: "active" | "revoked"; }
interface CanonicalAgent {
  id: string; project_id: string; agent_id: string; owner_id: string; organization_id: string | null;
  display_name: string; role: string; capabilities: string; avatar_seed: string; palette_key: string;
  character_type: string; public_projection: number; heartbeat_seconds: number; lifecycle_state: string;
}

interface Manifest {
  agentId: string; displayName: string; ownerId: string; projectId: string; role: string; capabilities: string[];
  identity: { avatarSeed: string; paletteKey: string; characterType: string };
  publicProjection: boolean; heartbeatSeconds: number; organizationId?: string;
}

export async function handleLifecycleRequest(input: {
  request: Request; path: string; method: string; env: WatchtowerEnv; coordinator: FederationCoordinator;
  json: Json; readBoundedJson: BoundedJson;
}): Promise<Response | null> {
  const { request, path, method, env, coordinator, json, readBoundedJson } = input;

  if (path === "/api/v1/owners" && method === "POST") {
    const { value } = await readBoundedJson(request);
    const body = record(value, "owner body");
    const ownerId = validateAgentId(body.ownerId);
    const displayName = text(body.displayName, "displayName", 80);
    const ownerType = body.ownerType === "organization" ? "organization" : body.ownerType === "individual" ? "individual" : fail("ownerType must be individual or organization");
    const existing = await env.DB.prepare("SELECT id FROM federation_owners WHERE id = ?").bind(ownerId).first();
    if (existing) return json({ error: "ownerId is already registered" }, 409);
    const credential = issue(OWNER_PREFIX);
    const now = Date.now();
    await env.DB.prepare("INSERT INTO federation_owners (id, display_name, owner_type, credential_hash, status, created_at, updated_at) VALUES (?, ?, ?, ?, 'active', ?, ?)")
      .bind(ownerId, displayName, ownerType, await sha256Hex(credential), now, now).run();
    return json({ owner: { ownerId, displayName, ownerType, status: "active" }, credential: { token: credential, scopes: ["owner:agents", "owner:organizations"], issuedAt: now }, requestId: crypto.randomUUID() }, 201);
  }

  const organizationMatch = path === "/api/v1/organizations/applications" && method === "POST";
  if (organizationMatch) {
    const owner = await authenticateOwner(request, env);
    if (!owner) return json({ error: "an active owner credential is required" }, 401);
    const { value } = await readBoundedJson(request);
    const body = record(value, "organization application");
    const organizationId = validateAgentId(body.organizationId);
    const name = text(body.name, "name", 120);
    const contactEmail = email(body.contactEmail);
    const officialUrl = httpsUrl(body.officialUrl, "officialUrl");
    const socialProofs = array(body.socialProofs, "socialProofs", 2, 12).map(item => {
      const proof = record(item, "social proof");
      const platform = text(proof.platform, "socialProof.platform", 40).toLowerCase();
      if (platform === "github") fail("socialProofs must include two non-GitHub profiles");
      return { platform, url: httpsUrl(proof.url, "socialProof.url") };
    });
    if (new Set(socialProofs.map(proof => `${proof.platform}:${proof.url}`)).size !== socialProofs.length) fail("socialProofs must be unique");
    const questions = array(body.technicalQuestions, "technicalQuestions", 5, 5).map(item => {
      const question = record(item, "technical question");
      return { question: text(question.question, "technicalQuestions.question", 500), answer: text(question.answer, "technicalQuestions.answer", 2_000) };
    });
    const exists = await env.DB.prepare("SELECT id FROM federation_organizations WHERE id = ?").bind(organizationId).first();
    if (exists) return json({ error: "organizationId is already registered" }, 409);
    const now = Date.now();
    const statements: D1PreparedStatement[] = [
      env.DB.prepare("INSERT INTO federation_organizations (id, owner_id, name, contact_email, official_url, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'submitted', ?, ?)")
        .bind(organizationId, owner.id, name, contactEmail, officialUrl, now, now),
    ];
    for (const proof of socialProofs) statements.push(env.DB.prepare("INSERT INTO federation_organization_social_proofs (organization_id, platform, url, created_at) VALUES (?, ?, ?, ?)").bind(organizationId, proof.platform, proof.url, now));
    questions.forEach((item, index) => statements.push(env.DB.prepare("INSERT INTO federation_organization_questions (id, organization_id, position, question, answer, submitted_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)").bind(`orgq-${crypto.randomUUID()}`, organizationId, index + 1, item.question, item.answer, owner.id, now)));
    await env.DB.batch(statements);
    return json({ application: { organizationId, name, status: "submitted", questionCount: 5, socialProofCount: socialProofs.length }, requestId: crypto.randomUUID() }, 201);
  }

  if (path === "/api/v1/agents" && method === "POST") {
    const owner = await authenticateOwner(request, env);
    if (!owner) return json({ error: "an active owner credential is required" }, 401);
    const { value } = await readBoundedJson(request);
    const manifest = validateLifecycleManifest(value);
    if (manifest.ownerId !== owner.id) return json({ error: "ownerId does not match the credential" }, 403);
    const canonicalId = `${manifest.projectId}:${manifest.agentId}`;
    const existing = await env.DB.prepare("SELECT id FROM federation_agents WHERE id = ?").bind(canonicalId).first();
    if (existing) return json({ error: "agentId is already registered in this project" }, 409);
    if (manifest.organizationId) {
      const organization = await env.DB.prepare("SELECT owner_id, status FROM federation_organizations WHERE id = ?").bind(manifest.organizationId).first<{ owner_id: string; status: string }>();
      if (!organization || organization.owner_id !== owner.id) return json({ error: "organizationId is not owned by this credential" }, 403);
    }
    if (!await coordinator.getProjectSummary(manifest.projectId)) {
      await coordinator.registerProject({ id: manifest.projectId, name: manifest.projectId, track: "Federation lifecycle", color: "#4fd1c5", emoji: "📡", prefix: "FW" });
    }
    const registry = env.AGENT_REGISTRY.get(env.AGENT_REGISTRY.idFromName(`${manifest.projectId}-registry`)) as DurableObjectStub<AgentRegistry>;
    const now = Date.now();
    const legacy = manifest.publicProjection ? await registry.registerAgent({ agentId: manifest.agentId, projectId: manifest.projectId, name: manifest.displayName, role: manifest.role, capabilities: manifest.capabilities, status: "offline", metadata: { ownerLabel: owner.display_name, publicProjection: true, paletteKey: manifest.identity.paletteKey, characterType: manifest.identity.characterType } }) : null;
    await env.DB.prepare("INSERT INTO federation_agents (id, project_id, agent_id, owner_id, organization_id, display_name, role, capabilities, avatar_seed, palette_key, character_type, public_projection, heartbeat_seconds, lifecycle_state, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'registered', ?, ?)")
      .bind(canonicalId, manifest.projectId, manifest.agentId, owner.id, manifest.organizationId || null, manifest.displayName, manifest.role, JSON.stringify(manifest.capabilities), manifest.identity.avatarSeed, manifest.identity.paletteKey, manifest.identity.characterType, manifest.publicProjection ? 1 : 0, manifest.heartbeatSeconds, now, now).run();
    const token = issue(AGENT_PREFIX);
    await env.DB.prepare("INSERT INTO federation_agent_credentials (id, agent_id, credential_hash, scopes, issued_at) VALUES (?, ?, ?, ?, ?)")
      .bind(`agentcred-${crypto.randomUUID()}`, canonicalId, await sha256Hex(token), JSON.stringify(["agent:connect", "agent:heartbeat", "agent:emit", "agent:disconnect"]), now).run();
    await appendLifecycle(env, canonicalId, "agent.registered", `register-${crypto.randomUUID()}`, { publicProjection: manifest.publicProjection, roomId: legacy?.roomId }, now);
    return json({ agent: presentAgent({ id: canonicalId, project_id: manifest.projectId, agent_id: manifest.agentId, owner_id: owner.id, organization_id: manifest.organizationId || null, display_name: manifest.displayName, role: manifest.role, capabilities: JSON.stringify(manifest.capabilities), avatar_seed: manifest.identity.avatarSeed, palette_key: manifest.identity.paletteKey, character_type: manifest.identity.characterType, public_projection: manifest.publicProjection ? 1 : 0, heartbeat_seconds: manifest.heartbeatSeconds, lifecycle_state: "registered" }, legacy?.roomId), credential: { token, scopes: ["agent:connect", "agent:heartbeat", "agent:emit", "agent:disconnect"], issuedAt: now }, next: { connect: `/api/v1/agents/${encodeURIComponent(manifest.agentId)}/connect`, heartbeat: `/api/v1/agents/${encodeURIComponent(manifest.agentId)}/heartbeat`, event: `/api/v1/agents/${encodeURIComponent(manifest.agentId)}/events` }, requestId: crypto.randomUUID() }, 201);
  }

  const agentMatch = path.match(/^\/api\/v1\/agents\/([^/]+)\/(connect|heartbeat|events|disconnect)$/);
  if (!agentMatch || method !== "POST") return null;
  const agentId = validateAgentId(agentMatch[1]);
  const action = agentMatch[2];
  const { value, raw } = await readBoundedJson(request);
  const body = record(value, "agent lifecycle body");
  const projectId = validateProjectId(body.projectId);
  const agent = await authenticateAgent(request, env, projectId, agentId);
  if (!agent) return json({ error: "an active credential for this agent is required" }, 401);
  const registry = env.AGENT_REGISTRY.get(env.AGENT_REGISTRY.idFromName(`${projectId}-registry`)) as DurableObjectStub<AgentRegistry>;
  const watchdog = env.AGENT_WATCHDOG.get(env.AGENT_WATCHDOG.idFromName(`${projectId}:${agentId}`)) as DurableObjectStub<AgentWatchdog>;
  const now = Date.now();
  if (action === "disconnect") {
    await registry.setAgentStatus(agentId, "offline");
    await watchdog.disconnect({ projectId, agentId });
    await env.DB.prepare("UPDATE federation_agents SET lifecycle_state = 'offline', disconnected_at = ?, updated_at = ? WHERE id = ?").bind(now, now, agent.id).run();
    await appendLifecycle(env, agent.id, "agent.disconnected", optionalId(body.idempotencyKey), {}, now);
    return json({ agent: { ...presentAgent(agent), lifecycleState: "offline" }, requestId: crypto.randomUUID() });
  }
  const deadlineAt = now + agent.heartbeat_seconds * 1_000;
  await registry.heartbeat(agentId);
  await watchdog.recordHeartbeat({ projectId, agentId, deadlineAt });
  await env.DB.prepare("UPDATE federation_agents SET lifecycle_state = 'connected', connected_at = COALESCE(connected_at, ?), last_heartbeat_at = ?, disconnected_at = NULL, updated_at = ? WHERE id = ?").bind(now, now, now, agent.id).run();
  if (action === "events") {
    const event = validateOperationalEvent({ schemaVersion: "2026-07-17", eventId: body.eventId || `evt-${crypto.randomUUID()}`, idempotencyKey: body.idempotencyKey || `agent-event-${crypto.randomUUID()}`, projectId, agentId, eventType: body.eventType, severity: body.severity, occurredAt: body.occurredAt || new Date(now).toISOString(), statement: body.statement, metadata: body.metadata || {} });
    const guardrail = env.PROJECT_GUARDRAIL.get(env.PROJECT_GUARDRAIL.idFromName(projectId)) as DurableObjectStub<ProjectGuardrail>;
    const result = await guardrail.ingest({ event, producerId: `agent:${agent.id}`, payloadDigest: await sha256Hex(raw), receivedAt: now });
    if (result.alerts.length) await env.WATCHTOWER_ALERTS.sendBatch(result.alerts.map(alert => ({ body: alert })));
    if (agent.public_projection) await registry.recordPublicEvent({ eventType: event.eventType, agentId, message: event.statement, priority: event.severity === "critical" ? "critical" : event.severity === "error" ? "high" : "normal", metadata: { lifecycle: "canonical", eventId: event.eventId } });
    await appendLifecycle(env, agent.id, event.eventType, event.idempotencyKey, { severity: event.severity }, now);
    return json({ accepted: true, eventId: event.eventId, watchdogDeadlineAt: deadlineAt, guardrail: result, requestId: crypto.randomUUID() }, result.duplicate ? 200 : 201);
  }
  await appendLifecycle(env, agent.id, action === "connect" ? "agent.connected" : "agent.heartbeat", optionalId(body.idempotencyKey), { deadlineAt }, now);
  return json({ agent: { ...presentAgent(agent), lifecycleState: "connected", lastHeartbeatAt: now }, watchdogDeadlineAt: deadlineAt, requestId: crypto.randomUUID() });
}

async function authenticateOwner(request: Request, env: WatchtowerEnv): Promise<Owner | null> {
  const token = bearer(request, OWNER_PREFIX); if (!token) return null;
  return env.DB.prepare("SELECT id, display_name, owner_type, status FROM federation_owners WHERE credential_hash = ? AND status = 'active'").bind(await sha256Hex(token)).first<Owner>();
}

async function authenticateAgent(request: Request, env: WatchtowerEnv, projectId: string, agentId: string): Promise<CanonicalAgent | null> {
  const token = bearer(request, AGENT_PREFIX); if (!token) return null;
  return env.DB.prepare(`SELECT a.* FROM federation_agents a JOIN federation_agent_credentials c ON c.agent_id = a.id WHERE a.project_id = ? AND a.agent_id = ? AND a.lifecycle_state != 'revoked' AND c.credential_hash = ? AND c.revoked_at IS NULL AND (c.expires_at IS NULL OR c.expires_at > ?)`)
    .bind(projectId, agentId, await sha256Hex(token), Date.now()).first<CanonicalAgent>();
}

export function validateLifecycleManifest(value: unknown): Manifest {
  const body = record(value, "manifest"); const identity = record(body.identity, "identity"); const heartbeat = record(body.heartbeat, "heartbeat");
  const capabilities = array(body.capabilities, "capabilities", 1, 16).map(item => validateAgentId(item));
  if (new Set(capabilities).size !== capabilities.length) fail("capabilities must be unique");
  const paletteKey = text(identity.paletteKey, "identity.paletteKey", 32).toLowerCase(); if (!SAFE_PALETTES.has(paletteKey)) fail("identity.paletteKey is not supported");
  const characterType = text(identity.characterType, "identity.characterType", 32).toLowerCase(); if (!SAFE_CHARACTERS.has(characterType)) fail("identity.characterType is not supported");
  if (typeof body.publicProjection !== "boolean") fail("publicProjection must be a boolean");
  const heartbeatSeconds = integer(heartbeat.intervalSeconds, "heartbeat.intervalSeconds", 30, 3600);
  rejectSensitive(body.metadata);
  return { agentId: validateAgentId(body.agentId), displayName: text(body.displayName, "displayName", 80), ownerId: validateAgentId(body.ownerId), projectId: validateProjectId(body.projectId), role: text(body.role, "role", 80), capabilities, identity: { avatarSeed: validateAgentId(identity.avatarSeed), paletteKey, characterType }, publicProjection: body.publicProjection, heartbeatSeconds, organizationId: body.organizationId === undefined ? undefined : validateAgentId(body.organizationId) };
}

async function appendLifecycle(env: WatchtowerEnv, agentId: string, eventType: string, idempotencyKey: string | undefined, detail: Record<string, unknown>, occurredAt: number): Promise<void> {
  await env.DB.prepare("INSERT OR IGNORE INTO federation_lifecycle_events (id, agent_id, event_type, idempotency_key, detail, occurred_at) VALUES (?, ?, ?, ?, ?, ?)").bind(`life-${crypto.randomUUID()}`, agentId, eventType, idempotencyKey || null, JSON.stringify(detail), occurredAt).run();
}
function presentAgent(agent: CanonicalAgent, roomId?: string) { return { agentId: agent.agent_id, projectId: agent.project_id, ownerId: agent.owner_id, organizationId: agent.organization_id || undefined, displayName: agent.display_name, role: agent.role, capabilities: JSON.parse(agent.capabilities), identity: { avatarSeed: agent.avatar_seed, paletteKey: agent.palette_key, characterType: agent.character_type }, publicProjection: Boolean(agent.public_projection), heartbeat: { intervalSeconds: agent.heartbeat_seconds }, lifecycleState: agent.lifecycle_state, roomId }; }
function bearer(request: Request, prefix: string): string | null { const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") || ""; return token.startsWith(prefix) ? token : null; }
function issue(prefix: string): string { const bytes = new Uint8Array(32); crypto.getRandomValues(bytes); return `${prefix}${Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("")}`; }
function record(value: unknown, label: string): Record<string, unknown> { if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${label} must be a JSON object`); return value as Record<string, unknown>; }
function array(value: unknown, label: string, min: number, max: number): unknown[] { if (!Array.isArray(value) || value.length < min || value.length > max) fail(`${label} must contain ${min === max ? min : `${min}-${max}`} entries`); return value; }
function text(value: unknown, label: string, max: number): string { if (typeof value !== "string" || !(value = value.trim()) || value.length > max) fail(`${label} must be a non-empty string up to ${max} characters`); return value; }
function integer(value: unknown, label: string, min: number, max: number): number { if (!Number.isInteger(value) || (value as number) < min || (value as number) > max) fail(`${label} must be an integer from ${min} to ${max}`); return value as number; }
function optionalId(value: unknown): string | undefined { return value === undefined ? undefined : validateAgentId(value); }
function email(value: unknown): string { const result = text(value, "contactEmail", 254); if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result)) fail("contactEmail must be valid"); return result; }
function httpsUrl(value: unknown, label: string): string { try { const url = new URL(text(value, label, 500)); if (url.protocol !== "https:") fail(`${label} must use HTTPS`); return url.toString(); } catch { fail(`${label} must be a valid HTTPS URL`); } }
function rejectSensitive(value: unknown): void { if (value === undefined) return; const body = record(value, "metadata"); for (const key of Object.keys(body)) if (SENSITIVE_KEY.test(key)) fail("metadata must not contain secret-shaped keys"); }
function fail(message: string): never { throw new Error(message); }
