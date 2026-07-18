import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { WatchtowerEnv } from "./agent-registry";
import type { FederationCoordinator } from "./federation-coordinator";
import type { ProjectGuardrail } from "./project-guardrail";
import {
  constantTimeEqual, sha256Hex, stableJson, validateCommandAcknowledgement,
  validateControlledToolAuthorizationRequest, validateLeaseRequest,
  validateLeaseValidationRequest, validateValidationGateRequest,
} from "./watchtower.ts";

export interface MCPPrincipal {
  orgId: string;
  name: string;
  scopes: string[];
  rateLimit: number;
  ipAllowlist: string[];
}

export interface MCPOrganizationRecord {
  id: string;
  name: string;
  api_key_hash: string;
  scopes: string;
  rate_limit: number;
  ip_allowlist: string;
  status: string;
}

interface MCPGatewayDependencies {
  env: WatchtowerEnv;
  coordinator: FederationCoordinator;
  guardrail(projectId: string): DurableObjectStub<ProjectGuardrail>;
}

interface ToolResponse {
  value: unknown;
  isError?: boolean;
  status?: "success" | "error" | "unauthorized";
}

const IDENTIFIER = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const PROJECT_IDENTIFIER = /^[a-z0-9][a-z0-9-]{0,63}$/;
const SHA_256_HASH = /^sha256:([a-f0-9]{64})$/i;

export function parseMcpCredential(value: string | null): { orgId: string; apiKey: string } | null {
  const token = value?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!token) return null;
  const separator = token.indexOf(".");
  if (separator <= 0 || separator === token.length - 1) return null;
  const orgId = token.slice(0, separator);
  const apiKey = token.slice(separator + 1);
  if (!IDENTIFIER.test(orgId) || apiKey.length < 32 || apiKey.length > 512) return null;
  return { orgId, apiKey };
}

export async function verifyMcpApiKey(storedHash: string, apiKey: string): Promise<boolean> {
  const match = storedHash.match(SHA_256_HASH);
  if (!match) return false;
  return constantTimeEqual(match[1].toLowerCase(), await sha256Hex(apiKey));
}

export function parseScopeList(value: string | null | undefined): string[] {
  try {
    const parsed = JSON.parse(value || "[]");
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((scope): scope is string => typeof scope === "string" && scope.length > 0 && scope.length <= 128);
  } catch {
    return [];
  }
}

export function parseIpAllowlist(value: string | null | undefined): string[] {
  try {
    const parsed = JSON.parse(value || "[]");
    return Array.isArray(parsed) ? parsed.filter((entry): entry is string => typeof entry === "string" && entry.length <= 64) : [];
  } catch {
    return [];
  }
}

export function hasMcpScope(scopes: string[], requiredScope: string, projectId?: string, projectPermission = "read"): boolean {
  const hasGlobalScope = scopes.includes("*") || scopes.includes("watchtower:*") || scopes.includes(requiredScope);
  if (!hasGlobalScope) return false;
  if (!projectId) return true;
  return scopes.includes("project:*") || scopes.includes(`project:${projectId}`) || scopes.includes(`project:${projectId}:${projectPermission}`);
}

export function isIpAllowed(clientIp: string | null, allowlist: string[]): boolean {
  if (allowlist.length === 0) return true;
  if (!clientIp) return false;
  return allowlist.some(entry => entry === clientIp || ipv4CidrContains(entry, clientIp));
}

function ipv4CidrContains(cidr: string, clientIp: string): boolean {
  const [network, maskText] = cidr.split("/");
  if (!network || maskText === undefined || !/^\d{1,2}$/.test(maskText)) return false;
  const maskBits = Number(maskText);
  if (maskBits < 0 || maskBits > 32) return false;
  const networkValue = ipv4ToNumber(network);
  const clientValue = ipv4ToNumber(clientIp);
  if (networkValue === null || clientValue === null) return false;
  const mask = maskBits === 0 ? 0 : (0xffffffff << (32 - maskBits)) >>> 0;
  return (networkValue & mask) === (clientValue & mask);
}

