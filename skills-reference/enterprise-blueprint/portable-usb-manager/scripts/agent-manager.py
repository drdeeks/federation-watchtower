#!/usr/bin/env python3
"""
Agent Manager Script

Manages isolated agent workspaces on portable Linux USB drives.

Usage:
    python3 agent-manager.py create --name alpha --size 5G --usb /dev/sdX
    python3 agent-manager.py list --usb /dev/sdX
    python3 agent-manager.py enter --name alpha
    python3 agent-manager.py backup --name alpha --dest ~/backups/
    python3 agent-manager.py restore --name alpha --src ~/backups/alpha-backup.tar.gz
    python3 agent-manager.py delete --name alpha --usb /dev/sdX
    python3 agent-manager.py health --name alpha
    python3 agent-manager.py clone --source alpha --dest beta --usb /dev/sdX
"""

import argparse
import json
import os
import subprocess
import sys
import tarfile
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


def get_usb_mount():
    """Get current USB mount point."""
    result = run_command("mount | grep ventoy", capture=True)
    if result and result.stdout:
        # Parse mount output to find mount point
        for line in result.stdout.strip().split("\n"):
            if "ventoy" in line:
                parts = line.split()
                if len(parts) >= 3:
                    return parts[2]
    # Not currently mounted — fall back to a per-user mountpoint, overridable
    # via $USB_MOUNT. Never assume a fixed, machine-specific mount path.
    user = os.environ.get("USER") or os.environ.get("USERNAME") or "root"
    return os.environ.get("USB_MOUNT", f"/media/{user}/Ventoy")


def get_agents_dir(usb_mount):
    """Get agents directory path."""
    return os.path.join(usb_mount, "agents")


def list_agents(usb_mount):
    """List all agents on the USB."""
    agents_dir = get_agents_dir(usb_mount)
    
    if not os.path.exists(agents_dir):
        print("No agents directory found on USB.")
        return []
    
    agents = []
    for file in os.listdir(agents_dir):
        if file.endswith("-home.dat"):
            agent_name = file.replace("-home.dat", "")
            agents.append(agent_name)
    
    return agents


def get_agent_info(usb_mount, agent_name):
    """Get agent information."""
    agents_dir = get_agents_dir(usb_mount)
    agent_file = os.path.join(agents_dir, f"{agent_name}-home.dat")
    
    if not os.path.exists(agent_file):
        return None
    
    # Mount and read info
    mount_point = "/tmp/agent-info-mount"
    run_command(f"sudo mkdir -p {mount_point}")
    run_command(f"sudo mount -o loop {agent_file} {mount_point}")
    
    info_file = os.path.join(mount_point, "agent-info.json")
    info = None
    
    if os.path.exists(info_file):
        with open(info_file, 'r') as f:
            info = json.load(f)
    
    run_command(f"sudo umount {mount_point}")
    
    # Get file size
    size_result = run_command(f"du -h {agent_file}", capture=True)
    size = size_result.stdout.split()[0] if size_result else "Unknown"
    
    return {
        "name": agent_name,
        "file": agent_file,
        "size": size,
        "info": info
    }


def create_agent(args):
    """Create a new agent workspace."""
    usb_mount = get_usb_mount()
    agents_dir = get_agents_dir(usb_mount)
    agent_file = os.path.join(agents_dir, f"{args.name}-home.dat")
    
    # Check if agent already exists
    if os.path.exists(agent_file):
        print(f"Error: Agent '{args.name}' already exists.")
        sys.exit(1)
    
    print(f"Creating agent workspace: {args.name}")
    
    # Create agents directory if it doesn't exist
    run_command(f"sudo mkdir -p {agents_dir}")
    
    # Parse size
    size_gb = int(args.size.replace("G", ""))
    size_mb = size_gb * 1024
    
    # Create agent storage
    print(f"Creating {size_gb}GB storage...")
    run_command(f"sudo dd if=/dev/zero of={agent_file} bs=1M count={size_mb} status=progress")
    run_command(f"sudo mkfs.ext4 -F -L {args.name}-home {agent_file}")
    
    # Initialize agent home
    print("Initializing workspace...")
    mount_point = "/tmp/agent-init"
    run_command(f"sudo mkdir -p {mount_point}")
    run_command(f"sudo mount -o loop {agent_file} {mount_point}")
    
    # Create directory structure
    directories = ["bin", "lib", "share", "workspace", "config", "cache", "logs"]
    for dir_name in directories:
        run_command(f"sudo mkdir -p {os.path.join(mount_point, dir_name)}")
    
    # Create agent info file
    agent_info = {
        "name": args.name,
        "created": datetime.now().isoformat(),
        "version": "1.0",
        "isolation_level": "L2",
        "storage_size": args.size,
        "creator": "agent-manager"
    }
    
    run_command(f"sudo tee {mount_point}/agent-info.json > /dev/null << 'EOF'\n{json.dumps(agent_info, indent=2)}\nEOF")
    
    # Set permissions
    run_command("sudo chown -R 1000:1000 /tmp/agent-init")
    
    # Unmount
    run_command(f"sudo umount {mount_point}")
    
    print(f"Agent '{args.name}' created successfully!")
    print(f"  Storage: {agent_file}")
    print(f"  Size: {size_gb}GB")
    
    # Update Ventoy config
    update_ventoy_config(usb_mount, args.name, agent_file)


