# Federation Watchtower - Testing Guide

This guide explains how to test every aspect of Federation Watchtower, from local unit tests to end-to-end lifecycle validation and guardrail failure scenarios.

## Quick Start

```bash
# Run all local tests (TypeScript, unit, syntax, git)
./scripts/local-test-runner.sh

# Test the full agent lifecycle (success path)
./scripts/e2e-agent-lifecycle.sh

# Test guardrail enforcement (failure scenarios)
./scripts/test-guardrail-failures.sh

# Validate all API paths respond correctly
./scripts/validate-api-paths.sh --verbose
```

## Test Scripts

### 1. `local-test-runner.sh`

**Purpose:** Comprehensive local validation before deployment.

**What it tests:**
- ✅ npm dependency installation
- ✅ TypeScript compilation (`npm run types`)
- ✅ Unit tests (`npm test`) - 24/24 tests expected
- ✅ JavaScript syntax validation (tv-widget.js files)
- ✅ Git cleanliness (whitespace, untracked files)
- ✅ Database migration files exist
- ✅ Critical source files present
- ✅ HTML pages present (9 pages)
- ✅ Documentation files present
- ✅ SDK tests (8/8 tests expected)

**Expected output:**
```
========================================
Federation Watchtower - Local Test Suite
========================================

[PASS] Dependencies installed
[PASS] TypeScript compilation successful
[PASS] Unit tests passed (24 tests)
[PASS] JavaScript syntax valid: tv-widget.js
[PASS] Git diff clean
[PASS] Migration exists: 0001_watchtower_enforcement.sql
...
[PASS] SDK tests passed (8 tests)

========================================
[PASS] All Local Tests Passed
========================================
```

**Exit codes:**
- `0` - All tests passed
- `1` - One or more tests failed

---

### 2. `e2e-agent-lifecycle.sh`

**Purpose:** Demonstrate the complete canonical agent lifecycle against the live API.

**What it tests:**
1. **Owner creation** - `POST /api/v1/owners`
2. **Agent registration** - `POST /api/v1/agents` (with manifest validation)
3. **Agent connect** - `POST /api/v1/agents/{id}/connect`
4. **Heartbeat** - `POST /api/v1/agents/{id}/heartbeat` (watchdog deadline set)
5. **Event emission** - `POST /api/v1/agents/{id}/events`
6. **Agent disconnect** - `POST /api/v1/agents/{id}/disconnect`
7. **Public projection** - `GET /api/v1/public/rooms/{roomId}/scene`

**Modes:**
- **Success mode** (default): Emits normal operational events
- **Failure mode** (`--fail`): Emits 3 validation failures to trigger guardrail alerts

**Options:**
- `--fail` - Trigger guardrail failure scenarios
- `--cleanup` - Attempt to clean up test data (requires admin credentials)

**Expected output (success mode):**
```
[INFO] Starting E2E Agent Lifecycle Test
[INFO] Owner ID: e2e-test-12345
[INFO] Agent ID: e2e-agent-12345
[SUCCESS] Owner created successfully
[SUCCESS] Agent registered successfully (lifecycle: registered)
[SUCCESS] Agent connected successfully
[SUCCESS] Heartbeat sent (watchdog deadline: ...)
[SUCCESS] Action event emitted successfully
[SUCCESS] Agent disconnected successfully
[SUCCESS] E2E Agent Lifecycle Test Complete
```

**Expected output (failure mode):**
```
[WARNING] FAILURE MODE: Emitting validation failure events...
[INFO] Emitting validation failure event 1/3...
[INFO] Event accepted, incidents: 1
[INFO] Emitting validation failure event 2/3...
[INFO] Event accepted, incidents: 2
[INFO] Emitting validation failure event 3/3...
[INFO] Event accepted, incidents: 3
[WARNING] Guardrail should have triggered alert after 3 validation failures
[INFO] Attempting to request lease (should be denied)...
[INFO] Lease status: denied (expected: denied due to blocking command)
```

**Environment variables:**
- `WATCHTOWER_API_BASE` - API base URL (default: `https://fapi.drdeeks.xyz`)

---

### 3. `test-guardrail-failures.sh`

**Purpose:** Demonstrate guardrail enforcement by triggering specific failure conditions.

**What it tests:**

#### Test 1: Validation Failure Runaway
- Emits 3+ `validation.failed` events within 15 minutes
- **Expected:** Blocking command created, lease denied
- **Rule:** 3 validation failures triggers `require_approval` action