function ipv4ToNumber(value: string): number | null {
  const octets = value.split(".");
  if (octets.length !== 4) return null;
  let result = 0;
  for (const octet of octets) {
    if (!/^\d{1,3}$/.test(octet)) return null;
    const number = Number(octet);
    if (number > 255) return null;
    result = (result << 8) | number;
  }
  return result >>> 0;
}

export function toMcpPrincipal(org: MCPOrganizationRecord): MCPPrincipal {
  return {
    orgId: org.id,
    name: org.name,
    scopes: parseScopeList(org.scopes),
    rateLimit: Math.min(Math.max(Number.isInteger(org.rate_limit) ? org.rate_limit : 100, 1), 1_000),
    ipAllowlist: parseIpAllowlist(org.ip_allowlist),
  };
}

function textResult(response: ToolResponse) {
  return {
    isError: response.isError ?? false,
    content: [{ type: "text" as const, text: stableJson(response.value) }],
  };
}

async function executeTool(
  principal: MCPPrincipal,
  dependencies: MCPGatewayDependencies,
  input: { toolName: string; requiredScope: string; projectId?: string; projectPermission?: string; params: Record<string, unknown> },
  handler: () => Promise<ToolResponse>,
) {
  const requestId = crypto.randomUUID();
  const projectPermission = input.projectPermission ?? "read";
  if (!hasMcpScope(principal.scopes, input.requiredScope, input.projectId, projectPermission)) {
    await dependencies.coordinator.logMCPAccess({
      orgId: principal.orgId, toolName: input.toolName, params: input.params, projectId: input.projectId,
      status: "unauthorized", errorMessage: `missing ${input.requiredScope} or project scope`, requestId,
    });
    return textResult({ value: { error: "scope denied", requiredScope: input.requiredScope, projectId: input.projectId }, isError: true, status: "unauthorized" });
  }

  try {
    const response = await handler();
    await dependencies.coordinator.logMCPAccess({
      orgId: principal.orgId, toolName: input.toolName, params: input.params, projectId: input.projectId,
      status: response.status ?? (response.isError ? "error" : "success"), requestId,
    });
    return textResult(response);
  } catch (cause) {
    const detail = cause instanceof Error ? cause.message.slice(0, 240) : "tool execution failed";
    await dependencies.coordinator.logMCPAccess({
      orgId: principal.orgId, toolName: input.toolName, params: input.params, projectId: input.projectId,
      status: "error", errorMessage: detail, requestId,
    });
    return textResult({ value: { error: detail }, isError: true, status: "error" });
  }
}

const projectId = z.string().regex(PROJECT_IDENTIFIER, "projectId must be a valid project identifier");
const identifier = z.string().regex(IDENTIFIER, "identifier contains unsupported characters");

