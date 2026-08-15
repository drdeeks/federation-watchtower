-- Release 12: per-organization and per-agent alert webhook destinations
-- (MOD-003 / FEAT-003). Replaces the single global WATCHTOWER_ALERT_WEBHOOK_URL
-- as the only delivery target -- that global URL remains the last-resort
-- fallback when neither scope has configured a destination, so nobody's
-- notifications silently stop.

CREATE TABLE IF NOT EXISTS webhook_destinations (
    id TEXT PRIMARY KEY,
    scope_type TEXT NOT NULL CHECK(scope_type IN ('organization', 'agent')),
    scope_id TEXT NOT NULL,                  -- organization_id, or a canonical agent id (projectId:agentId)
    url TEXT NOT NULL,
    format TEXT NOT NULL DEFAULT 'json' CHECK(format IN ('slack', 'discord', 'json')),
    secret TEXT,                              -- per-destination HMAC secret, NULL only for slack/discord (URL is the secret there)
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(scope_type, scope_id)
);