#### Test 2: Duplicate Chain Key Detection
- Emits 3 `run.started` events with the same `chainKey`
- **Expected:** Runaway rule triggers, incident created
- **Rule:** 3 chain starts with same key within 15 minutes

#### Test 3: Budget Threshold Alert
- Emits events with `creditCostUsd` metadata exceeding default $10 budget
- **Expected:** Budget threshold alert triggered
- **Rule:** Spending exceeds `budgetWarningUsd` ($8 default)

#### Test 4: Controlled Tool Authorization
- Requests tool authorization with active lease
- **Expected:** Tool authorized if lease scopes permit
- **Rule:** Lease must grant tool name or action

**Expected output:**
```
========================================
Guardrail Failure Scenario Tests
========================================

[TEST] Test 1: Validation Failure Runaway Detection
  Event 1: incidents=1
  Event 2: incidents=2
  Event 3: incidents=3
[PASS] Blocking command created (count: 1)
[PASS] Lease correctly denied due to blocking command

[TEST] Test 2: Duplicate Chain Key Detection
  Event 1: incidents=1, decisions=1
  Event 2: incidents=2, decisions=2
  Event 3: incidents=3, decisions=3

[TEST] Test 3: Budget Threshold Alert
  Event 1 (cumulative: $3): within budget
  Event 2 (cumulative: $6): within budget
  Event 3 (cumulative: $9): BUDGET ALERT TRIGGERED

[TEST] Test 4: Controlled Tool Authorization
[PASS] Tool authorization granted

========================================
Guardrail Tests Complete
========================================
```

---

### 4. `validate-api-paths.sh`

**Purpose:** Trace every API route to ensure no stalls, silent failures, or crashes.

**What it tests:**
- ✅ Health & discovery endpoints
- ✅ Public read endpoints (rooms, feed, search)
- ✅ Federation verification endpoints
- ✅ Owner lifecycle endpoints (authenticated)
- ✅ Agent lifecycle endpoints (authenticated)
- ✅ Guardrail & control loop endpoints
- ✅ Admin endpoints (expected 401/403 without token)
- ✅ MCP endpoints
- ✅ Error handling (404, 401 responses)

**Options:**
- `--verbose` - Show full response bodies

**Expected output:**
```
========================================
API Path Validation
========================================

=== HEALTH & DISCOVERY ===
[PATH] GET /health - Health check
[OK] 200 (45ms)
[PATH] GET / - API discovery
[OK] 200 (52ms)
...

=== AGENT LIFECYCLE ===
[PATH] POST /api/v1/agents/path-test-agent-2/connect - Agent connect
[OK] 200 (89ms)
[PATH] POST /api/v1/agents/path-test-agent-2/heartbeat - Agent heartbeat
[OK] 200 (67ms)
...

========================================
Path Validation Complete
========================================
Tests: 28
Passed: 28
Failed: 0

[PASS] All 28 paths validated successfully
```

**Exit codes:**
- `0` - All paths responded correctly
- `1` - One or more paths failed

---

## Agent Lifecycle State Machine

```
┌──────────┐     owner credential      ┌──────────┐
│   NEW    │ ────────────────────────> │ REGISTER │
└──────────┘   POST /api/v1/owners     └──────────┘
                                            │
                                            │ manifest validation
                                            │ POST /api/v1/agents
                                            ▼
                                       ┌────────────┐
                                       │ REGISTERED │
                                       └────────────┘
                                            │
                                            │ connect
                                            ▼
                                       ┌────────────┐
                                       │ CONNECTED  │ ──┐
                                       └────────────┘   │
                                            │           │ heartbeat
                                      heartbeat         │ (extends deadline)
                                            │           │
                                            ▼           │
                                       ┌────────────┐   │
                                       │ CONNECTED  │ <─┘
                                       └────────────┘
                                            │
                                            │ disconnect
                                            ▼
                                       ┌──────────┐
                                       │ OFFLINE  │
                                       └──────────┘
```

### Watchdog Enforcement

- **Heartbeat deadline:** Default 120 seconds (configurable 30-3600s)
- **On expiry:** `heartbeat.missed` event, agent set to `offline`, removed from public scene
- **Alert:** If guardrail rules trigger, alert webhook notified

### Guardrail Rules

