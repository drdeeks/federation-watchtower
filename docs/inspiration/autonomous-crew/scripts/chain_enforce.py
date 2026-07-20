#!/usr/bin/env python3
"""
Chain enforcement wrapper for kanban workers.
Usage:
  chain_enforce.py check <project> <phase_num>    — Check if phase is active
  chain_enforce.py complete <project> <phase_num> — Verify + complete phase
  chain_enforce.py status <project>               — Show chain status

Project names: aires, autopilot, agora, edgewalker, mnemosyne
Looks for chains in: ${WORKSPACE_ROOT}/qwen-cloud-2026/<project>/.chain/
"""
import json
import sys
import os
import subprocess

CHAIN_SCRIPT = os.path.expanduser("~/.hermes/skills/devops/loop-enforcer/scripts/chain.py")
PROJECT_BASE = "${WORKSPACE_ROOT}/qwen-cloud-2026"

def find_chain(project_dir):
    """Find the blueprint chain JSON file."""
    # Check both .chain and .blueprint-chain directories
    for chain_dir_name in [".blueprint-chain", ".chain"]:
        chain_dir = os.path.join(project_dir, chain_dir_name)
        if not os.path.isdir(chain_dir):
            continue
        for f in os.listdir(chain_dir):
            if f.endswith(".json") and "blueprint" in f:
                chain_path = os.path.join(chain_dir, f)
                with open(chain_path) as fh:
                    data = json.load(fh)
                return data["name"], chain_path
    return None, None

def find_step_for_phase(chain_data, phase_num):
    """Find the chain step index for a given phase number."""
    for i, step in enumerate(chain_data["steps"]):
        path = step.get("path", "")
        # Match phase number in the path
        if f"phase-{phase_num:02d}" in path.lower() or f"phase-{phase_num}" in path.lower():
            # Return the main phase step (not sub-steps)
            if "step-" not in path.lower():
                return i, step
    # Fallback: look for marker files
    for i, step in enumerate(chain_data["steps"]):
        path = step.get("path", "")
        if f"phase_{phase_num}" in path.lower() or f"phase-{phase_num}" in path.lower():
            if "step-" not in path.lower():
                return i, step
    return None, None

def run_chain_cmd(cmd, project_dir, chain_name, marker_path):
    """Run a chain.py command."""
    result = subprocess.run(
        ["python3", CHAIN_SCRIPT, cmd, project_dir, chain_name, marker_path],
        capture_output=True, text=True
    )
    return result.stdout.strip(), result.returncode

def cmd_check(project, phase_num):
    """Check if a phase is active and can be worked on."""
    project_dir = os.path.join(PROJECT_BASE, project)
    if not os.path.isdir(project_dir):
        print(json.dumps({"ok": False, "error": f"Project directory not found: {project_dir}"}))
        return 1

    chain_name, chain_path = find_chain(project_dir)
    if not chain_name:
        print(json.dumps({"ok": False, "error": f"No chain found in {project_dir}/.chain/"}))
        return 1

    with open(chain_path) as f:
        chain_data = json.load(f)

    idx, step = find_step_for_phase(chain_data, phase_num)
    if idx is None:
        print(json.dumps({"ok": False, "error": f"Phase {phase_num} not found in chain {chain_name}"}))
        return 1

    marker_path = step["path"]
    state = step["state"]

    output, rc = run_chain_cmd("check", project_dir, chain_name, marker_path)

    result = {
        "ok": True,
        "chain": chain_name,
        "phase": phase_num,
        "step_index": idx,
        "state": state,
        "marker": marker_path,
        "can_proceed": state == "active",
        "chain_output": output
    }
    print(json.dumps(result, indent=2))
    return 0 if state == "active" else 1

def cmd_complete(project, phase_num):
    """Verify and complete a phase, unlocking the next one."""
    project_dir = os.path.join(PROJECT_BASE, project)
    chain_name, chain_path = find_chain(project_dir)
    if not chain_name:
        print(json.dumps({"ok": False, "error": f"No chain found"}))
        return 1

    with open(chain_path) as f:
        chain_data = json.load(f)

    idx, step = find_step_for_phase(chain_data, phase_num)
    if idx is None:
        print(json.dumps({"ok": False, "error": f"Phase {phase_num} not found"}))
        return 1

    marker_path = step["path"]

    # Create marker file if it doesn't exist
    os.makedirs(os.path.dirname(marker_path), exist_ok=True)
    if not os.path.exists(marker_path):
        with open(marker_path, "w") as f:
            f.write(f"Phase {phase_num} completed\n")

    # Verify
    v_out, v_rc = run_chain_cmd("verify", project_dir, chain_name, marker_path)
    if v_rc != 0:
        print(json.dumps({"ok": False, "error": f"Verify failed: {v_out}"}))
        return 1

    # Complete
    c_out, c_rc = run_chain_cmd("complete", project_dir, chain_name, marker_path)
    if c_rc != 0:
        print(json.dumps({"ok": False, "error": f"Complete failed: {c_out}"}))
        return 1

    result = {
        "ok": True,
        "chain": chain_name,
        "phase": phase_num,
        "verified": True,
        "completed": True,
        "verify_output": v_out,
        "complete_output": c_out
    }
    print(json.dumps(result, indent=2))
    return 0

def cmd_status(project):
    """Show chain status for a project."""
    project_dir = os.path.join(PROJECT_BASE, project)
    chain_name, chain_path = find_chain(project_dir)
    if not chain_name:
        print(json.dumps({"ok": False, "error": f"No chain found"}))
        return 1

    with open(chain_path) as f:
        chain_data = json.load(f)

    steps = []
    for i, s in enumerate(chain_data["steps"]):
        steps.append({
            "index": i,
            "state": s["state"],
            "path": s.get("path", "?")
        })

    done = sum(1 for s in steps if s["state"] == "complete")
    active = sum(1 for s in steps if s["state"] == "active")
    locked = sum(1 for s in steps if s["state"] == "locked")

    result = {
        "ok": True,
        "chain": chain_name,
        "total": len(steps),
        "done": done,
        "active": active,
        "locked": locked,
        "progress": f"{done}/{len(steps)}",
        "steps": steps
    }
    print(json.dumps(result, indent=2))
    return 0

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]
    project = sys.argv[2]

    if cmd == "check" and len(sys.argv) >= 4:
        sys.exit(cmd_check(project, int(sys.argv[3])))
    elif cmd == "complete" and len(sys.argv) >= 4:
        sys.exit(cmd_complete(project, int(sys.argv[3])))
    elif cmd == "status":
        sys.exit(cmd_status(project))
    else:
        print(__doc__)
        sys.exit(1)
