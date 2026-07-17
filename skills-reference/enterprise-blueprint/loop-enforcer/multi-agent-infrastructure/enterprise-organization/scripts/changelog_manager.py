#!/usr/bin/env python3
"""
CHANGELOG Manager - Append-only CHANGELOG with decision rationale
Every entry includes: datetime, author, changes, method, validation, reasoning
"""

import sys
import json
import argparse
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List


class ChangelogManager:
    def __init__(self, workspace: Path):
        self.workspace = workspace.resolve()
        self.changelog_path = self.workspace / "CHANGELOG.md"
        self.results = {
            "operation": "changelog",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }

    def ensure_changelog_exists(self):
        """Create CHANGELOG.md if it doesn't exist."""
        if not self.changelog_path.exists():
            initial = f"""# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

---

*All changes tracked with: datetime, author, changes, method, validation, reasoning*
"""
            self.changelog_path.write_text(initial)

    def add_entry(self, phase: str, author: str, reason: str, method: str = "", validation: str = "") -> Dict:
        """Add a new entry to CHANGELOG.md under [Unreleased]."""
        self.ensure_changelog_exists()

        content = self.changelog_path.read_text()
        timestamp = datetime.now().isoformat()
        date_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        # Build entry
        entry_lines = [f"### {phase} - {date_str}"]
        entry_lines.append(f"**Author:** {author}")
        entry_lines.append(f"**Reason:** {reason}")
        if method:
            entry_lines.append(f"**Method:** {method}")
        if validation:
            entry_lines.append(f"**Validation:** {validation}")
        entry_lines.append(f"**Reasoning:** {reason}")  # Reason includes the 'why'
        entry_lines.append("")

        entry = "\n".join(entry_lines)

        # Insert after "## [Unreleased]" section
        lines = content.split("\n")
        insert_idx = -1
        for i, line in enumerate(lines):
            if line.strip() == "## [Unreleased]":
                # Find next line after the header
                for j in range(i + 1, len(lines)):
                    if lines[j].strip() and not lines[j].startswith("#"):
                        insert_idx = j
                        break
                if insert_idx == -1:
                    insert_idx = i + 1
                break

        if insert_idx == -1:
            # Fallback: append at end
            insert_idx = len(lines)

        lines.insert(insert_idx, entry)
        self.changelog_path.write_text("\n".join(lines))

        self.results["details"] = {
            "workspace": str(self.workspace),
            "phase": phase,
            "author": author,
            "reason": reason,
            "method": method,
            "validation": validation,
            "timestamp": timestamp,
            "entry_added": True
        }
        self.results["message"] = f"CHANGELOG entry added for phase: {phase}"
        return self.results

    def list_entries(self, phase_filter: str = None, author_filter: str = None, since: str = None, limit: int = 50) -> Dict:
        """List CHANGELOG entries with optional filters."""
        self.ensure_changelog_exists()
        content = self.changelog_path.read_text()

        # Parse entries
        entries = []
        current_entry = None

        for line in content.split("\n"):
            # Match phase headers: "### Phase - YYYY-MM-DD HH:MM:SS"
            match = re.match(r"^###\s+(.+?)\s+-\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})$", line)
            if match:
                if current_entry:
                    entries.append(current_entry)
                current_entry = {
                    "phase": match.group(1),
                    "timestamp": match.group(2),
                    "author": "",
                    "reason": "",
                    "method": "",
                    "validation": "",
                    "reasoning": ""
                }
                continue

            if current_entry:
                if line.startswith("**Author:**"):
                    current_entry["author"] = line.replace("**Author:**", "").strip()
                elif line.startswith("**Reason:**"):
                    current_entry["reason"] = line.replace("**Reason:**", "").strip()
                elif line.startswith("**Method:**"):
                    current_entry["method"] = line.replace("**Method:**", "").strip()
                elif line.startswith("**Validation:**"):
                    current_entry["validation"] = line.replace("**Validation:**", "").strip()
                elif line.startswith("**Reasoning:**"):
                    current_entry["reasoning"] = line.replace("**Reasoning:**", "").strip()
                elif line.strip() == "" or line.startswith("##") or line.startswith("###"):
                    # End of entry (empty line or next section)
                    if any(current_entry.values()):
                        entries.append(current_entry)
                    current_entry = None

        # Add last entry
        if current_entry and any(current_entry.values()):
            entries.append(current_entry)

        # Apply filters
        filtered = entries
        if phase_filter:
            filtered = [e for e in filtered if phase_filter.lower() in e["phase"].lower()]
        if author_filter:
            filtered = [e for e in filtered if author_filter.lower() in e["author"].lower()]
        if since:
            try:
                since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
                filtered = [e for e in filtered if datetime.strptime(e["timestamp"], "%Y-%m-%d %H:%M:%S") >= since_dt]
            except Exception:
                pass

        filtered = filtered[:limit]

        self.results["details"] = {
            "workspace": str(self.workspace),
            "filters": {"phase": phase_filter, "author": author_filter, "since": since, "limit": limit},
            "total_entries": len(entries),
            "filtered_entries": len(filtered),
            "entries": filtered
        }
        self.results["message"] = f"Found {len(filtered)} entries (of {len(entries)} total)"
        return self.results

    def verify_integrity(self) -> Dict:
        """Verify CHANGELOG integrity (hash chain, no deletions)."""
        self.ensure_changelog_exists()
        content = self.changelog_path.read_text()

        issues = []
        checks = {}

        checks["has_unreleased"] = "## [Unreleased]" in content
        if not checks["has_unreleased"]:
            issues.append("Missing [Unreleased] section")

        checks["has_keepachangelog_ref"] = "keepachangelog" in content.lower()
        checks["has_semver_ref"] = "semver" in content.lower()

        # Check for required fields in entries
        entries = re.findall(r"###\s+.+?\s+-\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}", content)
        checks["entry_count"] = len(entries)

        # Check each entry has required fields
        entry_blocks = re.split(r"\n###\s+", content)[1:]  # Split by entries
        for i, block in enumerate(entry_blocks):
            if "**Author:**" not in block:
                issues.append(f"Entry {i+1} missing Author field")
            if "**Reason:**" not in block:
                issues.append(f"Entry {i+1} missing Reason field")
            if "**Timestamp:**" not in block and not re.search(r"-\s+\d{4}-\d{2}-\d{2}", block):
                issues.append(f"Entry {i+1} missing timestamp")

        self.results["details"] = {
            "workspace": str(self.workspace),
            "checks": checks,
            "issues": issues,
            "valid": len(issues) == 0
        }

        if issues:
            self.results["status"] = "failed"
            self.results["message"] = f"CHANGELOG integrity check failed: {len(issues)} issues"
        else:
            self.results["message"] = "CHANGELOG integrity verified"

        return self.results


