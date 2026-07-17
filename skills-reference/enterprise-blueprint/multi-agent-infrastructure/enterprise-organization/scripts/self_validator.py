#!/usr/bin/env python3
"""
Rigorous Self-Validation with Rollback Verification
Validates modular design, rollback capability, performance, and cross-references.
"""

import sys
import json
import argparse
import subprocess
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, List


class SelfValidator:
    def __init__(self, workspace: Path):
        self.workspace = workspace.resolve()
        self.results = {
            "operation": "self_validation",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }

    def check_modular_design(self) -> Dict:
        """Verify modular design principles."""
        issues = []
        checks = {}

        # Check for scripts directory with modular scripts
        scripts_dir = self.workspace / "scripts"
        if scripts_dir.exists():
            scripts = list(scripts_dir.glob("*.py")) + list(scripts_dir.glob("*.sh"))
            checks["scripts_count"] = len(scripts)
            checks["scripts_modular"] = len(scripts) > 1
            if len(scripts) <= 1:
                issues.append("Only one script found - modular design requires separation of concerns")
        else:
            issues.append("Missing scripts/ directory")
            checks["scripts_modular"] = False

        # Check for references directory
        refs_dir = self.workspace / "references"
        checks["has_references"] = refs_dir.exists()
        if not refs_dir.exists():
            issues.append("Missing references/ directory for deep documentation")

        # Check for config separation
        config_dir = self.workspace / "config"
        checks["has_config_dir"] = config_dir.exists()

        # Check for data separation
        data_dir = self.workspace / "data"
        checks["has_data_dir"] = data_dir.exists()

        return {"valid": len(issues) == 0, "issues": issues, "checks": checks}

    def check_rollback_capability(self) -> Dict:
        """Verify rollback capability exists and works."""
        issues = []
        checks = {}

        # Check for backups directory
        backups_dir = self.workspace / "backups"
        checks["has_backups_dir"] = backups_dir.exists()
        if not backups_dir.exists():
            issues.append("Missing backups/ directory - required for rollback")

        # Check for git repository (primary rollback mechanism)
        git_dir = self.workspace / ".git"
        checks["is_git_repo"] = git_dir.exists()
        if not git_dir.exists():
            issues.append("Not a git repository - git is primary rollback mechanism")

        # Check for CHANGELOG.md (audit trail for rollback decisions)
        changelog = self.workspace / "CHANGELOG.md"
        checks["has_changelog"] = changelog.exists()
        if not changelog.exists():
            issues.append("Missing CHANGELOG.md - required for rollback audit trail")

        # Check for TODO.md (state tracking for rollback context)
        todo = self.workspace / "TODO.md"
        checks["has_todo"] = todo.exists()

        # Test git status (can we rollback?)
        if checks["is_git_repo"]:
            try:
                result = subprocess.run(
                    ["git", "status", "--porcelain"],
                    cwd=self.workspace, capture_output=True, text=True, timeout=10
                )
                checks["git_clean"] = result.returncode == 0 and not result.stdout.strip()
                if not checks["git_clean"]:
                    issues.append("Git working directory has uncommitted changes - commit before rollback test")
            except Exception:
                checks["git_clean"] = False
                issues.append("Cannot check git status")

        return {"valid": len(issues) == 0, "issues": issues, "checks": checks}

    def check_performance_baseline(self) -> Dict:
        """Basic performance checks."""
        issues = []
        checks = {}

        # Check for large files that shouldn't be in repo
        large_files = []
        for file_path in self.workspace.rglob("*"):
            if file_path.is_file():
                # Skip excluded
                if any(p in str(file_path) for p in [".git", "node_modules", "backups", "logs", "data", "tmp", ".venv", "venv"]):
                    continue
                try:
                    size_mb = file_path.stat().st_size / (1024 * 1024)
                    if size_mb > 10:
                        large_files.append(f"{file_path.relative_to(self.workspace)}: {size_mb:.1f}MB")
                except Exception:
                    pass

        checks["large_files"] = large_files
        if large_files:
            issues.append(f"Large files in repo (consider git-lfs): {len(large_files)} files")

        # Check total repo size (excluding .git)
        total_size = 0
        for file_path in self.workspace.rglob("*"):
            if file_path.is_file() and ".git" not in str(file_path):
                try:
                    total_size += file_path.stat().st_size
                except Exception:
                    pass

        checks["total_size_mb"] = round(total_size / (1024 * 1024), 2)
        if checks["total_size_mb"] > 500:
            issues.append(f"Repository size {checks['total_size_mb']}MB exceeds 500MB threshold")

        return {"valid": len(issues) == 0, "issues": issues, "checks": checks}

    def check_cross_references(self) -> Dict:
        """Validate cross-references between files."""
        issues = []
        checks = {}

        readme = self.workspace / "README.md"
        changelog = self.workspace / "CHANGELOG.md"
        todo = self.workspace / "TODO.md"
        gitignore = self.workspace / ".gitignore"

        checks["readme_exists"] = readme.exists()
        checks["changelog_exists"] = changelog.exists()
        checks["todo_exists"] = todo.exists()
        checks["gitignore_exists"] = gitignore.exists()

        # Check README references CHANGELOG
        if readme.exists():
            readme_content = readme.read_text()
            checks["readme_refs_changelog"] = "CHANGELOG" in readme_content
            checks["readme_refs_todo"] = "TODO" in readme_content
            checks["readme_refs_gitignore"] = ".gitignore" in readme_content
            if not checks["readme_refs_changelog"]:
                issues.append("README.md should reference CHANGELOG.md")
            if not checks["readme_refs_gitignore"]:
                issues.append("README.md should reference .gitignore")

        # Check CHANGELOG format
        if changelog.exists():
            cl_content = changelog.read_text()
            checks["changelog_has_unreleased"] = "## [Unreleased]" in cl_content
            checks["changelog_has_versions"] = "## [" in cl_content
            if not checks["changelog_has_unreleased"]:
                issues.append("CHANGELOG.md missing [Unreleased] section")

        # Check TODO references validation
        if todo.exists():
            todo_content = todo.read_text()
            checks["todo_has_validation_rules"] = "validation" in todo_content.lower()
            checks["todo_has_phases"] = "phase" in todo_content.lower()

        return {"valid": len(issues) == 0, "issues": issues, "checks": checks}

    def verify_rollback_test(self) -> Dict:
        """Test actual rollback capability."""
        issues = []
        checks = {}

        git_dir = self.workspace / ".git"
        if not git_dir.exists():
            return {"valid": False, "issues": ["Not a git repo - cannot test rollback"], "checks": {}}

        try:
            # Get current commit
            result = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=self.workspace, capture_output=True, text=True, timeout=10
            )
            if result.returncode != 0:
                issues.append("Cannot get current commit")
                return {"valid": False, "issues": issues, "checks": {}}

            current_commit = result.stdout.strip()
            checks["current_commit"] = current_commit[:8]

            # Check if we can create a test commit and rollback
            test_file = self.workspace / ".rollback_test"
            test_file.write_text(f"rollback test {datetime.now().isoformat()}")

            subprocess.run(["git", "add", ".rollback_test"], cwd=self.workspace, capture_output=True, timeout=10)
            subprocess.run(["git", "commit", "-m", "rollback test commit"], cwd=self.workspace, capture_output=True, timeout=10)

            # Now rollback
            subprocess.run(["git", "reset", "--hard", "HEAD~1"], cwd=self.workspace, capture_output=True, timeout=10)

            # Verify file is gone
            checks["rollback_works"] = not test_file.exists()
            if not checks["rollback_works"]:
                issues.append("Rollback test failed - file still exists after reset")

            # Clean up - restore to original state
            subprocess.run(["git", "reset", "--hard", current_commit], cwd=self.workspace, capture_output=True, timeout=10)

        except Exception as e:
            issues.append(f"Rollback test error: {e}")

        return {"valid": len(issues) == 0, "issues": issues, "checks": checks}

    def run(self, verify_rollback: bool = False) -> Dict:
        """Run all self-validations."""
        all_issues = []

        # Modular design
        mod_result = self.check_modular_design()
        all_issues.extend(mod_result["issues"])

        # Rollback capability
        rollback_result = self.check_rollback_capability()
        all_issues.extend(rollback_result["issues"])

        # Performance
        perf_result = self.check_performance_baseline()
        all_issues.extend(perf_result["issues"])

        # Cross-references
        ref_result = self.check_cross_references()
        all_issues.extend(ref_result["issues"])

        # Actual rollback test (optional, can be destructive)
        rollback_test = {"valid": True, "issues": [], "checks": {}}
        if verify_rollback:
            rollback_test = self.verify_rollback_test()
            all_issues.extend(rollback_test["issues"])

        self.results["details"] = {
            "workspace": str(self.workspace),
            "modular_design": mod_result,
            "rollback_capability": rollback_result,
            "performance": perf_result,
            "cross_references": ref_result,
            "rollback_test": rollback_test if verify_rollback else {"skipped": True},
            "total_issues": len(all_issues),
            "valid": len(all_issues) == 0
        }

        if all_issues:
            self.results["status"] = "failed"
            self.results["message"] = f"Self-validation failed: {len(all_issues)} issues"
        else:
            self.results["message"] = "Self-validation passed - modular design, rollback, performance, and references verified"

        return self.results


def main():
    parser = argparse.ArgumentParser(description="Rigorous self-validation with rollback verification")
    parser.add_argument("--workspace", required=True, help="Workspace path")
    parser.add_argument("--verify-rollback", action="store_true", help="Test actual rollback (creates temp commit)")
    parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    validator = SelfValidator(Path(args.workspace))
    result = validator.run(verify_rollback=args.verify_rollback)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        status = "✓" if result.get("valid") else "✗"
        print(f"{status} Self-Validation: {result.get('message')}")
        if result.get("details", {}).get("total_issues", 0) > 0:
            for key, val in result["details"].items():
                if isinstance(val, dict) and val.get("issues"):
                    for issue in val["issues"]:
                        print(f"  [{key}] {issue}")

    sys.exit(0 if result.get("valid") else 1)


if __name__ == "__main__":
    main()