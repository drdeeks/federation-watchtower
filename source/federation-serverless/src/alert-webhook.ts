import type { AlertDispatch } from "./project-guardrail.ts";
import { stableJson, hmacSha256Hex } from "./watchtower.ts";

// Outbound alert-webhook payload formats. "json" is the generic signed envelope a
// custom receiver (e.g. /api/v1/alert-sink) verifies; "slack" and "discord" emit
// the message shape their incoming webhooks require. Kept as a small closed set so
// more destinations (PagerDuty, Teams, email relay, ...) can be added later behind
// the same WATCHTOWER_ALERT_WEBHOOK_FORMAT switch without touching the queue loop.
export type AlertWebhookFormat = "json" | "slack" | "discord";

export function alertWebhookFormat(value: string | undefined): AlertWebhookFormat {
  const v = (value || "json").trim().toLowerCase();
  return v === "slack" || v === "discord" ? v : "json";
}

// One readable line for a chat channel. Severity leads with a colour dot so an
// operator can triage at a glance; identity and reason follow. No secrets: the
// alert payload is already redacted operational evidence.
export function formatAlertMessage(alert: AlertDispatch): string {
  const icon = alert.severity === "critical" || alert.severity === "error" ? "🔴"
    : alert.severity === "warning" ? "🟡" : "🔵";
  const head = `${icon} Watchtower alert · ${alert.severity} · ${alert.action}`;
  const who = `project ${alert.projectId}${alert.agentId ? ` · agent ${alert.agentId}` : ""}`;
  const detail = alert.statement || alert.reason || "";
  const extra = alert.reason && alert.statement && alert.reason !== alert.statement ? ` (${alert.reason})` : "";
  const incident = alert.incidentId ? ` · incident ${alert.incidentId}` : "";
  return [head, who, detail].filter(Boolean).join(" — ") + extra + incident;
}

// Build the exact body + headers to POST for a given destination. Slack/Discord
// authenticate by their secret URL and ignore our signature, so we only sign the
// generic "json" envelope (over the exact body bytes) for a custom receiver.
export async function buildAlertDelivery(
  alert: AlertDispatch, format: AlertWebhookFormat, secret: string | undefined,
): Promise<{ body: string; headers: Record<string, string> }> {
  const timestamp = Math.floor(Date.now() / 1_000).toString();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-Watchtower-Delivery": alert.deliveryId,
    "X-Watchtower-Timestamp": timestamp,
  };
  if (format === "slack") return { body: JSON.stringify({ text: formatAlertMessage(alert) }), headers };
  if (format === "discord") return { body: JSON.stringify({ content: formatAlertMessage(alert) }), headers };
  const body = stableJson(alert);
  if (secret) headers["X-Watchtower-Signature"] = `sha256=${await hmacSha256Hex(secret, `${timestamp}.${body}`)}`;
  return { body, headers };
}
