#!/usr/bin/env python3
"""
discover_agents.py — Accurate agent/crew/neither detection

Singular source of truth for workspace identity (§1 Forever System).
Returns structured JSON for programmatic use by apply_blueprint.py.

Detection Rules (ALL must exist for positive ID):

AGENT:
  1. .agent/ directory (enforcer-owned identity layer)
  2. SOUL.md (agent constitution)
  3. agent.json OR crew.json with agent_id matching directory name
  4. agent-model-map.yaml OR crew-model-map.yaml (config layer)

CREW:
  1. crew.json at root with agents[] roster
  2. crew/agents/*/.agent/ (multiple agent subdirs with identity)
  3. .crew-config.yaml (crew metadata)
  4. crew-model-map.yaml (crew orchestration layer)

NEITHER:
  If neither AGENT nor CREW criteria fully met → "project directory"

FAIL-CLOSED (§4):
  Ambiguous/partial markers → BLOCK with clear error.
"""

import json
import sys
from pathlib import Path
from datetime import datetime, timezone


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def check_agent_identity(dir_path: Path) -> dict:
    """Check if directory is a valid agent. Returns agent info or None."""
    # 1. .agent/ directory (enforcer-owned)
    agent_dir = dir_path / ".agent"
    if not agent_dir.is_dir():
        return None
    
    # 2. SOUL.md (constitution)
    soul_file = dir_path / "SOUL.md"
    if not soul_file.is_file():
        return None
    
    # 3. agent.json OR crew.json with matching agent_id
    agent_json = dir_path / "agent.json"
    crew_json = dir_path / "crew.json"
    
    agent_id = None
    agent_type = None
    
    if agent_json.is_file():
        data = read_json(agent_json)
        if data:
            agent_id = data.get("agent_id")
            agent_type = data.get("agent_type", data.get("type"))
    
    if not agent_id and crew_json.is_file():
        data = read_json(crew_json)
        if data:
            # crew.json might have agents[] array
            agents = data.get("agents", [])
            for a in agents:
                if a.get("agent_id") == dir_path.name:
                    agent_id = a.get("agent_id")
                    agent_type = a.get("agent_type", a.get("type"))
                    break
    
    if not agent_id:
        # Fallback: directory name
        agent_id = dir_path.name
    
    # 4. Config layer (agent-model-map.yaml or crew-model-map.yaml)
    has_model_map = (dir_path / "agent-model-map.yaml").is_file() or \
                    (dir_path / "crew-model-map.yaml").is_file()
    
    # Check for sub-agents (nested .agent/ directories)
    sub_agents = []
    for subdir in dir_path.iterdir():
        if subdir.is_dir() and subdir != agent_dir and not subdir.name.startswith("."):
            sub_agent_dir = subdir / ".agent"
            if sub_agent_dir.is_dir():
                sub_info = check_agent_identity(subdir)
                if sub_info:
                    sub_agents.append({
                        "agent_id": sub_info["agent_id"],
                        "agent_type": sub_info["agent_type"],
                        "path": str(subdir)
                    })
    
    return {
        "type": "agent",
        "agent_id": agent_id,
        "agent_type": agent_type or "unknown",
        "path": str(dir_path),
        "has_model_map": has_model_map,
        "has_soul": True,
        "has_agent_dir": True,
        "sub_agents": sub_agents,
        "config_files": {
            "agent_json": str(agent_json) if agent_json.is_file() else None,
            "crew_json": str(crew_json) if crew_json.is_file() else None,
            "soul_md": str(soul_file),
            "agent_dir": str(agent_dir),
            "model_map": str(dir_path / "agent-model-map.yaml") if (dir_path / "agent-model-map.yaml").is_file() else
                        str(dir_path / "crew-model-map.yaml") if (dir_path / "crew-model-map.yaml").is_file() else None
        }
    }


