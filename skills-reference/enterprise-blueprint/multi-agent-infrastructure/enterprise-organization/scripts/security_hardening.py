#!/usr/bin/env python3
"""
Security Hardening & Gitignore Enforcement
Enforces enterprise security standards and gitignore compliance.
"""

import sys
import json
import argparse
import os
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Set


class SecurityHardening:
    def __init__(self, workspace: Path):
        self.workspace = workspace.resolve()
        self.results = {
            "operation": "security_hardening",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }

    def get_enterprise_gitignore(self) -> str:
        """Return enterprise gitignore template."""
        return f"""# Enterprise Organization - Gitignore Standards
# Generated: {datetime.now().isoformat()}

# Secrets & Credentials (NEVER commit)
.secrets/
*.key
*.pem
*.p12
*.pfx
*.jks
*.keystore
.env
.env.*
!.env.example
*.secret
*.credential
*_rsa
*_dsa
*_ecdsa
*_ed25519

# API Keys & Tokens
*API_KEY*
*API_SECRET*
*TOKEN*
*BEARER*
*AUTH*
*.webhook

# Wallets & Blockchain
*.wallet
*.keystore
*private*key*
*mnemonic*
*seed*
utxo*
*.dat

# Database & Local Data
*.db
*.sqlite
*.sqlite3
*.db-journal
data/local/
*.log
logs/*.log

# Build & Cache
__pycache__/
*.py[cod]
*$py.class
.pytest_cache/
.coverage
.mypy_cache/
.tox/
dist/
build/
*.egg-info/

# IDE & Editor
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store
Thumbs.db

# OS & Temporary
tmp/
temp/
*.tmp
*.temp

# Large Files & Binaries
*.bin
*.iso
*.img
*.vmdk
*.qcow2
*.vdi
*.ova

# Node.js
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-store/

# Python
pip-log.txt
pip-delete-this-directory.txt
*.egg
.eggs/

# Docker
.docker/
docker-compose.override.yml

# Agent Specific
agents/*/tmp/
agents/*/cache/
agents/*/sessions/*.json
skills/*/scripts/__pycache__/
"""

    def check_gitignore(self, fix: bool = False) -> Dict:
        """Check .gitignore compliance."""
        gitignore_path = self.workspace / ".gitignore"
        issues = []
        fixed = []

        if not gitignore_path.exists():
            if fix:
                gitignore_path.write_text(self.get_enterprise_gitignore())
                fixed.append("Created enterprise .gitignore")
            else:
                issues.append("Missing .gitignore")
            return {"issues": issues, "fixed": fixed, "valid": len(issues) == 0}

        content = gitignore_path.read_text()
        required_patterns = [
            r"\.secrets/",
            r"\*\.key",
            r"\*\.pem",
            r"\.env",
            r"\*API_KEY\*",
            r"\*TOKEN\*",
            r"\*\.wallet",
            r"\*private\*key\*",
            r"\.db$",
            r"__pycache__/",
            r"node_modules/",
            r"\.vscode/",
        ]

        for pattern in required_patterns:
            if not re.search(pattern, content, re.MULTILINE):
                issues.append(f"Missing gitignore pattern: {pattern}")

        # Check for dangerous patterns (things that should NOT be gitignored)
        dangerous = [r"!\\.secrets/", r"!\\*\\.key", r"!\\.env(?:$|\\s)"]
        for pattern in dangerous:
            if re.search(pattern, content):
                issues.append(f"Dangerous gitignore override: {pattern}")

        return {"issues": issues, "fixed": fixed, "valid": len(issues) == 0}

    def check_permissions(self, fix: bool = False) -> Dict:
        """Check file/directory permissions."""
        issues = []
        fixed = []

        # Check .secrets permissions
        secrets_path = self.workspace / ".secrets"
        if secrets_path.exists():
            perm = oct(secrets_path.stat().st_mode)[-3:]
            if perm != "700":
                issues.append(f".secrets has {perm} permissions, expected 700")
                if fix:
                    os.chmod(secrets_path, 0o700)
                    fixed.append("Fixed .secrets permissions to 700")

        # Check for world-writable files
        for file_path in self.workspace.rglob("*"):
            if file_path.is_file():
                perm = oct(file_path.stat().st_mode)[-3:]
                if perm.endswith("7") or perm.endswith("6") or perm.endswith("5"):
                    # World writable
                    if int(perm[-1]) >= 2:
                        issues.append(f"World-writable file: {file_path.relative_to(self.workspace)} ({perm})")
                        if fix:
                            os.chmod(file_path, 0o600)
                            fixed.append(f"Fixed permissions on {file_path.relative_to(self.workspace)}")

        return {"issues": issues, "fixed": fixed, "valid": len(issues) == 0}

    def check_secrets_exposure(self) -> Dict:
        """Scan for potential secrets in tracked files."""
        issues = []

        # Patterns that indicate secrets
        secret_patterns = [
            (r"AKIA[0-9A-Z]{16}", "AWS Access Key"),
            (r"sk-[a-zA-Z0-9]{48}", "OpenAI API Key"),
            (r"gh[pousr]_[a-zA-Z0-9]{36,}", "GitHub Token"),
            (r"xoxb-[0-9]{11}-[0-9]{11}-[a-zA-Z0-9]{24}", "Slack Bot Token"),
            (r"-----BEGIN (RSA|EC|DSA|OPENSSH) PRIVATE KEY-----", "Private Key"),
            (r"mnemonic\s*[=:]\s*[\"']?(\w+\s+){11,12}\w+", "Mnemonic Phrase"),
            (r"private[_-]?key\s*[=:]\s*[\"']?[a-fA-F0-9]{64}", "Private Key Hex"),
            (r"rpc[_-]?url\s*[=:]\s*[\"']?https?://.*(infura|alchemy|quicknode)", "RPC URL with Key"),
        ]

        # Files to scan (exclude .git, node_modules, etc.)
        for file_path in self.workspace.rglob("*"):
            if file_path.is_file():
                # Skip binary, large, and excluded files
                if any(part in str(file_path) for part in [".git", "node_modules", "__pycache__", ".venv", "dist", "build"]):
                    continue
                if file_path.suffix in [".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".zip", ".tar", ".gz", ".bin"]:
                    continue
                try:
                    content = file_path.read_text(encoding="utf-8", errors="ignore")
                    if len(content) > 100000:  # Skip large files
                        continue
                    for pattern, desc in secret_patterns:
                        if re.search(pattern, content, re.IGNORECASE):
                            issues.append(f"Potential {desc} in {file_path.relative_to(self.workspace)}")
                except Exception:
                    pass

        return {"issues": issues, "fixed": [], "valid": len(issues) == 0}

    def run_all(self, fix: bool = False, check_only: bool = False) -> Dict:
        """Run all security checks."""
        all_issues = []
        all_fixed = []

        if not check_only:
            gitignore_result = self.check_gitignore(fix=fix)
            all_issues.extend(gitignore_result["issues"])
            all_fixed.extend(gitignore_result["fixed"])

        perm_result = self.check_permissions(fix=fix)
        all_issues.extend(perm_result["issues"])
        all_fixed.extend(perm_result["fixed"])

        secrets_result = self.check_secrets_exposure()
        all_issues.extend(secrets_result["issues"])

        self.results["details"] = {
            "workspace": str(self.workspace),
            "check_only": check_only,
            "fix_mode": fix,
            "gitignore": self.check_gitignore(fix=False) if check_only else gitignore_result,
            "permissions": perm_result,
            "secrets_exposure": secrets_result,
            "total_issues": len(all_issues),
            "total_fixed": len(all_fixed),
            "valid": len(all_issues) == 0
        }

        if all_issues:
            self.results["status"] = "failed"
            self.results["message"] = f"Security hardening failed: {len(all_issues)} issues"
        else:
            self.results["message"] = "Security hardening passed"

        return self.results


def main():
    parser = argparse.ArgumentParser(description="Security hardening & gitignore enforcement")
    parser.add_argument("--workspace", required=True, help="Workspace path")
    parser.add_argument("--fix", action="store_true", help="Auto-fix issues")
    parser.add_argument("--check-only", action="store_true", help="Only check gitignore (don't fix)")
    parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    # If --fix is used, don't use --check-only
    check_only = args.check_only and not args.fix

    hardener = SecurityHardening(Path(args.workspace))
    result = hardener.run_all(fix=args.fix, check_only=check_only)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        status = "✓" if result.get("valid") else "✗"
        print(f"{status} Security Hardening: {result.get('message')}")
        if result.get("details", {}).get("total_issues", 0) > 0:
            print(f"  Issues: {result['details']['total_issues']}")
            print(f"  Fixed: {result['details']['total_fixed']}")

    sys.exit(0 if result.get("valid") else 1)


if __name__ == "__main__":
    main()