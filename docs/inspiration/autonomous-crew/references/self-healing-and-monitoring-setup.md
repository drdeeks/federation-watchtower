# Self-Healing Loop and Progress Monitor Setup

## Self-Healing Loop (`scripts/self-healing-loop.py`)

Runs integrity checks every 30 seconds (configurable). **Scope: Crew infrastructure ONLY** — not project code/tests.

### Checks Performed:
1. **Enforcer daemon health** — Socket exists and responsive
2. **Constitution hash verification** — Tamper detection (SHA256)
3. **Chain state integrity** — No gaps (active step without prior complete)
4. **Marker files** — Proper content in `.phase-*.marker`
5. **Memory pipeline curation** — Daily → weekly → long-term promotion
6. **Habit violation remediation** — Drift detection from internalized habits

### NOT Included (Project Level):
- Test failures (npm test / cargo test)
- TypeScript compilation errors
- Missing API keys
- Missing dependencies

Those are the responsibility of **crew agents themselves** via task polling and execution.

### Configuration:
```bash
# Per-project, 30-second interval
python3 scripts/self-healing-loop.py --project /path/to/project --interval 30
```

### Log Output:
Writes to `.blueprint-chain/self-healing.log` in project directory.

---

## Progress Monitor (`scripts/progress-monitor.py`)

Monitors project functionality every 30 seconds. Reports to `progress-report.json`.

### Checks:
- **Chain status** — Progress, active phase, locked phases
- **Test results** — npm test / cargo test pass/fail
- **API health** — Health endpoint checks (ports 41212-41216 per project)

### Configuration:
```bash
# Workspace-wide monitor
export WORKSPACE_ROOT=/path/to/workspace
python3 scripts/progress-monitor.py
```

### Output Format:
```
[2026-07-09T05:52:44Z] Progress Check:
  mnemosyne: 1/7 | Phase 1 | Tests: ✓ | API: ?
  aires: 1/7 | Phase 1 | Tests: ? | API: ?
  ...
```

---

## Task Dispatcher (`scripts/task-dispatcher.py`)

Assigns kanban tasks to available agents based on active chain phases.

### Flow:
1. Reads chain status for each project
2. Finds active phase (or activates first pending)
3. Matches kanban task to active phase
4. Assigns to available agent (prefers running enforcer)
5. Creates `.agent/current_task.json` in agent workspace
6. Updates kanban status: `pending` → `in_progress`
7. Updates chain step: `locked` → `active`

### Runs continuously at 30s interval.

---

## Task Poller (`scripts/task-poller.py`)

Runs on **each agent**, polls kanban for assigned tasks, executes work.

### Agent-Side Execution:
1. Polls kanban for tasks assigned to this agent ID
2. For each `in_progress` task:
   - Runs `chain_enforce.py check <project> <phase>`
   - If `can_proceed: true` → executes phase work
   - Verifies deliverables (Phase 0: files, Phase 1+: tests)
   - Runs `chain_enforce.py complete <project> <phase>`
   - Updates kanban: `in_progress` → `completed`

### Runs continuously at 5s/30s intervals depending on work availability.

---

## Startup Sequence (Full Crew)

```bash
# 1. Spawn agents with identity layer
python3 scripts/spawn-crew-agents.py /path/to/project crew-name

# 2. Start enforcer daemons (detached)
python3 scripts/start-crew-enforcers.py /path/to/project crew-name

# 3. Start self-healing (per project, background)
for p in mnemosyne aires autopilot agora edgewalker; do
  python3 scripts/self-healing-loop.py --project /path/$p --interval 30 &
done

# 4. Start progress monitor (background)
python3 scripts/progress-monitor.py &

# 5. Start task dispatcher (background)
python3 scripts/task-dispatcher.py &

# 6. Start task pollers (per agent, background)
for p in projects; do
  for agent in /path/$p/agents/*/; do
    python3 scripts/task-poller.py $(basename $agent) $agent $p &
  done
done
```

---

## Chain Enforcement Integration (`chain_enforce.py`)

Patched to find chains in crew-manager directories:

```python
def find_chain(project_dir):
    """Find blueprint chain JSON file."""
    # Priority: .crew-* directories first, then .blueprint-chain, then .chain
    search_dirs = []
    
    # First check .crew-* directories (crew-manager format)
    for d in Path(project_dir).glob(".crew-*"):
        chain_dir = d / ".blueprint-chain"
        if chain_dir.exists():
            search_dirs.append(chain_dir)
    
    # Then check standard locations
    search_dirs.extend([
        project_dir / ".blueprint-chain",
        project_dir / ".chain",
    ])
    
    for chain_dir in search_dirs:
        for f in chain_dir.glob("*-blueprint.json"):
            return f
    return None
```

---

## Model Quota & Provider Configuration

### `model.json` (Project Root)
Tracks per-model quotas and usage:
```json
{
  "version": "1.0.0",
  "models": {
    "qwen3-max-preview": {"daily_limit": 500, "current_usage": 6},
    "qwen-plus-latest": {"daily_limit": 5000, "current_usage": 9},
    "text-embedding-v3": {"daily_limit": 10000, "current_usage": 1}
  },
  "projects": {
    "mnemosyne": ["qwen-plus-latest", "qwen3-235b-thinking", "text-embedding-v3"],
    "aires": ["qwen3-max-preview", "qwen-vl-plus-latest"],
    ...
  }
}
```

### `config/providers.json` (Skill Config)
Dynamic provider/model detection:
```json
{
  "providers": {
    "dashscope": {
      "name": "DashScope (Alibaba Cloud)",
      "api_base": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
      "env_key": "DASHSCOPE_API_KEY",
      "models": {
        "text": ["qwen3-max-preview", "qwen-plus-latest", "qwen3-235b-a22b-thinking-2507"],
        "vision": ["qwen-vl-plus-latest", "qwen-vl-max-latest"],
        "embedding": ["text-embedding-v3"]
      }
    }
  }
}
```

### Role-Based Model Selection (crew-manager.py):
```python
def _select_model_for_role(self, role, available):
    mapping = {
        "lead": "reasoning",
        "creative": "creative", 
        "reasoning": "reasoning",
        "general": "general",
        "edge": "edge",
        "vision": "vision",
        "embedding": "embedding"
    }
    category = mapping.get(role, "general")
    return available.get(category, [available.get("text", ["model-not-configured"])] )[0]
```

**NEVER HARDCODE MODELS.** All model references removed from crew-manager.py.