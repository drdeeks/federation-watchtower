-- Release 11: per-organization operator credential (MOD-001 / FEAT-001).
-- Gives an approved organization its own scoped credential instead of
-- reusing the platform-wide WATCHTOWER_ADMIN_TOKEN via operator.html's
-- ?project= convenience. Every query against this table is filtered by
-- organization_id server-side (src/operator-rbac.ts) -- a caller's
-- credential can never read/write another organization's data.

CREATE TABLE IF NOT EXISTS federation_operator_credentials (
    id TEXT PRIMARY KEY,
    organization_id TEXT NOT NULL,
    credential_hash TEXT NOT NULL UNIQUE,   -- SHA-256 hex, same pattern as federation_owners.credential_hash
    scopes TEXT NOT NULL DEFAULT '["operator:read","operator:write"]',
    issued_at INTEGER NOT NULL,
    revoked_at INTEGER,
    FOREIGN KEY(organization_id) REFERENCES federation_organizations(id)
);
CREATE INDEX IF NOT EXISTS idx_operator_cred_org ON federation_operator_credentials(organization_id);
