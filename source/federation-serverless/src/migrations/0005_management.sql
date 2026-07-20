-- Release 5: operator management (agents). Additive. Adds pause state and
-- canonical room membership to federation_agents so the admin operator console
-- can pause/resume/revoke. Run ONCE — ALTER TABLE ADD COLUMN is not idempotent.
-- Room lifecycle (federation_rooms) is a separate migration (0006).

ALTER TABLE federation_agents ADD COLUMN paused_at INTEGER;
ALTER TABLE federation_agents ADD COLUMN room_id TEXT;

CREATE INDEX IF NOT EXISTS idx_federation_agents_owner ON federation_agents(owner_id);
CREATE INDEX IF NOT EXISTS idx_federation_agents_room ON federation_agents(room_id);
CREATE INDEX IF NOT EXISTS idx_federation_agents_state ON federation_agents(lifecycle_state);
