#!/usr/bin/env python3
"""
Guardrail Gate Engine
=====================

A workflow gate that enforces a user-defined loop before an action is allowed to
"land". Each invocation:

    1. Runs the configured **pre-checks**   (abort if any fail)
    2. Runs the configured **loop command**  (the actual work)
    3. Runs the configured **post-checks**   (abort if any fail)
    4. Appends an **HMAC-signed, hash-chained** entry to the loop log
    5. (optional) Verifies a paired ``monitor`` service is active first

The signed, chained log is what git hooks (see ``install_hooks.py``) check to
decide whether a commit is allowed: no valid, recent log entry → no commit.

Design constraints:
  * Python 3.8+ stdlib only — no third-party deps.
  * Path-agnostic: config, log, and secret paths are resolved from the config
    file or CLI flags and ``expanduser``-ed. No hardcoded absolute paths.
  * The same engine gates skills authoring, k8s deploys, or batch pipelines —
    the difference is entirely in ``.gate.json``.

Config schema (``.gate.json`` in the gated directory, or ``--config PATH``):

    {
      "pre_checks":   [["python3", "validate.py", "{path}", "--basic"]],
      "loop_command": ["python3", "build.py", "{path}"],
      "post_checks":  [["python3", "validate.py", "{path}"]],
      "hmac_secret_path": "~/.config/gate/hmac.key",
      "log_path": ".loop-log.jsonl",
      "git_integration": true,
      "paired_monitor_service": "autowatch-curated"
    }

``{path}`` (and any ``--var NAME=VALUE`` you pass) is substituted into every
command token before execution.
"""

import argparse
import hashlib
import hmac
import json
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True  # never litter skills with __pycache__ (validator FAIL)
from datetime import datetime, timezone
from pathlib import Path

GATE_CONFIG_NAME = ".gate.json"
DEFAULT_LOG_NAME = ".loop-log.jsonl"


def utcnow():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def resolve_config(config_arg, cwd):
    path = Path(config_arg).expanduser() if config_arg else (cwd / GATE_CONFIG_NAME)
    if not path.is_file():
        raise SystemExit(f"error: gate config not found: {path}\n"
                         f"run setup.py to create one.")
    with path.open() as fh:
        return json.load(fh), path.resolve()


def load_secret(secret_path):
    p = Path(secret_path).expanduser()
    if not p.is_file():
        raise SystemExit(f"error: HMAC secret not found: {p}\n"
                         f"run setup.py to generate one.")
    data = p.read_bytes().strip()
    if not data:
        raise SystemExit(f"error: HMAC secret is empty: {p}")
    return data


def substitute(tokens, variables):
    out = []
    for tok in tokens:
        for name, value in variables.items():
            tok = tok.replace("{" + name + "}", value)
        out.append(tok)
    return out


def run_command(tokens, cwd, variables, dry_run):
    cmd = substitute(list(tokens), variables)
    record = {"command": cmd}
    if dry_run:
        record["status"] = "planned"
        record["returncode"] = None
        return True, record
    try:
        proc = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, timeout=3600)
        record["returncode"] = proc.returncode
        record["status"] = "passed" if proc.returncode == 0 else "failed"
        if proc.returncode != 0:
            record["detail"] = ((proc.stdout or "") + (proc.stderr or "")).strip()[-2000:]
        return proc.returncode == 0, record
    except subprocess.TimeoutExpired:
        record.update({"status": "failed", "returncode": 124, "detail": "timeout after 3600s"})
        return False, record
    except FileNotFoundError as exc:
        record.update({"status": "failed", "returncode": 127, "detail": str(exc)})
        return False, record


def run_stage(stage_name, command_lists, cwd, variables, dry_run):
    records = []
    ok = True
    for tokens in command_lists:
        passed, rec = run_command(tokens, cwd, variables, dry_run)
        records.append(rec)
        if not passed:
            ok = False
            break  # fail fast within a stage
    return ok, records


def last_log_hash(log_path):
    """Return the chain hash of the last log entry, or the genesis constant."""
    if not log_path.is_file():
        return "0" * 64
    prev = "0" * 64
    with log_path.open() as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                prev = json.loads(line).get("entry_hash", prev)
            except json.JSONDecodeError:
                continue
    return prev


def sign_and_append(log_path, secret, payload):
    """Chain-hash + HMAC-sign a payload and append it as one JSONL line."""
    prev_hash = last_log_hash(log_path)
    body = dict(payload)
    body["prev_hash"] = prev_hash
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":")).encode()
    entry_hash = hashlib.sha256(prev_hash.encode() + canonical).hexdigest()
    signature = hmac.new(secret, entry_hash.encode(), hashlib.sha256).hexdigest()
    body["entry_hash"] = entry_hash
    body["hmac_sha256"] = signature
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a") as fh:
        fh.write(json.dumps(body, sort_keys=True) + "\n")
    return entry_hash


