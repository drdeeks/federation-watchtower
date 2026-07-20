#!/usr/bin/env python3
"""
chain_audit.py — Audit and compliance reporting for loop-enforcer chains.
Generates audit trails, compliance reports, and integrity checks.
"""

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any

CHAIN_DIR = ".chain"

def find_chain_dir(base: Path) -> Path:
    """Find .chain directory, searching upwards."""
    current = base.resolve()
    while current != current.parent:
        chain = current / CHAIN_DIR
        if chain.exists():
            return chain
        current = current.parent
    return base / CHAIN_DIR

def load_chain(chain_dir: Path, name: str) -> Dict[str, Any]:
    """Load chain state from file."""
    state_file = chain_dir / f"{name}.json"
    if not state_file.exists():
        return {}
    with open(state_file) as f:
        return json.load(f)

def load_log(chain_dir: Path, name: str) -> List[Dict[str, Any]]:
    """Load chain audit log."""
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

def audit_chain(chain_dir: Path, name: str) -> Dict[str, Any]:
    """Perform full audit of a chain."""
    chain = load_chain(chain_dir, name)
    log = load_log(chain_dir, name)
    
    if not chain:
        return {"error": f"Chain '{name}' not found"}
    
    steps = chain.get("steps", [])
    total = len(steps)
    verified = sum(1 for s in steps if s.get("state") == "verified")
    complete = sum(1 for s in steps if s.get("state") == "complete")
    active = sum(1 for s in steps if s.get("state") == "active")
    locked = sum(1 for s in steps if s.get("state") == "locked")
    failed = sum(1 for s in steps if s.get("state") == "failed")
    
    # Check for gaps in verification
    verification_gaps = []
    for i, step in enumerate(steps):
        if step.get("state") in ("verified", "complete"):
            if i > 0:
                prev = steps[i-1]
                if prev.get("state") not in ("verified", "complete"):
                    verification_gaps.append({
                        "step": step.get("file"),
                        "index": i,
                        "issue": f"Step {i} verified but step {i-1} ({prev.get('file')}) is {prev.get('state')}"
                    })
    
    # Log analysis
    log_by_step = {}
    for entry in log:
        step_idx = entry.get("step_index", -1)
        if step_idx not in log_by_step:
            log_by_step[step_idx] = []
        log_by_step[step_idx].append(entry)
    
    # Timeline
    timeline = []
    for entry in log:
        timeline.append({
            "timestamp": entry.get("timestamp"),
            "action": entry.get("action"),
            "step": entry.get("step_file"),
            "index": entry.get("step_index"),
            "result": entry.get("result", "unknown")
        })
    
    return {
        "chain": name,
        "audited_at": datetime.utcnow().isoformat() + "Z",
        "summary": {
            "total_steps": total,
            "verified": verified,
            "complete": complete,
            "active": active,
            "locked": locked,
            "failed": failed,
            "completion_rate": round(complete / total * 100, 1) if total > 0 else 0
        },
        "verification_gaps": verification_gaps,
        "log_entries": len(log),
        "timeline": timeline[-20:],  # Last 20 entries
        "integrity": {
            "state_file_exists": (chain_dir / f"{name}.json").exists(),
            "log_file_exists": (chain_dir / f"{name}.log").exists(),
            "steps_match_log": len(set(s.get("file") for s in steps)) == len(steps),
            "no_orphaned_logs": all(e.get("step_index", -1) < total for e in log)
        }
    }

def audit_all(chain_dir: Path) -> Dict[str, Any]:
    """Audit all chains in directory."""
    chains = []
    for state_file in chain_dir.glob("*.json"):
        name = state_file.stem
        if name != "index":  # Skip index if exists
            chains.append(audit_chain(chain_dir, name))
    
    return {
        "audited_at": datetime.utcnow().isoformat() + "Z",
        "total_chains": len(chains),
        "chains": chains
    }

def main():
    parser = argparse.ArgumentParser(description="Chain audit and compliance reporter")
    parser.add_argument("command", choices=["audit", "audit-all", "report"], help="Command to run")
    parser.add_argument("--chain", help="Chain name to audit")
    parser.add_argument("--dir", default=".", help="Base directory (searches up for .chain)")
    parser.add_argument("--output", choices=["json", "text"], default="json")
    parser.add_argument("--save", help="Save report to file")
    args = parser.parse_args()
    
    base = Path(args.dir).resolve()
    chain_dir = find_chain_dir(base)
    
    if not chain_dir.exists():
        print(json.dumps({"error": f"No .chain directory found in {base} or parents"}))
        return 1
    
    if args.command == "audit":
        if not args.chain:
            print(json.dumps({"error": "--chain required for audit"}))
            return 1
        result = audit_chain(chain_dir, args.chain)
    elif args.command == "audit-all":
        result = audit_all(chain_dir)
    elif args.command == "report":
        # Alias for audit-all with text output
        result = audit_all(chain_dir)
        args.output = "text"
    else:
        print(json.dumps({"error": f"Unknown command: {args.command}"}))
        return 1
    
    if args.output == "text":
        # Human-readable output
        if "chains" in result:
            print(f"=== Chain Audit Report ===")
            print(f"Generated: {result['audited_at']}")
            print(f"Total Chains: {result['total_chains']}")
            print()
            for c in result["chains"]:
                if "error" in c:
                    print(f"  ❌ {c['error']}")
                    continue
                s = c["summary"]
                print(f"  📋 {c['chain']}: {s['complete']}/{s['total_steps']} complete ({s['completion_rate']}%)")
                if c["verification_gaps"]:
                    print(f"     ⚠️  {len(c['verification_gaps'])} verification gaps")
                if not c["integrity"]["state_file_exists"]:
                    print(f"     ❌ Missing state file")
        else:
            if "error" in result:
                print(f"❌ {result['error']}")
            else:
                s = result["summary"]
                print(f"=== Audit: {result['chain']} ===")
                print(f"Steps: {s['total_steps']} | Verified: {s['verified']} | Complete: {s['complete']} | Active: {s['active']} | Locked: {s['locked']}")
                print(f"Completion: {s['completion_rate']}%")
                if result["verification_gaps"]:
                    print(f"\n⚠️  Verification Gaps ({len(result['verification_gaps'])}):")
                    for g in result["verification_gaps"]:
                        print(f"   Step {g['index']}: {g['issue']}")
                print(f"\nIntegrity: {'✅' if all(result['integrity'].values()) else '❌'}")
                for k, v in result["integrity"].items():
                    print(f"  {k}: {'✅' if v else '❌'}")
    else:
        print(json.dumps(result, indent=2))
    
    if args.save:
        with open(args.save, "w") as f:
            json.dump(result, f, indent=2)
        print(f"\nSaved to {args.save}", file=sys.stderr)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())