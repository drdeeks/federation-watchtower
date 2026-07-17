#!/usr/bin/env python3
"""
Portable Linux USB Setup Script

Creates a bootable Ubuntu USB with Ventoy, persistence, and optional agent isolation.

Usage:
    python3 setup.py --device /dev/sdX --iso ~/Downloads/ubuntu-24.04.4-desktop-amd64.iso
    python3 setup.py --device /dev/sdX --iso ~/Downloads/ubuntu-24.04.4-desktop-amd64.iso --persistence 20G
    python3 setup.py --device /dev/sdX --iso ~/Downloads/ubuntu-24.04.4-desktop-amd64.iso --agents alpha,beta,gamma
    python3 setup.py --device /dev/sdX --iso ~/Downloads/ubuntu-24.04.4-desktop-amd64.iso --global-deps 10G
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


def run_command(cmd, check=True, capture=False):
    """Run a shell command with error handling."""
    try:
        result = subprocess.run(
            cmd, shell=True, check=check, capture_output=capture, text=True
        )
        return result
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {cmd}")
        print(f"Error: {e.stderr if capture else str(e)}")
        if check:
            sys.exit(1)
        return None


def check_prerequisites():
    """Check if required tools are installed."""
    required_tools = ['dd', 'mkfs.vfat', 'mkfs.ext4', 'parted', 'wget']
    missing = []
    
    for tool in required_tools:
        if run_command(f"which {tool}", check=False).returncode != 0:
            missing.append(tool)
    
    if missing:
        print(f"Missing required tools: {', '.join(missing)}")
        print("Install them with: sudo apt install " + " ".join(missing))
        sys.exit(1)


def detect_ventoy():
    """Check if Ventoy is installed and find its location."""
    ventoy_paths = [
        "/opt/ventoy",
        "/tmp/ventoy-1.1.12",
        os.path.expanduser("~/ventoy")
    ]
    
    for path in ventoy_paths:
        if os.path.exists(os.path.join(path, "Ventoy2Disk.sh")):
            return path
    
    # Try to download Ventoy
    print("Ventoy not found. Downloading...")
    run_command("wget -P /tmp https://github.com/ventoy/Ventoy/releases/download/v1.1.12/ventoy-1.1.12-linux.tar.gz")
    run_command("tar -xf /tmp/ventoy-1.1.12-linux.tar.gz -C /tmp")
    
    return "/tmp/ventoy-1.1.12"


def get_usb_info(device):
    """Get USB device information."""
    result = run_command(f"lsblk -f {device}", capture=True)
    if result and result.returncode == 0:
        print(f"\nUSB Device Information:")
        print(result.stdout)
        return True
    return False


def confirm_action(message):
    """Get user confirmation."""
    response = input(f"\n{message} (y/N): ").strip().lower()
    return response in ['y', 'yes']


def backup_existing(device):
    """Backup existing USB data if requested."""
    if confirm_action("Backup existing USB data before proceeding?"):
        backup_path = f"~/usb-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}.img"
        print(f"Creating backup: {backup_path}")
        run_command(f"sudo dd if={device} of={backup_path} bs=4M status=progress")
        print(f"Backup complete: {backup_path}")


def install_ventoy(device, ventoy_path):
    """Install Ventoy on the USB device."""
    print("\n=== Installing Ventoy ===")
    
    # Check for exfat support
    result = run_command("dpkg -l | grep exfat", capture=True)
    if not result or "exfatprogs" not in result.stdout:
        print("Installing exfat support...")
        run_command("sudo apt install exfatprogs exfat-fuse -y")
    
    # Fix mkexfatfs symlink if needed
    if run_command("which mkexfatfs", check=False).returncode != 0:
        print("Creating mkexfatfs symlink...")
        run_command("sudo ln -s /usr/sbin/mkfs.exfat /usr/sbin/mkexfatfs")
    
    # Copy Ventoy tools to PATH
    print("Setting up Ventoy tools...")
    run_command(f"sudo cp {ventoy_path}/tool/x86_64/* /usr/sbin/")
    
    # Install Ventoy
    print("Installing Ventoy to USB...")
    run_command(f"cd {ventoy_path} && sudo ./Ventoy2Disk.sh -iI {device}")
    
    print("Ventoy installation complete!")


def mount_usb(device, mount_point=None):
    """Mount the Ventoy partition (mount point resolved at runtime)."""
    if mount_point is None:
        user = os.environ.get("USER") or os.environ.get("USERNAME") or "root"
        mount_point = os.environ.get("USB_MOUNT", f"/media/{user}/Ventoy")
    run_command(f"sudo mkdir -p {mount_point}")
    run_command(f"sudo mount {device}1 {mount_point}")
    return mount_point


def copy_iso(mount_point, iso_path):
    """Copy ISO file to USB."""
    print(f"\nCopying ISO: {iso_path}")
    run_command(f"sudo cp {iso_path} {mount_point}/")
    
    iso_name = os.path.basename(iso_path)
    print(f"ISO copied: {iso_name}")
    return iso_name


def create_persistence(mount_point, size_gb, iso_name):
    """Create persistence file."""
    print(f"\nCreating persistence file ({size_gb}GB)...")
    
    size_mb = int(size_gb) * 1024
    persist_dir = f"{mount_point}/persistence"
    persist_file = f"{persist_dir}/ubuntu-persistence.dat"
    
    run_command(f"sudo mkdir -p {persist_dir}")
    run_command(f"sudo dd if=/dev/zero of={persist_file} bs=1M count={size_mb} status=progress")
    run_command(f"sudo mkfs.ext4 -F -L casper-rw {persist_file}")
    
    print("Persistence file created!")
    return persist_file


def create_global_deps(mount_point, size_gb):
    """Create global read-only dependencies partition."""
    print(f"\nCreating global dependencies partition ({size_gb}GB)...")
    
    size_mb = int(size_gb) * 1024
    deps_file = f"{mount_point}/global-deps.dat"
    
    run_command(f"sudo dd if=/dev/zero of={deps_file} bs=1M count={size_mb} status=progress")
    run_command(f"sudo mkfs.ext4 -F -L global-deps {deps_file}")
    
    # Mount and populate
    print("Populating global dependencies...")
    run_command(f"sudo mkdir -p /tmp/global-deps")
    run_command(f"sudo mount -o loop {deps_file} /tmp/global-deps")
    
    # Copy common libraries
    run_command("sudo rsync -av /usr/lib/ /tmp/global-deps/usr/lib/ 2>/dev/null || true")
    run_command("sudo rsync -av /usr/share/ /tmp/global-deps/usr/share/ 2>/dev/null || true")
    
    run_command("sudo umount /tmp/global-deps")
    run_command("sudo tune2fs -O ro {deps_file}")
    
    print("Global dependencies partition created!")
    return deps_file


def create_agent_workspaces(mount_point, agents, size_gb):
    """Create isolated agent workspaces."""
    print(f"\nCreating agent workspaces: {', '.join(agents)}")
    
    agents_dir = f"{mount_point}/agents"
    run_command(f"sudo mkdir -p {agents_dir}")
    
    agent_configs = {}
    size_mb = int(size_gb) * 1024
    
    for agent in agents:
        print(f"  Creating workspace for agent: {agent}")
        
        agent_file = f"{agents_dir}/{agent}-home.dat"
        
        # Create agent storage
        run_command(f"sudo dd if=/dev/zero of={agent_file} bs=1M count={size_mb} status=progress")
        run_command(f"sudo mkfs.ext4 -F -L {agent}-home {agent_file}")
        
        # Initialize agent home
        run_command(f"sudo mkdir -p /tmp/agent-init")
        run_command(f"sudo mount -o loop {agent_file} /tmp/agent-init")
        
        # Create directory structure
        run_command("sudo mkdir -p /tmp/agent-init/{bin,lib,share,workspace,config,cache}")
        
        # Create agent info file
        agent_info = {
            "name": agent,
            "created": datetime.now().isoformat(),
            "version": "1.0",
            "isolation_level": "L2",
            "storage_size": f"{size_gb}G"
        }
        
        run_command(f"sudo tee /tmp/agent-init/agent-info.json > /dev/null << 'EOF'\n{json.dumps(agent_info, indent=2)}\nEOF")
        
        run_command("sudo chown -R 1000:1000 /tmp/agent-init")
        run_command("sudo umount /tmp/agent-init")
        
        agent_configs[agent] = {
            "backend": f"/agents/{agent}-home.dat",
            "description": f"Isolated workspace for agent {agent}",
            "storage_size": f"{size_gb}G"
        }
    
    print(f"Agent workspaces created: {len(agents)} agents")
    return agent_configs


def configure_ventoy(mount_point, iso_name, persistence_file, agent_configs=None):
    """Create Ventoy configuration file."""
    print("\nConfiguring Ventoy...")
    
    config = {
        "persistence": [
            {
                "image": f"/{iso_name}",
                "backend": persistence_file.replace(mount_point, "")
            }
        ]
    }
    
    if agent_configs:
        config["agent_isolation"] = agent_configs
    
    config_dir = f"{mount_point}/ventoy"
    run_command(f"sudo mkdir -p {config_dir}")
    
    # Write config file
    config_json = json.dumps(config, indent=4)
    run_command(f"sudo tee {config_dir}/ventoy.json > /dev/null << 'EOF'\n{config_json}\nEOF")
    
    print("Ventoy configuration complete!")
    return config


def setup_aliases():
    """Set up USB management aliases."""
    print("\nSetting up aliases...")
    
    alias_script = """# USB Management Aliases
