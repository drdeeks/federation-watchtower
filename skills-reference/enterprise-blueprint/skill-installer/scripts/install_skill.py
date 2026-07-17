#!/usr/bin/env python3
"""
Graceful skill installer with automatic validation delegated to
skill-creator (the single source of truth for skill validity).
Handles .skill zip archives, directory-based skills, and remote packages.
"""

import os
import sys
import json
import zipfile
import shutil
import hashlib
import argparse
import tempfile
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse
import uuid

sys.dont_write_bytecode = True  # keep __pycache__ out of skill trees

# Validation is DELEGATED — no rules live in this skill.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_install import validate_skill as _delegate_validate

# Constants - use environment variables for platform agnosticism
SKILLS_DIR = Path(os.environ.get("OPENCODE_SKILLS_DIR",
    Path.home() / ".config" / "opencode" / "skills"))
RECEIPTS_DIR = SKILLS_DIR / ".receipts"

def ensure_dirs():
    """Ensure required directories exist."""
    RECEIPTS_DIR.mkdir(parents=True, exist_ok=True)

def detect_format(path: str) -> Dict:
    """Detect the format of a skill or package."""
    path_obj = Path(path)
    
    if path_obj.is_file() and path_obj.suffix == '.skill':
        return {
            "format": "skill-zip",
            "path": str(path_obj.absolute()),
            "is_archive": True
        }
    elif path_obj.is_file() and path_obj.suffix == '.zip':
        return {
            "format": "skill-zip",
            "path": str(path_obj.absolute()),
            "is_archive": True
        }
    elif path_obj.is_dir():
        # Check if it's a single skill or a package
        skill_md = path_obj / "SKILL.md"
        if skill_md.exists():
            return {
                "format": "directory",
                "path": str(path_obj.absolute()),
                "is_archive": False,
                "skill_name": path_obj.name
            }
        else:
            # It's a package directory
            skills_found = []
            for item in path_obj.iterdir():
                if item.is_dir() and (item / "SKILL.md").exists():
                    skills_found.append(item.name)
                elif item.is_file() and item.suffix == '.skill':
                    skills_found.append(item.stem)
            
            return {
                "format": "package",
                "path": str(path_obj.absolute()),
                "is_archive": False,
                "skills_found": skills_found
            }
    elif path.startswith(('http://', 'https://', 'git@')):
        return {
            "format": "remote",
            "path": path,
            "is_archive": False
        }
    else:
        return {
            "format": "unknown",
            "path": str(path_obj.absolute()) if path_obj.exists() else path,
            "is_archive": False
        }

def extract_skill_archive(archive_path: str, output_dir: str) -> Dict:
    """Extract a .skill zip archive."""
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    with zipfile.ZipFile(archive_path, 'r') as zip_ref:
        zip_ref.extractall(output_path)
    
    # Find SKILL.md in extracted content
    skill_md_files = list(output_path.rglob("SKILL.md"))
    
    if not skill_md_files:
        return {"success": False, "error": "No SKILL.md found in archive"}
    
    # Get the skill directory (parent of SKILL.md)
    skill_dir = skill_md_files[0].parent
    
    return {
        "success": True,
        "skill_dir": str(skill_dir),
        "files_extracted": len(list(output_path.rglob("*")))
    }

def validate_skill(skill_dir: str) -> Dict:
    """Validate via skill-creator's validate.py (basic tier for installs).
    Returns success=False when the skill is invalid OR the delegation
    itself failed — installs must never proceed unvalidated."""
    verdict = _delegate_validate(skill_dir, enterprise=False)
    if not verdict.get("success"):
        return {"success": False, "error": verdict.get("error", "delegation failed")}
    if not verdict.get("valid"):
        fails = [f"{c.get('name')}: {c.get('detail', '')}"
                 for c in verdict.get("checks", [])
                 if not c.get("passed") and c.get("severity") == "FAIL"]
        return {
            "success": False,
            "status": "invalid",
            "error": f"{verdict.get('fails', 0)} validation fail(s)",
            "output": "\n".join(fails),
        }
    return {"success": True, "status": "valid",
            "output": f"valid at basic tier ({verdict.get('warnings', 0)} warnings)"}

