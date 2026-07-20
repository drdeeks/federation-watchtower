# Critical File Protection

## Purpose

Prevents accidental or unauthorized modification of files that could break agent configuration, identity, or security.

## Protected Files

### Identity Files
- `agent.json` — Core agent configuration
- `SOUL.md` — Agent personality and identity
- `MEMORY.md` — Agent memory (short-term)
- `USER.md` — User preferences and context
- `TOOLS.md` — Agent-specific personal notes (NEVER overwrite)
- `SECURITY.md` — Security policies and practices

### Tool Files
- `tools/*` — All files in tools/ directory
- `skills/*` — All files in skills/ directory
- `projects/*` — All files in projects/ directory

## Detection Script

Use `scripts/validate.sh` to check if a file is critical:

```bash
scripts/validate.sh --check-permissions
```

## Safe Write Pattern

Use `scripts/safe-write.sh` to safely modify files:

```bash
scripts/safe-write.sh <target_file> <source_file>
```

If the target is critical, the script:
1. Creates `.override/TIMESTAMP/` directory
2. Copies the original target there
3. Creates `EXPLANATION.md` with the change reason
4. Applies the modification
5. Returns success/failure status
