# Kanban Cleanup Reference

## DB Schema (tasks table)

Key columns for cleanup operations:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | Task ID (t_hex format) |
| `status` | TEXT | running, ready, todo, blocked, done, cancelled |
| `assignee` | TEXT | Profile name (e.g. mnemosyne-ingestion) |
| `worker_pid` | INTEGER | PID of the dispatched worker process |
| `claim_lock` | TEXT | Which profile claimed the task |
| `claim_expires` | INTEGER | Unix timestamp when claim auto-releases (~15min TTL) |
| `workspace_path` | TEXT | Working directory for this task |
| `current_run_id` | INTEGER | Links to task_runs table |
| `last_heartbeat_at` | INTEGER | Last worker heartbeat timestamp |

## Useful SQL Queries

### Find all active tasks
```sql
SELECT id, status, assignee, title, worker_pid
FROM tasks WHERE status IN ('running','ready')
ORDER BY created_at;
```

### Count by status
```sql
SELECT status, count(*) FROM tasks GROUP BY status;
```

### Find stale running tasks (no heartbeat in 30+ minutes)
```sql
SELECT id, assignee, title, worker_pid,
       (strftime('%s','now') - last_heartbeat_at) / 60 AS minutes_since_heartbeat
FROM tasks
WHERE status = 'running'
  AND last_heartbeat_at IS NOT NULL
  AND (strftime('%s','now') - last_heartbeat_at) > 1800;
```

### Kill all active tasks
```sql
UPDATE tasks SET status='cancelled', completed_at=strftime('%s','now')
WHERE status IN ('running','ready');
```

### Kill tasks for a specific project
```sql
-- Match on assignee prefix (e.g. all mnemosyne tasks)
UPDATE tasks SET status='cancelled', completed_at=strftime('%s','now')
WHERE status IN ('running','ready') AND assignee LIKE 'mnemosyne%';
```

### Reclaim a single stuck task
```sql
UPDATE tasks SET status='ready', worker_pid=NULL, claim_lock=NULL, claim_expires=NULL
WHERE id='t_XXXX' AND status='running';
```

## Multi-Gateway Profile Discovery

Each gateway process has its own HERMES_HOME:

```bash
for pid in $(pgrep -f "hermes.*gateway"); do
    home=$(cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep HERMES_HOME | cut -d= -f2)
    echo "PID $pid -> $home"
done
```

- Different HERMES_HOME = different profile gateways (normal)
- Same HERMES_HOME = duplicate process (kill the older PID)

## Stale Worker Patterns

After a system update or crash, worker PIDs die but DB records stay `running`:
- Worker PIDs are process-local — they don't survive updates/reboots
- The DB doesn't auto-detect dead PIDs (no watchdog)
- Fix: run the "Kill all active tasks" SQL above
- Prevention: `claim_expires` TTL (~15min) auto-releases abandoned claims, but only if the dispatcher runs cleanup
