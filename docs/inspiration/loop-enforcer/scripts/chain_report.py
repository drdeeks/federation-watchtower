#!/usr/bin/env python3
"""
chain_report.py — Generate a human-readable report of chain status.
Usage: python3 chain_report.py <project-dir> <chain-name>
"""
import json, sys, os
from pathlib import Path

def report(project_dir, chain_name):
    state_file = Path(project_dir) / ".chain" / f"{chain_name}.json"
    if not state_file.exists():
        print(f"Chain '{chain_name}' not found")
        return

    with open(state_file) as f:
        state = json.load(f)

    steps = state["steps"]
    total = len(steps)
    complete = sum(1 for s in steps if s["state"] == "complete")
    pct = (complete / total * 100) if total else 0

    print(f"Chain: {chain_name}")
    print(f"Project: {state['project']}")
    print(f"Created: {state['created_at']}")
    print(f"Progress: {complete}/{total} ({pct:.0f}%)")
    print()

    for step in steps:
        icon = {"locked":"LOCK","active":">>>","pending_verify":"?","verified":"OK","complete":"DONE"}.get(step["state"],"???")
        name = os.path.basename(step["path"])
        validator = " [v]" if step.get("validator") else ""
        attempts = f" ({step['attempts']} attempts)" if step["attempts"] else ""
        print(f"  [{icon}] {name}{validator}{attempts}")

    # Show log tail
    log_file = Path(project_dir) / ".chain" / f"{chain_name}.log"
    if log_file.exists():
        lines = log_file.read_text().strip().split("\n")
        print(f"\nRecent log (last 5):")
        for line in lines[-5:]:
            print(f"  {line}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: chain_report.py <project-dir> <chain-name>")
        sys.exit(1)
    report(sys.argv[1], sys.argv[2])
