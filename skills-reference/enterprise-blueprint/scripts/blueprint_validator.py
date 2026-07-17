#!/usr/bin/env python3
"""
blueprint_validator.py — Validator for blueprint chain steps.

Reads deliverables.json from .blueprint-chain/ to determine what to validate
for each step. Called by chain.py via set-validator.

Usage:
    python3 blueprint_validator.py <step-file-path>
    (chain.py passes the step file path as argument)
"""

import json
import os
import re
import sys
from pathlib import Path

def find_project_root(step_file):
    """Walk up from step file to find project root (contains .blueprint-chain)."""
    p = Path(step_file).resolve()
    for parent in p.parents:
        if (parent / ".blueprint-chain").exists():
            return parent
    return None

def load_deliverables(project_root):
    """Load deliverable mapping from .blueprint-chain/deliverables.json."""
    mapping_path = project_root / ".blueprint-chain" / "deliverables.json"
    if mapping_path.exists():
        return json.loads(mapping_path.read_text())
    return {}

def validate_deliverable(project_root, deliverable, step_path):
    """Validate a single deliverable."""
    if deliverable.endswith("CHANGELOG.md"):
        return validate_changelog(project_root, deliverable)
    elif deliverable.startswith("DELIVERABLE:"):
        return validate_implementation_step(project_root, deliverable, step_path)
    return True, "No specific validation"

def validate_changelog(project_root, changelog_path):
    """Validate changelog has proper entries."""
    changelog = Path(changelog_path)
    if not changelog.exists():
        return False, f"CHANGELOG.md not found at {changelog_path}"
    
    content = changelog.read_text(encoding="utf-8")
    if len(content.strip()) < 20:
        return False, "CHANGELOG.md is empty or too short"
    
    # Check for CL- entries
    if not re.search(r"##\s+CL-\d+", content):
        return False, "No CL- entries found in changelog"
    
    return True, "CHANGELOG.md valid"

def validate_implementation_step(project_root, deliverable, step_path):
    """Validate an implementation step deliverable."""
    parts = deliverable.split(":")
    if len(parts) < 4:
        return True, "Deliverable format unrecognized"
    
    phase_idx = int(parts[1])
    step_idx = int(parts[2])
    step_desc = parts[3]
    desc_lower = step_desc.lower()
    
    # Find actual files that match the step description
    # Look for common patterns
    checks = []
    
    if "migration" in desc_lower or "sql" in desc_lower:
        sql_files = list(project_root.rglob("*.sql"))
        if not sql_files:
            return False, f"No SQL migration files found for: {step_desc}"
        checks.append(f"Found {len(sql_files)} SQL files")
    
    if "config" in desc_lower or "yaml" in desc_lower:
        yaml_files = list(project_root.rglob("*.yaml")) + list(project_root.rglob("*.yml"))
        if not yaml_files:
            return False, f"No YAML config files found for: {step_desc}"
        checks.append(f"Found {len(yaml_files)} YAML files")
    
    if "docker" in desc_lower or "dockerfile" in desc_lower:
        docker_files = list(project_root.rglob("Dockerfile*")) + list(project_root.rglob("docker-compose*.y*ml"))
        if not docker_files:
            return False, f"No Docker files found for: {step_desc}"
        checks.append(f"Found {len(docker_files)} Docker files")
    
    if "test" in desc_lower:
        test_files = list(project_root.rglob("*test*.py")) + list(project_root.rglob("*test*.js")) + list(project_root.rglob("*_test.py"))
        if not test_files:
            return False, f"No test files found for: {step_desc}"
        checks.append(f"Found {len(test_files)} test files")
    
    # Generic: check if any code files exist
    code_files = list(project_root.rglob("*.py")) + list(project_root.rglob("*.js")) + list(project_root.rglob("*.ts")) + list(project_root.rglob("*.go")) + list(project_root.rglob("*.rs"))
    if not code_files:
        return False, f"No code files found in project for: {step_desc}"
    
    return True, "; ".join(checks) if checks else "Step validated"

def main():
    if len(sys.argv) < 2:
        print("Usage: blueprint_validator.py <step-file-path>")
        sys.exit(1)
    
    step_file = sys.argv[1]
    
    project_root = find_project_root(step_file)
    if not project_root:
        print("ERROR: Could not find project root (.blueprint-chain)")
        sys.exit(1)
    
    deliverables = load_deliverables(project_root)
    deliverable = deliverables.get(step_file, "")
    
    if not deliverable:
        print(f"WARN: No deliverable mapping for {step_file}")
        sys.exit(0)  # Don't fail if no mapping
    
    ok, msg = validate_deliverable(project_root, deliverable, step_file)
    if ok:
        print(f"OK: {msg}")
        sys.exit(0)
    else:
        print(f"FAIL: {msg}")
        sys.exit(1)

if __name__ == "__main__":
    main()