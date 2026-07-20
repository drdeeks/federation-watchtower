#!/usr/bin/env python3
"""
Guardrail Gate Setup
====================

Writes a ``.gate.json`` config into a target directory and generates the HMAC
secret used to sign the loop log. Works two ways:

  * **Interactive** (default when a TTY is attached) — prompts for each field.
  * **Non-interactive** — every field can be supplied via a flag, so CI and
    automation never block on a prompt. Missing flags fall back to safe
    defaults; ``--yes`` accepts all defaults without prompting.

Path-agnostic: the gated directory and secret path are taken from flags or
sensible per-user defaults (``~/.config/gate/hmac.key``); nothing is hardcoded.
The secret file is created ``0600``.
"""

import argparse
import json
import os
import secrets
import sys
sys.dont_write_bytecode = True  # never litter skills with __pycache__ (validator FAIL)
from pathlib import Path

GATE_CONFIG_NAME = ".gate.json"
DEFAULT_SECRET = "~/.config/gate/hmac.key"
DEFAULT_LOG = ".loop-log.jsonl"


def prompt(question, default, interactive):
    if not interactive:
        return default
    suffix = f" [{default}]" if default else ""
    try:
        ans = input(f"? {question}{suffix}: ").strip()
    except EOFError:
        ans = ""
    return ans or default


def prompt_list(question, interactive):
    """Collect a list of shell commands (each split on whitespace). Blank ends input."""
    if not interactive:
        return []
    print(f"? {question} (one per line, blank to finish):")
    commands = []
    while True:
        try:
            line = input("    > ").strip()
        except EOFError:
            break
        if not line:
            break
        commands.append(line.split())
    return commands


def parse_cmd(value):
    """Turn a --flag string into a command-list; JSON array or shell-split string."""
    if not value:
        return None
    value = value.strip()
    if value.startswith("["):
        return json.loads(value)
    return value.split()


def ensure_secret(secret_path):
    p = Path(secret_path).expanduser()
    if p.is_file() and p.read_bytes().strip():
        return p, False
    p.parent.mkdir(parents=True, exist_ok=True)
    # 64 hex chars = 256 bits of entropy.
    p.write_text(secrets.token_hex(32))
    os.chmod(p, 0o600)
    return p, True


def main(argv=None):
    parser = argparse.ArgumentParser(description="Create a .gate.json config and HMAC secret.")
    parser.add_argument("directory", nargs="?", default=".", help="Directory to gate (default: current).")
    parser.add_argument("--pre-check", action="append", default=[], help="Pre-check command; repeatable.")
    parser.add_argument("--loop-command", help="The loop command (JSON array or shell string).")
    parser.add_argument("--post-check", action="append", default=[], help="Post-check command; repeatable.")
    parser.add_argument("--secret-path", default=DEFAULT_SECRET, help=f"HMAC secret path (default: {DEFAULT_SECRET}).")
    parser.add_argument("--log-path", default=DEFAULT_LOG, help=f"Loop log path (default: {DEFAULT_LOG}).")
    parser.add_argument("--monitor", help="Paired monitor service name to cross-check (optional).")
    parser.add_argument("--no-git", action="store_true", help="Disable git hook integration.")
    parser.add_argument("--yes", action="store_true", help="Accept defaults; never prompt.")
    parser.add_argument("--force", action="store_true", help="Overwrite an existing .gate.json.")
    parser.add_argument("-n", "--dry-run", action="store_true",
                        help="Report the config that would be written; write nothing.")
    args = parser.parse_args(argv)

    target = Path(args.directory).expanduser().resolve()
    if not target.is_dir():
        raise SystemExit(f"error: not a directory: {target}")
    config_path = target / GATE_CONFIG_NAME
    if config_path.exists() and not args.force:
        raise SystemExit(f"error: {config_path} exists (use --force to overwrite).")

    interactive = sys.stdin.isatty() and not args.yes and not any(
        [args.loop_command, args.pre_check, args.post_check]
    )

    pre = [parse_cmd(" ".join(c)) if isinstance(c, list) else parse_cmd(c) for c in args.pre_check]
    pre = [c for c in pre if c] or prompt_list("Pre-check commands", interactive)
    loop = parse_cmd(args.loop_command)
    if not loop and interactive:
        raw = prompt("Loop command (the actual work)", "", interactive)
        loop = raw.split() if raw else []
    post = [parse_cmd(c) for c in args.post_check]
    post = [c for c in post if c] or prompt_list("Post-check commands", interactive)

    secret_path = prompt("Where to store the HMAC secret", args.secret_path, interactive)
    log_path = prompt("Where to store the loop log", args.log_path, interactive)
    git_integration = not args.no_git
    if interactive:
        git_integration = prompt("Git integration? (y/n)", "y", interactive).lower().startswith("y")
    monitor = args.monitor
    if interactive and monitor is None:
        monitor = prompt("Paired monitor service to verify (blank = none)", "", interactive) or None

    config = {
        "pre_checks": pre,
        "loop_command": loop,
        "post_checks": post,
        "hmac_secret_path": secret_path,
        "log_path": log_path,
        "git_integration": git_integration,
    }
    if monitor:
        config["paired_monitor_service"] = monitor

    if args.dry_run:
        result = {
            "operation": "gate_setup",
            "status": "dry_run",
            "config_path": str(config_path),
            "config": config,
            "secret_path": str(Path(secret_path).expanduser()),
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
        }
        print(json.dumps(result, indent=2))
        print(f"\n(--dry-run) would write {config_path} and ensure secret at "
              f"{Path(secret_path).expanduser()}", file=sys.stderr)
        return 0

    config_path.write_text(json.dumps(config, indent=2) + "\n")
    secret_file, created = ensure_secret(secret_path)

    result = {
        "operation": "gate_setup",
        "status": "success",
        "config": str(config_path),
        "secret": str(secret_file),
        "secret_created": created,
        "git_integration": git_integration,
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
    }
    print(json.dumps(result, indent=2))
    print(f"\n✓ Config written to {config_path}", file=sys.stderr)
    print(f"✓ Secret {'generated' if created else 'reused'} at {secret_file} (mode 0600)", file=sys.stderr)
    if git_integration:
        print("→ Next: python3 install_hooks.py --repo <path>", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
