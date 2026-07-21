-- Release 8: audit hash-chain integrity guard. Additive, defense-in-depth.
--
-- The per-project audit_events chain is append-only: each row chains off exactly
-- one predecessor via previous_hash, and its own hash becomes the next row's
-- previous_hash. In a correct chain, (project_id, previous_hash) is therefore
-- unique — GENESIS appears once per project, every other predecessor hash once.
-- Two rows sharing a (project_id, previous_hash) means the chain FORKED, which
-- silently corrupts the immutable evidence stream.
--
-- ProjectGuardrail.ingest now serializes the read-modify-write per project DO
-- (blockConcurrencyWhile), so forks should be impossible in normal operation.
-- This unique index is the storage-layer backstop: if serialization is ever
-- bypassed (external writer, future refactor), the forked INSERT fails loudly
-- inside the ingest batch instead of corrupting the chain.
--
-- PRECHECK — apply ONLY after confirming no existing forks return rows:
--   SELECT project_id, previous_hash, COUNT(*) AS c
--   FROM audit_events GROUP BY project_id, previous_hash HAVING c > 1;
-- If that query returns rows, resolve the duplicates before creating the index
-- (index creation will otherwise fail). Run ONCE.

CREATE UNIQUE INDEX IF NOT EXISTS idx_audit_events_chain_unique
    ON audit_events (project_id, previous_hash);
