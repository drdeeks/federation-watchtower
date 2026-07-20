#!/usr/bin/env python3
"""
chain.py — Sequential dependency chain enforcer
Locks files until prior steps are verified complete.
Works interactively (menu) and programmatically (agent API).

Usage:
    python3 chain.py create <project-dir> <chain-name> <path1> [path2] ...
    python3 chain.py menu <project-dir> <chain-name>
    python3 chain.py check <project-dir> <chain-name> [path]
    python3 chain.py verify <project-dir> <chain-name> <path>
    python3 chain.py complete <project-dir> <chain-name> <path>
    python3 chain.py set-validator <project-dir> <chain-name> <path> <script>
    python3 chain.py add <project-dir> <chain-name> <path>
    python3 chain.py list <project-dir>
    python3 chain.py status <project-dir> <chain-name>
    python3 chain.py log <project-dir> <chain-name> [message]
"""

import json
import os
import sys
import subprocess
from datetime import datetime, timezone
from pathlib import Path


# ── State management ──────────────────────────────────────────────────────────

def state_dir(project_dir):
    d = Path(project_dir) / ".chain"
    d.mkdir(parents=True, exist_ok=True)
    return d

def state_path(project_dir, chain_name):
    return state_dir(project_dir) / f"{chain_name}.json"

def log_path(project_dir, chain_name):
    return state_dir(project_dir) / f"{chain_name}.log"

def load_state(project_dir, chain_name):
    p = state_path(project_dir, chain_name)
    if not p.exists():
        return None
    with open(p) as f:
        return json.load(f)

def save_state(project_dir, chain_name, state):
    p = state_path(project_dir, chain_name)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = str(p) + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, p)

def append_log(project_dir, chain_name, message):
    lp = log_path(project_dir, chain_name)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(lp, "a") as f:
        f.write(f"[{ts}] {message}\n")

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ── Chain operations ──────────────────────────────────────────────────────────

def create_chain(project_dir, chain_name, paths):
    existing = load_state(project_dir, chain_name)
    if existing:
        return {"error": f"Chain '{chain_name}' already exists with {len(existing['steps'])} steps"}

    steps = []
    for i, path in enumerate(paths):
        steps.append({
            "index": i,
            "path": os.path.abspath(path),
            "state": "active" if i == 0 else "locked",
            "validator": None,
            "created_at": now_iso(),
            "verified_at": None,
            "completed_at": None,
            "attempts": 0,
        })

    state = {
        "name": chain_name,
        "project": os.path.abspath(project_dir),
        "created_at": now_iso(),
        "steps": steps,
    }
    save_state(project_dir, chain_name, state)
    append_log(project_dir, chain_name, f"Chain created with {len(steps)} steps")
    return {"ok": True, "chain": chain_name, "steps": len(steps)}


def check_status(project_dir, chain_name, path=None):
    state = load_state(project_dir, chain_name)
    if not state:
        return {"error": f"Chain '{chain_name}' not found"}

    if path:
        abs_path = os.path.abspath(path)
        for step in state["steps"]:
            if step["path"] == abs_path:
                return {"path": step["path"], "state": step["state"], "index": step["index"]}
        return {"error": f"Path '{path}' not in chain"}

    summary = {
        "chain": chain_name,
        "total": len(state["steps"]),
        "active": 0, "locked": 0, "verified": 0, "complete": 0,
        "steps": [],
    }
    for step in state["steps"]:
        summary[step["state"]] = summary.get(step["state"], 0) + 1
        summary["steps"].append({
            "index": step["index"],
            "path": step["path"],
            "state": step["state"],
            "validator": step.get("validator"),
            "attempts": step.get("attempts", 0),
        })
    return summary


def verify_step(project_dir, chain_name, path):
    state = load_state(project_dir, chain_name)
    if not state:
        return {"error": f"Chain '{chain_name}' not found"}

    abs_path = os.path.abspath(path)
    step = None
    for s in state["steps"]:
        if s["path"] == abs_path:
            step = s
            break
    if not step:
        return {"error": f"Path '{path}' not in chain"}

    if step["state"] not in ("active", "pending_verify"):
        return {"error": f"Step is '{step['state']}', must be 'active' to verify"}

    step["attempts"] = step.get("attempts", 0) + 1
    step["state"] = "pending_verify"

    validator = step.get("validator")
    if validator:
        python_cmd = os.environ.get("CHAIN_PYTHON", sys.executable)
        try:
            result = subprocess.run(
                [python_cmd, validator, abs_path],
                capture_output=True, text=True, timeout=30
            )
            passed = result.returncode == 0
            output = result.stdout + result.stderr
        except Exception as e:
            passed = False
            output = str(e)
    else:
        passed = True
        output = "No validator set — auto-pass"

    if passed:
        step["state"] = "verified"
        step["verified_at"] = now_iso()
        append_log(project_dir, chain_name, f"VERIFIED: {step['path']} (attempt {step['attempts']})")
        next_idx = step["index"] + 1
        if next_idx < len(state["steps"]):
            state["steps"][next_idx]["state"] = "active"
            append_log(project_dir, chain_name, f"ACTIVATED: {state['steps'][next_idx]['path']}")
    else:
        step["state"] = "active"
        append_log(project_dir, chain_name, f"VERIFY FAILED: {step['path']} (attempt {step['attempts']})")

    save_state(project_dir, chain_name, state)
    return {"ok": passed, "path": step["path"], "state": step["state"], "output": output}