export function createWatchtowerMcpServer(principal: MCPPrincipal, dependencies: MCPGatewayDependencies): McpServer {
  const server = new McpServer({ name: "Federation Watchtower", version: "2026.07" });

  server.registerTool("watchtower_whoami", {
    title: "Watchtower principal",
    description: "Return the scoped Federation organization principal backing this MCP connection.",
  }, async () => executeTool(principal, dependencies, {
    toolName: "watchtower_whoami", requiredScope: "watchtower:read", params: {},
  }, async () => ({ value: { organization: principal.orgId, name: principal.name, scopes: principal.scopes, rateLimitPerMinute: principal.rateLimit } })));

  server.registerTool("watchtower_get_status", {
    title: "Watchtower system status",
    description: "Read aggregate Watchtower project and agent health. This returns public-safe operational counts only.",
  }, async () => executeTool(principal, dependencies, {
    toolName: "watchtower_get_status", requiredScope: "watchtower:read", params: {},
  }, async () => ({ value: await dependencies.coordinator.getSystemStatus() })));

  server.registerTool("watchtower_get_project", {
    title: "Watchtower project summary",
    description: "Read one project summary. Requires watchtower:read plus project:<projectId>:read.",
    inputSchema: { projectId },
  }, async ({ projectId: requestedProjectId }) => executeTool(principal, dependencies, {
    toolName: "watchtower_get_project", requiredScope: "watchtower:read", projectId: requestedProjectId, params: { projectId: requestedProjectId },
  }, async () => {
    const summary = await dependencies.coordinator.getProjectSummary(requestedProjectId);
    return summary ? { value: summary } : { value: { error: "project not found" }, isError: true, status: "error" };
  }));

  server.registerTool("watchtower_get_incidents", {
    title: "Watchtower incidents",
    description: "Read the current private incident ledger for one allowed project.",
    inputSchema: { projectId, limit: z.number().int().min(1).max(100).default(50) },
  }, async ({ projectId: requestedProjectId, limit }) => executeTool(principal, dependencies, {
    toolName: "watchtower_get_incidents", requiredScope: "watchtower:read", projectId: requestedProjectId, params: { projectId: requestedProjectId, limit },
  }, async () => ({ value: { incidents: await dependencies.guardrail(requestedProjectId).getIncidents(limit) } })));

  server.registerTool("watchtower_get_sessions", {
    title: "Watchtower session registry",
    description: "Read active, blocked, completed, and failed agent-run sessions for one allowed project.",
    inputSchema: { projectId, limit: z.number().int().min(1).max(200).default(100) },
  }, async ({ projectId: requestedProjectId, limit }) => executeTool(principal, dependencies, {
    toolName: "watchtower_get_sessions", requiredScope: "watchtower:read", projectId: requestedProjectId, params: { projectId: requestedProjectId, limit },
  }, async () => ({ value: { sessions: await dependencies.guardrail(requestedProjectId).getSessions(limit) } })));

  server.registerTool("watchtower_get_budget", {
    title: "Watchtower credit budget",
    description: "Read the configured credit limit, warning level, observed spend, and remaining budget for one allowed project.",
    inputSchema: { projectId },
  }, async ({ projectId: requestedProjectId }) => executeTool(principal, dependencies, {
    toolName: "watchtower_get_budget", requiredScope: "watchtower:budget:read", projectId: requestedProjectId, params: { projectId: requestedProjectId },
  }, async () => ({ value: { budget: await dependencies.guardrail(requestedProjectId).getBudget() } })));

  server.registerTool("watchtower_request_lease", {
    title: "Request a bounded work lease",
    description: "Acquire a 30–900 second cooperative lease before a consequential run. Requires watchtower:lease and project:<projectId>:control.",
    inputSchema: { projectId, agentId: identifier, runId: identifier, ttlSeconds: z.number().int().min(30).max(900), scopes: z.array(identifier).max(16).default([]) },
  }, async (input) => executeTool(principal, dependencies, {
    toolName: "watchtower_request_lease", requiredScope: "watchtower:lease", projectId: input.projectId, projectPermission: "control", params: input,
  }, async () => {
    const request = validateLeaseRequest(input);
    const lease = await dependencies.guardrail(request.projectId).requestLease(request, `mcp:${principal.orgId}`);
    return { value: lease, isError: lease.status !== "active", status: lease.status === "active" ? "success" : "error" };
  }));

  server.registerTool("watchtower_validate_lease", {
    title: "Validate a work lease",
    description: "Check a lease immediately before the next controlled action. A non-active result means the caller must stop.",
    inputSchema: { projectId, agentId: identifier, leaseId: identifier },
  }, async (input) => executeTool(principal, dependencies, {
    toolName: "watchtower_validate_lease", requiredScope: "watchtower:lease", projectId: input.projectId, projectPermission: "control", params: input,
  }, async () => {
    const { agentId } = validateLeaseValidationRequest({ agentId: input.agentId });
    const lease = await dependencies.guardrail(input.projectId).validateLease(input.projectId, input.leaseId, agentId);
    return { value: lease, isError: lease.status !== "active", status: lease.status === "active" ? "success" : "error" };
  }));

  server.registerTool("watchtower_authorize_action", {
    title: "Authorize a controlled action",
    description: "The mandatory pre-action gate for an existing Loop Enforcer client. It records an allow or deny decision before the client executes its configured tool; Watchtower never proxies arbitrary URLs.",
    inputSchema: { projectId, agentId: identifier, leaseId: identifier, toolName: identifier, action: identifier, requestId: identifier, inputDigest: z.string().regex(/^[a-f0-9]{64}$/i) },
  }, async (input) => executeTool(principal, dependencies, {
    toolName: "watchtower_authorize_action", requiredScope: "watchtower:actions:authorize", projectId: input.projectId, projectPermission: "control", params: input,
  }, async () => {
    const request = validateControlledToolAuthorizationRequest(input);
    const authorization = await dependencies.guardrail(request.projectId).authorizeControlledTool(request, `mcp:${principal.orgId}`, principal.orgId);
    return {
      value: { ...authorization, enforcement: "The caller must execute only after status=authorized. No arbitrary outbound target is configured in Watchtower." },
      isError: authorization.status !== "authorized", status: authorization.status === "authorized" ? "success" : "error",
    };
  }));

  server.registerTool("watchtower_validate_gate", {
    title: "Run a validation gate",
    description: "Record a pass or fail validation outcome before a controlled step. A failed gate or inactive lease returns allowed=false and the client must not continue.",
    inputSchema: { projectId, agentId: identifier, runId: identifier, leaseId: identifier.optional(), gateId: identifier, requestId: identifier, passed: z.boolean(), statement: z.string().min(1).max(120), metadata: z.record(z.string(), z.unknown()).default({}) },
  }, async (input) => executeTool(principal, dependencies, {
    toolName: "watchtower_validate_gate", requiredScope: "watchtower:validation:gate", projectId: input.projectId, projectPermission: "control", params: { ...input, metadata: "[redacted from MCP audit parameters]" },
  }, async () => {
    const gate = validateValidationGateRequest(input);
    const result = await dependencies.guardrail(gate.projectId).evaluateValidationGate(gate, `mcp:${principal.orgId}`);
    return { value: result, isError: !result.allowed, status: result.allowed ? "success" : "error" };
  }));

  server.registerTool("watchtower_acknowledge_command", {
    title: "Acknowledge a containment command",
    description: "Record whether a Watchtower pause, quarantine, or approval command was contained, rejected, or failed.",
    inputSchema: { projectId, commandId: identifier, agentId: identifier, outcome: z.enum(["contained", "rejected", "failed"]), note: z.string().max(240).optional() },
  }, async (input) => executeTool(principal, dependencies, {
    toolName: "watchtower_acknowledge_command", requiredScope: "watchtower:commands:acknowledge", projectId: input.projectId, projectPermission: "control", params: input,
  }, async () => {
    const acknowledgement = validateCommandAcknowledgement(input);
    const result = await dependencies.guardrail(input.projectId).acknowledgeCommand(input.projectId, acknowledgement);
    return { value: result, isError: !result.success, status: result.success ? "success" : "error" };
  }));

  server.registerTool("watchtower_simulate_policy", {
    title: "Simulate a policy decision",
    description: "Evaluate the current deterministic policy against a historical event without opening an incident or issuing a command.",
    inputSchema: { projectId, eventId: identifier },
  }, async (input) => executeTool(principal, dependencies, {
    toolName: "watchtower_simulate_policy", requiredScope: "watchtower:policy:simulate", projectId: input.projectId, params: input,
  }, async () => ({ value: await dependencies.coordinator.simulatePolicy(input.projectId, input.eventId) })));

  server.registerTool("watchtower_export_evidence", {
    title: "Create a retained audit export",
    description: "Create a redacted JSON evidence export in the Watchtower R2 vault. The returned export ID is used to retrieve the evidence through the authorized API.",
    inputSchema: { projectId, retentionDays: z.number().int().min(1).max(365).default(30) },
  }, async (input) => executeTool(principal, dependencies, {
    toolName: "watchtower_export_evidence", requiredScope: "watchtower:evidence:export", projectId: input.projectId, params: input,
  }, async () => ({ value: await dependencies.coordinator.exportProjectEvidence(input.projectId, `mcp:${principal.orgId}`, input.retentionDays) })));

  return server;
}
