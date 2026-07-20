#!/usr/bin/env python3
"""
enterprise-blueprint — Assign agent roles and track implementation metrics

Manages agent assignments keyed by phase tag or module ID. Reads project.json
for phase structure. Writes assignments.json as the persistent assignment
store. Produces completion reports and bottleneck analysis.

Usage:
    python3 scripts/assign_agents.py <project-dir> --assign "AgentName:PHASE-1"
    python3 scripts/assign_agents.py <project-dir> --assign "AgentName:MOD-003"
    python3 scripts/assign_agents.py <project-dir> --unassign "PHASE-1"
    python3 scripts/assign_agents.py <project-dir> --complete "PHASE-1"
    python3 scripts/assign_agents.py <project-dir> --list
    python3 scripts/assign_agents.py <project-dir> --report
    python3 scripts/assign_agents.py <project-dir> --metrics
    python3 scripts/assign_agents.py <project-dir> --json
"""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


# ── Constants ──────────────────────────────────────────────────────────────────

VALID_STATUSES = ("not_started", "in_progress", "blocked", "complete")

ROLE_DEFINITIONS = {
    "architect":       "Owns Part I–II. Responsible for vision, architecture, module registry.",
    "backend":         "Owns API layer, database schemas, migrations, business logic.",
    "frontend":        "Owns all screen specifications and UI components.",
    "blockchain":      "Owns smart contracts, on-chain interactions, wallet integration.",
    "ai_integration":  "Owns AI/LLM API integration, prompt management, content filtering.",
    "qa":              "Owns test coverage, integration tests, E2E suite, performance budgets.",
    "devops":          "Owns CI/CD, feature flags, monitoring, deployment pipeline.",
    "security":        "Owns auth flows, payment security, smart contract audit, GDPR.",
    "agent":           "AI agent operating autonomously within assigned scope.",
    "unassigned":      "No agent currently assigned to this scope.",
}

BOTTLENECK_THRESHOLD_SCOPES = 4   # warn if one agent has > this many scopes


# ── Helpers ────────────────────────────────────────────────────────────────────

def now_iso():
    return datetime.now(timezone.utc).isoformat()


def today():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return None


def write_json(path, data):
    Path(path).write_text(json.dumps(data, indent=2), encoding="utf-8")


def load_assignments(project_dir):
    path = Path(project_dir) / "assignments.json"
    data = read_json(path)
    if not data:
        return {"assignments": {}, "history": [], "created_at": now_iso()}
    return data


def save_assignments(project_dir, data):
    write_json(Path(project_dir) / "assignments.json", data)


def load_project(project_dir):
    data = read_json(Path(project_dir) / "project.json")
    if not data:
        return {"phases": [], "project": str(project_dir)}
    return data


def parse_scope_key(raw):
    """Normalise a scope string: PHASE-1, [PHASE-1-v1], MOD-003, etc."""
    raw = raw.strip().strip("[]")
    raw = re.sub(r"-v\d+$", "", raw)   # strip version suffix
    return raw.upper()


def scope_label(key):
    """Human-readable label for a scope key."""
    if key.startswith("PHASE-"):
        num = key.replace("PHASE-", "")
        return f"Phase {num}"
    if key.startswith("MOD-"):
        return f"Module {key}"
    return key


# ── Commands ───────────────────────────────────────────────────────────────────

def cmd_assign(project_dir, raw_value, assignments_data):
    """Assign an agent to a scope: 'AgentName:PHASE-1' or 'AgentName:MOD-003'."""
    if ":" not in raw_value:
        print("[ERROR] Format must be 'AgentName:SCOPE' e.g. 'AlphaAgent:PHASE-1'")
        return False

    agent_name, raw_scope = raw_value.split(":", 1)
    agent_name = agent_name.strip()
    scope = parse_scope_key(raw_scope)

    if not agent_name:
        print("[ERROR] Agent name cannot be empty.")
        return False

    existing = assignments_data["assignments"].get(scope, {})
    prior_agent = existing.get("agent", "unassigned")

    assignments_data["assignments"][scope] = {
        "agent": agent_name,
        "scope": scope,
        "label": scope_label(scope),
        "status": existing.get("status", "not_started"),
        "assigned_at": now_iso(),
        "completed_at": existing.get("completed_at"),
        "notes": existing.get("notes", ""),
    }
    assignments_data["history"].append({
        "event": "assigned",
        "scope": scope,
        "agent": agent_name,
        "prior_agent": prior_agent,
        "timestamp": now_iso(),
    })

    save_assignments(project_dir, assignments_data)
    print(f"[OK] Assigned {agent_name} → {scope_label(scope)} ({scope})")
    return True


