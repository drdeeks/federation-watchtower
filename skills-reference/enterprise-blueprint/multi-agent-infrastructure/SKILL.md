---
name: multi-agent-infrastructure
description: "Multi-agent infrastructure with port management, file locking, changelog tracking, and builder code integration. Use when: setting up multiple agents that need isolation, preventing file conflicts between agents, tracking agent work in projects, or integrating blockchain builder codes. Covers: port allocation, file flocking, append-only changelogs, agent registries."
version: 2.0.0
metadata:
  hermes:
    tags: [multi-agent, infrastructure, ports, locking, changelog, builder-code, agent-management, telegram-bots, autonomous-crew]
    category: devops
    complexity: advanced
---

# Multi-Agent Infrastructure

Infrastructure components for running multiple agents with proper isolation, conflict prevention, and tracking.

## Components

### 1. Port Manager
Allocates dedicated ports per agent to prevent conflicts.

```python
from agent_port_manager import AgentPortManager

pm = AgentPortManager()
ports = pm.allocate_ports_for_agent('agent-id', 'agent-type')
# Returns: {'webhook': 8081, 'api': 8082, 'communication': 8083, 'llm_proxy': 8084}
```

**Port Ranges:**
- Titan: 8081-8090
- Avery: 8091-8100
- Trading: 8101-8110
- Research: 8111-8120
- Default: 8200-8299

### 2. File Locking
Prevents agents from modifying each other's files.

```python
from file_locking import get_file_locking, LockType

fl = get_file_locking()

# Agent 1 locks file
lock_id = fl.acquire_lock('/path/to/file', 'agent1', LockType.EXCLUSIVE)

# Agent 2 cannot modify
status = fl.check_lock('/path/to/file', 'agent2')
# Returns: {'locked': True, 'agent_id': 'agent1', ...}

# Release
fl.release_lock(lock_id, 'agent1')
```

### 3. Changelog System
Append-only CHANGELOG.md for tracking agent work.

```python
from changelog_manager import log_agent_action

log_agent_action(
    '/project/path',
    'agent-id',
    'Created',
    'Added new feature',
    ['file.py'],
    'Details about the change'
)
```

### 4. Builder Code Integration
Hardcodes blockchain builder code into all agents.

```python
from builder_code_integration import get_builder_code_manager

bcm = get_builder_code_manager()

# Register agent with builder code
bcm.register_agent('agent-id', 'Agent Name', 'agent-type')

# Append to transaction
tx_with_builder = bcm.append_builder_code_to_transaction(tx_data)

# Verify
verification = bcm.verify_agent_builder_code('agent-id')
```

**Builder Code:** `bc_26ulyc23`
**Hex:** `0x62635f3236756c79633233`

## Key Patterns

### Agent Creation with Infrastructure
```python
def create_agent_with_infrastructure(agent_id, agent_type):
    # 1. Allocate ports
    pm = AgentPortManager()
    ports = pm.allocate_ports_for_agent(agent_id, agent_type)
    
    # 2. Register with builder code
    bcm = get_builder_code_manager()
    bcm.register_agent(agent_id, agent_name, agent_type)
    
    # 3. Initialize changelog
    cm = ChangelogManager()
    cm.initialize_changelog(f'/workspace/{agent_id}', agent_id)
    
    return {'ports': ports, 'builder_code': bcm.BUILDER_CODE}
```

### Safe File Operations
```python
from file_locking import AgentFileOperation, LockType

# Context manager for safe file operations
with AgentFileOperation('/path/to/file', 'agent-id', LockType.EXCLUSIVE):
    # Safe to modify - other agents locked out
    with open('/path/to/file', 'w') as f:
        f.write('new content')
```

## Common Issues

### Port Conflicts
```bash
# Check what's using a port
netstat -tlnp | grep 8081

# Release stale allocations
pm.cleanup_stale_allocations()
```

### Permission Errors
```bash
# Fix ownership
sudo chown -R ubuntu:ubuntu /opt/telegram-webhook
sudo chown -R ubuntu:ubuntu /tmp/bot_*
```

### Import Errors
```bash
# System Python needs psutil
sudo apt-get install python3-psutil

# Ensure typing imports
from typing import Dict, List, Optional, Any, Tuple
```

## Agent Management System

### Creating Agents with Unique Identities

Each agent gets a unique identity with personality, expertise, and its own Telegram bot.

