const base = `http://localhost:${process.env.PORT || 41207}`;
async function request(path, method = 'GET', body) { const response = await fetch(`${base}${path}`, { method, headers: body ? { 'Content-Type': 'application/json' } : undefined, body: body ? JSON.stringify(body) : undefined }); const data = await response.json(); if (!response.ok) throw new Error(`${method} ${path}: ${response.status} ${data.error || ''}`); return data; }
const health = await request('/health');
const dynamicAgentId = `verifier-${Date.now()}`;
const agent = { agentId: dynamicAgentId, name: `Verifier ${Date.now()}`, role: 'integration verifier', capabilities: ['register', 'heartbeat', 'status', 'packet'] };
await request('/api/projects/watchtower/agents', 'POST', agent);
const listed = await request('/api/projects/watchtower/agents');
if (!listed.agents.some(item => item.agentId === dynamicAgentId)) throw new Error('dynamic agent missing from registry');
await request(`/api/projects/watchtower/agents/${dynamicAgentId}/heartbeat`, 'POST');
await request(`/api/projects/watchtower/agents/${dynamicAgentId}/status`, 'PATCH', { status: 'busy', action: 'pacing' });
const statement = `Verifier completed task ${Date.now()}`;
const accepted = await request('/api/federation/statement', 'POST', { agentId: dynamicAgentId, eventType: 'task_completed', severity: 'success', statement, action: 'working' });
const feed = await request('/api/feed?limit=100');
const lifecycle = ['agent_registered', 'heartbeat', 'status_changed', 'task_completed'];
if (!lifecycle.every(type => feed.events.some(event => event.agentId === dynamicAgentId && event.eventType === type))) throw new Error('missing lifecycle event');
if (!feed.events.some(event => event.agentId === dynamicAgentId && event.statement === statement)) throw new Error('public statement missing');
console.log(JSON.stringify({ ok: true, health: health.status, dynamicAgentId, lifecycleEvents: lifecycle, packetAccepted: accepted.success === true }, null, 2));
