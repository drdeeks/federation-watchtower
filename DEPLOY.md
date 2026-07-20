# Federation Watchtower - Deploy Guide

## Quick Deploy (5 minutes)

### Step 1: Merge to Main (if using git)

```bash
cd /home/drdeek/projects/federation

# Check what changed
git status

# Commit your changes
git add .
git commit -m "Ready for deployment"

# Push to main
git checkout main
git merge -
git push origin main
```

---

### Step 2: Deploy to Cloudflare

```bash
cd /home/drdeek/projects/federation/source/federation-serverless

# Deploy
npm run deploy
```

**Wait for:** `Deployment complete` (10-30 seconds)

---

### Step 3: Apply Migrations (First Deploy Only)

⚠️ **Migrations are NOT auto-applied.** Run these in order:

```bash
cd /home/drdeek/projects/federation/source/federation-serverless

# Apply all 6 migrations (adds tables, no destructive changes)
npm run migrate:watchtower      # 0001: Core enforcement (agents, rooms, feed)
npm run migrate:control-loop    # 0002: Watchdog, audit, sessions
npm run migrate:access-gateway  # 0003: Owner credentials, org applications
npm run migrate:lifecycle       # 0004: Canonical lifecycle events
npm run migrate:management      # 0005: Admin management tables
npm run migrate:alert-sink      # 0006: Alert webhook receipts

# Or run all at once:
for m in src/migrations/*.sql; do wrangler d1 execute federation-db --remote --file="$m"; done
```

---

### Step 4: Set Secrets (First Deploy Only)

```bash
cd /home/drdeek/projects/federation/source/federation-serverless

# Required secrets (you'll be prompted to enter values)
wrangler secret put WATCHTOWER_INGESTION_SECRET
wrangler secret put WATCHTOWER_ADMIN_TOKEN

# Optional secrets
wrangler secret put WATCHTOWER_ALERT_WEBHOOK_URL
wrangler secret put WATCHTOWER_ALERT_WEBHOOK_SECRET
wrangler secret put WATCHTOWER_ALERT_WEBHOOK_FORMAT  # slack, discord, or json
```

---

### Step 5: Verify Deploy

```bash
# Health check
curl https://fapi.drdeeks.xyz/health

# Should return: {"status":"healthy","timestamp":...}

# Run E2E test
cd /home/drdeek/projects/federation
./scripts/e2e-agent-lifecycle.sh

# Check Watchtower
open https://watch.drdeeks.xyz
```

---

## Rollback (If Something Breaks)

### Option 1: Instant Rollback (Worker Code Only)

```bash
cd /home/drdeek/projects/federation/source/federation-serverless

# List recent deployments
wrangler deployments list

# Rollback to previous (replace ID with the one before latest)
wrangler deployments rollback <DEPLOYMENT_ID>
```

⚠️ **Note:** Rollback does NOT undo migrations. D1 schema changes are additive and backward-compatible. If you need to revert schema changes, contact Cloudflare support or restore from backup.

### Option 2: Redeploy Previous Commit

```bash
cd /home/drdeek/projects/federation

# Revert to last known good commit
git checkout <commit-hash>

# Redeploy
cd source/federation-serverless
npm run deploy
```

### Option 3: Emergency Disable

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. **Workers & Pages** → **federation-gateway**
3. **Triggers** → **Custom Domains**
4. Remove or disable `fapi.drdeeks.xyz`

---

### Migration Rollback Notes

Migrations are **additive only** (CREATE TABLE, ADD COLUMN, CREATE INDEX). No destructive operations. Safe to run multiple times. If you need to inspect migration state:

```bash
# Check which tables exist
wrangler d1 execute federation-db --remote --command "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"

# Check migration 0004 (lifecycle) applied
wrangler d1 execute federation-db --remote --command "SELECT COUNT(*) FROM federation_lifecycle_events;"

# Check migration 0006 (alert receipts) applied
wrangler d1 execute federation-db --remote --command "SELECT COUNT(*) FROM alert_webhook_receipts;"
```

---

## Pre-Deploy Checklist

