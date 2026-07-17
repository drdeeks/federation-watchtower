#!/usr/bin/env python3
"""
quick-bootstrap.py — Automated agent bootstrap sequence.
Runs identity setup, memory load, skill scan, workspace verify in order.
Outputs a bootstrap report.
"""
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def load_identity():
    """Load SOUL.md or USER.md identity files."""
    home = Path.home()
    hermes_home = home / ".hermes"
    
    identity = {"soul": None, "user": None, "agent_name": None}
    
    for profile_dir in hermes_home.glob("profiles/*/"):
        soul = profile_dir / "SOUL.md"
        user = profile_dir / "USER.md"
        if soul.exists():
            identity["soul"] = str(soul)
        if user.exists():
            identity["user"] = str(user)
        break  # Use first profile found
    
    # Check workspace templates
    for ws in home.glob("<agent-framework>/workspaces/*/"):
        soul = ws / "SOUL.md"
        if soul.exists():
            identity["soul"] = str(soul)
            identity["agent_name"] = ws.name
            break
    
    return identity


def scan_skills():
    """Quick scan of available skills."""
    skills_dir = Path.home() / ".hermes" / "skills"
    if not skills_dir.exists():
        return {"count": 0, "skills": []}
    
    skills = []
    for d in sorted(skills_dir.iterdir()):
        if d.is_dir() and not d.name.startswith("."):
            skill_md = d / "SKILL.md"
            if skill_md.exists():
                skills.append(d.name)
    
    return {"count": len(skills), "skills": skills[:20]}  # Cap at 20 for brevity


def verify_workspace():
    """Verify workspace integrity."""
    checks = []
    hermes_home = Path.home() / ".hermes"
    
    # Check profiles exist
    profiles_dir = hermes_home / "profiles"
    if profiles_dir.exists():
        profiles = [d.name for d in profiles_dir.iterdir() if d.is_dir()]
        checks.append({"item": "profiles", "count": len(profiles), "status": "ok"})
    else:
        checks.append({"item": "profiles", "count": 0, "status": "warn"})
    
    # Check kanban
    kanban_db = hermes_home / "kanban" / "kanban.db"
    checks.append({"item": "kanban", "status": "ok" if kanban_db.exists() else "warn"})
    
    return checks


def main():
    result = {
        "operation": "quick_bootstrap",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "identity": load_identity(),
        "skills": scan_skills(),
        "workspace": verify_workspace(),
        "status": "complete",
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
    }
    
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
