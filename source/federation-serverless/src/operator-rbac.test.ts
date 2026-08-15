import assert from "node:assert/strict";
import test from "node:test";
import { issueOperatorCredential, revokeOperatorCredentials, authenticateOperator, authenticateOperatorOrAdmin } from "./operator-rbac.ts";

// Minimal in-memory D1 fake scoped to exactly the statements operator-rbac.ts
// issues against federation_operator_credentials -- not a general SQL engine,
// mirroring this repo's existing convention of testing real logic against a
// narrow fake rather than a full database (see tests/character-kit.test.ts's
// fake-daemon pattern in the adapter repo for the same idea).
interface Row { id: string; organization_id: string; credential_hash: string; scopes: string; issued_at: number; revoked_at: number | null; }

function fakeDb() {
  const rows: Row[] = [];
  return {
    rows,
    prepare(sql: string) {
      return {
        bind(...args: unknown[]) {
          return {
            async run() {
              if (sql.startsWith("INSERT INTO federation_operator_credentials")) {
                const [id, organization_id, credential_hash, scopes, issued_at] = args as [string, string, string, string, number];
                rows.push({ id, organization_id, credential_hash, scopes, issued_at, revoked_at: null });
                return { meta: { changes: 1 } };
              }
              if (sql.startsWith("UPDATE federation_operator_credentials SET revoked_at")) {
                const [revokedAt, organizationId] = args as [number, string];
                let changes = 0;
                for (const row of rows) if (row.organization_id === organizationId && row.revoked_at === null) { row.revoked_at = revokedAt; changes++; }
                return { meta: { changes } };
              }
              throw new Error(`fakeDb: unhandled run() for: ${sql}`);
            },
            async first<T>() {
              if (sql.startsWith("SELECT id, organization_id, scopes, issued_at FROM federation_operator_credentials")) {
                const [organizationId, credentialHash] = args as [string, string];
                const row = rows.find(r => r.organization_id === organizationId && r.credential_hash === credentialHash && r.revoked_at === null);
                return (row ? { id: row.id, organization_id: row.organization_id, scopes: row.scopes, issued_at: row.issued_at } : null) as T | null;
              }
              throw new Error(`fakeDb: unhandled first() for: ${sql}`);
            },
          };
        },
      };
    },
  };
}

function env(adminToken?: string) { return { DB: fakeDb(), WATCHTOWER_ADMIN_TOKEN: adminToken } as any; }
function bearerRequest(token?: string): Request {
  return new Request("https://fapi.drdeeks.xyz/api/v1/organizations/acme/webhook", {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
}

test("issueOperatorCredential returns a bearer token and stores only its hash", async () => {
  const e = env();
  const credential = await issueOperatorCredential(e, "acme");
  assert.match(credential.token, /^fw_operator_[0-9a-f]{64}$/);
  assert.deepEqual(credential.scopes, ["operator:read", "operator:write"]);
  assert.equal(e.DB.rows.length, 1);
  assert.equal(e.DB.rows[0].organization_id, "acme");
  assert.notEqual(e.DB.rows[0].credential_hash, credential.token);
});

test("authenticateOperator accepts a valid credential scoped to its own org and rejects everything else", async () => {
  const e = env();
  const credential = await issueOperatorCredential(e, "acme");
  const ok = await authenticateOperator(bearerRequest(credential.token), e, "acme");
  assert.ok(ok);
  assert.equal(ok!.organization_id, "acme");

  // Wrong org -- a credential minted for "acme" must not authenticate for "beta",
  // even though the token itself is valid and unrevoked (FEAT-001's hard-scoping rule).
  const wrongOrg = await authenticateOperator(bearerRequest(credential.token), e, "beta");
  assert.equal(wrongOrg, null);

  // Wrong token, no token, and a non-operator-prefixed bearer all reject.
  assert.equal(await authenticateOperator(bearerRequest("fw_operator_" + "0".repeat(64)), e, "acme"), null);
  assert.equal(await authenticateOperator(bearerRequest(), e, "acme"), null);
  assert.equal(await authenticateOperator(bearerRequest("fw_owner_" + "1".repeat(64)), e, "acme"), null);
});

test("revokeOperatorCredentials makes the next request 401 immediately and is scoped per-org", async () => {
  const e = env();
  const acme = await issueOperatorCredential(e, "acme");
  const beta = await issueOperatorCredential(e, "beta");

  const revokedCount = await revokeOperatorCredentials(e, "acme");
  assert.equal(revokedCount, 1);

  assert.equal(await authenticateOperator(bearerRequest(acme.token), e, "acme"), null);
  // beta's credential is untouched by acme's revocation.
  assert.ok(await authenticateOperator(bearerRequest(beta.token), e, "beta"));

  // Revoking again finds nothing left to revoke.
  assert.equal(await revokeOperatorCredentials(e, "acme"), 0);
});

test("authenticateOperatorOrAdmin accepts the platform admin token for any org", async () => {
  const e = env("super-secret-admin-token");
  const result = await authenticateOperatorOrAdmin(bearerRequest("super-secret-admin-token"), e, "any-org-at-all");
  assert.deepEqual(result, { isAdmin: true });
});

test("authenticateOperatorOrAdmin falls back to a scoped operator credential when the admin token doesn't match", async () => {
  const e = env("super-secret-admin-token");
  const credential = await issueOperatorCredential(e, "acme");
  const result = await authenticateOperatorOrAdmin(bearerRequest(credential.token), e, "acme");
  assert.deepEqual(result, { isAdmin: false });
  assert.equal(await authenticateOperatorOrAdmin(bearerRequest(credential.token), e, "beta"), null);
});

test("authenticateOperatorOrAdmin never bypasses when no admin token is configured (no dev-mode hole)", async () => {
  const e = env(undefined);
  assert.equal(await authenticateOperatorOrAdmin(bearerRequest("anything"), e, "acme"), null);
  assert.equal(await authenticateOperatorOrAdmin(bearerRequest(), e, "acme"), null);
});
