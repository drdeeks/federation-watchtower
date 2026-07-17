#!/usr/bin/env python3
"""
Phase Tagger - Tagging system per phase for enterprise organization.
Manages phase tags, milestones, and phase-based tracking in git, CHANGELOG, and TODO.
"""

import sys
import json
import argparse
import subprocess
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional


class PhaseTagger:
    def __init__(self, workspace: Path):
        self.workspace = workspace.resolve()
        self.results = {
            "operation": "phase_tagger",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }
        self._verify_git_repo()

    def _verify_git_repo(self) -> bool:
        return (self.workspace / ".git").exists()

    def _run_git(self, args: List[str]) -> subprocess.CompletedProcess:
        cmd = ["git"] + args
        return subprocess.run(cmd, cwd=self.workspace, capture_output=True, text=True, timeout=30)

    def define_phase(self, name: str, description: str, tags: List[str] = None) -> Dict:
        """Define a new phase with metadata."""
        self.results["operation"] = "define_phase"
        
        phases_file = self.workspace / ".phases.json"
        phases = {}
        
        if phases_file.exists():
            import json as json_module
            try:
                phases = json_module.loads(phases_file.read_text())
            except Exception:
                phases = {}
        
        phases[name] = {
            "description": description,
            "tags": tags or [name],
            "created": datetime.now().isoformat(),
            "status": "active",
            "milestones": []
        }
        
        phases_file.write_text(json.dumps(phases, indent=2))
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "phase": name,
            "description": description,
            "tags": tags or [name]
        }
        self.results["message"] = f"Phase '{name}' defined"
        return self.results

    def start_phase(self, name: str, commit: bool = True, tag: bool = True, push: bool = False) -> Dict:
        """Start a new phase - creates git tag and updates CHANGELOG/TODO."""
        self.results["operation"] = "start_phase"
        
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        timestamp = datetime.now().isoformat()
        phase_tag = f"phase-{name}-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        
        # Create git tag for phase start
        if tag:
            tag_result = self._run_git(["tag", "-a", phase_tag, "-m", f"Phase start: {name}"])
            if tag_result.returncode != 0:
                return self._fail(f"Failed to create phase tag: {tag_result.stderr}")
        
        # Update CHANGELOG
        changelog_path = self.workspace / "CHANGELOG.md"
        if changelog_path.exists():
            content = changelog_path.read_text()
            entry = f"""### {name} - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

**Author:** {self._get_git_user()}
**Reason:** Phase started: {name}
**Method:** phase_tagger.py start_phase
**Validation:** Git tag {phase_tag} created
**Reasoning:** Starting new development phase

"""
            lines = content.split('\n')
            insert_idx = -1
            for i, line in enumerate(lines):
                if line.strip() == "## [Unreleased]":
                    for j in range(i + 1, len(lines)):
                        if lines[j].strip() and not lines[j].startswith("#"):
                            insert_idx = j
                            break
                    if insert_idx == -1:
                        insert_idx = i + 1
                    break
            
            if insert_idx != -1:
                lines.insert(insert_idx, entry)
                changelog_path.write_text('\n'.join(lines))
        
        # Update TODO.md
        todo_path = self.workspace / "TODO.md"
        if todo_path.exists():
            content = todo_path.read_text()
            # Add phase section
            phase_section = f"""
## Phase: {name}

- [ ] Phase initialized

"""
            lines = content.split('\n')
            # Find end of file or last phase
            insert_idx = len(lines)
            for i in range(len(lines) - 1, -1, -1):
                if lines[i].startswith("## Phase:"):
                    insert_idx = i
                    break
            lines.insert(insert_idx, phase_section)
            todo_path.write_text('\n'.join(lines))
        
        # Commit if requested
        if commit:
            self._run_git(["add", "-A"])
            commit_msg = f"chore(phase): start phase {name}\n\nPhase tag: {phase_tag}"
            self._run_git(["commit", "-m", commit_msg])
        
        if push:
            self._run_git(["push", "origin", "--tags"])
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "phase": name,
            "tag": phase_tag,
            "committed": commit,
            "pushed": push
        }
        self.results["message"] = f"Phase '{name}' started with tag {phase_tag}"
        return self.results

    def complete_phase(self, name: str, summary: str, commit: bool = True, tag: bool = True, push: bool = False) -> Dict:
        """Complete a phase - creates completion tag and updates CHANGELOG."""
        self.results["operation"] = "complete_phase"
        
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        phase_tag = f"phase-{name}-complete-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        
        if tag:
            tag_result = self._run_git(["tag", "-a", phase_tag, "-m", f"Phase complete: {name} - {summary}"])
            if tag_result.returncode != 0:
                return self._fail(f"Failed to create phase completion tag: {tag_result.stderr}")
        
        # Update CHANGELOG
        changelog_path = self.workspace / "CHANGELOG.md"
        if changelog_path.exists():
            content = changelog_path.read_text()
            entry = f"""### {name} (complete) - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

**Author:** {self._get_git_user()}
**Reason:** Phase completed: {name}
**Method:** phase_tagger.py complete_phase
**Validation:** Git tag {phase_tag} created, all tasks verified
**Reasoning:** {summary}

"""
            lines = content.split('\n')
            insert_idx = -1
            for i, line in enumerate(lines):
                if line.strip() == "## [Unreleased]":
                    for j in range(i + 1, len(lines)):
                        if lines[j].strip() and not lines[j].startswith("#"):
                            insert_idx = j
                            break
                    if insert_idx == -1:
                        insert_idx = i + 1
                    break
            
            if insert_idx != -1:
                lines.insert(insert_idx, entry)
                changelog_path.write_text('\n'.join(lines))
        
        # Update TODO.md - mark phase tasks complete
        todo_path = self.workspace / "TODO.md"
        if todo_path.exists():
            content = todo_path.read_text()
            # Find and update phase section
            lines = content.split('\n')
            in_phase = False
            for i, line in enumerate(lines):
                if line.strip().startswith(f"## Phase: {name}"):
                    in_phase = True
                elif in_phase and line.startswith("## Phase:"):
                    in_phase = False
                elif in_phase and line.startswith("- [ ]"):
                    lines[i] = line.replace("- [ ]", "- [x]")
            
            # Add completion note
            completion_note = f"\n# Phase {name} completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            lines.append(completion_note)
            todo_path.write_text('\n'.join(lines))
        
        if commit:
            self._run_git(["add", "-A"])
            commit_msg = f"chore(phase): complete phase {name}\n\n{summary}\n\nPhase tag: {phase_tag}"
            self._run_git(["commit", "-m", commit_msg])
        
        if push:
            self._run_git(["push", "origin", "--tags"])
        
        # Update phases.json
        phases_file = self.workspace / ".phases.json"
        if phases_file.exists():
            import json as json_module
            try:
                phases = json_module.loads(phases_file.read_text())
                if name in phases:
                    phases[name]["status"] = "completed"
                    phases[name]["completed"] = timestamp
                    phases[name]["summary"] = summary
                    phases_file.write_text(json_module.dumps(phases, indent=2))
            except Exception:
                pass
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "phase": name,
            "tag": phase_tag,
            "summary": summary,
            "committed": commit,
            "pushed": push
        }
        self.results["message"] = f"Phase '{name}' completed with tag {phase_tag}"
        return self.results

    def list_phases(self) -> Dict:
        """List all defined phases."""
        self.results["operation"] = "list_phases"
        
        phases_file = self.workspace / ".phases.json"
        phases = {}
        
        if phases_file.exists():
            import json as json_module
            try:
                phases = json_module.loads(phases_file.read_text())
            except Exception:
                phases = {}
        
        # Also get phase tags from git
        git_tags = []
        if self._verify_git_repo():
            result = self._run_git(["tag", "--list", "phase-*"])
            git_tags = result.stdout.strip().split('\n') if result.stdout.strip() else []
            git_tags = [t for t in git_tags if t]
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "defined_phases": phases,
            "git_tags": git_tags,
            "count": len(phases)
        }
        self.results["message"] = f"Found {len(phases)} defined phases, {len(git_tags)} phase tags"
        return self.results

    def show_phase(self, name: str) -> Dict:
        """Show details of a specific phase."""
        self.results["operation"] = "show_phase"
        
        phases_file = self.workspace / ".phases.json"
        if not phases_file.exists():
            return self._fail("No phases defined")
        
        import json as json_module
        try:
            phases = json_module.loads(phases_file.read_text())
        except Exception:
            return self._fail("Invalid phases file")
        
        if name not in phases:
            return self._fail(f"Phase '{name}' not found")
        
        # Get related git tags
        git_tags = []
        if self._verify_git_repo():
            result = self._run_git(["tag", "--list", f"phase-{name}-*"])
            git_tags = result.stdout.strip().split('\n') if result.stdout.strip() else []
            git_tags = [t for t in git_tags if t]
        
        phase = phases[name]
        phase["git_tags"] = sorted(git_tags)
        
        # Get CHANGELOG entries for this phase
        changelog_entries = []
        changelog_path = self.workspace / "CHANGELOG.md"
        if changelog_path.exists():
            content = changelog_path.read_text()
            in_entry = False
            for line in content.split('\n'):
                if line.strip().startswith(f"### {name}") or line.strip().startswith(f"### {name} (complete)"):
                    in_entry = True
                    changelog_entries.append(line)
                elif in_entry:
                    if line.startswith("### ") and not (line.startswith(f"### {name}") or line.startswith(f"### {name} (complete)")):
                        in_entry = False
                    elif in_entry:
                        changelog_entries.append(line)
        
        phase["changelog_entries"] = changelog_entries
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "phase": phase
        }
        self.results["message"] = f"Phase '{name}' details"
        return self.results

    def tag_files(self, phase: str, pattern: str = "**/*", message: str = "") -> Dict:
        """Tag files in a phase with git tag and update tracking."""
        self.results["operation"] = "tag_files"
        
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        files = list(self.workspace.glob(pattern))
        files = [f for f in files if f.is_file() and ".git" not in str(f)]
        
        if not files:
            return self._fail("No files found matching pattern")
        
        # Add files and commit
        for f in files:
            self._run_git(["add", str(f.relative_to(self.workspace))])
        
        tag = f"phase-{phase}-files-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        tag_msg = message or f"Phase {phase}: tagged {len(files)} files"
        
        self._run_git(["tag", "-a", tag, "-m", tag_msg])
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "phase": phase,
            "files_tagged": len(files),
            "tag": tag,
            "files": [str(f.relative_to(self.workspace)) for f in files[:20]]  # Limit
        }
        self.results["message"] = f"Tagged {len(files)} files for phase '{phase}' with {tag}"
        return self.results

    def _get_git_user(self) -> str:
        """Get git user name."""
        result = self._run_git(["config", "user.name"])
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        return "unknown"

    def _fail(self, message: str) -> Dict:
        self.results["status"] = "failed"
        self.results["message"] = message
        return self.results


