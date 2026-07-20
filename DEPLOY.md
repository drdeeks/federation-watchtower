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

### Step 3: Set Secrets (First Deploy Only)

```bash
cd /home/drdeek/projects/federation/source/federation-serverless

# Required secrets (you'll be prompted to enter values)
wrangler secret put WATCHTOWER_INGESTION_SECRET
wrangler secret put WATCHTOWER_ADMIN_TOKEN

# Optional secrets
wrangler secret put WATCHTOWER_ALERT_WEBHOOK_URL
wrangler secret put WATCHTOWER_ALERT_WEBHOOK_SECRET
```

---

### Step 4: Verify Deploy

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

### Option 1: Instant Rollback

```bash
cd /home/drdeek/projects/federation/source/federation-serverless

# List recent deployments
wrangler deployments list

# Rollback to previous (replace ID with the one before latest)
wrangler deployments rollback <DEPLOYMENT_ID>
```

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
```

---

## Post-Deploy Checklist

```bash
# 1. Health check
curl https://fapi.drdeeks.xyz/health

# 2. Test agent lifecycle
./scripts/e2e-agent-lifecycle.sh

# 3. Check public Watchtower
open https://watch.drdeeks.xyz

# 4. Check admin console
open https://federation.drdeeks.xyz/manage.html
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

---

## Summary

```bash
# DEPLOY
cd source/federation-serverless && npm run deploy

# VERIFY
curl https://fapi.drdeeks.xyz/health

# ROLLBACK
wrangler deployments rollback <ID>
```

That's it.
