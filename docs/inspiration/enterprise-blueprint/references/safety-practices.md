# Safety Practices

## Core Principles

1. **NEVER overwrite critical files** — Always use rename or backup before modification
2. **Use trash over delete** — Preserve recoverable state
3. **chmod 755/644 only** — Never use 700/600 (except .secret-key)
4. **Override protocol** — Store in `.override/TIMESTAMP/` with `EXPLANATION.md`
5. **Immediate notification** — Alert user/manager of any override attempt

## File Operations

| Action | Safe | Unsafe |
|--------|------|--------|
| Modify config | Backup first, then edit | Direct overwrite |
| Delete old files | Move to trash | `rm -rf` |
| Set permissions | `chmod 755` dirs, `644` files | `chmod 700/600` |
| Store secrets | Use dedicated secrets store | Hardcode in scripts |

## Critical Files (Never Overwrite)

- `agent.json` — Agent configuration
- `SOUL.md` — Agent identity
- `MEMORY.md` — Agent memory (short-term)
- `USER.md` — User preferences
- `TOOLS.md` — Agent-specific notes (personal, local)
- `SECURITY.md` — Security policies
- `tools/*` — All tool files
- `skills/*` — All skill files
- `projects/*` — All project files

## Override Protocol

When a critical file must be modified:

1. Create `.override/TIMESTAMP/` directory
2. Copy original file there
3. Create `EXPLANATION.md` documenting the change
4. Apply the modification
5. Notify user immediately
