-- Release 5: operator management (agents). Additive. Adds pause state and
-- canonical room membership to federation_agents so the admin operator console
-- can pause/resume/revoke. Run ONCE — ALTER TABLE ADD COLUMN is not idempotent.
-- Room lifecycle (federation_rooms) is a separate migration (0006).
--
-- NOTE: paused_at and room_id columns already exist in production (applied
-- previously). ALTER TABLE ADD COLUMN is not idempotent in SQLite, so the
-- ADD COLUMN statements below are commented out to allow safe re-runs.
-- For fresh databases, run the two ALTER TABLE statements manually first.

-- ALTER TABLE federation_agents ADD COLUMN paused_at INTEGER;
-- ALTER TABLE federation_agents ADD COLUMN room_id TEXT;

CREATE INDEX IF NOT EXISTS idx_federation_agents_owner ON federation_agents(owner_id);
CREATE INDEX IF NOT EXISTS idx_federation_agents_room ON federation_agents(room_id);
CREATE INDEX IF NOT EXISTS idx_federation_agents_state ON federation_agents(lifecycle_state);
