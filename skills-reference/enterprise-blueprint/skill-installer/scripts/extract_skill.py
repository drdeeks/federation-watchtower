#!/usr/bin/env python3
"""
Extract .skill zip archives gracefully.
Handles nested zips, multiple skills, and preserves directory structure.
"""

import os
import sys
import json
import zipfile
import shutil
import argparse
import tempfile
from pathlib import Path
from typing import Dict, List, Optional

def detect_skill_structure(extract_dir: Path) -> List[Dict]:
    """Detect skill structure in extracted directory."""
    skills = []
    
    # Look for SKILL.md files
    for skill_md in extract_dir.rglob("SKILL.md"):
        skill_dir = skill_md.parent
        skill_name = skill_dir.name
        
        # Check for supporting directories
        has_scripts = (skill_dir / "scripts").exists()
        has_references = (skill_dir / "references").exists()
        has_assets = (skill_dir / "assets").exists()
        
        # Get all files
        files = []
        for item in skill_dir.rglob("*"):
            if item.is_file():
                files.append(str(item.relative_to(skill_dir)))
        
        skills.append({
            "name": skill_name,
            "path": str(skill_dir),
            "has_scripts": has_scripts,
            "has_references": has_references,
            "has_assets": has_assets,
            "file_count": len(files),
            "files": files
        })
    
    return skills

def extract_skill_archive(archive_path: str, output_dir: str = None, 
                         flatten: bool = False) -> Dict:
    """
    Extract a .skill zip archive.
    
    Args:
        archive_path: Path to the .skill file
        output_dir: Output directory (default: temp dir)
        flatten: Flatten nested directories
    
    Returns:
        Dictionary with extraction results
    """
    archive_path = Path(archive_path)
    
    if not archive_path.exists():
        return {"success": False, "error": f"Archive not found: {archive_path}"}
    
    if not archive_path.suffix == '.skill' and not archive_path.suffix == '.zip':
        return {"success": False, "error": f"Not a .skill or .zip file: {archive_path}"}
    
    # Create output directory
    if output_dir:
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
    else:
        output_path = Path(tempfile.mkdtemp(prefix="skill_extract_"))
    
    try:
        with zipfile.ZipFile(archive_path, 'r') as zip_ref:
            zip_ref.extractall(output_path)
        
        # Detect skill structure
        skills = detect_skill_structure(output_path)
        
        if not skills:
            return {
                "success": False,
                "error": "No SKILL.md found in archive",
                "extracted_to": str(output_path)
            }
        
        # If flatten and multiple skills, reorganize
        if flatten and len(skills) > 1:
            flattened_dir = output_path / "flattened"
            flattened_dir.mkdir(exist_ok=True)
            
            for skill in skills:
                skill_src = Path(skill["path"])
                skill_dst = flattened_dir / skill["name"]
                shutil.copytree(skill_src, skill_dst, dirs_exist_ok=True)
                skill["path"] = str(skill_dst)
            
            skills = detect_skill_structure(flattened_dir)
        
        return {
            "success": True,
            "extracted_to": str(output_path),
            "skills_found": len(skills),
            "skills": skills,
            "total_files": sum(s["file_count"] for s in skills)
        }
    
    except zipfile.BadZipFile as e:
        return {"success": False, "error": f"Invalid zip file: {e}"}
    except Exception as e:
        return {"success": False, "error": str(e)}

def extract_nested_archives(extract_dir: Path) -> List[Dict]:
    """Extract any nested .skill or .zip archives."""
    nested_extractions = []
    
    for item in extract_dir.rglob("*.skill"):
        if item.is_file():
            result = extract_skill_archive(str(item), str(item.parent))
            nested_extractions.append({
                "archive": str(item),
                "result": result
            })
    
    for item in extract_dir.rglob("*.zip"):
        if item.is_file() and item.name != extract_dir.name:
            result = extract_skill_archive(str(item), str(item.parent))
            nested_extractions.append({
                "archive": str(item),
                "result": result
            })
    
    return nested_extractions

def extract_to_directory(archive_path: str, target_dir: str, 
                        skill_name: str = None) -> Dict:
    """Extract skill to a specific directory with proper structure."""
    target_path = Path(target_dir)
    
    # Determine skill name
    if not skill_name:
        skill_name = Path(archive_path).stem
    
    skill_dir = target_path / skill_name
    skill_dir.mkdir(parents=True, exist_ok=True)
    
    # Extract to temp dir first
    temp_dir = tempfile.mkdtemp(prefix="skill_extract_")
    
    try:
        result = extract_skill_archive(archive_path, temp_dir)
        
        if not result["success"]:
            return result
        
        # Find the SKILL.md in extracted content
        for skill in result["skills"]:
            skill_src = Path(skill["path"])
            
            # Copy all files to target
            for item in skill_src.rglob("*"):
                if item.is_file():
                    rel_path = item.relative_to(skill_src)
                    dest_path = skill_dir / rel_path
                    dest_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(item, dest_path)
        
        return {
            "success": True,
            "skill_name": skill_name,
            "extracted_to": str(skill_dir),
            "files_extracted": result["total_files"]
        }
    
    finally:
        shutil.rmtree(temp_dir)

def list_archive_contents(archive_path: str) -> Dict:
    """List contents of a .skill archive without extracting."""
    try:
        with zipfile.ZipFile(archive_path, 'r') as zip_ref:
            contents = zip_ref.namelist()
            
            # Group by directory
            dirs = {}
            for item in contents:
                parts = Path(item).parts
                if len(parts) > 1:
                    top_dir = parts[0]
                    if top_dir not in dirs:
                        dirs[top_dir] = []
                    dirs[top_dir].append(item)
                else:
                    if "." not in dirs:
                        dirs["."] = []
                    dirs["."].append(item)
            
            return {
                "success": True,
                "archive": archive_path,
                "total_files": len(contents),
                "directories": dirs,
                "contents": contents
            }
    
    except zipfile.BadZipFile as e:
        return {"success": False, "error": f"Invalid zip file: {e}"}
    except Exception as e:
        return {"success": False, "error": str(e)}

def main():
    parser = argparse.ArgumentParser(description="Extract .skill zip archives")
    parser.add_argument("archive", help=".skill or .zip file to extract")
    parser.add_argument("--output", "-o", help="Output directory")
    parser.add_argument("--flatten", action="store_true",
                       help="Flatten nested directories")
    parser.add_argument("--list", "-l", action="store_true",
                       help="List archive contents without extracting")
    parser.add_argument("--to-dir", help="Extract to specific directory")
    parser.add_argument("--skill-name", help="Skill name for extraction")
    parser.add_argument("--json", action="store_true",
                       help="Output results as JSON")
    
    args = parser.parse_args()
    
    if args.list:
        result = list_archive_contents(args.archive)
    elif args.to_dir:
        result = extract_to_directory(args.archive, args.to_dir, args.skill_name)
    else:
        result = extract_skill_archive(args.archive, args.output, args.flatten)
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if result["success"]:
            print(f"✓ Extracted: {result.get('skills_found', 1)} skill(s)")
            print(f"  Location: {result.get('extracted_to', 'unknown')}")
            print(f"  Files: {result.get('total_files', 0)}")
            
            if "skills" in result:
                for skill in result["skills"]:
                    print(f"  - {skill['name']}: {skill['file_count']} files")
        else:
            print(f"✗ Extraction failed: {result.get('error', 'Unknown error')}")
            sys.exit(1)

if __name__ == "__main__":
    main()