def calculate_checksum(path: str) -> str:
    """Calculate SHA256 checksum of a file or directory."""
    if os.path.isfile(path):
        with open(path, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    else:
        # Directory - hash all files
        hasher = hashlib.sha256()
        for root, dirs, files in os.walk(path):
            for file in sorted(files):
                filepath = os.path.join(root, file)
                with open(filepath, 'rb') as f:
                    hasher.update(f.read())
        return hasher.hexdigest()

def create_receipt(skill_name: str, source: str, format_type: str, 
                   validation_score: float, files_installed: List[str]) -> Dict:
    """Create an installation receipt."""
    receipt = {
        "receipt_id": str(uuid.uuid4()),
        "skill_name": skill_name,
        "installed_at": datetime.utcnow().isoformat() + "Z",
        "source": source,
        "format": format_type,
        "validation_score": validation_score,
        "files_installed": files_installed,
        "checksum": None  # Would be calculated in production
    }
    
    receipt_path = RECEIPTS_DIR / f"{skill_name}_{receipt['receipt_id'][:8]}.json"
    with open(receipt_path, 'w') as f:
        json.dump(receipt, f, indent=2)
    
    return receipt

def install_skill(source: str, target_dir: str, validate: bool = True, 
                  rollback_on_failure: bool = True) -> Dict:
    """Main installation function."""
    ensure_dirs()
    
    # Step 1: Detect format
    format_info = detect_format(source)
    
    if format_info["format"] == "unknown":
        return {"success": False, "error": f"Unknown format: {source}"}
    
    # Step 2: Extract if needed
    temp_dir = None
    skill_dir = source
    
    if format_info.get("is_archive"):
        temp_dir = tempfile.mkdtemp(prefix="skill_install_")
        extract_result = extract_skill_archive(source, temp_dir)
        
        if not extract_result["success"]:
            return {"success": False, "error": extract_result["error"]}
        
        skill_dir = extract_result["skill_dir"]
    
    # Step 3: Validate if requested
    if validate:
        validation = validate_skill(skill_dir)
        
        if not validation["success"]:
            if temp_dir:
                shutil.rmtree(temp_dir)
            return {
                "success": False,
                "error": f"Validation failed: {validation.get('error', 'Unknown error')}",
                "validation_output": validation.get("output", "")
            }
    
    # Step 4: Install
    skill_path = Path(skill_dir)
    skill_name = skill_path.name
    
    # Check if already exists
    target_path = Path(target_dir) / skill_name
    backup_path = None
    
    if target_path.exists():
        if rollback_on_failure:
            backup_path = Path(tempfile.mkdtemp(prefix="skill_backup_")) / skill_name
            shutil.copytree(target_path, backup_path)
    
    # Create target directory
    target_path.mkdir(parents=True, exist_ok=True)
    
    # Copy files
    files_installed = []
    for item in skill_path.rglob("*"):
        if item.is_file():
            rel_path = item.relative_to(skill_path)
            dest_path = target_path / rel_path
            dest_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, dest_path)
            files_installed.append(str(rel_path))
    
    # Step 5: Post-install validation
    post_check = validate_skill(str(target_path))
    
    if not post_check["success"] and rollback_on_failure and backup_path:
        # Rollback
        shutil.rmtree(target_path)
        if backup_path.exists():
            shutil.move(backup_path, target_path)
        return {
            "success": False,
            "error": f"Post-install validation failed, rolled back: {post_check.get('error', '')}"
        }
    
    # Create receipt
    validation_score = 1.0  # Would come from actual validation
    receipt = create_receipt(skill_name, source, format_info["format"], 
                           validation_score, files_installed)
    
    # Cleanup
    if temp_dir:
        shutil.rmtree(temp_dir)
    if backup_path and backup_path.exists():
        shutil.rmtree(backup_path.parent)
    
    return {
        "success": True,
        "skill_name": skill_name,
        "installed_to": str(target_path),
        "files_installed": files_installed,
        "receipt": receipt
    }

def batch_install(package_dir: str, target_dir: str, validate_all: bool = True) -> Dict:
    """Batch install multiple skills from a package directory."""
    package_path = Path(package_dir)
    results = []
    
    # Find all skills in package
    for item in package_path.iterdir():
        if item.is_dir() and (item / "SKILL.md").exists():
            # Directory-based skill
            result = install_skill(str(item), target_dir, validate_all)
            results.append({"skill": item.name, "result": result})
        elif item.is_file() and item.suffix == '.skill':
            # .skill archive
            result = install_skill(str(item), target_dir, validate_all)
            results.append({"skill": item.stem, "result": result})
    
    successes = sum(1 for r in results if r["result"]["success"])
    failures = len(results) - successes
    
    return {
        "success": failures == 0,
        "total": len(results),
        "successes": successes,
        "failures": failures,
        "results": results
    }

def main():
    parser = argparse.ArgumentParser(description="Graceful skill installer")
    parser.add_argument("source", help="Skill file, directory, or package to install")
    parser.add_argument("--target", default=str(SKILLS_DIR), 
                       help="Target skills directory")
    parser.add_argument("--validate", action="store_true", default=True,
                       help="Validate via skill-creator's validate.py before install")
    parser.add_argument("--no-validate", action="store_true",
                       help="Skip validation")
    parser.add_argument("--rollback-on-failure", action="store_true", default=True,
                       help="Rollback on validation failure")
    parser.add_argument("--batch", action="store_true",
                       help="Batch install from package directory")
    parser.add_argument("--json", action="store_true",
                       help="Output results as JSON")
    
    args = parser.parse_args()
    
    if args.no_validate:
        args.validate = False
    
    if args.batch:
        result = batch_install(args.source, args.target, args.validate)
    else:
        result = install_skill(args.source, args.target, args.validate, 
                              args.rollback_on_failure)
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if result["success"]:
            print(f"✓ Installed: {result.get('skill_name', 'unknown')}")
            print(f"  Location: {result.get('installed_to', 'unknown')}")
            print(f"  Files: {len(result.get('files_installed', []))}")
        else:
            print(f"✗ Installation failed: {result.get('error', 'Unknown error')}")
            sys.exit(1)

if __name__ == "__main__":
    main()
