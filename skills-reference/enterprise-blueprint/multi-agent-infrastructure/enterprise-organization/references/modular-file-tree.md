# Modular File Tree Standard

## Table of Contents

- [Overview](#overview)
- [Core Principles](#core-principles)
- [Directory Structure](#directory-structure)
- [Role-Specific Layouts](#role-specific-layouts)
- [Validation Rules](#validation-rules)
- [Auto-Correction](#auto-correction)

## Overview

The Modular File Tree Standard defines a consistent, scalable directory structure for all enterprise agent workspaces. This structure ensures:

- **Predictability** - Every agent/workspace follows the same pattern
- **Separation of Concerns** - Config, data, code, secrets are isolated
- **Security** - Clear boundaries for permission enforcement
- **Scalability** - Easy to add new agents, skills, plugins
- **Auditability** - Clear structure for compliance checks

## Core Principles

1. **Everything has a place** - No files in root except standard docs
2. **Secrets isolated** - `.secrets/` with 700 permissions, never in git
3. **Config separated** - `config/` for all configuration files
4. **Data persistent** - `data/` for databases, state, persistent storage
5. **Code modular** - `scripts/` for executable code, separated by concern
6. **Documentation deep** - `references/` for detailed docs loaded on demand
7. **Logs rotated** - `logs/` with automatic rotation
8. **Backups automated** - `backups/` with timestamped snapshots

## Directory Structure

### Base Structure (All Roles)

```
project-root/
├── .secrets/                 # 700 perms - credentials, keys, wallets, tokens
├── .github/
│   └── workflows/            # CI/CD pipelines
├── agents/                   # Agent-specific workspaces
├── skills/                   # Installed skills (symlinked or copied)
├── plugins/                  # Custom plugins/extensions
├── cron/                     # Scheduled jobs (systemd timers, cron)
├── config/                   # Configuration files (YAML, JSON, TOML)
├── data/                     # Persistent data (DBs, state, indexes)
├── logs/                     # Application logs (rotated)
├── backups/                  # Automated backups (timestamped)
├── tmp/                      # Temporary files (gitignored, cleaned on boot)
├── scripts/                  # Enterprise management scripts
├── references/               # Deep documentation
├── .gitignore                # Enterprise gitignore standards
├── README.md                 # Project documentation (required)
├── CHANGELOG.md              # Append-only change log (required)
└── TODO.md                   # Active task tracking (required)
```

### Required Root Files

| File | Purpose | Required |
|------|---------|----------|
| `README.md` | Tech stack tags, quick start, file tree, troubleshooting, official sources | ✅ |
| `CHANGELOG.md` | Append-only history with datetime, author, changes, method, validation, reasoning | ✅ |
| `TODO.md` | Active task tracking with validation evidence | ✅ |
| `.gitignore` | Enterprise security patterns | ✅ |

## Role-Specific Layouts

### Hermes (Orchestrator)
```
hermes-workspace/
├── agents/              # Agent configs: hermes, titan, avery, allman
├── skills/              # Loaded skills
├── plugins/             # Custom plugins
├── cron/                # Scheduled orchestration jobs
└── .github/workflows/   # Multi-agent CI/CD
```

### Titan (Trading)
```
titan-workspace/
├── agents/              # Trading agent configs
├── trading/             # Live trading strategies
├── strategies/          # Strategy configurations
├── data-feeds/          # Market data sources
└── .github/workflows/   # Trading pipeline CI/CD
```

### Avery (Creative)
```
avery-workspace/
├── agents/              # Creative agent configs
├── creative/            # Creative projects
├── media/               # Media assets
├── generation/          # Generation outputs
└── .github/workflows/   # Creative pipeline CI/CD
```

### Allman (Onchain)
```
allman-workspace/
├── agents/              # Onchain agent configs
├── onchain/             # Onchain operations
├── erc8004/             # ERC-8004 agent registrations
├── pinata/              # IPFS pins
├── wallets/             # Wallet management
└── .github/workflows/   # Onchain pipeline CI/CD
```

## Validation Rules

### Structure Validation (`validate_structure.py`)

```bash
# Check compliance
python3 scripts/validate_structure.py --workspace /path/to/workspace --role hermes

# Auto-fix missing directories
python3 scripts/validate_structure.py --workspace /path/to/workspace --role hermes --fix
```

**Checks performed:**

1. All base directories exist
2. Role-specific directories exist
3. `.secrets/` has 700 permissions
4. Required root files exist (README.md, CHANGELOG.md, TODO.md, .gitignore)
5. No unexpected directories (warns on extra)

### Auto-Correction

When `--fix` is used:
- Missing directories created with correct permissions
- `.secrets/` set to 700
- Reports all actions taken

## Integration

The modular file tree is validated on every enterprise operation:
- `init` - Creates structure from scratch
- `validate` - Checks compliance
- `enforce` - Auto-corrects deviations
- `audit` - Full compliance report
- `changelog` - Tracks structural changes

## Compliance

**Enterprise Grade Requirements:**
- ✅ All base directories present
- ✅ Role-specific directories present
- ✅ `.secrets/` = 700 permissions
- ✅ Required root files exist
- ✅ No world-writable files
- ✅ `.gitignore` covers all secret patterns