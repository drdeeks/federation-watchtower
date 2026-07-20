# Enterprise Validation Pitfalls

## Hardcoded Paths (Most Common Failure)

The skill_enhance.py validator rejects hardcoded paths in SKILL.md and scripts.

**Banned patterns:**
- `$HOME/` — any absolute path with a username
- `~/.hermes/` — tilde paths in SKILL.md content

**Use instead:**
- `<HEMLOCK_HOME>` — for Hermes config/skill paths
- `<WORKSPACE_ROOT>` — for project/workspace paths
- Runtime detection in scripts: `os.environ.get("WORKSPACE_ROOT", os.path.join(os.path.expanduser("~"), "qwen-cloud-2026"))`

**Exception:** Paths in code examples that show the actual runtime behavior are OK if they use variables. The validator flags literal `/home/` patterns.

## Reference File Types

Only these extensions allowed in `references/`:
- `.md`, `.html`, `.pdf`, `.txt`

**JSON files must go in** `references/templates/` (any type allowed there).

## Reference Subdirectories

Only `templates/` and `lessons/` allowed under `references/`.
Other dirs (like `test-specs/`) must be moved to `references/templates/`.

## Enterprise Tier Requirements

| Component | Minimum |
|-----------|---------|
| Tags (metadata.tags) | 7+ |
| Scripts | 5+ substantive |
| References | 7+ substantive |
| Description | 100-1024 chars |

## Script Validation

Scripts must have:
- Proper shebang (`#!/usr/bin/env python3` or `#!/usr/bin/env bash`)
- `--help` support (for CLI scripts)
- No syntax errors

## Quick Fix Workflow

1. Run `skill_enhance.py update --path <skill> --noninteractive`
2. Check output for FAIL items
3. Fix hardcoded paths → use placeholders or runtime detection
4. Move wrong file types to `references/templates/`
5. Add missing scripts/references
6. Re-run validation
