-- Release 6: alert webhook receipts. Additive. Records every alert the Worker
-- successfully delivered to its configured WATCHTOWER_ALERT_WEBHOOK_URL and that
-- the receiver verified by HMAC signature. This is the durable, operator-visible
-- proof that the outbound alert webhook is live end-to-end (not merely wired):
-- a guardrail rule fires -> the alert is signed and POSTed -> the receiver
-- verifies the signature and appends an immutable receipt here. delivery_id is
-- UNIQUE so queue redelivery stays idempotent (INSERT OR IGNORE). Run ONCE.

CREATE TABLE IF NOT EXISTS alert_webhook_receipts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    delivery_id TEXT NOT NULL UNIQUE,
    project_id TEXT NOT NULL,
    incident_id TEXT,
    event_id TEXT,
    agent_id TEXT,
    severity TEXT,
    action TEXT,
    statement TEXT,
    reason TEXT,
    signature_valid INTEGER NOT NULL DEFAULT 1,
    received_at INTEGER NOT NULL,
    payload TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_alert_webhook_receipts_received ON alert_webhook_receipts(received_at DESC);
