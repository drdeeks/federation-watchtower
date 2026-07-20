# Operational Guide — Loop Enforcer

## Quick Start

```bash
# Create a new chain for your project
chain.py create my-project build-chain src/main.py src/utils.py tests/test_main.py

# Check which file is next to work on
chain.py check my-project build-chain

# When file is ready, verify it
chain.py verify my-project build-chain src/main.py

# Complete the step
chain.py complete my-project build-chain src/main.py

# See full status
chain.py status my-project build-chain
```

## Chain Lifecycle

```
1. CREATE → 2. ACTIVE (first step) → 3. WORK → 4. VERIFY → 5. COMPLETE
                                                                 ↓
                                              (next step becomes ACTIVE)
                                              ↓
                                             REPEAT until all complete
```

## States Explained

| State | Meaning | Agent Action |
|-------|---------|--------------|
| `locked` | Previous step not complete | **STOP** — cannot touch |
| `active` | Ready to work | **WORK** — write the file |
| `pending_verify` | File written, needs check | **VERIFY** — run tests/lint |
| `verified` | Checks passed | **COMPLETE** — mark done |
| `complete` | Step finished | Move to next |

## Interactive Menu

```bash
chain.py menu my-project build-chain
```

Commands:
- `v` — Verify current step
- `c` — Complete current step  
- `s` — Show status
- `l` — View audit log
- `a` — Add step to chain
- `q` — Quit

## Audit Log

Every action logged to `.chain/<name>.log`:
```json
{"ts": "2026-01-15T10:30:00Z", "action": "verify", "file": "src/main.py", "result": "ok"}
{"ts": "2026-01-15T10:31:00Z", "action": "complete", "file": "src/main.py", "next": "src/utils.py"}
```

## Verification Hooks

Add validators in chain JSON:
```json
{
  "steps": [
    {
      "file": "src/main.py",
      "validator": "python3 -m py_compile src/main.py && python3 -m pytest tests/"
    }
  ]
}
```

Validator runs on `chain.py verify`. Must exit 0 for success.

## Common Patterns

### Feature Branch Chain
```bash
chain.py create feature-auth login-flow \
  src/auth/login.py src/auth/token.py tests/test_auth.py
```

### Release Chain
```bash
chain.py create v1.2 release \
  CHANGELOG.md pyproject.toml src/__init__.py
```

### Documentation Chain enforcer will block premature version bump
```

### CI Integration
```yaml
# .github/workflows/chain.yml
- name: Check chain status
  run: chain.py check my-project build-chain
- name: Verify step
  run: chain.py verify my-project build-chain src/main.py
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "File locked" | Complete previous step first |
| "Validator failed" | Fix code, re-run verify |
| "No active step" | All complete or chain not started |
| "Chain not found" | Check `.chain/` directory name |

## Migration

```bash
# Export chain
chain_migrate.py export --chain build-chain --output chain-backup.json

# Import to another project
chain_migrate.py import --input chain-backup.json --name build-chain-v2

# Sync between environments
chain_migrate.py sync --target-dir ../prod --direction push
```

## Recovery

If chain state corrupted:
1. Check `.chain/<name>.log` for last good state
2. Delete `.chain/<name>.json` 
3. Re-create chain with same steps
4. Steps before last verified will auto-verify