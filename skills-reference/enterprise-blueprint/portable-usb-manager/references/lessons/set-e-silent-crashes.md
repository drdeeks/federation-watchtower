# Lesson: `set -e` Causes Silent Crashes on Expected Failures

## Context
Interactive script using `set -euo pipefail` for strict error handling.

## What Happened
Script exited at random points with no error message. Common triggers:
- `mkdir -p` on existing directory (returns 0, but some implementations return 1)
- `rm -rf` on non-existent file (returns 1)
- `grep` finding no matches (returns 1)
- Commands in subshells or pipes

## Resolution
Three-layer defense:
1. ERR trap logs, doesn't exit
2. Explicit `|| true` for expected failures
3. Capture and check with `|| exit_code=$?`

```bash
# Layer 1: Log-only ERR trap
trap 'echo "[ERROR] at line $LINENO (exit: $?)" | tee -a "$LOG_FILE"' ERR

# Layer 2: Expected failures
umount "$part" 2>/dev/null || true

# Layer 3: Explicit capture
local output
local exit_code=0
output=$(risky_command 2>&1) || exit_code=$?
```

## Prevention
- ERR traps in interactive scripts should log, not exit
- Use `|| true` for commands where failure is expected/harmless
- Capture output and exit codes explicitly with `|| exit_code=$?`
- Test with piped commands — they behave differently with `pipefail`

## Date: 2026-06-10
## Verified: yes
