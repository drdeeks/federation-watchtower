-- Rollback for 0010_organizations_widen_status.sql.
-- Reverts federation_organizations.status CHECK from
-- ('draft','submitted','approved','rejected','suspended') back to
-- ('draft','submitted','approved','rejected').
--
-- Same detach/rebuild/reattach pattern as 0010 itself — D1's FK enforcement
-- requires every child to be disconnected before the parent can be dropped.
-- Any rows with status='suspended' are converted to 'submitted' (the most
-- neutral valid state) before the rebuild.

PRAGMA defer_foreign_keys = true;

-- 0. Convert any 'suspended' rows to 'submitted' so they survive the narrowed CHECK.
UPDATE federation_organizations SET status = 'submitted' WHERE status = 'suspended';

-- 1. Detach children so nothing references federation_organizations rows.
CREATE TABLE _mig0010r_agent_org AS
    SELECT id, organization_id FROM federation_agents WHERE organization_id IS NOT NULL;
UPDATE federation_agents SET organization_id = NULL WHERE organization_id IS NOT NULL;

CREATE TABLE _mig0010r_social_proofs AS SELECT * FROM federation_organization_social_proofs;
CREATE TABLE _mig0010r_questions AS SELECT * FROM federation_organization_questions;
DELETE FROM federation_organization_social_proofs;
DELETE FROM federation_organization_questions;

-- 2. Rebuild federation_organizations with the original CHECK constraint.
CREATE TABLE federation_organizations_new (
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

INSERT INTO federation_organizations_new
    (id, owner_id, name, contact_email, official_url, status, created_at, updated_at)
    SELECT id, owner_id, name, contact_email, official_url, status, created_at, updated_at
    FROM federation_organizations;

DROP TABLE federation_organizations;
ALTER TABLE federation_organizations_new RENAME TO federation_organizations;

-- 3. Reattach children to the rebuilt table (organization ids are unchanged).
INSERT INTO federation_organization_social_proofs SELECT * FROM _mig0010r_social_proofs;
INSERT INTO federation_organization_questions SELECT * FROM _mig0010r_questions;
UPDATE federation_agents
    SET organization_id = (SELECT organization_id FROM _mig0010r_agent_org WHERE _mig0010r_agent_org.id = federation_agents.id)
    WHERE id IN (SELECT id FROM _mig0010r_agent_org);

DROP TABLE _mig0010r_agent_org;
DROP TABLE _mig0010r_social_proofs;
DROP TABLE _mig0010r_questions;
