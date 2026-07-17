# Python Crew Manager for Multi-Agent Health Monitoring

## Overview
A Python-based crew manager that provides 5-minute health checks with dual rotation (models + credentials) for Hermes agents running Qwen models.

## Location
`/home/ubuntu/.hermes/hermes-agent/scripts/crew_manager.py`

## Key Features

### 1. Dual Rotation System
```python
class CrewManager:
    def __init__(self, crews_dir: Path):
        self.model_rotator = ModelRotator()      # Rotates Qwen models
        self.credential_rotator = CredentialRotator()  # Rotates API keys
```

### 2. 5-Minute Monitoring Loop
```python
def _monitoring_loop(self):
    while self.is_monitoring:
        self._perform_monitoring_check()
        time.sleep(300)  # 5 minutes
```

### 3. Agent Health Tracking
```python
@dataclass
class AgentHealth:
    # Credential-specific fields
    credential_id: Optional[str] = None
    credential_status: str = "active"
    credential_pool: Optional[List[str]] = None
    current_credential_index: int = 0
    api_key_exhausted: bool = False
    model_exhausted: bool = False
    
    @property
    def needs_credential_rotation(self) -> bool:
        return self.api_key_exhausted or self.credential_status == "exhausted"
    
    @property
    def needs_model_rotation(self) -> bool:
        return self.model_exhausted
```

### 4. Priority-Based Restart Logic
```python
def _attempt_agent_restart(self, agent_id: str, agent_health: AgentHealth):
    # Priority 1: Credential exhaustion (API key depleted)
    if agent_health.needs_credential_rotation:
        new_credential = self.credential_rotator.rotate_credential(agent_id, ...)
        if new_credential:
            agent_health.credential_id = new_credential["credential_id"]
            agent_health.api_key_exhausted = False
            return
    
    # Priority 2: Model exhaustion (token limit)
    if agent_health.needs_model_rotation:
        new_model = self.model_rotator.rotate_agent_model(...)
        if new_model:
            agent_health.model = new_model.name
            agent_health.model_exhausted = False
            return
    
    # Fallback: Standard restart
```

## Qwen-Only Model Pool (Verified)

| Crew | Models Pool | Rotation Strategy |
|------|-------------|-------------------|
| aires-crew | qwen3-max-preview, qwen3-235b-a22b-thinking-2507, qwen-plus-latest, qwen-vl-max-latest, qwen-vl-plus-latest, qwen3-30b-a3b-instruct | round_robin |
| autopilot-crew | qwen3-235b-a22b-thinking-2507, qwen3-max-preview, qwen-plus-latest, qwen3-coder-plus, qwen3-30b-a3b-instruct | round_robin |
| mnemosyne-crew | qwen3-235b-a22b-thinking-2507, qwen3-max-preview, qwen-plus-latest, qwen3-coder-plus, qwen3-32b | round_robin |

## Running

```bash
# Start monitoring (runs in foreground)
python3 /home/ubuntu/.hermes/hermes-agent/scripts/crew_manager.py

# Or as background service
nohup python3 /home/ubuntu/.hermes/hermes-agent/scripts/crew_manager.py > crew_manager.log 2>&1 &
```

## Health Report Output

```json
{
  "timestamp": 1720105200.0,
  "monitoring_active": true,
  "total_agents": 16,
  "healthy_agents": 16,
  "dead_agents": 0,
  "credit_exhausted_agents": 0,
  "health_percentage": 100.0,
  "crew_status": {
    "aires-crew": {"total_agents": 6, "healthy_agents": 6, "health_percentage": 100.0},
    "autopilot-crew": {"total_agents": 5, "healthy_agents": 5, "health_percentage": 100.0},
    "mnemosyne-crew": {"total_agents": 5, "healthy_agents": 5, "health_percentage": 100.0}
  },
  "credential_rotator_status": {
    "agents_with_credentials": 16,
    "credentials_initialized": true
  }
}
```

## Integration with Bash Multi-Agent Manager

The Python crew manager complements the bash `agent-bootstrap.sh`:
- **Bash**: Setup, config generation, profile management, skill linking
- **Python**: Runtime health monitoring, auto-restart, model/credential rotation

Use both together:
```bash
# 1. Bash: Set up agents and configs
./agent-bootstrap.sh --openclaw --yes sync
./skill-scanner.sh --openclaw --yes sync

# 2. Python: Start health monitoring
python3 crew_manager.py &
```

## Verification

```bash
# Test individual demos
cd /home/ubuntu/hermes-agent/workspaces/hackathon-2026/aires && node demo.js --quick
cd /home/ubuntu/hermes-agent/workspaces/hackathon-2026/autopilot && node demo.js

# Run tests
cd /home/ubuntu/hermes-agent/workspaces/hackathon-2026/autopilot && npm test

# Check crew manager status programmatically
python3 -c "
from pathlib import Path
import sys
sys.path.insert(0, '/home/ubuntu/.hermes/hermes-agent/scripts')
from crew_manager import CrewManager
cm = CrewManager(Path('/home/ubuntu/hermes-agent/workspaces/hackathon-2026/crews'))
import json
print(json.dumps(cm.get_monitoring_report(), indent=2))
"
```