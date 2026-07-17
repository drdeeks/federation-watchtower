#!/usr/bin/env python3
"""
crew-dispatcher.py — Self-healing crew dispatcher.

Dispatches kanban tasks with:
- One project at a time (configurable)
- Staggered starts (no API hammering)
- Self-healing: re-dispatches dead workers with backoff
- Full API cycling per attempt

Usage:
  python3 crew-dispatcher.py --project mnemosyne
  python3 crew-dispatcher.py --project aires --stagger 30
  python3 crew-dispatcher.py --all --stagger 20
  python3 crew-dispatcher.py --test
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional


BACKOFF_SEQUENCE = [10, 30, 120, 300, 600, 900, 1200, 1500, 1800, 3600, 7200, 18000]

API_PROVIDERS = [
    {"provider": "opencode-zen", "model": "mimo-v2.5-free"},
    {"provider": "opencode-zen", "model": "nemotron-3-ultra-free"},
    {"provider": "opencode-zen", "model": "deepseek-v4-flash-free"},
    {"provider": "opencode-zen", "model": "north-mini-code-free"},
    {"provider": "openrouter", "model": "meta-llama/llama-3.1-8b-instruct:free"},
    {"provider": "openrouter", "model": "google/gemini-2.0-flash-001:free"},
]

LOG_DIR = Path.home() / ".hermes" / "logs"
DEATH_LOG = LOG_DIR / "agent-deaths.log"
PROJECTS = ["mnemosyne", "aires", "agora", "autopilot", "edgewalker"]


def log(msg: str):
    ts = datetime.utcnow().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")


def try_api(provider: str, model: str) -> bool:
    try:
        r = subprocess.run(
            ["hermes", "chat", "-q", "ok", "--provider", provider, "--model", model],
            capture_output=True, text=True, timeout=30
        )
        return r.returncode == 0
    except:
        return False


def find_working_api() -> Optional[Dict]:
    for api in API_PROVIDERS:
        if try_api(api["provider"], api["model"]):
            return api
    return None


def get_tasks_by_status(project: str, status: str) -> List[Dict]:
    r = subprocess.run(
        ["hermes", "kanban", "list", f"--status={status}"],
        capture_output=True, text=True, timeout=30
    )
    tasks = []
    for line in r.stdout.strip().split("\n"):
        if not line.strip() or line.startswith("═") or line.startswith("─"):
            continue
        parts = line.split()
        if len(parts) >= 3 and parts[1].startswith("t_"):
            assignee = parts[3] if len(parts) > 3 else ""
            if assignee.startswith(project + "-"):
                tasks.append({"id": parts[1], "status": parts[2], "assignee": assignee})
    return tasks


def count_workers() -> int:
    r = subprocess.run(
        ["pgrep", "-f", "hermes.*kanban.*task"],
        capture_output=True, text=True
    )
    return len(r.stdout.strip().split("\n")) if r.stdout.strip() else 0


def dispatch_project(project: str, stagger: int = 15):
    """Dispatch one project's tasks with stagger."""
    log(f"=== DISPATCHING {project.upper()} ===")
    
    # Find working API first
    api = find_working_api()
    if not api:
        log("ALL APIs DOWN — cannot dispatch")
        return
    
    log(f"Using API: {api['provider']}/{api['model']}")
    
    # Get ready tasks
    ready = get_tasks_by_status(project, "ready")
    todo = get_tasks_by_status(project, "todo")
    tasks = ready + todo
    
    if not tasks:
        log(f"No tasks ready for {project}")
        return
    
    log(f"Found {len(tasks)} tasks")
    
    for i, task in enumerate(tasks):
        # Respect max concurrent
        while count_workers() >= 3:
            log(f"  At max workers (3), waiting...")
            time.sleep(10)
        
        # Stagger
        if i > 0:
            log(f"  Stagger: waiting {stagger}s...")
            time.sleep(stagger)
        
        # Dispatch
        log(f"  Dispatching: {task['assignee']}")
        r = subprocess.run(
            ["hermes", "kanban", "dispatch"],
            capture_output=True, text=True, timeout=60
        )
        if r.returncode == 0:
            log(f"  ✓ Dispatched {task['assignee']}")
        else:
            log(f"  ✗ Failed: {r.stderr[:100]}")
    
    log(f"=== {project.upper()} DISPATCHED ===")


def monitor_and_heal(project: str, check_interval: int = 60):
    """Monitor workers and re-dispatch dead ones."""
    log(f"=== MONITORING {project.upper()} ===")
    
    cycle = 0
    while cycle < len(BACKOFF_SEQUENCE):
        running = get_tasks_by_status(project, "running")
        ready = get_tasks_by_status(project, "ready")
        todo = get_tasks_by_status(project, "todo")
        
        log(f"  Running: {len(running)}, Ready: {len(ready)}, Todo: {len(todo)}")
        
        # If nothing running but tasks still pending, something died
        if not running and (ready or todo):
            log(f"  Workers died! Attempting recovery...")
            
            api = find_working_api()
            if api:
                log(f"  API found: {api['provider']}/{api['model']}")
                # Re-dispatch
                for task in (ready + todo):
                    subprocess.run(
                        ["hermes", "kanban", "dispatch"],
                        capture_output=True, text=True, timeout=60
                    )
                    time.sleep(5)
                cycle = 0  # Reset backoff on successful re-dispatch
            else:
                backoff = BACKOFF_SEQUENCE[cycle]
                log(f"  All APIs down, backoff {backoff}s (cycle {cycle+1})")
                time.sleep(backoff)
                cycle += 1
        
        # All done?
        if not running and not ready and not todo:
            log(f"  All tasks complete!")
            break
        
        time.sleep(check_interval)
    
    if cycle >= len(BACKOFF_SEQUENCE):
        log(f"  EXHAUSTED all backoff cycles. Tasks may be dead.")
        log(f"  Check: ~/.hermes/logs/agent-deaths.log")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Self-healing crew dispatcher")
    parser.add_argument("--project", choices=PROJECTS, help="Single project")
    parser.add_argument("--all", action="store_true", help="All projects sequentially")
    parser.add_argument("--stagger", type=int, default=15, help="Seconds between workers")
    parser.add_argument("--monitor", action="store_true", help="Monitor mode (re-dispatch dead)")
    parser.add_argument("--test", action="store_true", help="Test API only")
    args = parser.parse_args()
    
    if args.test:
        api = find_working_api()
        print(json.dumps({"status": "ok" if api else "fail", "api": api}))
        return 0 if api else 1
    
    projects = PROJECTS if args.all else [args.project]
    
    for project in projects:
        dispatch_project(project, args.stagger)
        
        if args.monitor:
            monitor_and_heal(project)
        
        if project != projects[-1]:
            log(f"Waiting 30s before next project...")
            time.sleep(30)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
