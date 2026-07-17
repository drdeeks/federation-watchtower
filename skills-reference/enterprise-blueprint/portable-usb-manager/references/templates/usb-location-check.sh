#!/usr/bin/env bash
# USB Location Safety Check Template
# Include this at the top of any USB management script

check_script_location() {
    # Check if script is running from a USB-mounted path
    local script_path="$(realpath "${BASH_SOURCE[0]}")"
    
    # Common USB mount points (cross-platform)
    local usb_paths=(
        "/media/*/Ventoy"
        "/mnt/ventoy"
        "/Volumes/Ventoy"
        "/run/media/*/Ventoy"
        "/media/*/usb*"
        "/mnt/usb*"
        # Windows/WSL paths
        "/mnt/c/*/Ventoy"
        "/mnt/d/*/Ventoy"
        "/mnt/e/*/Ventoy"
    )
    
    for pattern in "${usb_paths[@]}"; do
        for path in $pattern; do
            if [[ -d "$path" ]] && [[ "$script_path" == "$path"* ]]; then
                local RED='\033[0;31m'
                local NC='\033[0m'
                echo -e "${RED}================================================================="
                echo -e "  WARNING: SCRIPT RUNNING FROM USB DRIVE!"
                echo -e "================================================================="
                echo -e ""
                echo -e "  This script MUST run from the HOST system, not from the USB drive."
                echo -e ""
                echo -e "  Current location: $script_path"
                echo -e "  Detected USB path: $path"
                echo -e ""
                echo -e "  REQUIRED ACTION:"
                echo -e "  1. Copy this script to your host system:"
                echo -e "     cp \"$script_path\" ~/$(basename \"$script_path\")"
                echo -e "  2. Run it from the host:"
                echo -e "     sudo bash ~/$(basename \"$script_path\")"
                echo -e ""
                echo -e "  WHY? Operations like Ventoy installation, persistence formatting, "
                echo -e "  debootstrap, and chroot REQUIRE host privileges and will FAIL or "
                echo -e "  CORRUPT the USB if run from within the USB environment."
                echo -e ""
                echo -e "================================================================="
                echo -e "${NC}"
                
                # Simple confirm replacement for standalone use
                read -p "Continue anyway? (NOT RECOMMENDED) [y/N]: " response
                case "$response" in
                    [yY][eE][sS]|[yY]) 
                        return 0
                        ;;
                    *)
                        exit 1
                        ;;
                esac
            fi
        done
    done
}