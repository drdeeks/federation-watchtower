#!/usr/bin/env python3
"""
Duplicate Crew - Create a copy of an existing crew with selective data migration.
Supports bringing over identity, memory, knowledge, and communications from a
source crew to a new target crew.
"""

import argparse
import json
import os
import shutil
import sys
import uuid
from pathlib import Path
from datetime import datetime

def show_help():
    print("""
Crew Duplicate - Copy crew with selective data migration

Usage: python3 duplicate-crew.py --source <crew-id> --target <crew-id> [options]

Arguments:
  --source <crew-id>    Source crew to duplicate
  --target <crew-id>    New crew ID for the duplicate

Options:
  --include <cats>      Categories to include: identity,memory,knowledge,communications,checkpoints
                        (default: identity,memory,knowledge)
  --exclude <cats>      Categories to exclude
  --new-identities      Generate new agent IDs for isolation
  --preserve-builder-codes  Keep original ERC-8021 registrations (default: reset)
  --workspace <path>    Crew workspace root (default: $HOME/crews)
  --config-dir <path>   Crew config directory (default: ~/.config/autonomous-crew)
  --mode <mode>         Target mode: development | production | source (default: same as source)
  --dry-run             Preview actions without executing
  --help                Show this help

Example:
  python3 duplicate-crew.py --source hackathon-2026-prod --target hackathon-2026-experiment --include identity,memory,knowledge --new-identities
""")

