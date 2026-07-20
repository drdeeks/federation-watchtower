#!/usr/bin/env python3
"""
skill_root.py — shared skill-root discovery for the whole toolchain.

Single source of truth for answering three questions every other script needs:

  1. find_skill_root(path)   — given ANY path (a file inside a skill, a
                               subdirectory, or the skill dir itself), walk UP
                               to the nearest directory whose root holds a
                               SKILL.md. That directory is the skill root.
  2. find_skills(path)       — given a directory, walk DOWN and return every
                               skill root beneath it (does not descend into a
                               found skill, so nested SKILL.mds inside a skill
                               are NOT reported as separate skills — they are
                               a structural violation reported separately).
  3. nested_skill_mds(root)  — every SKILL.md below a skill's root. A valid
                               skill has zero of these.

Every function is read-only. CLI mirrors the API for shell callers:

  python3 skill_root.py --root /path/inside/some/skill
  python3 skill_root.py --scan /path/to/skills/parent [--json]
  python3 skill_root.py --nested /path/to/one/skill [--json]
  python3 skill_root.py --scan <dir> --dry-run   # read-only anyway; accepted
                                                 # so callers can pass it
                                                 # uniformly to every script
"""
import argparse
import json
import sys
sys.dont_write_bytecode = True  # never litter skills with __pycache__ (validator FAIL)
from pathlib import Path

# Directories never worth descending into during a scan — caches and VCS
# internals only (mirrors validate.py's FORBIDDEN_DIRS intent without
# importing it, so this module stays dependency-free and reusable anywhere).
SKIP_DIRS = {
    "__pycache__", ".git", ".svn", ".hg", "node_modules", "__MACOSX",
    ".cache", ".pytest_cache", ".mypy_cache", "venv", ".venv",
    "dist", "build", ".tox", ".eggs", ".next", ".nuxt",
}


def find_skill_root(path):
    """Walk UP from `path` to the nearest dir containing a root SKILL.md.

    Returns a Path, or None if no ancestor (including `path` itself) has one.
    Accepts a file or directory path.
    """
    p = Path(path).resolve()
    if p.is_file():
        p = p.parent
    while True:
        if (p / "SKILL.md").is_file():
            return p
        if p.parent == p:  # filesystem root
            return None
        p = p.parent


def find_skills(path, max_depth=6):
    """Walk DOWN from `path` and return every skill root beneath it.

    - If `path` itself is a skill root, returns [path] and stops — a skill
      is never scanned for skills nested inside it (those are violations,
      surfaced by nested_skill_mds, not more skills).
    - Otherwise recurses into subdirectories (skipping cache/VCS dirs) up to
      max_depth, collecting dirs whose root holds a SKILL.md.
    """
    base = Path(path).resolve()
    if not base.is_dir():
        return []
    if (base / "SKILL.md").is_file():
        return [base]
    found = []

    def _walk(d, depth):
        if depth > max_depth:
            return
        try:
            children = sorted(c for c in d.iterdir() if c.is_dir())
        except OSError:
            return
        for c in children:
            if c.name in SKIP_DIRS or c.name.startswith("."):
                continue
            if (c / "SKILL.md").is_file():
                found.append(c)      # a skill — do NOT descend further
            else:
                _walk(c, depth + 1)

    _walk(base, 1)
    return found


def nested_skill_mds(skill_root):
    """Return every SKILL.md strictly BELOW the skill root (violations)."""
    root = Path(skill_root).resolve()
    out = []
    for p in root.rglob("SKILL.md"):
        if p.parent == root:
            continue
        if any(part in SKIP_DIRS for part in p.relative_to(root).parts):
            continue
        out.append(p)
    return sorted(out)


def resolve_target(path):
    """Full context for one path: its skill root, whether the given path IS
    the root, and any nested SKILL.md violations. Dict is JSON-ready."""
    p = Path(path).resolve()
    root = find_skill_root(p)
    result = {
        "input": str(p),
        "skill_root": str(root) if root else None,
        "input_is_root": bool(root and root == p),
        "nested_skill_mds": [],
    }
    if root:
        result["nested_skill_mds"] = [str(x) for x in nested_skill_mds(root)]
    return result


def main():
    ap = argparse.ArgumentParser(description="Skill-root discovery (read-only)")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--root", metavar="PATH",
                   help="Resolve the skill root that contains PATH")
    g.add_argument("--scan", metavar="DIR",
                   help="List every skill root beneath DIR")
    g.add_argument("--nested", metavar="SKILL_DIR",
                   help="List nested SKILL.md violations inside one skill")
    ap.add_argument("--json", action="store_true", help="JSON output")
    ap.add_argument("--dry-run", action="store_true",
                    help="Accepted for CLI uniformity; this tool is read-only")
    args = ap.parse_args()

    if args.root:
        result = resolve_target(args.root)
        if args.json:
            print(json.dumps({"operation": "root", **result}, indent=2))
        else:
            if result["skill_root"]:
                print(result["skill_root"])
                for n in result["nested_skill_mds"]:
                    print(f"  ! nested SKILL.md: {n}", file=sys.stderr)
            else:
                print("no skill root found", file=sys.stderr)
                sys.exit(1)

    elif args.scan:
        skills = find_skills(args.scan)
        if args.json:
            print(json.dumps({
                "operation": "scan",
                "target": str(Path(args.scan).resolve()),
                "skills": [str(s) for s in skills],
                "count": len(skills),
            }, indent=2))
        else:
            for s in skills:
                print(s)
            print(f"({len(skills)} skill(s))", file=sys.stderr)

    elif args.nested:
        nested = nested_skill_mds(args.nested)
        if args.json:
            print(json.dumps({
                "operation": "nested",
                "skill": str(Path(args.nested).resolve()),
                "nested_skill_mds": [str(n) for n in nested],
                "count": len(nested),
            }, indent=2))
        else:
            for n in nested:
                print(n)
            sys.exit(1 if nested else 0)


if __name__ == "__main__":
    main()
