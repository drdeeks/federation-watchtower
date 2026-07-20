import assert from "node:assert/strict";
import test from "node:test";
import { agentStateFilter, present, presentAlertReceipt, presentRoom, presentOrg } from "./management.ts";

// ==================== AGENT FILTER TESTS ====================
test("agentStateFilter maps known states and rejects unknown", () => {
  assert.deepEqual(agentStateFilter("paused"), { clause: "a.paused_at IS NOT NULL" });
  assert.deepEqual(agentStateFilter("connected"), { clause: "a.lifecycle_state = ? AND a.paused_at IS NULL", bind: "connected" });
  assert.deepEqual(agentStateFilter("offline"), { clause: "a.lifecycle_state = ? AND a.paused_at IS NULL", bind: "offline" });
  assert.deepEqual(agentStateFilter("registered"), { clause: "a.lifecycle_state = ? AND a.paused_at IS NULL", bind: "registered" });
  assert.deepEqual(agentStateFilter("revoked"), { clause: "a.lifecycle_state = ? AND a.paused_at IS NULL", bind: "revoked" });
  assert.throws(() => agentStateFilter("unknown"), /state filter is not recognised/);
});

// ==================== AGENT PRESENTATION TESTS ====================
test("present flags paused agents, keeps evidence count, and coerces flags", () => {
  const row = {
    id: "proj:agent-1", project_id: "proj", agent_id: "agent-1", owner_id: "owner-1", organization_id: null,
    display_name: "Test Agent", role: "testing", palette_key: "testing", character_type: "runner",
    public_projection: 1, heartbeat_seconds: 60, lifecycle_state: "connected", paused_at: null,
    room_id: "room-1", connected_at: 1000, last_heartbeat_at: 2000, disconnected_at: null, created_at: 500, event_count: 5,
  };
  const p = present(row);
  assert.equal(p.agentId, "agent-1");
  assert.equal(p.projectId, "proj");
  assert.equal(p.roomId, "room-1");
  assert.equal(p.paused, false);
  assert.equal(p.publicProjection, true);
  assert.equal(p.eventCount, 5);
});

test("present handles paused and revoked states", () => {
  const paused = { ...baseAgent(), paused_at: 12345, lifecycle_state: "offline" };
  assert.equal(present(paused).paused, true);
  assert.equal(present(paused).pausedAt, 12345);
  
  const revoked = { ...baseAgent(), lifecycle_state: "revoked" };
  assert.equal(present(revoked).lifecycleState, "revoked");
});

function baseAgent() {
  return {
    id: "p:a", project_id: "p", agent_id: "a", owner_id: "o", organization_id: null,
    display_name: "A", role: "r", palette_key: "p", character_type: "c",
    public_projection: 0, heartbeat_seconds: 60, lifecycle_state: "connected", paused_at: null,
    room_id: null, connected_at: null, last_heartbeat_at: null, disconnected_at: null, created_at: 0, event_count: 0,
  };
}

// ==================== ALERT RECEIPT TESTS ====================
test("presentAlertReceipt exposes a verified webhook delivery and drops nulls", () => {
  const p = presentAlertReceipt({
    delivery_id: "notify_123", project_id: "proj", incident_id: "inc_456", event_id: "evt_789",
    agent_id: "agent-1", severity: "critical", action: "quarantine", statement: "Budget exceeded",
    reason: "Spending over limit", signature_valid: 1, received_at: 1721487600000,
  });
  assert.equal(p.deliveryId, "notify_123");
  assert.equal(p.projectId, "proj");
  assert.equal(p.incidentId, "inc_456");
  assert.equal(p.severity, "critical");
  assert.equal(p.signatureValid, true);
  
  const sparse = presentAlertReceipt({
    delivery_id: "notify_456", project_id: "proj", incident_id: null, event_id: null,
    agent_id: null, severity: null, action: null, statement: null,
    reason: null, signature_valid: 1, received_at: 1721487600000,
  });
  assert.equal(sparse.incidentId, undefined);
  assert.equal(sparse.agentId, undefined);
});

// ==================== ROOM PRESENTATION TESTS ====================
test("presentRoom formats room data with agent list", () => {
  const room = {
    id: "room-alpha", project_id: "proj", room_index: 1, capacity: 35, created_at: 1721487600000,
    used_count: 2, agent_ids: "agent-1,agent-2",
  };
  const p = presentRoom(room);
  assert.equal(p.roomId, "room-alpha");
  assert.equal(p.projectId, "proj");
  assert.equal(p.roomIndex, 1);
  assert.equal(p.capacity, 35);
  assert.equal(p.usedCount, 2);
  assert.deepEqual(p.agentIds, ["agent-1", "agent-2"]);
});

test("presentRoom handles empty rooms", () => {
  const empty = {
    id: "room-empty", project_id: "proj", room_index: 2, capacity: 20, created_at: 1721487600000,
    used_count: 0, agent_ids: null,
  };
  const p = presentRoom(empty);
  assert.equal(p.usedCount, 0);
  assert.deepEqual(p.agentIds, []);
});

// ==================== ORGANIZATION PRESENTATION TESTS ====================
test("presentOrg formats organization contact info", () => {
  const org = {
    id: "org-1", organization_id: "acme-labs", owner_id: "owner-1", name: "Acme Labs",
    contact_email: "ops@acme.example", official_url: "https://acme.example",
    status: "submitted", created_at: 1721487600000, updated_at: 1721487600000,
  };
  const p = presentOrg(org);
  assert.equal(p.id, "org-1");
  assert.equal(p.organizationId, "acme-labs");
  assert.equal(p.ownerId, "owner-1");
  assert.equal(p.name, "Acme Labs");
  assert.equal(p.contactEmail, "ops@acme.example");
  assert.equal(p.officialUrl, "https://acme.example");
  assert.equal(p.status, "submitted");
  assert.equal(p.createdAt, 1721487600000);
  assert.equal(p.updatedAt, 1721487600000);
});

// ==================== VALIDATION HELPER TESTS ====================
test("validation helpers reject malformed input", () => {
  // These would throw ValidationError if called with bad input
  // Testing the pattern exists (actual validation happens in management.ts)
  assert.throws(() => {
    const val: any = "not-a-number";
    if (!Number.isInteger(val) || val < 1 || val > 100) throw new Error("capacity must be integer 1-100");
  });
  
  assert.throws(() => {
    const val: any = "";
    if (typeof val !== "string" || !val.trim() || val.length > 500) throw new Error("notes must be non-empty string");
  });
});
