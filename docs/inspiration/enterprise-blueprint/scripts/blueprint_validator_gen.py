#!/usr/bin/env python3
"""
blueprint_validator_gen.py — Generate phase validators from blueprint deliverables.

The blueprint is the source of truth. Each phase declares:
- Deliverables (files/dirs that must exist)
- Validation Gate (description of what to validate)

This generates a validator script that checks EXACTLY what the blueprint declares.
No project-type registry — pure blueprint-driven validation.
"""

import re
import json
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional


def extract_blueprint_deliverables(blueprint_path: Path) -> List[Dict[str, Any]]:
    """Extract deliverables and validation gates from blueprint per phase."""
    content = blueprint_path.read_text(encoding="utf-8")
    phases = []
    
    # First, try to find the Part VI implementation checklist tables
    part_vi_match = re.search(r"## PART VI.*?---\n", content, re.DOTALL | re.IGNORECASE)
    if part_vi_match:
        part_vi_content = part_vi_match.group(0)
        # Parse the tables for each phase
        lines = part_vi_content.split("\n")
        
        current_phase = None
        current_deliverables = []
        current_gate = ""
        
        for line in lines:
            # Phase header
            phase_header_match = re.match(r"### PHASE-(\d+): ([^\n]+)", line)
            if phase_header_match:
                # Save previous phase
                if current_phase is not None:
                    phases.append({
                        "phase": current_phase["num"],
                        "title": current_phase["title"],
                        "tag": current_phase.get("tag", ""),
                        "flag": current_phase.get("flag", ""),
                        "deliverables": current_deliverables,
                        "validation_gate": current_gate,
                    })
                
                # Start new phase
                current_phase = {
                    "num": int(phase_header_match.group(1)),
                    "title": phase_header_match.group(2).strip(),
                }
                current_deliverables = []
                current_gate = ""
            
            # Table row (inside a phase)
            elif current_phase and line.startswith("|") and "|" in line:
                parts = [p.strip() for p in line.split("|") if p.strip()]
                if len(parts) >= 4:
                    # Check if this is a header row or separator
                    if parts[0].lower() in ["prerequisite", "---", "--------------"]:
                        continue
                    # Skip if it looks like a separator row (all dashes)
                    if all(re.match(r"^-+$", p) for p in parts):
                        continue
                    # Deliverables column (index 2)
                    deliv_cell = parts[2] if len(parts) > 2 else ""
                    # Validation Gate column (index 3)
                    gate_cell = parts[3] if len(parts) > 3 else ""
                    
                    if deliv_cell and deliv_cell != "-":
                        # Split deliverables by comma, semicolon
                        for d in re.split(r"[,;]\s*", deliv_cell):
                            d = d.strip()
                            if d and d != "-":
                                current_deliverables.append(d)
                    
                    if gate_cell and gate_cell != "-":
                        current_gate = gate_cell
        
        # Don't forget the last phase
        if current_phase is not None:
            phases.append({
                "phase": current_phase["num"],
                "title": current_phase["title"],
                "tag": current_phase.get("tag", ""),
                "flag": current_phase.get("flag", ""),
                "deliverables": current_deliverables,
                "validation_gate": current_gate,
            })
    
    # Fallback: try the inline format (**Deliverable:** etc.)
    if not phases:
        phase_pattern = r"### PHASE-(\d+)[a-z]?: ([^>\n]+)"
        for match in re.finditer(phase_pattern, content):
            phase_num = int(match.group(1))
            title = match.group(2).strip()
            
            section = content[match.start():]
            next_phase = re.search(r"### PHASE-\d+", section[1:])
            if next_phase:
                section = section[:next_phase.start()]
            
            deliverables = re.findall(r"\*\*Deliverable:\*\*\s*`?([^`\n]+)`?", section)
            gate_match = re.search(r"\*\*Validation Gate:\*\*\s*`?([^`\n]+)`?", section)
            validation_gate = gate_match.group(1).strip() if gate_match else ""
            tag_match = re.search(r"\*\*Tag:\*\*\s*`?([^`\n]+)`?", section)
            tag = tag_match.group(1).strip() if tag_match else ""
            flag_match = re.search(r"\*\*Flag:\*\*\s*`?([^`\n]+)`?", section)
            flag = flag_match.group(1).strip() if flag_match else ""
            
            phases.append({
                "phase": phase_num,
                "title": title,
                "tag": tag,
                "flag": flag,
                "deliverables": deliverables,
                "validation_gate": validation_gate,
            })
    
    return sorted(phases, key=lambda x: x["phase"])


