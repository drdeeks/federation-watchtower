#!/usr/bin/env python3
"""
self-heal.py — Self-healing wrapper for kanban workers.
Tries all available APIs with exponential backoff.
Logs deaths clearly. Notifies on final failure.

Backoff sequence: 10s → 30s → 2m → 5m → 10m → 15m → 20m → 25m → 30m → 1h → 2h → 5h
Each cycle: tries EVERY available API before advancing to next backoff.
"""
import json
import os
import subprocess
import sys
import time
import signal
from datetime import datetime
from pathlib import Path


# ─── Configuration ────────────────────────────────────────────────

BACKOFF_SEQUENCE = [
    10,      # 10 seconds
    30,      # 30 seconds
    120,     # 2 minutes
    300,     # 5 minutes
    600,     # 10 minutes
    900,     # 15 minutes
    1200,    # 20 minutes
    1500,    # 25 minutes
    1800,    # 30 minutes
    3600,    # 1 hour
    7200,    # 2 hours
    18000,   # 5 hours
]

# API providers to try (in order)
API_PROVIDERS = [
    {"provider": "opencode-zen", "model": "mimo-v2.5-free"},
    {"provider": "opencode-zen", "model": "nemotron-3-ultra-free"},
    {"provider": "opencode-zen", "model": "deepseek-v4-flash-free"},
    {"provider": "opencode-zen", "model": "north-mini-code-free"},
    {"provider": "openrouter", "model": "anthropic/claude-sonnet-4"},
    {"provider": "openrouter", "model": "google/gemini-2.0-flash-001"},
    {"provider": "openrouter", "model": "meta-llama/llama-3.1-8b-instruct:free"},
]

LOG_DIR = Path.home() / ".hermes" / "logs"
DEATH_LOG = LOG_DIR / "agent-deaths.log"


# ─── Helpers ──────────────────────────────────────────────────────

def log_event(task_id, event, details=""):
    """Append to death log."""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.utcnow().isoformat() + "Z"
    line = f"[{timestamp}] {task_id}: {event}"
    if details:
        line += f" — {details}"
    with open(DEATH_LOG, "a") as f:
        f.write(line + "\n")
    print(line, file=sys.stderr)


def try_api(provider, model, test_prompt="say OK"):
    """Test if an API provider/model is reachable."""
    try:
        r = subprocess.run(
            ["hermes", "chat", "-q", test_prompt,
             "--provider", provider, "--model", model],
            capture_output=True, text=True, timeout=30
        )
        return r.returncode == 0
    except subprocess.TimeoutExpired:
        return False
    except Exception:
        return False


def try_all_apis():
    """Try every available API. Return (success: bool, working: dict or None)."""
    for api in API_PROVIDERS:
        if try_api(api["provider"], api["model"]):
            return True, api
    return False, None


def format_backoff(seconds):
    """Human-readable backoff duration."""
    if seconds < 60:
        return f"{seconds}s"
    elif seconds < 3600:
        return f"{seconds // 60}m"
    else:
        return f"{seconds // 3600}h"


def notify_death(task_id, cycles_attempted):
    """Log clear death notification."""
    log_event(task_id, "DEAD",
              f"All APIs exhausted after {cycles_attempted} cycles. "
              f"Update API keys and re-dispatch.")

    # Write death marker file for kanban to pick up
    marker = LOG_DIR / f"death-{task_id}.json"
    with open(marker, "w") as f:
        json.dump({
            "task_id": task_id,
            "status": "dead",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "cycles_attempted": cycles_attempted,
            "backoff_sequence_exhausted": True,
            "action_required": "Update API keys and run: hermes kanban reclaim "
                               f"{task_id} && hermes kanban dispatch"
        }, f, indent=2)


# ─── Main Loop ────────────────────────────────────────────────────

def run_with_self_heal(task_id, command):
    """
    Run a kanban worker command with self-healing.
    
    If the worker crashes:
    1. Try all APIs
    2. If any work, restart immediately
    3. If none work, backoff and retry
    4. After all backoffs exhausted, die with notification
    """
    log_event(task_id, "STARTED", f"command: {command}")
    
    cycle = 0
    while cycle < len(BACKOFF_SEQUENCE):
        # Try all APIs
        success, working_api = try_all_apis()
        
        if success:
            log_event(task_id, "API_FOUND",
                      f"{working_api['provider']}/{working_api['model']}")
            
            # Run the actual worker
            try:
                result = subprocess.run(
                    command, shell=True, timeout=300
                )
                if result.returncode == 0:
                    log_event(task_id, "COMPLETED")
                    return 0
                else:
                    log_event(task_id, "CRASHED",
                              f"exit code {result.returncode}")
            except subprocess.TimeoutExpired:
                log_event(task_id, "TIMEOUT", "5min limit")
            except KeyboardInterrupt:
                log_event(task_id, "INTERRUPTED")
                return 1
            
            # Worker crashed — try again immediately (no backoff for crashes)
            continue
        
        # All APIs failed — backoff
        backoff = BACKOFF_SEQUENCE[cycle]
        log_event(task_id, "ALL_APIS_FAILED",
                  f"backoff {format_backoff(backoff)} "
                  f"(cycle {cycle + 1}/{len(BACKOFF_SEQUENCE)})")
        
        time.sleep(backoff)
        cycle += 1
    
    # All backoffs exhausted — die
    notify_death(task_id, len(BACKOFF_SEQUENCE))
    return 1


# ─── CLI ──────────────────────────────────────────────────────────

def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="Self-healing wrapper for kanban workers")
    parser.add_argument("--task-id", required=True,
                        help="Kanban task ID")
    parser.add_argument("--command",
                        help="Worker command to run")
    parser.add_argument("--test", action="store_true",
                        help="Test API connectivity only")
    args = parser.parse_args()
    
    if args.test:
        success, api = try_all_apis()
        if success:
            print(json.dumps({"status": "ok", "working_api": api}))
            return 0
        else:
            print(json.dumps({"status": "no_apis"}))
            return 1
    
    if not args.command:
        parser.error("--command is required when --test is not set")
    
    return run_with_self_heal(args.task_id, args.command)


if __name__ == "__main__":
    sys.exit(main())
