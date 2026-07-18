import assert from "node:assert/strict";
import test from "node:test";
import { FederationAgentClient, WatchtowerApiError, WatchtowerClient, hmacSha256Hex, stableJson } from "../src/index.js";

test("stableJson is deterministic and rejects non-JSON values", () => {
  assert.equal(stableJson({ z: [true, 2], a: "one" }), '{"a":"one","z":[true,2]}');
  assert.throws(() => stableJson({ missing: undefined }), /JSON-safe/);
});

test("client signs the exact JSON request body without exposing its secret", async () => {
  const requests = [];
  const client = new WatchtowerClient({
    gateway: "https://gateway.example/", ingestionSecret: "test-secret", producer: "sdk-test",
    fetch: async (url, init) => { requests.push({ url, init }); return new Response(JSON.stringify({ accepted: true }), { status: 201 }); },
  });
  const result = await client.requestLease({ projectId: "autopilot", agentId: "build-01", runId: "run-1", ttlSeconds: 60, scopes: ["deploy"] });
  assert.deepEqual(result, { accepted: true });
  assert.equal(requests[0].url, "https://gateway.example/api/v1/projects/autopilot/leases");
  assert.equal(requests[0].init.body, '{"agentId":"build-01","projectId":"autopilot","runId":"run-1","scopes":["deploy"],"ttlSeconds":60}');
  const timestamp = requests[0].init.headers.get("X-Watchtower-Timestamp");
  const expected = await hmacSha256Hex("test-secret", `${timestamp}.${requests[0].init.body}`);
  assert.equal(requests[0].init.headers.get("X-Watchtower-Signature"), `sha256=${expected}`);
  assert.equal(JSON.stringify(requests[0]), JSON.stringify(requests[0]).replace("test-secret", ""));
});

test("client turns rejected Watchtower responses into structured errors", async () => {
  const client = new WatchtowerClient({
    ingestionSecret: "test-secret", producer: "sdk-test",
    fetch: async () => new Response(JSON.stringify({ error: "lease blocked" }), { status: 409 }),
  });
  await assert.rejects(
    () => client.validateLease({ projectId: "autopilot", agentId: "build-01", leaseId: "lease-1" }),
    error => error instanceof WatchtowerApiError && error.status === 409 && error.message === "lease blocked",
  );
});

test("agent lifecycle client uses only its scoped credential", async () => {
  const requests = [];
  const client = new FederationAgentClient({ projectId: "autopilot", agentId: "build-01", agentToken: "fw_agent_test", fetch: async (url, init) => { requests.push({ url, init }); return new Response(JSON.stringify({ accepted: true })); } });
  await client.heartbeat({ idempotencyKey: "heartbeat-1" });
  assert.equal(requests[0].url, "https://fapi.drdeeks.xyz/api/v1/agents/build-01/heartbeat");
  assert.equal(requests[0].init.headers.Authorization, "Bearer fw_agent_test");
  assert.equal(requests[0].init.body, '{"idempotencyKey":"heartbeat-1","projectId":"autopilot"}');
});
