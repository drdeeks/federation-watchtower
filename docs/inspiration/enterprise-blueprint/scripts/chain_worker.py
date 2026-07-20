#!/usr/bin/env python3
"""
chain_worker.py — Real registered plugin interface for agent→loop-enforcer

This is NOT a suggested string — it's a real callable plugin that agents
invoke via pre-tool-call hooks. The enforcer daemon routes through this.

Forever System §5: "A plugin is a registered, loadable unit the running
system actually calls. AIK's Hermes/OpenCode hook is currently a suggestion
in a string. That is NOT integration. It must become a real registered
plugin before it counts."

Usage (agent calls via pre-tool-call hook):
  python3 chain_worker.py check .blueprint-chain PHASE-3.2
  python3 chain_worker.py verify .blueprint-chain PHASE-3.2
  python3 chain_worker.py complete .blueprint-chain PHASE-3.2

Environment (self-resolving paths §2):
  LOOP_ENFORCER_ROOT → /path/to/loop-enforcer (default: ~/.hermes/skills/devops/loop-enforcer)
  ENFORCER_SOCKET → /run/ack-enforcer.sock (for daemon connection)
"""

import json
import os
import sys
import subprocess
from pathlib import Path


def resolve_loop_enforcer() -> Path:
    """Self-resolving path to loop-enforcer chain.py (§2)."""
    env_root = os.environ.get("LOOP_ENFORCER_ROOT")
    if env_root:
        chain_py = Path(env_root) / "scripts" / "chain.py"
        if chain_py.exists():
            return chain_py
    
    # Default: Hermes skills directory
    skills_root = Path(os.environ.get("HERMES_SKILLS_ROOT", 
        Path.home() / ".hermes" / "skills"))
    chain_py = skills_root / "devops" / "loop-enforcer" / "scripts" / "chain.py"
    if chain_py.exists():
        return chain_py
    
    # Fallback: relative to this script
    chain_py = Path(__file__).parent.parent.parent / "loop-enforcer" / "scripts" / "chain.py"
    if chain_py.exists():
        return chain_py
    
    raise FileNotFoundError(
        "loop-enforcer chain.py not found. Set LOOP_ENFORCER_ROOT env var."
    )


def run_chain_cmd(cmd: str, chain_dir: str, chain_name: str, step: str, extra: list = None) -> dict:
    """Execute loop-enforcer chain.py command and return parsed JSON."""
    chain_py = resolve_loop_enforcer()
    
    # chain.py expects project_dir (parent of .blueprint-chain), not chain_dir itself
    chain_dir_path = Path(chain_dir)
    if chain_dir_path.name == ".blueprint-chain":
        project_dir = str(chain_dir_path.parent)
    else:
        project_dir = str(chain_dir_path)
    
    args = [sys.executable, str(chain_py), cmd, project_dir, chain_name, step]
    if extra:
        args.extend(extra)
    
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            try:
                return json.loads(result.stdout)
            except json.JSONDecodeError:
                return {"error": "Invalid JSON from chain.py", "raw": result.stdout}
        else:
            return {"error": result.stderr.strip() or f"Exit code {result.returncode}", "exit_code": result.returncode}
    except subprocess.TimeoutExpired:
        return {"error": "chain.py timeout (30s)"}
    except FileNotFoundError:
        return {"error": f"chain.py not found at {chain_py}"}
    except Exception as e:
        return {"error": str(e)}


def check(chain_dir: str, step: str, chain_name: str = None) -> dict:
    """
    Check step state. Agent calls before starting work.
    
    Returns: {"path": "...", "state": "active|locked|verified|complete", "index": N}
    """
    if chain_name is None:
        # Find the chain name from the chain directory
        chain_name = find_chain_name(chain_dir)
    return run_chain_cmd("check", chain_dir, chain_name, step)

def verify(chain_dir: str, step: str, validator_args: list = None, chain_name: str = None) -> dict:
    """
    Verify step completion. Runs validator if configured.
    Agent calls after completing deliverables.
    
    Returns: {"ok": true|false, "path": "...", "state": "verified|active", "output": "..."}
    """
    if chain_name is None:
        chain_name = find_chain_name(chain_dir)
    
    # Set validator if provided
    if validator_args:
        run_chain_cmd("set-validator", chain_dir, chain_name, step, validator_args)
    
    return run_chain_cmd("verify", chain_dir, chain_name, step)


