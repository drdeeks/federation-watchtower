# Lesson: Ventoy2Disk.sh Has No `-y` Flag

## Context
Building an automated USB setup script that installs Ventoy non-interactively. The script used `set -euo pipefail` with an ERR trap for error handling.

## What Happened
Script crashed immediately after user confirmed installation. No error message visible. The command:
```bash
"$ventoy_script" -i -y /dev/sdX
```
Failed because `-y` is not a valid Ventoy2Disk.sh flag. Ventoy treats unrecognized flags as device paths, so `-y` was interpreted as a non-existent block device.

With `set -euo pipefail`, the error was swallowed by the ERR trap before the if/else could catch it.

## Resolution
Removed `-y` flag. Piped two `y` answers to Ventoy's two confirmation prompts:
```bash
echo -e "y\ny" | "$ventoy_script" -i /dev/sdX
```

## Prevention
- Always check `command --help` before assuming CLI flags exist
- Never assume common flags like `-y`, `--yes`, `--force` are supported
- Ventoy2Disk.sh valid flags: `-i`, `-I`, `-u`, `-l`, `-r`, `-s`, `-S`, `-g`, `-L`, `-n`

## Date: 2026-06-10
## Verified: yes
