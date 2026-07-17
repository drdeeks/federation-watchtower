# Security & Gitignore Standards

## Table of Contents

- [Overview](#overview)
- [Gitignore Patterns](#gitignore-patterns)
- [Permission Standards](#permission-standards)
- [Secrets Management](#secrets-management)
- [Supply Chain Security](#supply-chain-security)
- [Audit & Compliance](#audit--compliance)

## Overview

Enterprise security standards for agent workspaces. These standards are non-negotiable and enforced automatically via `security_hardening.py`.

## Gitignore Patterns

### Mandatory Patterns (All Workspaces)

```gitignore
# Secrets & Credentials (NEVER commit)
.secrets/
*.key
*.pem
*.p12
*.pfx
*.jks
*.keystore
.env
.env.*
!.env.example
*.secret
*.credential
*_rsa
*_dsa
*_ecdsa
*_ed25519

# API Keys & Tokens
*API_KEY*
*API_SECRET*
*TOKEN*
*BEARER*
*AUTH*
*.webhook

# Wallets & Blockchain
*.wallet
*.keystore
*private*key*
*mnemonic*
*seed*
utxo*
*.dat

# Database & Local Data
*.db
*.sqlite
*.sqlite3
*.db-journal
data/local/
*.log
logs/*.log

# Build & Cache
__pycache__/
*.py[cod]
*$py.class
.pytest_cache/
.coverage
.mypy_cache/
.tox/
dist/
build/
*.egg-info/

# IDE & Editor
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store
Thumbs.db

# OS & Temporary
tmp/
temp/
*.tmp
*.temp

# Large Files & Binaries
*.bin
*.iso
*.img
*.vmdk
*.qcow2
*.vdi
*.ova

# Node.js
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-store/

# Python
pip-log.txt
pip-delete-this-directory.txt
*.egg
.eggs/

# Docker
.docker/
docker-compose.override.yml

# Agent Specific
agents/*/tmp/
agents/*/cache/
agents/*/sessions/*.json
skills/*/scripts/__pycache__/
```

### Dangerous Overrides (NEVER allowed)

```gitignore
# THESE ARE FORBIDDEN - they expose secrets
!.secrets/
!*.key
!*.pem
!.env
!*API_KEY*
!*TOKEN*
```

## Permission Standards

### Directory Permissions

| Path | Permission | Rationale |
|------|------------|-----------|
| `.secrets/` | `700` | Only owner can access credentials |
| `config/` | `750` | Group readable for agents |
| `data/` | `750` | Persistent data, group access |
| `logs/` | `755` | Logs readable by all agents |
| `backups/` | `700` | Backups may contain secrets |
| `scripts/` | `755` | Executable scripts |
| `references/` | `644` | Documentation |
| `agents/*/` | `750` | Agent workspaces |

### File Permissions

| Type | Permission | Examples |
|------|------------|----------|
| Scripts | `755` | `*.py`, `*.sh` |
| Config | `640` | `*.yaml`, `*.json`, `*.toml` |
| Secrets | `600` | `*.key`, `*.pem`, `.env` |
| Docs | `644` | `*.md`, `*.txt` |
| Data | `640` | `*.db`, `*.sqlite` |
| Logs | `644` | `*.log` |

### Verification

```bash
# Check all permissions
python3 scripts/security_hardening.py --workspace /path --check-only

# Auto-fix permissions
python3 scripts/security_hardening.py --workspace /path --fix
```

## Secrets Management

### .secrets/ Structure

```
.secrets/
├── hermes/              # Hermes agent credentials
│   ├── config.yaml      # Encrypted or restricted
│   └── api-keys/        # API keys per service
├── titan/               # Titan trading credentials
│   ├── exchange-keys/   # Exchange API keys
│   └── wallet/          # Trading wallet
├── avery/               # Avery creative credentials
│   └── api-keys/        # Generation API keys
├── allman/              # Allman onchain credentials
│   ├── wallet/          # Private keys (encrypted)
│   ├── pinata/          # Pinata JWT
│   └── erc8004/         # Registration data
└── shared/              # Shared infrastructure
    ├── github/          # GH_TOKEN
    ├── docker/          # Registry credentials
    └── monitoring/      # Monitoring tokens
```

### Secret Rotation Protocol

1. **Detect exposure** - `security_hardening.py` scans for patterns
2. **Immediate rotation** - Rotate compromised credentials
3. **Audit git history** - Check for historical exposure
4. **Update .secrets/** - Deploy new credentials
5. **Verify** - Run full security scan

### Environment Variables (Never in files)

```bash
# Set at runtime, never in config files
export HERMES_CONFIG="/path/to/.secrets/hermes/config.yaml"
export TITAN_EXCHANGE_KEY="$(cat /path/to/.secrets/titan/exchange-keys/binance)"
export ALLMAN_PINATA_JWT="$(cat /path/to/.secrets/allman/pinata/jwt)"
```

## Supply Chain Security

### Dependency Verification

```bash
# Python - verify hashes
pip install --require-hashes -r requirements.txt

# Node.js - audit
npm audit
npm audit fix

# Docker - scan images
docker scan image-name
```

### CI/CD Security Gates

```yaml
# .github/workflows/security.yml
- name: Security Scan
  run: |
    python3 scripts/security_hardening.py --workspace . --check-only
    python3 scripts/placeholder_scanner.py --workspace . --fail-on-found
    python3 scripts/validate_structure.py --workspace . --role hermes
```

### Prohibited Dependencies

- Packages with known CVEs (high/critical)
- Unmaintained packages (>2 years no updates)
- Packages without signed releases
- Typosquatting candidates

## Audit & Compliance

### Automated Checks (Run on Every Operation)

| Check | Tool | Frequency |
|-------|------|-----------|
| Gitignore compliance | `security_hardening.py` | Every operation |
| Permission audit | `security_hardening.py` | Every operation |
| Secrets exposure scan | `security_hardening.py` | Every operation |
| Placeholder scan | `placeholder_scanner.py` | Every operation |
| Structure validation | `validate_structure.py` | Every operation |

### Manual Audit (Quarterly)

1. **Full secrets rotation**
2. **Dependency audit** - `npm audit`, `pip-audit`, `cargo audit`
3. **Git history scan** - `git log --all --full-history -- "**/*.key" "**/*.pem" ".env*"`
4. **Permission review** - `find . -type f -perm /o=w`
5. **Access review** - Audit `.secrets/` access logs

### Compliance Evidence

All validation produces JSON output for compliance evidence:

```bash
python3 scripts/security_hardening.py --workspace . --json > logs/security-audit-$(date +%Y%m%d).json
python3 scripts/placeholder_scanner.py --workspace . --json > logs/placeholder-scan-$(date +%Y%m%d).json
python3 scripts/validate_structure.py --workspace . --json > logs/structure-validation-$(date +%Y%m%d).json
```

### Incident Response

If secrets exposed:

1. **Immediate** - Rotate all exposed credentials
2. **Within 1 hour** - Force push cleaned history (if recent)
3. **Within 4 hours** - Notify affected services
4. **Within 24 hours** - Complete audit report
5. **Within 1 week** - Process improvement implementation

## Required Environment Variables

```bash
# Per role - set in shell/profile, never in files
HERMES_CONFIG="/workspace/.secrets/hermes/config.yaml"
TITAN_STRATEGIES="/workspace/titan/strategies"
TITAN_EXCHANGE_KEYS="/workspace/.secrets/titan/exchange-keys"
AVERY_MEDIA="/workspace/avery/media"
ALLMAN_WALLETS="/workspace/.secrets/allman/wallet"
ALLMAN_PINATA="/workspace/.secrets/allman/pinata"
GITHUB_TOKEN="$(cat /workspace/.secrets/shared/github/token)"
```

## Quick Reference

```bash
# Full security check
python3 scripts/security_hardening.py --workspace . --check-only --json

# Fix all fixable issues
python3 scripts/security_hardening.py --workspace . --fix

# Scan for placeholders (zero-tolerance)
python3 scripts/placeholder_scanner.py --workspace . --fail-on-found

# Validate structure
python3 scripts/validate_structure.py --workspace . --role hermes

# Self-validation with rollback test
python3 scripts/self_validator.py --workspace . --verify-rollback
```