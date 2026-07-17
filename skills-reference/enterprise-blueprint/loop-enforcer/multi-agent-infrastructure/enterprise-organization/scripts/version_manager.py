#!/usr/bin/env python3
"""
Version Manager - Semantic versioning and release management for enterprise organization.
Handles version bumping, release tagging, changelog versioning, and release notes generation.
"""

import sys
import json
import argparse
import subprocess
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple


class VersionManager:
    def __init__(self, workspace: Path):
        self.workspace = workspace.resolve()
        self.results = {
            "operation": "version_manager",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }

    def get_current_version(self) -> str:
        """Get current version from git tags or VERSION file."""
        # Try git tags first
        try:
            result = subprocess.run(
                ["git", "describe", "--tags", "--abbrev=0", "--match", "v*"],
                cwd=self.workspace, capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip().lstrip('v')
        except Exception:
            pass

        # Try VERSION file
        version_file = self.workspace / "VERSION"
        if version_file.exists():
            return version_file.read_text().strip()

        # Try pyproject.toml or package.json
        for f in ["pyproject.toml", "package.json", "setup.py", "Cargo.toml"]:
            fp = self.workspace / f
            if fp.exists():
                content = fp.read_text()
                if f == "pyproject.toml":
                    match = re.search(r'version\s*=\s*["\']([^"\']+)["\']', content)
                    if match:
                        return match.group(1)
                elif f == "package.json":
                    import json as json_module
                    try:
                        data = json_module.loads(content)
                        if "version" in data:
                            return data["version"]
                    except Exception:
                        pass

        return "0.1.0"  # Default

    def parse_version(self, version: str) -> Tuple[int, int, int, str]:
        """Parse semantic version into major, minor, patch, prerelease."""
        # Handle v prefix
        version = version.lstrip('v')
        
        # Split version and prerelease
        parts = version.split('-', 1)
        version_part = parts[0]
        prerelease = parts[1] if len(parts) > 1 else ""
        
        # Parse major.minor.patch
        version_numbers = version_part.split('.')
        major = int(version_numbers[0]) if len(version_numbers) > 0 else 0
        minor = int(version_numbers[1]) if len(version_numbers) > 1 else 0
        patch = int(version_numbers[2]) if len(version_numbers) > 2 else 0
        
        return major, minor, patch, prerelease

    def bump_version(self, current: str, bump_type: str, prerelease: str = "") -> str:
        """Bump version according to semver rules."""
        major, minor, patch, _ = self.parse_version(current)
        
        if bump_type == "major":
            major += 1
            minor = 0
            patch = 0
        elif bump_type == "minor":
            minor += 1
            patch = 0
        elif bump_type == "patch":
            patch += 1
        else:
            raise ValueError(f"Invalid bump type: {bump_type}. Use major, minor, or patch")
        
        new_version = f"{major}.{minor}.{patch}"
        if prerelease:
            new_version += f"-{prerelease}"
        
        return new_version

    def set_version(self, version: str) -> Dict:
        """Set version in all relevant files."""
        self.results["operation"] = "set_version"
        updated_files = []
        
        # Update VERSION file
        version_file = self.workspace / "VERSION"
        version_file.write_text(version + "\n")
        updated_files.append("VERSION")
        
        # Update pyproject.toml if exists
        pyproject = self.workspace / "pyproject.toml"
        if pyproject.exists():
            content = pyproject.read_text()
            new_content = re.sub(
                r'version\s*=\s*["\'][^"\']+["\']',
                f'version = "{version}"',
                content
            )
            pyproject.write_text(new_content)
            updated_files.append("pyproject.toml")
        
        # Update package.json if exists
        package_json = self.workspace / "package.json"
        if package_json.exists():
            import json as json_module
            try:
                data = json_module.loads(package_json.read_text())
                data["version"] = version
                package_json.write_text(json_module.dumps(data, indent=2))
                updated_files.append("package.json")
            except Exception:
                pass
        
        # Update setup.py if exists
        setup_py = self.workspace / "setup.py"
        if setup_py.exists():
            content = setup_py.read_text()
            new_content = re.sub(
                r'version\s*=\s*["\'][^"\']+["\']',
                f'version = "{version}"',
                content
            )
            setup_py.write_text(new_content)
            updated_files.append("setup.py")
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "version": version,
            "updated_files": updated_files
        }
        self.results["message"] = f"Version set to {version} in {len(updated_files)} files"
        return self.results

    def create_release(self, version: str, message: str = "", push: bool = False) -> Dict:
        """Create a git tag for the release."""
        self.results["operation"] = "create_release"
        
        # Check if git repo
        if not (self.workspace / ".git").exists():
            self.results["status"] = "failed"
            self.results["message"] = "Not a git repository"
            return self.results
        
        tag = f"v{version}"
        
        # Create annotated tag
        try:
            if message:
                cmd = ["git", "tag", "-a", tag, "-m", message]
            else:
                cmd = ["git", "tag", "-a", tag, "-m", f"Release {tag}"]
            
            result = subprocess.run(cmd, cwd=self.workspace, capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                # Tag might already exist, try to force
                if "already exists" in result.stderr:
                    self.results["status"] = "failed"
                    self.results["message"] = f"Tag {tag} already exists"
                    return self.results
                raise Exception(result.stderr)
        except Exception as e:
            self.results["status"] = "failed"
            self.results["message"] = f"Failed to create tag: {e}"
            return self.results
        
        # Push tag if requested
        if push:
            try:
                result = subprocess.run(
                    ["git", "push", "origin", tag],
                    cwd=self.workspace, capture_output=True, text=True, timeout=30
                )
                if result.returncode != 0:
                    self.results["status"] = "failed"
                    self.results["message"] = f"Tag created but push failed: {result.stderr}"
                    return self.results
            except Exception as e:
                self.results["status"] = "failed"
                self.results["message"] = f"Tag created but push failed: {e}"
                return self.results
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "version": version,
            "tag": tag,
            "pushed": push
        }
        self.results["message"] = f"Release {tag} created{' and pushed' if push else ''}"
        return self.results

    def generate_release_notes(self, version: str, from_tag: str = None) -> Dict:
        """Generate release notes from git log and CHANGELOG."""
        self.results["operation"] = "generate_release_notes"
        
        if not (self.workspace / ".git").exists():
            self.results["status"] = "failed"
            self.results["message"] = "Not a git repository"
            return self.results
        
        # Get commits since last tag or all commits
        if from_tag:
            cmd = ["git", "log", f"{from_tag}..HEAD", "--pretty=format:%h %s (%an)", "--no-merges"]
        else:
            cmd = ["git", "log", "--pretty=format:%h %s (%an)", "--no-merges"]
        
        try:
            result = subprocess.run(cmd, cwd=self.workspace, capture_output=True, text=True, timeout=10)
            commits = result.stdout.strip().split('\n') if result.stdout.strip() else []
        except Exception:
            commits = []
        
        # Also get CHANGELOG entries for this version
        changelog_entries = []
        changelog_path = self.workspace / "CHANGELOG.md"
        if changelog_path.exists():
            content = changelog_path.read_text()
            # Find entries for this version
            in_version = False
            for line in content.split('\n'):
                if line.startswith(f"## [{version}]"):
                    in_version = True
                    continue
                elif in_version and line.startswith("## [") and not line.startswith(f"## [{version}]"):
                    break
                elif in_version and line.strip():
                    changelog_entries.append(line)
        
        # Format release notes
        notes = f"# Release {version}\n\n"
        notes += f"**Date:** {datetime.now().strftime('%Y-%m-%d')}\n\n"
        
        if changelog_entries:
            notes += "## Changes\n\n"
            for entry in changelog_entries:
                notes += f"- {entry}\n"
            notes += "\n"
        
        if commits:
            notes += "## Commits\n\n"
            for commit in commits[:50]:  # Limit to 50 commits
                notes += f"- {commit}\n"
            if len(commits) > 50:
                notes += f"\n... and {len(commits) - 50} more commits\n"
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "version": version,
            "notes": notes,
            "commit_count": len(commits),
            "changelog_entries": len(changelog_entries)
        }
        self.results["message"] = f"Release notes generated for {version}"
        return self.results

    def list_versions(self) -> Dict:
        """List all versions (git tags)."""
        self.results["operation"] = "list_versions"
        
        if not (self.workspace / ".git").exists():
            self.results["status"] = "failed"
            self.results["message"] = "Not a git repository"
            return self.results
        
        try:
            result = subprocess.run(
                ["git", "tag", "--sort=-v:refname", "--list", "v*"],
                cwd=self.workspace, capture_output=True, text=True, timeout=10
            )
            tags = result.stdout.strip().split('\n') if result.stdout.strip() else []
            tags = [t for t in tags if t]
        except Exception:
            tags = []
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "versions": [t.lstrip('v') for t in tags],
            "tags": tags,
            "current": self.get_current_version()
        }
        self.results["message"] = f"Found {len(tags)} versions"
        return self.results