def update_ventoy_config(usb_mount, agent_name, agent_file):
    """Update Ventoy configuration with new agent."""
    config_file = os.path.join(usb_mount, "ventoy", "ventoy.json")
    
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            config = json.load(f)
    else:
        config = {"persistence": [], "agent_isolation": {}}
    
    # Add agent isolation
    if "agent_isolation" not in config:
        config["agent_isolation"] = {}
    
    config["agent_isolation"][agent_name] = {
        "backend": agent_file.replace(usb_mount, ""),
        "description": f"Isolated workspace for agent {agent_name}",
        "created": datetime.now().isoformat()
    }
    
    # Write updated config
    run_command(f"sudo tee {config_file} > /dev/null << 'EOF'\n{json.dumps(config, indent=4)}\nEOF")
    
    print(f"Ventoy configuration updated for agent '{agent_name}'")


def list_agents_command(args):
    """List all agents."""
    usb_mount = get_usb_mount()
    agents = list_agents(usb_mount)
    
    if not agents:
        print("No agents found on USB.")
        return
    
    print(f"\nAgents on USB ({usb_mount}):")
    print("-" * 40)
    
    for agent_name in sorted(agents):
        info = get_agent_info(usb_mount, agent_name)
        if info:
            print(f"  {agent_name}")
            print(f"    Size: {info['size']}")
            if info['info']:
                print(f"    Created: {info['info'].get('created', 'Unknown')}")
            print()


def enter_agent(args):
    """Enter agent's isolated workspace."""
    usb_mount = get_usb_mount()
    agents_dir = get_agents_dir(usb_mount)
    agent_file = os.path.join(agents_dir, f"{args.name}-home.dat")
    
    if not os.path.exists(agent_file):
        print(f"Error: Agent '{args.name}' not found.")
        sys.exit(1)
    
    mount_point = f"/tmp/agent-{args.name}"
    run_command(f"sudo mkdir -p {mount_point}")
    run_command(f"sudo mount -o loop {agent_file} {mount_point}")
    
    print(f"Entering agent '{args.name}' workspace...")
    print(f"  Mounted at: {mount_point}")
    print(f"  Type 'exit' to leave")
    
    # Open shell in agent workspace
    run_command(f"sudo chroot {mount_point} /bin/bash", check=False)
    
    # Unmount when done
    run_command(f"sudo umount {mount_point}")


def backup_agent(args):
    """Backup agent data."""
    usb_mount = get_usb_mount()
    agents_dir = get_agents_dir(usb_mount)
    agent_file = os.path.join(agents_dir, f"{args.name}-home.dat")
    
    if not os.path.exists(agent_file):
        print(f"Error: Agent '{args.name}' not found.")
        sys.exit(1)
    
    # Create backup directory
    backup_dir = args.dest or os.path.expanduser("~/agent-backups")
    os.makedirs(backup_dir, exist_ok=True)
    
    # Create backup filename
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_file = os.path.join(backup_dir, f"{args.name}-backup-{timestamp}.tar.gz")
    
    print(f"Backing up agent '{args.name}'...")
    
    # Mount and backup
    mount_point = "/tmp/agent-backup-mount"
    run_command(f"sudo mkdir -p {mount_point}")
    run_command(f"sudo mount -o loop {agent_file} {mount_point}")
    
    # Create tarball
    with tarfile.open(backup_file, "w:gz") as tar:
        tar.add(mount_point, arcname=args.name)
    
    run_command(f"sudo umount {mount_point}")
    
    print(f"Backup complete: {backup_file}")
    print(f"Size: {os.path.getsize(backup_file) / (1024*1024):.2f} MB")