def parse_deliverable(deliverable: str) -> Dict[str, Any]:
    """Parse a deliverable string into checkable components.
    
    Formats supported:
    - "config/database.yml" — file must exist
    - "scripts/*.sh" — glob pattern, at least one match
    - "modules/ (dir)" — directory must exist
    - "api/specs/openapi.json (valid JSON)" — file exists + content validation
    - "CHANGELOG.md (has CL- entries)" — file exists + pattern check
    """
    deliverable = deliverable.strip()
    
    # Check for inline validation hints in parentheses
    validation_hint = ""
    if "(" in deliverable and ")" in deliverable:
        hint_start = deliverable.rfind("(")
        hint_end = deliverable.rfind(")")
        if hint_end > hint_start:
            validation_hint = deliverable[hint_start+1:hint_end].strip()
            deliverable = deliverable[:hint_start].strip()
    
    # Determine type
    is_dir = deliverable.endswith("/") or deliverable.endswith(" (dir)")
    is_glob = "*" in deliverable or "?" in deliverable
    path = deliverable.replace(" (dir)", "").rstrip("/")
    
    return {
        "raw": deliverable,
        "path": path,
        "is_dir": is_dir,
        "is_glob": is_glob,
        "validation_hint": validation_hint,
    }


def generate_validator_code(phase: Dict[str, Any]) -> str:
    """Generate a Python validator script for a phase based on its deliverables."""
    phase_num = phase["phase"]
    deliverables = [parse_deliverable(d) for d in phase.get("deliverables", [])]
    validation_gate = phase.get("validation_gate", "")
    
    lines = []
    lines.append("#!/usr/bin/env python3")
    lines.append(f'"""')
    lines.append(f'Validator for Phase {phase_num}: {phase["title"]}')
    lines.append(f'Auto-generated from blueprint deliverables.')
    lines.append(f'Validation Gate: {validation_gate}')
    lines.append(f'"""')
    lines.append("")
    lines.append("import json")
    lines.append("import os")
    lines.append("import sys")
    lines.append("import re")
    lines.append("import glob")
    lines.append("from pathlib import Path")
    lines.append("")
    lines.append("def find_project_root(step_file):")
    lines.append('    """Walk up from step file to find project root (contains .blueprint-chain)."""')
    lines.append("    p = Path(step_file).resolve()")
    lines.append("    for parent in p.parents:")
    lines.append("        if (parent / '.blueprint-chain').exists():")
    lines.append("            return parent")
    lines.append("    return None")
    lines.append("")
    lines.append("def check_deliverable(project_root, deliverable):")
    lines.append('    """Check a single deliverable. Returns (ok, message)."""')
    lines.append("    path = deliverable['path']")
    lines.append("    full_path = project_root / path")
    lines.append("    is_dir = deliverable['is_dir']")
    lines.append("    is_glob = deliverable['is_glob']")
    lines.append("    hint = deliverable['validation_hint']")
    lines.append("")
    lines.append("    if is_glob:")
    lines.append("        matches = list(project_root.glob(path))")
    lines.append("        if not matches:")
    lines.append('            return False, f"No files matching glob: {path}"')
    lines.append('        return True, f"Found {len(matches)} matches for {path}: {[str(m.relative_to(project_root)) for m in matches]}"')
    lines.append("")
    lines.append("    if is_dir:")
    lines.append("        if not full_path.is_dir():")
    lines.append('            return False, f"Directory not found: {path}"')
    lines.append('        return True, f"Directory exists: {path}"')
    lines.append("")
    lines.append("    # File checks")
    lines.append("    if not full_path.exists():")
    lines.append('        return False, f"File not found: {path}"')
    lines.append("")
    lines.append("    # Content validation hints")
    lines.append("    if hint:")
    lines.append("        if 'valid JSON' in hint.lower() or 'json' in hint.lower():")
    lines.append("            try:")
    lines.append("                json.loads(full_path.read_text())")
    lines.append("            except json.JSONDecodeError as e:")
    lines.append('                return False, f"Invalid JSON in {path}: {e}"')
    lines.append('            return True, f"Valid JSON: {path}"')
    lines.append("        elif 'CL-' in hint or 'changelog' in hint.lower():")
    lines.append("            content = full_path.read_text()")
    lines.append("            if not re.search(r'CL-\\d+', content):")
    lines.append('                return False, f"No CL- entries in {path}"')
    lines.append('            return True, f"CHANGELOG has CL- entries: {path}"')
    lines.append("        elif 'executable' in hint.lower():")
    lines.append("            if not os.access(full_path, os.X_OK):")
    lines.append('                return False, f"Not executable: {path}"')
    lines.append('            return True, f"Executable: {path}"')
    lines.append("        elif 'yaml' in hint.lower() or 'yml' in hint.lower():")
    lines.append("            try:")
    lines.append("                import yaml")
    lines.append("                yaml.safe_load(full_path.read_text())")
    lines.append("            except Exception as e:")
    lines.append('                return False, f"Invalid YAML in {path}: {e}"')
    lines.append('            return True, f"Valid YAML: {path}"')
    lines.append("")
    lines.append('    return True, f"File exists: {path}"')
    lines.append("")
    lines.append("def main():")
    lines.append("    if len(sys.argv) < 2:")
    lines.append('        print("Usage: validator.py <step-file-path>")')
    lines.append("        sys.exit(1)")
    lines.append("")
    lines.append("    step_file = sys.argv[1]")
    lines.append("    project_root = find_project_root(step_file)")
    lines.append("    if not project_root:")
    lines.append('        print("ERROR: Could not find project root (.blueprint-chain)")')
    lines.append("        sys.exit(1)")
    lines.append("")
    
    # Add deliverable list
    lines.append("    deliverables = [")
    for d in deliverables:
        # Use Python True/False instead of JSON true/false
        d_python = d.copy()
        d_python['is_dir'] = d['is_dir']
        d_python['is_glob'] = d['is_glob']
        lines.append(f"        {repr(d_python)},")
    lines.append("    ]")
    lines.append("")
    lines.append("    all_ok = True")
    lines.append("    messages = []")
    lines.append("")
    lines.append("    for d in deliverables:")
    lines.append("        ok, msg = check_deliverable(project_root, d)")
    lines.append("        messages.append(msg)")
    lines.append("        if not ok:")
    lines.append("            all_ok = False")
    lines.append("")
    lines.append("    # Print all messages")
    lines.append("    for msg in messages:")
    lines.append('        print(msg)')
    lines.append("")
    lines.append("    if all_ok:")
    lines.append(f'        print(f"OK: Phase {phase_num} validation passed")')
    lines.append("        sys.exit(0)")
    lines.append("    else:")
    lines.append(f'        print(f"FAIL: Phase {phase_num} validation failed")')
    lines.append("        sys.exit(1)")
    lines.append("")
    lines.append("if __name__ == '__main__':")
    lines.append("    main()")
    
    return "\n".join(lines)