def main():
    parser = argparse.ArgumentParser(description="Semantic Version Manager")
    parser.add_argument("--workspace", default=".", help="Workspace path")
    parser.add_argument("--json", action="store_true", help="Output JSON")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # Common arguments for all subparsers
    common_args = [
        ("--workspace", {"default": ".", "help": "Workspace path"}),
        ("--json", {"action": "store_true", "help": "Output JSON"})
    ]

    # get command
    get_parser = subparsers.add_parser("get", help="Get current version")
    for arg, opts in common_args:
        get_parser.add_argument(arg, **opts)

    # set command
    set_parser = subparsers.add_parser("set", help="Set version in files")
    set_parser.add_argument("version", help="Version to set (e.g., 1.2.3)")
    for arg, opts in common_args:
        set_parser.add_argument(arg, **opts)

    # bump command
    bump_parser = subparsers.add_parser("bump", help="Bump version")
    bump_parser.add_argument("type", choices=["major", "minor", "patch"], help="Bump type")
    bump_parser.add_argument("--prerelease", default="", help="Prerelease identifier")
    for arg, opts in common_args:
        bump_parser.add_argument(arg, **opts)

    # release command
    release_parser = subparsers.add_parser("release", help="Create release tag")
    release_parser.add_argument("version", help="Version to release")
    release_parser.add_argument("--message", default="", help="Tag message")
    release_parser.add_argument("--push", action="store_true", help="Push tag to origin")
    for arg, opts in common_args:
        release_parser.add_argument(arg, **opts)

    # notes command
    notes_parser = subparsers.add_parser("notes", help="Generate release notes")
    notes_parser.add_argument("version", help="Version for release notes")
    notes_parser.add_argument("--from-tag", help="Generate notes from this tag")
    for arg, opts in common_args:
        notes_parser.add_argument(arg, **opts)

    # list command
    list_parser = subparsers.add_parser("list", help="List all versions")
    for arg, opts in common_args:
        list_parser.add_argument(arg, **opts)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    manager = VersionManager(Path(args.workspace))

    if args.command == "get":
        version = manager.get_current_version()
        result = {
            "operation": "get_version",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {"version": version},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }
        print(json.dumps(result, indent=2))
        sys.exit(0)

    elif args.command == "set":
        result = manager.set_version(args.version)

    elif args.command == "bump":
        current = manager.get_current_version()
        new_version = manager.bump_version(current, args.type, args.prerelease)
        result = manager.set_version(new_version)

    elif args.command == "release":
        result = manager.create_release(args.version, args.message, args.push)

    elif args.command == "notes":
        result = manager.generate_release_notes(args.version, args.from_tag)

    elif args.command == "list":
        result = manager.list_versions()

    else:
        print(f"Unknown command: {args.command}")
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        status = "✓" if result.get("status") == "success" else "✗"
        print(f"{status} {result.get('message')}")
        if "details" in result and not args.json:
            for k, v in result["details"].items():
                if k != "notes":
                    print(f"  {k}: {v}")

    sys.exit(0 if result.get("status") == "success" else 1)


if __name__ == "__main__":
    main()