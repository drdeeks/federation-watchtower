#!/usr/bin/env python3
"""
Spawn and start crew agents from blueprint.json
Creates agents with proper identity layer and starts their enforcers
"""

import json
import sys
import os
import subprocess
import shutil
from pathlib import Path
from datetime import datetime, timezone

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# Resolve paths via environment variables with sensible defaults.
# HEMLOCK_HOME is canonical; HERMES_HOME kept as legacy fallback (older runtimes).
HEMLOCK_HOME = Path(os.environ.get("HEMLOCK_HOME") or os.environ.get("HERMES_HOME") or (Path.home() / ".hermes"))
AGENT_IDENTITY_SKILL = Path(os.environ.get("AGENT_IDENTITY_SKILL", HEMLOCK_HOME / "skills/devops/agent-identity-architecture"))
ENFORCER_SOCKET_DIR = Path(os.environ.get("ENFORCER_SOCKET_DIR", "/run/agent-enforcer"))
ENFORCER_LOG_DIR = Path(os.environ.get("ENFORCER_LOG_DIR", "/var/log/agent-enforcer"))

class CrewAgentSpawner:
    def __init__(self, project_dir, crew_name):
        self.project_dir = Path(project_dir)
        self.crew_name = crew_name
        self.crew_dir = self.project_dir / f".crew-{crew_name}"
        self.blueprint_path = self.crew_dir / "blueprint.json"
        self.identity_skill_path = AGENT_IDENTITY_SKILL
        self.scripts_path = self.identity_skill_path / "scripts"
        self.enforcer_socket_dir = ENFORCER_SOCKET_DIR
        self.enforcer_log_dir = ENFORCER_LOG_DIR
        
    def load_blueprint(self):
        with open(self.blueprint_path) as f:
            return json.load(f)
    
    def create_agent_workspace(self, agent_def, agent_index):
        """Create agent workspace with identity layer"""
        agent_id = agent_def["agent_id"]
        display_name = agent_def["display_name"]
        agent_type = agent_def["agent_type"]
        
        print(f"  Creating agent: {agent_id} ({display_name})")
        
        # Create workspace
        agent_workspace = self.project_dir / "agents" / agent_id
        agent_workspace.mkdir(parents=True, exist_ok=True)
        
        # Create .agent directory structure
        agent_dir = agent_workspace / ".agent"
        for d in ["habits", "logs", "metrics", "templates", "constitutions", "templates/tool-enforcement"]:
            (agent_dir / d).mkdir(parents=True, exist_ok=True)
        
        # Copy scripts from identity skill
        if self.scripts_path.exists():
            for script in self.scripts_path.glob("*.py"):
                shutil.copy2(script, agent_workspace / script.name)
            for script in self.scripts_path.glob("*.sh"):
                shutil.copy2(script, agent_workspace / script.name)
                os.chmod(agent_workspace / script.name, 0o755)
        
        # Copy templates
        templates_src = self.identity_skill_path / "references/templates"
        if templates_src.exists():
            for tpl in templates_src.rglob("*"):
                if tpl.is_file():
                    rel = tpl.relative_to(templates_src)
                    dest = agent_dir / "templates" / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(tpl, dest)
        
        # Copy reference habits
        for habit in self.identity_skill_path.glob("references/*.yaml"):
            if "habit" in habit.name.lower() or "enforcement" in habit.name.lower():
                shutil.copy2(habit, agent_dir / "habits" / habit.name)
        
        # Create constitution
        constitution = {
            "agent": {
                "id": agent_id,
                "name": display_name,
                "type": agent_type,
                "personality": f"{agent_type}-specialist",
                "purpose": f"Serve as {agent_type} specialist in crew {self.crew_name}",
                "core_values": [
                    "Identity before action",
                    "Validation before claim", 
                    "Memory before drift",
                    "Crew over individual"
                ],
                "hard_constraints": [
                    "Never execute without enforcer approval",
                    "Never claim completion without reflection",
                    "Never hardcode paths - use WORKSPACE_ROOT",
                    "Never store secrets in plaintext"
                ],
                "operational_standards": {
                    "pre_tool_check": "identity + tool + reflective habits",
                    "post_tool_reflection": "mandatory",
                    "completion_gate": "reflective-loop habit",
                    "heartbeat_interval_seconds": 300
                }
            }
        }
        
        import yaml
        with open(agent_dir / "constitution.yaml", "w") as f:
            yaml.dump(constitution, f, default_flow_style=False, sort_keys=False)
        
        # Create genesis.md
        genesis = f"""# GENESIS

**Agent:** {display_name} ({agent_id})
**Type:** {agent_type}
**Personality:** {agent_type}-specialist
**Crew:** {self.crew_name}
**Born:** {now_iso()}

## Purpose
Serve as {agent_type} specialist. Build systems that amplify human agency.
Learn continuously. Leave things better than found.

## Promise to Crew
- Constitution loaded at t=0
- Habits internalized, not invoked
- Enforcer watches, I build
- Memory curates, I act
- Next agent deserves better
"""
        with open(agent_dir / "genesis.md", "w") as f:
            f.write(genesis)
        
        # Create tools directory with required tools
        tools_dir = agent_workspace / "tools"
        tools_dir.mkdir(exist_ok=True)
        
        # Generate tool scripts from templates
        for tpl_name in ["enforce.sh.template", "secret.sh.template", "memory-log.sh.template", "memory-promote.sh.template", "TOOLS-GUIDE.md.template"]:
            tpl_path = agent_dir / "templates" / "tool-enforcement" / tpl_name
            if tpl_path.exists():
                dest_name = tpl_name.replace(".template", "")
                shutil.copy2(tpl_path, tools_dir / dest_name)
                os.chmod(tools_dir / dest_name, 0o755)
        
        # Create memory directories
        for d in ["daily", "weekly", "long-term"]:
            (agent_workspace / "memory" / d).mkdir(parents=True, exist_ok=True)
        
        # Create secrets directory
        secrets_dir = agent_workspace / ".secrets"
        secrets_dir.mkdir(exist_ok=True)
        os.chmod(secrets_dir, 0o700)
        
        # Create agent.json for crew manager
        import hashlib
        agent_json = {
            "agent_id": agent_id,
            "name": display_name,
            "type": agent_type,
            "personality": f"{agent_type}-specialist",
            "workspace": str(agent_workspace),
            "enforcer_socket": str(self.enforcer_socket_dir / f"{agent_id}.sock"),
            "constitution_hash": hashlib.sha256(json.dumps(constitution, sort_keys=True).encode()).hexdigest()[:16],
            "crew_id": self.crew_name,
            "created_utc": now_iso(),
            "identity_layer": "v1",
            "habits": ["identity-enforcement", "tool-enforcement", "reflective-loop"],
            "builder_code": None
        }
        
        with open(agent_workspace / "agent.json", "w") as f:
            json.dump(agent_json, f, indent=2)
        
        # Create crew registry entry
        crew_registry = self.crew_dir / "agents.json"
        if crew_registry.exists():
            with open(crew_registry) as f:
                registry = json.load(f)
        else:
            registry = {"crew_id": self.crew_name, "agents": []}
        
        registry["agents"] = [a for a in registry["agents"] if a["agent_id"] != agent_id]
        registry["agents"].append({
            "agent_id": agent_id,
            "name": display_name,
            "type": agent_type,
            "workspace": str(agent_workspace)
        })
        
        with open(crew_registry, "w") as f:
            json.dump(registry, f, indent=2)
        
        return agent_workspace
    
    def start_agent(self, agent_workspace):
        """Start the agent enforcer"""
        agent_id = agent_workspace.name
        
        print(f"  Starting agent: {agent_id}")
        
        # Set environment
        env = os.environ.copy()
        env["AGENT_ID"] = agent_id
        env["AGENT_WORKSPACE"] = str(agent_workspace)
        env["WORKSPACE_ROOT"] = str(agent_workspace.parent.parent)
        env["ENFORCER_SOCKET_DIR"] = str(self.enforcer_socket_dir)
        env["ENFORCER_LOG_DIR"] = str(self.enforcer_log_dir)
        
        # Start enforcer daemon
        enforcer_script = agent_workspace / "enforcer_daemon.py"
        if enforcer_script.exists():
            log_file = agent_workspace / ".agent" / "logs" / "enforcer.log"
            log_file.parent.mkdir(parents=True, exist_ok=True)
            
            with open(log_file, "a") as f:
                proc = subprocess.Popen(
                    ["python3", str(enforcer_script), agent_id],
                    cwd=str(agent_workspace),
                    env=env,
                    stdout=f,
                    stderr=subprocess.STDOUT,
                    start_new_session=True
                )
            
            # Save PID
            pid_file = agent_workspace / ".agent" / "enforcer.pid"
            with open(pid_file, "w") as f:
                f.write(str(proc.pid))
            
            print(f"    Enforcer started (PID: {proc.pid})")
            return proc
        else:
            print(f"    ERROR: enforcer_daemon.py not found")
            return None
    
    def spawn_all_agents(self):
        """Create and start all agents from blueprint"""
        blueprint = self.load_blueprint()
        agents = blueprint.get("agents", [])
        
        print(f"\n{'='*60}")
        print(f"SPAWNING CREW: {self.crew_name}")
        print(f"Project: {self.project_dir}")
        print(f"Agents: {len(agents)}")
        print(f"{'='*60}\n")
        
        workspaces = []
        for i, agent_def in enumerate(agents):
            ws = self.create_agent_workspace(agent_def, i)
            workspaces.append((agent_def["agent_id"], ws))
        
        print(f"\n{'='*60}")
        print(f"STARTING AGENTS")
        print(f"{'='*60}\n")
        
        processes = []
        for agent_id, ws in workspaces:
            proc = self.start_agent(ws)
            if proc:
                processes.append((agent_id, proc))
        
        print(f"\nStarted {len(processes)} agents")
        print("Agents are running in background. Check logs in agent workspaces.")
        
        return processes

def main():
    if len(sys.argv) < 3:
        print("Usage: spawn-crew-agents.py <project_dir> <crew_name>")
        sys.exit(1)
    
    project_dir = sys.argv[1]
    crew_name = sys.argv[2]
    
    spawner = CrewAgentSpawner(project_dir, crew_name)
    processes = spawner.spawn_all_agents()
    
    # Keep running and monitor
    print(f"\nMonitoring {len(processes)} agents... (Ctrl+C to stop)")
    try:
        import time
        while True:
            time.sleep(10)
            for agent_id, proc in processes:
                if proc.poll() is not None:
                    print(f"Agent {agent_id} exited with code {proc.returncode}")
    except KeyboardInterrupt:
        print("\nShutting down agents...")
        for agent_id, proc in processes:
            proc.terminate()
        print("Done")

if __name__ == "__main__":
    main()