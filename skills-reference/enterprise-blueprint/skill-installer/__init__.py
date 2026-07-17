#!/usr/bin/env python3
"""
skill-installer/__init__.py — scaffolder + integrator for install targets.

Per the project rule, every skill's __init__.py contains scaffolding logic
for the skill's own domain. skill-installer's domain is skill DESTINATIONS:
scaffold() prepares a skills root (directory + .receipts/ ledger) ready to
receive installs, and integrate() installs a skill into it by delegating to
scripts/install_skill.py.
"""
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True  # keep __pycache__ out of skill trees

__skill__ = "skill-installer"
__version__ = "1.0.11"
__all__ = ["__skill__", "__version__", "scaffold", "integrate"]


def scaffold(target_name, base_dir, dry_run=False):
    """Prepare a new skills root that installs can target.

    Creates <base_dir>/<target_name>/ with a .receipts/ ledger directory and
    a root manifest recording when the destination was initialized. Never
    touches an existing manifest or receipts.
    """
    root = Path(base_dir).resolve() / target_name
    receipts = root / ".receipts"
    manifest = root / ".installer-manifest.json"
    plan = {
        "operation": "scaffold",
        "skills_root": str(root),
        "dry_run": dry_run,
        "created": [],
    }
    if dry_run:
        plan["created"] = [str(root), str(receipts), str(manifest)]
        return plan
    for d in (root, receipts):
        if not d.exists():
            d.mkdir(parents=True)
            plan["created"].append(str(d))
    if not manifest.exists():
        manifest.write_text(json.dumps({
            "initialized_at": datetime.now(timezone.utc).isoformat(),
            "initialized_by": f"{__skill__} {__version__}",
            "installs": 0,
        }, indent=2), encoding="utf-8")
        plan["created"].append(str(manifest))
    return plan


def integrate(target_path, skill_source, dry_run=False):
    """Install a skill into a scaffolded skills root via install_skill.py."""
    import subprocess
    installer = Path(__file__).resolve().parent / "scripts" / "install_skill.py"
    cmd = [sys.executable, str(installer), str(skill_source),
           "--target", str(target_path), "--json"]
    if dry_run:
        return {"operation": "integrate", "dry_run": True,
                "would_run": " ".join(cmd)}
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    try:
        return json.loads(r.stdout)
    except (json.JSONDecodeError, ValueError):
        return {"operation": "integrate", "success": r.returncode == 0,
                "output": (r.stdout + r.stderr)[:500]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Scaffold a skills-root destination or integrate (install) a skill into one")
    parser.add_argument("--scaffold", help="Name of the new skills root to prepare")
    parser.add_argument("--path", help="Parent dir for the new skills root (default: cwd)")
    parser.add_argument("--integrate", help="Skills root to install into")
    parser.add_argument("--source", help="Skill dir or .skill archive (used with --integrate)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.scaffold:
        print(json.dumps(scaffold(args.scaffold, args.path or Path.cwd(),
                                  dry_run=args.dry_run), indent=2))
    elif args.integrate:
        if not args.source:
            sys.exit("ERROR: --source is required with --integrate")
        print(json.dumps(integrate(args.integrate, args.source,
                                   dry_run=args.dry_run), indent=2))
    else:
        parser.print_help()
