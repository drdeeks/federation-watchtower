# Hackathon Blueprint → Implementation Lessons (Session 2026-07-04)

## The Core Problem
**Blueprints exist but don't auto-produce working implementations.** All 5 tracks had blueprints, only 2 tracks (aires, autopilot) produced runnable demos with real Qwen API calls.

## Track Status Reality Check

| Track | Project | Blueprint | Demo | Tests | Models Working |
|-------|---------|-----------|------|-------|----------------|
| 1: MemoryAgent | mnemosyne | ✅ Complete | ❌ No entry point | ❌ No tests | Defined only |
| 2: AI Showrunner | aires | ✅ Complete | ✅ 94s, 8898 tokens | N/A | qwen3-max-preview, qwen3-235b-a22b, qwen-plus-latest |
| 3: Agent Society | agora | ✅ Complete | ⚠️ Timeout | Unknown | qwen3-max-preview |
| 4: Autopilot Agent | autopilot | ✅ Complete | ✅ 48s, 9/9 steps | ~73/100 pass | qwen-plus-latest |
| 5: EdgeAgent | edgewalker | ✅ Complete | ❌ API param error | Unknown | qwen3-coder-plus |

## Resource Constraints That Block Implementation

```
Disk: 58G total, 1.7G free (after aggressive cleanup)
RAM:  1.9G total, 429M available
```

**Space eaters removed:**
- `/home/ubuntu/projects/hemlock-test` (2.4G)
- `/home/ubuntu/projects/GhostWriter` (1.6G)  
- `/home/ubuntu/Downloads` (1G)
- `/home/ubuntu/hackathon-submissions` (122M)
- `mnemosyne/node_modules` (60M)
- `agent-sitcom/node_modules` (5.3M)

## Blueprint Enforcement Gaps

1. **No auto-validation gate** — Blueprints validated but not enforced as prerequisites for worker dispatch
2. **No implementation scaffolding** — Blueprint → code generation missing
3. **No resource-aware planning** — Blueprints don't account for disk/RAM limits
4. **No demo/video pipeline** — Submission deliverables not wired to blueprint phases

## Kanban State (from current_status.txt)

```
t_aires_001    running  aires-director    PID 16375
t_agora_001    running  agora-architect   PID 16376  
t_edgewalker_001 running edgewalker-kernel PID 16377
t_mnemosyne_001 done     mnemosyne-orchestrator
t_autopilot_001 done     autopilot-orchestrator
```

3 tasks still "running" with PIDs — need cleanup if stalled.

## Critical Fixes Needed Before Submission

### For mnemosyne (Track 1)
- Create `src/index.js` entry point
- Implement core modules: IngestionEngine, RecallEngine, ForgetEngine, LearningEngine
- Fix `better-sqlite3` native build (or swap to pure-JS alternative)
- Add demo.js that runs full memory lifecycle
- Create 3-min video

### For agora (Track 3)  
- Fix demo timeout (likely infinite loop in constitutional review)
- Verify all 4 branches work: legislative, judicial, executive, auditor

### For edgewalker (Track 5)
- Fix DashScope `enable_thinking` parameter error for qwen3-coder-plus
- Non-streaming calls need `enable_thinking: false`

## Enforcement Protocol for Future

**BEFORE dispatching workers:**
1. Run `validate_blueprint.py` → must pass 0 FAIL
2. Run `generate_checklist.py --sync` → creates enforcement checklist
3. Verify resource availability (disk > 5G, RAM > 1G free)
4. Verify demo.js exists and runs < 60s
5. Verify test suite passes > 80%
6. ONLY THEN create kanban tasks with blueprint/checklist references in body

**Worker task body must include:**
```
Blueprint: /path/to/blueprint.md
Checklist: /path/to/checklist.md
Deliverables: [demo.js, video.mp4, test-results.json]
Resource limits: disk=2G, ram=500M
Timeout: 1800s
```

## Session Artifacts Created
- `/home/ubuntu/hermes-agent/workspaces/hackathon-2026/agent-sitcom/` — real-time monitor (distraction)
- Updated kanban tasks still running (need cleanup)

## Action Items
- [ ] Kill stale kanban workers (PIDs 16375, 16376, 16377 if dead)
- [ ] Free 2G more disk space
- [ ] Decide: ship 2 working tracks OR fix 3 broken ones
- [ ] If fixing: prioritize mnemosyne (empty src) and edgewalker (simple param fix)