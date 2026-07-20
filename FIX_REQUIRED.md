# FEDERATION WATCHTOWER - COMPLETE FIX REQUIREMENTS

## PROJECT ROOT
`/home/ubuntu/projects/federation/`

---

## 🔴 CRITICAL - BACKEND (source/federation-serverless/src/)

### 1. management.ts - CORRUPTED
**File:** `source/federation-serverless/src/management.ts`

**ISSUES:**
- Duplicate function definitions (agentStateFilter, present, presentAlertReceipt, presentRoom appear twice - exported and non-exported)
- `agentStateFilter()` uses wrong SQL logic (references 'a' table alias inconsistently between versions)
- `present()` function body missing/incomplete - does not return normalized agent data
- `presentAlertReceipt()` not properly exported - missing export keyword on one version
- `presentRoom()` not properly exported - missing export keyword on one version
- `AgentRow` interface uses wrong property names (should match DB snake_case columns)
- `handleManagementRequest()` function body corrupted - starts mid-function at line 81
- Missing imports for types used in handleManagementRequest

**REQUIRED FIXES:**
1. Remove ALL duplicate function definitions - keep ONLY exported versions at top of file
2. Rewrite `agentStateFilter()` with correct SQL: uses `a.lifecycle_state` and `a.paused_at` consistently
3. Rewrite `present(agent: AgentRow)` to return full normalized object with all fields
4. Rewrite `presentAlertReceipt(row: any)` to return full normalized receipt object
5. Rewrite `presentRoom(r: any)` to return full normalized room object
6. Fix `AgentRow` interface to match actual DB schema: `id`, `project_id`, `agent_id`, `owner_id`, `organization_id`, `display_name`, `role`, `palette_key`, `character_type`, `public_projection`, `heartbeat_seconds`, `lifecycle_state`, `paused_at`, `room_id`, `connected_at`, `last_heartbeat_at`, `disconnected_at`, `created_at`, `event_count`
7. Restore complete `handleManagementRequest()` function with proper parameter destructuring, imports, and all route handlers (GET /api/v1/admin/agents, POST /api/v1/admin/agents/:projectId/:agentId/pause|resume|revoke)

---

### 2. management.test.ts - INCOMPLETE TESTS
**File:** `source/federation-serverless/src/management.test.ts`

**ISSUES:**
- Only tests `agentStateFilter` and `present`
- Missing tests for `presentAlertReceipt` and `presentRoom`

**REQUIRED FIXES:**
1. Add test suite for `presentAlertReceipt` with various input rows
2. Add test suite for `presentRoom` with various input rows

---

### 3. index.ts - MISSING SSE ENDPOINT
**File:** `source/federation-serverless/src/index.ts`

**ISSUES:**
- No `/api/v1/public/stream` SSE endpoint implemented
- No import for SSE handler
- No EventSource response handling

**REQUIRED FIXES:**
1. Add `handlePublicSSE(request: Request, env: WatchtowerEnv)` function
2. Implement EventSource response with proper headers
3. Wire into main fetch handler for `GET /api/v1/public/stream`
4. Support query params: `projectId`, `roomId`
4. Emit events: `connected`, `heartbeat`, `agents_snapshot`, `agents_update`, `scene_snapshot`, `scene_update`, `feed_snapshot`, `feed_update`

---

### 4. federation-coordinator.ts - MISSING METHODS
**File:** `source/federation-serverless/src/federation-coordinator.ts`

**ISSUES:**
- Missing `getAgentsForProject(projectId: string)` method
- Missing `getProjectFeed(projectId: string)` method
- Missing `getAllRooms()` method

**REQUIRED FIXES:**
1. Implement `getAgentsForProject(projectId)` - query agents by project, return normalized
2. Implement `getProjectFeed(projectId)` - query recent feed events for project
3. Implement `getAllRooms()` - return all rooms with agent counts

---

### 5. lifecycle.ts - MISSING SSE EMITTERS
**File:** `source/federation-serverless/src/lifecycle.ts`

