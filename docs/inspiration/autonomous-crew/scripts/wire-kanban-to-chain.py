#!/usr/bin/env python3
"""
Wire Kanban to Chain
Creates kanban tasks wired to blueprint chain steps.
"""

import json
import sys
import os
import sqlite3
import time
from pathlib import Path
from datetime import datetime, timezone

def now_ts():
    return int(time.time())

def wire_kanban_to_chain(project_dir, chain_json_path, kanban_db_path=None):
    """Wire kanban tasks to chain steps."""

    # Load chain
    with open(chain_json_path) as f:
        chain = json.load(f)

    project_name = chain.get("name", "unknown")
    steps = chain.get("steps", [])

    # Find kanban database
    if kanban_db_path:
        db_path = Path(kanban_db_path)
    else:
        candidates = [
            Path.home() / ".hermes" / "kanban.db",
            Path(project_dir) / ".hermes" / "kanban.db",
        ]
        db_path = None
        for candidate in candidates:
            if candidate.exists():
                db_path = candidate
                break

        if not db_path:
            print("Error: Kanban database not found")
            sys.exit(1)

    # Connect to kanban
    conn = sqlite3.connect(str(db_path))
    cursor = conn.cursor()

    # Ensure tasks table exists
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            body TEXT,
            status TEXT DEFAULT 'pending',
            created_at INTEGER NOT NULL,
            started_at INTEGER,
            completed_at INTEGER
        )
    """)

    # Create tasks for each step
    tasks_created = 0
    tasks_updated = 0

    for step in steps:
        step_index = step.get("index", 0)
        step_path = step.get("path", "")
        step_state = step.get("state", "locked")

        # Extract phase info from path
        phase_match = step_path.split("/")[-1] if "/" in step_path else step_path
        phase_name = phase_match.replace(".marker", "").replace("-", " ").title()

        task_id = f"{project_name}-phase-{step_index:02d}"
        task_title = f"[{project_name}] Phase {step_index}: {phase_name}"
        task_body = f"""Chain Step: {step_index}
Chain Path: {step_path}
Chain State: {step_state}
Project: {project_dir}

## Instructions
1. Run: chain_enforce.py check {project_name} {step_index}
2. If can_proceed: true -> complete the work
3. After work: chain_enforce.py complete {project_name} {step_index}
4. Verify all deliverables exist and pass validation
"""

        # Check if task already exists
        cursor.execute("SELECT id, status FROM tasks WHERE id = ?", (task_id,))
        existing = cursor.fetchone()

        if existing:
            # Update if state changed
            if existing[1] != step_state:
                cursor.execute(
                    "UPDATE tasks SET status = ? WHERE id = ?",
                    (step_state, task_id)
                )
                tasks_updated += 1
        else:
            # Insert new task
            cursor.execute(
                "INSERT INTO tasks (id, title, body, status, created_at) VALUES (?, ?, ?, ?, ?)",
                (task_id, task_title, task_body, step_state, now_ts())
            )
            tasks_created += 1

    conn.commit()
    conn.close()

    return {
        "project": project_name,
        "chain": chain_json_path,
        "tasks_created": tasks_created,
        "tasks_updated": tasks_updated,
        "total_steps": len(steps)
    }

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Wire Kanban to Chain")
    parser.add_argument("--project", required=True, help="Project directory")
    parser.add_argument("--chain", required=True, help="Chain JSON file")
    parser.add_argument("--kanban-db", help="Kanban database path")
    args = parser.parse_args()

    project_dir = Path(args.project)
    chain_path = Path(args.chain)

    if not chain_path.exists():
        print(f"Error: Chain not found: {chain_path}")
        sys.exit(1)

    result = wire_kanban_to_chain(str(project_dir), str(chain_path), args.kanban_db)
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()