# Poller Chain-Advance Bug Fix (v1.1.15)

## The Bug
`task-poller.py` only called `chain_enforce.py complete` for **Phase 0**. For Phases 1–6, it marked kanban tasks `completed` but **never advanced the chain step**, so the dispatcher never unlocked subsequent phases. All 5 projects stalled at Phase 1.

## Root Cause
```python
# BEFORE (broken)
if phase_num == 0:
    verify deliverables -> complete chain step
else:
    mark task completed  # chain step never advanced!
```

## The Fix
```python
# AFTER (v1.1.15)
verify_deliverables()  # for ALL phases
complete_chain_step()  # for ALL phases
```

Added `verify_deliverables(project, project_dir, phase_num, task)` that:
- Phase 0: checks for required files from checklist
- Phase 1+: requires test files OR non-empty src tree
- Calls `chain_enforce.py complete <project> <phase>` on success

## Verification
After fix, all 5 projects advanced:
| Project | Phase 0 | Phase 1 | Phase 2 | Phase 3 | Phase 4-6 |
|---------|---------|---------|---------|---------|-----------|
| mnemosyne | ✅ | ✅ | 🔄 | 🔒 | 🔒 |
| autopilot | ✅ | ✅ | ✅ | 🔄 | 🔒 |
| aires | ✅ | ✅ | ✅ | 🔄 | 🔒 |
| agora | ✅ | ✅ | ✅ | 🔄 | 🔒 |
| edgewalker | ✅ | ✅ | ✅ | 🔄 | 🔒 |

## Lesson
**Never gate chain advancement on phase number.** The deliverable verification is the gate — if artifacts exist, the phase is complete regardless of index. The poller must call `complete` for every phase uniformly.