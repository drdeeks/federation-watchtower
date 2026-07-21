-- Release 9: federation_speech_lines.federation_id no longer references
-- verified_federations. The speech pool now grows from every agent's
-- mandatory registration statement (individual owners included), not only
-- verified organizations, so the original FK made every individual-owner
-- agent registration fail with a foreign key constraint violation. Rebuild
-- the table without the FK; SQLite requires a recreate to drop a constraint.
-- federation_id keeps its existing values (owner id or organization id) —
-- only the reference constraint is removed. Additive to existing data: all
-- rows are copied across, nothing is dropped.

CREATE TABLE federation_speech_lines_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    federation_id TEXT NOT NULL,            -- owner id or organization id (no longer FK-bound)
    agent_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    statement TEXT NOT NULL UNIQUE,         -- must be globally unique
    is_unique INTEGER DEFAULT 1,            -- always 1, enforced by UNIQUE constraint
    submitted_at INTEGER NOT NULL
);

INSERT INTO federation_speech_lines_new
    (id, federation_id, agent_id, project_id, statement, is_unique, submitted_at)
    SELECT id, federation_id, agent_id, project_id, statement, is_unique, submitted_at
    FROM federation_speech_lines;

DROP TABLE federation_speech_lines;
ALTER TABLE federation_speech_lines_new RENAME TO federation_speech_lines;

CREATE INDEX IF NOT EXISTS idx_fed_speech_federation ON federation_speech_lines(federation_id);
CREATE INDEX IF NOT EXISTS idx_fed_speech_project ON federation_speech_lines(project_id);
CREATE INDEX IF NOT EXISTS idx_fed_speech_time ON federation_speech_lines(submitted_at DESC);
