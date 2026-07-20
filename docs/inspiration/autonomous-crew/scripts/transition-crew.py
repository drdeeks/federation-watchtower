#!/usr/bin/env python3
"""
Crew Transition - Migrate crew between development and production modes,
preserving all identity, memory, knowledge, and communications.
"""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from datetime import datetime

def show_help():
    print("""
Crew Transition - Migrate crew between dev/prod modes preserving all data

Usage: python3 transition-crew.py --source <crew-id> --target <crew-id> --mode <mode> [options]

Arguments:
  --source <id>         Source crew ID
  --target <id>         Target crew ID
  --mode <mode>         Transition mode: development-to-production | production-to-development

Options:
  --workspace <path>    Crew workspace root (default: $HOME/crews)
  --config-dir <path>   Crew config directory (default: ~/.config/autonomous-crew)
  --preserve-all        Preserve all data (identity, memory, knowledge, communications, checkpoints)
  --include <cats>      Comma-separated: identity,memory,knowledge,communications,checkpoints
  --exclude <cats>      Comma-separated categories to skip
  --dry-run             Preview actions without executing
  --help                Show this help

Example:
  python3 transition-crew.py --source hackathon-2026-dev --target hackathon-2026-prod --mode development-to-production --preserve-all
  python3 transition-crew.py --source hackathon-2026-prod --target hackathon-2026-experiment --mode production-to-development --include identity,memory,knowledge
""")

