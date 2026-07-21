import assert from "node:assert/strict";
import test from "node:test";
import { validateLifecycleManifest } from "./lifecycle.ts";

const manifest = () => ({
  agentId: "build-01", displayName: "Build Runner", ownerId: "owner-01", projectId: "autopilot", role: "build",
  capabilities: ["build", "test"], identity: { avatarSeed: "build-01", paletteKey: "build", characterType: "runner" },
  publicProjection: true, heartbeat: { intervalSeconds: 1800 }, metadata: { source: "sdk" },
});

test("accepts a bounded owner-bound canonical lifecycle manifest", () => {
  assert.deepEqual(validateLifecycleManifest(manifest()), {
    agentId: "build-01", displayName: "Build Runner", ownerId: "owner-01", projectId: "autopilot", role: "build",
    capabilities: ["build", "test"], identity: { avatarSeed: "build-01", paletteKey: "build", characterType: "runner" },
    publicProjection: true, heartbeatSeconds: 1800, organizationId: undefined, lease: undefined, statement: undefined,
  });
});

test("accepts and bounds an optional registration statement", () => {
  const withStatement = { ...manifest(), statement: "  One line for the public speech pool.  " };
  assert.equal(validateLifecycleManifest(withStatement).statement, "One line for the public speech pool.");
  const tooLong = { ...manifest(), statement: "x".repeat(121) };
  assert.throws(() => validateLifecycleManifest(tooLong), /statement/);
});

test("rejects secret-shaped metadata and invalid liveness intervals", () => {
  const secret = manifest(); secret.metadata = { apiKey: "do-not-store" };
  assert.throws(() => validateLifecycleManifest(secret), /secret-shaped/);
  const interval = manifest(); interval.heartbeat.intervalSeconds = 3601;
  assert.throws(() => validateLifecycleManifest(interval), /intervalSeconds/);
});