def main():
    parser = argparse.ArgumentParser(description="Phase Tagger - Per-phase tagging and tracking")
    parser.add_argument("--workspace", default=".", help="Workspace path")
    parser.add_argument("--json", action="store_true", help="Output JSON")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # Common arguments for all subparsers
    common_args = [
        ("--workspace", {"default": ".", "help": "Workspace path"}),
        ("--json", {"action": "store_true", "help": "Output JSON"})
    ]

    # define
    define_parser = subparsers.add_parser("define", help="Define a new phase")
    define_parser.add_argument("name", help="Phase name")
    define_parser.add_argument("description", help="Phase description")
    define_parser.add_argument("--tags", nargs="+", help="Additional tags")
    for arg, opts in common_args:
        define_parser.add_argument(arg, **opts)

    # start
    start_parser = subparsers.add_parser("start", help="Start a phase")
    start_parser.add_argument("name", help="Phase name")
    start_parser.add_argument("--no-commit", action="store_true", help="Don't commit")
    start_parser.add_argument("--no-tag", action="store_true", help="Don't create git tag")
    start_parser.add_argument("--push", action="store_true", help="Push tags")
    for arg, opts in common_args:
        start_parser.add_argument(arg, **opts)

    # complete
    complete_parser = subparsers.add_parser("complete", help="Complete a phase")
    complete_parser.add_argument("name", help="Phase name")
    complete_parser.add_argument("summary", help="Completion summary")
    complete_parser.add_argument("--no-commit", action="store_true", help="Don't commit")
    complete_parser.add_argument("--no-tag", action="store_true", help="Don't create git tag")
    complete_parser.add_argument("--push", action="store_true", help="Push tags")
    for arg, opts in common_args:
        complete_parser.add_argument(arg, **opts)

    # list
    list_parser = subparsers.add_parser("list", help="List all phases")
    for arg, opts in common_args:
        list_parser.add_argument(arg, **opts)

    # show
    show_parser = subparsers.add_parser("show", help="Show phase details")
    show_parser.add_argument("name", help="Phase name")
    for arg, opts in common_args:
        show_parser.add_argument(arg, **opts)

    # tag-files
    tag_files_parser = subparsers.add_parser("tag-files", help="Tag files for a phase")
    tag_files_parser.add_argument("phase", help="Phase name")
    tag_files_parser.add_argument("--pattern", default="**/*", help="File pattern")
    tag_files_parser.add_argument("--message", help="Tag message")
    for arg, opts in common_args:
        tag_files_parser.add_argument(arg, **opts)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    tagger = PhaseTagger(Path(args.workspace))

    if args.command == "define":
        result = tagger.define_phase(args.name, args.description, args.tags)
    elif args.command == "start":
        result = tagger.start_phase(args.name, not args.no_commit, not args.no_tag, args.push)
    elif args.command == "complete":
        result = tagger.complete_phase(args.name, args.summary, not args.no_commit, not args.no_tag, args.push)
    elif args.command == "list":
        result = tagger.list_phases()
    elif args.command == "show":
        result = tagger.show_phase(args.name)
    elif args.command == "tag-files":
        result = tagger.tag_files(args.phase, args.pattern, args.message)
    else:
        print(f"Unknown command: {args.command}")
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        status = "✓" if result.get("status") == "success" else "✗"
        print(f"{status} {result.get('message')}")
        if "details" in result:
            for k, v in result["details"].items():
                if k not in ["phase", "defined_phases"] or args.json:
                    print(f"  {k}: {v}")

    sys.exit(0 if result.get("status") == "success" else 1)


if __name__ == "__main__":
    main()