| Rule | Trigger | Action | Incident Severity |
|------|---------|--------|-------------------|
| `validation.runaway` | 3+ `validation.failed` in 15min | `require_approval` | `high` |
| `chain.runaway` | 3+ `run.started` same chainKey in 15min | `pause` | `high` |
| `budget.threshold` | Spending exceeds `budgetWarningUsd` | `notify` | `medium` |
| `budget.exceeded` | Spending exceeds `budgetLimitUsd` | `quarantine` | `critical` |
| `duplicate.event` | Same `idempotencyKey` | (idempotent return) | - |

---

## Manual Testing via Onboarding UI

For interactive testing without scripts:

1. **Visit** [https://federation.drdeeks.xyz/onboarding.html](https://federation.drdeeks.xyz/onboarding.html)

2. **Create owner:**
   - Enter Owner ID: `manual-test-user`
   - Click "Create owner"
   - Copy the credential (starts with `fw_owner_`)

3. **Register agent:**
   - Scroll to "Register an agent"
   - Agent ID: `manual-test-agent`
   - Check "Show this agent on public Watchtower"
   - Click "Register agent"
   - Copy the agent credential (starts with `fw_agent_`)

4. **Run live loop:**
   - Click **Connect** → status: `connected`
   - Click **Heartbeat** → watchdog deadline shown
   - Click **Emit action now** → event accepted
   - Click **Disconnect** → status: `offline`

5. **Watch on public Watchtower:**
   - Visit [https://watch.drdeeks.xyz](https://watch.drdeeks.xyz)
   - Your agent appears in the roster
   - Click agent to see details and event history

---

## Test Data Cleanup

Test scripts create temporary owners and agents. To clean up:

```bash
# Admin cleanup (requires admin token)
curl -X DELETE "https://fapi.drdeeks.xyz/api/v1/admin/agents/{agentId}" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Or visit the operator console
# https://federation.drdeeks.xyz/manage.html
```

---

## Troubleshooting

### "Owner credential rejected"
- Ensure credential starts with `fw_owner_`
- Credential must be passed as `Authorization: Bearer fw_owner_...`
- Owner status must be `active` (not revoked)

### "Agent already registered"
- Agent IDs are unique per project
- Use a unique agent ID or delete the existing agent

### "Watchdog deadline exceeded"
- Send heartbeat before deadline (default 120s)
- Check `watchdogDeadlineAt` in heartbeat response

### "Lease denied"
- Check for blocking commands: `GET /api/v1/projects/{id}/agents/{id}/commands`
- Guardrail may have triggered due to validation failures or runaway detection

### Tests fail locally
- Run `npm install` in `source/federation-serverless`
- Ensure Node.js 18+ is installed
- Check TypeScript: `npm run types`

---

## Continuous Integration

For CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run local tests
  run: ./scripts/local-test-runner.sh

- name: Validate API paths
  run: ./scripts/validate-api-paths.sh
  env:
    WATCHTOWER_API_BASE: https://fapi.drdeeks.xyz

- name: Run E2E lifecycle
  run: ./scripts/e2e-agent-lifecycle.sh
  env:
    WATCHTOWER_API_BASE: https://fapi.drdeeks.xyz
```

---

## Evidence Artifacts

After running tests, verify:

1. **Live Watchtower:** [watch.drdeeks.xyz](https://watch.drdeeks.xyz)
   - Agent roster shows test agents
   - Event feed shows lifecycle events

2. **Admin Console:** [federation.drdeeks.xyz/manage.html](https://federation.drdeeks.xyz/manage.html)
   - All agents listed with owner/room/state
   - Incidents visible for guardrail triggers

3. **API Evidence:**
   ```bash
   # Get incidents for a project
   curl "https://fapi.drdeeks.xyz/api/v1/projects/{projectId}/incidents" \
     -H "Authorization: Bearer $ADMIN_TOKEN"
   
   # Get evidence export
   curl -X POST "https://fapi.drdeeks.xyz/api/v1/projects/{projectId}/evidence/exports" \
     -H "Authorization: Bearer $ADMIN_TOKEN" \
     -d '{"retentionDays": 30}'
   ```

---

## Next Steps

After tests pass:

1. **Record demo video** - Follow `VIDEO_RECORDING_GUIDE.md`
2. **Complete Devpost submission** - Attach to OpenAI Build Week challenge
3. **Monitor production** - Check admin console for real agent activity
