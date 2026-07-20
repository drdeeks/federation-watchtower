# Status Reporting & Kanban Query

Concrete recipes for reconciling crew/kanban status into one consistent view.

## 1. The kanban `tasks` schema quirk

The kanban DB (`~/.hermes/kanban.db`) `tasks` table has **NO `project` column**.
Project is encoded in the task `id` prefix:

```
mnemosyne-phase-00
autopilot-phase-03-task-02
aires-phase-02-validation
```

Columns of interest: `id, title, body, assignee, status, priority,
created_at, started_at, completed_at, workspace_path, tenant, ...`

Valid `status` values seen: `completed`, `active`, `in_progress`, `locked`,
`pending`, `blocked`, `queued`.

## 2. Correct status query (by project prefix)

```python
import sqlite3, os
db = os.path.expanduser('~/.hermes/kanban.db')
c = sqlite3.connect(db)
projects = ["mnemosyne","autopilot","aires","agora","edgewalker"]
for p in projects:
    rows = c.execute(
        "SELECT status, COUNT(*) FROM tasks WHERE id LIKE ? GROUP BY status",
        (p + "-%",)
    ).fetchall()
    d = dict(rows)
    done   = d.get('completed',0) + d.get('done',0)
    active = d.get('active',0) + d.get('in_progress',0)
    locked = d.get('locked',0) + d.get('blocked',0)
    pending= d.get('pending',0) + d.get('queued',0)
    total  = sum(d.values())
    print(f"  {p:12} total={total:3} done={done:3} active={active:2} locked={locked:3} pending={pending:2}")
```

> Do NOT `SELECT ... WHERE project=?` — that column does not exist and the
> query fails with `no such column: project`.

## 3. Reconcile with chain JSON (canonical phase)

```python
import json, glob
base = "$HOME/qwen-cloud-2026"
for p in projects:
    f = glob.glob(f"{base}/{p}/.crew-{p}-crew/.blueprint-chain/*-blueprint.json")
    d = json.load(open(f[0]))
    steps = d.get("steps", d.get("chain", []))
    states = [s.get("state") for s in steps]
    complete = sum(1 for s in states if s == "complete")
    bar = " ".join({"complete":"C","active":"A","locked":"L"}.get(s,"?") for s in states)
    print(f"  {p:12} {complete}/{len(states)} complete  [{bar}]")
```

Chain `active` = the unlocked phase. Kanban `active` subtasks belong to that
phase. They must agree; if they don't, the chain is authoritative for *phase
progression* and the kanban `active` on an earlier phase is a stale sync
artifact.

## 4. Verify a claimed UI/tool is live (before asserting)

```bash
curl -s -m 5 -o /dev/null -w '%{http_code}' http://localhost:41207/health   # gateway
curl -s -m 5 -o /dev/null -w '%{http_code}' http://localhost:8081/index.html # TV UI
curl -s -m 5 -o /dev/null -w '%{http_code}' http://localhost:41208/mcp       # MCP (needs session, see tv-sitcom-mcp pitfalls)
ps -eo pid,etimes,cmd | grep -E 'task-dispatcher|task-poller' | grep -v grep  # crew processes
```

Never tell the user a dashboard is "accessible" without a 200 from the port.

## 5. User rule (verbatim intent)

> "what you printed earlier to what you printed now makes no sense"

Report ONE reconciled table. If chain and kanban disagree, flag which is
authoritative — never print two contradictory numbers for the same project as
if both were true.