def cmd_unassign(project_dir, raw_scope, assignments_data):
    scope = parse_scope_key(raw_scope)
    if scope not in assignments_data["assignments"]:
        print(f"[WARN] {scope} has no current assignment.")
        return True

    prior = assignments_data["assignments"][scope].get("agent", "unassigned")
    assignments_data["assignments"][scope]["agent"] = "unassigned"
    assignments_data["assignments"][scope]["assigned_at"] = now_iso()
    assignments_data["history"].append({
        "event": "unassigned",
        "scope": scope,
        "prior_agent": prior,
        "timestamp": now_iso(),
    })

    save_assignments(project_dir, assignments_data)
    print(f"[OK] Unassigned {scope_label(scope)} ({scope}) — was: {prior}")
    return True


def cmd_complete(project_dir, raw_scope, assignments_data):
    scope = parse_scope_key(raw_scope)
    if scope not in assignments_data["assignments"]:
        print(f"[ERROR] {scope} not found in assignments. Assign it first.")
        return False

    entry = assignments_data["assignments"][scope]
    if entry.get("status") == "complete":
        print(f"[WARN] {scope} is already marked complete.")
        return True

    entry["status"] = "complete"
    entry["completed_at"] = now_iso()
    assignments_data["history"].append({
        "event": "completed",
        "scope": scope,
        "agent": entry.get("agent", "unassigned"),
        "timestamp": now_iso(),
    })

    save_assignments(project_dir, assignments_data)
    print(f"[OK] Marked complete: {scope_label(scope)} ({scope})")
    return True


def cmd_list(assignments_data):
    assigns = assignments_data.get("assignments", {})
    if not assigns:
        print("No assignments recorded. Run --assign to add them.")
        return

    print(f"\n{'─' * 60}")
    print(f"  {'SCOPE':<18} {'AGENT':<20} {'STATUS':<14} ASSIGNED")
    print(f"{'─' * 60}")
    for scope, entry in sorted(assigns.items()):
        agent = entry.get("agent", "unassigned")
        status = entry.get("status", "not_started")
        at = (entry.get("assigned_at") or "")[:10]
        print(f"  {scope:<18} {agent:<20} {status:<14} {at}")
    print(f"{'─' * 60}\n")


def cmd_report(project_dir, assignments_data):
    assigns = assignments_data.get("assignments", {})
    project = load_project(project_dir)
    project_name = project.get("project", str(project_dir))

    total = len(assigns)
    complete = sum(1 for e in assigns.values() if e.get("status") == "complete")
    in_progress = sum(1 for e in assigns.values() if e.get("status") == "in_progress")
    blocked = sum(1 for e in assigns.values() if e.get("status") == "blocked")
    unassigned = sum(
        1 for e in assigns.values() if e.get("agent", "unassigned") == "unassigned"
    )

    agents = {}
    for scope, entry in assigns.items():
        agent = entry.get("agent", "unassigned")
        if agent not in agents:
            agents[agent] = []
        agents[agent].append(scope)

    print(f"\n{'=' * 62}")
    print(f"  Assignment Report — {project_name}")
    print(f"{'=' * 62}\n")
    print(f"  Total scopes   : {total}")
    print(f"  Complete       : {complete}")
    print(f"  In Progress    : {in_progress}")
    print(f"  Blocked        : {blocked}")
    print(f"  Unassigned     : {unassigned}")
    pct = round(complete / total * 100, 1) if total > 0 else 0.0
    print(f"  Completion     : {pct}%")
    print(f"\n{'─' * 62}")
    print("  Agent Breakdown:")
    print(f"{'─' * 62}")
    for agent, scopes in sorted(agents.items()):
        done = sum(
            1 for s in scopes
            if assigns.get(s, {}).get("status") == "complete"
        )
        flag = ""
        if len(scopes) > BOTTLENECK_THRESHOLD_SCOPES and agent != "unassigned":
            flag = "  ⚠ HIGH LOAD"
        print(f"  {agent:<22} {len(scopes):>2} scope(s)  {done:>2} complete{flag}")
        for s in sorted(scopes):
            st = assigns.get(s, {}).get("status", "not_started")
            print(f"    • {scope_label(s):<20} [{st}]")
    print(f"{'─' * 62}\n")

    if unassigned > 0:
        print(f"  ⚠  {unassigned} scope(s) have no assigned agent.")
        print("     Run --assign 'AgentName:SCOPE' for each.\n")


