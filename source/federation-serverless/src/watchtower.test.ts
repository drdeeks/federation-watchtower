import assert from "node:assert/strict";
import test from "node:test";
import { constantTimeEqual, evaluateRunawayRules, validateOperationalEvent } from "./watchtower.ts";

const now = Date.parse("2026-07-17T16:00:00.000Z");

function event(overrides: Record<string, unknown> = {}) {
  return {
    schemaVersion: "2026-07-17",
    eventId: "evt-001",
    idempotencyKey: "run-1-attempt-1",
    projectId: "watchtower",
    agentId: "build-goblin-01",
    runId: "run-1",
    eventType: "validation.failed",
    severity: "error",
    occurredAt: "2026-07-17T16:00:00.000Z",
    statement: "The gate said no in YAML.",
    metadata: {},
    ...overrides,
  };
}

test("redacts sensitive event metadata before it reaches persistence", () => {
  const parsed = validateOperationalEvent(event({ metadata: { apiKey: "do-not-store", nested: { token: "also-no" } } }), now);
  assert.deepEqual(parsed.metadata, { apiKey: "[REDACTED]", nested: { token: "[REDACTED]" } });
});

test("rejects an event type outside the allow-list", () => {
  assert.throws(() => validateOperationalEvent(event({ eventType: "rm.everything" }), now), /not approved/);
});

test("detects the core runaway conditions deterministically", () => {
  const parsed = validateOperationalEvent(event({ eventType: "run.started", chainKey: "deploy-main", metadata: { chainDepth: 6, budgetUsd: 10 } }), now);
  const decisions = evaluateRunawayRules(parsed, { failedAttempts: 3, matchingChainStarts: 2 });
  assert.deepEqual(decisions.map(decision => decision.ruleId), ["max-chain-depth-v1", "budget-limit-v1", "duplicate-chain-v1"]);
});

test("requires approval after three validation failures", () => {
  const parsed = validateOperationalEvent(event(), now);
  const decisions = evaluateRunawayRules(parsed, { failedAttempts: 3, matchingChainStarts: 0 });
  assert.equal(decisions[0]?.action, "require_approval");
});

test("compares signatures without early return", () => {
  assert.equal(constantTimeEqual("abcdef", "abcdef"), true);
  assert.equal(constantTimeEqual("abcdef", "abcdeg"), false);
  assert.equal(constantTimeEqual("abcdef", "abc"), false);
});
