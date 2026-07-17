#!/bin/bash
# =============================================================================
# fetch-ventoy.sh — obtain the Ventoy Linux release tarball on demand
# =============================================================================
# The skill does NOT bundle the ~20MB Ventoy binary tarball. Everything needed
# to produce a bootable USB ships in the skill; the Ventoy release itself is
# fetched on demand into the location the setup assistant expects
# (usb/volumes/ventoy/). Run this once (online) before building a USB offline.
#
# Path-agnostic: the default destination is resolved RELATIVE to this script's
# own location, so the skill works wherever it is installed. Override with
# --dest. No hardcoded absolute paths.
#
# Usage:
#   scripts/fetch-ventoy.sh                 # fetch default version to default dest
#   scripts/fetch-ventoy.sh --version 1.0.99
#   scripts/fetch-ventoy.sh --dest /path/to/volumes/ventoy
#   scripts/fetch-ventoy.sh --force         # re-download even if present
#   scripts/fetch-ventoy.sh --dry-run       # print the plan, fetch nothing
#   scripts/fetch-ventoy.sh --help
# =============================================================================
set -uo pipefail

VENTOY_VERSION="${VENTOY_VERSION:-1.0.99}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default dest: the volumes/ventoy dir the setup assistant reads from.
DEFAULT_DEST="$SCRIPT_DIR/../references/templates/usb-system/usb/volumes/ventoy"
DEST=""
FORCE=0
DRY_RUN=0

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -30; }

emit() {  # structured result line (matches skill convention)
    printf '{"operation":"fetch_ventoy","status":"%s","version":"%s","dest":"%s","cost":{"tier":0,"amount_usd":0.0,"service":"local"}}\n' \
        "$1" "$VENTOY_VERSION" "${2:-}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        --version)    VENTOY_VERSION="$2"; shift 2 ;;
        --dest)       DEST="$2"; shift 2 ;;
        --force)      FORCE=1; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        *) echo "unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

DEST="${DEST:-$DEFAULT_DEST}"
TARBALL="$DEST/ventoy-${VENTOY_VERSION}-linux.tar.gz"
URL="https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz"

echo "[fetch-ventoy] version : $VENTOY_VERSION"
echo "[fetch-ventoy] dest    : $DEST"
echo "[fetch-ventoy] url     : $URL"

if [[ -f "$TARBALL" && "$FORCE" -ne 1 ]]; then
    echo "[fetch-ventoy] already present: $TARBALL (use --force to re-download)"
    emit "present" "$TARBALL"
    exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[fetch-ventoy] DRY-RUN: would create $DEST and download the tarball"
    emit "dry_run" "$TARBALL"
    exit 0
fi

mkdir -p "$DEST" || { echo "[fetch-ventoy] cannot create $DEST" >&2; emit "failed" "$DEST"; exit 1; }

# Prefer curl, fall back to wget.
if command -v curl >/dev/null 2>&1; then
    curl -fSL -o "$TARBALL" "$URL" || { echo "[fetch-ventoy] download failed (offline?)" >&2; emit "failed" "$TARBALL"; exit 1; }
elif command -v wget >/dev/null 2>&1; then
    wget -O "$TARBALL" "$URL" || { echo "[fetch-ventoy] download failed (offline?)" >&2; emit "failed" "$TARBALL"; exit 1; }
else
    echo "[fetch-ventoy] neither curl nor wget available" >&2; emit "failed" "$TARBALL"; exit 1
fi

# Sanity: it must be a gzip tarball, not an HTML error page.
if ! tar -tzf "$TARBALL" >/dev/null 2>&1; then
    echo "[fetch-ventoy] downloaded file is not a valid tar.gz — removing" >&2
    rm -f "$TARBALL"
    emit "failed" "$TARBALL"
    exit 1
fi

echo "[fetch-ventoy] OK: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
emit "fetched" "$TARBALL"
exit 0