def main():
    parser = argparse.ArgumentParser(description="Duplicate Crew", add_help=False)
    parser.add_argument("--source", help="Source crew ID")
    parser.add_argument("--target", help="Target crew ID")
    parser.add_argument("--include", default="identity,memory,knowledge", help="Categories: identity,memory,knowledge,communications,checkpoints")
    parser.add_argument("--exclude", help="Categories to exclude")
    parser.add_argument("--new-identities", action="store_true", help="Generate new agent IDs")
    parser.add_argument("--preserve-builder-codes", action="store_true", help="Keep original ERC-8021 registrations")
    parser.add_argument("--workspace", default=str(Path.home() / "crews"))
    parser.add_argument("--config-dir", default=str(Path.home() / ".config" / "autonomous-crew"))
    parser.add_argument("--mode", choices=["development", "production", "source"], default="source")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--help", "-h", action="store_true")
    
    args, _ = parser.parse_known_args()
    
    if args.help or not (args.source and args.target):
        show_help()
        return 0
    
    parser.parse_args()
    
    workspace = Path(args.workspace)
    source_path = workspace / args.source
    target_path = workspace / args.target
    
    if not source_path.exists():
        print(f"ERROR: Source crew not found: {source_path}")
        return 1
    if target_path.exists():
        print(f"ERROR: Target crew already exists: {target_path}")
        return 1
    
    include = set(args.include.split(","))
    if args.exclude:
        include = include - set(args.exclude.split(","))
    
    # Determine target mode
    source_crew_json = source_path / "crew.json"
    source_crew_type = "development"
    if source_crew_json.exists():
        with open(source_crew_json) as f:
            source_config = json.load(f)
        source_crew_type = source_config.get("crew_type", "development")
    
    target_crew_type = source_crew_type if args.mode == "source" else args.mode
    
    agent_id_map = {}
    
    print(f"=== Duplicating Crew: {args.source} -> {args.target} ===")
    print(f"  Include: {', '.join(sorted(include))}")
    print(f"  Target mode: {target_crew_type}")
    if args.new_identities:
        print(f"  NEW agent IDs will be generated")
    if args.dry_run:
        print("  DRY RUN - no changes")
    print()
    
    if args.dry_run:
        return 0
    
    # Phase 1: Create target workspace structure
    print("[1/5] Creating target workspace structure...")
    target_path.mkdir(parents=True, exist_ok=True)
    (target_path / "agents").mkdir(exist_ok=True)
    (target_path / "shared").mkdir(exist_ok=True)
    (target_path / "index").mkdir(exist_ok=True)
    
    # Phase 2: Duplicate identity layer
    print("[2/5] Duplicating identity layer...")
    if "identity" in include:
        source_agents = source_path / "agents"
        if source_agents.exists():
            for agent_dir in source_agents.iterdir():
                if agent_dir.is_dir():
                    original_id = agent_dir.name
                    new_id = original_id
                    
                    if args.new_identities:
                        # Generate new ID preserving agent type prefix
                        prefix = original_id.split("-")[0] if "-" in original_id else "agent"
                        suffix = uuid.uuid4().hex[:8]
                        new_id = f"{prefix}-{suffix}"
                        agent_id_map[original_id] = new_id
                    
                    target_agent = target_path / "agents" / new_id
                    target_agent.mkdir(parents=True, exist_ok=True)
                    
                    # Copy .agent directory
                    source_dot_agent = agent_dir / ".agent"
                    if source_dot_agent.exists():
                        shutil.copytree(source_dot_agent, target_agent / ".agent", dirs_exist_ok=True)
                    
                    # Copy agent.json with updates
                    source_agent_json = agent_dir / "agent.json"
                    if source_agent_json.exists():
                        with open(source_agent_json) as f:
                            agent_config = json.load(f)
                        agent_config["agentId"] = new_id
                        agent_config["crew_id"] = args.target
                        agent_config["mode"] = target_crew_type
                        agent_config["workspace"] = str(target_agent)
                        if not args.preserve_builder_codes:
                            agent_config["builderCode"] = {
                                "code": "SET_AFTER_REGISTRATION",
                                "hex": "SET_AFTER_REGISTRATION",
                                "owner": "SET_AFTER_REGISTRATION",
                                "hardwired": True,
                                "enforced": True
                            }
                        with open(target_agent / "agent.json", "w") as f:
                            json.dump(agent_config, f, indent=2)
                    
                    # Copy scripts
                    for script in ["enforcer_daemon.py", "agent_runtime.py", "memory_curator.py", "start-agent.sh"]:
                        src = agent_dir / script
                        if src.exists():
                            shutil.copy2(src, target_agent / script)
                    
                    # Copy tools
                    source_tools = agent_dir / "tools"
                    if source_tools.exists():
                        shutil.copytree(source_tools, target_agent / "tools", dirs_exist_ok=True)
                    
                    # Copy skills
                    source_skills = agent_dir / "skills"
                    if source_skills.exists():
                        shutil.copytree(source_skills, target_agent / "skills", dirs_exist_ok=True)
                    
                    print(f"    {'→ '.join(filter(None, [original_id, new_id if new_id != original_id else '']))}")
    
    # Phase 3: Duplicate memory
    print("[3/5] Duplicating memory...")
    if "memory" in include:
        source_agents = source_path / "agents"
        if source_agents.exists():
            for agent_dir in source_agents.iterdir():
                if agent_dir.is_dir():
                    original_id = agent_dir.name
                    new_id = agent_id_map.get(original_id, original_id)
                    target_agent = target_path / "agents" / new_id
                    
                    # Copy memory subdirectories
                    for subdir in ["daily", "weekly", "long-term"]:
                        src = agent_dir / "memory" / subdir
                        dst = target_agent / "memory" / subdir
                        if src.exists():
                            dst.mkdir(parents=True, exist_ok=True)
                            for item in src.iterdir():
                                if item.is_file() and item.suffix in [".md", ".json", ".txt"]:
                                    shutil.copy2(item, dst / item.name)
                    
                    # Copy knowledge index
                    ki_src = agent_dir / "memory" / "knowledge-index.json"
                    ki_dst = target_agent / "memory" / "knowledge-index.json"
                    if ki_src.exists():
                        shutil.copy2(ki_src, ki_dst)
        print("    ✅ Memory duplicated")
    
    # Phase 4: Duplicate knowledge, communications
    print("[4/5] Duplicating knowledge and communications...")
    for category in ["knowledge", "communications"]:
        if category in include:
            src_shared = source_path / "shared" / category
            dst_shared = target_path / "shared" / category
            if src_shared.exists():
                dst_shared.mkdir(parents=True, exist_ok=True)
                shutil.copytree(src_shared, dst_shared, dirs_exist_ok=True)
                print(f"    ✅ {category} duplicated")
    
    # Phase 5: Create crew config
    print("[5/5] Creating crew config...")
    crew_config = {
        "crew_id": args.target,
        "crew_type": target_crew_type,
        "source_crew": args.source,
        "duplicated_utc": datetime.utcnow().isoformat() + "Z",
        "included_categories": list(sorted(include)),
        "new_identities": args.new_identities,
        "preserved_builder_codes": args.preserve_builder_codes,
        "agent_id_map": agent_id_map,
        "workspace": str(target_path)
    }
    
    with open(target_path / "crew.json", "w") as f:
        json.dump(crew_config, f, indent=2)
    
    # Create CHANGELOG
    with open(target_path / "CHANGELOG.md", "a") as f:
        f.write(f"\n## [{args.target}] - {datetime.utcnow().strftime('%Y-%m-%d')}\n")
        f.write(f"\n### Duplicated from {args.source}\n")
        f.write(f"- Included: {', '.join(sorted(include))}\n")
        f.write(f"- Target mode: {target_crew_type}\n")
        f.write(f"- New identities: {args.new_identities}\n\n---\n")
    
    print(f"\n=== Duplication Complete: {args.source} -> {args.target} ===")
    print(f"  Target workspace: {target_path}")
    print(f"  Target mode: {target_crew_type}")
    print(f"  Data included: {', '.join(sorted(include))}")
    if agent_id_map:
        print(f"  New agent IDs generated")
    return 0

if __name__ == "__main__":
    sys.exit(main())