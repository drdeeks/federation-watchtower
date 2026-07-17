# Lesson: Hardcoded Paths Break Portability

## Context
Script developed on one machine, deployed to another.

## What Happened
```bash
# BROKEN — hardcoded path
local script_dir="/path/to/your/project/scripts"

# BROKEN — assumes specific user
LOG_FILE="/tmp/usb-setup-$USER.log"
```
Script worked on development machine but failed on production.

## Resolution
```bash
# CORRECT — derive from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CORRECT — use system temp directory
LOG_FILE="$(mktemp /tmp/usb-setup-XXXXXX.log)"
```

## Prevention
- Never hardcode user paths or usernames
- Use `BASH_SOURCE[0]` for script directory
- Use `mktemp` for temporary files
- Test on a clean environment before deploying

## Date: 2026-06-10
## Verified: yes