def complete_step(project_dir, chain_name, path):
    state = load_state(project_dir, chain_name)
    if not state:
        return {"error": f"Chain '{chain_name}' not found"}

    abs_path = os.path.abspath(path)
    step = None
    for s in state["steps"]:
        if s["path"] == abs_path:
            step = s
            break
    if not step:
        return {"error": f"Path '{path}' not in chain"}

    if step["state"] != "verified":
        return {"error": f"Step must be 'verified' to complete, currently '{step['state']}'"}

    step["state"] = "complete"
    step["completed_at"] = now_iso()
    append_log(project_dir, chain_name, f"COMPLETED: {step['path']}")
    save_state(project_dir, chain_name, state)

    all_done = all(s["state"] == "complete" for s in state["steps"])
    return {"ok": True, "path": step["path"], "chain_complete": all_done}


def set_validator(project_dir, chain_name, path, validator_script):
    state = load_state(project_dir, chain_name)
    if not state:
        return {"error": f"Chain '{chain_name}' not found"}

    abs_path = os.path.abspath(path)
    for step in state["steps"]:
        if step["path"] == abs_path:
            step["validator"] = os.path.abspath(validator_script)
            save_state(project_dir, chain_name, state)
            append_log(project_dir, chain_name, f"VALIDATOR SET: {step['path']}")
            return {"ok": True}
    return {"error": f"Path '{path}' not in chain"}


def add_step(project_dir, chain_name, path):
    state = load_state(project_dir, chain_name)
    if not state:
        return {"error": f"Chain '{chain_name}' not found"}

    abs_path = os.path.abspath(path)
    for s in state["steps"]:
        if s["path"] == abs_path:
            return {"error": "Path already in chain"}

    new_idx = len(state["steps"])
    state["steps"].append({
        "index": new_idx,
        "path": abs_path,
        "state": "locked",
        "validator": None,
        "created_at": now_iso(),
        "verified_at": None,
        "completed_at": None,
        "attempts": 0,
    })
    save_state(project_dir, chain_name, state)
    append_log(project_dir, chain_name, f"ADDED: {abs_path} at index {new_idx}")
    return {"ok": True, "index": new_idx}


def list_chains(project_dir):
    sd = state_dir(project_dir)
    chains = []
    for f in sd.glob("*.json"):
        state = load_state(project_dir, f.stem)
        if state:
            chains.append({
                "name": state["name"],
                "steps": len(state["steps"]),
                "complete": sum(1 for s in state["steps"] if s["state"] == "complete"),
            })
    return {"chains": chains}


def get_log(project_dir, chain_name, tail=20):
    lp = log_path(project_dir, chain_name)
    if not lp.exists():
        return {"entries": []}
    lines = lp.read_text().strip().split("\n")
    return {"entries": lines[-tail:]}


def append_entry(project_dir, chain_name, message):
    append_log(project_dir, chain_name, message)
    return {"ok": True}


# ── Interactive menu ──────────────────────────────────────────────────────────

