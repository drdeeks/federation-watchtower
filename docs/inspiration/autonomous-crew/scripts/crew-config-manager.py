#!/usr/bin/env python3
"""
Crew Config Manager - Manage active crew configs, pointers, and transitions.
Handles listing, switching, creating crews, and maintaining the active crew pointer.
"""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from datetime import datetime

CONFIG_DIR = Path.home() / ".config" / "autonomous-crew"
DEFAULT_WORKSPACE = Path.home() / "crews"


def show_help():
    print("""
Crew Config Manager - Manage active crew configs and pointers

Usage: python3 crew-config-manager.py <command> [options]

Commands:
  list                    List all known crews
  active                  Show current active crew
  switch <crew-id>        Switch active crew
  create <crew-id>        Create new crew from template
  set-defaults            Set default crew config
  show <crew-id>          Show crew details
  remove <crew-id>        Remove crew from registry
  help                    Show this help

Options:
  --template <crew-id>    Source crew to use as template
  --mode <mode>           Crew mode: development | production
  --workspace <path>      Crew workspace root
  --config-dir <path>     Config directory (default: ~/.config/autonomous-crew)

Example:
  python3 crew-config-manager.py list
  python3 crew-config-manager.py switch hackathon-2026-prod
  python3 crew-config-manager.py create hackathon-2027 --template hackathon-2026-prod --mode production
""")


def get_all_crews(workspace=None):
    """Scan for all known crews from config dir and workspace."""
    ws = Path(workspace) if workspace else DEFAULT_WORKSPACE
    crews = {}

    # From config dir
    config_crews = CONFIG_DIR / "crews"
    if config_crews.exists():
        for crew_dir in config_crews.iterdir():
            if crew_dir.is_dir():
                crew_json = crew_dir / "crew.json"
                if crew_json.exists():
                    with open(crew_json) as f:
                        crews[crew_dir.name] = json.load(f)
                else:
                    crews[crew_dir.name] = {"crew_id": crew_dir.name, "status": "incomplete"}

    # From workspace
    if ws.exists():
        try:
            for crew_dir in ws.iterdir():
                if crew_dir.is_dir():
                    name = crew_dir.name
                    if name not in crews:
                        crew_json = crew_dir / "crew.json"
                        try:
                            if crew_json.exists():
                                with open(crew_json) as f:
                                    crews[name] = json.load(f)
                            else:
                                crews[name] = {"crew_id": name, "workspace": str(crew_dir), "status": "unregistered"}
                        except (PermissionError, OSError):
                            continue
        except (PermissionError, OSError):
            pass

    return crews


def ensure_config():
    """Ensure config directory structure exists."""
    (CONFIG_DIR / "crews").mkdir(parents=True, exist_ok=True)


def get_active_crew():
    """Get the active crew pointer."""
    active_link = CONFIG_DIR / "active"
    if active_link.exists() or active_link.is_symlink():
        target = os.readlink(str(active_link)) if active_link.is_symlink() else "broken"
        return Path(target).name
    return None


def cmd_list(args):
    ensure_config()
    ws = args.workspace if args.workspace else None
    crews = get_all_crews(ws)
    active = get_active_crew()

    print(f"\n{'Crew ID':<30} {'Type':<15} {'Mode':<12} Status")
    print("-" * 75)

    for name, config in sorted(crews.items()):
        prefix = "→ " if name == active else "  "
        crew_type = config.get("crew_type", "?")
        status = config.get("status", "registered")
        print(f"{prefix}{name:<28} {crew_type:<15} {'development' if crew_type == 'development' else 'production':<12} {status}")

    print(f"\nActive crew: {active or 'None'}")
    print(f"Config dir: {CONFIG_DIR}")
    ws_display = ws if ws else DEFAULT_WORKSPACE
    print(f"Workspace root: {ws_display}")
    return 0


def cmd_active(args):
    ensure_config()
    ws = args.workspace if args.workspace else None
    active_id = get_active_crew()

    if not active_id:
        print("No active crew configured.")
        print("Use: python3 crew-config-manager.py switch <crew-id>")
        return 1

    crews = get_all_crews(ws)
    config = crews.get(active_id, {})

    print(f"\n=== Active Crew: {active_id} ===")
    print(f"  Type: {config.get('crew_type', '?')}")
    ws_display = ws if ws else DEFAULT_WORKSPACE
    print(f"  Workspace: {config.get('workspace', str(ws_display / active_id))}")

    # Show crew.json details
    workspace = Path(config.get("workspace", str(ws_display / active_id)))
    crew_json = workspace / "crew.json"
    if crew_json.exists():
        with open(crew_json) as f:
            details = json.load(f)
        for key, value in details.items():
            if key != "agent_id_map":
                print(f"  {key}: {value}")

    # Show symlink info
    active_link = CONFIG_DIR / "active"
    if active_link.is_symlink():
        print(f"  Pointer: {active_link} -> {os.readlink(str(active_link))}")

    return 0


def cmd_switch(args):
    ensure_config()
    ws = args.workspace if args.workspace else None
    crew_id = args.switch_id

    if not crew_id:
        print("ERROR: crew-id required")
        return 1

    # Verify crew exists
    crews = get_all_crews(ws)
    if crew_id not in crews:
        print(f"WARNING: Crew '{crew_id}' not in registry")
        response = input("Add to registry and switch anyway? [Y/n] ")
        if response.lower() not in ["", "y", "yes"]:
            return 1

    # Update active pointer
    active_link = CONFIG_DIR / "active"
    crew_config_dir = CONFIG_DIR / "crews" / crew_id

    if not crew_config_dir.exists():
        crew_config_dir.mkdir(parents=True)

    if active_link.exists() or active_link.is_symlink():
        active_link.unlink()

    os.symlink(str(crew_config_dir), str(active_link))

    print(f"Active crew switched to: {crew_id}")
    print(f"  Pointer: {active_link} -> {crew_config_dir}")
    return 0