def generate_all_validators(blueprint_path: Path, output_dir: Path) -> List[Path]:
    """Generate validator scripts for all phases in blueprint."""
    output_dir.mkdir(parents=True, exist_ok=True)
    phases = extract_blueprint_deliverables(blueprint_path)
    generated = []
    
    for phase in phases:
        phase_num = phase["phase"]
        validator_code = generate_validator_code(phase)
        validator_path = output_dir / f"validate_phase{phase_num}_blueprint.py"
        validator_path.write_text(validator_code)
        validator_path.chmod(0o755)
        generated.append(validator_path)
        print(f"[OK] Generated {validator_path}")
    
    return generated


def get_validator_for_phase(blueprint_path: Path, phase_num: int, output_dir: Path) -> Optional[Path]:
    """Get (generate if needed) validator for specific phase."""
    validator_path = output_dir / f"validate_phase{phase_num}_blueprint.py"
    if validator_path.exists():
        return validator_path
    
    # Generate all and return the one requested
    generated = generate_all_validators(blueprint_path, output_dir)
    for v in generated:
        if f"validate_phase{phase_num}_blueprint.py" in str(v):
            return v
    return None


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Generate validators from blueprint deliverables")
    parser.add_argument("blueprint", help="Path to blueprint.md")
    parser.add_argument("--output-dir", "-o", help="Output directory for validators", default=".blueprint-chain/validators")
    parser.add_argument("--phase", type=int, help="Generate only for specific phase")
    args = parser.parse_args()
    
    bp_path = Path(args.blueprint)
    out_dir = Path(args.output_dir)
    
    if args.phase:
        v = get_validator_for_phase(bp_path, args.phase, out_dir)
        if v:
            print(f"Generated: {v}")
        else:
            print(f"No deliverables found for phase {args.phase}")
            sys.exit(1)
    else:
        generated = generate_all_validators(bp_path, out_dir)
        print(f"Generated {len(generated)} validators in {out_dir}")