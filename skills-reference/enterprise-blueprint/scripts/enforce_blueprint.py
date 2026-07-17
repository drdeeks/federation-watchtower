#!/usr/bin/env python3
"""
enterprise-blueprint — Chain enforcement for blueprint lifecycle.

Uses the checklist as the source of truth. Locks every phase and step
until prior work is verified complete. Integrates with loop-enforcer.

Usage:
    python3 scripts/enforce_blueprint.py <project-dir> --init
    python3 scripts/enforce_blueprint.py <project-dir> --status
    python3 scripts/enforce_blueprint.py <project-dir> --phase 0 --verify
    python3 scripts/enforce_blueprint.py <project-dir> --phase 0 --complete
    python3 scripts/enforce_blueprint.py <project-dir> --menu
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from scripts.generate_checklist import parse_phases, parse_modules, detect_tech_stack

LOOP_ENFORCER = Path(os.environ.get(
    "LOOP_ENFORCER_ROOT",
    str(Path.home() / ".hermes" / "skills" / "loop-enforcer")
))
CHAIN_PY = LOOP_ENFORCER / "scripts" / "chain.py"
BLUEPRINT_VALIDATOR = Path(__file__).parent / "blueprint_validator.py"

# Blueprint phases from the checklist
def extract_checklist_phases(checklist_path):
    """Parse checklist.md for detailed phase steps."""
    content = Path(checklist_path).read_text(encoding="utf-8")
    phases = []
    
    # Split by phase headers - match both "Phase N:" and "Phase N —" and "Phase N "
    phase_splits = re.split(r"(^##\s+Phase\s+\d+[:—\s][^\n]*$)", content, flags=re.MULTILINE)
    
    current_phase = None
    for part in phase_splits:
        if re.match(r"^##\s+Phase\s+\d+[:—\s]", part.strip()):
            if current_phase:
                phases.append(current_phase)
            current_phase = {
                "title": part.strip().lstrip("# ").strip(),
                "tag": "",
                "flag": "",
                "steps": [],
                "gate_items": [],
            }
        elif current_phase:
            # Extract steps
            step_matches = re.findall(r"-\s*\[\s*\]\s+\*\*(Step\s+\d+\s*—\s*[^*]+)\*\*", part)
            current_phase["steps"].extend(step_matches)
            # Extract gate items
            gate_matches = re.findall(r"-\s*\[\s*\]\s+\*\*([^*]+)\*\*", part)
            for g in gate_matches:
                if "Confirm" in g or "prior" in g.lower() or "migration" in g.lower() or "agent" in g.lower() or "flag" in g.lower() or "change log" in g.lower():
                    current_phase["gate_items"].append(g.strip())
    
    if current_phase:
        phases.append(current_phase)
    
    return phases


def extract_blueprint_phases(blueprint_path):
    """Parse blueprint.md for phase tags, flags, and deliverables."""
    return parse_phases(Path(blueprint_path).read_text(encoding="utf-8"))


def create_blueprint_chain(project_dir, project_name, phases):
    """Create a chain enforcing the blueprint phases and steps."""
    chain_name = f"blueprint-{project_name}"
    
    # Build step files - use actual deliverable files as step targets
    chain_step_dir = project_dir / ".blueprint-chain"
    chain_step_dir.mkdir(parents=True, exist_ok=True)
    
    step_files = []
    step_deliverables = {}  # Map step file -> actual deliverable path
    
    for i, phase in enumerate(phases):
        # Phase gate: check prerequisites
        phase_file = chain_step_dir / f"phase-{i:02d}-{phase['title'][:30].replace(' ', '-')}"
        phase_file.touch()
        step_files.append(str(phase_file))
        # Phase gate checks CHANGELOG.md and prior phase completion
        step_deliverables[str(phase_file)] = str(project_dir / "CHANGELOG.md")
        
        # Implementation steps: each step targets an actual file
        for j, step in enumerate(phase.get("steps", [])):
            # Sanitize step name for filename: keep only alphanumeric, dash, underscore
            step_slug = re.sub(r'[^a-zA-Z0-9_-]+', '-', step[:30]).strip('-')
            step_file = chain_step_dir / f"phase-{i:02d}-step-{j+1:02d}-{step_slug}"
            step_file.touch()
            step_files.append(str(step_file))
            # Map to actual deliverable (e.g., migration file, source file, config)
            step_deliverables[str(step_file)] = f"DELIVERABLE:{i}:{j}:{step}"
    
    # Run chain.py create
    cmd = [sys.executable, str(CHAIN_PY), "create", str(project_dir), chain_name] + step_files
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return False, result.stderr
    
    # Save deliverable mapping for validators
    mapping_path = chain_step_dir / "deliverables.json"
    mapping_path.write_text(json.dumps(step_deliverables))
    
    return True, chain_name


def run_chain_cmd(project_dir, chain_name, subcmd, *args):
    """Run a chain.py command."""
    cmd = [sys.executable, str(CHAIN_PY), subcmd, str(project_dir), chain_name] + list(args)
    return subprocess.run(cmd, capture_output=True, text=True)


def get_chain_status(project_dir, chain_name):
    """Get chain status."""
    result = run_chain_cmd(project_dir, chain_name, "status")
    if result.returncode == 0:
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return {"error": "parse failed", "raw": result.stdout}
    return {"error": result.stderr}


def verify_step(project_dir, chain_name, step_path):
    """Verify a chain step using the blueprint validator."""
    # Set the blueprint validator for this step
    set_cmd = [sys.executable, str(CHAIN_PY), "set-validator", str(project_dir), chain_name, step_path, str(BLUEPRINT_VALIDATOR)]
    subprocess.run(set_cmd, capture_output=True)
    
    result = run_chain_cmd(project_dir, chain_name, "verify", step_path)
    if result.returncode == 0:
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return {"error": "parse failed", "raw": result.stdout}
    return {"error": result.stderr}


def complete_step(project_dir, chain_name, step_path):
    """Complete a chain step."""
    result = run_chain_cmd(project_dir, chain_name, "complete", step_path)
    if result.returncode == 0:
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return {"error": "parse failed", "raw": result.stdout}
    return {"error": result.stderr}


def check_step(project_dir, chain_name, step_path):
    """Check a chain step status."""
    result = run_chain_cmd(project_dir, chain_name, "check", step_path)
    if result.returncode == 0:
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return {"error": "parse failed", "raw": result.stdout}
    return {"error": result.stderr}


def main():
    parser = argparse.ArgumentParser(
        description="Chain enforcement for blueprint lifecycle — checklist is the source of truth"
    )
    parser.add_argument("project_dir", help="Path to blueprint project directory")
    parser.add_argument("--init", action="store_true", help="Initialize chain from blueprint/checklist")
    parser.add_argument("--status", action="store_true", help="Show chain status")
    parser.add_argument("--phase", type=int, help="Phase index to operate on")
    parser.add_argument("--step", type=int, help="Step index within phase (default: 0 = phase gate)")
    parser.add_argument("--verify", action="store_true", help="Verify current step")
    parser.add_argument("--complete", action="store_true", help="Complete current step")
    parser.add_argument("--check", action="store_true", help="Check current step status")
    parser.add_argument("--menu", action="store_true", help="Interactive menu")
    parser.add_argument("--json", action="store_true", help="Output JSON")
    
    args = parser.parse_args()
    
    project_dir = Path(args.project_dir).resolve()
    blueprint_path = project_dir / "blueprint.md"
    checklist_path = project_dir / "checklist.md"
    metadata_path = project_dir / "project.json"
    
    if not blueprint_path.exists():
        print(f"Error: blueprint.md not found in {project_dir}", file=sys.stderr)
        sys.exit(1)
    
    # Load metadata
    metadata = {}
    if metadata_path.exists():
        metadata = json.loads(metadata_path.read_text())
    project_name = metadata.get("project", project_dir.name)
    
    # Parse phases from checklist (source of truth) and blueprint
    checklist_phases = extract_checklist_phases(checklist_path) if checklist_path.exists() else []
    blueprint_phases = extract_blueprint_phases(blueprint_path)
    
    # Merge: checklist has steps, blueprint has tags/flags
    merged_phases = []
    for i, cp in enumerate(checklist_phases):
        bp = blueprint_phases[i] if i < len(blueprint_phases) else {}
        merged_phases.append({
            "title": cp["title"],
            "tag": bp.get("tag", ""),
            "flag": bp.get("flag", ""),
            "steps": cp.get("steps", []),
            "gate_items": cp.get("gate_items", []),
            "deliverables": bp.get("deliverables", []),
            "validation_gate": bp.get("validation_gate", ""),
        })
    
    chain_name = f"blueprint-{project_name}"
    
    # Initialize chain if needed
    if args.init:
        ok, msg = create_blueprint_chain(project_dir, project_name, merged_phases)
        if ok:
            print(json.dumps({"ok": True, "chain": msg, "phases": len(merged_phases)}) if args.json else f"Created chain '{msg}' with {len(merged_phases)} phases")
        else:
            print(json.dumps({"ok": False, "error": msg}) if args.json else f"Failed: {msg}", file=sys.stderr)
            sys.exit(1)
        return
    
    # Get status
    if args.status:
        status = get_chain_status(project_dir, chain_name)
        if args.json:
            print(json.dumps(status))
        else:
            print(json.dumps(status, indent=2))
        return
    
    # Phase operations
    if args.phase is not None:
        if args.phase >= len(merged_phases):
            print(f"Error: Phase {args.phase} out of range (0-{len(merged_phases)-1})", file=sys.stderr)
            sys.exit(1)
        
        phase = merged_phases[args.phase]
        step_idx = args.step if args.step is not None else 0
        
        # Build step file path
        steps_dir = project_dir / ".blueprint-chain"
        phase_file = steps_dir / f"phase-{args.phase:02d}-{phase['title'][:30].replace(' ', '-')}"
        
        if step_idx > 0 and step_idx <= len(phase.get("steps", [])):
            step_file = steps_dir / f"phase-{args.phase:02d}-step-{step_idx:02d}-{phase['steps'][step_idx-1][:25].replace(' ', '-').replace('—', '')}"
        else:
            step_file = phase_file
        
        if not step_file.exists():
            print(f"Error: Step file not found: {step_file}", file=sys.stderr)
            sys.exit(1)
        
        step_path = str(step_file)
        
        if args.check:
            result = check_step(project_dir, chain_name, step_path)
            print(json.dumps(result) if args.json else json.dumps(result, indent=2))
        elif args.verify:
            # Validator reads deliverables.json directly - no args needed
            result = verify_step(project_dir, chain_name, step_path)
            print(json.dumps(result) if args.json else json.dumps(result, indent=2))
        elif args.complete:
            result = complete_step(project_dir, chain_name, step_path)
            print(json.dumps(result) if args.json else json.dumps(result, indent=2))
        else:
            result = check_step(project_dir, chain_name, step_path)
            print(json.dumps(result) if args.json else json.dumps(result, indent=2))
        return
    
    # Interactive menu
    if args.menu:
        subprocess.run([sys.executable, str(CHAIN_PY), "menu", str(project_dir), chain_name])
        return
    
    # Default: show status
    status = get_chain_status(project_dir, chain_name)
    print(json.dumps(status) if args.json else json.dumps(status, indent=2))


if __name__ == "__main__":
    main()