import { test } from "node:test";
import assert from "node:assert/strict";
import { agentStateFilter, present } from "./management.ts";

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
