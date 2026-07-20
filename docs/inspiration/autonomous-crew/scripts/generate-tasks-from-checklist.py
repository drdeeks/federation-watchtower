#!/usr/bin/env python3
"""
Generate Kanban tasks from project checklist.md files
Parses the detailed deliverables and validation gates from each phase
"""

import os
import re
import sqlite3
import sys
from pathlib import Path
from datetime import datetime, timezone

KANBAN_DB = Path.home() / ".hermes" / "kanban.db"
WORKSPACE_ROOT = Path(os.environ.get("WORKSPACE_ROOT", str(Path.home() / "qwen-cloud-2026")))

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def now_ts():
    return int(datetime.now(timezone.utc).timestamp())

def parse_checklist(project_dir):
    """Parse checklist.md and extract tasks per phase"""
    checklist_path = project_dir / "checklist.md"
    if not checklist_path.exists():
        print(f"No checklist.md found for {project_dir.name}")
        return []
    
    content = checklist_path.read_text()
    
    # Also find all checkbox items
    checkbox_pattern = r'- \[( |x)\] (.+)'
    
    tasks = []
    current_phase = None
    
    lines = content.split('\n')
    for i, line in enumerate(lines):
        # Check for phase header - support both "## Phase N — Title" and "## Phase N: Title"
        phase_match = re.match(r'^## Phase (\d+)[:—\s]+\s*([^\n]+)', line)
        if phase_match:
            phase_num = int(phase_match.group(1))
            phase_title = phase_match.group(2).strip()
            current_phase = phase_num
            continue
        
        # Also handle "### Phase Validation Gate" as phase boundary
        if re.match(r'^### Phase Validation Gate', line):
            current_phase = None
            continue
        
        # Check for checkbox items
        checkbox_match = re.match(checkbox_pattern, line)
        if checkbox_match and current_phase is not None:
            checked = checkbox_match.group(1) == 'x'
            text = checkbox_match.group(2).strip()
            
            # Determine task type
            if "Validation Gate" in text or "Tests pass" in text or "No linting" in text or "All files exist" in text:
                task_type = "validation"
            elif "Deliverables" in text or "Prerequisites" in text:
                continue  # Skip section headers
            else:
                task_type = "deliverable"
            
            tasks.append({
                "project": project_dir.name,
                "phase": current_phase,
                "type": task_type,
                "text": text,
                "checked": checked
            })
    
    return tasks

def generate_kanban_tasks(projects):
    """Generate kanban tasks from checklist items"""
    all_tasks = []
    
    for project in projects:
        project_dir = WORKSPACE_ROOT / project
        tasks = parse_checklist(project_dir)
        
        print(f"  {project}: parsed {len(tasks)} items from checklist")
        
        # Group by phase
        phases = {}
        for task in tasks:
            phase = task["phase"]
            if phase not in phases:
                phases[phase] = {"deliverables": [], "validations": []}
            if task["type"] == "deliverable":
                phases[phase]["deliverables"].append(task)
            else:
                phases[phase]["validations"].append(task)
        
        # Create kanban tasks
        for phase_num in sorted(phases.keys()):
            phase_data = phases[phase_num]
            
            # Create deliverable tasks
            for i, deliverable in enumerate(phase_data["deliverables"]):
                task_id = f"{project}-phase-{phase_num:02d}-task-{i:02d}"
                title = f"Phase {phase_num}: {deliverable['text'][:80]}"
                body = f"Project: {project}\nPhase: {phase_num}\nType: deliverable\n\n{deliverable['text']}"
                status = "completed" if deliverable["checked"] else ("active" if phase_num == 0 else "locked")
                
                all_tasks.append({
                    "id": task_id,
                    "title": title,
                    "status": status,
                    "body": body,
                    "project": project,
                    "phase": phase_num,
                    "task_index": i
                })
            
            # Create validation task (one per phase)
            if phase_data["validations"]:
                task_id = f"{project}-phase-{phase_num:02d}-validation"
                title = f"Phase {phase_num}: Validation Gate"
                validations = "\n".join([f"- {v['text']}" for v in phase_data["validations"]])
                body = f"Project: {project}\nPhase: {phase_num}\nType: validation\n\n{validations}"
                status = "completed" if all(v["checked"] for v in phase_data["validations"]) else ("active" if phase_num == 0 else "locked")
                
                all_tasks.append({
                    "id": task_id,
                    "title": title,
                    "status": status,
                    "body": body,
                    "project": project,
                    "phase": phase_num,
                    "task_index": 99  # validation last
                })
    
    return all_tasks

def sync_to_kanban(tasks):
    """Sync tasks to kanban database"""
    conn = sqlite3.connect(str(KANBAN_DB))
    cursor = conn.cursor()
    
    # Clear existing tasks for these projects
    for task in tasks:
        cursor.execute("DELETE FROM tasks WHERE id = ?", (task["id"],))
    
    # Insert new tasks
    for task in tasks:
        cursor.execute("""
            INSERT INTO tasks (id, title, status, body, assignee, created_at, started_at, completed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            task["id"],
            task["title"],
            task["status"],
            task["body"],
            None,  # assignee
            now_ts(),
            now_ts() if task["status"] in ("active", "in_progress") else None,
            now_ts() if task["status"] == "completed" else None
        ))
    
    conn.commit()
    conn.close()
    print(f"Synced {len(tasks)} tasks to kanban")

def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: generate-tasks-from-checklist.py")
        print("Parses each known project's checklist.md and syncs tasks to the kanban DB.")
        sys.exit(0)

    projects = ["mnemosyne", "aires", "autopilot", "agora", "edgewalker"]

    print("Parsing checklists...")
    tasks = generate_kanban_tasks(projects)
    
    print(f"Generated {len(tasks)} tasks:")
    for task in tasks[:10]:
        print(f"  {task['id']}: {task['title'][:60]} ({task['status']})")
    if len(tasks) > 10:
        print(f"  ... and {len(tasks) - 10} more")
    
    print("\nSyncing to kanban...")
    sync_to_kanban(tasks)
    print("Done!")

if __name__ == "__main__":
    main()