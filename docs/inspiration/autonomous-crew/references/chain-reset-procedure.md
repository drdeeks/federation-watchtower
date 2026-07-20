# Chain Reset Procedure (Full Chain + Kanban Reset)

When chains get out of sync (all phases marked "complete" but checklist shows "NOT STARTED"), you need a FULL RESET — not just chain state, but kanban tasks too.

## Full Reset Procedure

```bash
# 1. Delete old chain files entirely
rm -f <project>/.blueprint-chain/*-blueprint.json
rm -f <project>/.blueprint-chain/phase-*.marker

# 2. Create new chain with proper initial state
python3 -c "
import json
from pathlib import Path
from datetime import datetime, timezone

project = '<project>'
chain_dir = Path('<workspace>') / project / '.blueprint-chain'
chain_dir.mkdir(exist_ok=True)

chain = {
    'name': f'{project}-blueprint',
    'project': str(Path('<workspace>') / project),
    'created_at': datetime.now(timezone.utc).isoformat(),
    'steps': []
}

for i in range(7):
    marker = chain_dir / f'phase-{i:02d}.marker'
    marker.touch()
    chain['steps'].append({
        'index': i,
        'path': str(marker.absolute()),
        'state': 'active' if i == 0 else 'locked',
        'validator': None,
        'created_at': datetime.now(timezone.utc).isoformat(),
        'verified_at': None,
        'completed_at': None,
        'attempts': 0
    })

with open(chain_dir / f'{project}-blueprint.json', 'w') as f:
    json.dump(chain, f, indent=2)
"

# 3. Delete old kanban tasks for this project
sqlite3 ~/.hermes/kanban.db "DELETE FROM tasks WHERE title LIKE '%<project>%'"

# 4. Create new kanban tasks (one per phase)
sqlite3 ~/.hermes/kanban.db "
INSERT INTO tasks (id, title, body, status, created_at, workspace_kind) VALUES
('<project>-phase-00', '<Project> Phase 0: Foundation', 'Create project structure...', 'pending', strftime('%s','now'), 'scratch'),
...
"

# 5. Verify
python3 chain_enforce.py status <project>
# Should show: Progress: 0/7 | Active: 1 | Locked: 6
```

## Why Full Reset Is Needed

The chain state machine (locked→active→verified→complete) can get out of sync when:
- Phases were marked "complete" without actually creating deliverables
- The checklist was regenerated but chain wasn't updated
- Manual edits were made to chain JSON or marker files

**Root cause pattern:** Chain says "complete" but checklist says "NOT STARTED". This means the chain was lying — it tracked completion without validating deliverables existed. The fix is NOT to mark checklist items done; it's to RESET the chain and start fresh.

## Checklist Is Source of Truth

The checklist.md defines what MUST exist for each phase. The chain tracks whether those things have been verified. If they diverge:
1. Trust the CHECKLIST (what needs to exist)
2. RESET the chain (what has been verified)
3. Re-verify completed phases in order

## Quick Reset (No Kanban Changes)

If only the chain is wrong but kanban tasks are correct:

```bash
rm -f <project>/.blueprint-chain/*-blueprint.json
rm -f <project>/.blueprint-chain/phase-*.marker
# Then recreate chain (code block above)
```