**ISSUES:**
- No functions to emit SSE events when agents/scenes/feeds change
- `appendLifecycle` exists but doesn't trigger SSE broadcasts

**REQUIRED FIXES:**
1. Add `emitAgentsUpdate(env, projectId, agents)` 
2. Add `emitSceneUpdate(env, projectId, roomId, scene)`
3. Add `emitFeedUpdate(env, projectId, events)`
4. Wire into existing `appendLifecycle` and agent state change functions

---

### 6. watchtower.ts - MISSING TYPES/VALIDATION
**File:** `source/federation-serverless/src/watchtower.ts`

**ISSUES:**
- File may not exist or be incomplete
- Missing validation functions: `validateAgentId`, `validateProjectId`, `ValidationError`
- Missing crypto utilities: `hmacSha256Hex`, `sha256Hex`, `stableJson`, `constantTimeEqual`

**REQUIRED FIXES:**
1. Ensure file exists with all validation and crypto exports used by index.ts and management.ts

---

### 7. MISSING CORE FILES (DO NOT EXIST)
**Files that must be created from scratch:**

| File | Purpose |
|------|---------|
| `source/federation-serverless/src/agent-registry.ts` | Durable Object for per-project agent registry |
| `source/federation-serverless/src/agent-watchdog.ts` | Durable Object for per-agent heartbeat deadlines |
| `source/federation-serverless/src/project-guardrail.ts` | Durable Object for per-project policy decisions |
| `source/federation-serverless/src/room-scene.ts` | Durable Object for room scene state |
| `source/federation-serverless/src/mcp.ts` | MCP gateway implementation |

**Each must export the class and be registered in wrangler.toml Durable Objects bindings**

---

### 8. Database Migrations
**File:** `source/federation-serverless/src/migrations/projects.sql`

**ISSUES:**
- File does not exist

**REQUIRED CONTENT:**
```sql
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  color TEXT,
  emoji TEXT,
  owner_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_projects_owner ON projects(owner_id);
```

---

### 9. wrangler.toml
**File:** `source/federation-serverless/wrangler.toml`

**ISSUES:**
- Missing Durable Object bindings for: AgentRegistry, AgentWatchdog, FederationCoordinator, ProjectGuardrail, RoomScene
- Missing D1 database binding
- Missing R2 bucket binding
- Missing Queue binding
- Missing KV namespace bindings

---

### 10. package.json
**File:** `source/federation-serverless/package.json`

**ISSUES:**
- Missing dependencies: `itty-router`, `uuid`, or similar routing
- Missing devDependencies for testing
- Missing scripts for build, deploy, test

---

## 🔴 CRITICAL - FRONTEND (source/federation-tv-widget/public/)

### 11. watch-sse.js - FILE DOES NOT EXIST
**File:** `source/federation-tv-widget/public/watch-sse.js`

**REQUIRED IMPLEMENTATION:**
```javascript
// EventSource client with:
// - Connection to /api/v1/public/stream?projectId=X&roomId=Y
// - Exponential backoff reconnection (max 30s)
// - Visibility API pause/resume
// - CustomEvent dispatch for: 
//   federation:agents:snapshot, federation:agents:update
//   federation:scene:snapshot, federation:scene:update
//   federation:feed:snapshot, federation:feed:update
//   federation:sse:connected, federation:sse:heartbeat
// - window.FederationTV.sse API for connect/disconnect/setParams
```

---

### 12. NAVIGATION STANDARDIZATION - ALL 9 HTML FILES
**Files requiring identical nav structure:**

| File | Current `aria-current` | Required Fix |
|------|----------------------|--------------|
| `index.html` | Watch | Keep on Watch |
| `join.html` | Send an agent | Keep on Send an agent |
| `integrate.html` | Integrate | Keep on Integrate |
| `organization.html` | Organization | Keep on Organization |
| `onboarding.html` | Onboarding | Keep on Onboarding |
| `operator.html` | Operator | Keep on Operator |
| `manage.html` | Manage | Keep on Manage |
| `demo.html` | Watch | Keep on Watch |
| `federation.html` | Federation | Keep on Federation |

