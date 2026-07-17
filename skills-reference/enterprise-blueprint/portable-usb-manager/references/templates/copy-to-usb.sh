#!/usr/bin/env bash
# Copy File to USB Template
# Usage: bash copy-to-usb.sh <source-path> <destination-type> [custom-name]
# destination-type: freespace | persistence | custom

set -euo pipefail

SRC_FILE="${1:-}"
DEST_TYPE="${2:-freespace}"
DEST_NAME="${3:-}"

if [[ -z "$SRC_FILE" ]]; then
    echo "Usage: $0 <source-file> <freespace|persistence|custom> [dest-name]"
    exit 1
fi

if [[ ! -e "$SRC_FILE" ]]; then
    echo "Source not found: $SRC_FILE"
    exit 1
fi

# Detect USB device (assumes SELECTED_DEVICE is set or auto-detect)
if [[ -z "${SELECTED_DEVICE:-}" ]]; then
    # Auto-detect Ventoy USB
    if command -v blkid &>/dev/null; then
        SELECTED_DEVICE=$(blkid -l -t LABEL=Ventoy -o device 2>/dev/null | head -1 | sed 's/[0-9]*$//')
    fi
fi

if [[ -z "${SELECTED_DEVICE:-}" ]]; then
    echo "No USB device specified or detected. Set SELECTED_DEVICE or run from USB Setup Assistant."
    exit 1
fi

# Detect OS
if [[ "$(uname)" == "Darwin" ]]; then
    PART="${SELECTED_DEVICE}s1"
    VENTOY_MOUNT=$(df | grep "${SELECTED_DEVICE}s1" | awk '{print $NF}' || true)
else
    PART="${SELECTED_DEVICE}1"
    VENTOY_MOUNT=$(df | grep "${SELECTED_DEVICE}1" | awk '{print $NF}' || true)
fi

# Mount if needed
if [[ -z "$VENTOY_MOUNT" ]]; then
    MNT_DIR="/mnt/ventoy-copy-$$"
    mkdir -p "$MNT_DIR"
    if ! mount "$PART" "$MNT_DIR"; then
        echo "Failed to mount Ventoy partition: $PART"
        exit 1
    fi
    VENTOY_MOUNT="$MNT_DIR"
    AUTO_MOUNTED=true
else
    AUTO_MOUNTED=false
fi

# Determine destination
case "$DEST_TYPE" in
    freespace)
        DEST_BASE="$VENTOY_MOUNT"
        ;;
    persistence)
        PERSIST_FILE="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
        if [[ ! -f "$PERSIST_FILE" ]]; then
            echo "No persistence image found"
            [[ "$AUTO_MOUNTED" == "true" ]] && umount "$VENTOY_MOUNT" && rmdir "$VENTOY_MOUNT"
            exit 1
        fi
        PERSIST_MNT="/tmp/usb-persist-copy-$$"
        mkdir -p "$PERSIST_MNT"
        mount -o loop "$PERSIST_FILE" "$PERSIST_MNT"
        DEST_BASE="$PERSIST_MNT"
        ;;
    custom)
        read -p "Custom path on USB (relative to Ventoy root): " CUSTOM_PATH
        DEST_BASE="$VENTOY_MOUNT/$CUSTOM_PATH"
        ;;
    *)
        echo "Invalid destination type: $DEST_TYPE"
        [[ "$AUTO_MOUNTED" == "true" ]] && umount "$VENTOY_MOUNT" && rmdir "$VENTOY_MOUNT"
        exit 1
        ;;
esac

# Destination name
DEST_NAME="${DEST_NAME:-$(basename "$SRC_FILE")}"
DEST_PATH="$DEST_BASE/$DEST_NAME"

# Copy
echo "Copying $SRC_FILE -> $DEST_PATH"
if [[ -d "$SRC_FILE" ]]; then
    cp -r "$SRC_FILE" "$DEST_PATH" && echo "Directory copied" || echo "Copy failed"
else
    cp "$SRC_FILE" "$DEST_PATH" && echo "File copied" || echo "Copy failed"
fi

# Make scripts executable
if [[ -f "$DEST_PATH" && "$DEST_PATH" == *.sh ]]; then
    chmod +x "$DEST_PATH"
    echo "Made executable: $DEST_PATH"
fi

# Cleanup
if [[ "$DEST_TYPE" == "persistence" ]]; then
    umount "$PERSIST_MNT" 2>/dev/null || true
    rmdir "$PERSIST_MNT" 2>/dev/null || true
fi

if [[ "$AUTO_MOUNTED" == "true" ]]; then
    umount "$VENTOY_MOUNT" 2>/dev/null || true
    rmdir "$VENTOY_MOUNT" 2>/dev/null || true
fi

echo "Done"