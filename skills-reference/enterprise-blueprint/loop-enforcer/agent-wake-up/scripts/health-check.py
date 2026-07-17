#!/usr/bin/env python3
"""
health-check.py — Quick agent health diagnostic.
Checks: model connectivity, skills loading, memory status, workspace integrity.
Output: JSON with status per check.
"""
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def check_model():
    """Test if the configured model is reachable."""
    try:
        r = subprocess.run(
            ["hermes", "chat", "-q", "say OK", "--provider", "<your-provider>", "--model", "<your-model>"],
            capture_output=True, text=True, timeout=30
        )
        return {"status": "ok" if r.returncode == 0 else "error", "detail": r.stdout[:200] if r.returncode == 0 else r.stderr[:200]}
    except Exception as e:
        return {"status": "error", "detail": str(e)}


def check_skills():
    """Check skills directory exists and has content."""
    skills_dir = Path.home() / ".hermes" / "skills"
    if not skills_dir.exists():
        return {"status": "error", "detail": "skills directory missing"}
    count = len([d for d in skills_dir.iterdir() if d.is_dir()])
    return {"status": "ok", "detail": f"{count} skills installed"}


def check_memory():
    """Check memory file status."""
    memory_file = Path.home() / ".hermes" / "memory" / "MEMORY.md"
    if not memory_file.exists():
        return {"status": "warn", "detail": "no MEMORY.md found"}
    size = memory_file.stat().st_size
    return {"status": "ok", "detail": f"{size} bytes"}


def check_workspace():
    """Check workspace structure."""
    hermes_home = Path.home() / ".hermes"
    required = ["skills", "logs"]
    missing = [d for d in required if not (hermes_home / d).exists()]
    if missing:
        return {"status": "warn", "detail": f"missing: {', '.join(missing)}"}
    return {"status": "ok", "detail": "structure intact"}


def check_kanban():
    """Check kanban database exists."""
    db = Path.home() / ".hermes" / "kanban" / "kanban.db"
    if not db.exists():
        return {"status": "warn", "detail": "no kanban.db found"}
    return {"status": "ok", "detail": f"{db.stat().st_size} bytes"}


def main():
    result = {
        "operation": "health_check",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "checks": {
            "model": check_model(),
            "skills": check_skills(),
            "memory": check_memory(),
            "workspace": check_workspace(),
            "kanban": check_kanban(),
        },
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
    }
    
    all_ok = all(c["status"] in ("ok", "warn") for c in result["checks"].values())
    result["status"] = "healthy" if all_ok else "degraded"
    
    print(json.dumps(result, indent=2))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
