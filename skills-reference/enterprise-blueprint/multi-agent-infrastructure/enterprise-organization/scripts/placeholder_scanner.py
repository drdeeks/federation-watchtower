#!/usr/bin/env python3
"""
Zero-Placeholder Enforcement Scanner
Detects TODO/FIXME/TBD/WIP/stub patterns in code and documentation.
"""

import sys
import json
import argparse
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List


class PlaceholderScanner:
    # Conservative patterns - only flags clear, unambiguous markers
    PLACEHOLDER_PATTERNS = [
        (r'(?:^|(?<=\s))(?<!`)TODO(?!\\w)(?!.*\\btodo\\b)(?!\\s*,)(?!\\s+list)', 'TODO marker'),
        (r'\\bFIXME\\b', 'FIXME marker'),
        (r'(?<!\\| )TBD(?!\\w)(?! \\|)', 'TBD marker'),
        (r'\\bWIP\\b', 'Work in progress marker'),
        (r'\\bcoming\\s+soon\\b', 'Coming soon placeholder'),
        (r'\\binsert\\s+(here|text|data|info)\\b', 'Insert placeholder'),
        (r'\\breplace\\s+(this|here)\\b', 'Replace placeholder'),
        (r'\\byour\\s+(name|email|token|key|id)\\b', 'Your-<something> placeholder'),
        (r'\\blorem\\s+ipsum\\b', 'Lorem ipsum filler'),
        (r'\\[YOUR_', 'Template variable placeholder'),
        (r'(?!\\{)\\{\\{(?!\\{).*?\\}\\}(?!\\})', 'Mustache template variable'),
        (r'<!--\\s*(placeholder|todo|fixme)\\s*-->', 'HTML comment placeholder'),
        (r'\\bSTUB\\b', 'STUB implementation'),
        (r'\\bplaceholder\\b', 'Explicit placeholder'),
        (r'pass\\s*#\\s*(todo|fixme|implement)', 'Pass with TODO comment'),
        (r'raise NotImplementedError', 'NotImplementedError raised'),
        (r'return None\\s*#\\s*(todo|fixme|temporary)', 'Temporary None return'),
    ]

    # Patterns that are acceptable (legitimate uses)
    ALLOWED_PATTERNS = [
        r'# tag:.*todo',  # Tag references
        r'\"todo\"',      # String literals
        r"'todo'",        # String literals
        r'todo_list',     # Variable names
        r'todo_item',     # Variable names
        r'// tag:',       # Tag references
    ]

    def __init__(self, workspace: Path, fail_on_found: bool = False):
        self.workspace = workspace.resolve()
        self.fail_on_found = fail_on_found
        self.results = {
            "operation": "scan_placeholders",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }

    def should_scan_file(self, file_path: Path) -> bool:
        """Determine if file should be scanned."""
        # Skip binary, large, and excluded files
        excluded_dirs = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build", ".pytest_cache", ".mypy_cache", ".tox", "backups", "logs", "data", "tmp", ".secrets"}
        for part in file_path.parts:
            if part in excluded_dirs:
                return False

        excluded_suffixes = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".zip", ".tar", ".gz", ".bin", ".whl", ".so", ".dll", ".exe", ".class", ".pyc", ".pyo", ".pyd", ".db", ".sqlite", ".sqlite3", ".log", ".cache"}
        if file_path.suffix.lower() in excluded_suffixes:
            return False

        # Skip very large files
        try:
            if file_path.stat().st_size > 500000:
                return False
        except OSError:
            return False

        return True

    def is_allowed(self, line: str) -> bool:
        """Check if line contains allowed pattern that should be ignored."""
        for pattern in self.ALLOWED_PATTERNS:
            if re.search(pattern, line, re.IGNORECASE):
                return True
        return False

    def scan_file(self, file_path: Path) -> List[Dict]:
        """Scan a single file for placeholders."""
        findings = []
        try:
            content = file_path.read_text(encoding="utf-8", errors="ignore")
            lines = content.splitlines()

            for line_num, line in enumerate(lines, 1):
                if self.is_allowed(line):
                    continue

                for pattern, desc in self.PLACEHOLDER_PATTERNS:
                    if re.search(pattern, line, re.IGNORECASE):
                        findings.append({
                            "file": str(file_path.relative_to(self.workspace)),
                            "line": line_num,
                            "type": desc,
                            "pattern": pattern,
                            "content": line.strip()[:120]
                        })
                        break  # One finding per line max
        except Exception as e:
            pass
        return findings

    def scan(self) -> Dict:
        """Scan entire workspace."""
        all_findings = []
        files_scanned = 0

        for file_path in self.workspace.rglob("*"):
            if file_path.is_file() and self.should_scan_file(file_path):
                files_scanned += 1
                findings = self.scan_file(file_path)
                all_findings.extend(findings)

        # Categorize findings
        by_type = {}
        for f in all_findings:
            t = f["type"]
            if t not in by_type:
                by_type[t] = []
            by_type[t].append(f)

        # Determine overall status
        valid = len(all_findings) == 0
        if not valid and self.fail_on_found:
            self.results["status"] = "failed"

        self.results["details"] = {
            "workspace": str(self.workspace),
            "files_scanned": files_scanned,
            "total_findings": len(all_findings),
            "by_type": {k: len(v) for k, v in by_type.items()},
            "findings": all_findings[:50],  # Limit output
            "valid": valid,
            "fail_on_found": self.fail_on_found
        }

        if all_findings:
            self.results["message"] = f"Found {len(all_findings)} placeholder(s) in {files_scanned} files"
        else:
            self.results["message"] = "No placeholders found - zero-placeholder policy compliant"

        return self.results


def main():
    parser = argparse.ArgumentParser(description="Zero-placeholder enforcement scanner")
    parser.add_argument("--workspace", required=True, help="Workspace path")
    parser.add_argument("--fail-on-found", action="store_true", help="Exit with error if placeholders found")
    parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    scanner = PlaceholderScanner(Path(args.workspace), fail_on_found=args.fail_on_found)
    result = scanner.scan()

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        status = "✓" if result.get("valid") else "✗"
        print(f"{status} Placeholder Scan: {result.get('message')}")
        if result.get("details", {}).get("total_findings", 0) > 0:
            print(f"  Files scanned: {result['details']['files_scanned']}")
            print(f"  Findings by type:")
            for t, count in result["details"]["by_type"].items():
                print(f"    {t}: {count}")
            print(f"  First 10 findings:")
            for f in result["details"]["findings"][:10]:
                print(f"    {f['file']}:{f['line']} - {f['type']} - {f['content'][:80]}")

    sys.exit(0 if result.get("valid") or not result.get("details", {}).get("fail_on_found", False) else 1)


if __name__ == "__main__":
    main()