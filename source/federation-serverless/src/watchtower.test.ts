import assert from "node:assert/strict";
import test from "node:test";
import {
  constantTimeEqual, evaluateRunawayRules, validateCommandAcknowledgement,
  validateLeaseRequest, validateLeaseValidationRequest, validateOperationalEvent, validateValidationGateRequest,
} from "./watchtower.ts";

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

test("creates an alert decision when a watchdog reports a missed heartbeat", () => {
  const parsed = validateOperationalEvent(event({ eventType: "heartbeat.missed", severity: "warning", metadata: {} }), now);
  const decisions = evaluateRunawayRules(parsed, { failedAttempts: 0, matchingChainStarts: 0 });
  assert.deepEqual(decisions, [{
    ruleId: "heartbeat-missed-v1", action: "alert", severity: "warning",
    reason: "agent missed its Watchtower heartbeat deadline",
  }]);
});

test("uses accumulated ledger spend for a warning and a hard credit guard", () => {
  const parsed = validateOperationalEvent(event({ eventType: "run.started", severity: "info", metadata: { creditCostUsd: 1 } }), now);
  assert.deepEqual(evaluateRunawayRules(parsed, {
    failedAttempts: 0, matchingChainStarts: 0, projectBudgetUsd: 8.5, budgetWarningUsd: 8, budgetLimitUsd: 10,
  }).map(decision => decision.ruleId), ["budget-warning-v1"]);
  assert.deepEqual(evaluateRunawayRules(parsed, {
    failedAttempts: 0, matchingChainStarts: 0, projectBudgetUsd: 10, budgetWarningUsd: 8, budgetLimitUsd: 10,
  }).map(decision => decision.ruleId), ["budget-limit-v1"]);
});

test("validates bounded cooperative lease and command acknowledgement bodies", () => {
  assert.deepEqual(validateLeaseRequest({
    projectId: "watchtower", agentId: "build-goblin-01", runId: "run-1",
    ttlSeconds: 120, scopes: ["deploy"],
  }), {
    projectId: "watchtower", agentId: "build-goblin-01", runId: "run-1",
    ttlSeconds: 120, scopes: ["deploy"],
  });
  assert.deepEqual(validateLeaseValidationRequest({ agentId: "build-goblin-01" }), { agentId: "build-goblin-01" });
  assert.deepEqual(validateCommandAcknowledgement({ commandId: "cmd-1", agentId: "build-goblin-01", outcome: "contained" }), {
    commandId: "cmd-1", agentId: "build-goblin-01", outcome: "contained", note: undefined,
  });
  assert.deepEqual(validateValidationGateRequest({
    projectId: "watchtower", agentId: "build-goblin-01", runId: "run-1", leaseId: "lease-1",
    gateId: "preflight", requestId: "gate-1", passed: true, statement: "Checks passed.", metadata: { token: "nope" },
  }), {
    projectId: "watchtower", agentId: "build-goblin-01", runId: "run-1", leaseId: "lease-1",
    gateId: "preflight", requestId: "gate-1", passed: true, statement: "Checks passed.", metadata: { token: "[REDACTED]" },
  });
  assert.throws(() => validateLeaseRequest({ projectId: "watchtower", agentId: "a", runId: "run", ttlSeconds: 5 }), /ttlSeconds/);
  assert.throws(() => validateValidationGateRequest({ projectId: "watchtower", agentId: "a", runId: "run", gateId: "gate", passed: true, statement: "okay", metadata: {} }), /requestId/);
});

test("compares signatures without early return", () => {
  assert.equal(constantTimeEqual("abcdef", "abcdef"), true);
  assert.equal(constantTimeEqual("abcdef", "abcdeg"), false);
  assert.equal(constantTimeEqual("abcdef", "abc"), false);
});
