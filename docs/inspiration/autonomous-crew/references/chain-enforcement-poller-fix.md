# Chain Enforcement Poller Fix (v1.1.15)

## The Bug
`task-poller.py` only called `chain_enforce.py complete` for **Phase 0**. For Phases 1+, it marked kanban tasks `completed` but **never advanced the chain step**, so the dispatcher never unlocked subsequent phases. Everything stalled at Phase 1.

## Root Cause
```python
# OLD CODE (broken)
if phase_num == 0:
    # verify deliverables
    chain_enforce.py complete <project> <phase>
else:
    # Phase 1+ just fell through - no chain completion!
```

## The Fix (v1.1.15)
Added `verify_deliverables()` that checks actual artifacts exist for **every phase**, then calls `chain_enforce.py complete` unconditionally:

```python
# NEW CODE (fixed)
# Verify deliverables BEFORE completing the chain step.
# The checklist is the source of truth: every phase must have its
# deliverables verified before the chain advances.
if not verify_deliverables(project, project_dir, phase_num, task):
    print(f"[{agent_id}] Deliverables not satisfied; leaving task in_progress")
    return
# ... then complete chain for ALL phases
```

## Verification Logic
- **Phase 0**: File-based deliverables (check paths in task body)
- **Phase 1+**: Test-based validation (require test files / non-empty src tree)
- **All phases**: Call `chain_enforce.py complete <project> <phase>` after verification

## Impact
- All 5 projects now advance through enterprise-blueprint checklists
- mnemosyne: Phase 2 (Ingestion & Recall) active
- autopilot/aires/agora/edgewalker: Phase 3 (Integration) active
- No more "fake completion" — every locked task gated by real chain state

## Files Changed
- `$HOME/.hermes/skills/devops/autonomous-crew-integration/scripts/task-poller.py`
  - Added `verify_deliverables()` function
  - Removed Phase 0 special case
  - Chain completion now unconditional after verification