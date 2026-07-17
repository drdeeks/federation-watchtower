#!/usr/bin/env python3
"""
project-dispatcher.py — Dispatch one project at a time with self-healing.

Blocks all other projects, dispatches target, monitors, then moves to next.
Each worker gets self-healing with exponential backoff.

Usage:
  python3 project-dispatcher.py --project mnemosyne
  python3 project-dispatcher.py --all
  python3 project-dispatcher.py --project aires --max-concurrent 2
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


BACKOFF = [10, 30, 120, 300, 600, 900, 1200, 1500, 1800, 3600, 7200, 18000]
PROJECTS = ["mnemosyne", "aires", "agora", "autopilot", "edgewalker"]
LOG_DIR = Path.home() / ".hermes" / "logs"
DEATH_LOG = LOG_DIR / "agent-deaths.log"


def log(msg):
    ts = datetime.utcnow().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")


def run(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout, r.returncode
    except Exception as e:
        return str(e), 1


def get_all_tasks():
    """Get all tasks as list of dicts."""
    out, _ = run(["hermes", "kanban", "list", "--json"])
    try:
        return json.loads(out)
    except:
        return []


def block_project(project):
    """Block all ready tasks for a project."""
    tasks = get_all_tasks()
    blocked = 0
    for t in tasks:
        if t.get("assignee", "").startswith(project + "-") and t.get("status") == "ready":
            run(["hermes", "kanban", "block", t["id"]])
            blocked += 1
    log(f"Blocked {blocked} tasks for {project}")


def unblock_project(project):
    """Unblock all blocked tasks for a project."""
    tasks = get_all_tasks()
    unblocked = 0
    for t in tasks:
        if t.get("assignee", "").startswith(project + "-") and t.get("status") == "blocked":
            run(["hermes", "kanban", "unblock", t["id"]])
            unblocked += 1
    log(f"Unblocked {unblocked} tasks for {project}")


def count_running():
    """Count actual running worker processes."""
    out, _ = run(["pgrep", "-f", "hermes.*kanban.*task"])
    return len(out.strip().split("\n")) if out.strip() else 0


def dispatch_once(max_workers=3):
    """Dispatch ready tasks up to max_workers."""
    out, _ = run(["hermes", "kanban", "dispatch", f"--max={max_workers}"])
    return out


def check_project_done(project):
    """Check if all tasks for a project are done."""
    tasks = get_all_tasks()
    for t in tasks:
        if t.get("assignee", "").startswith(project + "-"):
            if t.get("status") != "done":
                return False
    return True


def dispatch_project(project, max_concurrent=3, monitor=True):
    """Dispatch one project and optionally monitor until done."""
    log(f"=== PROJECT: {project.upper()} ===")
    
    # Unblock this project's tasks
    unblock_project(project)
    
    # Block all other projects
    for p in PROJECTS:
        if p != project:
            block_project(p)
    
    # Dispatch
    out = dispatch_once(max_concurrent)
    log(f"Dispatch: {out[:200] if out else 'ok'}")
    
    if not monitor:
        return
    
    # Monitor with self-healing
    cycle = 0
    while cycle < len(BACKOFF):
        time.sleep(30)
        
        running = count_running()
        done = check_project_done(project)
        
        if done:
            log(f"  All tasks complete for {project}!")
            break
        
        if running == 0:
            # Workers died — try to recover
            log(f"  Workers died! Recovery attempt {cycle + 1}")
            out = dispatch_once(max_concurrent)
            cycle += 1
        else:
            log(f"  Running: {running}, waiting...")
            cycle = 0  # Reset on progress
    
    # Unblock everything for next project
    for p in PROJECTS:
        unblock_project(p)


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", choices=PROJECTS)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--max-concurrent", type=int, default=3)
    parser.add_argument("--no-monitor", action="store_true")
    args = parser.parse_args()
    
    if not args.project and not args.all:
        parser.error("Need --project or --all")
    
    projects = PROJECTS if args.all else [args.project]
    
    for p in projects:
        dispatch_project(p, args.max_concurrent, not args.no_monitor)
        if p != projects[-1]:
            log(f"Waiting 10s before next project...")
            time.sleep(10)
    
    log("Done.")


if __name__ == "__main__":
    main()
