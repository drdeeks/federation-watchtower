#!/usr/bin/env python3
"""
guardrail-enforcement/__init__.py — scaffolder + integrator for the gate.

scaffold() drops a starter ``.gate.json`` into a target directory so a new gated
workflow can be filled in (then finalized with ``scripts/setup.py`` to generate
the HMAC secret). integrate() reports how to wire the gate into a project.
"""
import argparse
import json
from pathlib import Path

__skill__ = "guardrail-enforcement"
__version__ = "0.1.6"

STARTER_CONFIG = {
    "pre_checks": [],
    "loop_command": [],
    "post_checks": [],
    "hmac_secret_path": "~/.config/gate/hmac.key",
    "log_path": ".loop-log.jsonl",
    "git_integration": True,
}


def scaffold(target_name, base_dir):
    """Create a starter .gate.json under base_dir/target_name."""
    target_dir = Path(base_dir) / target_name
    target_dir.mkdir(parents=True, exist_ok=True)
    config_path = target_dir / ".gate.json"
    if not config_path.exists():
        config_path.write_text(json.dumps(STARTER_CONFIG, indent=2) + "\n")
    print(f"Scaffolded gate config at {config_path}")
    print("Next: python3 scripts/setup.py <dir> to fill it in and generate the HMAC secret.")
    return config_path


def integrate(target_path, name, dry_run=False):
    """Report how to wire the gate into a target project."""
    print(f"Integrate guardrail-enforcement into {target_path} (name={name}, dry_run={dry_run}):")
    print("  1. python3 scripts/setup.py <target> --pre-check ... --loop-command ... --post-check ...")
    print("  2. python3 scripts/install_hooks.py --repo <target>   (if git_integration)")
    print("  3. python3 scripts/gate.py --config <target>/.gate.json")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Scaffolder for guardrail-enforcement skill")
    parser.add_argument("--scaffold", help="Name of new instance to scaffold")
    parser.add_argument("--integrate", help="Target path to integrate into")
    parser.add_argument("--name", help="Name of the instance being integrated")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.scaffold:
        scaffold(args.scaffold, Path.cwd())
    elif args.integrate:
        integrate(Path(args.integrate), args.name or "unknown", args.dry_run)
    else:
        parser.print_help()