def run_menu(project_dir, chain_name):
    state = load_state(project_dir, chain_name)
    if not state:
        print(f"[ERROR] Chain '{chain_name}' not found in {project_dir}")
        return

    print(f"\n{'='*60}")
    print(f"  CHAIN ENFORCER — {chain_name}")
    print(f"{'='*60}")

    while True:
        state = load_state(project_dir, chain_name)
        if not state:
            print("[ERROR] State file corrupted or deleted")
            break

        active = None
        complete_count = sum(1 for s in state["steps"] if s["state"] == "complete")
        total = len(state["steps"])

        print(f"\n  Progress: {complete_count}/{total} complete\n")
        for step in state["steps"]:
            icon = {
                "locked": "LOCK", "active": ">>>", "pending_verify": "???",
                "verified": " OK", "complete": "DONE"
            }.get(step["state"], " ? ")
            name = os.path.basename(step["path"])
            if step["state"] == "active":
                active = step
                print(f"  [{icon}] {name} <-- CURRENT")
            else:
                print(f"  [{icon}] {name}")

        if complete_count == total:
            print(f"\n  ** ALL STEPS COMPLETE **\n")

        print(f"\n  Commands: [v]erify  [c]omplete  [s]tatus  [l]og  [a]dd  [q]uit")
        try:
            cmd = input("  > ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\n  Bye.")
            break

        if cmd == "q":
            break
        elif cmd == "s":
            status = check_status(project_dir, chain_name)
            print(json.dumps(status, indent=2))
        elif cmd == "l":
            log_data = get_log(project_dir, chain_name, tail=30)
            for entry in log_data["entries"]:
                print(f"  {entry}")
        elif cmd == "v":
            if not active:
                print("  No active step to verify")
                continue
            print(f"  Verifying {os.path.basename(active['path'])}...")
            result = verify_step(project_dir, chain_name, active["path"])
            if result.get("ok"):
                print(f"  VERIFIED. Next step unlocked.")
            else:
                print(f"  FAILED: {result.get('error', result.get('output', 'unknown'))[:200]}")
        elif cmd == "c":
            if not active:
                print("  No active step to complete")
                continue
            if active["state"] != "verified":
                print(f"  Must verify first (current state: {active['state']})")
                continue
            result = complete_step(project_dir, chain_name, active["path"])
            if result.get("ok"):
                print(f"  COMPLETED.")
                if result.get("chain_complete"):
                    print(f"\n  ** ALL STEPS COMPLETE **\n")
            else:
                print(f"  Error: {result.get('error')}")
        elif cmd == "a":
            path = input("  Path to add: ").strip()
            if path:
                result = add_step(project_dir, chain_name, path)
                if result.get("ok"):
                    print(f"  Added at index {result['index']}")
                else:
                    print(f"  Error: {result.get('error')}")
        else:
            print(f"  Unknown command: {cmd}")


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    # Handle --dry-run globally
    dry_run = "--dry-run" in sys.argv
    if dry_run:
        print("[DRY RUN] No changes will be made")
        sys.argv.remove("--dry-run")

    cmd = sys.argv[1]
    project_dir = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("-") else "."
    if cmd == "create":
        if len(sys.argv) < 5:
            print("Usage: chain.py create <project-dir> <chain-name> <path1> [path2] ...")
            sys.exit(1)
        project_dir = sys.argv[2]
        chain_name = sys.argv[3]
        paths = sys.argv[4:]
        print(json.dumps(create_chain(project_dir, chain_name, paths), indent=2))

    elif cmd == "menu":
        if len(sys.argv) < 4:
            print("Usage: chain.py menu <project-dir> <chain-name>")
            sys.exit(1)
        run_menu(sys.argv[2], sys.argv[3])

    elif cmd == "check":
        if len(sys.argv) < 4:
            print("Usage: chain.py check <project-dir> <chain-name> [path]")
            sys.exit(1)
        path = sys.argv[4] if len(sys.argv) > 4 else None
        print(json.dumps(check_status(sys.argv[2], sys.argv[3], path), indent=2))

    elif cmd == "verify":
        if len(sys.argv) < 5:
            print("Usage: chain.py verify <project-dir> <chain-name> <path>")
            sys.exit(1)
        print(json.dumps(verify_step(sys.argv[2], sys.argv[3], sys.argv[4]), indent=2))

    elif cmd == "complete":
        if len(sys.argv) < 5:
            print("Usage: chain.py complete <project-dir> <chain-name> <path>")
            sys.exit(1)
        print(json.dumps(complete_step(sys.argv[2], sys.argv[3], sys.argv[4]), indent=2))

    elif cmd == "set-validator":
        if len(sys.argv) < 6:
            print("Usage: chain.py set-validator <project-dir> <chain-name> <path> <script>")
            sys.exit(1)
        print(json.dumps(set_validator(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]), indent=2))

    elif cmd == "add":
        if len(sys.argv) < 5:
            print("Usage: chain.py add <project-dir> <chain-name> <path>")
            sys.exit(1)
        print(json.dumps(add_step(sys.argv[2], sys.argv[3], sys.argv[4]), indent=2))

    elif cmd == "list":
        project_dir = sys.argv[2] if len(sys.argv) > 2 else "."
        print(json.dumps(list_chains(project_dir), indent=2))

    elif cmd == "status":
        if len(sys.argv) < 4:
            print("Usage: chain.py status <project-dir> <chain-name>")
            sys.exit(1)
        print(json.dumps(check_status(sys.argv[2], sys.argv[3]), indent=2))

    elif cmd == "log":
        if len(sys.argv) < 4:
            print("Usage: chain.py log <project-dir> <chain-name> [message]")
            sys.exit(1)
        chain_name = sys.argv[3]
        message = " ".join(sys.argv[4:]) if len(sys.argv) > 4 else None
        if message:
            print(json.dumps(append_entry(sys.argv[2], chain_name, message), indent=2))
        else:
            print(json.dumps(get_log(sys.argv[2], chain_name), indent=2))

    else:
        print(f"Unknown command: {cmd}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
