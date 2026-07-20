# Agnostic Rules Reference

## Table of Contents

- [Purpose](#purpose)
- [Hardcoded Path Patterns](#hardcoded-path-patterns)
- [Platform Compatibility](#platform-compatibility)
- [Environment Variable Patterns](#environment-variable-patterns)
- [File Path Patterns](#file-path-patterns)
- [Network Patterns](#network-patterns)
- [Validation Checklist](#validation-checklist)
- [Testing Agnostic Compliance](#testing-agnostic-compliance)
- [Common Anti-Patterns](#common-anti-patterns)

## Purpose

Ensure all skills are platform-agnostic and work across different environments without modification.

## Hardcoded Path Patterns

### ❌ Never Use

```bash
# Home directories (use ${HOME} instead)
USERNAME_HOME/
USER_HOME/

# Application paths (use ${APP_DIR} instead)
APP_DIR/
LOCAL_APP_DIR/

# Config paths (use env vars)
OPENCLAW_DIR/
HERMES_DIR/
OPENCODE_DIR/

# Temp paths (use ${TMPDIR} instead)
TMPDIR_APP/
```

### ✓ Use Instead

```bash
# Use environment variables
${HOME}/
${XDG_CONFIG_HOME:-$HOME/.config}/

# Use generic paths
${APP_DIR:-/opt/app-name}/
${TEMP_DIR:-/tmp}/

# Use tilde expansion
~/
~/.
```

## Platform Compatibility

### Commands to Avoid

```bash
# Linux-specific
apt-get install
systemctl start
journalctl

# macOS-specific
brew install
launchctl

# Windows-specific
winget install
sc start
```

### Portable Alternatives

```bash
# Package detection
if command -v apt-get &> /dev/null; then
    apt-get install
elif command -v brew &> /dev/null; then
    brew install
elif command -v winget &> /dev/null; then
    winget install
fi

# Service management
if command -v systemctl &> /dev/null; then
    systemctl start
elif command -v launchctl &> /dev/null; then
    launchctl start
fi
```

## Environment Variable Patterns

### Required Variables

```bash
# User directories
${HOME}              # User home directory
${XDG_CONFIG_HOME}   # Config directory
${XDG_DATA_HOME}     # Data directory
${TMPDIR}            # Temp directory

# Application-specific
${APP_DIR}           # Application install directory
${CONFIG_DIR}        # Application config directory
${DATA_DIR}          # Application data directory
```

### Fallback Patterns

```bash
# Config directory
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

# Data directory
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

# Temp directory
TEMP="${TMPDIR:-/tmp}"

# Application directory
APP="${APP_DIR:-/opt/app-name}"
```

## File Path Patterns

### ❌ Hardcoded

```python
# Python
path = "USER_CONFIG/config.yaml"
path = "APP_DIR/scripts/main.py"
```

### ✓ Dynamic

```python
# Python
import os
path = os.path.join(os.environ.get('HOME', '~'), '.config', 'app', 'config.yaml')
path = os.path.join(os.environ.get('APP_DIR', '/opt/app'), 'scripts', 'main.py')
```

### ❌ Hardcoded

```javascript
// JavaScript
const path = 'USER_CONFIG/config.json';
```

### ✓ Dynamic

```javascript
// JavaScript
const path = require('path');
const configPath = path.join(process.env.HOME || '~', '.config', 'app', 'config.json');
```

## Network Patterns

### ❌ Hardcoded

```python
# Hardcoded URLs
API_URL = "https://api.specific-service.com"
DB_HOST = "192.168.1.100"
```

### ✓ Configurable

```python
# Environment-based URLs
API_URL = os.environ.get('API_URL', 'https://api.default-service.com')
DB_HOST = os.environ.get('DB_HOST', 'localhost')
```

## Validation Checklist

- [ ] No hardcoded home directories
- [ ] No hardcoded application paths
- [ ] No hardcoded IP addresses
- [ ] No hardcoded hostnames
- [ ] Environment variables for all configurable paths
- [ ] Fallback values for environment variables
- [ ] Cross-platform command detection
- [ ] Portable file path construction

## Testing Agnostic Compliance

### Automated Check

```python
import re

HARDCODED_PATTERNS = [
    r'/home/\w+/',
    r'/root/',
    r'/opt/\w+/',
    r'~/.openclaw/',
    r'~/.hermes/',
]

def check_agnostic(filepath):
    with open(filepath) as f:
        content = f.read()
    
    issues = []
    for pattern in HARDCODED_PATTERNS:
        if re.search(pattern, content):
            issues.append(f"Hardcoded path found: {pattern}")
    
    return issues
```

### Manual Review

1. Search for `/home/` in all files
2. Search for `/opt/` in all files
3. Search for `~/.` in all files
4. Verify all paths use environment variables
5. Test on multiple platforms if possible

## Common Anti-Patterns

| Anti-Pattern | Correct Approach |
|--------------|------------------|
| `PATH="USER_HOME/bin"` | `PATH="${HOME}/bin"` |
| `CONFIG="APP_DIR/config"` | `CONFIG="${APP_DIR}/config"` |
| `LOG="TMPDIR/app.log"` | `LOG="${TMPDIR:-/tmp}/app.log"` |
| `HOST="192.168.1.1"` | `HOST="${DB_HOST:-localhost}"` |
