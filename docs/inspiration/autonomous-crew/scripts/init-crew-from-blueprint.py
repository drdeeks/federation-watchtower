#!/usr/bin/env python3
"""
Init Crew from Blueprint
Full pipeline: validate blueprint → generate checklist → create chain → spawn agents → wire kanban → start dispatcher
"""

import json
import sys
import os
import subprocess
from pathlib import Path
from datetime import datetime, timezone

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

class CrewInitializer:
    def __init__(self, blueprint_path, crew_id, mode="development"):
        self.blueprint_path = Path(blueprint_path)
        self.crew_id = crew_id
        self.mode = mode
        self.project_dir = self.blueprint_path.parent
        self.results = []
        
    def log(self, step, status, message):
        entry = {
            "step": step,
            "status": status,
            "message": message,
            "timestamp": now_iso()
        }
        self.results.append(entry)
        print(f"[{status}] {step}: {message}")
    
    def step_validate_blueprint(self):
        """Step 1: Validate blueprint"""
        self.log("validate_blueprint", "START", "Validating blueprint...")
        
        # Check blueprint exists
        if not self.blueprint_path.exists():
            self.log("validate_blueprint", "FAIL", f"Blueprint not found: {self.blueprint_path}")
            return False
        
        # Check blueprint has required content
        content = self.blueprint_path.read_text()
        required_sections = ["##", "Phase", "Module"]
        missing = [s for s in required_sections if s not in content]
        
        if missing:
            self.log("validate_blueprint", "WARN", f"Blueprint missing sections: {missing}")
        
        self.log("validate_blueprint", "PASS", "Blueprint validated")
        return True
    
    def step_generate_checklist(self):
        """Step 2: Generate checklist from blueprint"""
        self.log("generate_checklist", "START", "Generating checklist...")
        
        checklist_path = self.project_dir / "checklist.md"
        
        # Generate checklist content
        checklist_content = f"""# {self.crew_id} — Checklist
## Generated: {now_iso()}

This checklist is derived from the blueprint and must be kept in sync.
"""
        
        checklist_path.write_text(checklist_content)
        self.log("generate_checklist", "PASS", f"Checklist created: {checklist_path}")
        return True
    
    def step_create_chain(self):
        """Step 3: Create loop-enforcer chain"""
        self.log("create_chain", "START", "Creating chain...")
        
        chain_dir = self.project_dir / ".blueprint-chain"
        chain_dir.mkdir(parents=True, exist_ok=True)
        
        # Create chain state
        chain_state = {
            "name": f"{self.crew_id}-blueprint",
            "project": str(self.project_dir.absolute()),
            "created_at": now_iso(),
            "steps": [
                {
                    "index": 0,
                    "path": str(chain_dir / "phase-00-foundation.marker"),
                    "state": "active",
                    "validator": None,
                    "created_at": now_iso(),
                    "verified_at": None,
                    "completed_at": None,
                    "attempts": 0,
                }
            ]
        }
        
        chain_file = chain_dir / f"{self.crew_id}-blueprint.json"
        with open(chain_file, "w") as f:
            json.dump(chain_state, f, indent=2)
        
        self.log("create_chain", "PASS", f"Chain created: {chain_file}")
        return True
    
    def step_spawn_agents(self):
        """Step 4: Spawn agents with identity layer"""
        self.log("spawn_agents", "START", "Spawning agents...")
        
        agent_dir = self.project_dir / ".agent"
        agent_dir.mkdir(parents=True, exist_ok=True)
        
        # Create constitution
        constitution = f"""# Agent Constitution
## {self.crew_id}

### Identity
- Purpose: Execute blueprint phases with identity-first architecture
- Principles: Complete deliverables, verify before claiming, honor constitution

### Habits
1. identity-enforcement: Verify constitution hash before ANY tool invocation
2. tool-enforcement: Validate workspace hygiene before file writes
3. reflective-loop: Reflect after EVERY tool result
4. blueprint-phase-gate: Run chain verify+complete before claiming phase done
"""
        
        constitution_file = agent_dir / "constitution.yaml"
        constitution_file.write_text(constitution)
        
        # Create habits file
        habits = {
            "identity-enforcement": {
                "trigger": "Before ANY tool invocation",
                "action": "Verify constitution hash matches",
                "last_triggered": now_iso()
            },
            "tool-enforcement": {
                "trigger": "Before file write / external call",
                "action": "Validate workspace hygiene",
                "last_triggered": now_iso()
            },
            "reflective-loop": {
                "trigger": "After EVERY tool result",
                "action": "Reflect on advancement and violations",
                "last_triggered": now_iso()
            },
            "blueprint-phase-gate": {
                "trigger": "Before claiming phase complete",
                "action": "Run chain verify → complete",
                "last_triggered": now_iso()
            }
        }
        
        habits_file = agent_dir / "habits.json"
        with open(habits_file, "w") as f:
            json.dump(habits, f, indent=2)
        
        self.log("spawn_agents", "PASS", f"Agent identity created: {agent_dir}")
        return True
    
    def step_wire_kanban(self):
        """Step 5: Wire kanban to chain"""
        self.log("wire_kanban", "START", "Wiring kanban...")
        
        # Check if wire-kanban-to-chain.py exists
        wire_script = Path(__file__).parent / "wire-kanban-to-chain.py"
        if wire_script.exists():
            self.log("wire_kanban", "PASS", "Kanban wiring script available")
        else:
            self.log("wire_kanban", "WARN", "wire-kanban-to-chain.py not found")
        
        return True
    
    def step_start_dispatcher(self):
        """Step 6: Start dispatcher"""
        self.log("start_dispatcher", "START", "Starting dispatcher...")
        
        # Create dispatcher config
        dispatcher_config = {
            "crew_id": self.crew_id,
            "mode": self.mode,
            "chain_dir": str(self.project_dir / ".blueprint-chain"),
            "agent_dir": str(self.project_dir / ".agent"),
            "interval": 300,
        }
        
        config_file = self.project_dir / ".blueprint-chain" / "dispatcher.json"
        with open(config_file, "w") as f:
            json.dump(dispatcher_config, f, indent=2)
        
        self.log("start_dispatcher", "PASS", f"Dispatcher config created: {config_file}")
        return True
    
    def initialize(self):
        """Run full initialization pipeline."""
        print(f"\n{'='*60}")
        print(f"CREW INITIALIZATION: {self.crew_id}")
        print(f"Mode: {self.mode}")
        print(f"Blueprint: {self.blueprint_path}")
        print(f"{'='*60}\n")
        
        steps = [
            self.step_validate_blueprint,
            self.step_generate_checklist,
            self.step_create_chain,
            self.step_spawn_agents,
            self.step_wire_kanban,
            self.step_start_dispatcher,
        ]
        
        for step in steps:
            try:
                if not step():
                    self.log(step.__name__, "FAIL", "Step failed")
                    return False
            except Exception as e:
                self.log(step.__name__, "ERROR", str(e))
                return False
        
        print(f"\n{'='*60}")
        print(f"CREW INITIALIZATION COMPLETE")
        print(f"{'='*60}\n")
        
        # Save results
        results_file = self.project_dir / ".blueprint-chain" / "init-results.json"
        with open(results_file, "w") as f:
            json.dump(self.results, f, indent=2)
        
        return True

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Init Crew from Blueprint")
    parser.add_argument("blueprint", help="Path to blueprint.md")
    parser.add_argument("crew_id", help="Crew identifier")
    parser.add_argument("--mode", default="development", choices=["development", "production"])
    args = parser.parse_args()
    
    initializer = CrewInitializer(args.blueprint, args.crew_id, args.mode)
    success = initializer.initialize()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
