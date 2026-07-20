#!/usr/bin/env python3
"""
apply_blueprint.py — Main entry point for blueprint enforcement

Applies enterprise blueprint to target (agent dir, crew dir, or project dir).
Generates checklist, initializes loop-enforcer chain (optional), assigns agents.

Usage:
    # Single agent directory
    python3 apply_blueprint.py --target ./my-agent --blueprint ./blueprint.md
    
    # Crew directory (auto-discovers all agents)
    python3 apply_blueprint.py --crew ./my-crew --blueprint ./blueprint.md
    
    # Specific agents in crew
    python3 apply_blueprint.py --crew ./my-crew --agents ui,blockchain --blueprint ./blueprint.md
    
    # Opt-out of loop enforcement (just checklist + assignments)
    python3 apply_blueprint.py --target ./my-agent --blueprint ./blueprint.md --no-loop-enforcement
    
    # Non-interactive (CI/agent mode)
    python3 apply_blueprint.py --crew ./my-crew --blueprint ./blueprint.md --noninteractive
"""

import json
import subprocess
import sys
from pathlib import Path

from skill_paths import resolve_loop_enforcer

OWN_SCRIPTS_DIR = Path(__file__).resolve().parent


def resolve_own_script(script_name: str) -> Path:
    """Path to a script that always sits alongside this one (same skill)."""
    return OWN_SCRIPTS_DIR / script_name


def run_cmd(cmd: list, cwd: Path = None, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    """Run command with consistent error handling."""
    result = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=capture,
        text=True
    )
    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, cmd, result.stdout, result.stderr)
    return result


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Apply enterprise blueprint to target workspace",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Single agent
  python3 apply_blueprint.py --target ./my-agent --blueprint ./blueprint.md
  
  # Crew (all agents)
  python3 apply_blueprint.py --crew ./my-crew --blueprint ./blueprint.md
  
  # Subset of crew agents
  python3 apply_blueprint.py --crew ./my-crew --agents ui,blockchain --blueprint ./blueprint.md
  
  # Opt-out of loop enforcement (checklist + assignments only)
  python3 apply_blueprint.py --target ./my-agent --blueprint ./blueprint.md --no-loop-enforcement
  
  # CI/non-interactive mode
  python3 apply_blueprint.py --crew ./my-crew --blueprint ./blueprint.md --noninteractive