def check_monitor(service_name):
    """Best-effort verify a paired monitor service is active. Returns (ok, detail)."""
    systemctl = shutil.which("systemctl")
    if systemctl:
        proc = subprocess.run([systemctl, "--user", "is-active", service_name],
                              capture_output=True, text=True)
        active = proc.stdout.strip() == "active"
        return active, f"systemctl --user is-active {service_name} -> {proc.stdout.strip() or 'unknown'}"
    launchctl = shutil.which("launchctl")
    if launchctl:
        proc = subprocess.run([launchctl, "list"], capture_output=True, text=True)
        active = service_name in proc.stdout
        return active, f"launchctl list contains {service_name}: {active}"
    return True, "no service manager found; monitor cross-check skipped"


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run a guardrail gate: pre-checks -> loop -> post-checks -> signed log.")
    parser.add_argument("--config", help=f"Path to gate config (default: ./{GATE_CONFIG_NAME}).")
    parser.add_argument("--path", help="Value substituted for {path} in commands.")
    parser.add_argument("--var", action="append", default=[], metavar="NAME=VALUE",
                        help="Extra {NAME} substitution; repeatable.")
    parser.add_argument("--cwd", help="Working directory for commands (default: config's directory).")
    parser.add_argument("-n", "--dry-run", action="store_true", help="Report the plan; run nothing, log nothing.")
    parser.add_argument("--json", action="store_true", help="Emit a machine-readable JSON report.")
    args = parser.parse_args(argv)

    invocation_cwd = Path.cwd()
    config, config_path = resolve_config(args.config, invocation_cwd)
    gated_dir = Path(args.cwd).expanduser().resolve() if args.cwd else config_path.parent

    variables = {}
    if args.path:
        variables["path"] = args.path
    for item in args.var:
        if "=" not in item:
            raise SystemExit(f"error: --var must be NAME=VALUE, got: {item}")
        name, value = item.split("=", 1)
        variables[name] = value

    report = {
        "operation": "gate",
        "timestamp": utcnow(),
        "config": str(config_path),
        "gated_dir": str(gated_dir),
        "stages": {},
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
    }

    # Optional monitor cross-check.
    monitor = config.get("paired_monitor_service")
    if monitor and not args.dry_run:
        ok, detail = check_monitor(monitor)
        report["stages"]["monitor_crosscheck"] = {"status": "passed" if ok else "failed", "detail": detail}
        if not ok:
            report["status"] = "blocked"
            _emit(report, args.json)
            return 1

    # Stage pipeline.
    for stage in ("pre_checks", "loop_command", "post_checks"):
        raw = config.get(stage, [])
        # loop_command is a single command list; the check stages are lists of command lists.
        command_lists = [raw] if stage == "loop_command" and raw and isinstance(raw[0], str) else raw
        ok, records = run_stage(stage, command_lists, gated_dir, variables, args.dry_run)
        report["stages"][stage] = {"status": ("planned" if args.dry_run else ("passed" if ok else "failed")),
                                    "commands": records}
        if not ok:
            report["status"] = "failed"
            _emit(report, args.json)
            return 1

    if args.dry_run:
        report["status"] = "dry_run"
        _emit(report, args.json)
        return 0

    # All stages passed — sign and append the audit entry.
    secret = load_secret(config.get("hmac_secret_path", "~/.config/gate/hmac.key"))
    log_path = Path(config.get("log_path", DEFAULT_LOG_NAME))
    if not log_path.is_absolute():
        log_path = gated_dir / log_path
    entry_hash = sign_and_append(log_path, secret, {
        "timestamp": report["timestamp"],
        "gated_dir": str(gated_dir),
        "variables": variables,
        "result": "PASS",
    })
    report["status"] = "passed"
    report["log_path"] = str(log_path)
    report["entry_hash"] = entry_hash
    _emit(report, args.json)
    return 0


def _emit(report, as_json):
    if as_json:
        print(json.dumps(report, indent=2))
        return
    for name, stage in report.get("stages", {}).items():
        mark = {"passed": "✓", "failed": "✗", "planned": "»"}.get(stage["status"], "?")
        print(f"[{mark}] {name}: {stage['status']}")
        for c in stage.get("commands", []):
            if c.get("detail"):
                print(f"      {c['detail'].splitlines()[-1]}")
    print(f"\nGate: {report.get('status', 'unknown')}"
          + (f"  (logged {report['entry_hash'][:12]}…)" if report.get("entry_hash") else ""))


if __name__ == "__main__":
    sys.exit(main())
