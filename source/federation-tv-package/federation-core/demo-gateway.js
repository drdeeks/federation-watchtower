/** Contract-compatible local adapter. Runtime state is intentionally in-memory. */
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { dirname, extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const widgetRoot = join(__dirname, '../../federation-tv-widget/public');
const PORT = Number(process.env.PORT || 41207);
const PROJECT_ID = 'watchtower';
const PROJECT = { projectId: PROJECT_ID, name: 'Federation Watchtower', track: 'Local contract adapter' };
const agents = new Map();
const feed = [];
let nextEvent = 1;
const statuses = new Set(['active', 'busy', 'idle', 'offline']);
const actions = new Set(['working', 'pacing', 'watching', 'alerting']);
const severities = new Set(['info', 'success', 'warning', 'error', 'critical']);
const eventTypes = new Set(['agent_registered', 'heartbeat', 'status_changed', 'task_started', 'task_completed', 'test_passed', 'test_failed', 'incident_detected', 'nested_chain_detected']);

function addEvent({ agentId, eventType, severity = 'info', statement, metadata = {}, action, visibility }) {
  const event = { id: `evt_${String(nextEvent++).padStart(3, '0')}`, projectId: PROJECT_ID, projectName: PROJECT.name, agentId, eventType, event_type: eventType, severity, priority: severity, statement, message: statement, metadata, action, visibility: visibility || { publicBubble: true, publicFeed: true, auditLog: true }, timestamp: new Date().toISOString() };
  feed.unshift(event);
  return event;
}
function registerAgent(data) {
  const now = new Date().toISOString();
  const agent = { agentId: data.agentId, name: data.name, role: data.role, capabilities: data.capabilities, metadata: data.metadata || {}, projectId: PROJECT_ID, status: 'active', action: 'working', registeredAt: now, lastHeartbeat: now };
  agents.set(agent.agentId, agent);
  addEvent({ agentId: agent.agentId, eventType: 'agent_registered', statement: `${agent.name} joined Watchtower.`, metadata: { capabilities: agent.capabilities }, action: agent.action });
  return agent;
}
function validAgent(data) { return data && typeof data.agentId === 'string' && data.agentId.trim() && typeof data.name === 'string' && data.name.trim() && typeof data.role === 'string' && data.role.trim() && Array.isArray(data.capabilities) && data.capabilities.every(capability => typeof capability === 'string'); }
function seedDemo() {
  for (const data of [
    { agentId: 'watchtower-runner-1', name: 'Pipeline Runner', role: 'test runner', capabilities: ['tests'] },
    { agentId: 'watchtower-glitch-1', name: 'Glitch Reporter', role: 'failure detector', capabilities: ['incidents'] },
    { agentId: 'watchtower-watchdog-1', name: 'Chain Watchdog', role: 'governance', capabilities: ['watchdog'] }
  ]) registerAgent(data);
}
if (process.env.FEDERATION_SEED_DEMO === '1') seedDemo();

function json(res, status, body) { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' }); res.end(JSON.stringify(body)); }
async function body(req) { let value = ''; for await (const chunk of req) value += chunk; if (value.length > 64 * 1024) throw new Error('request body too large'); return JSON.parse(value || '{}'); }
function packetError(packet) {
  if (!eventTypes.has(packet.eventType)) return 'invalid eventType';
  if (!severities.has(packet.severity)) return 'invalid severity';
  if (!agents.has(packet.agentId)) return 'agentId must name a registered agent';
  if (typeof packet.statement !== 'string' || packet.statement.trim().length < 1 || packet.statement.length > 120) return 'statement must be 1–120 characters';
  if (packet.action !== undefined && !actions.has(packet.action)) return 'invalid action';
  if (feed.some(event => event.agentId === packet.agentId && event.statement === packet.statement)) return 'duplicate public statement';
}
async function staticFile(res, pathname) {
  const requested = pathname === '/' ? 'demo.html' : pathname.replace(/^\//, '');
  const file = normalize(join(widgetRoot, requested));
  if (!file.startsWith(`${widgetRoot}/`)) return json(res, 403, { error: 'forbidden' });
  try { const content = await readFile(file); const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' }; res.writeHead(200, { 'Content-Type': `${types[extname(file)] || 'application/octet-stream'}; charset=utf-8`, 'Cache-Control': 'no-store' }); res.end(content); } catch { json(res, 404, { error: 'Not found' }); }
}
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`); const { pathname } = url;
  if (req.method === 'OPTIONS') return json(res, 200, { success: true });
  if (req.method === 'GET' && pathname === '/health') return json(res, 200, { status: 'healthy', project: PROJECT_ID, agents: agents.size, events: feed.length });
  if (req.method === 'GET' && pathname === '/api/projects') return json(res, 200, { projects: [{ ...PROJECT, agentCount: agents.size, feedCount: feed.length }] });
  if (req.method === 'GET' && pathname === `/api/projects/${PROJECT_ID}/agents`) return json(res, 200, { agents: [...agents.values()] });
  if (req.method === 'GET' && pathname === '/api/feed') return json(res, 200, { events: feed.slice(0, Math.min(Number(url.searchParams.get('limit') || 100), 100)) });
  if (req.method === 'GET' && pathname === `/api/projects/${PROJECT_ID}/feed`) return json(res, 200, { events: feed.slice(0, Math.min(Number(url.searchParams.get('limit') || 100), 100)) });
  if (req.method === 'POST' && pathname === `/api/projects/${PROJECT_ID}/agents`) { try { const data = await body(req); if (!validAgent(data)) return json(res, 400, { error: 'agentId, name, role, and capabilities string array are required' }); if (agents.has(data.agentId)) return json(res, 409, { error: 'agentId already registered' }); return json(res, 201, { agent: registerAgent(data) }); } catch (error) { return json(res, 400, { error: error.message }); } }
  const heartbeat = pathname.match(/^\/api\/projects\/watchtower\/agents\/([^/]+)\/heartbeat$/);
  if (req.method === 'POST' && heartbeat) { const agent = agents.get(decodeURIComponent(heartbeat[1])); if (!agent) return json(res, 404, { error: 'agent not found' }); const previous = agent.lastHeartbeat; agent.lastHeartbeat = new Date().toISOString(); if (!agent.lastHeartbeatEventAt || Date.now() - agent.lastHeartbeatEventAt > 30_000 || !previous) { agent.lastHeartbeatEventAt = Date.now(); addEvent({ agentId: agent.agentId, eventType: 'heartbeat', statement: `${agent.name} is present.`, action: agent.action }); } return json(res, 200, { agent }); }
  const statusRoute = pathname.match(/^\/api\/projects\/watchtower\/agents\/([^/]+)\/status$/);
  if (req.method === 'PATCH' && statusRoute) { try { const data = await body(req); const agent = agents.get(decodeURIComponent(statusRoute[1])); if (!agent) return json(res, 404, { error: 'agent not found' }); if (!statuses.has(data.status) || (data.action !== undefined && !actions.has(data.action))) return json(res, 400, { error: 'invalid status or action' }); agent.status = data.status; if (data.action) agent.action = data.action; addEvent({ agentId: agent.agentId, eventType: 'status_changed', statement: `${agent.name} is ${agent.status}.`, action: agent.action, metadata: { status: agent.status } }); return json(res, 200, { agent }); } catch (error) { return json(res, 400, { error: error.message }); } }
  if (req.method === 'POST' && pathname === '/api/federation/statement') { try { const packet = await body(req); const error = packetError(packet); if (error) return json(res, error === 'duplicate public statement' ? 409 : 400, { success: false, error }); const agent = agents.get(packet.agentId); if (packet.action) agent.action = packet.action; return json(res, 201, { success: true, packet: addEvent(packet) }); } catch (error) { return json(res, 400, { success: false, error: error.message }); } }
  if (req.method === 'GET' && !pathname.startsWith('/api/')) return staticFile(res, pathname);
  return json(res, 404, { error: 'Not found' });
});
server.listen(PORT, () => console.log(`Federation Watchtower local contract adapter: http://localhost:${PORT} (${agents.size} agents; set FEDERATION_SEED_DEMO=1 to seed)`));
process.on('SIGINT', () => server.close(() => process.exit(0)));
