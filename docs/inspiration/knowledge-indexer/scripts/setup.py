#!/usr/bin/env python3
"""
Knowledge Indexer — Setup & Deployment

One-command initialization for the knowledge-indexer skill.

Usage:
    python3 setup.py                 # Full setup
    python3 setup.py --dry-run       # Preview without changes
    python3 setup.py --status        # Show current state
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path.home() / ".knowledge-indexer"
CONFIG_PATH = STATE_DIR / "config.json"

DEFAULT_CONFIG = {
    "version": 1,
    "created_at": "",
    "status": "initializing",
}

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def setup(dry_run=False):
    prefix = "[DRY RUN] " if dry_run else ""
    print(f"{prefix}Setting up knowledge-indexer...\n")
    dirs = [STATE_DIR, STATE_DIR / "analytics", STATE_DIR / "reports", STATE_DIR / "logs"]
    for d in dirs:
        if not dry_run:
            d.mkdir(parents=True, exist_ok=True)
        print(f"  {prefix}Directory: {d}")
    if not dry_run and not CONFIG_PATH.exists():
        config = DEFAULT_CONFIG.copy()
        config["created_at"] = now_iso()
        CONFIG_PATH.write_text(json.dumps(config, indent=2))
    print(f"\n{prefix}Setup complete.")

def show_status():
    if CONFIG_PATH.exists():
        print(json.dumps(json.loads(CONFIG_PATH.read_text()), indent=2))
    else:
        print(f"Not initialized. Run: python3 setup.py")

def main():
    if "--dry-run" in sys.argv:
        setup(dry_run=True)
    elif "--status" in sys.argv:
        show_status()
    elif "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
    else:
        setup()

if __name__ == "__main__":
    main()