```python
from agent_manager import get_agent_manager

manager = get_agent_manager()

# Create agent with unique identity
result = manager.create_agent('ui', 'Design-Master')
# Returns: {
#   'success': True,
#   'agent_id': 'ui-a1b2c3d4',
#   'name': 'Design-Master',
#   'personality': 'Creative and detail-oriented',
#   'expertise': ['User Interface Design', 'User Experience', ...],
#   'builderCode': 'bc_26ulyc23',
#   'builderCodeHex': '0x62635f3236756c79633233'
# }
```

**Agent Types (8 Specializations):**
- `ui` - UI/UX Specialist
- `integration` - Integration Architect  
- `blockchain` - Blockchain & Security
- `debugger` - Debugger
- `documentation` - Documentation Specialist
- `optimization` - Optimization Expert
- `architecture` - Organizational Architect
- `validation` - Validation Expert

### Telegram Bot Setup Wizard

```python
# Start setup wizard for agent
result = manager.setup_telegram_bot('ui-a1b2c3d4')
# Returns wizard instructions for creating Telegram bot

# Or provide token directly
result = manager.setup_telegram_bot('ui-a1b2c3d4', 'BOT_TOKEN_HERE')
# Creates bot script, systemd service, and starts bot
```

### Lead Agent as Manager

```python
from lead_agent import get_lead_agent

lead = get_lead_agent()

# List all agents
agents = lead.list_agents()

# Get agent details
details = lead.get_agent_details('ui-a1b2c3d4')

# Detect configuration issues
issues = lead.detect_issues()

# Get available agent types
types = lead.get_agent_types()
```

## Telegram Bot Commands

The system includes 50+ slash commands for comprehensive bot management.

### Agent Commands (`/agent`)
```
/agent list [type]          - List all agents
/agent create <type> [name] - Create new agent
/agent setup <id> [token]   - Set up Telegram bot
/agent show <id>            - Show agent details
/agent types                - Show available types
/agent issues               - Check configuration issues
```

### Crew Commands (`/crew`)
```
/crew create <name> <agents> - Create multi-agent crew
/crew start <name>           - Start autonomous workflow
/crew status <name>          - Show crew status
/crew stop <name>            - Stop crew workflow
```

### Other Commands
- `/alias` - Comprehensive alias management
- `/env` - Environment variable management
- `/model` - Model control and thinking power
- `/session` - Session management
- `/memory` - Memory control

## Autonomous Crew System

### Creating a Crew

```python
from autonomous_crew import CrewManager

# Initialize crew
crew = CrewManager('/project/path')
crew.initialize_crew(
    project_name='My Project',
    success_criteria=['All tests pass', 'Documentation complete'],
    agent_types=['ui', 'debugger', 'documentation']
)

# Run autonomous workflow
crew.run_autonomous_workflow(max_iterations=100)
```

### Workflow Phases
1. **Planning** - Lead agent creates blueprint
2. **Confirmation** - Blueprint solidifying
3. **Acting** - Autonomous execution (1-2 agents at a time)
4. **Validation** - End-to-end testing

### Key Features
- Mandatory agent-to-agent communication
- Checkpoints every 5 iterations
- Git commits after every change
- agent.json logging per agent
- Autonomous problem-solving (web search when stuck)

## Deployment

### Service Configuration
```ini
# /etc/systemd/system/telegram-{agent-id}.service
[Unit]
Description=Telegram Bot - {agent-name}
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/telegram-webhook/{agent-id}_bot.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=WEBHOOK_PORT={port}
User=ubuntu
Group=ubuntu

[Install]
WantedBy=multi-user.target
```

### Permission Fixes
```bash
# Fix ownership for bot directories
sudo chown -R ubuntu:ubuntu /opt/telegram-webhook
sudo chown -R ubuntu:ubuntu /tmp/bot_*
sudo chown -R ubuntu:ubuntu /tmp/titan_*
sudo chown -R ubuntu:ubuntu /tmp/avery_*

# Install required packages
sudo apt-get install python3-psutil
```

## Troubleshooting

### Import Errors
```python
# Missing typing imports - add to file
from typing import Dict, List, Optional, Any, Tuple

# Missing psutil
sudo apt-get install python3-psutil
```

### Permission Errors
```bash
# Bot can't write to directories
sudo chown -R ubuntu:ubuntu /opt/telegram-webhook
sudo chown -R ubuntu:ubuntu /tmp/bot_*
```