def complete(chain_dir: str, step: str, chain_name: str = None) -> dict:
    """
    Mark step complete. Activates next step in chain.
    Agent calls after verification passes.
    
    Returns: {"ok": true, "path": "...", "state": "complete", "next_step": "..."}
    """
    if chain_name is None:
        chain_name = find_chain_name(chain_dir)
    return run_chain_cmd("complete", chain_dir, chain_name, step)


def status(chain_dir: str, chain_name: str = None) -> dict:
    """Get full chain status. Agent can call for dashboard."""
    if chain_name is None:
        chain_name = find_chain_name(chain_dir)
    return run_chain_cmd("status", chain_dir, chain_name, "")


def add_step(chain_dir: str, step_path: str, chain_name: str = None) -> dict:
    """Add a step to existing chain (for dynamic checklists)."""
    if chain_name is None:
        chain_name = find_chain_name(chain_dir)
    return run_chain_cmd("add", chain_dir, chain_name, step_path)


def find_chain_name(chain_dir: str) -> str:
    """Find the correct chain name from the chain directory."""
    chain_dir_path = Path(chain_dir)
    if chain_dir_path.name == ".blueprint-chain":
        project_dir = chain_dir_path.parent
    else:
        project_dir = chain_dir_path
    
    chain_state_dir = project_dir / ".chain"
    if chain_state_dir.exists():
        for f in chain_state_dir.glob("*.json"):
            if not f.name.endswith(".log"):
                return f.stem
    
    # Fallback: use blueprint-<project-name>
    return f"blueprint-{project_dir.name}"


def main():
    """CLI entry point for direct agent invocation."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Chain Worker Plugin — Agent interface to loop-enforcer",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Check if step is active
  python3 chain_worker.py check .blueprint-chain PHASE-3.2
  
  # Verify work (runs validator)
  python3 chain_worker.py verify .blueprint-chain PHASE-3.2
  
  # Mark complete (activates next step)
  python3 chain_worker.py complete .blueprint-chain PHASE-3.2
  
  # Full chain status
  python3 chain_worker.py status .blueprint-chain
  
  # Set validator then verify
  python3 chain_worker.py verify .blueprint-chain PHASE-3.2 --validator test-runner.py --arg integration
"""
    )
    
    parser.add_argument("action", choices=["check", "verify", "complete", "status", "add"],
                        help="Action to perform")
    parser.add_argument("chain_dir", help="Chain directory (e.g., .blueprint-chain)")
    parser.add_argument("step", nargs="?", help="Step path (required for check/verify/complete/add)")
    parser.add_argument("--chain-name", help="Chain name (default: bp-<project>)")
    parser.add_argument("--validator", action="append", dest="validator_args",
                        help="Validator script + args (can repeat for verify)")
    parser.add_argument("--json", action="store_true", help="JSON output (default)")
    
    args = parser.parse_args()
    
    if args.action in ("check", "verify", "complete", "add") and not args.step:
        parser.error(f"{args.action} requires step argument")
    
    if args.action == "check":
        result = check(args.chain_dir, args.step, args.chain_name)
    elif args.action == "verify":
        result = verify(args.chain_dir, args.step, args.validator_args, args.chain_name)
    elif args.action == "complete":
        result = complete(args.chain_dir, args.step, args.chain_name)
    elif args.action == "status":
        result = status(args.chain_dir, args.chain_name)
    elif args.action == "add":
        result = add_step(args.chain_dir, args.step, args.chain_name)
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        # Human readable
        if "error" in result:
            print(f"ERROR: {result['error']}", file=sys.stderr)
            sys.exit(1)
        else:
            print(json.dumps(result, indent=2))
    
    # Exit code based on result
    if args.action == "verify":
        sys.exit(0 if result.get("ok") else 1)
    elif args.action == "check":
        sys.exit(0 if result.get("state") in ("active", "pending_verify") else 1)
    else:
        sys.exit(0 if "error" not in result else 1)


if __name__ == "__main__":
    main()