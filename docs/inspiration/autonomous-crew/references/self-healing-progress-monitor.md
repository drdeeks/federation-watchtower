# Self-Healing Loop & Progress Monitor Architecture

## Self-Healing Loop (self-healing-loop.py)

### Purpose
Runs continuous integrity checks every 30 seconds (configurable) to detect and remediate issues automatically.

### Checks Performed

1. **Enforcer Daemon Health**
   - Checks Unix socket at `~/.agent/enforcer.sock`
   - Verifies daemon responds to ping
   - Restarts if unresponsive

2. **Constitution Hash Verification**
   - Computes SHA256 of `.agent/constitution.yaml`
   - Compares against stored hash in `.agent/constitution.hash`
   - Alerts on tampering, can restore from backup

3. **Chain State Integrity**
   - Validates chain JSON structure
   - Ensures active phase has valid marker
   - Detects skipped phases (locked phase marked active)
   - Repairs broken chains by resetting to last verified state

4. **Agent Heartbeat Status**
   - Reads `.agent/heartbeat/last-seen` for each agent
   - Flags agents missing heartbeat > 60s
   - Triggers agent restart if configured

5. **Memory Pipeline Curation**
   - Checks STM size limits
   - Verifies LTM consolidation jobs running
   - Cleans up orphaned memory files

6. **Habit Violation Remediation**
   - Runs habit checks from `.agent/habits/*.yaml`
   - Auto-fixes common violations (missing docs, lint errors)
   - Escalates persistent violations to PM

### Configuration
```python
# Command line
python3 self-healing-loop.py --project /path/to/project --interval 30

# Environment variables
HEALING_INTERVAL=30          # Check interval in seconds
HEALING_AUTO_REPAIR=true     # Attempt automatic repairs
HEALING_ALERT_WEBHOOK=       # Optional webhook for alerts
```

### Output
- Logs to `.crew-<name>/logs/self-healing.log`
- Metrics in `.crew-<name>/metrics/healing-metrics.json`
- Alerts via webhook if configured

---

## Progress Monitor (progress-monitor.py)

### Purpose
Checks project functionality and progress every 30 seconds, generating a consolidated report.

### Checks Performed

1. **Chain Status**
   - Calls `chain_enforce.py status <project>`
   - Extracts progress (e.g., "2/7"), active phase
   - Works with both crew-manager and loop-enforcer chains

2. **Test Results**
   - Runs `npm test --silent` for Node.js projects
   - Runs `cargo test --quiet` for Rust projects
   - Returns passing/failing/unknown

3. **API Health**
   - Checks `/health` endpoint on project port
   - Ports: mnemosyne=41212, aires=41213, autopilot=41214, agora=41215, edgewalker=41216
   - Returns healthy/unhealthy/unknown

### Report Format (progress-report.json)
```json
{
  "timestamp": "2026-07-09T05:13:04Z",
  "projects": {
    "mnemosyne": {
      "chain": {
        "ok": true,
        "chain": "mnemosyne-blueprint",
        "progress": "2/7",
        "active": 1
      },
      "tests_passing": true,
      "api_healthy": false
    }
  }
}
```

### Configuration
```python
# Environment variables
WORKSPACE_ROOT=$HOME/qwen-cloud-2026  # Projects root directory
MONITOR_INTERVAL=30                          # Check interval (seconds)
MONITOR_PORTS={"mnemosyne": 41212, ...}     # Custom port mapping
```

### Usage
```bash
# Run once and exit
python3 progress-monitor.py --once

# Run continuously (daemon)
python3 progress-monitor.py &
```

### Integration with Self-Healing
- Self-healing uses progress-monitor data to prioritize repairs
- If tests fail, healing loop runs test diagnostics
- If API unhealthy, healing loop checks service status
- Both write to same workspace for correlation

---

## Running Both Together

### Startup Script
```bash
#!/bin/bash
# start-monitoring.sh

WORKSPACE="$HOME/qwen-cloud-2026"
PROJECTS="mnemosyne aires autopilot agora edgewalker"

# Start self-healing for each project
for p in $PROJECTS; do
    python3 ~/.hermes/skills/devops/autonomous-crew/scripts/self-healing-loop.py \
        --project "$WORKSPACE/$p" --interval 30 &
done

# Start progress monitor
python3 ~/.hermes/skills/devops/autonomous-crew/scripts/progress-monitor.py &

# Wait for all
wait
```

### Systemd Service (production)
```ini
[Unit]
Description=Autonomous Crew Self-Healing & Progress Monitor
After=network.target

[Service]
Type=simple
WorkingDirectory=$HOME/qwen-cloud-2026
ExecStart=/bin/bash -c "source $HOME/start-monitoring.sh"
Restart=always
RestartSec=10
Environment=WORKSPACE_ROOT=$HOME/qwen-cloud-2026

[Install]
WantedBy=multi-user.target
```

---

## Key Design Principles

1. **Non-Invasive**: Read-only checks by default, repairs only with `--auto-repair`
2. **Idempotent**: Safe to run multiple times, no side effects from repeated runs
3. **Observable**: All actions logged with timestamps, correlation IDs
4. **Configurable**: All intervals, thresholds, ports via environment variables
5. **Resilient**: Handles missing files, network errors, process crashes gracefully
6. **No Hardcoded Paths**: Uses `${WORKSPACE_ROOT}`, `$HOME`, environment variables

---

## Pitfalls to Avoid

❌ Don't run healing loop without `--interval` (defaults to once-and-exit)
❌ Don't assume all projects use same port or test framework
❌ Don't write logs to `/tmp` - use project `.crew-<name>/logs/`
❌ Don't hardcode 30 seconds - make configurable
✅ Use `--dry-run` flag for testing repairs
✅ Correlate healing actions with progress monitor reports
✅ Alert on repeated failures (circuit breaker pattern)