def cmd_create(args):
    ensure_config()
    if not args.create_id:
        print("ERROR: crew-id required")
        return 1

    crew_id = args.create_id
    mode = args.mode or "development"
    template = args.template

    crew_config_path = CONFIG_DIR / "crews" / crew_id
    if crew_config_path.exists():
        print(f"ERROR: Crew '{crew_id}' already exists")
        return 1

    crew_config_path.mkdir(parents=True)

    workspace = Path(args.workspace or str(DEFAULT_WORKSPACE / crew_id))

    config = {
        "crew_id": crew_id,
        "crew_type": mode,
        "workspace": str(workspace),
        "created_utc": datetime.utcnow().isoformat() + "Z",
        "template": template or "none",
        "agents": [],
        "status": "initialized"
    }

    with open(crew_config_path / "crew.json", "w") as f:
        json.dump(config, f, indent=2)

    # Create workspace structure
    if args.workspace:
        workspace.mkdir(parents=True, exist_ok=True)
    else:
        workspace.mkdir(parents=True, exist_ok=True)
        (workspace / "agents").mkdir(exist_ok=True)
        (workspace / "shared").mkdir(exist_ok=True)
        (workspace / "index").mkdir(exist_ok=True)

    print(f"Created crew: {crew_id}")
    print(f"  Mode: {mode}")
    print(f"  Workspace: {workspace}")
    print(f"  Config: {crew_config_path / 'crew.json'}")

    if template:
        print(f"  Template: {template}")
        print("NOTE: Use duplicate-crew.py to copy data from template")

    return 0


def cmd_set_defaults(args):
    ensure_config()
    defaults = {
        "default_mode": args.mode or "development",
        "default_workspace": args.workspace or str(DEFAULT_WORKSPACE),
        "updated_utc": datetime.utcnow().isoformat() + "Z"
    }

    with open(CONFIG_DIR / "defaults.yaml", "w") as f:
        for key, value in defaults.items():
            f.write(f"{key}: {value}\n")

    print(f"Defaults updated at {CONFIG_DIR / 'defaults.yaml'}")
    return 0


def cmd_show(args):
    ensure_config()
    ws = args.workspace if args.workspace else None
    if not args.show_id:
        print("ERROR: crew-id required")
        return 1

    crew_id = args.show_id
    crews = get_all_crews(ws)
    config = crews.get(crew_id)

    if not config:
        print(f"Crew '{crew_id}' not found")
        return 1

    print(f"\n=== Crew: {crew_id} ===")
    for key, value in config.items():
        if isinstance(value, dict):
            print(f"  {key}:")
            for k, v in value.items():
                print(f"    {k}: {v}")
        elif isinstance(value, list):
            print(f"  {key}: [{', '.join(value)}]")
        else:
            print(f"  {key}: {value}")

    # Show workspace contents
    ws_display = ws if ws else DEFAULT_WORKSPACE
    workspace = Path(config.get("workspace", str(ws_display / crew_id)))
    if workspace.exists():
        print(f"\n  Workspace Contents ({workspace}):")
        for item in workspace.iterdir():
            if item.is_dir():
                agents = list(item.iterdir()) if item.name == "agents" else []
                agent_count = len(agents)
                print(f"    📁 {item.name}/ ({agent_count} agents)" if item.name == "agents" else f"    📁 {item.name}/")

    return 0


def cmd_remove(args):
    ensure_config()
    ws = args.workspace if args.workspace else None
    if not args.remove_id:
        print("ERROR: crew-id required")
        return 1

    crew_id = args.remove_id

    # Remove from config
    crew_config_path = CONFIG_DIR / "crews" / crew_id
    if crew_config_path.exists():
        shutil.rmtree(crew_config_path)

    # Clear active pointer if this was active
    active = get_active_crew()
    if active == crew_id:
        active_link = CONFIG_DIR / "active"
        if active_link.exists() or active_link.is_symlink():
            active_link.unlink()
        print(f"Active crew pointer cleared (was: {crew_id})")

    print(f"Removed crew '{crew_id}' from registry")
    print("NOTE: Workspace files were NOT deleted")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Crew Config Manager", add_help=False)
    parser.add_argument("command", nargs="?", choices=["list", "active", "switch", "create", "set-defaults", "show", "remove", "help"])
    parser.add_argument("id_arg", nargs="?", help="Crew ID")
    parser.add_argument("--template", help="Template crew for create")
    parser.add_argument("--mode", choices=["development", "production"], help="Crew mode")
    parser.add_argument("--workspace", help="Crew workspace root")
    parser.add_argument("--config-dir", help="Config directory")
    parser.add_argument("--help", "-h", action="store_true")

    args, _ = parser.parse_known_args()

    if args.help or args.command == "help" or not args.command:
        show_help()
        return 0

    # Route to command handler
    if args.command == "list":
        return cmd_list(args)
    elif args.command == "active":
        return cmd_active(args)
    elif args.command == "switch":
        args.switch_id = args.id_arg
        return cmd_switch(args)
    elif args.command == "create":
        args.create_id = args.id_arg
        return cmd_create(args)
    elif args.command == "set-defaults":
        return cmd_set_defaults(args)
    elif args.command == "show":
        args.show_id = args.id_arg
        return cmd_show(args)
    elif args.command == "remove":
        args.remove_id = args.id_arg
        return cmd_remove(args)

    return 0


if __name__ == "__main__":
    sys.exit(main())