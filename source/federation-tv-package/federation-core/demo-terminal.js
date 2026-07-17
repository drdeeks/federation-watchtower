const base = `http://localhost:${process.env.PORT || 41207}`;
const get = async path => {
  const response = await fetch(`${base}${path}`);
  if (!response.ok) throw new Error(`GET ${path}: ${response.status}`);
  return response.json();
};

const [health, registry, audit] = await Promise.all([
  get('/health'), get('/api/projects/watchtower/agents'), get('/api/feed?limit=100')
]);
console.log('Federation Watchtower');
console.log('=====================');
console.log('\nRegistered agents:');
for (const agent of registry.agents) console.log(`- ${agent.agentId} — ${agent.name} (${agent.role}) [${agent.status}/${agent.action}]`);
console.log('\nEvent packets and mapped speech bubbles:');
for (const event of [...audit.events].reverse()) {
  console.log(`- [${event.eventType}] ${event.agentId}: ${event.statement || event.message}`);
  if (event.statement || event.message) console.log(`  Mapped speech bubble: “${event.statement || event.message}”`);
}
const valid = health.status === 'healthy' && registry.agents.length > 0 && audit.events.length > 0;
console.log('\nFinal verification summary:');
console.log(JSON.stringify({ ok: valid, agents: registry.agents.length, events: audit.events.length }, null, 2));
if (!valid) process.exitCode = 1;
