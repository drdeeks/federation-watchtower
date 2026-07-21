-- Federation Serverless Database Schema
-- D1 (SQLite) - Persistent state for agents, rooms, memory

-- Projects (namespaces)
CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    track TEXT,
    color TEXT,
    emoji TEXT,
    prefix TEXT,
    created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000)
);

-- Agents (per project)
CREATE TABLE IF NOT EXISTS agents (
    id TEXT PRIMARY KEY,                    -- composite: projectId:agentId
    project_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    name TEXT NOT NULL,
    role TEXT,
    capabilities TEXT,                      -- JSON array
    status TEXT DEFAULT 'active',           -- active, idle, busy, offline
    room_id TEXT,
    avatar_url TEXT,
    metadata TEXT,                          -- JSON object
    registered_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    last_heartbeat INTEGER,
    updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);
CREATE INDEX IF NOT EXISTS idx_agents_project ON agents(project_id);
CREATE INDEX IF NOT EXISTS idx_agents_room ON agents(room_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_agents_unique ON agents(project_id, agent_id);

-- Rooms (per project, auto-overflow)
CREATE TABLE IF NOT EXISTS rooms (
    id TEXT PRIMARY KEY,                    -- composite: projectId:roomIndex
    project_id TEXT NOT NULL,
    room_index INTEGER NOT NULL,
    capacity INTEGER DEFAULT 35,
    created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_rooms_unique ON rooms(project_id, room_index);

-- Feed events (live activity stream)
CREATE TABLE IF NOT EXISTS feed_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id TEXT NOT NULL,
    event_type TEXT NOT NULL,               -- agentRegistered, agentUpdated, heartbeat, roomChanged, error
    agent_id TEXT,
    message TEXT,
    priority TEXT DEFAULT 'normal',         -- low, normal, high, critical
    metadata TEXT,                          -- JSON
    timestamp INTEGER DEFAULT (strftime('%s', 'now') * 1000)
);
CREATE INDEX IF NOT EXISTS idx_feed_project_time ON feed_events(project_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_feed_agent ON feed_events(agent_id);

-- Memory: SOUL.md (one per project)
CREATE TABLE IF NOT EXISTS soul_docs (
    project_id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

-- Memory: MEMORY.md (one per project)
CREATE TABLE IF NOT EXISTS memory_docs (
    project_id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

-- Memory: Daily notes
CREATE TABLE IF NOT EXISTS daily_notes (
    id TEXT PRIMARY KEY,                    -- projectId:date (YYYY-MM-DD)
    project_id TEXT NOT NULL,
    date TEXT NOT NULL,                     -- YYYY-MM-DD
    content TEXT NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);
CREATE INDEX IF NOT EXISTS idx_daily_project_date ON daily_notes(project_id, date DESC);

-- Memory: Entities (knowledge graph nodes)
CREATE TABLE IF NOT EXISTS entities (
    id TEXT PRIMARY KEY,                    -- projectId:entityId
    project_id TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    type TEXT,                              -- note, concept, person, task, etc.
    name TEXT,
    content TEXT,
    frontmatter TEXT,                       -- JSON
    wikilinks TEXT,                         -- JSON array
    tags TEXT,                              -- JSON array
    created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);
CREATE INDEX IF NOT EXISTS idx_entities_project ON entities(project_id);
CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(type);
CREATE INDEX IF NOT EXISTS idx_entities_tags ON entities(tags);

-- Memory: Entity backlinks (for graph traversal)
CREATE TABLE IF NOT EXISTS entity_backlinks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_entity_id TEXT NOT NULL,
    target_entity_id TEXT NOT NULL,
    link_type TEXT DEFAULT 'wikilink',
    created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    FOREIGN KEY (source_entity_id) REFERENCES entities(id),
    FOREIGN KEY (target_entity_id) REFERENCES entities(id)
);
CREATE INDEX IF NOT EXISTS idx_backlinks_source ON entity_backlinks(source_entity_id);
CREATE INDEX IF NOT EXISTS idx_backlinks_target ON entity_backlinks(target_entity_id);

-- Project configuration (tracks which DO is active for project)
CREATE TABLE IF NOT EXISTS project_state (
    project_id TEXT PRIMARY KEY,
    registry_do_id TEXT,                    -- Durable Object ID for AgentRegistry
    coordinator_do_id TEXT,                 -- Durable Object ID for FederationCoordinator
    updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000)
);

-- ============================================================
-- FEDERATION VERIFICATION SYSTEM
-- ============================================================

-- Federation applications (pending review)
CREATE TABLE IF NOT EXISTS federation_applications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    federation_id TEXT NOT NULL UNIQUE,     -- unique org identifier
    name TEXT NOT NULL,
    org_email TEXT NOT NULL,
    official_repo TEXT NOT NULL,
    social_profiles TEXT NOT NULL,          -- JSON array: [{platform, url}]
    tech_questions TEXT NOT NULL,           -- JSON array: [{question, answer}]
    status TEXT DEFAULT 'submitted',        -- submitted, approved, rejected
    submitted_at INTEGER NOT NULL,
    reviewed_at INTEGER,
    reviewed_by TEXT,
    review_notes TEXT
);
CREATE INDEX IF NOT EXISTS idx_fed_apps_status ON federation_applications(status);

-- Verified federations (approved)
CREATE TABLE IF NOT EXISTS verified_federations (
    id TEXT PRIMARY KEY,                    -- federation_id
    name TEXT NOT NULL,
    org_email TEXT NOT NULL,
    official_repo TEXT NOT NULL,
    social_profiles TEXT NOT NULL,          -- JSON array
    status TEXT DEFAULT 'verified',         -- verified, suspended, revoked
    reviewed_by TEXT NOT NULL,
    reviewed_at INTEGER NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    metadata TEXT DEFAULT '{}'              -- JSON: notes, contacts, etc.
);
CREATE INDEX IF NOT EXISTS idx_verified_feds_status ON verified_federations(status);

-- Federation speech lines: one mandatory statement per agent at registration
-- (individual owners included, not just verified organizations) plus five
-- Q&A per organization application. federation_id is an owner id or
-- organization id — intentionally not FK-bound to verified_federations,
-- since most submitters are never a verified organization.
CREATE TABLE IF NOT EXISTS federation_speech_lines (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    federation_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    statement TEXT NOT NULL UNIQUE,         -- must be globally unique
    is_unique INTEGER DEFAULT 1,            -- always 1, enforced by UNIQUE constraint
    submitted_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_fed_speech_federation ON federation_speech_lines(federation_id);
CREATE INDEX IF NOT EXISTS idx_fed_speech_project ON federation_speech_lines(project_id);
CREATE INDEX IF NOT EXISTS idx_fed_speech_time ON federation_speech_lines(submitted_at DESC);

-- ============================================================
-- MCP ORGANIZATION MANAGEMENT
-- ============================================================

-- Organizations registered for MCP access
CREATE TABLE IF NOT EXISTS mcp_organizations (
    id TEXT PRIMARY KEY,                    -- org_id (e.g., "acme-corp")
    name TEXT NOT NULL,
    contact_email TEXT,
    api_key_hash TEXT NOT NULL,             -- bcrypt hash
    scopes TEXT DEFAULT '["org:read"]',     -- JSON array
    rate_limit INTEGER DEFAULT 100,         -- req/min
    ip_allowlist TEXT DEFAULT '[]',         -- JSON array of CIDRs
    status TEXT DEFAULT 'active',           -- active, suspended, revoked
    created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    last_access_at INTEGER,
    metadata TEXT DEFAULT '{}'              -- JSON: billing, notes, etc.
);

-- Access logs (immutable audit trail)
CREATE TABLE IF NOT EXISTS mcp_access_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    org_id TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    params TEXT,                            -- JSON (sanitized, no secrets)
    project_id TEXT,
    agent_id TEXT,
    status TEXT DEFAULT 'success',          -- success, error, rate_limited, unauthorized
    error_message TEXT,
    ip_address TEXT,
    user_agent TEXT,
    request_id TEXT,                        -- UUID for tracing
    timestamp INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    FOREIGN KEY (org_id) REFERENCES mcp_organizations(id)
);
CREATE INDEX IF NOT EXISTS idx_access_logs_org ON mcp_access_logs(org_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_access_logs_time ON mcp_access_logs(timestamp DESC);

-- Token issuance history (admin audit)
CREATE TABLE IF NOT EXISTS mcp_token_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    org_id TEXT NOT NULL,
    action TEXT NOT NULL,                   -- issued, rotated, revoked
    scopes TEXT,
    issued_by TEXT,                         -- admin who issued
    timestamp INTEGER DEFAULT (strftime('%s', 'now') * 1000),
    FOREIGN KEY (org_id) REFERENCES mcp_organizations(id)
);
CREATE INDEX IF NOT EXISTS idx_token_history_org ON mcp_token_history(org_id, timestamp DESC);

-- ============================================================
-- SEED DEFAULT PROJECTS
-- ============================================================

INSERT OR IGNORE INTO projects (id, name, track, color, emoji, prefix) VALUES
    ('mnemosyne', 'Mnemosyne', 'Track 1: MemoryAgent', '#3b82f6', '🧠', 'MN'),
    ('agora', 'Agora', 'Track 3: Agent Society', '#f59e0b', '🏛️', 'AG'),
    ('aires', 'Aires', 'Track 2: AI Showrunner', '#a855f7', '🎬', 'AI'),
    ('autopilot', 'Autopilot', 'Track 4: Autopilot Agent', '#22c55e', '⚙️', 'AP'),
    ('edgewalker', 'Edgewalker', 'Track 5: EdgeAgent', '#ef4444', '⚡', 'EW');