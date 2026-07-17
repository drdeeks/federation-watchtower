#!/usr/bin/env python3
"""
Git Control - Robust git operations for enterprise organization.
Handles commits, pushes, branches, merges, hooks, and automated workflows.
"""

import sys
import json
import argparse
import subprocess
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional


class GitControl:
    def __init__(self, workspace: Path):
        self.workspace = workspace.resolve()
        self.results = {
            "operation": "git_control",
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            "skill_name": "enterprise-organization",
            "details": {},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }
        self._verify_git_repo()

    def _verify_git_repo(self) -> bool:
        """Verify this is a git repository."""
        return (self.workspace / ".git").exists()

    def _run_git(self, args: List[str], capture: bool = True) -> subprocess.CompletedProcess:
        """Run a git command."""
        cmd = ["git"] + args
        return subprocess.run(cmd, cwd=self.workspace, capture_output=capture, text=True, timeout=30)

    def status(self) -> Dict:
        """Get git status."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        result = self._run_git(["status", "--porcelain", "--branch"])
        
        branch_info = ""
        clean = True
        if result.stdout:
            lines = result.stdout.strip().split('\n')
            if lines and lines[0].startswith('##'):
                branch_info = lines[0][3:].strip()  # Remove '## '
                lines = lines[1:]
            clean = len(lines) == 0
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "branch": branch_info,
            "clean": clean,
            "raw": result.stdout
        }
        self.results["message"] = f"Git status: {'clean' if clean else 'dirty'} on {branch_info or 'unknown branch'}"
        return self.results

    def add(self, paths: List[str] = None, all_files: bool = False) -> Dict:
        """Stage files for commit."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        if all_files:
            result = self._run_git(["add", "-A"])
        elif paths:
            result = self._run_git(["add"] + paths)
        else:
            return self._fail("Specify paths or use --all")
        
        if result.returncode != 0:
            return self._fail(f"git add failed: {result.stderr}")
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "paths": paths or ["* (all)"],
            "all": all_files
        }
        self.results["message"] = f"Staged {len(paths) if paths else 'all'} files"
        return self.results

    def commit(self, message: str, author: str = None, amend: bool = False, sign: bool = False) -> Dict:
        """Create a commit with optional author, amend, and signing."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        # Check if there's anything to commit
        status = self._run_git(["status", "--porcelain"])
        if not status.stdout.strip() and not amend:
            return self._fail("Nothing to commit, working tree clean")
        
        cmd = ["commit"]
        if amend:
            cmd.append("--amend")
            cmd.append("--no-edit")
        else:
            cmd.extend(["-m", message])
        
        if author:
            cmd.extend(["--author", author])
        
        if sign:
            cmd.append("-S")
        
        result = self._run_git(cmd)
        
        if result.returncode != 0:
            return self._fail(f"git commit failed: {result.stderr}")
        
        # Get commit hash
        hash_result = self._run_git(["rev-parse", "HEAD"])
        commit_hash = hash_result.stdout.strip()[:8] if hash_result.stdout.strip() else "unknown"
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "message": message,
            "author": author,
            "amend": amend,
            "signed": sign,
            "commit_hash": commit_hash
        }
        self.results["message"] = f"Committed {commit_hash}: {message[:50]}"
        return self.results

    def push(self, remote: str = "origin", branch: str = None, force: bool = False, tags: bool = False) -> Dict:
        """Push commits/tags to remote."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        cmd = ["push"]
        if force:
            cmd.append("--force")
        if tags:
            cmd.append("--tags")
        else:
            cmd.append(remote)
            if branch:
                cmd.append(branch)
        
        result = self._run_git(cmd)
        
        if result.returncode != 0:
            return self._fail(f"git push failed: {result.stderr}")
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "remote": remote,
            "branch": branch,
            "force": force,
            "tags": tags
        }
        self.results["message"] = f"Pushed to {remote}/{branch or 'current branch'}"
        return self.results

    def pull(self, remote: str = "origin", branch: str = None, rebase: bool = False) -> Dict:
        """Pull changes from remote."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        cmd = ["pull"]
        if rebase:
            cmd.append("--rebase")
        cmd.append(remote)
        if branch:
            cmd.append(branch)
        
        result = self._run_git(cmd)
        
        if result.returncode != 0:
            return self._fail(f"git pull failed: {result.stderr}")
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "remote": remote,
            "branch": branch,
            "rebase": rebase
        }
        self.results["message"] = f"Pulled from {remote}/{branch or 'current branch'}"
        return self.results

    def branch(self, name: str = None, create: bool = False, delete: bool = False, list_all: bool = False) -> Dict:
        """Branch management."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        if list_all:
            result = self._run_git(["branch", "-a"])
            branches = result.stdout.strip().split('\n') if result.stdout.strip() else []
            self.results["details"] = {
                "workspace": str(self.workspace),
                "branches": [b.strip('* ').strip() for b in branches],
                "current": next((b.strip('* ').strip() for b in branches if b.startswith('*')), None)
            }
            self.results["message"] = f"Found {len(branches)} branches"
            return self.results
        
        if not name:
            return self._fail("Branch name required")
        
        if create:
            result = self._run_git(["checkout", "-b", name])
            action = "Created and switched to"
        elif delete:
            result = self._run_git(["branch", "-d", name])
            action = "Deleted"
        else:
            result = self._run_git(["checkout", name])
            action = "Switched to"
        
        if result.returncode != 0:
            return self._fail(f"git branch operation failed: {result.stderr}")
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "branch": name,
            "action": action
        }
        self.results["message"] = f"{action} branch: {name}"
        return self.results

    def merge(self, source_branch: str, target_branch: str = None, no_ff: bool = False, squash: bool = False) -> Dict:
        """Merge branches."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        # Switch to target branch if specified
        if target_branch:
            checkout_result = self._run_git(["checkout", target_branch])
            if checkout_result.returncode != 0:
                return self._fail(f"Cannot switch to {target_branch}: {checkout_result.stderr}")
        
        cmd = ["merge"]
        if no_ff:
            cmd.append("--no-ff")
        if squash:
            cmd.append("--squash")
        cmd.append(source_branch)
        
        result = self._run_git(cmd)
        
        if result.returncode != 0:
            return self._fail(f"git merge failed: {result.stderr}")
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "source": source_branch,
            "target": target_branch or "current",
            "no_ff": no_ff,
            "squash": squash
        }
        self.results["message"] = f"Merged {source_branch} into {target_branch or 'current branch'}"
        return self.results

    def log(self, limit: int = 20, oneline: bool = True, since: str = None, author: str = None) -> Dict:
        """Get git log."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        cmd = ["log"]
        if oneline:
            cmd.append("--oneline")
        if limit:
            cmd.extend(["-n", str(limit)])
        if since:
            cmd.extend(["--since", since])
        if author:
            cmd.extend(["--author", author])
        
        result = self._run_git(cmd)
        
        if result.returncode != 0:
            return self._fail(f"git log failed: {result.stderr}")
        
        commits = result.stdout.strip().split('\n') if result.stdout.strip() else []
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "commits": commits,
            "count": len(commits)
        }
        self.results["message"] = f"Showing {len(commits)} commits"
        return self.results

    def diff(self, staged: bool = False, file_path: str = None) -> Dict:
        """Show git diff."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        cmd = ["diff"]
        if staged:
            cmd.append("--cached")
        if file_path:
            cmd.append(file_path)
        
        result = self._run_git(cmd)
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "staged": staged,
            "file": file_path,
            "diff": result.stdout
        }
        self.results["message"] = "Diff generated" if result.stdout else "No changes"
        return self.results

    def stash(self, action: str = "push", name: str = None, pop: bool = False, list_stashes: bool = False) -> Dict:
        """Stash management."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        if list_stashes:
            result = self._run_git(["stash", "list"])
            stashes = result.stdout.strip().split('\n') if result.stdout.strip() else []
            self.results["details"] = {
                "workspace": str(self.workspace),
                "stashes": stashes
            }
            self.results["message"] = f"Found {len(stashes)} stashes"
            return self.results
        
        if action == "pop" or pop:
            cmd = ["stash", "pop"]
        elif action == "push":
            cmd = ["stash", "push"]
            if name:
                cmd.extend(["-m", name])
        elif action == "drop":
            cmd = ["stash", "drop"]
            if name:
                cmd.append(name)
        else:
            return self._fail("Invalid stash action")
        
        result = self._run_git(cmd)
        
        if result.returncode != 0:
            return self._fail(f"git stash failed: {result.stderr}")
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "action": action,
            "name": name
        }
        self.results["message"] = f"Stash {action} completed"
        return self.results

    def setup_hooks(self) -> Dict:
        """Setup enterprise git hooks (pre-commit, commit-msg, pre-push)."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        hooks_dir = self.workspace / ".git" / "hooks"
        hooks_dir.mkdir(parents=True, exist_ok=True)
        
        hooks_installed = []
        
        # Pre-commit hook
        pre_commit = hooks_dir / "pre-commit"
        pre_commit_content = """#!/bin/bash
