import assert from "node:assert/strict";
import test from "node:test";
import { hasMcpScope, isIpAllowed, parseMcpCredential, verifyMcpApiKey } from "./mcp.ts";
import { sha256Hex } from "./watchtower.ts";

test("parses only a bounded organization API credential", () => {
  assert.deepEqual(parseMcpCredential(`Bearer acme.${"a".repeat(32)}`), { orgId: "acme", apiKey: "a".repeat(32) });
  assert.equal(parseMcpCredential("Bearer short.key"), null);
  assert.equal(parseMcpCredential("Basic credentials"), null);
});

test("checks global and project MCP scopes independently", () => {
  const scopes = ["watchtower:read", "watchtower:lease", "project:acme:read", "project:acme:control"];
  assert.equal(hasMcpScope(scopes, "watchtower:read", "acme"), true);
  assert.equal(hasMcpScope(scopes, "watchtower:lease", "acme", "control"), true);
  assert.equal(hasMcpScope(scopes, "watchtower:read", "other-proj"), false);
  assert.equal(hasMcpScope(scopes, "watchtower:actions:authorize", "acme", "control"), false);
});

test("verifies sha256 credential verifiers and CIDR allowlists", async () => {
  const apiKey = "a".repeat(32);
  assert.equal(await verifyMcpApiKey(`sha256:${await sha256Hex(apiKey)}`, apiKey), true);
  assert.equal(await verifyMcpApiKey(`sha256:${await sha256Hex(apiKey)}`, "b".repeat(32)), false);
  assert.equal(isIpAllowed("203.0.113.8", ["203.0.113.0/24"]), true);
  assert.equal(isIpAllowed("198.51.100.8", ["203.0.113.0/24"]), false);
  assert.equal(isIpAllowed("2001:db8::1", ["2001:db8::1"]), true);
});
