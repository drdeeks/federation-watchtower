import assert from "node:assert/strict";
import test from "node:test";
import { projectAmbientBeat, projectSceneEvent, type RoomSceneSnapshot } from "./room-scene-model.ts";

function empty(): RoomSceneSnapshot {
  return { roomId: "watchtower:room-0", sequence: 0, generatedAt: 0, agents: [], events: [] };
}

test("projects real run and failure events into bounded attributable room positions", () => {
  const scene = empty();
  projectSceneEvent(scene, { roomId: scene.roomId, agentId: "build-01", displayName: "Build Runner", role: "build", paletteKey: "build", lifecycleState: "connected", eventType: "run.started", sourceEventId: "evt-run", occurredAt: 100 });
  assert.equal(scene.agents[0].operationalAction, "working");
  assert.equal(scene.agents[0].destination.zone, "workbench");
  assert.deepEqual(scene.agents[0].presentation, { origin: "operational", label: "operational event", sourceEventId: "evt-run", sourceEventType: "run.started" });

  projectSceneEvent(scene, { roomId: scene.roomId, agentId: "build-01", displayName: "Build Runner", lifecycleState: "connected", eventType: "validation.failed", sourceEventId: "evt-failed", occurredAt: 200 });
  assert.equal(scene.agents[0].operationalAction, "alerting");
  assert.equal(scene.agents[0].destination.zone, "incident");
});

test("labels randomized ambient beats as presentation rather than operational truth", () => {
  const scene = empty();
  projectSceneEvent(scene, { roomId: scene.roomId, agentId: "observer-01", displayName: "Observer", lifecycleState: "connected", eventType: "agent.connected", occurredAt: 100 });
  const result = projectAmbientBeat(scene, 200);
  assert.ok(result);
  assert.equal(scene.agents[0].presentation.origin, "ambient");
  assert.equal(scene.agents[0].presentation.label, "ambient choreography · no operational event");
  assert.equal(scene.events[0].eventType, "presentation.ambient");
});
