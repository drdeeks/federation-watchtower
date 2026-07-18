-- Release 4: owner-bound, scoped agent lifecycle. This is additive: legacy
-- projects/agents/feed tables continue to supply the current public Watchtower.

CREATE TABLE IF NOT EXISTS federation_owners (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    owner_type TEXT NOT NULL CHECK(owner_type IN ('individual', 'organization')),
    credential_hash TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'revoked')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS federation_organizations (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL,
    name TEXT NOT NULL,
    contact_email TEXT NOT NULL,
    official_url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft', 'submitted', 'approved', 'rejected')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(owner_id) REFERENCES federation_owners(id)
);

CREATE TABLE IF NOT EXISTS federation_organization_social_proofs (
    organization_id TEXT NOT NULL,
    platform TEXT NOT NULL,
    url TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (organization_id, platform, url),
    FOREIGN KEY(organization_id) REFERENCES federation_organizations(id)
);

CREATE TABLE IF NOT EXISTS federation_organization_questions (
    id TEXT PRIMARY KEY,
    organization_id TEXT NOT NULL,
    position INTEGER NOT NULL CHECK(position BETWEEN 1 AND 5),
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    submitted_by TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    UNIQUE(organization_id, position),
    FOREIGN KEY(organization_id) REFERENCES federation_organizations(id),
    FOREIGN KEY(submitted_by) REFERENCES federation_owners(id)
);

CREATE TABLE IF NOT EXISTS federation_agents (
    id TEXT PRIMARY KEY,                     -- projectId:agentId
    project_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    owner_id TEXT NOT NULL,
    organization_id TEXT,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL,
    capabilities TEXT NOT NULL,
    avatar_seed TEXT NOT NULL,
    palette_key TEXT NOT NULL,
    character_type TEXT NOT NULL,
    public_projection INTEGER NOT NULL DEFAULT 1,
    heartbeat_seconds INTEGER NOT NULL CHECK(heartbeat_seconds BETWEEN 30 AND 3600),
    lifecycle_state TEXT NOT NULL DEFAULT 'registered' CHECK(lifecycle_state IN ('registered', 'connected', 'offline', 'revoked')),
    created_at INTEGER NOT NULL,
    connected_at INTEGER,
    last_heartbeat_at INTEGER,
    disconnected_at INTEGER,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(owner_id) REFERENCES federation_owners(id),
    FOREIGN KEY(organization_id) REFERENCES federation_organizations(id),
    UNIQUE(project_id, agent_id)
);
CREATE INDEX IF NOT EXISTS idx_federation_agents_owner ON federation_agents(owner_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_federation_agents_project ON federation_agents(project_id, lifecycle_state);

CREATE TABLE IF NOT EXISTS federation_agent_credentials (
    id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    credential_hash TEXT NOT NULL UNIQUE,
    scopes TEXT NOT NULL,
    issued_at INTEGER NOT NULL,
    expires_at INTEGER,
    revoked_at INTEGER,
    last_used_at INTEGER,
    FOREIGN KEY(agent_id) REFERENCES federation_agents(id)
);
CREATE INDEX IF NOT EXISTS idx_federation_agent_credentials_active ON federation_agent_credentials(agent_id, revoked_at, expires_at);

CREATE TABLE IF NOT EXISTS federation_lifecycle_events (
    id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    idempotency_key TEXT,
    detail TEXT NOT NULL DEFAULT '{}',
    occurred_at INTEGER NOT NULL,
    FOREIGN KEY(agent_id) REFERENCES federation_agents(id),
    UNIQUE(agent_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_federation_lifecycle_agent_time ON federation_lifecycle_events(agent_id, occurred_at DESC);
