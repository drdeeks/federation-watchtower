#!/usr/bin/env bash
# Federation Watchtower — ordered D1 migration runner.
#
# Applies every migration in source/federation-serverless/src/migrations in
# numeric order (0001 -> 0012). Rollback files (*_rollback.sql) are deliberately
# excluded — they are never part of forward migration.
#
# Usage:
#   ./scripts/migrate-all.sh            # REMOTE federation-db (matches `npm run migrate:*` convention)
#   ./scripts/migrate-all.sh --local   # LOCAL dev database instead
#
# Migrations use CREATE TABLE/INDEX IF NOT EXISTS, so additive ones are safe to
# re-run. WARNING: 0010 (organizations_widen_status) recreates a table and is
# deploy-gated per AGENTS.md — do not run --remote against production without an
# approved rollback plan and explicit go-ahead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVERLESS_DIR="$SCRIPT_DIR/../source/federation-serverless"

TARGET="remote"
if [[ "${1:-}" == "--local" ]]; then
  TARGET="local"
fi

MIGRATIONS=(
  "0001_watchtower_enforcement"
  "0002_watchtower_control_loop"
  "0003_watchtower_access_gateway"
  "0004_federation_lifecycle"
  "0005_management"
  "0006_alert_webhook_receipts"
  "0007_seed_speech_repertoire"
  "0008_audit_chain_integrity"
  "0009_speech_lines_drop_federation_fk"
  "0010_organizations_widen_status"
  "0011_operator_credentials"
  "0012_webhook_destinations"
)

cd "$SERVERLESS_DIR"

if [[ "$TARGET" == "remote" ]]; then
  echo "WARNING: applying migrations to REMOTE federation-db."
  echo "  (0010 widens federation_organizations.status — deploy-gated; confirm go-ahead + rollback plan.)"
fi

for m in "${MIGRATIONS[@]}"; do
  echo "Applying $m ($TARGET)..."
  wrangler d1 execute federation-db --"$TARGET" --file="src/migrations/$m.sql"
done

echo "All migrations applied ($TARGET)."
