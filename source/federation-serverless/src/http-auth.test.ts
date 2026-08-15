import assert from "node:assert/strict";
import test from "node:test";
import { authenticateCanonicalOrProducer, authenticateProducer, HttpError } from "./http-auth.ts";
import { hmacSha256Hex, sha256Hex } from "./watchtower.ts";

// MOD-002 / FEAT-002 integration coverage: the four previously HMAC-only
// routes (lease validate, tool authorize, validation gates, commands
// get+acknowledge) now share this one dual-auth helper. Exercised here
// against a fake D1 scoped to authenticateAgent's real join query, plus
// genuine HMAC-signed requests, rather than a full mocked-DO fetch() call --
// matching this repo's existing convention of testing exported logic
// directly instead of the whole Worker request pipeline.
interface AgentRow { id: string; project_id: string; agent_id: string; lifecycle_state: string; paused_at: number | null; }
interface CredRow { agent_id: string; credential_hash: string; revoked_at: number | null; expires_at: number | null; }

function fakeAgentDb(agents: AgentRow[], creds: CredRow[]) {
  return {
    prepare(sql: string) {
      return {
        bind(...args: unknown[]) {
          return {
            async first<T>() {
              if (sql.includes("FROM federation_agents a JOIN federation_agent_credentials c")) {
                const [projectId, agentId, credentialHash, now] = args as [string, string, string, number];
                const agent = agents.find(a => a.project_id === projectId && a.agent_id === agentId && a.lifecycle_state !== "revoked" && a.paused_at === null);
                if (!agent) return null;
                const cred = creds.find(c => c.agent_id === agent.id && c.credential_hash === credentialHash && c.revoked_at === null && (c.expires_at === null || c.expires_at > now));
                return (cred ? agent : null) as T | null;
              }
              throw new Error(`fakeAgentDb: unhandled first() for: ${sql}`);
            },
            async run() {
              if (sql.startsWith("UPDATE federation_agent_credentials SET last_used_at")) {
                const [lastUsedAt, credentialHash] = args as [number, string];
                const cred = creds.find(c => c.credential_hash === credentialHash);
                if (cred) (cred as CredRow & { last_used_at?: number }).last_used_at = lastUsedAt;
                return { meta: { changes: cred ? 1 : 0 } };
              }
              throw new Error(`fakeAgentDb: unhandled run() for: ${sql}`);
            },
          };
        },
      };
    },
  };
}

async function env(opts: { agents: AgentRow[]; creds: CredRow[]; ingestionSecret?: string }) {
  return { DB: fakeAgentDb(opts.agents, opts.creds), WATCHTOWER_INGESTION_SECRET: opts.ingestionSecret, ENVIRONMENT: undefined } as any;
}

async function setup(token: string) {
  const agent: AgentRow = { id: "proj:agent-1", project_id: "proj", agent_id: "agent-1", lifecycle_state: "connected", paused_at: null };
  const cred: CredRow = { agent_id: "proj:agent-1", credential_hash: await sha256Hex(token), revoked_at: null, expires_at: null };
  return { agent, cred };
}

test("a present fw_agent_* bearer authenticates canonically and never touches HMAC", async () => {
  const token = "fw_agent_" + "a".repeat(64);
  const { agent, cred } = await setup(token);
  const e = await env({ agents: [agent], creds: [cred], ingestionSecret: "unused-because-canonical-wins" });
  const request = new Request("https://fapi.drdeeks.xyz/x", { headers: { Authorization: `Bearer ${token}` } });
  const producerId = await authenticateCanonicalOrProducer(request, "", e, "proj", "agent-1");
  assert.equal(producerId, "agent:proj:agent-1");
});

test("a successful canonical authentication stamps the credential's last_used_at", async () => {
  const token = "fw_agent_" + "c".repeat(64);
  const { agent, cred } = await setup(token);
  const e = await env({ agents: [agent], creds: [cred] });
  const request = new Request("https://fapi.drdeeks.xyz/x", { headers: { Authorization: `Bearer ${token}` } });
  const before = Date.now();
  await authenticateCanonicalOrProducer(request, "", e, "proj", "agent-1");
  const stamped = (cred as CredRow & { last_used_at?: number }).last_used_at;
  assert.ok(typeof stamped === "number" && stamped >= before);
});

test("a present but wrong/expired fw_agent_* bearer 401s and does NOT fall back to HMAC", async () => {
  const token = "fw_agent_" + "b".repeat(64);
  const { agent, cred } = await setup(token);
  const e = await env({ agents: [agent], creds: [cred] });
  // Same token, but the route claims a different agentId than the credential covers.
  const request = new Request("https://fapi.drdeeks.xyz/x", { headers: { Authorization: `Bearer ${token}` } });
  await assert.rejects(
    () => authenticateCanonicalOrProducer(request, "", e, "proj", "some-other-agent"),
    (err: unknown) => err instanceof HttpError && err.status === 401,
  );
});

test("no Authorization header falls through to producer-signed HMAC unchanged (today's adapter behavior)", async () => {
  const secret = "shared-ingestion-secret";
  const e = await env({ agents: [], creds: [], ingestionSecret: secret });
  const raw = JSON.stringify({ agentId: "agent-1" });
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signature = await hmacSha256Hex(secret, `${timestamp}.${raw}`);
  const request = new Request("https://fapi.drdeeks.xyz/x", {
    method: "POST",
    headers: {
      "X-Watchtower-Timestamp": timestamp,
      "X-Watchtower-Signature": `sha256=${signature}`,
      "X-Watchtower-Producer": "legacy-producer-01",
    },
  });
  const producerId = await authenticateCanonicalOrProducer(request, raw, e, "proj", "agent-1");
  assert.equal(producerId, "legacy-producer-01");
});

test("no Authorization header and an invalid HMAC signature still rejects (no accidental open door)", async () => {
  const e = await env({ agents: [], creds: [], ingestionSecret: "shared-ingestion-secret" });
  const raw = JSON.stringify({ agentId: "agent-1" });
  const request = new Request("https://fapi.drdeeks.xyz/x", {
    method: "POST",
    headers: { "X-Watchtower-Timestamp": Math.floor(Date.now() / 1000).toString(), "X-Watchtower-Signature": "sha256=" + "0".repeat(64) },
  });
  await assert.rejects(
    () => authenticateCanonicalOrProducer(request, raw, e, "proj", "agent-1"),
    (err: unknown) => err instanceof HttpError && err.status === 401,
  );
});

test("authenticateProducer alone still accepts a validly HMAC-signed legacy request (regression guard)", async () => {
  const secret = "another-secret";
  const e = { WATCHTOWER_INGESTION_SECRET: secret, ENVIRONMENT: undefined } as any;
  const raw = "{}";
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signature = await hmacSha256Hex(secret, `${timestamp}.${raw}`);
  const request = new Request("https://fapi.drdeeks.xyz/x", {
    headers: { "X-Watchtower-Timestamp": timestamp, "X-Watchtower-Signature": `sha256=${signature}`, "X-Watchtower-Producer": "adapter-01" },
  });
  assert.equal(await authenticateProducer(request, raw, e), "adapter-01");
});
