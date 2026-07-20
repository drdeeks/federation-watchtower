#!/usr/bin/env python3
"""
Task Dispatcher for Crew Agents
Reads chain state, syncs kanban, assigns work to available agents
"""

import json
import os
import sys
import time
import sqlite3
import subprocess
from pathlib import Path
from datetime import datetime, timezone

KANBAN_DB = Path.home() / ".hermes" / "kanban.db"
WORKSPACE_ROOT = Path(os.environ.get("WORKSPACE_ROOT", str(Path.home() / "qwen-cloud-2026")))

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def get_chain_status(project):
    """Get chain status from .crew-*/.blueprint-chain/ first, then fallbacks"""
    search_dirs = []
    project_dir = WORKSPACE_ROOT / project
    
    # Check .crew-* directories first
    for item in project_dir.iterdir():
        if item.is_dir() and item.name.startswith(".crew-"):
            search_dirs.append(item / ".blueprint-chain")
    
    # Fallbacks
    search_dirs.append(project_dir / ".blueprint-chain")
    search_dirs.append(project_dir / ".chain")
    
    chain_file = None
    for search_dir in search_dirs:
        if search_dir.exists():
            candidates = list(search_dir.glob("*-blueprint.json"))
            if candidates:
                chain_file = candidates[0]
                break
    
    if not chain_file:
        return None
    
    with open(chain_file) as f:
        chain = json.load(f)
    
    steps = chain.get("steps", [])
    active_steps = [s for s in steps if s.get("state") == "active"]
    completed_steps = [s for s in steps if s.get("state") == "complete"]
    
    return {
        "steps": steps,
        "active": active_steps,
        "completed": completed_steps,
        "progress": f"{len(completed_steps)}/{len(steps)}"
    }

def get_kanban_tasks(project):
    """Get kanban tasks for a project"""
    conn = sqlite3.connect(str(KANBAN_DB))
    cursor = conn.cursor()
    cursor.execute(
        "SELECT id, title, status, body, assignee FROM tasks WHERE id LIKE ?",
        (f"{project}-phase-%",)
    )
    rows = cursor.fetchall()
    conn.close()
    
    tasks = []
    for row in rows:
        tasks.append({
            "id": row[0],
            "title": row[1],
            "status": row[2],
            "body": row[3],
            "assignee": row[4]
        })
    return tasks

def get_available_agents(project):
    """Get agents available for a project"""
    agents_dir = WORKSPACE_ROOT / project / "agents"
    if not agents_dir.exists():
        return []
    
    agents = []
    for agent_dir in agents_dir.iterdir():
        if agent_dir.is_dir():
            agent_id = agent_dir.name
            pid_file = agent_dir / ".agent" / "enforcer.pid"
            enforcer_running = False
            if pid_file.exists():
                try:
                    pid = int(pid_file.read_text().strip())
                    os.kill(pid, 0)
                    enforcer_running = True
                except:
                    pass
            agents.append({
                "id": agent_id,
                "workspace": agent_dir,
                "enforcer_running": enforcer_running
            })
    return agents

def assign_task_to_agent(project, task, agent):
    """Assign a task to an agent by creating a work file"""
    work_file = agent["workspace"] / ".agent" / "current_task.json"
    work_file.parent.mkdir(parents=True, exist_ok=True)
    
    task_data = {
        "task_id": task["id"],
        "title": task["title"],
        "body": task["body"],
        "assigned_at": now_iso(),
        "project": project,
        "agent_id": agent["id"]
    }
    
    with open(work_file, "w") as f:
        json.dump(task_data, f, indent=2)
    
    print(f"  Assigned {task['id']} to {agent['id']}")
    return True

def update_kanban_status(task_id, status, assignee=None):
    """Update kanban task status"""
    conn = sqlite3.connect(str(KANBAN_DB))
    cursor = conn.cursor()
    if assignee:
        cursor.execute("UPDATE tasks SET status = ?, assignee = ? WHERE id = ?", 
                      (status, assignee, task_id))
    else:
        cursor.execute("UPDATE tasks SET status = ? WHERE id = ?", (status, task_id))
    conn.commit()
    conn.close()

def update_chain_step(project, step_index, state):
    """Update chain step state in .crew-*/.blueprint-chain/ first"""
    search_dirs = []
    project_dir = WORKSPACE_ROOT / project
    
    for item in project_dir.iterdir():
        if item.is_dir() and item.name.startswith(".crew-"):
            search_dirs.append(item / ".blueprint-chain")
    
    search_dirs.append(project_dir / ".blueprint-chain")
    search_dirs.append(project_dir / ".chain")
    
    chain_file = None
    for search_dir in search_dirs:
        if search_dir.exists():
            candidates = list(search_dir.glob("*-blueprint.json"))
            if candidates:
                chain_file = candidates[0]
                break
    
    if not chain_file:
        return
    
    with open(chain_file) as f:
        chain = json.load(f)
    
    steps = chain.get("steps", [])
    if step_index < len(steps):
        steps[step_index]["state"] = state
        if state == "active":
            steps[step_index]["activated_at"] = now_iso()
        elif state == "complete":
            steps[step_index]["completed_at"] = now_iso()
    
    with open(chain_file, "w") as f:
        json.dump(chain, f, indent=2)
    
    # Also update kanban task
    phase_task_id = f"{project}-phase-{step_index:02d}"
    kanban_status = "active" if state == "active" else "completed" if state == "complete" else "locked"
    update_kanban_status(phase_task_id, kanban_status)

