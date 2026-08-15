-- Rollback for 0011_operator_credentials.sql. Safe to run any time: this
-- table has no inbound foreign keys (nothing else references it), so a
-- straight drop is sufficient -- no detach/rebuild sequence required.

DROP INDEX IF EXISTS idx_operator_cred_org;
DROP TABLE IF EXISTS federation_operator_credentials;