alias usb-list='lsblk -f /dev/sd*'
alias usb-mount='sudo mount /dev/sdX1 "${USB_MOUNT:-/run/media/$USER/USB}"'
alias usb-unmount='sudo umount /dev/sdX*'
alias usb-iso-list='ls -lh "${USB_MOUNT:-/run/media/$USER/USB}"/*.iso 2>/dev/null'
alias usb-vm-boot='sudo qemu-system-x86_64 -m 4G -drive file=/dev/sdX,format=raw -boot c -display gtk'
alias usb-backup='sudo dd if=/dev/sdX of=~/usb-backup-$(date +%Y%m%d).img bs=4M status=progress'
"""
    
    print("Add these aliases to ~/.bashrc:")
    print(alias_script)


def verify_setup(mount_point, iso_name):
    """Verify the USB setup."""
    print("\n=== Verifying Setup ===")
    
    # Check ISO exists
    iso_path = f"{mount_point}/{iso_name}"
    if os.path.exists(iso_path):
        print(f"✓ ISO file: {iso_name}")
    else:
        print(f"✗ ISO file missing: {iso_name}")
    
    # Check persistence
    persist_file = f"{mount_point}/persistence/ubuntu-persistence.dat"
    if os.path.exists(persist_file):
        print("✓ Persistence file created")
    else:
        print("✗ Persistence file missing")
    
    # Check Ventoy config
    config_file = f"{mount_point}/ventoy/ventoy.json"
    if os.path.exists(config_file):
        print("✓ Ventoy configuration created")
    else:
        print("✗ Ventoy configuration missing")
    
    # Check agents
    agents_dir = f"{mount_point}/agents"
    if os.path.exists(agents_dir):
        agent_files = [f for f in os.listdir(agents_dir) if f.endswith('-home.dat')]
        print(f"✓ Agent workspaces: {len(agent_files)} agents")
    else:
        print("- No agent workspaces created")
    
    print("\n=== Setup Complete ===")


def main():
    parser = argparse.ArgumentParser(
        description="Create a portable Linux USB with Ventoy and persistence"
    )
    
    parser.add_argument(
        "--device", "-d",
        required=True,
        help="USB device (e.g., /dev/sdb)"
    )
    
    parser.add_argument(
        "--iso", "-i",
        required=True,
        help="Path to ISO file"
    )
    
    parser.add_argument(
        "--persistence", "-p",
        default="20G",
        help="Persistence size (default: 20G)"
    )
    
    parser.add_argument(
        "--agents", "-a",
        help="Comma-separated list of agent names to create"
    )
    
    parser.add_argument(
        "--agent-size",
        default="5G",
        help="Size per agent workspace (default: 5G)"
    )
    
    parser.add_argument(
        "--global-deps",
        help="Size for global dependencies partition (e.g., 10G)"
    )
    
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Skip backup prompt"
    )
    
    parser.add_argument(
        "--mount-point",
        default=os.environ.get("USB_MOUNT"),
        help="Mount point for USB (default: $USB_MOUNT, else resolved at runtime)"
    )
    
    args = parser.parse_args()
    
    # Validate ISO exists
    if not os.path.exists(args.iso):
        print(f"Error: ISO file not found: {args.iso}")
        sys.exit(1)
    
    # Check prerequisites
    print("=== Portable Linux USB Setup ===")
    print(f"Device: {args.device}")
    print(f"ISO: {args.iso}")
    print(f"Persistence: {args.persistence}")
    
    if args.agents:
        agents = [a.strip() for a in args.agents.split(",")]
        print(f"Agents: {', '.join(agents)}")
    
    if args.global_deps:
        print(f"Global Dependencies: {args.global_deps}")
    
    # Get USB info
    if not get_usb_info(args.device):
        print(f"Error: Could not read device {args.device}")
        sys.exit(1)
    
    # Confirm action
    if not confirm_action(f"This will wipe ALL data on {args.device}. Continue?"):
        print("Aborted.")
        sys.exit(0)
    
    # Backup if requested
    if not args.no_backup:
        backup_existing(args.device)
    
    # Detect Ventoy
    ventoy_path = detect_ventoy()
    
    # Install Ventoy
    install_ventoy(args.device, ventoy_path)
    
    # Mount USB
    mount_point = mount_usb(args.device, args.mount_point)
    
    # Copy ISO
    iso_name = copy_iso(mount_point, args.iso)
    
    # Create persistence
    persist_size = int(args.persistence.replace("G", ""))
    persistence_file = create_persistence(mount_point, persist_size, iso_name)
    
    # Create global dependencies if requested
    if args.global_deps:
        deps_size = int(args.global_deps.replace("G", ""))
        create_global_deps(mount_point, deps_size)
    
    # Create agent workspaces if requested
    agent_configs = None
    if args.agents:
        agent_size = int(args.agent_size.replace("G", ""))
        agent_configs = create_agent_workspaces(mount_point, agents, agent_size)
    
    # Configure Ventoy
    configure_ventoy(mount_point, iso_name, persistence_file, agent_configs)
    
    # Verify setup
    verify_setup(mount_point, iso_name)
    
    # Setup aliases
    setup_aliases()
    
    # Unmount
    run_command(f"sudo umount {mount_point}")
    
    print("\n=== USB Ready! ===")
    print("Insert USB and boot from it to use your portable Linux environment.")
    print("For VM access, use: sudo qemu-system-x86_64 -m 4G -drive file=/dev/sdX,format=raw -boot c -display gtk")


if __name__ == "__main__":
    main()
