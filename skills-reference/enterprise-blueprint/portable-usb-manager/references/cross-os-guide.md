# Cross-Platform Tool Selection System

## Overview

The unified USB skill includes an intelligent tool detection system that automatically selects the best available tool for each category based on the current platform (Linux, macOS, WSL2, Windows). This ensures optimal cross-platform experience without manual configuration.

## Tool Selection Framework

```bash
select_best_tool() {
    local tool_category="$1"
    local preferred_tools=()
    local available_tools=()
    
    case "$tool_category" in
        terminal_emulator)
            # Priority order: most featured -> basic
            preferred_tools=("gnome-terminal" "konsole" "terminator" "alacritty" "kitty" "wezterm" "xterm" "tmux" "wt.exe" "WindowsTerminal.exe")
            ;;
        virtualization)
            # Priority: native hypervisor -> cross-platform
            case "$OS" in
                Linux)
                    preferred_tools=("qemu-system-x86_64" "virt-manager" "libvirt" "virtualbox" "vmware")
                    ;;
                macOS)
                    preferred_tools=("UTM" "qemu-system-x86_64" "virtualbox" "vmware-fusion" "parallels")
                    ;;
                Windows|WSL*)
                    preferred_tools=("hyper-v" "wsl2" "virtualbox" "vmware" "qemu-system-x86_64")
                    ;;
            esac
            ;;
        container_runtime)
            preferred_tools=("docker" "podman" "nerdctl")
            ;;
        usb_imager)
            preferred_tools=("ventoy" "mkusb" "balenaetcher" "rufus" "dd")
            ;;
        network_tool)
            preferred_tools=("ssh" "tailscale" "wireguard" "socat" "ngrok" "cloudflared")
            ;;
        editor)
            preferred_tools=("code" "vim" "nano" "micro" "helix" "zed")
            ;;
    esac
    
    for tool in "${preferred_tools[@]}"; do
        if command -v "$tool" &>/dev/null || [[ -n "$(which "$tool" 2>/dev/null)" ]] || [[ -x "/Applications/${tool}.app/Contents/MacOS/${tool}" ]]; then
            available_tools+=("$tool")
        fi
    done
    
    # Return first available, or empty
    if [[ ${#available_tools[@]} -gt 0 ]]; then
        echo "${available_tools[0]}"
        return 0
    fi
    return 1
}
```

## Interactive Tool Selection

For user choice when multiple tools are available:

```bash
select_tool_interactive() {
    local tool_category="$1"
    local prompt="${2:-Select tool}"
    
    local tools=()
    case "$tool_category" in
        terminal_emulator)
            tools=("gnome-terminal" "konsole" "terminator" "alacritty" "kitty" "wezterm" "xterm" "tmux" "wt.exe" "WindowsTerminal.exe" "osascript (macOS Terminal)")
            ;;
        virtualization)
            case "$OS" in
                Linux) tools=("qemu/kvm" "virtualbox" "vmware" "libvirt/virt-manager") ;;
                macOS) tools=("UTM" "qemu" "virtualbox" "vmware-fusion" "parallels") ;;
                Windows|WSL*) tools=("hyper-v" "wsl2" "virtualbox" "vmware" "qemu") ;;
            esac
            ;;
        container_runtime)
            tools=("docker" "podman" "nerdctl")
            ;;
    esac
    
    # Filter to only available tools
    local available=()
    for tool in "${tools[@]}"; do
        local cmd="${tool%% *}"
        if command -v "$cmd" &>/dev/null || [[ "$tool" == "osascript"* ]]; then
            available+=("$tool")
        fi
    done
    
    if [[ ${#available[@]} -eq 0 ]]; then
        print_error "No supported $tool_category tools found"
        return 1
    fi
    
    echo ""
    print_header "Available $tool_category Tools"
    for i in "${!available[@]}"; do
        echo "  $((i+1))) ${available[$i]}"
    done
    echo "  a) Auto-select best"
    echo ""
    
    local choice
    read -p "$(echo -e "${YELLOW}$prompt [1-${#available[@]}/a]: ${NC}")" choice
    
    if [[ "$choice" == "a" ]]; then
        echo "${available[0]}"
        return 0
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#available[@]}" ]]; then
        echo "${available[$((choice-1))]}"
        return 0
    else
        print_error "Invalid selection"
        return 1
    fi
}
```

## OS Detection with WSL2 Support

