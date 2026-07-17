#!/usr/bin/env python3
"""
backup-skill.py — Backup a skill directory to a timestamped archive.
Creates a .tar.gz of the skill for portability.
"""
import argparse
import json
import os
import subprocess
import sys
import tarfile
from datetime import datetime
from pathlib import Path


def backup_skill(skill_name, output_dir=None):
    """Backup a skill to a tar.gz archive."""
    skill_dir = Path.home() / ".hermes" / "skills" / skill_name
    if not skill_dir.exists():
        return {"status": "error", "detail": f"Skill {skill_name} not found"}
    
    if output_dir is None:
        output_dir = Path.home() / "Downloads"
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    archive_name = f"{skill_name}-{timestamp}.tar.gz"
    archive_path = output_dir / archive_name
    
    with tarfile.open(archive_path, "w:gz") as tar:
        # Add SKILL.md
        skill_md = skill_dir / "SKILL.md"
        if skill_md.exists():
            tar.add(skill_md, arcname=f"{skill_name}/SKILL.md")
        
        # Add __init__.py
        init_py = skill_dir / "__init__.py"
        if init_py.exists():
            tar.add(init_py, arcname=f"{skill_name}/__init__.py")
        
        # Add scripts/
        scripts_dir = skill_dir / "scripts"
        if scripts_dir.exists():
            for f in scripts_dir.iterdir():
                if f.is_file() and not f.name.startswith("."):
                    tar.add(f, arcname=f"{skill_name}/scripts/{f.name}")
        
        # Add references/
        refs_dir = skill_dir / "references"
        if refs_dir.exists():
            for f in refs_dir.rglob("*"):
                if f.is_file() and not f.name.startswith("."):
                    rel = f.relative_to(refs_dir)
                    tar.add(f, arcname=f"{skill_name}/references/{rel}")
    
    return {
        "status": "ok",
        "archive": str(archive_path),
        "size": archive_path.stat().st_size,
        "skill": skill_name
    }


def main():
    parser = argparse.ArgumentParser(description="Backup a skill to tar.gz")
    parser.add_argument("--skill", required=True, help="Skill name")
    parser.add_argument("--output", help="Output directory")
    args = parser.parse_args()
    
    result = backup_skill(args.skill, args.output)
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
