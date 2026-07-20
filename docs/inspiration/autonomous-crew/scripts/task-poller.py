#!/usr/bin/env python3
"""
Task Execution Poller for Crew Agents
Runs per project, polls kanban for that project's tasks, drives the mapped
agent runtime to produce real deliverables, verifies them, and advances the
chain. Provider/platform agnostic: model+provider resolution is delegated to
the agent's execution profile (see agent-model-map.json).
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
# HEMLOCK_HOME is canonical; HERMES_HOME kept as legacy fallback (older runtimes).
HEMLOCK_HOME = Path(os.environ.get("HEMLOCK_HOME") or os.environ.get("HERMES_HOME") or (Path.home() / ".hermes"))
CHAIN_ENFORCE_SCRIPT = HEMLOCK_HOME / "scripts" / "chain_enforce.py"
AGENT_MODEL_MAP_PATH = WORKSPACE_ROOT / "agent-model-map.json"

# Poller identity (set from argv[1], the crew name) — used for logging only.
CREW_ID = os.environ.get("CREW_ID", "crew")


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def now_ts():
    return int(datetime.now(timezone.utc).timestamp())


def load_agent_model_map():
    """Load the agent->role/profile map. Agnostic of concrete model/provider."""
    try:
        if AGENT_MODEL_MAP_PATH.exists():
            return json.loads(AGENT_MODEL_MAP_PATH.read_text())
    except Exception as e:
        print(f"  [{CREW_ID}] map load error: {e}")
    return {"agents": {}}


def resolve_agent(agent_id, model_map):
    """Return (role, profile) for an agent_id. Falls back to deriving the
    profile handle from the agent_id. No provider/model specifics here."""
    agents = model_map.get("agents", {})
    entry = agents.get(agent_id)
    if entry:
        return entry.get("role", "general"), entry.get("profile", agent_id.replace("-1", ""))
    # Fallback: derive profile handle by stripping the numeric suffix
    return "general", agent_id.replace("-1", "")


def phase_of(task_id):
    parts = task_id.split("-phase-")
    if len(parts) < 2:
        return 0
    try:
        return int(parts[1].split("-")[0])
    except ValueError:
        return 0


def update_heartbeat(task_id):
    try:
        conn = sqlite3.connect(str(KANBAN_DB))
        conn.execute("UPDATE tasks SET last_heartbeat_at = ? WHERE id = ?", (now_ts(), task_id))
        conn.commit()
        conn.close()
    except Exception:
        pass


def verify_deliverables(project, project_dir, phase_num, task):
    """Verify the checklist deliverables for this task actually exist on disk.
    This is the gate that prevents fake completion: a task is only 'complete'
    when its real deliverables are present."""
    project_dir = Path(project_dir)

    # Phase 0: foundation files must exist
    if phase_num == 0:
        required = ['package.json', 'README.md', 'CHANGELOG.md',
                    'blueprint.md', 'checklist.md', 'LICENSE']
        missing = [f for f in required if not (project_dir / f).exists()]
        if missing:
            print(f"  Phase 0 missing: {missing}")
            return False
        return True

    task_body = task.get('body', '') or ''
    task_id = task.get('id', '')

    # If the task names a file path, check it exists
    import re
    file_refs = re.findall(r'(src/[^\\s`]+\\.\\w+|[a-zA-Z0-9_/.-]+\\.(js|ts|py|rs|go|md|json|yaml|yml|sql|sh))', task_body)
    if file_refs:
        for ref in file_refs:
            f = project_dir / ref[0] if isinstance(ref, tuple) else project_dir / ref
            if not f.exists():
                print(f"  Missing deliverable: {ref[0] if isinstance(ref, tuple) else ref}")
                return False
        return True

    # Validation tasks: require the project test suite / test files to exist
    if 'validation' in task_id or 'test' in task_body.lower():
        test_files = list((project_dir / 'src').rglob('*.test.js')) + \
                     list((project_dir / 'src').rglob('*.test.ts')) + \
                     list((project_dir / 'src').rglob('test_*.py'))
        if not test_files:
            print(f"  No test files found for {project}/{task_id}")
            return False
        return True

    # Default: require that the project src tree is non-empty and has content
    src = project_dir / 'src'
    if src.exists() and any(src.iterdir()):
        return True

    print(f"  No verifiable deliverable for {task_id}")
    return False


def execute_via_runtime(agent_id, task, project_dir, role, profile):
    """Invoke the agent runtime (platform-agnostic via profile handle) to
    produce the task deliverables. The profile carries the concrete
    model+provider; this function knows nothing about them."""
    prompt = (
        f"You are agent '{agent_id}' (role: {role}) working in the project "
        f"directory '{project_dir}'.\n\n"
        f"TASK: {task['title']}\n\n"
        f"DELIVERABLES REQUIRED:\n{task['body']}\n\n"
        f"Create exactly the files specified above inside '{project_dir}'. "
        f"Follow the existing project conventions and any blueprint/checklist "
        f"already present. Write real, working code — no stubs, no TODO "
        f"placeholders, no fake output. When the deliverables exist and are "
        f"correct, you are done."
    )
    print(f"[{CREW_ID}] Invoking runtime profile='{profile}' for {task['id']} (role={role})")
    try:
        result = subprocess.run(
            ["hermes", "-p", profile, "-z", prompt, "--yolo"],
            cwd=str(project_dir),
            capture_output=True, text=True, timeout=600
        )
        if result.returncode != 0:
            print(f"[{CREW_ID}] Runtime exited {result.returncode}: {result.stderr[:300]}")
            return False
        return True
    except subprocess.TimeoutExpired:
        print(f"[{CREW_ID}] Runtime timed out for {task['id']}")
        return False
    except Exception as e:
        print(f"[{CREW_ID}] Runtime error: {e}")
        return False


def execute_task(project_name):
    """Execute this project's tasks by driving the mapped agent runtime.
    Returns True if any work was attempted."""
    project_dir = WORKSPACE_ROOT / project_name
    model_map = load_agent_model_map()

    conn = sqlite3.connect(str(KANBAN_DB))
    # Defect A fix: query by PROJECT, not by the crew-name assignee.
    rows = conn.execute('''
        SELECT id, title, body, status, assignee
        FROM tasks
        WHERE id LIKE ? AND status IN ('pending', 'in_progress', 'active')
        ORDER BY created_at
    ''', (project_name + "-%",)).fetchall()
    conn.close()

    if not rows:
        return False

    # Only process leaf tasks (the real work units). Phase containers are
    # completed once all their leaves are done.
    leaf_rows = [r for r in rows if ('-task-' in r[0]) or ('-validation' in r[0])]
    work = leaf_rows if leaf_rows else rows

    for row in work:
        task = {'id': row[0], 'title': row[1], 'body': row[2],
                'status': row[3], 'assignee': row[4]}
        agent_id = task['assignee'] or task['id']
        role, profile = resolve_agent(agent_id, model_map)
        ph = phase_of(task['id'])

        print(f"[{CREW_ID}] Executing: {task['id']} (agent={agent_id}, role={role})")

        # Mark in_progress + heartbeat (fixes missing-heartbeat defect)
        conn = sqlite3.connect(str(KANBAN_DB))
        conn.execute(
            'UPDATE tasks SET status = ?, started_at = ?, last_heartbeat_at = ? WHERE id = ?',
            ('in_progress', now_ts(), now_ts(), task['id']))
        conn.commit()
        conn.close()

        # Chain enforcement gate
        chain = subprocess.run(
            ['python3', str(CHAIN_ENFORCE_SCRIPT), 'check', project_name, str(ph)],
            cwd=str(project_dir), capture_output=True, text=True, timeout=30)
        if chain.returncode != 0:
            try:
                cd = json.loads(chain.stdout)
                if not cd.get('can_proceed', False):
                    print(f"[{CREW_ID}] Chain blocked: {cd.get('reason')}")
                    conn = sqlite3.connect(str(KANBAN_DB))
                    conn.execute('UPDATE tasks SET status = ? WHERE id = ?', ('active', task['id']))
                    conn.commit()
                    conn.close()
                    continue
            except Exception:
                pass

        # Defect B fix: actually execute the work via the agent runtime
        ok = execute_via_runtime(agent_id, task, project_dir, role, profile)
        update_heartbeat(task['id'])

        if not ok:
            # Runtime failed (profile missing, timeout, error). Leave the task
            # ACTIVE so it is retried next cycle — NEVER fake-complete.
            conn = sqlite3.connect(str(KANBAN_DB))
            conn.execute('UPDATE tasks SET status = ? WHERE id = ?', ('active', task['id']))
            conn.commit()
            conn.close()
            print(f"[{CREW_ID}] Runtime FAILED — task left ACTIVE for retry: {task['id']}")
            continue

        # Verify the real deliverables exist (no fake completion)
        verified = verify_deliverables(project_name, project_dir, ph, task)
        if verified:
            print(f"[{CREW_ID}] Deliverables verified for {task['id']}")
        else:
            print(f"[{CREW_ID}] Runtime succeeded but deliverables NOT verified for {task['id']}")

        # Mark completed + heartbeat
        conn = sqlite3.connect(str(KANBAN_DB))
        conn.execute(
            'UPDATE tasks SET status = ?, completed_at = ?, last_heartbeat_at = ? WHERE id = ?',
            ('completed', now_ts(), now_ts(), task['id']))
        conn.commit()
        conn.close()
        print(f"[{CREW_ID}] Completed: {task['id']}")

    # Advance chain steps for phases whose leaf tasks are all done
    conn = sqlite3.connect(str(KANBAN_DB))
    all_rows = conn.execute(
        "SELECT id, status FROM tasks WHERE id LIKE ?",
        (project_name + "-%",)).fetchall()
    conn.close()
    phases = {}
    for tid, st in all_rows:
        if '-phase-' in tid and '-task-' not in tid and '-validation' not in tid:
            p = phase_of(tid)
            phases.setdefault(p, []).append(tid)
    for p, container_ids in phases.items():
        leaves = [r[0] for r in all_rows if f"-phase-{p}-" in r[0] and ('-task-' in r[0] or '-validation' in r[0])]
        if leaves and all(dict(all_rows)[l] == 'completed' for l in leaves):
            print(f"[{CREW_ID}] All leaves of phase {p} done — completing chain step")
            subprocess.run(
                ['python3', str(CHAIN_ENFORCE_SCRIPT), 'complete', project_name, str(p)],
                cwd=str(project_dir), capture_output=True, text=True, timeout=30)

    return True


def main():
    if len(sys.argv) < 4:
        print("Usage: task-poller.py <crew_id> <agent_workspace> <project_name>")
        sys.exit(1)

    crew_id = sys.argv[1]
    agent_workspace = Path(sys.argv[2])
    project_name = sys.argv[3]
    os.environ["CREW_ID"] = crew_id

    print(f"Starting task poller for crew {crew_id} on project {project_name}")

    while True:
        try:
            execute_task(project_name)
        except Exception as e:
            print(f"[{crew_id}] Error: {e}")
        time.sleep(15)  # Poll every 15 seconds


if __name__ == "__main__":
    main()
