-- Release 3: controlled-tool evidence and retained R2 audit exports.

CREATE TABLE IF NOT EXISTS agent_sessions (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    run_id TEXT NOT NULL,
    lease_id TEXT,
    status TEXT NOT NULL,                 -- active, blocked, completed, failed
    control_state TEXT,
    started_at INTEGER NOT NULL,
    last_heartbeat_at INTEGER,
    ended_at INTEGER,
    updated_at INTEGER NOT NULL,
    metadata TEXT NOT NULL DEFAULT '{}',
    FOREIGN KEY (project_id) REFERENCES projects(id),
    UNIQUE (project_id, agent_id, run_id)
);
CREATE INDEX IF NOT EXISTS idx_agent_sessions_project_status
    ON agent_sessions(project_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS project_budgets (
    project_id TEXT PRIMARY KEY,
    limit_usd REAL NOT NULL,
    warning_usd REAL NOT NULL,
    updated_by TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

CREATE TABLE IF NOT EXISTS budget_ledger (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    run_id TEXT,
    operational_event_id TEXT NOT NULL UNIQUE,
    amount_usd REAL NOT NULL,
    source TEXT NOT NULL,
    recorded_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id),
    FOREIGN KEY (operational_event_id) REFERENCES operational_events(id)
);
CREATE INDEX IF NOT EXISTS idx_budget_ledger_project_time
    ON budget_ledger(project_id, recorded_at DESC);

CREATE TABLE IF NOT EXISTS controlled_tool_invocations (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    org_id TEXT,
    producer_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    lease_id TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    action TEXT NOT NULL,
    request_id TEXT NOT NULL,
    input_digest TEXT NOT NULL,
    status TEXT NOT NULL,                 -- authorized, denied
    reason TEXT,
    operational_event_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id),
    FOREIGN KEY (operational_event_id) REFERENCES operational_events(id),
    UNIQUE (project_id, request_id)
);
CREATE INDEX IF NOT EXISTS idx_controlled_tool_invocations_project_time
    ON controlled_tool_invocations(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_controlled_tool_invocations_lease
    ON controlled_tool_invocations(project_id, lease_id, created_at DESC);

CREATE TABLE IF NOT EXISTS evidence_exports (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    requested_by TEXT NOT NULL,
    r2_key TEXT NOT NULL UNIQUE,
    sha256 TEXT NOT NULL,
    status TEXT NOT NULL,                 -- ready, purged, failed
    event_count INTEGER NOT NULL,
    audit_count INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    purged_at INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id)
);
CREATE INDEX IF NOT EXISTS idx_evidence_exports_retention
    ON evidence_exports(status, expires_at);
