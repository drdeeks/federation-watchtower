# PHASE-7/8/9 Integration Guide

## Overview
This document captures the integration of PHASE-7 (Safety/Logging/Database), PHASE-8 (Validation/Observability), and PHASE-9 (Knowledge Indexer) into the Hemlock Enterprise Blueprint and the unified-usb-skill framework.

---

## PHASE-7: Safety, Logging & Database Foundation (Week 4)

### Modules Added
| Module | Feature Flag | Script | Purpose |
|--------|-------------|--------|---------|
| MOD-014 | FEAT_SAFETY_LIB | `scripts/safety.sh` | Timeout/retry/circuit breaker, atomic ops, locks, ports, rollback |
| MOD-015 | FEAT_LOGGING_SYSTEM | `scripts/logging.sh` | Structured logging, JSON agent logs, audit trail, dry-run |
| MOD-016 | FEAT_DATABASE | `scripts/database.sh` | SQLite/JSON + migrations, registry sync |

### Key Components

#### Safety Library (`scripts/safety.sh`)
- `safe_command` — Command execution with timeout
- `safe_command_with_retry` — Retry with circuit breaker (5 failures)
- `atomic_write` / `atomic_copy` — Atomic file operations
- `acquire_lock` / `release_lock` — Lock management with timeout
- `allocate_port_atomic` — Atomic port allocation (18790-18899)
- `push_rollback` / `execute_rollback` / `clear_rollback` — Rollback stack
- `verify_ollama_service` — Ollama health check
- `test_model_load` — Model load testing

#### Logging System (`scripts/logging.sh`)
- `log` — Structured logging (ERROR/WARN/SUCCESS/INFO/DEBUG)
- `log_json` — JSONL agent activity logs
- `audit_log` — Security audit trail
- `record_agent_action` — Per-agent action logging
- `spin` / `progress_bar` — Progress indicators
- `dry_run_log` / `execute_or_dry_run` — Dry-run support

#### Database Module (`scripts/database.sh`)
- SQLite and JSON backends
- Agent/crew/message schemas
- Registry sync
- Migration runner (V{NNN}__*.sql)
- JSON state with file locking

### CLI Entry Points Added
```bash
hemlock safety-check           # Check dependencies
hemlock safety-ram             # RAM threshold check
hemlock safety-verify-ollama   # Ollama verification
hemlock safety-test-model      # Test model load
hemlock safety-allocate-port   # Atomic port allocation
hemlock log-tail               # Tail orchestrator log
hemlock log-agent <id>         # View agent JSONL log
hemlock db-status              # Database status + registry
hemlock db-init                # Initialize database
```

---

## PHASE-8: Validation, Security & Observability (Week 5)

### Modules Added
| Module | Feature Flag | Script | Purpose |
|--------|-------------|--------|---------|
| MOD-017 | FEAT_VALIDATION | `scripts/validation.sh` | ID/token/JSON/crew validation, secret scan, path checks |
| MOD-018 | FEAT_OBSERVABILITY | `scripts/observability.sh` | Auto-save, heartbeat, secret scan, agent watchdog |

### Key Components

#### Validation Module (`scripts/validation.sh`)
- ID validation (agent/crew/project)
- Telegram token format + API test
- JSON validation (file + content)
- Crew ruleset validation
- Auth profiles schema validation
- Command existence checking
- Path traversal prevention
- Model backend validation (ollama/llama.cpp)
- GGUF file validation

#### Observability Module (`scripts/observability.sh`)
- Auto-save checkpoints (15-min, git commit on changes)
- Agent heartbeat monitoring (alpha/beta/gamma/titan)
- Secret scanning (multi-repo, multi-branch, patterns)
- Agent watchdog (heartbeat >300s → restart)
- Resource monitoring (VRAM/RAM/GPU)

### CLI Entry Points Added
```bash
hemlock validate-agent-id <id>
hemlock validate-crew-id <id>
hemlock validate-project-id <id>
hemlock validate-telegram-token <token>
hemlock test-telegram-token <token>
hemlock validate-json <file>
hemlock validate-ruleset <file>
hemlock validate-auth <file> [strict]
hemlock validate-gguf <file>
hemlock auto-save
hemlock scan-secrets
hemlock watchdog
```

---

## PHASE-9: Knowledge Indexer & Documentation (Week 6)

### Module Added
| Module | Feature Flag | Script | Purpose |
|--------|-------------|--------|---------|
| MOD-019 | FEAT_KNOWLEDGE_INDEXER | `scripts/knowledge-indexer.sh` | Doc indexer, full-text search, links, incremental |

### Key Components

#### Knowledge Indexer (`scripts/knowledge-indexer.sh`)
- Incremental indexing (content hash diff)
- Excludes: node_modules, .git, .secrets, *.log, secrets
- Keywords extracted (4+ char words)
- Full-text search with scoring
- Link management (add/remove/list/search with categories)
- Scheduled indexing (manual/daily/weekly)

### CLI Entry Points Added
```bash
hemlock docs-index              # Index all documentation
hemlock docs-search "term"      # Full-text search
hemlock docs-add-link <url> <title> [category]
hemlock docs-list               # List indexed documents
hemlock docs-status             # Index status (count, last indexed, categories)
```

---

## Docker Integration

### Dockerfile.runtime Updates
Added 10 new scripts to container:
```dockerfile
# Safety & Core Infrastructure (PHASE-7)
COPY scripts/safety.sh /scripts/safety.sh
COPY scripts/logging.sh /scripts/logging.sh
COPY scripts/database.sh /scripts/database.sh

# Validation & Security (PHASE-8)
COPY scripts/validation.sh /scripts/validation.sh
COPY scripts/observability.sh /scripts/observability.sh

# Knowledge Indexer (PHASE-9)
COPY scripts/knowledge-indexer.sh /scripts/knowledge-indexer.sh

# Testing Framework
COPY scripts/safety-test-framework.sh /scripts/safety-test-framework.sh
COPY scripts/test-runner.sh /scripts/test-runner.sh

# Desktop Access
COPY scripts/desktop-access.sh /scripts/desktop-access.sh
```

### docker-compose.yml Port Updates
```yaml
ports:
  - "18789:18789"    # Gateway
  - "41214:41214"    # MCP Proxy
  - "5901:5901"      # VNC
  - "5930:5930"      # SPICE
  - "5931:5931"      # SPICE TLS
```

---

## Entry Points (entrypoint.sh)

Added 50 new CLI commands across all phases:
- Model Management (8 commands)
- Safety & Logging (6 commands)
- Database (2 commands)
- Validation (9 commands)
- Observability (3 commands)
- Knowledge Indexer (5 commands)
- Testing (5 commands)
- Desktop Access (8 commands)
- Self-Healing (3 commands)

---

## Blueprint Validation Results

| Check | Status |
|-------|--------|
| Total Checks | 48 |
| Passed | 46 |
| Failed | 0 |
| Warned | 2 |

Warnings (minor documentation only):
1. Table of contents present — checklist.md serves as TOC
2. Test coverage target specified — implemented in test-runner.sh

---

## Related Files
- `references/bash-enhanced-troubleshooting.md` — Bash script debugging
- `references/testing-framework.md` — Testing framework with safety wrapper
- `references/setup-wizard-hemlock.md` — Hemlock deployment via setup wizard
- `unified-usb-skill/scripts/setup-essentials-enhanced.sh` — Enhanced USB setup

---

## Version History
| Date | Version | Changes |
|------|---------|---------|
| 2026-06-14 | 1.0 | Initial PHASE-7/8/9 integration documentation |