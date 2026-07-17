#!/usr/bin/env python3
"""
Validation script for enterprise-organization skill.
Produces standardized JSON output matching main.py schema.
"""

import json
import sys
import os
from datetime import datetime
from pathlib import Path


def validate_skill_structure(skill_dir: Path) -> dict:
    """Validate enterprise skill structure."""
    issues = []
    warnings = []
    
    # Check required directories
    for dir_name in ["scripts", "references"]:
        dir_path = skill_dir / dir_name
        if not dir_path.exists():
            issues.append(f"Missing required directory: {dir_name}/")
        elif not list(dir_path.iterdir()):
            warnings.append(f"Empty directory: {dir_name}/")
    
    # Check SKILL.md
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        issues.append("Missing SKILL.md")
    else:
        content = skill_md.read_text()
        # Check for enterprise sections
        required_sections = [
            "Provider Compatibility",
            "Free-First Strategy",
            "Enforced Output Statistics",
            "Error Handling",
            "Enhancement Hooks",
            "Scripts Reference",
            "Key References"
        ]
        for section in required_sections:
            if section not in content:
                warnings.append(f"Missing enterprise section: '{section}'")
    
    # Check frontmatter
    if skill_md.exists():
        content = skill_md.read_text()
        if not content.startswith("---"):
            issues.append("Missing YAML frontmatter")
        else:
            import yaml
            try:
                fm_end = content.index("---", 3)
                frontmatter = yaml.safe_load(content[3:fm_end])
                if not frontmatter.get("name"):
                    issues.append("Frontmatter missing 'name'")
                if not frontmatter.get("description"):
                    issues.append("Frontmatter missing 'description'")
            except Exception as e:
                issues.append(f"Invalid frontmatter YAML: {e}")
    
    # Check for hardcoded paths
    for py_file in skill_dir.rglob("*.py"):
        try:
            text = py_file.read_text()
            if "/home/" in text or "/tmp/" in text or "C:\\" in text:
                # Allow in comments and strings that look like examples
                lines = text.split("\n")
                for i, line in enumerate(lines):
                    if any(p in line for p in ["/home/", "/tmp/", "C:\\"]):
                        if not line.strip().startswith("#"):
                            warnings.append(f"Possible hardcoded path in {py_file.name}:{i+1}")
        except Exception:
            pass
    
    # Check required scripts exist
    required_scripts = [
        "enterprise-org.py",
        "validate_structure.py",
        "security_hardening.py",
        "todo_validator.py",
        "placeholder_scanner.py",
        "self_validator.py",
        "changelog_manager.py",
        "version_manager.py",
        "git_control.py",
        "phase_tagger.py",
        "main.py",
        "validate.py"
    ]
    scripts_dir = skill_dir / "scripts"
    for script in required_scripts:
        if not (scripts_dir / script).exists():
            issues.append(f"Missing required script: {script}")
    
    return {"issues": issues, "warnings": warnings}


def main():
    """Main validation entry point."""
    skill_dir = Path(__file__).parent.parent
    
    validation_result = validate_skill_structure(skill_dir)
    
    is_valid = len(validation_result["issues"]) == 0
    
    result = {
        "operation": "validate",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "status": "success" if is_valid else "failed",
        "skill_name": "enterprise-organization",
        "details": {
            "valid": is_valid,
            "issues": validation_result["issues"],
            "warnings": validation_result["warnings"],
            "summary": f"{len(validation_result['issues'])} issues, {len(validation_result['warnings'])} warnings"
        },
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
    }
    print(json.dumps(result, indent=2))
    return 0 if is_valid else 1


if __name__ == "__main__":
    sys.exit(main())