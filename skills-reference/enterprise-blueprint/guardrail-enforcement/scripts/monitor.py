#!/usr/bin/env python3
"""
Guardrail Monitor — the watcher half
====================================

A directory-agnostic **condition → action** trigger. It watches for a condition
(a skill's SKILL.md version bumping, or a file's mtime changing) and fires an
action (an auto git commit, or an arbitrary command) when the condition trips.

The watcher and the gate (``gate.py``) are independent tools that compose: run
the monitor alone to auto-commit on version bumps, run the gate alone to enforce
a loop, or point the monitor's action at ``gate.py`` to chain them.

Headline use case (skill version tracking):

    Watch every skill directory under a root. When a skill's SKILL.md
    ``version:`` field changes, derive the skill name from its own directory
    (the parent/owner of SKILL.md) and auto-commit:

        <skill_name> version bumped to v<X.Y.Z>

This forces consistent per-skill version tracking and clean rollback points.

Design constraints:
  * Python 3.8+ stdlib only.
  * Path-agnostic: the watched root, config, and state paths come from flags or
    the config file; nothing is hardcoded.
  * State is kept in ``.monitor-state.json`` so "changed" means "changed since we
    last looked", surviving across runs.

Config (``.monitor.json`` in the watched dir, or ``--config PATH``):

    {
      "watches": [
        {
          "name": "skill-versions",
          "condition": {"type": "skill_version", "root": ".", "depth": 1},
          "action": {"type": "git_commit",
                     "message_template": "{skill_name} version bumped to v{version}",
                     "scope": "skill_dir"}
        }
      ],
      "state_path": ".monitor-state.json"
    }

Condition types:  skill_version | file_mtime
Action types:     git_commit | shell_command | none
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

MONITOR_CONFIG_NAME = ".monitor.json"
DEFAULT_STATE_NAME = ".monitor-state.json"
VERSION_RE = re.compile(r"^version:\s*[\"']?([^\"'\r\n]+?)[\"']?\s*$", re.MULTILINE)


def utcnow():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def resolve_config(config_arg, cwd):
    path = Path(config_arg).expanduser() if config_arg else (cwd / MONITOR_CONFIG_NAME)
    if not path.is_file():
        raise SystemExit(f"error: monitor config not found: {path}\nrun 'monitor.py setup' first.")
    with path.open() as fh:
        return json.load(fh), path.resolve()


def read_skill_version(skill_md):
    """Extract the frontmatter `version:` from a SKILL.md, or None."""
    try:
        text = skill_md.read_text(errors="ignore")
    except OSError:
        return None
    # Only look inside the leading frontmatter block if present.
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            text = text[:end]
    m = VERSION_RE.search(text)
    return m.group(1).strip() if m else None


def git_root(start):
    try:
        out = subprocess.run(["git", "-C", str(start), "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True)
        return Path(out.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def substitute(value, variables):
    for name, val in variables.items():
        value = value.replace("{" + name + "}", str(val))
    return value


# --------------------------------------------------------------------------- #
# Conditions — each returns a list of "trip" dicts describing what changed.
# --------------------------------------------------------------------------- #

def condition_skill_version(cond, base_dir, state):
    root = (base_dir / cond.get("root", ".")).resolve()
    depth = int(cond.get("depth", 1))
    trips = []
    # Discover SKILL.md files at the configured depth (default: immediate subdirs).
    candidates = []
    if depth == 1:
        for child in sorted(root.iterdir()):
            if child.is_dir() and (child / "SKILL.md").is_file():
                candidates.append(child / "SKILL.md")
    else:
        candidates = sorted(root.rglob("SKILL.md"))
    for skill_md in candidates:
        skill_dir = skill_md.parent
        # Honor the advisory .loop.lock: a skill mid-authoring is skipped entirely
        # so half-authored version state is never recorded or auto-committed. The
        # bump is detected on the next scan after the lock is released.
        if (skill_dir / ".loop.lock").exists():
            continue
        skill_name = skill_dir.name  # parent/owner directory name
        version = read_skill_version(skill_md)
        if version is None:
            continue
        key = f"skill_version::{skill_dir}"
        prev = state.get(key)
        state[key] = version
        if prev is None:
            continue  # baseline: record, do not fire
        if prev != version:
            trips.append({
                "skill_name": skill_name,
                "skill_dir": str(skill_dir),
                "subdir": skill_dir.name,
                "path": str(skill_md),
                "version": version,
                "previous_version": prev,
            })
    return trips


def condition_file_mtime(cond, base_dir, state):
    root = (base_dir / cond.get("root", ".")).resolve()
    pattern = cond.get("pattern", "**/*")
    trips = []
    for path in sorted(root.glob(pattern)):
        if not path.is_file():
            continue
        mtime = path.stat().st_mtime
        key = f"file_mtime::{path}"
        prev = state.get(key)
        state[key] = mtime
        if prev is None:
            continue
        if prev != mtime:
            trips.append({"path": str(path), "subdir": path.parent.name,
                          "skill_name": path.parent.name, "version": "",
                          "skill_dir": str(path.parent)})
    return trips


CONDITIONS = {"skill_version": condition_skill_version, "file_mtime": condition_file_mtime}


# --------------------------------------------------------------------------- #
# Actions
# --------------------------------------------------------------------------- #

def action_git_commit(action, trip, base_dir, dry_run):
    template = action.get("message_template", "{skill_name} version bumped to v{version}")
    message = substitute(template, trip)
    scope = action.get("scope", "skill_dir")
    repo = git_root(Path(trip.get("skill_dir", base_dir)))
    if repo is None:
        return {"action": "git_commit", "status": "failed", "detail": "not a git repository", "message": message}
    if scope == "skill_dir":
        add_targets = [trip.get("skill_dir")]
        # Keep the root manifest in lockstep: its entry for this skill records the
        # very version we're committing, so it travels with the skill's commit.
        manifest = repo / ".skill-manifest.json"
        if manifest.is_file():
            add_targets.append(str(manifest))
    else:
        add_targets = [str(repo)]
    if dry_run:
        return {"action": "git_commit", "status": "planned", "message": message, "add": add_targets}
    subprocess.run(["git", "-C", str(repo), "add", "--", *add_targets], capture_output=True, text=True)
    proc = subprocess.run(["git", "-C", str(repo), "commit", "-m", message],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        detail = (proc.stdout + proc.stderr).strip()
        status = "nothing_to_commit" if "nothing to commit" in detail else "failed"
        return {"action": "git_commit", "status": status, "message": message, "detail": detail[-500:]}
    return {"action": "git_commit", "status": "committed", "message": message}


def action_shell_command(action, trip, base_dir, dry_run):
    cmd = [substitute(tok, trip) for tok in action.get("cmd", [])]
    if not cmd:
        return {"action": "shell_command", "status": "failed", "detail": "empty cmd"}
    if dry_run:
        return {"action": "shell_command", "status": "planned", "command": cmd}
    proc = subprocess.run(cmd, cwd=str(base_dir), capture_output=True, text=True, timeout=1800)
    return {"action": "shell_command", "status": "ran" if proc.returncode == 0 else "failed",
            "command": cmd, "returncode": proc.returncode,
            "detail": ((proc.stdout + proc.stderr).strip()[-500:] if proc.returncode else "")}


def action_none(action, trip, base_dir, dry_run):
    return {"action": "none", "status": "observed"}


ACTIONS = {"git_commit": action_git_commit, "shell_command": action_shell_command, "none": action_none}


def run_scan(config, config_path, base_dir, dry_run):
    state_path = base_dir / config.get("state_path", DEFAULT_STATE_NAME)
    state = {}
    if state_path.is_file():
        try:
            state = json.loads(state_path.read_text())
        except json.JSONDecodeError:
            state = {}

    results = []
    for watch in config.get("watches", []):
        cond = watch.get("condition", {})
        ctype = cond.get("type")
        cfunc = CONDITIONS.get(ctype)
        if not cfunc:
            results.append({"watch": watch.get("name", "?"), "error": f"unknown condition '{ctype}'"})
            continue
        trips = cfunc(cond, base_dir, state)
        action = watch.get("action", {"type": "none"})
        afunc = ACTIONS.get(action.get("type", "none"), action_none)
        for trip in trips:
            outcome = afunc(action, trip, base_dir, dry_run)
            results.append({"watch": watch.get("name", "?"), "trip": trip, "outcome": outcome})

    if not dry_run:
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")

    return {
        "operation": "monitor_scan",
        "timestamp": utcnow(),
        "config": str(config_path),
        "base_dir": str(base_dir),
        "fired": results,
        "status": "dry_run" if dry_run else "scanned",
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
    }


# --------------------------------------------------------------------------- #
# Setup (interactive + flag-driven)
# --------------------------------------------------------------------------- #

def cmd_setup(args):
    target = Path(args.directory).expanduser().resolve()
    if not target.is_dir():
        raise SystemExit(f"error: not a directory: {target}")
    config_path = target / MONITOR_CONFIG_NAME
    if config_path.exists() and not args.force:
        raise SystemExit(f"error: {config_path} exists (use --force).")

    interactive = sys.stdin.isatty() and not args.yes and not args.condition

    def ask(q, default):
        if not interactive:
            return default
        try:
            a = input(f"? {q} [{default}]: ").strip()
        except EOFError:
            a = ""
        return a or default

    condition_type = args.condition or ask(
        "What to watch? (skill_version / file_mtime)", "skill_version")
    action_type = args.action or ask(
        "What to trigger? (git_commit / shell_command / none)", "git_commit")

    condition = {"type": condition_type, "root": ".", "depth": 1}
    if condition_type == "file_mtime":
        condition["pattern"] = args.pattern or ask("Glob pattern to watch", "**/SKILL.md")

    if action_type == "git_commit":
        default_tpl = "{skill_name} version bumped to v{version}"
        action = {"type": "git_commit",
                  "message_template": args.message_template or ask("Commit message template", default_tpl),
                  "scope": args.scope or ask("Commit scope (skill_dir / all)", "skill_dir")}
    elif action_type == "shell_command":
        raw = args.cmd or (ask("Command to run on trigger", "") if interactive else "")
        action = {"type": "shell_command", "cmd": raw.split() if isinstance(raw, str) else raw}
    else:
        action = {"type": "none"}

    config = {
        "watches": [{"name": args.name or condition_type, "condition": condition, "action": action}],
        "state_path": DEFAULT_STATE_NAME,
    }
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    result = {"operation": "monitor_setup", "status": "success", "config": str(config_path),
              "watch": config["watches"][0], "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}}
    print(json.dumps(result, indent=2))
    print(f"\n✓ Monitor config written to {config_path}", file=sys.stderr)
    print("→ Establish a baseline: python3 monitor.py scan --config "
          f"{config_path}", file=sys.stderr)
    return 0


def cmd_scan(args):
    cwd = Path.cwd()
    config, config_path = resolve_config(args.config, cwd)
    base_dir = config_path.parent
    report = run_scan(config, config_path, base_dir, args.dry_run)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        fired = report["fired"]
        if not fired:
            print("no changes detected (baseline recorded on first run)")
        for f in fired:
            if "error" in f:
                print(f"! {f['watch']}: {f['error']}")
                continue
            t, o = f["trip"], f["outcome"]
            mark = {"committed": "✓", "planned": "»", "ran": "✓", "observed": "·"}.get(o["status"], "✗")
            msg = o.get("message") or " ".join(o.get("command", []))
            print(f"[{mark}] {t.get('skill_name','?')}: {t.get('previous_version','?')} → "
                  f"{t.get('version','?')}  ({o['status']}) {msg}")
            if o.get("detail"):
                print(f"      {o['detail'].splitlines()[-1] if o['detail'] else ''}")
        print(f"\n{report['status']}")
    return 0


def cmd_status(args):
    cwd = Path.cwd()
    config, config_path = resolve_config(args.config, cwd)
    base_dir = config_path.parent
    state_path = base_dir / config.get("state_path", DEFAULT_STATE_NAME)
    state = json.loads(state_path.read_text()) if state_path.is_file() else {}
    print(json.dumps({"config": str(config_path), "tracked": state}, indent=2))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Guardrail monitor: watch a condition, fire an action.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_setup = sub.add_parser("setup", help="Write a .monitor.json config (interactive or flag-driven).")
    p_setup.add_argument("directory", nargs="?", default=".", help="Directory to watch (default: current).")
    p_setup.add_argument("--name")
    p_setup.add_argument("--condition", choices=list(CONDITIONS), help="Condition type.")
    p_setup.add_argument("--action", choices=list(ACTIONS), help="Action type.")
    p_setup.add_argument("--pattern", help="Glob for file_mtime condition.")
    p_setup.add_argument("--message-template", help="Commit message template for git_commit.")
    p_setup.add_argument("--scope", choices=["skill_dir", "all"], help="git_commit add scope.")
    p_setup.add_argument("--cmd", help="Command string for shell_command action.")
    p_setup.add_argument("--yes", action="store_true", help="Accept defaults; never prompt.")
    p_setup.add_argument("--force", action="store_true", help="Overwrite existing config.")
    p_setup.set_defaults(func=cmd_setup)

    p_scan = sub.add_parser("scan", help="One pass: detect changes, fire actions, update state.")
    p_scan.add_argument("--config", help=f"Config path (default ./{MONITOR_CONFIG_NAME}).")
    p_scan.add_argument("-n", "--dry-run", action="store_true", help="Report what would fire; change nothing.")
    p_scan.add_argument("--json", action="store_true")
    p_scan.set_defaults(func=cmd_scan)

    p_status = sub.add_parser("status", help="Show tracked versions/state.")
    p_status.add_argument("--config")
    p_status.set_defaults(func=cmd_status)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
