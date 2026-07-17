#!/usr/bin/env python3
"""
Enterprise Upgrade — gap analysis and guided upgrade to enterprise tier.

This tool NEVER generates content. No stub scripts, no fake validators, no
boilerplate sections, no filler references. (Its predecessor did exactly
that and every generated file had to be hunted down and removed.) A skill
reaches enterprise tier when a human or agent writes REAL content; this
tool's job is to tell you precisely what's missing and in what order to
add it.

What it does:
  1. Runs validate.py (enterprise mode) against the skill
  2. Computes the tier gap: tags (7), scripts (3+ substantive),
     references (5+ substantive), structure, placeholders, description
  3. Creates ONLY missing required directories (scripts/, references/) —
     empty, for the author to populate
  4. Emits an ordered work list, human or --json

Usage:
    python3 upgrade_to_enterprise.py <skill_dir> [--json] [--dry-run]
    python3 upgrade_to_enterprise.py --target <skills_root> [--json]
"""
import argparse
import json
import os
import subprocess
import sys
sys.dont_write_bytecode = True  # keep __pycache__ out of skill trees
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from skill_root import find_skill_root, find_skills
from validate import validate_skill


SCRIPT_DIR = Path(__file__).parent.resolve()

ENTERPRISE_MINS = {"tags": 7, "scripts": 3, "references": 5}
SUBSTANTIVE_SCRIPT_BYTES = 100
SUBSTANTIVE_REF_BYTES = 200


def _substantive_count(dir_path: Path, min_bytes: int) -> int:
    if not dir_path.is_dir():
        return 0
    count = 0
    for p in dir_path.rglob("*"):
        if not p.is_file() or p.name.startswith(".") or "__pycache__" in p.parts:
            continue
        try:
            body = "".join(p.read_text(encoding="utf-8", errors="ignore").split())
        except OSError:
            continue
        if len(body) >= min_bytes:
            count += 1
    return count


def analyze_gap(skill_dir: Path, dry_run: bool = False) -> Dict:
    """Gap report for one skill. Only mutation: mkdir of missing required
    dirs (empty — author populates them with real content)."""
    report = {
        "skill": skill_dir.name,
        "path": str(skill_dir),
        "enterprise_ready": False,
        "created_dirs": [],
        "work_list": [],
        "validator": {},
    }

    # Only structural creation this tool performs: the two required dirs
    for sub in ("scripts", "references"):
        d = skill_dir / sub
        if not d.is_dir():
            if not dry_run:
                d.mkdir(parents=True, exist_ok=True)
            report["created_dirs"].append(f"{sub}/ (empty — populate with real content)")

    result = validate_skill(str(skill_dir), basic_mode=False)
    fails = [c for c in result["checks"] if not c.passed and c.severity == "FAIL"]
    report["validator"] = {
        "status": result["status"],
        "fails": result["fails"],
        "warnings": result["warnings"],
        "fail_details": [f"{c.name}: {c.detail}" if c.detail else c.name
                         for c in fails],
    }
    report["enterprise_ready"] = result["valid"]

    # Ordered work list — structure first, then counts, then content polish
    work = report["work_list"]
    structural_tags = ("Unexpected", "Forbidden", "lessons/", "templates/",
                       "Cached", "assets", "Foreign", "Nested", "Subdirectory")
    if any(any(t in c.name for t in structural_tags) for c in fails):
        work.append("1. Fix structure: run auto_fix.py (safe moves only), "
                    "then rename anything it flagged")

    n_scripts = _substantive_count(skill_dir / "scripts", SUBSTANTIVE_SCRIPT_BYTES)
    if n_scripts < ENTERPRISE_MINS["scripts"]:
        work.append(f"2. Write {ENTERPRISE_MINS['scripts'] - n_scripts} more real "
                    f"script(s) (have {n_scripts}, need {ENTERPRISE_MINS['scripts']}) — "
                    "each with docstring, --help, and --dry-run where it mutates")

    n_refs = _substantive_count(skill_dir / "references", SUBSTANTIVE_REF_BYTES)
    if n_refs < ENTERPRISE_MINS["references"]:
        work.append(f"3. Write {ENTERPRISE_MINS['references'] - n_refs} more real "
                    f"reference doc(s) (have {n_refs}, need {ENTERPRISE_MINS['references']}) — "
                    "purpose-scoped names, .md/.txt/.html/.pdf")

    if any("metadata.tags" in c.name for c in fails):
        work.append(f"4. Add tags to reach {ENTERPRISE_MINS['tags']} — each a "
                    "distinct natural-language trigger phrase")

    if any("Placeholder" in c.name or "Contains" in c.name for c in fails):
        work.append("5. Remove/complete every placeholder the validator lists — "
                    "real content only, no filler")

    if any("__init__" in c.name for c in fails):
        work.append("6. Make __init__.py functional — it must scaffold/serve "
                    "this skill's own domain, not just exist")

    if not work and not report["enterprise_ready"]:
        work.append("Fix the remaining validator fails listed above")
    if report["enterprise_ready"]:
        work.append("Nothing — run skill_enhance.py update to package")

    return report


def main():
    ap = argparse.ArgumentParser(
        description="Enterprise gap analysis (generates NO content, ever)")
    ap.add_argument("skill", nargs="?", help="One skill directory")
    ap.add_argument("--target", help="Skills root — analyze every skill beneath it")
    ap.add_argument("--json", action="store_true", help="JSON output")
    ap.add_argument("--dry-run", action="store_true",
                    help="Analyze only; don't create missing dirs")
    args = ap.parse_args()

    if not args.skill and not args.target:
        ap.error("give a skill dir or --target <skills_root>")

    if args.skill:
        root = find_skill_root(args.skill)
        if root is None:
            # Not yet a skill — still analyzable as a candidate dir
            root = Path(args.skill).resolve()
        targets = [root]
    else:
        targets = find_skills(args.target)

    reports = [analyze_gap(t, dry_run=args.dry_run) for t in targets]
    ready = sum(1 for r in reports if r["enterprise_ready"])

    if args.json:
        print(json.dumps({
            "operation": "upgrade_to_enterprise",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "dry_run": args.dry_run,
            "skills_analyzed": len(reports),
            "enterprise_ready": ready,
            "reports": reports,
        }, indent=2))
    else:
        print(f"=== Enterprise Gap Report ({len(reports)} skill(s)) ===\n")
        for r in reports:
            mark = "✓" if r["enterprise_ready"] else "✗"
            print(f"{mark} {r['skill']}  "
                  f"(fails: {r['validator']['fails']}, "
                  f"warnings: {r['validator']['warnings']})")
            for d in r["created_dirs"]:
                print(f"    + created {d}")
            for w in r["work_list"]:
                print(f"    → {w}")
            if r["validator"]["fail_details"] and not r["enterprise_ready"]:
                print(f"    validator fails:")
                for fd in r["validator"]["fail_details"][:10]:
                    print(f"      ✗ {fd}")
                extra = len(r["validator"]["fail_details"]) - 10
                if extra > 0:
                    print(f"      … and {extra} more (run validate.py for all)")
            print()
        print(f"{ready}/{len(reports)} enterprise-ready")

    sys.exit(0 if ready == len(reports) else 1)


if __name__ == "__main__":
    main()
