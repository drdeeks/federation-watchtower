#!/usr/bin/env python3
"""
Enterprise Blueprint Skill — enhance_skill applies blueprint enforcement to a target project.
Uses loop-enforcer chain for phase-gated enforcement. No skill-creator dependency.

Forever System §2: Self-resolving paths via env vars (LOOP_ENFORCER_ROOT, AGENT_WORKSPACE).
Forever System §1: No duplicate enforcement logic — delegates to enforce_blueprint.py.
"""

import sys
import argparse
import subprocess
import json
import os
import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent

def _loop_enforcer() -> Path:
    """Self-resolving loop-enforcer chain.py — vendored copy by default
    (scripts/chain.py), overridden by LOOP_ENFORCER_ROOT if set and valid."""
    env_le = os.environ.get("LOOP_ENFORCER_ROOT")
    if env_le:
        le_path = Path(env_le).expanduser().resolve() / "scripts" / "chain.py"
        if le_path.exists():
            return le_path
    return SCRIPT_DIR / "scripts" / "chain.py"

def scaffold(skill_name, base_dir):
    skill_dir = base_dir / skill_name
    for d in ["scripts", "references", "references/lessons", "assets"]:
        (skill_dir / d).mkdir(parents=True, exist_ok=True)
    print(f"Scaffolded {skill_dir}")

def enhance_skill(target_path, tier="enterprise", noninteractive=False):
    """
    Apply enterprise-blueprint enforcement to a target project.
    DELEGATES to enforce_blueprint.py for checklist-item-level chain enforcement (§1 Forever System).
    This function now only validates blueprint structure and generates checklist.
    """
    target = Path(target_path).resolve()
    if not target.exists():
        print(f"ERROR: Target not found: {target}")
        return 1

    print(f"[ENHANCE] Applying enterprise-blueprint enforcement to {target}")

    # 1. Validate blueprint exists
    blueprint = target / "blueprint.md"
    if not blueprint.exists():
        print(f"  No blueprint.md found. Run 'enterprise-blueprint scaffold' first.")
        return 1

    # 2. Validate blueprint structure
    print("  Validating blueprint...")
    rc = subprocess.run([
        sys.executable, str(SCRIPT_DIR / "scripts" / "validate_blueprint.py"),
        str(blueprint)
    ])
    if rc.returncode != 0:
        print("  Blueprint validation FAILED")
        return rc.returncode

    # 3. Generate/sync checklist from blueprint
    print("  Generating checklist from blueprint...")
    rc = subprocess.run([
        sys.executable, str(SCRIPT_DIR / "scripts" / "generate_checklist.py"),
        str(blueprint)
    ])
    if rc.returncode != 0:
        print("  Checklist generation FAILED")
        return rc.returncode

    # 4. Initialize loop-enforcer chain (checklist-item granularity)
    print("  Initializing loop-enforcer chain (checklist-item granularity)...")
    chain_dir = target / ".blueprint-chain"
    rc = subprocess.run([
        sys.executable, str(SCRIPT_DIR / "scripts" / "generate_checklist.py"),
        str(target), "--init"
    ])
    if rc.returncode != 0:
        print("  Failed to initialize enforcement chain")
        return rc.returncode

    print("  ✓ Chain initialized at .blueprint-chain/")

    # 5. Final validation - run tests
    print("  Running final validation tests...")
    test_runner = SCRIPT_DIR / "scripts" / "test-runner.py"
    if test_runner.exists():
        test_rc = subprocess.run([
            sys.executable, str(test_runner),
            "--root", str(target), "--json"
        ])
        if test_rc.returncode != 0:
            print("  Test validation FAILED")
            return test_rc.returncode
    else:
        print("  ⚠ test-runner.py not found, skipping test validation")

    print(f"[ENHANCE] Enterprise-blueprint enforcement COMPLETE for {target}")
    print(f"  Checklist: {target}/checklist.md")
    print(f"  Chain: {chain_dir}/ (managed by loop-enforcer)")
    print(f"  Worker API: chain_worker.py check/verify/complete")
    return 0


def _extract_phases(blueprint_path):
    """Extract phase definitions from blueprint Part VI (kept for reference)."""
    content = blueprint_path.read_text()

    # Find Part VI
    part6_match = re.search(r"# PART VI.*?(?=# PART VII|# CHANGE LOG|\Z)", content, re.DOTALL | re.IGNORECASE)
    if not part6_match:
        return []

    part6 = part6_match.group(0)

    # Find phase headers: ### PHASE-N or ### PHASE-N: Title
    phase_pattern = r"###\s*(PHASE-\d+)[:\\s]*([^\\n]*)"
    phases = []

    for match in re.finditer(phase_pattern, part6, re.IGNORECASE):
        phase_id = match.group(1).upper()
        title = match.group(2).strip()

        section_start = match.start()
        next_match = re.search(r"###\s*(PHASE-\d+|PART VII)", part6[section_start + 1:])
        section_end = section_start + 1 + next_match.start() if next_match else len(part6)
        section = part6[section_start:section_end]

        # Extract deliverables
        deliverables = re.findall(r"- \\[ \\]\\s*([^\\n]+)", section)

        # Extract validation gate
        gate_match = re.search(r"### Validation Gate\\s*\\n(.*?)(?:\\n###|\\Z)", section, re.DOTALL)
        validation_gate = gate_match.group(1).strip() if gate_match else ""

        # Extract rollback
        rb_match = re.search(r"### Rollback Procedure\\s*\\n(.*?)(?:\\n###|\\Z)", section, re.DOTALL)
        rollback = rb_match.group(1).strip() if rb_match else ""

        # Extract section tag
        tag_match = re.search(r"\\*\\*Section Tag:\\*\\* `\\\\[([^\\]]+)\\\\]", section)
        section_tag = tag_match.group(1) if tag_match else f"[{phase_id}-v1]"

        # Extract feature flag
        ff_match = re.search(r"\\*\\*Feature Flag:\\*\\* `([^`]+)`", section)
        feature_flag = ff_match.group(1) if ff_match else f"FEAT_{phase_id.replace('-', '_')}"

        phases.append({
            "id": phase_id,
            "name": title or phase_id,
            "section_tag": section_tag,
            "feature_flag": feature_flag,
            "deliverables": deliverables,
            "validation_gate": validation_gate,
            "rollback": rollback
        })

    return phases


import re


def main():
    parser = argparse.ArgumentParser(description="Enterprise Blueprint Skill")
    sub = parser.add_subparsers(dest="cmd", required=True)

    ap_scaffold = sub.add_parser("scaffold", help="Scaffold new blueprint project")
    ap_scaffold.add_argument("project_name")
    ap_scaffold.add_argument("--path", required=True, help="Output directory")
    ap_scaffold.add_argument("--phases", help="Comma-separated phase names")
    ap_scaffold.add_argument("--dry-run", action="store_true")
    ap_scaffold.add_argument("--json", action="store_true")

    ap_enhance = sub.add_parser("enhance_skill", help="Apply enterprise-blueprint enforcement to target project")
    ap_enhance.add_argument("target", help="Target project path")
    ap_enhance.add_argument("--tier", choices=["enterprise", "basic"], default="enterprise")
    ap_enhance.add_argument("--noninteractive", action="store_true")

    args = parser.parse_args()

    if args.cmd == "scaffold":
        return scaffold(args.project_name, Path(args.path))
    elif args.cmd == "enhance_skill":
        return enhance_skill(args.target, args.tier, args.noninteractive)
    else:
        parser.print_help()
        return 1


if __name__ == "__main__":
    sys.exit(main())