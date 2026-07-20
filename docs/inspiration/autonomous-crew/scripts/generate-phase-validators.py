#!/usr/bin/env python3
"""
Generate Phase Validators from Blueprint
Creates per-phase validation scripts that check DELIVERABLES, not syntax.
"""

import json
import sys
import os
from pathlib import Path
from datetime import datetime, timezone

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def generate_phase_validator(project_dir, phase_num, phase_title, deliverables):
    """Generate a validator script for a specific phase."""
    
    validator_content = f'''#!/usr/bin/env python3
"""
Phase {phase_num} Validator: {phase_title}
Validates deliverables exist and are non-empty.
"""

import json
import sys
from pathlib import Path

def validate():
    """Validate phase {phase_num} deliverables."""
    project_dir = Path("{project_dir}")
    results = []
    all_passed = True
    
    deliverables = {json.dumps(deliverables, indent=8)}
    
    for deliverable in deliverables:
        path = project_dir / deliverable["path"]
        expected_type = deliverable.get("type", "file")
        min_size = deliverable.get("min_size", 1)
        
        if not path.exists():
            results.append({{
                "deliverable": deliverable["name"],
                "path": str(path),
                "status": "FAIL",
                "reason": "File does not exist"
            }})
            all_passed = False
            continue
        
        if expected_type == "file":
            size = path.stat().st_size
            if size < min_size:
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "FAIL",
                    "reason": f"File too small: {{size}} bytes (min: {{min_size}})"
                }})
                all_passed = False
            else:
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "PASS",
                    "size": size
                }})
        elif expected_type == "directory":
            if not path.is_dir():
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "FAIL",
                    "reason": "Path is not a directory"
                }})
                all_passed = False
            else:
                file_count = len(list(path.rglob("*")))
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "PASS",
                    "file_count": file_count
                }})
    
    return {{"passed": all_passed, "results": results}}

if __name__ == "__main__":
    result = validate()
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["passed"] else 1)
'''
    
    return validator_content

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Generate Phase Validators")
    parser.add_argument("--project", required=True, help="Project directory")
    parser.add_argument("--blueprint", required=True, help="Blueprint JSON file")
    parser.add_argument("--output-dir", help="Output directory for validators")
    args = parser.parse_args()
    
    project_dir = Path(args.project)
    blueprint_path = Path(args.blueprint)
    
    if not blueprint_path.exists():
        print(f"Error: Blueprint not found: {blueprint_path}")
        sys.exit(1)
    
    with open(blueprint_path) as f:
        blueprint = json.load(f)
    
    output_dir = Path(args.output_dir) if args.output_dir else project_dir / ".blueprint-chain" / "validators"
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Extract phases and their deliverables from blueprint
    steps = blueprint.get("steps", [])
    
    for step in steps:
        phase_num = step.get("index", 0)
        phase_title = step.get("path", f"phase-{phase_num:02d}").split("/")[-1].replace(".marker", "")
        
        # Define deliverables based on phase
        deliverables = []
        
        # Common deliverables for all phases
        common_deliverables = [
            {"name": "package.json", "path": "package.json", "type": "file", "min_size": 50},
            {"name": "README.md", "path": "README.md", "type": "file", "min_size": 100},
            {"name": "src directory", "path": "src", "type": "directory"},
        ]
        
        # Phase-specific deliverables
        if phase_num == 0:  # Foundation
            deliverables = common_deliverables + [
                {"name": ".env.example", "path": ".env.example", "type": "file", "min_size": 10},
                {"name": ".gitignore", "path": ".gitignore", "type": "file", "min_size": 20},
                {"name": "CHANGELOG.md", "path": "CHANGELOG.md", "type": "file", "min_size": 30},
            ]
        elif phase_num == 6:  # Deployment
            deliverables = common_deliverables + [
                {"name": "Dockerfile", "path": "Dockerfile", "type": "file", "min_size": 50},
                {"name": "docker-compose.yml", "path": "docker-compose.yml", "type": "file", "min_size": 30},
                {"name": "API.md", "path": "API.md", "type": "file", "min_size": 200},
                {"name": "ARCHITECTURE.md", "path": "ARCHITECTURE.md", "type": "file", "min_size": 200},
            ]
        else:  # Other phases
            deliverables = common_deliverables + [
                {"name": f"Phase {phase_num} tests", "path": f"tests/phase-{phase_num:02d}", "type": "directory"},
            ]
        
        # Generate validator
        validator_content = generate_phase_validator(str(project_dir), phase_num, phase_title, deliverables)
        validator_file = output_dir / f"validate-phase-{phase_num:02d}.py"
        validator_file.write_text(validator_content)
        validator_file.chmod(0o755)
        
        print(f"Generated validator: {validator_file}")
    
    print(f"\nGenerated {len(steps)} phase validators in {output_dir}")

if __name__ == "__main__":
    main()
