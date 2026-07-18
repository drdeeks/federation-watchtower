-- Cooperative containment: renewable work leases and asynchronous owner alerts.

CREATE TABLE IF NOT EXISTS work_leases (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    run_id TEXT NOT NULL,
    producer_id TEXT NOT NULL,
    scopes TEXT NOT NULL DEFAULT '[]',
    status TEXT NOT NULL,                  -- active, denied, revoked, expired
    reason TEXT,
    issued_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    command_id TEXT,
    acknowledged_at INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id),
    FOREIGN KEY (command_id) REFERENCES control_commands(id)
);
CREATE INDEX IF NOT EXISTS idx_work_leases_agent ON work_leases(project_id, agent_id, status, expires_at DESC);
CREATE INDEX IF NOT EXISTS idx_work_leases_run ON work_leases(project_id, run_id, status, expires_at DESC);

CREATE TABLE IF NOT EXISTS notification_deliveries (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    incident_id TEXT NOT NULL,
    operational_event_id TEXT NOT NULL,
    channel TEXT NOT NULL,                 -- webhook for the first adapter
    status TEXT NOT NULL,                  -- queued, delivered, retrying, suppressed, failed
    payload TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    queued_at INTEGER NOT NULL,
    completed_at INTEGER,
    last_error TEXT,
    FOREIGN KEY (project_id) REFERENCES projects(id),
    FOREIGN KEY (incident_id) REFERENCES incidents(id),
    FOREIGN KEY (operational_event_id) REFERENCES operational_events(id)
);
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_status ON notification_deliveries(status, queued_at);

CREATE TABLE IF NOT EXISTS control_command_receipts (
    id TEXT PRIMARY KEY,
    command_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    outcome TEXT NOT NULL,                 -- contained, rejected, failed
    note TEXT,
    received_at INTEGER NOT NULL,
    FOREIGN KEY (command_id) REFERENCES control_commands(id),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);
CREATE INDEX IF NOT EXISTS idx_control_command_receipts_command ON control_command_receipts(command_id, received_at DESC);
