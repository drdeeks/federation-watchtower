#!/usr/bin/env python3
"""
Guardrail Loop-Log Verifier
===========================

Verifies the integrity of a ``.loop-log.jsonl`` produced by ``gate.py``:

  1. **Signature** — every entry's ``hmac_sha256`` matches an HMAC-SHA256 of its
     ``entry_hash`` under the secret. A wrong/absent secret or a forged entry
     fails here.
  2. **Chain** — every entry's ``prev_hash`` equals the previous entry's
     ``entry_hash``, and its own ``entry_hash`` recomputes from its body. This
     detects insertion, deletion, or reordering of entries anywhere in the log.

Exit code 0 only when the whole log verifies; non-zero on the first defect (or a
summary of all defects with ``--all``). Path-agnostic: log and secret come from
flags, ``expanduser``-ed; no hardcoded paths.

Also answers the question git hooks ask — "is there a valid PASS entry newer
than N seconds?" — via ``--recent SECONDS`` for hook integration.
"""

import argparse
import hashlib
import hmac
import json
import sys
sys.dont_write_bytecode = True  # never litter skills with __pycache__ (validator FAIL)
from datetime import datetime, timezone
from pathlib import Path

GENESIS = "0" * 64


def load_secret(secret_path):
    p = Path(secret_path).expanduser()
    if not p.is_file():
        raise SystemExit(f"error: HMAC secret not found: {p}")
    data = p.read_bytes().strip()
    if not data:
        raise SystemExit(f"error: HMAC secret is empty: {p}")
    return data


def recompute_hash(entry, prev_hash):
    body = {k: v for k, v in entry.items() if k not in ("entry_hash", "hmac_sha256")}
    body["prev_hash"] = prev_hash
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(prev_hash.encode() + canonical).hexdigest()


def verify(log_path, secret, collect_all):
    defects = []
    entries = []
    with log_path.open() as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append((lineno, json.loads(line)))
            except json.JSONDecodeError as exc:
                defects.append({"line": lineno, "error": f"invalid JSON: {exc}"})

    prev = GENESIS
    for lineno, entry in entries:
        expected_prev = prev
        actual_prev = entry.get("prev_hash")
        if actual_prev != expected_prev:
            defects.append({"line": lineno, "error": f"chain break: prev_hash {actual_prev} != {expected_prev}"})
            if not collect_all:
                break
        recomputed = recompute_hash(entry, expected_prev)
        if recomputed != entry.get("entry_hash"):
            defects.append({"line": lineno, "error": "entry_hash mismatch (body tampered)"})
            if not collect_all:
                break
        expected_sig = hmac.new(secret, entry.get("entry_hash", "").encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected_sig, entry.get("hmac_sha256", "")):
            defects.append({"line": lineno, "error": "HMAC signature invalid (wrong secret or forged)"})
            if not collect_all:
                break
        prev = entry.get("entry_hash", prev)

    return defects, entries


def most_recent_pass_age(entries):
    """Seconds since the newest PASS entry, or None if there is no PASS entry."""
    newest = None
    for _, entry in entries:
        if entry.get("result") != "PASS":
            continue
        ts = entry.get("timestamp", "").replace("Z", "+00:00")
        try:
            dt = datetime.fromisoformat(ts)
        except ValueError:
            continue
        if newest is None or dt > newest:
            newest = dt
    if newest is None:
        return None
    return (datetime.now(timezone.utc) - newest).total_seconds()


def main(argv=None):
    parser = argparse.ArgumentParser(description="Verify a guardrail .loop-log.jsonl (signatures + chain).")
    parser.add_argument("log", nargs="?", default=".loop-log.jsonl", help="Path to the loop log.")
    parser.add_argument("--secret", default="~/.config/gate/hmac.key", help="HMAC secret path.")
    parser.add_argument("--all", action="store_true", help="Report every defect, not just the first.")
    parser.add_argument("--recent", type=float, metavar="SECONDS",
                        help="Also require a valid PASS entry newer than SECONDS (for git hooks).")
    parser.add_argument("--json", action="store_true", help="Machine-readable output.")
    args = parser.parse_args(argv)

    log_path = Path(args.log).expanduser()
    if not log_path.is_file():
        result = {"operation": "verify_log", "status": "failed", "error": f"log not found: {log_path}"}
        print(json.dumps(result, indent=2) if args.json else f"error: log not found: {log_path}",
              file=sys.stderr)
        return 2

    secret = load_secret(args.secret)
    defects, entries = verify(log_path, secret, args.all)

    status = "verified" if not defects else "failed"
    result = {
        "operation": "verify_log",
        "log": str(log_path),
        "entries": len(entries),
        "defects": defects,
        "status": status,
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
    }

    if args.recent is not None:
        age = most_recent_pass_age(entries)
        result["recent_pass_age_seconds"] = age
        if age is None or age > args.recent:
            result["status"] = "failed"
            result["recent_check"] = f"no valid PASS entry within {args.recent}s"
            status = "failed"

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if status == "verified":
            print(f"✓ {len(entries)} entries verified (signatures + chain intact)")
        else:
            for d in defects:
                print(f"✗ line {d['line']}: {d['error']}", file=sys.stderr)
            if result.get("recent_check"):
                print(f"✗ {result['recent_check']}", file=sys.stderr)

    return 0 if status == "verified" else 1


if __name__ == "__main__":
    sys.exit(main())
