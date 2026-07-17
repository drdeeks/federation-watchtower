# Daily Skills Auto-Pull

## Overview
Automated daily git pull of the drdeeks skills repository (https://github.com/drdeeks/skills.git) to keep skills up to date on the portable Hemlock USB deployment.

## Architecture

```
Container (PID 1: OpenClaw Gateway)
├── Gateway process (port 18789)
├── MCP loopback server (random port)
├── cron daemon (started by container-init.sh)
│   └── Daily job: 0 2 * * * /scripts/pull-drdeeks-daily.sh
└── Skills directory: /home/ubuntu/hemlock-minimal/hemlock-minimal/skills/drdeeks/
    ├── 131 .skill files (from drdeeks/skills repo)
    ├── .git/ (for git operations)
    └── ... (skills extracted from .skill files)
```

## Implementation Files

### 1. scripts/pull-drdeeks-daily.sh
```bash
#!/bin/bash
# Daily pull of drdeeks skills repo - runs inside container
# Keeps skills up to date on the portable USB

set -e

SKILLS_DIR="/home/ubuntu/hemlock-minimal/hemlock-minimal/skills/drdeeks"
LOG_FILE="/var/log/drdeeks-pull.log"

echo "[$(date)] Starting drdeeks skills pull" >> $LOG_FILE

# Check if drdeeks repo exists
if [ -d "$SKILLS_DIR/.git" ]; then
    cd "$SKILLS_DIR"
    echo "[$(date)] Pulling latest changes..." >> $LOG_FILE
    git pull origin main 2>&1 | tee -a $LOG_FILE
    echo "[$(date)] Pull complete" >> $LOG_FILE
else
    echo "[$(date)] Initial clone..." >> $LOG_FILE
    git clone --depth 1 https://github.com/drdeeks/skills.git "$SKILLS_DIR" 2>&1 | tee -a $LOG_FILE
    echo "[$(date)] Initial clone complete" >> $LOG_FILE
fi

echo "[$(date)] drdeeks skills update finished" >> $LOG_FILE
```

### 2. Cron Entry (in container-init.sh)
```bash
CRON_JOB="0 2 * * * /home/ubuntu/hemlock-minimal/scripts/pull-drdeeks-daily.sh >> /var/log/drdeeks-cron.log 2>&1"

if ! crontab -l 2>/dev/null | grep -q "pull-drdeeks-daily.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Added daily drdeeks pull cron job (2 AM daily)"
fi
```

### 3. Container Init (runs on startup)
```bash
# Install cron if not present
if ! command -v cron &> /dev/null; then
    apt-get update && apt-get install -y cron 2>/dev/null | tail -5
fi

# Add crontab entry
# ... (see above)

# Start cron daemon
service cron start 2>/dev/null || cron
```

## Crontab Entry
```
0 2 * * * /home/ubuntu/hemlock-minimal/scripts/pull-drdeeks-daily.sh >> /var/log/drdeeks-cron.log 2>&1
```
Runs daily at 2:00 AM UTC.

## Log Files
- `/var/log/drdeeks-pull.log` - Pull operation logs
- `/var/log/drdeeks-cron.log` - Cron execution logs

## Log Rotation
```bash
# /etc/logrotate.d/drdeeks
/var/log/drdeeks-pull.log /var/log/drdeeks-cron.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
```

## Key Design Decisions

1. **Runs inside container** - Not on host, for USB portability
2. **Installs cron if missing** - Many base images don't include it
3. **Checks crontab before adding** - Avoid duplicate entries on restart
4. **Logs to file** - `tee -a` for both stdout and log file
5. **Uses `git pull origin main`** - Explicit remote/branch
6. **Uses `--depth 1` for initial clone** - Shallow clone saves space
7. **Log timestamps** - `[$(date)]` prefix for debugging
8. **Checks `.git` directory** - Not just directory existence
9. **Redirects stderr** - `2>&1 | tee -a` captures all output
9. **Uses `git pull origin main`** - Not just `git pull`
10. **Shallow clone** - Saves space on USB

## Cron Syntax
```
0 2 * * *  = 2:00 AM daily
```

## Verification
```bash
# Check cron is running
service cron status

# View crontab
crontab -l

# Check logs
tail -f /var/log/drdeeks-pull.log
tail -f /var/log/drdeeks-cron.log

# Test pull manually
/scripts/pull-drdeeks-daily.sh
```

## Integration with USB Deployment

The daily pull keeps the skills on the USB up to date:
1. USB deployed with initial skills clone
2. On target machine, container starts
3. Cron starts, adds daily pull job
4. Daily at 2 AM: `git pull` updates skills
5. Skills available immediately to agents via `/skills` mount

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Cron not running | Service not started | `service cron start` |
| Duplicate entries | Restart adds duplicates | Check `crontab -l | grep` before adding |
| Git pull fails | No internet | Log failure, retry next day |
| Permission denied | Script not executable | `chmod +x /scripts/pull-drdeeks-daily.sh` |
| Cron not persisting | Container restart loses crontab | Add to entrypoint.sh startup |
| Drdeeks repo missing | Never cloned | Script handles initial clone |

## Cron Syntax
```
0 2 * * *  = 2:00 AM daily
```

## Manual Test
```bash
# Test pull manually
/scripts/pull-drdeeks-daily.sh

# Check logs
tail -f /var/log/drdeeks-pull.log
tail -f /var/log/drdeeks-cron.log

# Check skills updated
ls -la /home/ubuntu/hemlock-minimal/hemlock-minimal/skills/drdeeks/
```