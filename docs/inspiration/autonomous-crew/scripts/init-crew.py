#!/usr/bin/env python3
"""
Initialize Crew - Create new autonomous crew with identity-first architecture
"""

import argparse
import json
import os
import sys
from pathlib import Path
import shutil

def show_help():
    print("""
Initialize Crew - Create new autonomous crew with identity-first architecture

Usage: python3 init-crew.py <crew-id> [--help] [--template <type>]

Arguments:
  crew-id      Unique crew identifier (e.g., hackathon-2026)

Options:
  --help       Show this help message
  --template   Crew template (default: standard) - standard, minimal, hemlock

Environment:
  WORKSPACE_ROOT   Root directory for crews (default: $HOME/crews)
  AGENT_TYPES      Space-separated agent types to pre-create

Example:
  python3 init-crew.py hackathon-2026
  AGENT_TYPES="ui blockchain validation" python3 init-crew.py my-crew
""")

def main():
    parser = argparse.ArgumentParser(description="Initialize Crew", add_help=False)
    parser.add_argument("crew_id", nargs="?", help="Crew identifier")
    parser.add_argument("--help", "-h", action="store_true", help="Show help")
    parser.add_argument("--template", default="standard", help="Crew template")
    
    args, _ = parser.parse_known_args()
    
    if args.help or not args.crew_id:
        show_help()
        return 0
    
    parser.parse_args()
    
    workspace_root = Path(os.environ.get("WORKSPACE_ROOT", Path.home() / "crews"))
    crew_dir = workspace_root / args.crew_id
    crew_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"=== Initializing Crew: {args.crew_id} ===")
    print(f"  Workspace: {crew_dir}")
    
    # Create crew structure
    (crew_dir / "agents").mkdir(exist_ok=True)
    (crew_dir / "blueprints").mkdir(exist_ok=True)
    (crew_dir / "checkpoints").mkdir(exist_ok=True)
    (crew_dir / "logs").mkdir(exist_ok=True)
    (crew_dir / "shared").mkdir(exist_ok=True)
    
    # Create crew config
    crew_config = {
        "crew_id": args.crew_id,
        "template": args.template,
        "created_utc": __import__("datetime").datetime.utcnow().isoformat() + "Z",
        "identity_layer": "v1",
        "agents": [],
        "blueprints": [],
        "enforcer_registry": f"{crew_dir}/.enforcer-registry.json",
        "memory_pipeline": {
            "daily_retention_days": 14,
            "weekly_retention_weeks": 12,
            "shared_knowledge_index": f"{crew_dir}/shared/knowledge-index.json"
        }
    }
    
    with open(crew_dir / "crew.json", "w") as f:
        json.dump(crew_config, f, indent=2)
    
    # Create agents registry
    with open(crew_dir / "agents.json", "w") as f:
        json.dump({"crew_id": args.crew_id, "agents": []}, f, indent=2)
    
    # Create shared knowledge index
    with open(crew_dir / "shared" / "knowledge-index.json", "w") as f:
        json.dump({}, f, indent=2)
    
    # Create CHANGELOG.md (enterprise format)
    changelog = f"""# CHANGELOG

## [{args.crew_id}] - {__import__("datetime").datetime.utcnow().strftime("%Y-%m-%d")}

### Crew Initialized
- Crew ID: {args.crew_id}
- Template: {args.template}
- Identity Layer: v1 (agent-identity-architecture)
- Enforcer Registry: .enforcer-registry.json

---
"""
    with open(crew_dir / "CHANGELOG.md", "w") as f:
        f.write(changelog)
    
    # Create .enforcer-registry.json
    with open(crew_dir / ".enforcer-registry.json", "w") as f:
        json.dump({"crew_id": args.crew_id, "enforcers": {}}, f, indent=2)
    
    print(f"  ✅ Crew structure created")
    print(f"  ✅ crew.json written")
    print(f"  ✅ agents.json written")
    print(f"  ✅ CHANGELOG.md initialized")
    print(f"  ✅ .enforcer-registry.json created")
    print(f"  ✅ Shared knowledge index initialized")
    
    # Pre-create agents if specified
    agent_types = os.environ.get("AGENT_TYPES", "").split()
    if agent_types:
        print(f"\n  Pre-creating agents: {', '.join(agent_types)}")
        for atype in agent_types:
            print(f"    → {atype}...")
            # In production, would call create-crew-agent.sh here
    
    print(f"\n=== Crew {args.crew_id} Ready ===")
    print(f"  Next: bash scripts/create-crew-agent.sh <type> [name]")
    print(f"  Crew dir: {crew_dir}")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())