#!/usr/bin/env python3
"""
validate_install.py — pre-install validation, delegated to skill-creator.

skill-creator's scripts/validate.py is the SINGLE source of truth for what a
valid skill is. This script ships ZERO validation rules of its own: it
locates skill-creator, subprocess-calls its validator with --json, and
relays the verdict. When skill-creator's rules evolve, the installer is
automatically current — nothing here to keep in sync.

Locator order for the validator (first hit wins):
  1. $SKILL_CREATOR_DIR                      (explicit override)
  2. sibling of this skill's parent dir      (.../<skills-root>/skill-creator)
  3. $OPENCODE_SKILLS_DIR/skill-creator
  4. ~/.config/opencode/skills/skill-creator (legacy default)
  5. THIS skill's bundled copy (scripts/validate.py) — a byte-identical copy
     of skill-creator's validator shipped inside skill-installer so the
     installer works STANDALONE, without requiring skill-creator to be
     installed. skill-creator remains the source of truth: on update, the
     bundled copy is overwritten byte-identical, never forked.

Usage:
    python3 validate_install.py <skill_dir> [--enterprise] [--json] [--dry-run]

Exit codes: 0 valid at tier, 1 invalid, 2 skill-creator not found.
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional

sys.dont_write_bytecode = True  # keep __pycache__ out of skill trees

VALIDATE_TIMEOUT = 120


def find_skill_creator() -> Optional[Path]:
    """Locate a live skill-creator skill directory. Returns None if absent
    (callers then fall back to the bundled validator copy)."""
    candidates = []
    env_dir = os.environ.get("SKILL_CREATOR_DIR")
    if env_dir:
        candidates.append(Path(env_dir).expanduser())
    # Sibling: <skills-root>/skill-installer/scripts/this-file → <skills-root>/skill-creator
    candidates.append(Path(__file__).resolve().parent.parent.parent / "skill-creator")
    env_skills = os.environ.get("OPENCODE_SKILLS_DIR")
    if env_skills:
        candidates.append(Path(env_skills).expanduser() / "skill-creator")
    candidates.append(Path.home() / ".config" / "opencode" / "skills" / "skill-creator")

    for c in candidates:
        if (c / "scripts" / "validate.py").is_file():
            return c
    return None


def find_validator() -> Optional[Path]:
    """Resolve the validator script: a live skill-creator if present,
    otherwise this skill's bundled byte-identical copy (standalone mode)."""
    creator = find_skill_creator()
    if creator is not None:
        return creator / "scripts" / "validate.py"
    bundled = Path(__file__).resolve().parent / "validate.py"
    if bundled.is_file():
        return bundled
    return None


def validate_skill(skill_dir, enterprise: bool = False) -> Dict:
    """Delegate validation to skill-creator's validate.py. Returns its JSON
    verdict plus locator metadata; never applies rules of its own."""
    validator = find_validator()
    if validator is None:
        return {
            "operation": "validate_install",
            "success": False,
            "error": ("no validator available: neither a live skill-creator "
                      "nor the bundled validate.py copy could be found — the "
                      "installer never invents rules of its own."),
        }
    cmd = [sys.executable, str(validator), str(skill_dir), "--json"]
    if not enterprise:
        cmd.append("--basic")
    try:
        r = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=VALIDATE_TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"operation": "validate_install", "success": False,
                "error": f"validator timed out after {VALIDATE_TIMEOUT}s"}
    try:
        verdict = json.loads(r.stdout)
    except (json.JSONDecodeError, ValueError):
        return {"operation": "validate_install", "success": False,
                "error": f"validator produced no JSON (rc={r.returncode}): "
                         f"{(r.stderr or r.stdout)[:300]}"}
    return {
        "operation": "validate_install",
        "success": True,
        "delegated_to": str(validator),
        "tier": "enterprise" if enterprise else "basic",
        "valid": bool(verdict.get("valid")),
        "status": verdict.get("status"),
        "fails": verdict.get("fails", 0),
        "warnings": verdict.get("warnings", 0),
        "checks": verdict.get("checks", []),
    }


def main():
    ap = argparse.ArgumentParser(
        description="Pre-install validation (delegates to skill-creator's "
                    "validate.py — no local rules)")
    ap.add_argument("skill_dir", help="Skill directory to validate")
    ap.add_argument("--enterprise", action="store_true",
                    help="Validate at enterprise tier (default: basic)")
    ap.add_argument("--json", action="store_true", help="JSON output")
    ap.add_argument("--dry-run", action="store_true",
                    help="Show what would run without invoking the validator")
    args = ap.parse_args()

    if args.dry_run:
        validator = find_validator()
        creator = find_skill_creator()
        plan = {
            "operation": "validate_install",
            "dry_run": True,
            "validator": str(validator) if validator else None,
            "mode": ("live skill-creator" if creator else
                     "bundled copy (standalone)") if validator else "unavailable",
            "would_run": (f"validate.py {args.skill_dir} --json"
                          + ("" if args.enterprise else " --basic")),
        }
        print(json.dumps(plan, indent=2) if args.json else
              f"[dry-run] validator: {plan['validator']} ({plan['mode']})\n"
              f"[dry-run] command:   {plan['would_run']}")
        sys.exit(0 if validator else 2)

    result = validate_skill(args.skill_dir, enterprise=args.enterprise)
    result["timestamp"] = datetime.now(timezone.utc).isoformat()

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if not result["success"]:
            print(f"✗ {result['error']}", file=sys.stderr)
        else:
            mark = "✓" if result["valid"] else "✗"
            print(f"{mark} {args.skill_dir} — {result['status']} at "
                  f"{result['tier']} tier "
                  f"({result['fails']} fails, {result['warnings']} warnings)")
            for c in result.get("checks", []):
                if not c.get("passed"):
                    print(f"  {'✗' if c.get('severity') == 'FAIL' else '⚠'} "
                          f"{c.get('name')}: {c.get('detail', '')}")

    if not result["success"]:
        sys.exit(2)
    sys.exit(0 if result["valid"] else 1)


if __name__ == "__main__":
    main()
