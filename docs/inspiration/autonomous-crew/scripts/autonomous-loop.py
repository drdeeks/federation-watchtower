#!/usr/bin/env python3
"""Portable autonomous crew loop.

Runs one active chain item at a time in a shared workspace. A builder agent
implements the item, a separate reviewer agent verifies it, and the chain only
advances after an explicit `VERDICT: PASS` review.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def tail(path: Path, limit: int = 8000) -> str:
    if not path.exists():
        return ""
    return path.read_bytes()[-limit:].decode("utf-8", errors="replace")


def find_chain(root: Path, explicit: str | None) -> Path:
    if explicit:
        chain = Path(explicit)
        return chain if chain.is_absolute() else root / chain
    candidates = sorted((root / ".chain").glob("*.json")) + sorted((root / ".blueprint-chain").glob("*.json"))
    if not candidates:
        raise SystemExit("No chain JSON found. Pass --chain path/to/chain.json.")
    return candidates[0]


def active_step(chain: dict) -> dict | None:
    active = [step for step in chain.get("steps", []) if step.get("state") == "active"]
    if len(active) == 1:
        return active[0]
    return None


def step_slug(step: dict) -> str:
    path = Path(str(step.get("path", f"step-{step.get('index', 0)}")))
    return f"{int(step.get('index', 0)):02d}-{path.name}"


def step_title(step: dict) -> str:
    return Path(str(step.get("path", "active-step"))).name.replace("-", " ")


def review_passed(path: Path) -> bool:
    return path.exists() and bool(re.search(r"^VERDICT: PASS\s*$", path.read_text(encoding="utf-8", errors="replace"), re.MULTILINE))


def run_command(command: str, root: Path, timeout: int) -> dict:
    started = utc_now()
    try:
        result = subprocess.run(
            shlex.split(command),
            cwd=root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
        return {
            "command": command,
            "started_at": started,
            "finished_at": utc_now(),
            "returncode": result.returncode,
            "output": result.stdout[-4000:],
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "command": command,
            "started_at": started,
            "finished_at": utc_now(),
            "returncode": 124,
            "output": (exc.stdout or "")[-4000:],
            "error": "timeout",
        }


def run_preflight(root: Path, commands: list[str], timeout: int) -> dict:
    results = {}
    for idx, command in enumerate(commands, start=1):
        results[f"preflight_{idx}"] = run_command(command, root, timeout)
    return results


def preflight_summary(results: dict) -> str:
    if not results:
        return "- no preflight commands configured"
    lines = []
    for name, result in results.items():
        state = "ok" if result.get("returncode") == 0 else "failed"
        lines.append(f"- {name}: {state} ({result.get('command')})")
    return "\n".join(lines)


def codex_prompt(role: str, step: dict, evidence: Path, review: Path, root: Path, preflight: dict) -> str:
    title = step_title(step)
    if role == "builder":
        return f"""You are the autonomous crew builder. Work without asking for human input.

Use the repository at `{root}` as one shared workspace. Read AGENTS.md,
blueprint/checklist files, and the active chain item `{title}`. Implement only
this active item. Preserve unrelated user changes.

Supervisor preflight:
{preflight_summary(preflight)}

Run the checks required to prove the item works. Write `{evidence.relative_to(root)}`
with requirement, files changed, commands run, limitations, and
`builder_status: ready_for_independent_review` only when the gate is actually
met. Commit focused project changes when possible. Do not edit the chain,
review file, or claim reviewer approval.
"""
    return f"""You are the autonomous crew reviewer. Work without asking for human input.

Use the repository at `{root}` as one shared workspace. Read AGENTS.md,
blueprint/checklist files, active item `{title}`, and `{evidence.relative_to(root)}`.
Inspect the actual implementation and run independent checks.

Supervisor preflight:
{preflight_summary(preflight)}

