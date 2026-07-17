#!/usr/bin/env python3
"""
loop-enforcer/__init__.py — Scaffolder + integration for sequential chain enforcement.

Usage:
    python3 __init__.py --scaffold <chain-name> --path <project-dir> <file1> <file2> ...
    python3 __init__.py --status <chain-name> --path <project-dir>
"""
import json
import os
import sys
from pathlib import Path

NAME = "loop-enforcer"
VERSION = "1.0.6"
DESCRIPTION = "Sequential dependency chain enforcement with file locking and verification gates"


def scaffold(chain_name, project_dir, files):
    """Create a new chain in the project directory."""
    # Import from the scripts directory
    scripts_dir = Path(__file__).parent / "scripts"
    sys.path.insert(0, str(scripts_dir))

    from chain import create_chain
    result = create_chain(project_dir, chain_name, files)
    return result


def status(chain_name, project_dir):
    """Get chain status."""
    scripts_dir = Path(__file__).parent / "scripts"
    sys.path.insert(0, str(scripts_dir))

    from chain import check_status
    return check_status(project_dir, chain_name)


def main():
    if "--scaffold" in sys.argv:
        idx = sys.argv.index("--scaffold")
        chain_name = sys.argv[idx + 1]
        path_idx = sys.argv.index("--path") if "--path" in sys.argv else None
        project_dir = sys.argv[path_idx + 1] if path_idx else "."
        files = sys.argv[path_idx + 2:] if path_idx else sys.argv[idx + 2:]
        result = scaffold(chain_name, project_dir, files)
        print(json.dumps(result, indent=2))
    elif "--status" in sys.argv:
        idx = sys.argv.index("--status")
        chain_name = sys.argv[idx + 1]
        path_idx = sys.argv.index("--path") if "--path" in sys.argv else None
        project_dir = sys.argv[path_idx + 1] if path_idx else "."
        result = status(chain_name, project_dir)
        print(json.dumps(result, indent=2))
    else:
        print(f"{NAME} v{VERSION} — {DESCRIPTION}")
        print("Use: --scaffold <name> --path <dir> <files...>")
        print("Use: --status <name> --path <dir>")


if __name__ == "__main__":
    main()
