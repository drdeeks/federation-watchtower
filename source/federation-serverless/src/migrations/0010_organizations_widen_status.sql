-- Release 10: federation_organizations.status gains 'suspended'.
-- The admin organization-management routes approve/reject/suspend an
-- application (src/management.ts). 'suspended' is a real post-approval
-- state — an administrator revoking a previously approved organization —
-- but the original 0004 CHECK only permitted ('draft','submitted',
-- 'approved','rejected'), so every suspend attempt threw a CHECK
-- constraint violation. (The companion code fix aligns approve to write
-- 'approved' instead of the mcp_organizations vocabulary 'active'.)
-- SQLite cannot widen a CHECK constraint in place, so recreate the table.
--
-- federation_organizations has three inbound foreign keys:
-- federation_organization_social_proofs, federation_organization_questions
-- (both NOT NULL organization_id), and federation_agents (nullable
-- organization_id). D1 runs each migration file as a single transaction
-- with foreign keys enforced, and SQLite's deferred-FK counter aborts the
-- commit if a referenced parent row is dropped while a child still points
-- at it — even with PRAGMA defer_foreign_keys and even though the final
-- data is consistent (verified against a remote D1 fork). So detach every
-- child from the organizations table BEFORE the rebuild, then reattach:
--   * federation_agents keeps its rows (it has its own inbound FK from
--     federation_agent_credentials); only its nullable organization_id is
--     parked to NULL and restored afterwards.
--   * social_proofs / questions have no further children, so their rows are
--     stashed in scratch tables, cleared, and reinserted verbatim.
-- Every column, row, and organization id is preserved; no status value in
-- use is removed. The scratch tables live only inside this transaction and
-- are dropped at the end (or rolled back with everything else on failure).

PRAGMA defer_foreign_keys = true;

-- 1. Detach children so nothing references federation_organizations rows.
CREATE TABLE _mig0010_agent_org AS
    SELECT id, organization_id FROM federation_agents WHERE organization_id IS NOT NULL;
UPDATE federation_agents SET organization_id = NULL WHERE organization_id IS NOT NULL;

CREATE TABLE _mig0010_social_proofs AS SELECT * FROM federation_organization_social_proofs;
CREATE TABLE _mig0010_questions AS SELECT * FROM federation_organization_questions;
DELETE FROM federation_organization_social_proofs;
DELETE FROM federation_organization_questions;

-- 2. Rebuild federation_organizations with the widened status CHECK.
CREATE TABLE federation_organizations_new (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL,
    name TEXT NOT NULL,
    contact_email TEXT NOT NULL,
    official_url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft', 'submitted', 'approved', 'rejected', 'suspended')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(owner_id) REFERENCES federation_owners(id)
);

INSERT INTO federation_organizations_new
    (id, owner_id, name, contact_email, official_url, status, created_at, updated_at)
    SELECT id, owner_id, name, contact_email, official_url, status, created_at, updated_at
    FROM federation_organizations;

DROP TABLE federation_organizations;
ALTER TABLE federation_organizations_new RENAME TO federation_organizations;

-- 3. Reattach children to the rebuilt table (organization ids are unchanged).
INSERT INTO federation_organization_social_proofs SELECT * FROM _mig0010_social_proofs;
INSERT INTO federation_organization_questions SELECT * FROM _mig0010_questions;
UPDATE federation_agents
    SET organization_id = (SELECT organization_id FROM _mig0010_agent_org WHERE _mig0010_agent_org.id = federation_agents.id)
    WHERE id IN (SELECT id FROM _mig0010_agent_org);

DROP TABLE _mig0010_agent_org;
DROP TABLE _mig0010_social_proofs;
DROP TABLE _mig0010_questions;