"""
    )
    
    # Target selection (mutually exclusive)
    target_group = parser.add_mutually_exclusive_group(required=True)
    target_group.add_argument("--target", help="Single agent/project directory")
    target_group.add_argument("--crew", help="Crew directory (auto-discovers agents)")
    
    parser.add_argument("--agents", help="Comma-separated agent IDs (subset of crew)")
    parser.add_argument("--blueprint", required=True, help="Blueprint markdown file")
    parser.add_argument("--model-map", help="Agent model map YAML (optional)")
    parser.add_argument("--output", help="Output directory (default: target directory)")
    parser.add_argument("--no-loop-enforcement", action="store_true", 
                        help="Skip loop-enforcer chain initialization (checklist + assignments only)")
    parser.add_argument("--noninteractive", action="store_true", help="Agent/CI mode - no prompts")
    parser.add_argument("--dry-run", action="store_true", help="Plan only, no writes")
    parser.add_argument("--json", action="store_true", help="JSON output")
    
    args = parser.parse_args()
    
    # Resolve paths
    blueprint_path = Path(args.blueprint).resolve()
    
    if not blueprint_path.exists():
        sys.exit(f"ERROR: Blueprint not found: {blueprint_path}")
    
    # Discover target agents
    target_agents = []
    target_type = None
    base_dir = None
    
    if args.target:
        target_dir = Path(args.target).resolve()
        base_dir = target_dir
        
        # Discover identity
        result = run_cmd([
            sys.executable,
            str(resolve_own_script("discover_agents.py")),
            str(target_dir), "--json"
        ], capture=True)
        
        identity = json.loads(result.stdout)
        
        if identity["type"] == "agent":
            target_type = "agent"
            target_agents = [{
                "agent_id": identity["agent_id"],
                "agent_type": identity["agent_type"],
                "path": str(target_dir),
                "sub_agents": identity.get("sub_agents", [])
            }]
        elif identity["type"] == "crew":
            # Target is a crew dir but --target used instead of --crew
            target_type = "crew"
            target_agents = identity["agents"]
        else:
            target_type = "project"
            target_agents = [{"agent_id": target_dir.name, "agent_type": "project", "path": str(target_dir)}]
    
    elif args.crew:
        crew_dir = Path(args.crew).resolve()
        base_dir = crew_dir
        
        result = run_cmd([
            sys.executable,
            str(resolve_own_script("discover_agents.py")),
            str(crew_dir), "--json"
        ], capture=True)
        
        identity = json.loads(result.stdout)
        
        if identity["type"] != "crew":
            sys.exit(f"ERROR: --crew specified but directory is not a valid crew: {crew_dir}")
        
        target_type = "crew"
        all_agents = identity["agents"]
        
        if args.agents:
            requested = set(args.agents.split(","))
            target_agents = [a for a in all_agents if a["agent_id"] in requested]
            missing = requested - {a["agent_id"] for a in target_agents}
            if missing:
                sys.exit(f"ERROR: Agents not found in crew: {', '.join(missing)}")
        else:
            target_agents = all_agents
    
    # Output directory
    output_dir = Path(args.output).resolve() if args.output else base_dir
    
    # Summary
    summary = {
        "blueprint": str(blueprint_path),
        "target_type": target_type,
        "target_agents": len(target_agents),
        "agents": [a["agent_id"] for a in target_agents],
        "loop_enforcement": not args.no_loop_enforcement,
        "dry_run": args.dry_run,
        "output_dir": str(output_dir)
    }
    
    if args.json:
        print(json.dumps(summary, indent=2))
    
    if args.dry_run:
        print("[DRY RUN] Would apply blueprint to:")
        for agent in target_agents:
            print(f"  - {agent['agent_id']} ({agent['agent_type']}) at {agent['path']}")
        print(f"  Loop enforcement: {'enabled' if not args.no_loop_enforcement else 'disabled'}")
        return 0
    
    # Process each agent
    generate_cl = resolve_own_script("generate_checklist.py")
    assign_agents = resolve_own_script("assign_agents.py")
    loop_enforcer = resolve_loop_enforcer()
    
    for agent in target_agents:
        agent_dir = Path(agent["path"]).resolve()
        agent_id = agent["agent_id"]
        
        print(f"\n=== Processing {agent_id} ({agent['agent_type']}) ===")
        
        # 1. Generate checklist in agent directory
        checklist_path = agent_dir / "checklist.md"
        print(f"  Generating checklist: {checklist_path}")
        
        run_cmd([
            sys.executable, str(generate_cl),
            str(blueprint_path),
            "--output", str(checklist_path)
        ])
        
        # 2. Initialize loop-enforcer chain (unless opted out)
        if not args.no_loop_enforcement:
            chain_dir = agent_dir / ".blueprint-chain"
            print(f"  Initializing loop-enforcer chain: {chain_dir}")
            
            run_cmd([
                sys.executable, str(generate_cl), str(agent_dir), "--init",
                "--json"
            ])
            
            # Verify chain created
            state_dir = agent_dir / ".blueprint-chain"
            if state_dir.exists():
                print(f"    ✓ Chain created: {state_dir}")
            else:
                print(f"    ⚠ Chain state not found at expected path")
        
        # 3. Assign scopes (if model-map provided)
        if args.model_map:
            assignments_path = agent_dir / "assignments.json"
            print(f"  Creating assignments: {assignments_path}")
            
            # Prepare agents data for assign_agents.py
            agents_data = {
                "agents": target_agents,
                "model_map": args.model_map
            }
            
            run_cmd([
                sys.executable, str(assign_agents),
                str(agent_dir),
                "--model-map", args.model_map,
                "--output", str(assignments_path)
            ], check=False)  # assign_agents may not have --model-map yet
    
    # Final summary
    print(f"\n✓ Blueprint applied to {len(target_agents)} agent(s)")
    print(f"  Checklist: checklist.md in each agent directory")
    if not args.no_loop_enforcement:
        print(f"  Chain: .blueprint-chain/ (managed by loop-enforcer)")
        print(f"  Worker API: chain_worker.py check/verify/complete")
    print(f"  Assignments: assignments.json (if model-map provided)")
    
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Command failed: {' '.join(e.cmd)}", file=sys.stderr)
        print(e.stderr, file=sys.stderr)
        sys.exit(e.returncode)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)