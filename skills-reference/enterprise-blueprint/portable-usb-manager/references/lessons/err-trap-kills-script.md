# Lesson: ERR Trap With `exit 1` Kills Script Silently

## Context
Interactive USB setup script using `set -euo pipefail` with an ERR trap for debugging failed piped commands.

## What Happened
Script exited without showing any error message. The ERR trap was defined as:
```bash
trap 'echo "[ERROR]"; exit 1' ERR
```
When a piped command failed (due to `pipefail`), the ERR trap fired and called `exit 1`, killing the script before the `if/else` block could handle the error:
```bash
if echo -e "y\ny" | "$ventoy_script" -i /dev/sdX; then
    echo "Success"
else
    echo "Failed"  # NEVER REACHED
fi
```

## Resolution
Changed ERR trap from `exit 1` to log-only:
```bash
trap 'echo "[ERROR] at line $LINENO (exit code: $?)" | tee -a "${LOG_FILE:-/dev/null}"' ERR
```
Captured exit codes explicitly:
```bash
local ventoy_exit=0
ventoy_output=$(echo -e "y\ny" | "$ventoy_script" -i "$DEVICE" 2>&1) || ventoy_exit=$?
```

## Prevention
- In interactive scripts, ERR traps should **log** errors, not **exit**
- Always capture command output and exit codes explicitly with `|| exit_code=$?`
- Let the calling function handle user-facing error display and recovery

## Date: 2026-06-10
## Verified: yes
