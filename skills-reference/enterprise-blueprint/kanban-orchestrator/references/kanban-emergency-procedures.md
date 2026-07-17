# Kanban Cleanup & Emergency Procedures (Session 2026-07-04)

## Stale Worker Recovery (This Session)

### Current State
```
sqlite3 ~/.hermes/kanban.db "SELECT id, status, assignee, title, worker_pid FROM tasks WHERE status IN ('running','ready');"
```

Returns 3 running tasks with PIDs 16375, 16376, 16377 — verify if processes exist:

```bash
ps aux | grep -E "16375|16376|16377" | grep -v grep
# If no output → processes dead, DB stale
```

### Emergency Stop Procedure

**Step 1: Kill worker processes**
```bash
for pid in $(sqlite3 ~/.hermes/kanban.db "SELECT worker_pid FROM tasks WHERE status='running' AND worker_pid IS NOT NULL;"); do
    kill $pid 2>/dev/null && echo "Killed $pid" || echo "PID $pid already dead"
done
```

**Step 2: Cancel in DB**
```bash
sqlite3 ~/.hermes/kanban.db "UPDATE tasks SET status='cancelled', completed_at=strftime('%s','now') WHERE status IN ('running','ready');"
```

**Step 3: Clear stale claim locks**
```bash
sqlite3 ~/.hermes/kanban.db "UPDATE tasks SET claim_lock=NULL, claim_expires=NULL WHERE status='cancelled';"
```

**Step 4: Check for stale gateway processes**
```bash
ps aux | grep "hermes.*gateway" | grep -v grep
for pid in $(pgrep -f "hermes.*gateway"); do
    echo "PID $pid: $(cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep HERMES_HOME)"
done
# Different HERMES_HOME = different profile gateways (OK)
# Same HERMES_HOME = duplicate (kill older)
```

### Profile Config Verification (Critical)

Workers on profiles created with `hermes profile create --no-skills` produce NOTHING — they run but have no config/tools.

**Verify before dispatch:**
```bash
for p in $(ls ~/.hermes/profiles/ | grep -v default); do
  echo "=== $p ==="
  [ -f ~/.hermes/profiles/$p/config.yaml ] && wc -c ~/.hermes/profiles/$p/config.yaml || echo "NO CONFIG"
  [ -d ~/.hermes/profiles/$p/skills ] && ls ~/.hermes/profiles/$p/skills/ | wc -l || echo "NO SKILLS"
done
```

**Fix all at once:**
```bash
for p in $(ls ~/.hermes/profiles/ | grep -v default); do
  [ ! -f ~/.hermes/profiles/$p/config.yaml ] && cp ~/.hermes/config.yaml ~/.hermes/profiles/$p/config.yaml
  [ ! -d ~/.hermes/profiles/$p/skills ] && [ ! -L ~/.hermes/profiles/$p/skills ] && ln -s ~/.hermes/skills ~/.hermes/profiles/$p/skills
done
```

Then reclaim and re-dispatch:
```bash
hermes kanban reclaim <task_id>
hermes kanban dispatch
```

## Hackathon-Specific Kanban Patterns

### Sequential Project Execution (Portfolio)
When running multiple hackathon tracks, queue ALL as kanban tasks but execute ONE at a time:

```
t_project1_001 (done) → t_project2_001 (ready) → t_project3_001 (ready)
```

Each task body includes:
- Queue position
- Dependencies  
- Resource limits
- Deliverable checklist

### Blueprint-Before-Dispatch (Non-Negotiable)
```
1. init_blueprint.py → scaffold
2. Fill blueprint.md with REAL content (not templates)
3. validate_blueprint.py → 0 FAIL
4. generate_checklist.py --sync → enforcement checklist
5. Update kanban task body with: blueprint/blueprint.md + blueprint/checklist.md
6. THEN dispatch
```

Workers without specific blueprints produce generic demos. Workers with rigorous blueprints produce production submissions.

## Resource-Aware Dispatch

**Before creating ANY task, check:**
```bash
df -h /      # Disk > 5G free?
free -h      # RAM > 1G available?
```

If not, tasks WILL fail with OOM or disk full. Add to task body:
```
Required: disk=2G, ram=500M
Timeout: 1800s
Kill-if: disk<1G or ram<200M
```

## Common Failure Patterns This Session

| Symptom | Root Cause | Fix |
|---------|------------|-----|
| Task "running" 30min, no files | Profile missing config/skills | Verify profile setup before dispatch |
| Dispatch spawns 0 workers | Stale claim_lock | Clear claim_lock/claim_expires |
| Worker OOM killed | No RAM check before dispatch | Add resource checks to task body |
| Disk full mid-run | No disk check | `df -h` gate in task body |
| Demo times out | No timeout in task | Add `Timeout: 1800s` to task body |