# Enterprise Organization - Pre-commit Hook
# Runs validation checks before commit

set -e

WORKSPACE=$(git rev-parse --show-toplevel)
SCRIPTS_DIR="$WORKSPACE/scripts"

# Check if enterprise scripts exist
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "Enterprise scripts not found, skipping validation"
    exit 0
fi

echo "Running enterprise pre-commit checks..."

# Run placeholder scanner
if [ -f "$SCRIPTS_DIR/placeholder_scanner.py" ]; then
    python3 "$SCRIPTS_DIR/placeholder_scanner.py" --workspace "$WORKSPACE" --fail-on-found --json
    if [ $? -ne 0 ]; then
        echo "Placeholder scanner failed - commit rejected"
        exit 1
    fi
fi

# Run security hardening check
if [ -f "$SCRIPTS_DIR/security_hardening.py" ]; then
    python3 "$SCRIPTS_DIR/security_hardening.py" --workspace "$WORKSPACE" --check-only --json
    if [ $? -ne 0 ]; then
        echo "Security check failed - commit rejected"
        exit 1
    fi
fi

echo "Pre-commit checks passed"
exit 0
"""
        pre_commit.write_text(pre_commit_content)
        pre_commit.chmod(0o755)
        hooks_installed.append("pre-commit")

        # Commit-msg hook
        commit_msg = hooks_dir / "commit-msg"
        commit_msg_content = """#!/bin/bash
