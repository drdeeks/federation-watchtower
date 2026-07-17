# Hemlock CLI & TUI Patterns Reference

## Hemlock CLI (scripts/hemlock)

### Command Structure
```bash
hemlock <command> [subcommand] [args...]

# Gateway commands
hemlock gateway start|status|stop|restart|logs|health

# Agent commands
hemlock agent create <id> [model] [name]
hemlock agent attach <id>
hemlock agent detach <id>
hemlock agent delete <id>
hemlock agent list
hemlock agent export <id> [MINIMAL|STANDARD|FULL]
hemlock agent import <src> <new_id>
hemlock agent copy <id> [skill1 skill2...]

# Crew commands
hemlock crew create <name> [agent1 agent2...]
hemlock crew attach <name>
hemlock crew detach <name>
hemlock crew delete <name>
hemlock crew list
hemlock crew export <name> [MINIMAL|STANDARD|FULL]
hemlock crew import <src> <new_name>

# System
hemlock doctor
hemlock backup create|list|restore
hemlock usb create|restore
```

### Agent Creation Flow
```bash
# 1. Create agent (generates init script)
hemlock agent create agent-001 anthropic/claude-sonnet-4 "Research Agent"

# 2. Attach to gateway (registers MCP bridge)
hemlock agent attach agent-001

# 3. Verify
hemlock agent list
# agent-001: Research Agent (attached)
```

### Agent Export/Import Modes
| Mode | Includes | Excludes |
|------|----------|----------|
| MINIMAL | Core identity, avatars/, tools/ | config.yaml, .env, .secrets/, sessions/, memory/, skills/ |
| STANDARD | Minimal + config.yaml, .env, .secrets/, HEARTBEAT.md, skills/, latest 5 sessions/, latest 5 memory/ | Full history, logs/ |
| FULL | Entire volume | Nothing |

### Export Example
```bash
# Export agent with STANDARD mode
hemlock agent export agent-001 STANDARD
# Creates: /tmp/hemlock-export/agent-001.tar.gz

# Import with new ID
hemlock agent import /tmp/hemlock-export/agent-001.tar.gz agent-002
```

## Hemlock TUI (scripts/hemlock-tui)

### Menu Structure
```
┌─────────────────────────────────────┐
│         HEMLOCK TUI v1.0            │
├─────────────────────────────────────┤
│ 1. Gateway Management               │
│ 2. Agent Management                 │
│ 3. Crew Management                  │
│ 4. Skills Management                │
│ 5. Backup/Restore                   │
│ 6. System Status                    │
│ 7. Settings                         │
│ Q. Quit                             │
└─────────────────────────────────────┘
```

### Agent Management Submenu
```
┌─────────────────────────────────────┐
│      Agent Management               │
├─────────────────────────────────────┤
│ 1. List Agents                      │
│ 2. Create Agent                     │
│ 3. Attach Agent                     │
│ 4. Detach Agent                     │
│ 5. Delete Agent                     │
│ 6. Export Agent                     │
│ 7. Import Agent                     │
│ B. Back                             │
└─────────────────────────────────────┘
```

### Interactive Agent Creation
```text
Create New Agent
─────────────────
Agent ID: agent-001
Model: anthropic/claude-sonnet-4
Name: Research Agent
Skills (comma-separated): enterprise-organization, skill-installer

[Create] [Cancel]
```

## CLI Patterns & Best Practices

### Error Handling
```bash
# Exit codes
0  = success
1  = general error
2  = invalid arguments
3  = not found
4  = permission denied
5  = gateway unavailable
```

### Output Formats
```bash
# Human readable (default)
hemlock agent list
# agent-001: Research Agent (attached)
# agent-002: Trading Bot (detached)

# JSON output
hemlock agent list --json
# [{"id":"agent-001","name":"Research Agent","status":"attached"}]

# CSV output
hemlock agent list --csv
# id,name,status
# agent-001,Research Agent,attached
```

### Verbose Mode
```bash
hemlock --verbose agent create agent-001
# DEBUG: Creating agent directory
# DEBUG: Generating init script
# DEBUG: Starting container
# INFO: Agent created successfully
```

## MCP Integration in CLI

### Agent Attach (Registers MCP)
```bash
# Under the hood:
# 1. Creates agent volume
# 2. Copies init script to volume
# 3. Runs init script (registers MCP bridge)
# 4. Restarts gateway to pick up new agent
```

### Agent Export (MCP Data)
```bash
# Exports via MCP gateway
# 1. Calls gateway /mcp export endpoint
# 2. Streams agent volume data
# 3. Compresses to tar.gz
# 4. Includes MCP bridge registration
```

## TUI Keyboard Shortcuts

| Key | Action |
|-----|--------|
| ↑/↓ | Navigate menu |
| Enter | Select |
| Esc/B | Back/Cancel |
| q/Q | Quit |
| h/? | Help |
| r | Refresh |

## Error Messages

| Error | Cause | Fix |
|-------|-------|-----|
| "Agent already attached" | Agent already registered | `hemlock agent detach <id>` first |
| "Gateway unavailable" | Gateway not running | `hemlock gateway start` |
| "Invalid agent ID" | ID doesn't exist | `hemlock agent list` to check |
| "Port 41214 in use" | MCP proxy running | `systemctl stop hemlock-mcp-proxy-manager` |

## Configuration

### CLI Config (~/.hemlock/config.yaml)
```yaml
gateway:
  host: localhost
  port: 18789
  token: "test-token-12345"

output:
  format: human  # human|json|csv
  color: true

defaults:
  model: anthropic/claude-sonnet-4
  skills: [enterprise-organization, skill-installer]

tui:
  theme: dark
  refresh_interval: 5
```

## Testing CLI

```bash
# Test all commands
./scripts/hemlock gateway health
./scripts/hemlock agent create test-agent
./scripts/hemlock agent attach test-agent
./scripts/hemlock agent list --json
./scripts/hemlock agent detach test-agent
./scripts/hemlock agent delete test-agent

# Test TUI (requires TTY)
docker exec -it hemlock-runtime /scripts/hemlock-tui
```