```bash
cd /home/drdeek/projects/federation

# 1. Run tests (2 min)
./scripts/local-test-runner.sh

# 2. Check git status
git status

# 3. Verify wrangler config
cd source/federation-serverless
wrangler deploy --dry-run

# 4. Verify migrations are ready
ls src/migrations/*.sql  # Should show 0001-0006
```

---

## Post-Deploy Checklist

```bash
# 1. Health check
curl https://fapi.drdeeks.xyz/health

# 2. Verify migrations applied
cd source/federation-serverless
wrangler d1 execute federation-db --remote --command "SELECT COUNT(*) as tables FROM sqlite_master WHERE type='table';"
# Should show 15+ tables

# 3. Test agent lifecycle
cd /home/drdeek/projects/federation
./scripts/e2e-agent-lifecycle.sh

# 4. Check public Watchtower
open https://watch.drdeeks.xyz

# 5. Check admin console (full management capabilities)
open https://federation.drdeeks.xyz/manage.html
# → Manage agents (pause/resume/revoke)
# → Manage rooms (create/delete empty)
# → Manage organizations (approve/reject/suspend)
# → View alert receipts
# → Export evidence
```

---

## Common Issues

### Deploy Fails

```bash
# Check authentication
wrangler whoami

# Login if needed
wrangler login

# Retry deploy
npm run deploy
```

### Worker Returns 503

```bash
# Missing secrets - set them
wrangler secret put WATCHTOWER_INGESTION_SECRET
wrangler secret put WATCHTOWER_ADMIN_TOKEN
```

### Tests Fail After Deploy

```bash
# Run API path validation
./scripts/validate-api-paths.sh --verbose

# Check which endpoint fails
# Fix code, redeploy
npm run deploy
```

---

## Environment Variables

Set these in Cloudflare Dashboard OR via `wrangler secret`:

| Variable | Required | Command |
|----------|----------|---------|
| `WATCHTOWER_INGESTION_SECRET` | ✅ | `wrangler secret put WATCHTOWER_INGESTION_SECRET` |
| `WATCHTOWER_ADMIN_TOKEN` | ✅ | `wrangler secret put WATCHTOWER_ADMIN_TOKEN` |
| `WATCHTOWER_ALERT_WEBHOOK_URL` | Optional | `wrangler secret put WATCHTOWER_ALERT_WEBHOOK_URL` |
| `WATCHTOWER_ALERT_WEBHOOK_SECRET` | Optional | `wrangler secret put WATCHTOWER_ALERT_WEBHOOK_SECRET` |
| `WATCHTOWER_ALERT_WEBHOOK_FORMAT` | Optional | `wrangler secret put WATCHTOWER_ALERT_WEBHOOK_FORMAT` (slack/discord/json) |

---

## Admin Capabilities (Post-Deploy)

After deploy, access `https://federation.drdeeks.xyz/manage.html` with admin token to:

| Capability | How To Use |
|------------|------------|
| **Create rooms** | Click "+ Add room" → Enter roomId, projectId, capacity |
| **Delete rooms** | Click "Delete" on empty rooms only (blocked if agents present) |
| **Review organizations** | Click "Review" on submitted applications |
| **Approve organizations** | Review 5 Q&A + social proofs → Click "Approve" → Adds to verified_federations |
| **Reject/Suspend orgs** | Click "Reject" or "Suspend" with optional notes |
| **Manage agents** | Search/filter → Pause/Resume/Revoke any agent |
| **View alerts** | Scroll to alert webhook section (shows all delivered alerts) |
| **Export evidence** | Click "Export evidence" → 30-day R2 retention |

---

## Summary

```bash
# DEPLOY
cd source/federation-serverless && npm run deploy

# MIGRATE (first deploy only, in order)
npm run migrate:watchtower
npm run migrate:control-loop
npm run migrate:access-gateway
npm run migrate:lifecycle
npm run migrate:management
npm run migrate:alert-sink

# VERIFY
curl https://fapi.drdeeks.xyz/health

# ROLLBACK (worker only, not migrations)
wrangler deployments rollback <ID>
```

That's it.
