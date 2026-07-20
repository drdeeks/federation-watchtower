#!/usr/bin/env python3
"""
chain_migrate.py — Chain migration tool for export/import, version upgrades, cross-project sync.
"""

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List

CHAIN_DIR = ".chain"

def find_chain_dir(base: Path) -> Path:
    current = base.resolve()
    while current != current.parent:
        chain = current / CHAIN_DIR
        if chain.exists():
            return chain
        current = current.parent
    return base / CHAIN_DIR

def load_chain(chain_dir: Path, name: str) -> Dict[str, Any]:
    state_file = chain_dir / f"{name}.json"
    if not state_file.exists():
        return {}
    with open(state_file) as f:
        return json.load(f)

def load_log(chain_dir: Path, name: str) -> List[Dict[str, Any]]:
    log_file = chain_dir / f"{name}.log"
    if not log_file.exists():
        return []
    entries = []
    with open(log_file) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return entries

def export_chain(chain_dir: Path, name: str) -> Dict[str, Any]:
    chain = load_chain(chain_dir, name)
    log = load_log(chain_dir, name)
    return {
        "version": "1.0",
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "chain_name": name,
        "state": chain,
        "log": log
    }

def import_chain(chain_dir: Path, data: Dict[str, Any], new_name: str = None, dry_run: bool = False) -> Dict[str, Any]:
    name = new_name or data.get("chain_name", "imported-chain")
    
    if dry_run:
        return {
            "would_create": f"{name}.json",
            "steps": len(data.get("state", {}).get("steps", [])),
            "log_entries": len(data.get("log", []))
        }
    
    # Write state
    state_file = chain_dir / f"{name}.json"
    with open(state_file, "w") as f:
        json.dump(data["state"], f, indent=2)
    
    # Write log
    log_file = chain_dir / f"{name}.log"
    with open(log_file, "w") as f:
        for entry in data.get("log", []):
            f.write(json.dumps(entry) + "\n")
    
    return {
        "created": str(state_file),
        "steps": len(data["state"].get("steps", [])),
        "log_entries": len(data.get("log", []))
    }

def sync_chain(source_dir: Path, target_dir: Path, name: str, direction: str = "push") -> Dict[str, Any]:
    if direction == "push":
        src, dst = source_dir, target_dir
    else:
        src, dst = target_dir, source_dir
    
    data = export_chain(src, name)
    return import_chain(dst, data, name)

def main():
    parser = argparse.ArgumentParser(description="Chain migration tool")
    parser.add_argument("command", choices=["export", "import", "sync", "version-upgrade"])
    parser.add_argument("--chain", help="Chain name")
    parser.add_argument("--dir", default=".", help="Base directory")
    parser.add_argument("--target-dir", help="Target directory for sync")
    parser.add_argument("--output", help="Output file for export")
    parser.add_argument("--input", help="Input file for import")
    parser.add_argument("--name", help="New chain name for import")
    parser.add_argument("--direction", choices=["push", "pull"], default="push")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--version", help="Target version for upgrade")
    args = parser.parse_args()
    
    base = Path(args.dir).resolve()
    chain_dir = find_chain_dir(base)
    
    if not chain_dir.exists():
        print(json.dumps({"error": f"No .chain directory found in {base} or parents"}))
        return 1
    
    if args.command == "export":
        if not args.chain:
            print(json.dumps({"error": "--chain required"}))
            return 1
        data = export_chain(chain_dir, args.chain)
        if args.output:
            with open(args.output, "w") as f:
                json.dump(data, f, indent=2)
            print(json.dumps({"exported_to": args.output, "chain": args.chain}))
        else:
            print(json.dumps(data, indent=2))
    
    elif args.command == "import":
        if not args.input:
            print(json.dumps({"error": "--input required"}))
            return 1
        with open(args.input) as f:
            data = json.load(f)
        result = import_chain(chain_dir, data, args.name, args.dry_run)
        print(json.dumps(result, indent=2))
    
    elif args.command == "sync":
        if not args.chain or not args.target_dir:
            print(json.dumps({"error": "--chain and --target-dir required"}))
            return 1
        target = Path(args.target_dir).resolve()
        target_chain = find_chain_dir(target)
        if not target_chain.exists():
            print(json.dumps({"error": f"No .chain in target: {target}"}))
            return 1
        result = sync_chain(chain_dir, target_chain, args.chain, args.direction)
        print(json.dumps(result, indent=2))
    
    elif args.command == "version-upgrade":
        if not args.chain or not args.version:
            print(json.dumps({"error": "--chain and --version required"}))
            return 1
        chain = load_chain(chain_dir, args.chain)
        chain["version"] = args.version
        chain["upgraded_at"] = datetime.utcnow().isoformat() + "Z"
        state_file = chain_dir / f"{args.chain}.json"
        with open(state_file, "w") as f:
            json.dump(chain, f, indent=2)
        print(json.dumps({"upgraded": args.chain, "version": args.version}))
    
    return 0

if __name__ == "__main__":
    sys.exit(main())