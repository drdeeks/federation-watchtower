#!/usr/bin/env python3
"""
Start all enforcer daemons for a crew in the background
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

def start_enforcer(agent_workspace, agent_id):
    """Start enforcer daemon for a single agent"""
    pid_file = agent_workspace / ".agent" / "enforcer.pid"
    
    # Check if already running
    if pid_file.exists():
        try:
            pid = int(pid_file.read_text().strip())
            os.kill(pid, 0)
            print(f"  {agent_id}: Enforcer already running (PID {pid})")
            return True
        except:
            pass  # Stale PID file
    
    # Start enforcer.
    # HEMLOCK_HOME is canonical; HERMES_HOME set too as legacy mirror (older runtimes).
    home = os.environ.get("HEMLOCK_HOME") or os.environ.get("HERMES_HOME") or str(Path.home() / ".hermes")
    enforcer_script = Path(home) / "skills" / "devops" / "agent-identity-architecture" / "scripts" / "enforcer_daemon.py"

    env = os.environ.copy()
    env["WORKSPACE_ROOT"] = str(agent_workspace)
    env["AGENT_ID"] = agent_id
    env["HEMLOCK_HOME"] = home
    env["HERMES_HOME"] = home
    
    try:
        proc = subprocess.Popen(
            [sys.executable, str(enforcer_script)],
            cwd=agent_workspace,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        
        # Wait briefly and check PID
        time.sleep(0.5)
        if proc.poll() is None:
            pid_file.parent.mkdir(parents=True, exist_ok=True)
            pid_file.write_text(str(proc.pid))
            print(f"  {agent_id}: Enforcer started (PID {proc.pid})")
            return True
        else:
            print(f"  {agent_id}: Enforcer failed to start")
            return False
    except Exception as e:
        print(f"  {agent_id}: Enforcer start error: {e}")
        return False

def main():
    if len(sys.argv) < 3:
        print("Usage: start-crew-enforcers.py <project_dir> <crew_name>")
        sys.exit(1)
    
    project_dir = Path(sys.argv[1])
    crew_name = sys.argv[2]
    
    agents_dir = project_dir / "agents"
    if not agents_dir.exists():
        print(f"No agents directory: {agents_dir}")
        return
    
    print(f"Starting enforcers for {crew_name} in {project_dir}")
    
    for agent_dir in agents_dir.iterdir():
        if agent_dir.is_dir():
            agent_id = agent_dir.name
            start_enforcer(agent_dir, agent_id)
    
    print("Enforcer startup complete")

if __name__ == "__main__":
    main()