def cmd_metrics(project_dir, assignments_data):
    assigns = assignments_data.get("assignments", {})
    history = assignments_data.get("history", [])

    total = len(assigns)
    complete = sum(1 for e in assigns.values() if e.get("status") == "complete")
    blocked = sum(1 for e in assigns.values() if e.get("status") == "blocked")

    pct = round(complete / total * 100, 1) if total > 0 else 0.0

    # Agent load
    agent_scopes = {}
    for entry in assigns.values():
        a = entry.get("agent", "unassigned")
        agent_scopes[a] = agent_scopes.get(a, 0) + 1

    overloaded = [
        a for a, count in agent_scopes.items()
        if count > BOTTLENECK_THRESHOLD_SCOPES and a != "unassigned"
    ]
    unassigned_count = agent_scopes.get("unassigned", 0)

    # Velocity — completions per day from history
    completions = [e for e in history if e.get("event") == "completed"]
    velocity = "N/A"
    if len(completions) >= 2:
        try:
            first_dt = datetime.fromisoformat(completions[0]["timestamp"])
            last_dt = datetime.fromisoformat(completions[-1]["timestamp"])
            days = max((last_dt - first_dt).days, 1)
            velocity = f"{round(len(completions) / days, 2)} completions/day"
        except Exception:
            pass

    metrics = {
        "operation": "metrics",
        "timestamp": now_iso(),
        "status": "success",
        "project": str(project_dir),
        "details": {
            "total_scopes": total,
            "complete": complete,
            "in_progress": sum(
                1 for e in assigns.values() if e.get("status") == "in_progress"
            ),
            "blocked": blocked,
            "not_started": sum(
                1 for e in assigns.values() if e.get("status") == "not_started"
            ),
            "unassigned": unassigned_count,
            "completion_pct": pct,
            "velocity": velocity,
            "agent_count": len([a for a in agent_scopes if a != "unassigned"]),
            "overloaded_agents": overloaded,
            "blocked_scopes": [
                s for s, e in assigns.items() if e.get("status") == "blocked"
            ],
            "recommendations": [],
        },
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
    }

    recs = metrics["details"]["recommendations"]
    if unassigned_count > 0:
        recs.append(
            f"{unassigned_count} scope(s) unassigned — assign agents before work begins."
        )
    for agent in overloaded:
        count = agent_scopes[agent]
        recs.append(
            f"Agent '{agent}' owns {count} scopes (threshold: {BOTTLENECK_THRESHOLD_SCOPES})"
            " — consider redistributing to prevent bottleneck."
        )
    if blocked > 0:
        recs.append(
            f"{blocked} scope(s) blocked — investigate and resolve before proceeding."
        )
    if not recs:
        recs.append("No bottlenecks detected. Assignments look balanced.")

    print(f"\n{'=' * 62}")
    print("  Blueprint Metrics")
    print(f"{'=' * 62}\n")
    print(f"  Completion   : {pct}% ({complete}/{total} scopes)")
    print(f"  Velocity     : {velocity}")
    print(f"  Agents active: {metrics['details']['agent_count']}")
    print(f"  Overloaded   : {len(overloaded)}")
    print(f"  Blocked      : {blocked}")
    print(f"\n  Recommendations:")
    for r in recs:
        print(f"    • {r}")
    print()
    print(json.dumps(metrics, indent=2))


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--help", "-h"):
        print(__doc__)
        sys.exit(0)

    project_dir = Path(sys.argv[1])
    if not project_dir.exists():
        print(f"[ERROR] Project directory not found: {project_dir}")
        sys.exit(1)

    assignments_data = load_assignments(project_dir)
    success = True

    if "--assign" in sys.argv:
        idx = sys.argv.index("--assign")
        value = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else ""
        success = cmd_assign(project_dir, value, assignments_data)

    elif "--unassign" in sys.argv:
        idx = sys.argv.index("--unassign")
        scope = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else ""
        success = cmd_unassign(project_dir, scope, assignments_data)

    elif "--complete" in sys.argv:
        idx = sys.argv.index("--complete")
        scope = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else ""
        success = cmd_complete(project_dir, scope, assignments_data)

    elif "--list" in sys.argv:
        cmd_list(assignments_data)

    elif "--report" in sys.argv:
        cmd_report(project_dir, assignments_data)

    elif "--metrics" in sys.argv:
        cmd_metrics(project_dir, assignments_data)

    else:
        print("[ERROR] No command specified. Use --help to see available commands.")
        success = False

    # Emit JSON statistics for assign/unassign/complete
    if "--json" in sys.argv and "--assign" in sys.argv:
        result = {
            "operation": "assign_agents",
            "timestamp": now_iso(),
            "status": "success" if success else "failed",
            "project": str(project_dir),
            "details": {
                "total_assigned": len([
                    e for e in assignments_data["assignments"].values()
                    if e.get("agent", "unassigned") != "unassigned"
                ]),
                "total_scopes": len(assignments_data["assignments"]),
            },
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
        }
        print(json.dumps(result, indent=2))

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
