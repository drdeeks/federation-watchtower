import assert from "node:assert/strict";
import test from "node:test";
import { FederationAgentClient, FederationOperatorClient, FederationOwnerClient, WatchtowerApiError, WatchtowerClient, hmacSha256Hex, stableJson } from "../src/index.js";

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
  const result = await client.requestLease({ projectId: "acme", agentId: "build-01", runId: "run-1", ttlSeconds: 60, scopes: ["deploy"] });
  assert.deepEqual(result, { accepted: true });
  assert.equal(requests[0].url, "https://gateway.example/api/v1/projects/acme/leases");
  assert.equal(requests[0].init.body, '{"agentId":"build-01","projectId":"acme","runId":"run-1","scopes":["deploy"],"ttlSeconds":60}');
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
    () => client.validateLease({ projectId: "acme", agentId: "build-01", leaseId: "lease-1" }),
    error => error instanceof WatchtowerApiError && error.status === 409 && error.message === "lease blocked",
  );
});

test("agent lifecycle client uses only its scoped credential", async () => {
  const requests = [];
  const client = new FederationAgentClient({ projectId: "acme", agentId: "build-01", agentToken: "fw_agent_test", fetch: async (url, init) => { requests.push({ url, init }); return new Response(JSON.stringify({ accepted: true })); } });
  await client.heartbeat({ idempotencyKey: "heartbeat-1" });
  assert.equal(requests[0].url, "https://fapi.drdeeks.xyz/api/v1/agents/build-01/heartbeat");
  assert.equal(requests[0].init.headers.Authorization, "Bearer fw_agent_test");
  assert.equal(requests[0].init.body, '{"idempotencyKey":"heartbeat-1","projectId":"acme"}');
});

test("agent lease methods bind bearer scope", async () => {
  const requests = [];
  const client = new FederationAgentClient({ gateway: "https://gateway.example", projectId: "acme", agentId: "build-01", agentToken: "fw_agent_test", fetch: async (url, init) => { requests.push({ url, init }); return new Response("{}"); } });
  await client.requestLease({ projectId: "other", agentId: "other-agent", runId: "run-1", ttlSeconds: 60, scopes: ["deploy"] });
  await client.validateLease("lease-1");
  assert.equal(requests[0].url, "https://gateway.example/api/v1/projects/acme/leases");
  assert.equal(requests[0].init.headers.Authorization, "Bearer fw_agent_test");
  assert.equal(requests[0].init.body, '{"agentId":"build-01","projectId":"acme","runId":"run-1","scopes":["deploy"],"ttlSeconds":60}');
  assert.equal(requests[1].init.body, '{"agentId":"build-01","projectId":"acme"}');
});

test("operator client uses scoped bearer for webhook configuration", async () => {
  let request;
  const client = new FederationOperatorClient({ gateway: "https://gateway.example/", organizationId: "acme", operatorToken: "fw_operator_test", fetch: async (url, init) => { request = { url, init }; return new Response("{}"); } });
  await client.setWebhook({ url: "https://hooks.example/acme", format: "json" });
  assert.equal(request.url, "https://gateway.example/api/v1/organizations/acme/webhook");
  assert.equal(request.init.headers.Authorization, "Bearer fw_operator_test");
});

test("createOwner posts the unauthenticated owner body and binds the returned token", async () => {
  const requests = [];
  const doFetch = async (url, init) => { requests.push({ url, init }); return new Response(JSON.stringify({ owner: { ownerId: "acme" }, credential: { token: "fw_owner_abc" } }), { status: 201 }); };
  const { owner, credential, client } = await FederationOwnerClient.createOwner({ gateway: "https://gateway.example/", ownerId: "acme", displayName: "Acme", ownerType: "individual", fetch: doFetch });
  assert.equal(requests[0].url, "https://gateway.example/api/v1/owners");
  assert.equal(requests[0].init.headers.Authorization, undefined);
  assert.equal(requests[0].init.body, '{"displayName":"Acme","ownerId":"acme","ownerType":"individual"}');
  assert.equal(owner.ownerId, "acme");
  assert.equal(credential.token, "fw_owner_abc");
  assert.ok(client instanceof FederationOwnerClient);
  assert.equal(client.ownerToken, "fw_owner_abc");
});

test("owner client rejects a non-owner token", () => {
  assert.throws(() => new FederationOwnerClient({ ownerToken: "fw_agent_nope" }), /fw_owner_/);
});

test("registerAgent authenticates with the owner token and returns a wired agent client", async () => {
  const requests = [];
  const owner = new FederationOwnerClient({ gateway: "https://gateway.example/", ownerToken: "fw_owner_abc", fetch: async (url, init) => { requests.push({ url, init }); return new Response(JSON.stringify({ agent: { agentId: "build-01", projectId: "acme", roomId: "room-1" }, credential: { token: "fw_agent_xyz" }, next: { connect: "/api/v1/agents/build-01/connect" } }), { status: 201 }); } });
  const manifest = {
    agentId: "build-01", displayName: "Build 01", ownerId: "acme", projectId: "acme", role: "testing",
    capabilities: ["testing", "reporting"], identity: { avatarSeed: "build-01", paletteKey: "testing", characterType: "operator" },
    publicProjection: true, heartbeat: { intervalSeconds: 30 }, statement: "Runs the test suite and reports results.",
  };
  const { agent, credential, next, client } = await owner.registerAgent(manifest);
  assert.equal(requests[0].url, "https://gateway.example/api/v1/agents");
  assert.equal(requests[0].init.headers.Authorization, "Bearer fw_owner_abc");
  assert.equal(requests[0].init.body, stableJson(manifest));
  assert.equal(agent.agentId, "build-01");
  assert.equal(credential.token, "fw_agent_xyz");
  assert.equal(next.connect, "/api/v1/agents/build-01/connect");
  assert.ok(client instanceof FederationAgentClient);
  assert.equal(client.agentToken, "fw_agent_xyz");
  assert.equal(client.projectId, "acme");
  assert.equal(client.agentId, "build-01");
});

test("registerAgent surfaces a rejected manifest as a structured error", async () => {
  const owner = new FederationOwnerClient({ ownerToken: "fw_owner_abc", fetch: async () => new Response(JSON.stringify({ error: "identity.paletteKey is not supported" }), { status: 400 }) });
  await assert.rejects(
    () => owner.registerAgent({ agentId: "x", projectId: "p", capabilities: [], identity: { avatarSeed: "x", paletteKey: "neon", characterType: "operator" }, publicProjection: true, heartbeat: { intervalSeconds: 30 }, displayName: "X", ownerId: "acme", role: "testing" }),
    error => error instanceof WatchtowerApiError && error.status === 400 && error.message === "identity.paletteKey is not supported",
  );
});
