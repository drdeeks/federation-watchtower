#!/usr/bin/env python3
"""
Guardrail Loop Lock — advisory ``.loop.lock`` manager
=====================================================

Implements the advisory lock from the CL-040 design: while a skill (or any
directory) is mid-authoring, a ``.loop.lock`` marker sits at its root. Cooperating
tools — the monitor (``monitor.py``), the gate (``gate.py``), and any packager or
validator — check for the lock and **skip** locked directories, so half-authored
state is never auto-committed and concurrent tool runs don't step on each other.

This is deliberately an *advisory* lock, not a kernel ``flock`` or ``chattr +i``:
it only constrains tools that choose to honor it. That is the right trade-off for
a cooperating toolchain — no sudo, no stuck kernel locks, fully portable — with
the git pre-commit hook and the signed loop log as the belt-and-suspenders layers
that catch anyone who bypasses it.

Lock file contents (JSON): pid, token, host, acquired_at, note.

Path-agnostic: the locked directory is a positional argument; nothing hardcoded.

Subcommands:
    acquire <dir> [--token T] [--note ...] [--force]
    release <dir> [--token T] [--force]
    check   <dir>                 # exit 0 if locked, 1 if not
    list    <root> [--json]       # find all .loop.lock under a root
"""

import argparse
import json
import os
import socket
import sys
from datetime import datetime, timezone
from pathlib import Path

LOCK_NAME = ".loop.lock"


def utcnow():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def lock_path(directory):
    return Path(directory).expanduser().resolve() / LOCK_NAME


def read_lock(path):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def cmd_acquire(args):
    path = lock_path(args.directory)
    if not path.parent.is_dir():
        raise SystemExit(f"error: not a directory: {path.parent}")
    if path.exists() and not args.force:
        existing = read_lock(path) or {}
        raise SystemExit(
            f"error: already locked by pid={existing.get('pid')} token={existing.get('token')} "
            f"since {existing.get('acquired_at')} (use --force to override)")
    payload = {
        "pid": os.getpid(),
        "token": args.token or "",
        "host": socket.gethostname(),
        "acquired_at": utcnow(),
        "note": args.note or "",
    }
    path.write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps({"operation": "lock_acquire", "status": "locked",
                      "path": str(path), "token": payload["token"]}, indent=2))
    return 0


def cmd_release(args):
    path = lock_path(args.directory)
    if not path.exists():
        print(json.dumps({"operation": "lock_release", "status": "not_locked", "path": str(path)}, indent=2))
        return 0
    existing = read_lock(path) or {}
    if args.token and existing.get("token") and existing["token"] != args.token and not args.force:
        raise SystemExit(f"error: token mismatch (lock held by token={existing.get('token')}); "
                         f"use --force to override")
    path.unlink()
    print(json.dumps({"operation": "lock_release", "status": "released", "path": str(path)}, indent=2))
    return 0


def cmd_check(args):
    path = lock_path(args.directory)
    locked = path.exists()
    if not args.quiet:
        info = read_lock(path) if locked else None
        print(json.dumps({"operation": "lock_check", "locked": locked,
                          "path": str(path), "info": info}, indent=2))
    return 0 if locked else 1


def cmd_list(args):
    root = Path(args.root).expanduser().resolve()
    locks = []
    for p in sorted(root.rglob(LOCK_NAME)):
        locks.append({"dir": str(p.parent), "lock": read_lock(p)})
    if args.json:
        print(json.dumps({"operation": "lock_list", "root": str(root), "locks": locks}, indent=2))
    else:
        if not locks:
            print(f"no {LOCK_NAME} files under {root}")
        for l in locks:
            info = l["lock"] or {}
            print(f"🔒 {l['dir']}  (pid={info.get('pid')}, since {info.get('acquired_at')})")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Manage advisory .loop.lock markers.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_a = sub.add_parser("acquire", help="Create a .loop.lock in a directory.")
    p_a.add_argument("directory")
    p_a.add_argument("--token", help="Opaque token; required to release when set.")
    p_a.add_argument("--note", help="Free-text note stored in the lock.")
    p_a.add_argument("--force", action="store_true", help="Overwrite an existing lock.")
    p_a.set_defaults(func=cmd_acquire)

    p_r = sub.add_parser("release", help="Remove a .loop.lock from a directory.")
    p_r.add_argument("directory")
    p_r.add_argument("--token", help="Must match the lock's token unless --force.")
    p_r.add_argument("--force", action="store_true", help="Release regardless of token.")
    p_r.set_defaults(func=cmd_release)

    p_c = sub.add_parser("check", help="Exit 0 if locked, 1 if not.")
    p_c.add_argument("directory")
    p_c.add_argument("-q", "--quiet", action="store_true")
    p_c.set_defaults(func=cmd_check)

    p_l = sub.add_parser("list", help="List all .loop.lock markers under a root.")
    p_l.add_argument("root", nargs="?", default=".")
    p_l.add_argument("--json", action="store_true")
    p_l.set_defaults(func=cmd_list)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