Write only `{review.relative_to(root)}`. Use final line `VERDICT: PASS` only
when the active requirement and validation gate are demonstrably satisfied.
Otherwise use `VERDICT: FAIL` with concrete failures. Do not edit application
source, chain state, blueprint, checklist, or user assets.
"""


def run_codex(root: Path, prompt: str, output_file: Path, status_file: Path, base_status: dict,
              role: str, timeout: int, heartbeat: int, sandbox: str, model: str | None,
              bypass: bool) -> dict:
    command = ["codex", "exec", "--cd", str(root), "--output-last-message", str(output_file)]
    if bypass:
        command.append("--dangerously-bypass-approvals-and-sandbox")
    else:
        command.extend(["--sandbox", sandbox])
    if model:
        command.extend(["--model", model])
    command.append(prompt)

    stdout_log = output_file.with_name(f"{output_file.name}.stdout.log")
    output_file.parent.mkdir(parents=True, exist_ok=True)
    started_dt = datetime.now(timezone.utc)
    started = started_dt.isoformat().replace("+00:00", "Z")
    with stdout_log.open("w", encoding="utf-8") as out:
        proc = subprocess.Popen(command, cwd=root, text=True, stdout=out, stderr=subprocess.STDOUT)
        while proc.poll() is None:
            elapsed = int((datetime.now(timezone.utc) - started_dt).total_seconds())
            payload = dict(base_status)
            payload.update({
                "status": f"{role}_running",
                "heartbeat_at": utc_now(),
                "child": {
                    "role": role,
                    "pid": proc.pid,
                    "started_at": started,
                    "elapsed_seconds": elapsed,
                    "timeout_seconds": timeout,
                    "stdout_log": str(stdout_log.relative_to(root)),
                    "last_message": str(output_file.relative_to(root)),
                },
            })
            write_json(status_file, payload)
            if elapsed >= timeout:
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=10)
                return {
                    "role": role,
                    "started_at": started,
                    "finished_at": utc_now(),
                    "returncode": 124,
                    "stdout_log": str(stdout_log.relative_to(root)),
                    "output": tail(stdout_log),
                    "error": "timeout",
                }
            time.sleep(heartbeat)
    return {
        "role": role,
        "started_at": started,
        "finished_at": utc_now(),
        "returncode": proc.returncode,
        "stdout_log": str(stdout_log.relative_to(root)),
        "output": tail(stdout_log),
    }


def advance_chain(root: Path, chain_file: Path, chain_name: str | None, step: dict) -> dict:
    chain_py = root / "chain.py"
    if not chain_py.exists() or not chain_name:
        return {"ok": False, "reason": "chain.py or --chain-name missing; review passed but chain not advanced"}
    step_path = str(step.get("path", ""))
    verify = subprocess.run([sys.executable, str(chain_py), "verify", str(root), chain_name, step_path],
                            cwd=root, text=True, capture_output=True, check=False)
    if verify.returncode != 0:
        return {"ok": False, "stage": "verify", "output": verify.stdout + verify.stderr}
    complete = subprocess.run([sys.executable, str(chain_py), "complete", str(root), chain_name, step_path],
                              cwd=root, text=True, capture_output=True, check=False)
    if complete.returncode != 0:
        return {"ok": False, "stage": "complete", "output": complete.stdout + complete.stderr}
    return {"ok": True, "chain": str(chain_file), "output": complete.stdout[-2000:]}


def cycle(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    chain_file = find_chain(root, args.chain)
    chain = read_json(chain_file)
    step = active_step(chain)
    runtime = root / args.runtime_dir
    evidence_dir = root / args.evidence_dir
    review_dir = root / args.review_dir
    status_file = runtime / "autonomous-crew-status.json"

    if not step:
        complete = bool(chain.get("steps")) and all(s.get("state") == "complete" for s in chain.get("steps", []))
        write_json(status_file, {"status": "complete" if complete else "blocked", "heartbeat_at": utc_now(), "chain": str(chain_file)})
        return 0 if complete else 2

    slug = step_slug(step)
    evidence = evidence_dir / f"{slug}.md"
    review = review_dir / f"{slug}.md"
    preflight = run_preflight(root, args.preflight, args.preflight_timeout)
    base = {
        "heartbeat_at": utc_now(),
        "chain": str(chain_file.relative_to(root)),
        "active_step": step,
        "evidence": str(evidence.relative_to(root)),
        "review": str(review.relative_to(root)),
        "preflight": {k: {"returncode": v.get("returncode"), "command": v.get("command"), "output": v.get("output")} for k, v in preflight.items()},
    }

    if args.dry_run:
        write_json(status_file, {"status": "dry_run", **base})
        print(json.dumps({"active": step_title(step), "status_file": str(status_file)}, indent=2))
        return 0

    evidence_ready = evidence.exists() and "builder_status: ready_for_independent_review" in evidence.read_text(encoding="utf-8", errors="replace")
    if not evidence_ready or (review.exists() and not review_passed(review)):
        builder_result = run_codex(
            root, codex_prompt("builder", step, evidence, review, root, preflight),
            runtime / f"builder-{slug}.txt", status_file, base, "builder",
            args.builder_timeout, args.heartbeat, args.sandbox, args.model, args.bypass,
        )
        if builder_result.get("returncode") != 0:
            write_json(status_file, {"status": "builder_failed", "builder": builder_result, **base})
            return 2

    reviewer_result = run_codex(
        root, codex_prompt("reviewer", step, evidence, review, root, preflight),
        runtime / f"reviewer-{slug}.txt", status_file, base, "reviewer",
        args.reviewer_timeout, args.heartbeat, args.sandbox, args.model, args.bypass,
    )
    if reviewer_result.get("returncode") != 0 or not review_passed(review):
        write_json(status_file, {"status": "review_failed", "reviewer": reviewer_result, **base})
        return 2

    advanced = advance_chain(root, chain_file, args.chain_name, step)
    write_json(status_file, {"status": "advanced" if advanced.get("ok") else "review_passed_chain_not_advanced",
                             "reviewer": reviewer_result, "advance": advanced, **base})
    return 0 if advanced.get("ok") else 2


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a portable autonomous crew loop.")
    parser.add_argument("--root", default=".", help="Project root/shared workspace.")
    parser.add_argument("--chain", help="Chain JSON path. Defaults to first .chain/*.json.")
    parser.add_argument("--chain-name", help="Name passed to root chain.py verify/complete.")
    parser.add_argument("--runtime-dir", default=".agent/runtime/autonomous-crew")
    parser.add_argument("--evidence-dir", default="docs/autonomy/evidence")
    parser.add_argument("--review-dir", default="docs/autonomy/reviews")
    parser.add_argument("--preflight", action="append", default=[], help="Command to run before each cycle; repeatable.")
    parser.add_argument("--preflight-timeout", type=int, default=180)
    parser.add_argument("--builder-timeout", type=int, default=1800)
    parser.add_argument("--reviewer-timeout", type=int, default=1200)
    parser.add_argument("--heartbeat", type=int, default=15)
    parser.add_argument("--interval", type=int, default=30)
    parser.add_argument("--cycles", type=int, default=1, help="0 runs until complete or stopped.")
    parser.add_argument("--sandbox", default="workspace-write", choices=["read-only", "workspace-write", "danger-full-access"])
    parser.add_argument("--bypass", action="store_true", help="Use Codex bypass mode for local Docker/package/server gates.")
    parser.add_argument("--model", help="Optional Codex model.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    count = 0
    last = 0
    while args.cycles == 0 or count < args.cycles:
        last = cycle(args)
        count += 1
        if args.cycles and count >= args.cycles:
            break
        time.sleep(args.interval)
    return last


if __name__ == "__main__":
    raise SystemExit(main())