def main():
    parser = argparse.ArgumentParser(description="Crew Transition", add_help=False)
    parser.add_argument("--source", help="Source crew ID")
    parser.add_argument("--target", help="Target crew ID")
    parser.add_argument("--mode", choices=["development-to-production", "production-to-development"])
    parser.add_argument("--workspace", default=str(Path.home() / "crews"))
    parser.add_argument("--config-dir", default=str(Path.home() / ".config" / "autonomous-crew"))
    parser.add_argument("--preserve-all", action="store_true")
    parser.add_argument("--include", help="Comma-separated categories: identity,memory,knowledge,communications,checkpoints")
    parser.add_argument("--exclude", help="Comma-separated categories to exclude")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--help", "-h", action="store_true")
    
    args, _ = parser.parse_known_args()
    
    if args.help or not (args.source and args.target and args.mode):
        show_help()
        return 0
    
    parser.parse_args()
    
    workspace = Path(args.workspace)
    config_dir = Path(args.config_dir)
    source_path = workspace / args.source
    target_path = workspace / args.target
    
    if not source_path.exists():
        print(f"ERROR: Source crew not found: {source_path}")
        return 1
    if target_path.exists():
        print(f"ERROR: Target crew already exists: {target_path}")
        return 1
    
    # Determine what to preserve
    if args.preserve_all:
        preserve = {"identity", "memory", "knowledge", "communications", "checkpoints"}
    else:
        preserve = set(args.include.split(",")) if args.include else {"identity", "memory", "knowledge", "communications"}
    
    if args.exclude:
        exclude = set(args.exclude.split(","))
        preserve = preserve - exclude
    
    target_crew_type = "production" if args.mode == "development-to-production" else "development"
    
    print(f"=== Crew Transition: {args.source} -> {args.target} ===")
    print(f"  Mode: {args.mode}")
    print(f"  Preserve: {', '.join(sorted(preserve))}")
    print(f"  Target type: {target_crew_type}")
    if args.dry_run:
        print("  DRY RUN - no changes will be made")
    print()
    
    if args.dry_run:
        for category in sorted(preserve):
            print(f"  Would transition: {category}")
        print()
        print(f"  Source: {source_path}")
        print(f"  Target: {target_path}")
        return 0
    
    # Phase 1: Create target crew directory
    print("[1/5] Creating target crew workspace...")
    target_path.mkdir(parents=True, exist_ok=True)
    
    if target_crew_type == "production":
        # Production uses agent subdirectories
        (target_path / "agents").mkdir(exist_ok=True)
        (target_path / "shared").mkdir(exist_ok=True)
        (target_path / "index").mkdir(exist_ok=True)
    else:
        # Development uses shared workspace
        (target_path / "shared").mkdir(exist_ok=True)
        (target_path / "agents").mkdir(exist_ok=True)
    
    # Phase 2: Transition identity layer (constitutions, habits, enforcer configs)
    print("[2/5] Transitioning identity layer...")
    if "identity" in preserve:
        # Read agent info from source crew.json
        source_crew_json = source_path / "crew.json"
        source_agents_info = []
        if source_crew_json.exists():
            with open(source_crew_json) as f:
                source_crew_config = json.load(f)
            source_agents_info = source_crew_config.get("agents", [])
        
        target_agents = target_path / "agents"
        
        for agent_info in source_agents_info:
            agent_id = agent_info.get("agent_id")
            agent_workspace = Path(agent_info.get("workspace", ""))
            
            if not agent_workspace.exists():
                print(f"    ⚠️  Agent workspace not found: {agent_workspace}")
                continue
            
            target_agent = target_agents / agent_id
            target_agent.mkdir(parents=True, exist_ok=True)
            
            # Copy .agent directory (constitution, habits, enforcer configs)
            source_dot_agent = agent_workspace / ".agent"
            if source_dot_agent.exists():
                shutil.copytree(source_dot_agent, target_agent / ".agent", 
                                dirs_exist_ok=True)
            
            # Copy agent.json
            source_agent_json = agent_workspace / "agent.json"
            if source_agent_json.exists():
                with open(source_agent_json) as f:
                    agent_config = json.load(f)
                # Update for new crew
                agent_config["crew_id"] = args.target
                agent_config["mode"] = target_crew_type
                agent_config["workspace"] = str(target_agent)
                agent_config["enforcer_socket"] = str(target_agent / ".agent" / "enforcer.sock")
                with open(target_agent / "agent.json", "w") as f:
                    json.dump(agent_config, f, indent=2)
            
            # Copy enforcer daemon, agent runtime, memory curator
            for script in ["enforcer_daemon.py", "agent_runtime.py", "memory_curator.py", "start-agent.sh"]:
                src = agent_workspace / script
                if src.exists():
                    shutil.copy2(src, target_agent / script)
            
            print(f"    ✅ Agent {agent_id}")
    
    # Phase 3: Transition memory pipeline
    print("[3/5] Transitioning memory pipeline...")
    if "memory" in preserve:
        def copy_memory(source_base, target_base, label):
            for subdir in ["daily", "weekly", "long-term"]:
                src = source_base / "memory" / subdir
                dst = target_base / "memory" / subdir
                if src.exists():
                    dst.mkdir(parents=True, exist_ok=True)
                    for item in src.iterdir():
                        if item.is_file() and item.suffix in [".md", ".json"]:
                            shutil.copy2(item, dst / item.name)
            # Copy knowledge index
            ki_src = source_base / "memory" / "knowledge-index.json"
            ki_dst = target_base / "memory" / "knowledge-index.json"
            if ki_src.exists():
                shutil.copy2(ki_src, ki_dst)
        
        if target_crew_type == "production":
            agents = target_path / "agents"
            for agent_dir in agents.iterdir():
                if agent_dir.is_dir():
                    # Find matching source agent workspace
                    agent_id = agent_dir.name
                    src_agent_workspace = None
                    for agent_info in source_agents_info:
                        if agent_info.get("agent_id") == agent_id:
                            src_agent_workspace = Path(agent_info.get("workspace", ""))
                            break
                    if src_agent_workspace and src_agent_workspace.exists():
                        copy_memory(src_agent_workspace, agent_dir, agent_dir.name)
        else:
            # Copy shared memory
            src_shared = source_path / "shared" / "memory"
            dst_shared = target_path / "shared" / "memory"
            if src_shared.exists():
                if dst_shared.exists():
                    shutil.rmtree(dst_shared)
                shutil.copytree(src_shared, dst_shared, dirs_exist_ok=True)
        
        print("    ✅ Memory preserved")
    
    # Phase 4: Transition knowledge base and communications
    print("[4/5] Transitioning knowledge and communications...")
    for category in ["knowledge", "communications"]:
        if category in preserve:
            src_shared = source_path / "shared" / category
            dst_shared = target_path / "shared" / category
            if src_shared.exists():
                dst_shared.mkdir(parents=True, exist_ok=True)
                shutil.copytree(src_shared, dst_shared, dirs_exist_ok=True)
                print(f"    ✅ {category} preserved")
    
    # Phase 5: Create crew config and commit
    print("[5/5] Creating crew config...")
    crew_config = {
        "crew_id": args.target,
        "crew_type": target_crew_type,
        "source_crew": args.source,
        "transitioned_utc": datetime.utcnow().isoformat() + "Z",
        "transition_mode": args.mode,
        "preserved_categories": list(sorted(preserve)),
        "workspace": str(target_path)
    }
    
    with open(target_path / "crew.json", "w") as f:
        json.dump(crew_config, f, indent=2)
    
    # Create CHANGELOG
    with open(target_path / "CHANGELOG.md", "a") as f:
        f.write(f"\n## [{args.target}] - {datetime.utcnow().strftime('%Y-%m-%d')}\n")
        f.write(f"\n### Transitioned from {args.source}\n")
        f.write(f"- Mode: {args.mode}\n")
        f.write(f"- Preserved: {', '.join(sorted(preserve))}\n")
        f.write(f"- Target type: {target_crew_type}\n\n---\n")
    
    # Create snapshot of source crew config for reference
    shutil.copy2(source_path / "crew.json", target_path / f"source-{args.source}-crew.json")
    
    print(f"\n=== Transition Complete: {args.source} -> {args.target} ===")
    print(f"  Target workspace: {target_path}")
    print(f"  Target type: {target_crew_type}")
    print(f"  Data preserved: {', '.join(sorted(preserve))}")
    print(f"  CHANGELOG updated")
    print()
    print("Next steps:")
    print(f"  1. Run: bash scripts/verify-crew-identity.sh {args.target}")
    print(f"  2. Run: bash scripts/crew-heartbeat.sh {args.target}")
    print(f"  3. Start agent enforcers and runtimes")
    return 0

if __name__ == "__main__":
    sys.exit(main())