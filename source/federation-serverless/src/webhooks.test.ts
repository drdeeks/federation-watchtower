import assert from "node:assert/strict";
import test from "node:test";
import { validateWebhookDestinationBody, upsertWebhookDestination, resolveWebhookDestination } from "./webhooks.ts";

// ==================== VALIDATION ====================
test("validateWebhookDestinationBody accepts an HTTPS URL and normalizes format", () => {
  assert.deepEqual(validateWebhookDestinationBody({ url: "https://hooks.example/x", format: "slack" }), { url: "https://hooks.example/x", format: "slack" });
  assert.deepEqual(validateWebhookDestinationBody({ url: "https://hooks.example/x" }), { url: "https://hooks.example/x", format: "json" });
});

test("validateWebhookDestinationBody rejects non-HTTPS and malformed input", () => {
  assert.throws(() => validateWebhookDestinationBody({ url: "http://hooks.example/x" }), /HTTPS/);
  assert.throws(() => validateWebhookDestinationBody({ url: "not-a-url" }), /valid URL/);
  assert.throws(() => validateWebhookDestinationBody({}), /url must be/);
  assert.throws(() => validateWebhookDestinationBody(null), /JSON object/);
});

// ==================== FAKE D1 (scoped to exactly the statements webhooks.ts issues) ====================
interface DestRow { scope_type: string; scope_id: string; url: string; format: string; secret: string | null; updated_at: number; }

function fakeDb(agents: Array<{ id: string; organization_id: string | null }> = []) {
  const destinations: DestRow[] = [];
  return {
    destinations,
    prepare(sql: string) {
      return {
        bind(...args: unknown[]) {
          return {
            async run() {
              if (sql.startsWith("INSERT INTO webhook_destinations")) {
                const [, scope_type, scope_id, url, format, secret, , updated_at] = args as [string, string, string, string, string, string | null, number, number];
                const existing = destinations.find(d => d.scope_type === scope_type && d.scope_id === scope_id);
                if (existing) { existing.url = url; existing.format = format; existing.secret = secret; existing.updated_at = updated_at; }
                else destinations.push({ scope_type, scope_id, url, format, secret, updated_at });
                return { meta: { changes: 1 } };
              }
              throw new Error(`fakeDb: unhandled run() for: ${sql}`);
            },
            async first<T>() {
              if (sql.includes("FROM webhook_destinations WHERE scope_type = 'agent'")) {
                const [scopeId] = args as [string];
                const row = destinations.find(d => d.scope_type === "agent" && d.scope_id === scopeId);
                return (row ? { url: row.url, format: row.format, secret: row.secret } : null) as T | null;
              }
              if (sql.includes("FROM webhook_destinations WHERE scope_type = 'organization'")) {
                const [scopeId] = args as [string];
                const row = destinations.find(d => d.scope_type === "organization" && d.scope_id === scopeId);
                return (row ? { url: row.url, format: row.format, secret: row.secret } : null) as T | null;
              }
              if (sql.startsWith("SELECT organization_id FROM federation_agents")) {
                const [id] = args as [string];
                const agent = agents.find(a => a.id === id);
                return (agent ? { organization_id: agent.organization_id } : null) as T | null;
              }
              throw new Error(`fakeDb: unhandled first() for: ${sql}`);
            },
          };
        },
      };
    },
  };
}

// ==================== UPSERT ====================
test("upsertWebhookDestination generates a secret for json format and returns it once", async () => {
  const env = { DB: fakeDb() } as any;
  const result = await upsertWebhookDestination(env, "organization", "acme", { url: "https://hooks.example/acme", format: "json" });
  assert.equal(result.url, "https://hooks.example/acme");
  assert.match(result.secret!, /^[0-9a-f]{64}$/);
  assert.equal(env.DB.destinations.length, 1);
  assert.equal(env.DB.destinations[0].secret, result.secret);
});

test("upsertWebhookDestination leaves secret unset for slack/discord (the URL is the secret)", async () => {
  const env = { DB: fakeDb() } as any;
  const result = await upsertWebhookDestination(env, "organization", "acme", { url: "https://hooks.slack.com/services/x", format: "slack" });
  assert.equal(result.secret, undefined);
  assert.equal(env.DB.destinations[0].secret, null);
});

test("upsertWebhookDestination replaces (not duplicates) an existing destination for the same scope", async () => {
  const env = { DB: fakeDb() } as any;
  await upsertWebhookDestination(env, "agent", "proj:agent-1", { url: "https://hooks.example/v1", format: "json" });
  const updated = await upsertWebhookDestination(env, "agent", "proj:agent-1", { url: "https://hooks.example/v2", format: "json" });
  assert.equal(env.DB.destinations.length, 1);
  assert.equal(env.DB.destinations[0].url, "https://hooks.example/v2");
  assert.notEqual(env.DB.destinations[0].secret, undefined); // rotated to a fresh secret on replace
  assert.equal(updated.url, "https://hooks.example/v2");
});

// ==================== RESOLUTION PRECEDENCE ====================
test("resolveWebhookDestination prefers an agent-level override over the org's destination", async () => {
  const env = { DB: fakeDb([{ id: "proj:agent-1", organization_id: "acme" }]) } as any;
  await upsertWebhookDestination(env, "organization", "acme", { url: "https://hooks.example/org", format: "json" });
  await upsertWebhookDestination(env, "agent", "proj:agent-1", { url: "https://hooks.example/agent-override", format: "json" });
  const resolved = await resolveWebhookDestination(env, "proj", "agent-1");
  assert.equal(resolved!.url, "https://hooks.example/agent-override");
});

test("resolveWebhookDestination falls back to the agent's organization when no agent override exists", async () => {
  const env = { DB: fakeDb([{ id: "proj:agent-1", organization_id: "acme" }]) } as any;
  await upsertWebhookDestination(env, "organization", "acme", { url: "https://hooks.example/org", format: "json" });
  const resolved = await resolveWebhookDestination(env, "proj", "agent-1");
  assert.equal(resolved!.url, "https://hooks.example/org");
});

test("resolveWebhookDestination returns null (caller falls back to global) when neither scope is configured", async () => {
  const env = { DB: fakeDb([{ id: "proj:agent-1", organization_id: null }]) } as any;
  assert.equal(await resolveWebhookDestination(env, "proj", "agent-1"), null);
});

test("resolveWebhookDestination returns null for an agent that isn't in federation_agents at all (legacy/producer agent)", async () => {
  const env = { DB: fakeDb([]) } as any;
  assert.equal(await resolveWebhookDestination(env, "proj", "unregistered-agent"), null);
});
