#!/usr/bin/env python3
"""
Phase-Gated Test Orchestrator
=============================

Discovers and runs a project's test suites by tier (unit, integration, e2e,
playwright) and enforces phase gating: a tier only "passes" when every suite in
it exits 0, and the orchestrator's own exit code is non-zero if any required
tier fails. This is the engine behind the ``hemlock test-*`` commands documented
in SKILL.md.

Design constraints (matches the enterprise-blueprint-validation standard):
  * Python 3.8+ stdlib only — zero pip installs.
  * Fully path-agnostic: the project root is resolved from ``--root`` or the
    current working directory. No hardcoded absolute paths anywhere.
  * Runner-agnostic: uses ``pytest`` when available, falls back to ``unittest``
    for ``.py`` suites and to ``bash``/``sh`` for ``.sh`` suites.
  * ``--dry-run`` reports the plan without executing anything.
  * ``--json`` emits a machine-readable report suitable for CI gates.

Discovery convention (all relative to the project root):
    tests/unit/          -> tier "unit"
    tests/integration/   -> tier "integration"
    tests/e2e/           -> tier "e2e"
    tests/playwright/    -> tier "playwright"
Any ``test_*.py``, ``*_test.py``, ``test_*.sh`` or ``*_test.sh`` file inside a
tier directory is treated as a suite. Empty or missing tiers are reported as
skipped (not failed) unless explicitly requested via a single-tier invocation.
"""

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

TIERS = ("unit", "integration", "e2e", "playwright")
SUITE_GLOBS = ("test_*.py", "*_test.py", "test_*.sh", "*_test.sh")


def utcnow():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def resolve_root(root_arg):
    """Resolve the project root from --root or CWD, always as an absolute path."""
    root = Path(root_arg).expanduser().resolve() if root_arg else Path.cwd().resolve()
    return root


def discover_suites(root, tier):
    """Return a sorted list of suite files for a tier, or [] if the dir is absent."""
    tier_dir = root / "tests" / tier
    if not tier_dir.is_dir():
        return []
    found = set()
    for pattern in SUITE_GLOBS:
        found.update(tier_dir.rglob(pattern))
    return sorted(found)


def build_command(suite):
    """Choose an execution command for a single suite file."""
    if suite.suffix == ".py":
        if shutil.which("pytest"):
            return ["pytest", "-q", str(suite)]
        return [sys.executable, "-m", "unittest", "-v", str(suite)]
    if suite.suffix == ".sh":
        shell = shutil.which("bash") or shutil.which("sh") or "sh"
        return [shell, str(suite)]
    # Fallback: execute directly if marked executable.
    return [str(suite)]


def run_suite(suite, root, dry_run):
    cmd = build_command(suite)
    rel = suite.relative_to(root) if root in suite.parents else suite
    entry = {"suite": str(rel), "command": " ".join(cmd)}
    if dry_run:
        entry.update({"status": "planned", "returncode": None})
        return entry
    try:
        proc = subprocess.run(
            cmd, cwd=str(root), capture_output=True, text=True, timeout=1800
        )
        entry["returncode"] = proc.returncode
        entry["status"] = "passed" if proc.returncode == 0 else "failed"
        if proc.returncode != 0:
            tail = (proc.stdout or "") + (proc.stderr or "")
            entry["detail"] = tail.strip()[-2000:]
    except subprocess.TimeoutExpired:
        entry.update({"status": "failed", "returncode": 124, "detail": "timeout after 1800s"})
    except FileNotFoundError as exc:
        entry.update({"status": "failed", "returncode": 127, "detail": str(exc)})
    return entry


def run_tier(root, tier, dry_run, required):
    suites = discover_suites(root, tier)
    results = [run_suite(s, root, dry_run) for s in suites]
    if not suites:
        status = "failed" if required else "skipped"
        return {
            "tier": tier,
            "status": status,
            "suites": [],
            "detail": "no suites discovered" if required else "tier not present",
        }
    if dry_run:
        status = "planned"
    else:
        status = "passed" if all(r["status"] == "passed" for r in results) else "failed"
    return {"tier": tier, "status": status, "suites": results}


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Phase-gated test orchestrator (unit/integration/e2e/playwright)."
    )
    parser.add_argument(
        "tier",
        nargs="?",
        default="all",
        choices=("all",) + TIERS,
        help="Which tier to run (default: all).",
    )
    parser.add_argument("--root", help="Project root (default: current directory).")
    parser.add_argument("-n", "--dry-run", action="store_true", help="Report the plan; run nothing.")
    parser.add_argument("--json", action="store_true", help="Emit a machine-readable JSON report.")
    args = parser.parse_args(argv)

    root = resolve_root(args.root)
    if not root.is_dir():
        print(f"error: project root not found: {root}", file=sys.stderr)
        return 2

    if args.tier == "all":
        # In "all" mode every tier is optional (skipped if absent).
        selected = [(t, False) for t in TIERS]
    else:
        # A single named tier is required — absence is a failure, not a skip.
        selected = [(args.tier, True)]

    tier_reports = [run_tier(root, t, args.dry_run, required) for t, required in selected]

    if args.dry_run:
        status = "dry_run"
    else:
        failed = [t for t in tier_reports if t["status"] == "failed"]
        status = "failed" if failed else "passed"

    report = {
        "operation": "test_runner",
        "timestamp": utcnow(),
        "root": str(root),
        "requested": args.tier,
        "status": status,
        "tiers": tier_reports,
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        for tr in tier_reports:
            mark = {"passed": "✓", "failed": "✗", "skipped": "-", "planned": "»"}.get(tr["status"], "?")
            print(f"[{mark}] {tr['tier']:<12} {tr['status']}  ({len(tr.get('suites', []))} suite(s))")
            for s in tr.get("suites", []):
                smark = {"passed": "✓", "failed": "✗", "planned": "»"}.get(s["status"], "?")
                print(f"      [{smark}] {s['suite']}")
                if s.get("detail"):
                    print(f"          {s['detail'].splitlines()[-1] if s['detail'] else ''}")
        print(f"\nOverall: {status}")

    return 0 if status in ("passed", "dry_run") else 1


if __name__ == "__main__":
    sys.exit(main())