### Token Issues
```bash
# Verify token works
python3 -c "
import requests
r = requests.get('https://api.telegram.org/botTOKEN/getMe')
print(r.json())
"
```

### Service Not Starting
```bash
# Check service logs
sudo journalctl -u telegram-{agent-id}.service -f

# Check Python path
which python3  # Should be /usr/bin/python3 for system service
```

## Three-Bot Architecture

The system runs three separate Telegram bots:

### Hermes Bot (Communication)
- **Service:** `telegram-bot.service`
- **Username:** @hermes_vpss_bot
- **Token:** 8607935991:AAF2BMsLneIqYDQ2pOwoV6HmVS_Kl5gJlx8
- **Purpose:** Direct communication with user
- **Commands:** 50 (including /agent, /crew)

### Titan Bot (Infrastructure Agent)
- **Service:** `telegram-titan.service`
- **Token:** New token from @BotFather required
- **Purpose:** Infrastructure, development, operations
- **Commands:** 50 (full admin access)

### Avery Bot (Child-Safe Agent)
- **Service:** `telegram-avery.service`
- **Token:** 8507673087:AAFKGSvRwQwq8qQqQqQqQqQqQqQqQqQqQqQ
- **Purpose:** Child-safe companion for Ava (6yo)
- **Commands:** 18 (limited, child-safe)

## Deploying New Bot

```bash
# 1. Create bot via @BotFather
# 2. Update token in bot file
sudo sed -i 's/TOKEN="PLACEHOLDER"/TOKEN="new_token"/g' /opt/telegram-webhook/{agent}_bot.py

# 3. Create service
sudo tee /etc/systemd/system/telegram-{agent}.service > /dev/null << 'EOF'
[Unit]
Description=Hermes Telegram Bot ({Agent})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/telegram-webhook/{agent}_bot.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=AGENT_ID={agent}
WorkingDirectory=/opt/telegram-webhook
User=ubuntu
Group=ubuntu

[Install]
WantedBy=multi-user.target
EOF

# 4. Enable and start
sudo systemctl daemon-reload
sudo systemctl enable telegram-{agent}.service
sudo systemctl start telegram-{agent}.service
```

## Files

### Core Infrastructure
- `agent_port_manager.py` - Port allocation with auto-expansion
- `file_locking.py` - File flocking for agent isolation
- `changelog_manager.py` - Append-only changelogs
- `builder_code_integration.py` - Blockchain builder codes

### Agent Management
- `agent_manager.py` - Agent creation with unique identities
- `lead_agent.py` - Lead agent as manager
- `enhanced_telegram_commands.py` - Telegram bot commands
- `autonomous_crew.py` - Crew workflow engine

### Configuration
- `~/.hermes/builder-code/builder-code.json` - Builder code config
- `~/.hermes/builder-code/agent-registry.json` - Agent registry
- `/opt/telegram-webhook/port_config.json` - Port allocations

### Bot Scripts
- `/opt/telegram-webhook/bot_enhanced.py` - Hermes bot (50 commands)
- `/opt/telegram-webhook/titan_bot_enhanced.py` - Titan bot (50 commands)
- `/opt/telegram-webhook/avery-bot_enhanced.py` - Avery bot (18 commands)

## Validation

Run comprehensive validation:
```bash
cd ~/hermes-agent
python3 final_validation.py
```

Expected output: 32/32 tests passed (100%)

### What Gets Validated
1. **Builder Code Integration** - Hardcoded values verified
2. **Agent Creation** - Agents get builder code automatically
3. **Builder Code Registry** - All agents tracked and verified
4. **Transaction Integration** - Builder code appended to TXs
5. **Port Manager** - Auto-expanding ports working
6. **File Locking** - Agent-specific locking working
7. **Changelog System** - Append-only enforcement working
8. **Lead Agent** - Agent management working
9. **Telegram Commands** - All 50 commands registered
10. **Autonomous Crew** - Crew workflows working

### Validation Results (100% Pass Rate)
```
✅ Builder Code: HARDWIRED (bc_26ulyc23)
✅ Agent Creation: WORKING
✅ Builder Code Registry: WORKING
✅ Transaction Integration: WORKING
✅ Port Manager: WORKING
✅ File Locking: WORKING
✅ Changelog System: WORKING
✅ Lead Agent: WORKING
✅ Telegram Commands: WORKING
✅ Autonomous Crew: WORKING
```
