#!/usr/bin/env python3
"""
gate_status.py — honest, read-only report of the guardrail gate's state.

Answers three questions plainly and WITHOUT claiming anything it did not check:
  1. Is the gate configured?           (.gate.json present at the skill root)
  2. Is the hash log present, and WHERE are hashes stored?   (.loop-log.jsonl)
  3. Does the hash chain actually verify?  (delegates to verify_log.py + HMAC secret)

The .loop-log.jsonl is the single source of truth for every HMAC-signed, hash-
chained gate entry. Path-agnostic: resolves everything relative to this skill dir.
Exit 0 only when the log exists AND its chain verifies; non-zero otherwise.
"""
import json
import subprocess
import sys
sys.dont_write_bytecode = True  # never litter skills with __pycache__ (validator FAIL)
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
GATE_CONFIG = SKILL_DIR / ".gate.json"
DEFAULT_LOG = ".loop-log.jsonl"


def main() -> int:
    report = {"skill_dir": str(SKILL_DIR)}

    # 1. Gate configured?
    report["gate_configured"] = GATE_CONFIG.is_file()
    cfg = {}
    if GATE_CONFIG.is_file():
        try:
            cfg = json.loads(GATE_CONFIG.read_text())
        except json.JSONDecodeError:
            report["gate_config_error"] = "unparseable .gate.json"

    # 2. Hash log present + where hashes are stored?
    log_rel = cfg.get("log_path", DEFAULT_LOG)
    log_path = Path(log_rel)
    if not log_path.is_absolute():
        log_path = SKILL_DIR / log_path
    report["hash_store"] = str(log_path)
    report["hash_log_present"] = log_path.is_file()
    entries = 0
    if log_path.is_file():
        entries = sum(1 for line in log_path.read_text().splitlines() if line.strip())
    report["entries"] = entries

    # 3. Chain verifies? (only a real check — never a bare claim)
    verify_script = SKILL_DIR / "scripts" / "verify_log.py"
    secret = Path(cfg.get("hmac_secret_path", "~/.config/gate/hmac.key")).expanduser()
    report["chain_verified"] = False
    if log_path.is_file() and verify_script.is_file() and secret.is_file():
        proc = subprocess.run(
            [sys.executable, str(verify_script), str(log_path), "--secret", str(secret)],
            capture_output=True, text=True,
        )
        report["chain_verified"] = proc.returncode == 0
        report["verify_detail"] = (proc.stdout + proc.stderr).strip()[-200:]
    elif not secret.is_file():
        report["verify_detail"] = f"HMAC secret not found ({secret}) — cannot verify chain"

    print(json.dumps(report, indent=2))
    ok = report["hash_log_present"] and report["chain_verified"]
    print(("PASS" if ok else "INCOMPLETE") + ": gate hash store "
          + ("present and chain intact." if ok else "not fully verified — see report above."))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