```bash
# Check OS with WSL detection
if [[ "$(uname)" == "Darwin" ]]; then
    OS="macOS"
elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
    # Check for WSL
    if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        OS="WSL"
        WSL_VERSION="${WSL_VERSION:-2}"
        print_info "Windows Subsystem for Linux detected (WSL $WSL_VERSION)"
    else
        OS="Linux"
    fi
elif [[ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]] || [[ "$(expr substr $(uname -s) 1 10)" == "MINGW64_NT" ]]; then
    OS="Windows"
else
    print_error "Unsupported operating system: $(uname)"
    print_info "Supported: macOS, Linux, WSL2, Windows (via WSL2)"
    return 1
fi
```

## Platform-Specific Optimizations

### WSL2-Specific Optimizations

- **USB passthrough**: Use `usbipd` on Windows host + `wsld` in WSL2
- **Systemd support**: WSL2 with `systemd=true` in `/etc/wsl.conf`
- **Ventoy access**: Mount via `/mnt/c/...` paths or usbipd
- **Docker**: Native Docker Engine in WSL2 (no Docker Desktop needed)

```bash
# WSL2 USB passthrough setup (run on Windows host)
usbipd list
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>

# In WSL2
sudo usbipd attach --remote <WINDOWS_HOST_IP> --busid <BUSID>
```

### Platform Capability Matrix

| Platform | Boot | Persistence | VM Access | Notes |
|---|---|---|---|---|
| Linux Host | Yes | Yes | Yes (QEMU/KVM) | Full support, native tools |
| Windows Host | Yes | Yes | Yes (QEMU) | Use Ext2Fsd for ext4 access |
| macOS Host | Yes | Yes | Yes (UTM/VMware) | Use macFUSE for ext4 access |
| WSL2 | Yes | Yes | Yes (QEMU) | Best Windows experience — full Linux kernel, systemd support |
| Any PC (UEFI) | Yes | Yes | N/A | Boot from USB directly |
| Any PC (BIOS) | Yes | Yes | N/A | Legacy boot support |

### Terminal Emulator Priority

| Platform | 1st Choice | 2nd Choice | 3rd Choice | Fallback |
|---|---|---|---|---|
| Linux | gnome-terminal | konsole | terminator | xterm |
| macOS | Terminal.app (osascript) | iTerm2 | Alacritty | xterm |
| WSL2 | Windows Terminal (wt.exe) | wsl.exe | Alacritty | xterm |
| Windows | Windows Terminal | cmd.exe | PowerShell | - |

### Virtualization Priority

| Platform | 1st Choice | 2nd Choice | 3rd Choice |
|---|---|---|---|
| Linux | QEMU/KVM | VirtualBox | VMware |
| macOS | UTM | VMware Fusion | Parallels |
| WSL2 | Hyper-V | WSL2 nested | VirtualBox |

## Usage in USB Setup Assistant

The tool selection is automatically invoked during initialization:

```bash
initialize() {
    # ... OS detection ...
    
    # Detect best tools for this platform
    TERMINAL_TOOL="$(select_best_tool terminal_emulator)"
    VIRT_TOOL="$(select_best_tool virtualization)"
    CONTAINER_TOOL="$(select_best_tool container_runtime)"
    
    print_info "Best terminal: ${TERMINAL_TOOL:-none found}"
    print_info "Best virtualization: ${VIRT_TOOL:-none found}"
    print_info "Best container runtime: ${CONTAINER_TOOL:-none found}"
}
```

## Interactive Override

Users can override auto-selection via interactive menu:

```bash
# In Hemlock launch menu (Option 13)
echo "  1) Launch TUI in NEW terminal window (recommended)"
echo "  2) Launch TUI in CURRENT terminal"
# Auto-detects best terminal, or user can choose specific one
```

## Error Handling

| Error | Response |
|-------|----------|
| No tools found in category | Show error, suggest installation commands |
| Command not found at runtime | Fall back to next available tool |
| Platform not supported | Clear error with supported platforms list |

## Testing Tool Detection

```bash
# Test tool detection
bash -c 'source usb-setup-assistant.sh; select_best_tool terminal_emulator'
bash -c 'source usb-setup-assistant.sh; select_best_tool virtualization'
bash -c 'source usb-setup-assistant.sh; select_best_tool container_runtime'

# List available tools interactively
bash -c 'source usb-setup-assistant.sh; select_tool_interactive terminal_emulator "Choose terminal"'
```