def restore_agent(args):
    """Restore agent from backup."""
    usb_mount = get_usb_mount()
    agents_dir = get_agents_dir(usb_mount)
    agent_file = os.path.join(agents_dir, f"{args.name}-home.dat")
    
    # Check if agent already exists
    if os.path.exists(agent_file):
        response = input(f"Agent '{args.name}' already exists. Overwrite? (y/N): ")
        if response.lower() != 'y':
            print("Restore cancelled.")
            return
    
    # Check backup file
    if not os.path.exists(args.src):
        print(f"Error: Backup file not found: {args.src}")
        sys.exit(1)
    
    print(f"Restoring agent '{args.name}' from backup...")
    
    # Create agents directory
    run_command(f"sudo mkdir -p {agents_dir}")
    
    # Parse size from backup
    # For now, use default size
    size_gb = 5
    size_mb = size_gb * 1024
    
    # Create agent storage
    run_command(f"sudo dd if=/dev/zero of={agent_file} bs=1M count={size_mb} status=progress")
    run_command(f"sudo mkfs.ext4 -F -L {args.name}-home {agent_file}")
    
    # Mount and restore
    mount_point = "/tmp/agent-restore-mount"
    run_command(f"sudo mkdir -p {mount_point}")
    run_command(f"sudo mount -o loop {agent_file} {mount_point}")
    
    # Extract backup
    with tarfile.open(args.src, "r:gz") as tar:
        tar.extractall(mount_point)
    
    run_command(f"sudo umount {mount_point}")
    
    print(f"Agent '{args.name}' restored successfully!")
    
    # Update Ventoy config
    update_ventoy_config(usb_mount, args.name, agent_file)


