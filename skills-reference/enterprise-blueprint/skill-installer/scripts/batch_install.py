#!/usr/bin/env python3
"""
Batch install multiple skills from packages or directories.
Handles .skill archives, directories, and mixed formats.
"""

import os
import sys
import json
import argparse
import tempfile
import shutil
from pathlib import Path
from typing import Dict, List, Optional
from datetime import datetime

sys.dont_write_bytecode = True  # keep __pycache__ out of skill trees

# Import our modules
sys.path.insert(0, str(Path(__file__).parent))
from install_skill import install_skill, detect_format, SKILLS_DIR
from extract_skill import extract_skill_archive

def scan_package(package_path: Path) -> List[Dict]:
    """Scan a package directory for skills."""
    skills = []
    
    for item in package_path.iterdir():
        if item.is_dir():
            # Check if it's a skill directory
            skill_md = item / "SKILL.md"
            if skill_md.exists():
                skills.append({
                    "type": "directory",
                    "path": str(item),
                    "name": item.name
                })
            else:
                # Check for nested skills
                nested_skills = scan_package(item)
                skills.extend(nested_skills)
        elif item.is_file():
            if item.suffix == '.skill':
                skills.append({
                    "type": "skill-zip",
                    "path": str(item),
                    "name": item.stem
                })
            elif item.suffix == '.zip':
                skills.append({
                    "type": "zip",
                    "path": str(item),
                    "name": item.stem
                })
    
    return skills

def extract_and_install(archive_path: str, target_dir: str, 
                       validate: bool = True) -> Dict:
    """Extract a zip archive and install all skills found."""
    temp_dir = tempfile.mkdtemp(prefix="batch_install_")
    
    try:
        # Extract archive
        extract_result = extract_skill_archive(archive_path, temp_dir)
        
        if not extract_result["success"]:
            return {"success": False, "error": extract_result["error"]}
        
        # Install each skill found
        results = []
        for skill in extract_result.get("skills", []):
            skill_dir = skill["path"]
            result = install_skill(skill_dir, target_dir, validate)
            results.append({
                "skill_name": skill["name"],
                "result": result
            })
        
        successes = sum(1 for r in results if r["result"]["success"])
        failures = len(results) - successes
        
        return {
            "success": failures == 0,
            "total": len(results),
            "successes": successes,
            "failures": failures,
            "results": results
        }
    
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

def batch_install_from_directory(package_dir: str, target_dir: str, 
                               validate: bool = True,
                               recursive: bool = True) -> Dict:
    """Batch install all skills from a directory."""
    package_path = Path(package_dir)
    
    if not package_path.exists():
        return {"success": False, "error": f"Package directory not found: {package_dir}"}
    
    # Scan for skills
    skills = scan_package(package_path)
    
    if not skills:
        return {"success": False, "error": "No skills found in package"}
    
    # Install each skill
    results = []
    for skill in skills:
        if skill["type"] in ["skill-zip", "zip"]:
            result = extract_and_install(skill["path"], target_dir, validate)
        else:
            result = install_skill(skill["path"], target_dir, validate)
        
        results.append({
            "skill_name": skill["name"],
            "type": skill["type"],
            "result": result
        })
    
    successes = sum(1 for r in results if r["result"]["success"])
    failures = len(results) - successes
    
    return {
        "success": failures == 0,
        "total": len(results),
        "successes": successes,
        "failures": failures,
        "results": results
    }

def batch_install_from_zip(zip_path: str, target_dir: str, 
                          validate: bool = True) -> Dict:
    """Batch install all skills from a zip archive."""
    return extract_and_install(zip_path, target_dir, validate)

def generate_report(results: Dict, output_file: str = None) -> str:
    """Generate a batch installation report."""
    report = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "summary": {
            "total": results["total"],
            "successes": results["successes"],
            "failures": results["failures"]
        },
        "details": []
    }
    
    for item in results["results"]:
        detail = {
            "skill_name": item["skill_name"],
            "type": item.get("type", "unknown"),
            "success": item["result"]["success"],
            "error": item["result"].get("error"),
            "installed_to": item["result"].get("installed_to")
        }
        report["details"].append(detail)
    
    report_text = json.dumps(report, indent=2)
    
    if output_file:
        Path(output_file).write_text(report_text)
    
    return report_text

def main():
    parser = argparse.ArgumentParser(description="Batch install multiple skills")
    parser.add_argument("package", help="Package directory or zip file")
    parser.add_argument("--target", default=str(SKILLS_DIR),
                       help="Target skills directory")
    parser.add_argument("--validate", action="store_true", default=True,
                       help="Validate skills before installation")
    parser.add_argument("--no-validate", action="store_true",
                       help="Skip validation")
    parser.add_argument("--recursive", action="store_true", default=True,
                       help="Scan directories recursively")
    parser.add_argument("--no-recursive", action="store_true",
                       help="Don't scan directories recursively")
    parser.add_argument("--report", help="Output report file")
    parser.add_argument("--json", action="store_true",
                       help="Output results as JSON")
    
    args = parser.parse_args()
    
    if args.no_validate:
        args.validate = False
    if args.no_recursive:
        args.recursive = False
    
    # Determine input type
    package_path = Path(args.package)
    
    if package_path.is_file() and package_path.suffix == '.zip':
        results = batch_install_from_zip(args.package, args.target, args.validate)
    elif package_path.is_dir():
        results = batch_install_from_directory(args.package, args.target, 
                                              args.validate, args.recursive)
    else:
        print(f"✗ Invalid package: {args.package}")
        sys.exit(1)
    
    # Generate report
    if args.report:
        generate_report(results, args.report)
        print(f"✓ Report saved to: {args.report}")
    
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print(f"\n{'='*50}")
        print(f"Batch Installation Complete")
        print(f"{'='*50}")
        print(f"Total: {results['total']}")
        print(f"Successes: {results['successes']}")
        print(f"Failures: {results['failures']}")
        print(f"{'='*50}\n")
        
        for item in results["results"]:
            status = "✓" if item["result"]["success"] else "✗"
            print(f"{status} {item['skill_name']}")
            if not item["result"]["success"]:
                print(f"  Error: {item['result'].get('error', 'Unknown')}")
        
        sys.exit(0 if results["success"] else 1)

if __name__ == "__main__":
    main()
