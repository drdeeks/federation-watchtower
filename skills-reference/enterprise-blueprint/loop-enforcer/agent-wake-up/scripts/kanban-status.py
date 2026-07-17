#!/usr/bin/env python3
"""
kanban-status.py — Quick kanban board status report.
Shows task counts by status, running workers, recent completions.
"""
import json
import os
import subprocess
import sys
from datetime import datetime


def run_kanban(args):
    """Run hermes kanban command and capture output."""
    try:
        r = subprocess.run(
            ["hermes", "kanban"] + args,
            capture_output=True, text=True, timeout=15
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def count_workers():
    """Count running kanban worker processes."""
    try:
        r = subprocess.run(
            ["ps", "aux"], capture_output=True, text=True, timeout=5
        )
        if r.returncode == 0:
            lines = [l for l in r.stdout.split("\n") if "hermes" in l and "kanban" in l and "task" in l and "grep" not in l]
            return len(lines)
    except Exception:
        pass
    return 0


def main():
    # Get task lists
    statuses = {}
    for status in ["ready", "todo", "running", "done", "blocked"]:
        output = run_kanban(["list", f"--status={status}"])
        if output and output != "(no matching tasks)":
            lines = [l for l in output.split("\n") if l.strip() and "t_" in l]
            statuses[status] = len(lines)
        else:
            statuses[status] = 0
    
    result = {
        "operation": "kanban_status",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "tasks": statuses,
        "workers_running": count_workers(),
        "total_tasks": sum(statuses.values()),
        "status": "ok",
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
    }
    
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