# Enterprise Organization - Commit Message Hook
# Validates commit message format

COMMIT_MSG_FILE=$1
COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")

# Check for conventional commit format
if ! echo "$COMMIT_MSG" | grep -qE '^(feat|fix|docs|style|refactor|test|chore|revert)(\(.+\))?: .+'; then
    echo "Warning: Commit message should follow conventional format:"
    echo "  type(scope): description"
    echo "  e.g., feat(auth): add OAuth2 login"
    echo "  e.g., fix: resolve memory leak"
    # Don't fail, just warn
fi

# Check minimum length
if [ ${#COMMIT_MSG} -lt 10 ]; then
    echo "Warning: Commit message is very short"
fi

exit 0
"""
        commit_msg.write_text(commit_msg_content)
        commit_msg.chmod(0o755)
        hooks_installed.append("commit-msg")

        # Pre-push hook
        pre_push = hooks_dir / "pre-push"
        pre_push_content = """#!/bin/bash
# Enterprise Organization - Pre-push Hook
# Runs validation before push

set -e

WORKSPACE=$(git rev-parse --show-toplevel)
SCRIPTS_DIR="$WORKSPACE/scripts"

echo "Running enterprise pre-push checks..."

# Run full validation
if [ -f "$SCRIPTS_DIR/enterprise-org.py" ]; then
    python3 "$SCRIPTS_DIR/enterprise-org.py" validate --workspace "$WORKSPACE" --json
    if [ $? -ne 0 ]; then
        echo "Validation failed - push rejected"
        exit 1
    fi
fi

echo "Pre-push checks passed"
exit 0
"""
        pre_push.write_text(pre_push_content)
        pre_push.chmod(0o755)
        hooks_installed.append("pre-push")

        self.results["details"] = {
            "workspace": str(self.workspace),
            "hooks_installed": hooks_installed
        }
        self.results["message"] = f"Installed {len(hooks_installed)} git hooks"
        return self.results

    def sync(self, remote: str = "origin", branch: str = None) -> Dict:
        """Full sync: pull, push, push tags."""
        if not self._verify_git_repo():
            return self._fail("Not a git repository")
        
        results = []
        
        # Pull first
        pull_result = self.pull(remote, branch, rebase=True)
        results.append(("pull", pull_result))
        if pull_result.get("status") != "success":
            return self._fail(f"Sync failed at pull: {pull_result.get('message')}")
        
        # Push
        push_result = self.push(remote, branch)
        results.append(("push", push_result))
        if push_result.get("status") != "success":
            return self._fail(f"Sync failed at push: {push_result.get('message')}")
        
        # Push tags
        tags_result = self.push(remote, branch, tags=True)
        results.append(("push_tags", tags_result))
        
        self.results["details"] = {
            "workspace": str(self.workspace),
            "remote": remote,
            "branch": branch,
            "steps": [r[0] for r in results]
        }
        self.results["message"] = f"Synced with {remote}/{branch or 'current branch'}"
        return self.results

    def _fail(self, message: str) -> Dict:
        self.results["status"] = "failed"
        self.results["message"] = message
        return self.results


def main():
    parser = argparse.ArgumentParser(description="Robust Git Control")
    parser.add_argument("--workspace", default=".", help="Workspace path")
    parser.add_argument("--json", action="store_true", help="Output JSON")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # Common arguments for all subparsers
    common_args = [
        ("--workspace", {"default": ".", "help": "Workspace path"}),
        ("--json", {"action": "store_true", "help": "Output JSON"})
    ]

    # status
    status_parser = subparsers.add_parser("status", help="Show git status")
    for arg, opts in common_args:
        status_parser.add_argument(arg, **opts)

    # add
    add_parser = subparsers.add_parser("add", help="Stage files")
    add_parser.add_argument("paths", nargs="*", help="Files to stage")
    add_parser.add_argument("--all", "-a", action="store_true", help="Stage all files")
    for arg, opts in common_args:
        add_parser.add_argument(arg, **opts)

    # commit
    commit_parser = subparsers.add_parser("commit", help="Create commit")
    commit_parser.add_argument("message", help="Commit message")
    commit_parser.add_argument("--author", help="Author (Name <email>)")
    commit_parser.add_argument("--amend", action="store_true", help="Amend last commit")
    commit_parser.add_argument("--sign", "-S", action="store_true", help="GPG sign commit")
    for arg, opts in common_args:
        commit_parser.add_argument(arg, **opts)

    # push
    push_parser = subparsers.add_parser("push", help="Push to remote")
    push_parser.add_argument("--remote", default="origin", help="Remote name")
    push_parser.add_argument("--branch", help="Branch name")
    push_parser.add_argument("--force", action="store_true", help="Force push")
    push_parser.add_argument("--tags", action="store_true", help="Push tags")
    for arg, opts in common_args:
        push_parser.add_argument(arg, **opts)

    # pull
    pull_parser = subparsers.add_parser("pull", help="Pull from remote")
    pull_parser.add_argument("--remote", default="origin", help="Remote name")
    pull_parser.add_argument("--branch", help="Branch name")
    pull_parser.add_argument("--rebase", action="store_true", help="Rebase instead of merge")
    for arg, opts in common_args:
        pull_parser.add_argument(arg, **opts)

    # branch
    branch_parser = subparsers.add_parser("branch", help="Branch management")
    branch_parser.add_argument("name", nargs="?", help="Branch name")
    branch_parser.add_argument("--create", "-c", action="store_true", help="Create branch")
    branch_parser.add_argument("--delete", "-d", action="store_true", help="Delete branch")
    branch_parser.add_argument("--list", "-l", action="store_true", help="List all branches")
    for arg, opts in common_args:
        branch_parser.add_argument(arg, **opts)

    # merge
    merge_parser = subparsers.add_parser("merge", help="Merge branches")
    merge_parser.add_argument("source", help="Source branch")
    merge_parser.add_argument("--target", help="Target branch (default: current)")
    merge_parser.add_argument("--no-ff", action="store_true", help="No fast-forward")
    merge_parser.add_argument("--squash", action="store_true", help="Squash merge")
    for arg, opts in common_args:
        merge_parser.add_argument(arg, **opts)

    # log
    log_parser = subparsers.add_parser("log", help="Show git log")
    log_parser.add_argument("--limit", type=int, default=20, help="Number of commits")
    log_parser.add_argument("--no-oneline", action="store_true", help="Full log format")
    log_parser.add_argument("--since", help="Since date")
    log_parser.add_argument("--author", help="Filter by author")
    for arg, opts in common_args:
        log_parser.add_argument(arg, **opts)

    # diff
    diff_parser = subparsers.add_parser("diff", help="Show diff")
    diff_parser.add_argument("--staged", action="store_true", help="Show staged changes")
    diff_parser.add_argument("file", nargs="?", help="Specific file")
    for arg, opts in common_args:
        diff_parser.add_argument(arg, **opts)

    # stash
    stash_parser = subparsers.add_parser("stash", help="Stash management")
    stash_parser.add_argument("action", choices=["push", "pop", "drop", "list"], default="push", nargs="?")
    stash_parser.add_argument("--name", help="Stash name/message")
    for arg, opts in common_args:
        stash_parser.add_argument(arg, **opts)

    # hooks
    hooks_parser = subparsers.add_parser("hooks", help="Setup git hooks")
    for arg, opts in common_args:
        hooks_parser.add_argument(arg, **opts)

    # sync
    sync_parser = subparsers.add_parser("sync", help="Full sync (pull + push + tags)")
    sync_parser.add_argument("--remote", default="origin", help="Remote name")
    sync_parser.add_argument("--branch", help="Branch name")
    for arg, opts in common_args:
        sync_parser.add_argument(arg, **opts)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    git = GitControl(Path(args.workspace))

    if args.command == "status":
        result = git.status()
    elif args.command == "add":
        result = git.add(args.paths, args.all)
    elif args.command == "commit":
        result = git.commit(args.message, args.author, args.amend, args.sign)
    elif args.command == "push":
        result = git.push(args.remote, args.branch, args.force, args.tags)
    elif args.command == "pull":
        result = git.pull(args.remote, args.branch, args.rebase)
    elif args.command == "branch":
        result = git.branch(args.name, args.create, args.delete, args.list)
    elif args.command == "merge":
        result = git.merge(args.source, args.target, args.no_ff, args.squash)
    elif args.command == "log":
        result = git.log(args.limit, not args.no_oneline, args.since, args.author)
    elif args.command == "diff":
        result = git.diff(args.staged, args.file)
    elif args.command == "stash":
        result = git.stash(args.action, args.name, args.action == "pop", args.action == "list")
    elif args.command == "hooks":
        result = git.setup_hooks()
    elif args.command == "sync":
        result = git.sync(args.remote, args.branch)
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
                if k not in ["diff", "commits", "raw"] or args.json:
                    print(f"  {k}: {v}")

    sys.exit(0 if result.get("status") == "success" else 1)


if __name__ == "__main__":
    main()