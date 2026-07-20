import { test } from "node:test";
import assert from "node:assert/strict";
import { agentStateFilter, present, presentAlertReceipt } from "./management.ts";

test("agentStateFilter maps known states and rejects unknown", () => {
  assert.deepEqual(agentStateFilter("paused"), { clause: "a.paused_at IS NOT NULL" });
  assert.deepEqual(agentStateFilter("connected"), { clause: "a.lifecycle_state = ? AND a.paused_at IS NULL", bind: "connected" });
  assert.deepEqual(agentStateFilter("revoked"), { clause: "a.lifecycle_state = ? AND a.paused_at IS NULL", bind: "revoked" });
  assert.throws(() => agentStateFilter("everything"), /not recognised/);
});

test("present flags paused agents, keeps evidence count, and coerces flags", () => {
  const row = {
    id: "proj:agent", project_id: "proj", agent_id: "agent", owner_id: "own", organization_id: null,
    display_name: "Agent", role: "build", palette_key: "build", character_type: "runner", public_projection: 1,
    heartbeat_seconds: 60, lifecycle_state: "offline", paused_at: 123, room_id: null,
    connected_at: null, last_heartbeat_at: null, disconnected_at: null, created_at: 1, event_count: 7,
  };
  const p = present(row);
  assert.equal(p.paused, true);
  assert.equal(p.pausedAt, 123);
  assert.equal(p.eventCount, 7);
  assert.equal(p.publicProjection, true);
  assert.equal(p.lifecycleState, "offline");

  const active = present({ ...row, paused_at: null, lifecycle_state: "connected", public_projection: 0 });
  assert.equal(active.paused, false);
  assert.equal(active.pausedAt, undefined);
  assert.equal(active.publicProjection, false);
});

test("presentAlertReceipt exposes a verified webhook delivery and drops nulls", () => {
  const p = presentAlertReceipt({
    delivery_id: "notify_1", project_id: "autopilot", incident_id: "inc_1", event_id: "evt_1",
    agent_id: "build-01", severity: "critical", action: "pause", statement: "chain depth exceeded",
    reason: "chain depth 6 exceeds 5", signature_valid: 1, received_at: 42,
  });
  assert.equal(p.deliveryId, "notify_1");
  assert.equal(p.projectId, "autopilot");
  assert.equal(p.signatureValid, true);
  assert.equal(p.receivedAt, 42);

  const sparse = presentAlertReceipt({
    delivery_id: "notify_2", project_id: "autopilot", incident_id: null, event_id: null,
    agent_id: null, severity: null, action: null, statement: null, reason: null, signature_valid: 0, received_at: 7,
  });
  assert.equal(sparse.agentId, undefined);
  assert.equal(sparse.statement, undefined);
  assert.equal(sparse.signatureValid, false);
});
