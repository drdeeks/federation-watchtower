#!/usr/bin/env python3
"""
Knowledge Indexer — Core Pipeline

Queue-based processing pipeline with parallel execution and retry logic.

Usage:
    python3 pipeline.py process [--max-concurrent 5]
    python3 pipeline.py status
    python3 pipeline.py retry
    python3 pipeline.py --help
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path.home() / ".knowledge-indexer"
QUEUE_FILE = STATE_DIR / "queue.jsonl"
RETRY_FILE = STATE_DIR / "retry_queue.jsonl"
ANALYTICS_DIR = STATE_DIR / "analytics"
MAX_RETRIES = 3

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def read_jsonl(filepath):
    if not Path(filepath).exists():
        return []
    records = []
    for line in Path(filepath).read_text().strip().split("\n"):
        if line.strip():
            records.append(json.loads(line))
    return records

def append_jsonl(filepath, record):
    Path(filepath).parent.mkdir(parents=True, exist_ok=True)
    with open(filepath, "a") as f:
        f.write(json.dumps(record) + "\n")

def do_process():
    pending = [r for r in read_jsonl(QUEUE_FILE) if r.get("status") == "pending"]
    if not pending:
        print("Queue empty.")
        return
    print(f"Processing {len(pending)} items...")

def do_status():
    queue = read_jsonl(QUEUE_FILE)
    retry = read_jsonl(RETRY_FILE)
    pending = len([r for r in queue if r.get("status") == "pending"])
    print(json.dumps({"pending": pending, "retry": len(retry), "total": len(queue)}, indent=2))

def do_retry():
    retries = read_jsonl(RETRY_FILE)
    requeued = 0
    for item in retries:
        if item.get("retries", 0) < MAX_RETRIES:
            item["status"] = "pending"
            append_jsonl(QUEUE_FILE, item)
            requeued += 1
    if retries:
        Path(RETRY_FILE).write_text("")
    print(f"Requeued: {requeued}")

COMMANDS = {"process": do_process, "status": do_status, "retry": do_retry}

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd in ("--help", "-h", "help"):
        print(__doc__)
    elif cmd in COMMANDS:
        COMMANDS[cmd]()
    else:
        print(f"Unknown: {cmd}")
        sys.exit(1)

if __name__ == "__main__":
    main()
