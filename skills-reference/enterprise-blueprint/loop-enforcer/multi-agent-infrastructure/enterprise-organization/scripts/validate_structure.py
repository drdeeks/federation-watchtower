#!/usr/bin/env python3
"""
Modular File Tree Validation
Enforces enterprise-standard directory structure.
"""

import sys
import json
import argparse
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Set


class StructureValidator:
    def __init__(self, workspace: Path, role: str = "hermes"):
        self.workspace = workspace.resolve()
        self.role = role
        self.results = {
            "operation": "validate_structure",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }

    def get_expected_structure(self) -> Dict:
        """Get expected directory structure for role."""
        base_dirs = {
            ".secrets", "scripts", "references", "logs", "backups",
            "config", "data", "tmp", ".github", "agents", "skills"
        }
        role_dirs = {
            "hermes": {"plugins", "cron", ".github/workflows"},
            "titan": {"trading", "strategies", "data-feeds", ".github/workflows"},
            "avery": {"creative", "media", "generation", ".github/workflows"},
            "allman": {"onchain", "erc8004", "pinata", "wallets", ".github/workflows"},
        }
        return {"directories": base_dirs | role_dirs.get(self.role, set())}

    def validate(self, fix: bool = False) -> Dict:
        """Validate directory structure."""
        expected = self.get_expected_structure()
        existing = self._scan_existing_dirs()

        missing = expected["directories"] - existing
        extra = existing - expected["directories"] - self._get_allowed_extra()

        issues = []
        fixed = []

        # Fix missing directories
        for dir_name in sorted(missing):
            dir_path = self.workspace / dir_name
            if fix:
                dir_path.mkdir(parents=True, exist_ok=True)
                # Set permissions for .secrets
                if dir_name == ".secrets":
                    os.chmod(dir_path, 0o700)
                fixed.append(f"Created: {dir_name}")
            else:
                issues.append(f"Missing required directory: {dir_name}")

        # Report extra directories (not errors, just info)
        extra_info = [f"Extra directory (not in standard): {d}" for d in sorted(extra)]

        # Check .secrets permissions
        secrets_path = self.workspace / ".secrets"
        perm_issues = []
        if secrets_path.exists():
            perm = oct(secrets_path.stat().st_mode)[-3:]
            if perm != "700":
                perm_issues.append(f".secrets has {perm} permissions, expected 700")
                if fix:
                    os.chmod(secrets_path, 0o700)
                    fixed.append("Fixed .secrets permissions to 700")

        # Check required files
        required_files = ["README.md", "CHANGELOG.md", "TODO.md", ".gitignore"]
        missing_files = [f for f in required_files if not (self.workspace / f).exists()]
        for f in missing_files:
            issues.append(f"Missing required file: {f}")

        self.results["details"] = {
            "workspace": str(self.workspace),
            "role": self.role,
            "expected_dirs": sorted(expected["directories"]),
            "found_dirs": sorted(existing),
            "missing_dirs": sorted(missing),
            "extra_dirs": sorted(extra),
            "missing_files": missing_files,
            "permission_issues": perm_issues,
            "fixed": fixed,
            "issues": issues,
            "valid": len(issues) == 0
        }

        if issues:
            self.results["status"] = "failed"
            self.results["message"] = f"Structure validation failed: {len(issues)} issues"
        else:
            self.results["message"] = "Structure validation passed"

        return self.results

    def _scan_existing_dirs(self) -> Set[str]:
        """Scan existing directories."""
        dirs = set()
        for item in self.workspace.iterdir():
            if item.is_dir() and not item.name.startswith("."):
                dirs.add(item.name)
            elif item.is_dir() and item.name == ".secrets":
                dirs.add(".secrets")
            elif item.is_dir() and item.name == ".github":
                dirs.add(".github")
        # Check nested
        if (self.workspace / ".github" / "workflows").exists():
            dirs.add(".github/workflows")
        return dirs

    def _get_allowed_extra(self) -> Set[str]:
        """Directories allowed but not in standard."""
        return {"node_modules", "venv", ".venv", "dist", "build", "__pycache__", ".pytest_cache"}


def main():
    parser = argparse.ArgumentParser(description="Validate modular file tree structure")
    parser.add_argument("--workspace", required=True, help="Workspace path")
    parser.add_argument("--role", choices=["hermes", "titan", "avery", "allman"], default="hermes")
    parser.add_argument("--fix", action="store_true", help="Auto-fix missing directories")
    parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    validator = StructureValidator(Path(args.workspace), role=args.role)
    result = validator.validate(fix=args.fix)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        status = "✓" if result.get("valid") else "✗"
        print(f"{status} Structure Validation: {result.get('message')}")
        if result.get("details", {}).get("issues"):
            for issue in result["details"]["issues"]:
                print(f"  - {issue}")
        if result.get("details", {}).get("fixed"):
            for fix in result["details"]["fixed"]:
                print(f"  + {fix}")

    sys.exit(0 if result.get("valid") else 1)


if __name__ == "__main__":
    main()