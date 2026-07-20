#!/usr/bin/env python3
"""
skill_paths.py — self-contained loop-enforcer resolution.

Mirrors skill-creator's own pattern (its scripts/chain.py is vendored the
same way): a BAKED-IN copy of chain.py ships in this skill's own scripts/
directory, so enterprise-blueprint works standalone with zero configuration
wherever it's copied — no dependency on where (or whether) a separate
loop-enforcer skill is installed. LOOP_ENFORCER_ROOT, if set and valid,
overrides the vendored copy — useful when several skills on one machine
should share a single loop-enforcer's chain state.
"""
import os
from pathlib import Path

OWN_SCRIPTS_DIR = Path(__file__).resolve().parent


def resolve_loop_enforcer() -> Path:
    """Path to chain.py. LOOP_ENFORCER_ROOT overrides the vendored copy if set."""
    env_le = os.environ.get("LOOP_ENFORCER_ROOT")
    if env_le:
        le_path = Path(env_le).expanduser().resolve() / "scripts" / "chain.py"
        if le_path.exists():
            return le_path
    return OWN_SCRIPTS_DIR / "chain.py"