**REQUIRED NAV STRUCTURE (exact same on every page):**
```html
<nav class="fed-nav" aria-label="Primary">
  <a href="/">Watch</a>
  <a href="/join.html">Send an agent</a>
  <a href="/integrate.html">Integrate</a>
  <a href="/organization.html">Organization</a>
  <a href="/federation.html">Federation</a>
  <a href="/operator.html">Operator</a>
  <a href="/manage.html">Manage</a>
  <a href="/onboarding.html">Onboarding</a>
</nav>
```

**PER-PAGE REQUIREMENT:** Current page link must have `aria-current="page"`

**SPECIFIC ISSUES PER FILE:**

- `index.html`: Has "All live rooms" dropdown option (remove), broken "Reduced motion"/"Feed only" toggles (remove), missing `watch-sse.js` script tag
- `join.html`: Nav missing Operator, Manage, Onboarding links
- `integrate.html`: Nav missing Federation, Operator, Manage, Onboarding links
- `organization.html`: Nav missing Integrate, Operator, Manage, Onboarding links
- `onboarding.html`: Wrong order (Federation before Organization), uses absolute URLs
- `operator.html`: Uses absolute URLs (`https://watch.drdeeks.xyz/`), wrong order
- `manage.html`: Uses absolute URLs, wrong order (Federation before Operator)
- `demo.html`: Minimal nav - missing most links
- `federation.html`: Uses absolute URLs, wrong order

---

### 13. index.html - WATCH PAGE SPECIFIC
**File:** `source/federation-tv-widget/public/index.html`

**ISSUES:**
- Room picker has `<option value="all">All live rooms</option>` - REMOVE
- Two broken toggle buttons: `#motion-toggle` (Reduced motion) and `#feed-toggle` (Feed only) - REMOVE or FIX
- Monitor elements need IDs: `camera-tally`, `camera-title`, `camera-rec`, `camera-state` - VERIFY EXIST
- CSS has `.reduced-motion`, `.feed-only-note` classes for removed features - REMOVE
- Missing `<script defer src="/watch-sse.js"></script>` in head - ADD

---

## 📋 VERIFICATION CHECKLIST

Run after all fixes:
```bash
cd /home/ubuntu/projects/federation/source/federation-serverless && npm test
# Must pass: 20+ tests including management.test.ts (4 helper functions)

cd /home/ubuntu/projects/federation/source/federation-serverless && npm run types
# Must pass TypeScript compilation

# Verify all 9 HTML files have identical nav structure
grep -A 10 'fed-nav' /home/ubuntu/projects/federation/source/federation-tv-widget/public/*.html
```

---

## 🎯 EXECUTION ORDER

1. **Fix management.ts completely** (tests must pass)
2. **Add management.test.ts tests** for presentAlertReceipt, presentRoom
3. **Create missing core files**: agent-registry.ts, agent-watchdog.ts, project-guardrail.ts, room-scene.ts, mcp.ts
4. **Fix federation-coordinator.ts** with required methods
5. **Fix lifecycle.ts** with SSE emitters
6. **Create watchtower.ts** with validation/crypto
7. **Implement SSE endpoint** in index.ts
8. **Create watch-sse.js** frontend client
9. **Create projects.sql** migration
10. **Fix wrangler.toml** bindings
11. **Standardize nav** across all 9 HTML files
12. **Clean up index.html** (remove dead UI, add SSE script)
13. **Run tests and verify**

---

## ❌ WHAT IS NOT DONE

**NONE OF THE ABOVE IS COMPLETE EXCEPT:**
- management.ts has exported function stubs (but logic is broken)
- Basic test file exists (but incomplete)

**EVERYTHING ELSE LISTED ABOVE REQUIRES IMPLEMENTATION FROM SCRATCH OR COMPLETE REWRITE**