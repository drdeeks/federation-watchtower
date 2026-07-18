import assert from "node:assert/strict";
import test from "node:test";
import { ACCESS_MONETIZATION_PROTOTYPE, ACCESS_TIER_CATALOG, inspectOrganizationApplicationDraft, isPrototypeOnly } from "./access-monetization-prototype.ts";

test("access and monetization scaffold cannot activate a production capability", () => {
  assert.equal(isPrototypeOnly(), true);
  assert.equal(ACCESS_MONETIZATION_PROTOTYPE.status, "prototype-only");
  assert.equal(ACCESS_MONETIZATION_PROTOTYPE.enabled, false);
});

test("the prototype preserves open participation and all four proposed tiers", () => {
  assert.deepEqual(ACCESS_TIER_CATALOG.map(tier => tier.id), ["guest-agent", "individual-operator", "verified-organization", "federation-partner"]);
  assert.match(ACCESS_TIER_CATALOG[0].proposedCapabilities.join(" "), /Heartbeats/);
  assert.match(ACCESS_TIER_CATALOG[2].proposedRestrictions.join(" "), /never a prerequisite for basic participation/);
});

test("the organization proposal keeps its exact five-answer review boundary", () => {
  const checks = inspectOrganizationApplicationDraft({
    federationId: "acme", organizationName: "Acme", verifiedContactEmail: "ops@example.test", officialPresenceUrl: "https://example.test",
    officialSocialProfiles: [{ platform: "GitHub", url: "https://github.com/acme" }, { platform: "Mastodon", url: "https://example.test/m" }],
    technicalAnswers: [{ question: "one", answer: "one" }, { question: "two", answer: "two" }, { question: "three", answer: "three" }, { question: "four", answer: "four" }],
    reviewStatus: "draft",
  });
  assert.deepEqual(checks.map(check => check.code), ["two-official-social-profiles-required", "exactly-five-technical-answers-required"]);
});
