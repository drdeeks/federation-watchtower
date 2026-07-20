#!/usr/bin/env python3
"""
Create Blueprint Chain
Creates a loop-enforcer chain from a blueprint.
"""

import json
import sys
import os
from pathlib import Path
from datetime import datetime, timezone

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def create_blueprint_chain(project_dir, blueprint_json_path):
    """Create a loop-enforcer chain from a blueprint JSON."""
    
    with open(blueprint_json_path) as f:
        blueprint = json.load(f)
    
    project_dir = Path(project_dir)
    chain_dir = project_dir / ".blueprint-chain"
    chain_dir.mkdir(parents=True, exist_ok=True)
    
    # Extract chain info
    chain_name = blueprint.get("name", project_dir.name)
    steps = blueprint.get("steps", [])
    
    # Create chain state
    chain_state = {
        "name": chain_name,
        "project": str(project_dir.absolute()),
        "created_at": now_iso(),
        "steps": []
    }
    
    for i, step in enumerate(steps):
        step_path = step.get("path", f"phase-{i:02d}.marker")
        
        # Create marker file if it doesn't exist
        marker_file = chain_dir / step_path.split("/")[-1]
        if not marker_file.exists():
            marker_file.write_text(f"Phase {i} created")
        
        chain_step = {
            "index": i,
            "path": str(marker_file.absolute()),
            "state": "active" if i == 0 else "locked",
            "validator": None,
            "created_at": now_iso(),
            "verified_at": None,
            "completed_at": None,
            "attempts": 0,
        }
        chain_state["steps"].append(chain_step)
    
    # Save chain state
    chain_file = chain_dir / f"{chain_name}.json"
    with open(chain_file, "w") as f:
        json.dump(chain_state, f, indent=2)
    
    # Create log file
    log_file = chain_dir / f"{chain_name}.log"
    with open(log_file, "w") as f:
        f.write(f"[{now_iso()}] Chain created with {len(steps)} steps\n")
    
    return {
        "ok": True,
        "chain": chain_name,
        "steps": len(steps),
        "chain_file": str(chain_file),
        "marker_dir": str(chain_dir)
    }

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Create Blueprint Chain")
    parser.add_argument("--project", required=True, help="Project directory")
    parser.add_argument("--blueprint", required=True, help="Blueprint JSON file")
    args = parser.parse_args()
    
    project_dir = Path(args.project)
    blueprint_path = Path(args.blueprint)
    
    if not blueprint_path.exists():
        print(f"Error: Blueprint not found: {blueprint_path}")
        sys.exit(1)
    
    result = create_blueprint_chain(str(project_dir), str(blueprint_path))
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