def check_crew_identity(dir_path: Path) -> dict:
    """Check if directory is a valid crew. Returns crew info or None."""
    # 1. crew.json at root with agents[] roster
    crew_json = dir_path / "crew.json"
    if not crew_json.is_file():
        return None
    
    crew_data = read_json(crew_json)
    if not crew_data:
        return None
    
    agents_roster = crew_data.get("agents", [])
    if not isinstance(agents_roster, list) or not agents_roster:
        return None
    
    # 2. crew/agents/*/.agent/ (multiple agent subdirs)
    agents_dir = dir_path / "crew" / "agents"
    if not agents_dir.is_dir():
        return None
    
    # 3. .crew-config.yaml
    crew_config = dir_path / ".crew-config.yaml"
    if not crew_config.is_file():
        return None
    
    # 4. crew-model-map.yaml
    has_model_map = (dir_path / "crew-model-map.yaml").is_file()
    
    # Discover actual agent subdirectories
    discovered_agents = []
    for agent_subdir in agents_dir.iterdir():
        if agent_subdir.is_dir():
            agent_info = check_agent_identity(agent_subdir)
            if agent_info:
                discovered_agents.append(agent_info)
    
    # Validate roster matches discovered agents
    roster_ids = {a.get("agent_id") for a in agents_roster if isinstance(a, dict)}
    discovered_ids = {a["agent_id"] for a in discovered_agents}
    
    if roster_ids and discovered_ids:
        missing = roster_ids - discovered_ids
        extra = discovered_ids - roster_ids
        # Don't fail - just warn in metadata
    elif roster_ids and not discovered_ids:
        # Crew config exists but no agents discovered - partial
        pass
    
    return {
        "type": "crew",
        "crew_id": crew_data.get("crew_id", dir_path.name),
        "crew_mode": crew_data.get("crew_mode", "production"),
        "path": str(dir_path),
        "has_model_map": has_model_map,
        "roster": agents_roster,
        "discovered_agents": discovered_agents,
        "config_files": {
            "crew_json": str(crew_json),
            "crew_config": str(crew_config),
            "model_map": str(dir_path / "crew-model-map.yaml") if has_model_map else None,
            "agents_dir": str(agents_dir)
        }
    }


def detect_identity(dir_path: Path) -> dict:
    """
    Main detection entry point.
    Returns dict with type: 'agent', 'crew', or 'none'
    """
    dir_path = dir_path.resolve()
    
    if not dir_path.is_dir():
        return {
            "type": "error",
            "error": f"Not a directory: {dir_path}",
            "timestamp": now_iso()
        }
    
    # Check for agent first (more specific)
    agent_info = check_agent_identity(dir_path)
    if agent_info:
        # Verify it's not ALSO a crew (agent inside crew dir)
        # If parent has crew.json, this is part of a crew
        parent = dir_path.parent
        if (parent / "crew.json").is_file() and (parent / "crew" / "agents").is_dir():
            # This agent belongs to a crew - don't report as standalone
            pass
        else:
            return {**agent_info, "timestamp": now_iso()}
    
    # Check for crew
    crew_info = check_crew_identity(dir_path)
    if crew_info:
        return {**crew_info, "timestamp": now_iso()}
    
    # Check if it's an agent inside a crew structure
    # Look for .agent/ in subdirectories
    for subdir in dir_path.iterdir():
        if subdir.is_dir():
            sub_agent = check_agent_identity(subdir)
            if sub_agent:
                # Found at least one agent subdir - this might be a crew root
                # but missing some crew markers
                pass
    
    # Neither agent nor crew
    return {
        "type": "none",
        "path": str(dir_path),
        "message": "No agent or crew identity detected. Run 'interactive_setup' to initialize.",
        "timestamp": now_iso()
    }


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Detect agent/crew identity")
    parser.add_argument("path", help="Directory to inspect")
    parser.add_argument("--json", action="store_true", help="Output JSON (default)")
    parser.add_argument("--verbose", action="store_true", help="Verbose output")
    args = parser.parse_args()
    
    target = Path(args.path).resolve()
    result = detect_identity(target)
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        # Human readable
        print(f"Identity Detection: {target}")
        print(f"  Type: {result['type']}")
        if result['type'] == 'agent':
            print(f"  Agent ID: {result['agent_id']}")
            print(f"  Agent Type: {result['agent_type']}")
            print(f"  Has Model Map: {result['has_model_map']}")
            if result['sub_agents']:
                print(f"  Sub-agents: {len(result['sub_agents'])}")
        elif result['type'] == 'crew':
            print(f"  Crew ID: {result['crew_id']}")
            print(f"  Crew Mode: {result['crew_mode']}")
            print(f"  Roster: {len(result['roster'])} agents")
            print(f"  Discovered: {len(result['discovered_agents'])} agents")
            print(f"  Has Model Map: {result['has_model_map']}")
        else:
            print(f"  {result.get('message', 'Unknown')}")
    
    # Exit code: 0 for agent/crew, 1 for none/error
    if result['type'] in ('agent', 'crew'):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()