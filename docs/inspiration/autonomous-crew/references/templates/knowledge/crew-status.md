# Crew Status & Health Dashboard
# Used by crew-status.sh and for monitoring

## Overview
Health dashboard for crew operations - aggregator for agent status, enforcer health, knowledge index, and sync state.

## Status Sources

| Source | Check | Frequency |
|--------|-------|-----------|
| Agent enforcers | Socket connectivity, heartbeat freshness | Every 30s |
| Knowledge index | Document count, last indexed, semantic status | On demand |
| Communications | Message queue depth, thread activity | On demand |
| Sync state | Last sync timestamp, sync mode | On sync |
| Git status | Uncommitted changes, branch | On demand (prod) |

## Agent Health Check

```bash
# Per agent (via enforcer RPC)
{
  "agent_id": "ui-a1b2",
  "status": "healthy",
  "enforcer": {
    "socket_connected": true,
    "last_heartbeat": "2026-07-05T14:30:15Z",
    "stale_threshold": 600,
    "workspace_hash": "a1b2c3d4"
  },
  "identity": {
    "constitution_hash": "33b67cd3f423e0d7",
    "habits_active": ["identity-enforcement", "tool-enforcement", "reflective-loop", "crew-phase-gate"],
    "last_verification": "2026-07-05T14:25:00Z"
  },
  "knowledge": {
    "documents": 42,
    "last_indexed": "2026-07-05T14:00:00Z",
    "categories": ["architecture", "ui", "api"]
  },
  "memory": {
    "daily_entries_today": 12,
    "weekly_current": "2026-W27",
    "long_term_size_kb": 245
  }
}
```

## Crew Aggregated Status

```bash
# crew-status.sh output
=== Crew Status: hackathon-2026 ===
Crew Type: development
Created: 2026-07-05T10:00:00Z
Last Synced: 2026-07-05T14:30:00Z

--- Agents (5) ---
  ui-a1b2 (ui): healthy ✅
  integration-b2c3 (integration): healthy ✅
  blockchain-c3d4 (blockchain): healthy ✅
  debugger-d4e5 (debugger): healthy ✅
  validation-e5f6 (validation): healthy ✅

--- Enforcers ---
  All 5 enforcers: running, heartbeats fresh

--- Knowledge Index ---
  Total documents: 156
  By category: architecture(42), api(28), ui(35), infra(12), process(18), debugging(15), research(6)
  Last indexed: 2026-07-05T14:00:00Z
  Semantic vectors: disabled

--- Communications ---
  Active threads: 8
  Messages today: 34
  Broadcasts today: 2
  Unread messages: 0

--- Sync ---
  Last full sync: 2026-07-05T14:30:00Z
  Sync mode: full
  Knowledge synced: 12 files
```

## Health Thresholds

| Metric | Healthy | Degraded | Critical |
|--------|---------|----------|----------|
| Enforcer heartbeat | < 60s | 60-300s | > 300s |
| Identity verification | < 5min ago | 5-30min | > 30min |
| Knowledge index age | < 1h | 1-6h | > 6h |
| Sync age | < 30min | 30min-2h | > 2h |
| Unread messages | 0 | 1-5 | > 5 |
| Thread depth | < 5 | 5-10 | > 10 |

## Alerting

- **Critical**: Any enforcer down, identity verification failed, sync failed
- **Warning**: Heartbeat > 60s, index > 1h old, unread messages > 0
- **Info**: New documents indexed, sync completed, phase gate transitioned

## Integration Points

- `crew-heartbeat.sh` - Individual agent heartbeat aggregation
- `crew-indexer.sh status` - Index health
- `crew-sync.sh` - Sync state
- `verify-crew-identity.sh` - Identity layer verification
- Enforcer registry (`.enforcer-registry.json`) - Enforcer metadata