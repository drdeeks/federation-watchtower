import { test } from "node:test";
import assert from "node:assert/strict";
import { alertWebhookFormat, formatAlertMessage, buildAlertDelivery } from "./alert-webhook.ts";

const alert = {
  deliveryId: "notify_1", projectId: "autopilot", incidentId: "inc_1", eventId: "evt_1",
  agentId: "build-01", severity: "critical", action: "pause",
  statement: "chain depth exceeded", reason: "chain depth 6 exceeds 5",
};

test("alertWebhookFormat normalises input and defaults to json", () => {
  assert.equal(alertWebhookFormat("slack"), "slack");
  assert.equal(alertWebhookFormat("DISCORD"), "discord");
  assert.equal(alertWebhookFormat(undefined), "json");
  assert.equal(alertWebhookFormat("email"), "json");
});

test("formatAlertMessage is one readable line with severity and context", () => {
  const m = formatAlertMessage(alert);
  assert.match(m, /Watchtower alert/);
  assert.match(m, /critical/);
  assert.match(m, /autopilot/);
  assert.match(m, /agent build-01/);
  assert.match(m, /chain depth 6 exceeds 5/);
});

test("buildAlertDelivery emits the shape each destination requires", async () => {
  const slack = await buildAlertDelivery(alert, "slack", "s");
  assert.deepEqual(Object.keys(JSON.parse(slack.body)), ["text"]);
  assert.equal(slack.headers["X-Watchtower-Signature"], undefined);
  assert.equal(slack.headers["X-Watchtower-Delivery"], "notify_1");

  const discord = await buildAlertDelivery(alert, "discord", "s");
  assert.deepEqual(Object.keys(JSON.parse(discord.body)), ["content"]);

  const json = await buildAlertDelivery(alert, "json", "s");
  assert.equal(JSON.parse(json.body).deliveryId, "notify_1");
  assert.match(json.headers["X-Watchtower-Signature"], /^sha256=[0-9a-f]{64}$/);

  const unsigned = await buildAlertDelivery(alert, "json", undefined);
  assert.equal(unsigned.headers["X-Watchtower-Signature"], undefined);
});
