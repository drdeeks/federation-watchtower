#!/usr/bin/env bash
# =============================================================================
# Alias Manager - USB Compute Automation System
# Universal portable alias management with environment detection
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

ALIAS_FILE="${HOME}/.bash_aliases_usb"
ALIAS_BACKUP_DIR="${HOME}/.alias_backups"
ALIAS_EXPORT_FORMAT="table"  # table, csv, json

# Dry-run mode
DRY_RUN=false

run_or_dry() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would execute: $*"
        return 0
    fi
    "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# COLOR DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
print_header()  { echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"; }

# ... rest of alias_manager.sh content (truncated for template)
# See references/universal-portable-shell-utilities.md for complete patterns