def delete_agent(args):
    """Delete agent workspace."""
    usb_mount = get_usb_mount()
    agents_dir = get_agents_dir(usb_mount)
    agent_file = os.path.join(agents_dir, f"{args.name}-home.dat")
    
    if not os.path.exists(agent_file):
        print(f"Error: Agent '{args.name}' not found.")
        sys.exit(1)
    
    # Confirm deletion
    response = input(f"Delete agent '{args.name}'? This cannot be undone. (y/N): ")
    if response.lower() != 'y':
        print("Deletion cancelled.")
        return
    
    print(f"Deleting agent '{args.name}'...")
    
    # Backup before deletion
    backup_dir = os.path.expanduser("~/agent-deletion-backups")
    os.makedirs(backup_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_file = os.path.join(backup_dir, f"{args.name}-pre-delete-{timestamp}.tar.gz")
    
    mount_point = "/tmp/agent-delete-mount"
    run_command(f"sudo mkdir -p {mount_point}")
    run_command(f"sudo mount -o loop {agent_file} {mount_point}")
    
    with tarfile.open(backup_file, "w:gz") as tar:
        tar.add(mount_point, arcname=args.name)
    
    run_command(f"sudo umount {mount_point}")
    
    # Delete agent file
    run_command(f"sudo rm {agent_file}")
    
    # Update Ventoy config
    config_file = os.path.join(usb_mount, "ventoy", "ventoy.json")
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            config = json.load(f)
        
        if "agent_isolation" in config and args.name in config["agent_isolation"]:
            del config["agent_isolation"][args.name]
        
        run_command(f"sudo tee {config_file} > /dev/null << 'EOF'\n{json.dumps(config, indent=4)}\nEOF")
    
    print(f"Agent '{args.name}' deleted.")
    print(f"Pre-deletion backup: {backup_file}")


def health_agent(args):
    """Check agent health."""
    usb_mount = get_usb_mount()
    agents_dir = get_agents_dir(usb_mount)
    agent_file = os.path.join(agents_dir, f"{args.name}-home.dat")
    
    if not os.path.exists(agent_file):
        print(f"Error: Agent '{args.name}' not found.")
        sys.exit(1)
    
    print(f"\nHealth Report for Agent '{args.name}':")
    print("-" * 40)
    
    # File system check
    print("\nFilesystem check:")
    run_command(f"sudo e2fsck -f -n {agent_file}", check=False)
    
    # Disk usage
    print("\nDisk usage:")
    run_command(f"du -h {agent_file}")
    
    # Mount and check contents
    mount_point = "/tmp/agent-health-mount"
    run_command(f"sudo mkdir -p {mount_point}")
    run_command(f"sudo mount -o loop {agent_file} {mount_point}")
    
    # Check directory structure
    print("\nDirectory structure:")
    run_command(f"ls -la {mount_point}")
    
    # Check agent info
    info_file = os.path.join(mount_point, "agent-info.json")
    if os.path.exists(info_file):
        print("\nAgent info:")
        run_command(f"cat {info_file}")
    
    run_command(f"sudo umount {mount_point}")


def clone_agent(args):
    """Clone an existing agent."""
    usb_mount = get_usb_mount()
    agents_dir = get_agents_dir(usb_mount)
    source_file = os.path.join(agents_dir, f"{args.source}-home.dat")
    dest_file = os.path.join(agents_dir, f"{args.dest}-home.dat")
    
    if not os.path.exists(source_file):
        print(f"Error: Source agent '{args.source}' not found.")
        sys.exit(1)
    
    if os.path.exists(dest_file):
        print(f"Error: Destination agent '{args.dest}' already exists.")
        sys.exit(1)
    
    print(f"Cloning agent '{args.source}' to '{args.dest}'...")
    
    # Copy agent file
    run_command(f"sudo cp {source_file} {dest_file}")
    
    # Update agent info in clone
    mount_point = "/tmp/agent-clone-mount"
    run_command(f"sudo mkdir -p {mount_point}")
    run_command(f"sudo mount -o loop {dest_file} {mount_point}")
    
    # Update agent-info.json
    info_file = os.path.join(mount_point, "agent-info.json")
    if os.path.exists(info_file):
        with open(info_file, 'r') as f:
            info = json.load(f)
        
        info["name"] = args.dest
        info["created"] = datetime.now().isoformat()
        info["cloned_from"] = args.source
        
        run_command(f"sudo tee {info_file} > /dev/null << 'EOF'\n{json.dumps(info, indent=2)}\nEOF")
    
    # Regenerate UUID
    run_command(f"sudo tune2fs -U random {dest_file}")
    
    run_command(f"sudo umount {mount_point}")
    
    print(f"Agent '{args.dest}' created from '{args.source}'")
    
    # Update Ventoy config
    update_ventoy_config(usb_mount, args.dest, dest_file)


def main():
    parser = argparse.ArgumentParser(
        description="Manage isolated agent workspaces on portable Linux USB"
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")
    
    # Create command
    create_parser = subparsers.add_parser("create", help="Create a new agent")
    create_parser.add_argument("--name", "-n", required=True, help="Agent name")
    create_parser.add_argument("--size", "-s", default="5G", help="Storage size (default: 5G)")
    create_parser.add_argument("--usb", "-u", help="USB device (auto-detected if not specified)")
    
    # List command
    list_parser = subparsers.add_parser("list", help="List all agents")
    list_parser.add_argument("--usb", "-u", help="USB device (auto-detected if not specified)")
    
    # Enter command
    enter_parser = subparsers.add_parser("enter", help="Enter agent workspace")
    enter_parser.add_argument("--name", "-n", required=True, help="Agent name")
    
    # Backup command
    backup_parser = subparsers.add_parser("backup", help="Backup agent data")
    backup_parser.add_argument("--name", "-n", required=True, help="Agent name")
    backup_parser.add_argument("--dest", "-d", help="Backup destination directory")
    
    # Restore command
    restore_parser = subparsers.add_parser("restore", help="Restore agent from backup")
    restore_parser.add_argument("--name", "-n", required=True, help="Agent name")
    restore_parser.add_argument("--src", "-s", required=True, help="Backup file path")
    
    # Delete command
    delete_parser = subparsers.add_parser("delete", help="Delete agent workspace")
    delete_parser.add_argument("--name", "-n", required=True, help="Agent name")
    delete_parser.add_argument("--usb", "-u", help="USB device (auto-detected if not specified)")
    
    # Health command
    health_parser = subparsers.add_parser("health", help="Check agent health")
    health_parser.add_argument("--name", "-n", required=True, help="Agent name")
    
    # Clone command
    clone_parser = subparsers.add_parser("clone", help="Clone an existing agent")
    clone_parser.add_argument("--source", "-s", required=True, help="Source agent name")
    clone_parser.add_argument("--dest", "-d", required=True, help="Destination agent name")
    clone_parser.add_argument("--usb", "-u", help="USB device (auto-detected if not specified)")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    # Execute command
    commands = {
        "create": create_agent,
        "list": list_agents_command,
        "enter": enter_agent,
        "backup": backup_agent,
        "restore": restore_agent,
        "delete": delete_agent,
        "health": health_agent,
        "clone": clone_agent
    }
    
    commands[args.command](args)


if __name__ == "__main__":
    main()
