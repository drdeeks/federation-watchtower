-- Additive migration: Federation Watchtower event, policy, incident, and audit core.

CREATE TABLE IF NOT EXISTS operational_events (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    schema_version TEXT NOT NULL,
    producer_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    run_id TEXT,
    parent_run_id TEXT,
    chain_key TEXT,
    event_type TEXT NOT NULL,
    severity TEXT NOT NULL,
    statement TEXT NOT NULL,
    metadata TEXT NOT NULL DEFAULT '{}',
    occurred_at INTEGER NOT NULL,
    received_at INTEGER NOT NULL,
    payload_digest TEXT NOT NULL,
    decision TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id),
    UNIQUE (project_id, event_id),
    UNIQUE (project_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_operational_events_project_time ON operational_events(project_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_operational_events_agent_time ON operational_events(project_id, agent_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_operational_events_chain ON operational_events(project_id, chain_key, received_at DESC);

CREATE TABLE IF NOT EXISTS guardrail_policies (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    rules TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    superseded_at INTEGER,
    UNIQUE (project_id, version),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

CREATE TABLE IF NOT EXISTS incidents (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    dedupe_key TEXT NOT NULL,
    agent_id TEXT,
    run_id TEXT,
    rule_id TEXT NOT NULL,
    severity TEXT NOT NULL,
    status TEXT NOT NULL,
    title TEXT NOT NULL,
    opened_at INTEGER NOT NULL,
    acknowledged_at INTEGER,
    resolved_at INTEGER,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id)
);
CREATE INDEX IF NOT EXISTS idx_incidents_project_status ON incidents(project_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_dedupe ON incidents(project_id, dedupe_key, updated_at DESC);

CREATE TABLE IF NOT EXISTS incident_events (
    incident_id TEXT NOT NULL,
    operational_event_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (incident_id, operational_event_id),
    FOREIGN KEY (incident_id) REFERENCES incidents(id),
    FOREIGN KEY (operational_event_id) REFERENCES operational_events(id)
);

CREATE TABLE IF NOT EXISTS incident_transitions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT NOT NULL,
    from_status TEXT,
    to_status TEXT NOT NULL,
    actor TEXT NOT NULL,
    reason TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (incident_id) REFERENCES incidents(id)
);
CREATE INDEX IF NOT EXISTS idx_incident_transitions_incident ON incident_transitions(incident_id, created_at);

CREATE TABLE IF NOT EXISTS control_commands (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    incident_id TEXT,
    agent_id TEXT NOT NULL,
    action TEXT NOT NULL,
    mode TEXT NOT NULL,
    status TEXT NOT NULL,
    requested_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    acknowledged_at INTEGER,
    reason TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id),
    FOREIGN KEY (incident_id) REFERENCES incidents(id)
);
CREATE INDEX IF NOT EXISTS idx_control_commands_agent ON control_commands(project_id, agent_id, status, expires_at);

CREATE TABLE IF NOT EXISTS audit_events (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    id TEXT NOT NULL UNIQUE,
    project_id TEXT NOT NULL,
    operational_event_id TEXT NOT NULL,
    previous_hash TEXT NOT NULL,
    hash TEXT NOT NULL,
    decision TEXT NOT NULL,
    evidence_r2_key TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id),
    FOREIGN KEY (operational_event_id) REFERENCES operational_events(id)
);
CREATE INDEX IF NOT EXISTS idx_audit_events_project_sequence ON audit_events(project_id, sequence DESC);
