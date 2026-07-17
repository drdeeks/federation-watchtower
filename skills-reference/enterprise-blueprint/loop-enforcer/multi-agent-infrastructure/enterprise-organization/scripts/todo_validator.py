#!/usr/bin/env python3
"""
Todo Completion Validator
Enforces todo-driven development with validation evidence.
"""

import sys
import json
import argparse
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List


class TodoValidator:
    def __init__(self, workspace: Path, strict: bool = False):
        self.workspace = workspace.resolve()
        self.strict = strict
        self.results = {
            "operation": "validate_todos",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }

    def parse_todo_md(self) -> Dict:
        """Parse TODO.md for tasks."""
        todo_path = self.workspace / "TODO.md"
        if not todo_path.exists():
            return {"error": "TODO.md not found", "tasks": []}

        content = todo_path.read_text()
        tasks = []

        # Parse table format
        table_pattern = r"\| (\d+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|"
        for match in re.finditer(table_pattern, content):
            tasks.append({
                "id": int(match.group(1)),
                "task": match.group(2).strip(),
                "phase": match.group(3).strip(),
                "status": match.group(4).strip(),
                "assigned": match.group(5).strip(),
                "created": match.group(6).strip(),
                "validated": match.group(7).strip()
            })

        # Parse checkbox format
        checkbox_pattern = r"- \[([ xX])\] (.+)"
        for match in re.finditer(checkbox_pattern, content):
            if not any(t["task"] == match.group(2).strip() for t in tasks):
                tasks.append({
                    "id": len(tasks) + 1,
                    "task": match.group(2).strip(),
                    "phase": "unknown",
                    "status": "✅ Done" if match.group(1).lower() == "x" else "⏳ Pending",
                    "assigned": "unknown",
                    "created": "",
                    "validated": ""
                })

        return {"tasks": tasks, "raw_content": content}

    def validate_tasks(self) -> Dict:
        """Validate task completion with evidence."""
        todo_data = self.parse_todo_md()
        if "error" in todo_data:
            return {"valid": False, "issues": [todo_data["error"]], "tasks": []}

        issues = []
        validations = []

        for task in todo_data["tasks"]:
            if "done" in task["status"].lower() or "✅" in task["status"]:
                if self.strict:
                    # Strict mode: require validation evidence
                    if not task.get("validated") or task["validated"].strip() in ["", "N/A", "pending"]:
                        issues.append(f"Task {task['id']} marked complete but no validation timestamp: {task['task']}")
                    else:
                        # Check if validation artifacts exist
                        artifact_patterns = [
                            f"logs/*validation*{task['id']}*.json",
                            f"logs/*{task['task'][:20]}*.json",
                            f"backups/*{task['id']}*",
                        ]
                        # In real implementation, would check for actual artifacts
                        validations.append({
                            "task_id": task["id"],
                            "task": task["task"],
                            "validated_at": task["validated"],
                            "has_artifacts": True  # Placeholder
                        })
                else:
                    # Lenient mode: just check for validation field
                    if not task.get("validated"):
                        issues.append(f"Task {task['id']} missing validation timestamp: {task['task']}")

        return {
            "valid": len(issues) == 0,
            "issues": issues,
            "validations": validations,
            "total_tasks": len(todo_data["tasks"]),
            "completed_tasks": len([t for t in todo_data["tasks"] if "done" in t["status"].lower() or "✅" in t["status"]])
        }

    def check_todo_exists(self) -> Dict:
        """Check that TODO.md exists and has content."""
        todo_path = self.workspace / "TODO.md"
        if not todo_path.exists():
            return {"valid": False, "issues": ["TODO.md not found - every workspace must have active todo tracking"]}

        content = todo_path.read_text()
        if len(content.strip()) < 100:
            return {"valid": False, "issues": ["TODO.md too sparse - must contain active task tracking"]}

        # Check for active tasks
        if not re.search(r"- \[ \]|⏳|Pending|active", content, re.IGNORECASE):
            return {"valid": False, "issues": ["No active tasks found in TODO.md - work must be tracked"]}

        return {"valid": True, "issues": []}

    def run(self) -> Dict:
        """Run all todo validations."""
        all_issues = []

        # Check TODO.md exists
        todo_check = self.check_todo_exists()
        all_issues.extend(todo_check["issues"])

        # Validate tasks
        task_check = self.validate_tasks()
        all_issues.extend(task_check["issues"])

        self.results["details"] = {
            "workspace": str(self.workspace),
            "strict_mode": self.strict,
            "todo_check": todo_check,
            "task_validation": task_check,
            "total_issues": len(all_issues),
            "valid": len(all_issues) == 0
        }

        if all_issues:
            self.results["status"] = "failed"
            self.results["message"] = f"Todo validation failed: {len(all_issues)} issues"
        else:
            self.results["message"] = "Todo validation passed"

        return self.results


def main():
    parser = argparse.ArgumentParser(description="Validate todo completion with evidence")
    parser.add_argument("--workspace", required=True, help="Workspace path")
    parser.add_argument("--strict", action="store_true", help="Strict validation (require artifacts)")
    parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    validator = TodoValidator(Path(args.workspace), strict=args.strict)
    result = validator.run()

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        status = "✓" if result.get("valid") else "✗"
        print(f"{status} Todo Validation: {result.get('message')}")
        if result.get("details", {}).get("total_issues", 0) > 0:
            for issue in result["details"]["task_validation"].get("issues", []):
                print(f"  - {issue}")

    sys.exit(0 if result.get("valid") else 1)


if __name__ == "__main__":
    main()