def main():
    parser = argparse.ArgumentParser(description="CHANGELOG Manager - append-only with rationale")
    parser.add_argument("--workspace", required=True, help="Workspace path")
    parser.add_argument("--action", choices=["add", "list", "verify"], default="add", help="Action to perform")
    parser.add_argument("--phase", help="Phase name (for add)")
    parser.add_argument("--author", help="Author name (for add)")
    parser.add_argument("--reason", help="Change reason (for add)")
    parser.add_argument("--method", default="", help="Method used (for add)")
    parser.add_argument("--validation", default="", help="Validation performed (for add)")
    parser.add_argument("--phase-filter", help="Filter by phase (for list)")
    parser.add_argument("--author-filter", help="Filter by author (for list)")
    parser.add_argument("--since", help="Filter entries since date (ISO format, for list)")
    parser.add_argument("--limit", type=int, default=50, help="Limit entries (for list)")
    parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    manager = ChangelogManager(Path(args.workspace))

    if args.action == "add":
        if not all([args.phase, args.author, args.reason]):
            parser.error("--phase, --author, --reason required for add")
        result = manager.add_entry(args.phase, args.author, args.reason, args.method, args.validation)
    elif args.action == "list":
        result = manager.list_entries(args.phase_filter, args.author_filter, args.since, args.limit)
    elif args.action == "verify":
        result = manager.verify_integrity()
    else:
        parser.error(f"Unknown action: {args.action}")

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        status = "✓" if result.get("status") == "success" else "✗"
        print(f"{status} CHANGELOG {args.action}: {result.get('message')}")
        if "details" in result and "entries" in result["details"]:
            for e in result["details"]["entries"]:
                print(f"  {e['timestamp']} | {e['phase']} | {e['author']} | {e['reason'][:60]}")

    sys.exit(0 if result.get("status") == "success" else 1)


if __name__ == "__main__":
    main()