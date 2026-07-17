# Lesson: Exit Code Capture Bug in `if/else`

## Context
Capturing exit codes from piped commands for error handling.

## What Happened
Error branch always showed "exit code: 1" regardless of actual failure:
```bash
# BROKEN — $? is always 1 (from if condition failing)
if echo -e "y\ny" | "$ventoy_script" -i "$DEVICE"; then
    echo "Success"
else
    echo "Exit code: $?"  # Always 1, not Ventoy's actual code
fi
```

## Resolution
Capture exit code before the if:
```bash
# CORRECT — capture exit code explicitly
local ventoy_exit=0
ventoy_output=$(echo -e "y\ny" | "$ventoy_script" -i "$DEVICE" 2>&1) || ventoy_exit=$?

if [[ $ventoy_exit -eq 0 ]]; then
    echo "Success"
else
    echo "Exit code: $ventoy_exit"  # This is Ventoy's actual exit code
fi
```

## Prevention
- Always use `command || exit_code=$?` pattern for exit code capture
- Never rely on `$?` inside `if/else` blocks
- Capture output and exit code together: `output=$(cmd 2>&1) || exit_code=$?`

## Date: 2026-06-10
## Verified: yes
