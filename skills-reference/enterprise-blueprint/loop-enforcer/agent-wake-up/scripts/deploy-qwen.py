#!/usr/bin/env python3
"""
deploy-qwen.py — Deploy all projects with Qwen models.

Assigns best-fit Qwen model to each agent role.
Uses Alibaba/DashScope API with staggered dispatch.

Model assignments:
  Mnemosyne (memory): qwen3-235b-a22b (reasoning), qwen-mt-plus (data), qwen-vl-plus (UI)
  Aires (film): qwen-max (creative), qwen-vl-max (visual), qwen-vl-plus (storyboard)
  Agora (governance): qwen3-235b-a22b (policy), qwen3-coder-plus (code), qwen-plus-latest (exec)
  Autopilot (ops): qwen3-235b-a22b (design), qwen-mt-plus (connect), qwen-mt-turbo (fast)
  Edgewalker (edge): qwen3-235b-a22b (kernel), qwen3-coder-plus (Rust), qwen-mt-turbo (runtime)

Usage:
  python3 deploy-qwen.py --project mnemosyne
  python3 deploy-qwen.py --all
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
PROVIDER = "alibaba"

# Model assignments per project per role
MODEL_ASSIGNMENTS = {
    "mnemosyne": {
        "lead": "qwen3-235b-a22b",
        "ingestion": "qwen-mt-plus",
        "memory": "qwen3-coder-plus",
        "shadow": "qwen3-235b-a22b-instruct",
        "privacy": "qwen-mt-turbo",
        "frontend": "qwen-vl-plus",
    },
    "aires": {
        "director": "qwen-max",
        "bible": "qwen3-coder-plus",
        "shotlist": "qwen-vl-max",
        "composer": "qwen-vl-plus",
        "continuity": "qwen2.5-vl-72b-instruct",
        "cost": "qwen-mt-plus",
    },
    "agora": {
        "architect": "qwen3-235b-a22b",
        "legalvm": "qwen3-coder-plus",
        "legislative": "qwen-max",
        "judicial": "qwen3-235b-a22b-instruct",
        "executive": "qwen-plus-latest",
        "auditor": "qwen-mt-plus",
    },
    "autopilot": {
        "architect": "qwen3-235b-a22b",
        "connector": "qwen-mt-plus",
        "graph": "qwen3-coder-plus",
        "inference": "qwen3-235b-a22b-instruct",
        "operator": "qwen-mt-turbo",
        "cynic": "qwen-plus-latest",
    },
    "edgewalker": {
        "architect": "qwen3-235b-a22b",
        "kernel": "qwen3-coder-plus",
        "runtime": "qwen-mt-turbo",
        "mesh": "qwen3-235b-a22b-instruct",
        "deception": "qwen-max",
        "policy": "qwen-mt-plus",
    },
}


def log(msg):
    ts = datetime.utcnow().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")


def run(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout, r.returncode
    except Exception as e:
        return str(e), 1


def test_model(model):
    """Test if a model works."""
    out, code = run(["hermes", "chat", "-q", "ok",
                     "--provider", PROVIDER, "--model", model])
    return code == 0 and "error" not in out.lower()


def get_profiles():
    """Get all team profiles."""
    profiles_dir = Path.home() / ".hermes" / "profiles"
    return [p.name for p in profiles_dir.iterdir() 
            if p.is_dir() and p.name != "default"]


def configure_profile(profile_name, model):
    """Set a profile's model provider."""
    config_path = Path.home() / ".hermes" / "profiles" / profile_name / "config.yaml"
    if not config_path.exists():
        return False
    
    import yaml
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    if not config:
        config = {}
    
    config['model'] = {
        'default': model,
        'provider': PROVIDER
    }
    
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
    
    return True


def dispatch_project(project, stagger=15):
    """Dispatch one project's tasks."""
    log(f"=== DEPLOYING {project.upper()} ===")
    
    assignments = MODEL_ASSIGNMENTS.get(project, {})
    
    # Configure each profile with its model
    for role, model in assignments.items():
        profile = f"{project}-{role}"
        log(f"  Configuring {profile} → {model}")
        
        # Test model first
        if not test_model(model):
            log(f"  ⚠ Model {model} failed test, skipping")
            continue
        
        configure_profile(profile, model)
    
    # Unblock project tasks
    out, _ = run(["hermes", "kanban", "list", "--json"])
    try:
        tasks = json.loads(out)
        for t in tasks:
            if t.get("assignee", "").startswith(project + "-"):
                if t.get("status") == "blocked":
                    run(["hermes", "kanban", "unblock", t["id"]])
    except:
        pass
    
    # Block other projects
    for p in PROJECTS:
        if p != project:
            out, _ = run(["hermes", "kanban", "list", "--json"])
            try:
                tasks = json.loads(out)
                for t in tasks:
                    if t.get("assignee", "").startswith(p + "-"):
                        if t.get("status") in ("ready", "todo"):
                            run(["hermes", "kanban", "block", t["id"]])
            except:
                pass
    
    # Dispatch with max 3 concurrent
    out, _ = run(["hermes", "kanban", "dispatch", "--max=3"])
    log(f"  Dispatch: {out[:200] if out else 'ok'}")
    
    return True


def monitor_project(project, check_interval=60):
    """Monitor and re-dispatch if workers die."""
    log(f"=== MONITORING {project.upper()} ===")
    
    cycle = 0
    while cycle < len(BACKOFF):
        time.sleep(check_interval)
        
        # Check if all done
        out, _ = run(["hermes", "kanban", "list", "--json"])
        try:
            tasks = json.loads(out)
            project_tasks = [t for t in tasks 
                           if t.get("assignee", "").startswith(project + "-")]
            done = all(t.get("status") == "done" for t in project_tasks)
            
            if done:
                log(f"  All {project} tasks complete!")
                return True
            
            running = sum(1 for t in project_tasks if t.get("status") == "running")
            log(f"  Running: {running}/{len(project_tasks)}")
            
            if running == 0:
                # Workers died — re-dispatch
                log(f"  Workers died! Recovery attempt {cycle + 1}")
                out, _ = run(["hermes", "kanban", "dispatch", "--max=3"])
                cycle += 1
            else:
                cycle = 0  # Reset on progress
        except:
            cycle += 1
    
    return False


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", choices=PROJECTS)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--stagger", type=int, default=15)
    parser.add_argument("--no-monitor", action="store_true")
    args = parser.parse_args()
    
    if not args.project and not args.all:
        parser.error("Need --project or --all")
    
    projects = PROJECTS if args.all else [args.project]
    
    for p in projects:
        dispatch_project(p, args.stagger)
        
        if not args.no_monitor:
            monitor_project(p)
        
        if p != projects[-1]:
            log(f"Waiting 10s before next project...")
            time.sleep(10)
    
    log("All projects deployed.")


if __name__ == "__main__":
    main()
