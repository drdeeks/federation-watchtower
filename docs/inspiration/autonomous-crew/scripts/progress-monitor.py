#!/usr/bin/env python3
"""
Progress Monitor - Checks project functionality and progress every 30 seconds
"""

import json
import os
import sys
import time
import subprocess
from pathlib import Path
from datetime import datetime, timezone

WORKSPACE = os.environ.get("WORKSPACE_ROOT", str(__import__("pathlib").Path.home() / "qwen-cloud-2026"))
PROJECTS = ["mnemosyne", "aires", "autopilot", "agora", "edgewalker"]

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def check_chain_status(project):
    """Check chain status for a project."""
    try:
        result = subprocess.run(
            ["python3", os.path.expanduser("~/.hermes/scripts/chain_enforce.py"), "status", project],
            capture_output=True, text=True, cwd=os.path.join(WORKSPACE, project)
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except:
        pass
    return None

def check_tests(project):
    """Check if tests pass for a project."""
    project_dir = os.path.join(WORKSPACE, project)

    # Check for test scripts
    if os.path.exists(os.path.join(project_dir, "package.json")):
        try:
            result = subprocess.run(
                ["npm", "test", "--silent"],
                capture_output=True, text=True, cwd=project_dir, timeout=30
            )
            return result.returncode == 0
        except:
            return None

    # Check for Rust projects
    if os.path.exists(os.path.join(project_dir, "Cargo.toml")):
        try:
            result = subprocess.run(
                ["cargo", "test", "--quiet"],
                capture_output=True, text=True, cwd=project_dir, timeout=60
            )
            return result.returncode == 0
        except:
            return None

    return None

def check_api_health(project):
    """Check if API is responding."""
    ports = {
        "mnemosyne": 41212,
        "aires": 41213,
        "autopilot": 41214,
        "agora": 41215,
        "edgewalker": 41216
    }

    port = ports.get(project)
    if not port:
        return None

    try:
        result = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", f"http://localhost:{port}/health"],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout == "200"
    except:
        return None

def generate_report():
    """Generate progress report for all projects."""
    report = {
        "timestamp": now_iso(),
        "projects": {}
    }

    for project in PROJECTS:
        chain = check_chain_status(project)
        tests = check_tests(project)
        api = check_api_health(project)

        report["projects"][project] = {
            "chain": chain,
            "tests_passing": tests,
            "api_healthy": api
        }

    return report

def main():
    """Main entry point - shows help if requested."""
    if len(sys.argv) > 1 and sys.argv[1] in ("--help", "-h"):
        print("Usage: progress-monitor.py")
        print("Monitors project progress every 30 seconds.")
        print("Environment: WORKSPACE_ROOT")
        return 0

    # Run monitor loop
    print(f"[{now_iso()}] Progress monitor started (30-second interval)")
    print(f"Workspace: {WORKSPACE}")
    print(f"Projects: {PROJECTS}")
    print("-" * 60)

    while True:
        try:
            report = generate_report()

            # Print summary
            print(f"\n[{report['timestamp']}] Progress Check:")
            for project, data in report["projects"].items():
                chain = data["chain"]
                if chain:
                    progress = chain.get("progress", "?/7")
                    active = [s["index"] for s in chain.get("steps", []) if s["state"] == "active"]
                    active_str = f"Phase {active[0]}" if active else "None"
                    tests = "\u2713" if data["tests_passing"] else ("\u2717" if data["tests_passing"] is False else "?")
                    api = "\u2713" if data["api_healthy"] else ("\u2717" if data["api_healthy"] is False else "?")
                    print(f"  {project}: {progress} | {active_str} | Tests: {tests} | API: {api}")
                else:
                    print(f"  {project}: No chain found")

            # Save report
            report_file = os.path.join(WORKSPACE, "progress-report.json")
            with open(report_file, "w") as f:
                json.dump(report, f, indent=2)

            time.sleep(30)

        except KeyboardInterrupt:
            print(f"\n[{now_iso()}] Progress monitor stopped")
            break
        except Exception as e:
            print(f"[{now_iso()}] Error: {e}")
            time.sleep(30)

if __name__ == "__main__":
    sys.exit(main())