def sync_kanban_with_chain(project, chain_status, tasks):
    """Sync kanban task statuses with chain step states"""
    steps = chain_status["steps"]
    for step in steps:
        step_index = step.get("index", 0)
        step_state = step.get("state", "locked")
        phase_task_id = f"{project}-phase-{step_index:02d}"
        
        # Sync phase task
        task = next((t for t in tasks if t["id"] == phase_task_id), None)
        if task:
            expected_status = "active" if step_state == "active" else "completed" if step_state == "complete" else "locked"
            if task["status"] != expected_status:
                print(f"  {project}: Syncing {phase_task_id} from {task['status']} to {expected_status}")
                update_kanban_status(phase_task_id, expected_status)
        
        # Unlock subtasks when phase becomes active
        if step_state == "active":
            subtask_prefix = f"{project}-phase-{step_index:02d}-task-"
            validation_id = f"{project}-phase-{step_index:02d}-validation"
            
            for t in tasks:
                if t["id"].startswith(subtask_prefix) or t["id"] == validation_id:
                    if t["status"] == "locked":
                        print(f"  {project}: Unlocking subtask {t['id']}")
                        update_kanban_status(t["id"], "pending")

def main():
    import sys
    if "--help" in sys.argv or "-h" in sys.argv:
        print("Task Dispatcher for Crew Agents")
        print("Usage: task-dispatcher.py [--help]")
        print("Runs continuously, dispatching tasks based on chain state.")
        sys.exit(0)
    
    projects = ["mnemosyne", "aires", "autopilot", "agora", "edgewalker"]
    
    print(f"Starting Task Dispatcher for {len(projects)} projects")
    print(f"Workspace: {WORKSPACE_ROOT}")
    print(f"Kanban DB: {KANBAN_DB}")
    print("=" * 60)
    
    while True:
        try:
            print(f"\n[{now_iso()}] Dispatcher cycle")
            
            for project in projects:
                chain_status = get_chain_status(project)
                if not chain_status:
                    continue
                
                tasks = get_kanban_tasks(project)
                agents = get_available_agents(project)
                
                if not agents:
                    continue
                
                # SYNC: Ensure kanban task statuses match chain step states
                sync_kanban_with_chain(project, chain_status, tasks)
                
                # Find active phase
                active_steps = chain_status["active"]
                if not active_steps:
                    # Check if there are pending tasks that should be activated
                    pending_tasks = [t for t in tasks if t["status"] == "pending"]
                    if pending_tasks:
                        first_pending = pending_tasks[0]
                        phase_num = int(first_pending["id"].split("-")[-1])
                        update_chain_step(project, phase_num, "active")
                        print(f"  {project}: Activated phase {phase_num}")
                        continue
                
                # Assign tasks for active phase
                for step in active_steps:
                    step_index = step.get("index", 0)
                    phase_task_id = f"{project}-phase-{step_index:02d}"
                    
                    phase_task = next((t for t in tasks if t["id"] == phase_task_id), None)
                    if not phase_task:
                        continue
                    
                    # Assign phase task if unassigned
                    if phase_task["status"] in ("pending", "active") and (phase_task.get("assignee") is None or phase_task.get("assignee") == ""):
                        available_agents = [a for a in agents if a["enforcer_running"]]
                        if not available_agents:
                            available_agents = agents
                        
                        if available_agents:
                            agent = available_agents[0]
                            assign_task_to_agent(project, phase_task, agent)
                            update_kanban_status(phase_task["id"], "in_progress", agent["id"])
                            print(f"  {project}: Assigned phase {step_index} to {agent['id']}")
                    
                    # ALSO assign all subtasks for this active phase
                    subtask_prefix = f"{project}-phase-{step_index:02d}-task-"
                    subtasks = [t for t in tasks if t["id"].startswith(subtask_prefix) and t["status"] in ("pending", "active")]
                    
                    for i, subtask in enumerate(subtasks):
                        if subtask.get("assignee") is None or subtask.get("assignee") == "":
                            available_agents = [a for a in agents if a["enforcer_running"]]
                            if not available_agents:
                                available_agents = agents
                            
                            agent = available_agents[i % len(available_agents)]
                            assign_task_to_agent(project, subtask, agent)
                            update_kanban_status(subtask["id"], "in_progress", agent["id"])
                            print(f"  {project}: Assigned subtask {subtask['id']} to {agent['id']}")
                    
                    # Assign validation task
                    validation_id = f"{project}-phase-{step_index:02d}-validation"
                    validation_task = next((t for t in tasks if t["id"] == validation_id), None)
                    if validation_task and (validation_task.get("assignee") is None or validation_task.get("assignee") == ""):
                        available_agents = [a for a in agents if a["enforcer_running"]]
                        if not available_agents:
                            available_agents = agents
                        if available_agents:
                            agent = available_agents[0]
                            assign_task_to_agent(project, validation_task, agent)
                            update_kanban_status(validation_task["id"], "in_progress", agent["id"])
                            print(f"  {project}: Assigned validation to {agent['id']}")
            
            time.sleep(30)  # Poll every 30 seconds
        except KeyboardInterrupt:
            print("\nDispatcher stopped")
            break
        except Exception as e:
            print(f"Dispatcher error: {e}")
            time.sleep(30)

if __name__ == "__main__":
    main()