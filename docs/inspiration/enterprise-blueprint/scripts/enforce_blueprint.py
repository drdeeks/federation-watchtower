#!/usr/bin/env python3
"""
enforce_blueprint.py — COMPAT WRAPPER around generate_checklist.py.

Deleted the old enforce_blueprint.py? This file IS the replacement.
All real logic lives in generate_checklist.py now. This wrapper just
translates legacy CLI args into the new format.

Legacy CLI:
  enforce_blueprint.py /project --init --blueprint bp.md --checklist cl.md --output dir
  enforce_blueprint.py --phase 0 --step 1 --verify /project [--json]

New unified CLI:
  generate_checklist.py /project --init
  generate_checklist.py /project --phase 0 --step 1 --verify

This wrapper lives here so nothing breaks until the last reference is updated.
"""

import sys
import json
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
GENERATE = SCRIPT_DIR / "generate_checklist.py"


def main():
    args = sys.argv[1:]

    # Translate legacy calls to new CLI
    if "--init" in args:
        # enforce_blueprint.py /project --init --blueprint bp.md --checklist cl.md --output dir
        project_dir = "."
        new_args = []
        i = 0
        while i < len(args):
            if args[i] == "--init":
                new_args.append("--init")
            elif args[i] == "--blueprint" and i + 1 < len(args):
                i += 1  # skip value — no longer needed
            elif args[i] == "--checklist" and i + 1 < len(args):
                i += 1  # skip value — no longer needed
            elif args[i] == "--output" and i + 1 < len(args):
                # --output used to specify chain output dir, now unused
                i += 1
            elif not args[i].startswith("--") and not project_dir:
                project_dir = args[i]
            elif args[i] == "--json":
                new_args.append("--json")
            elif args[i] == "--with-validators":
                new_args.append("--with-validators")
            else:
                if i == 0 and not args[i].startswith("--"):
                    project_dir = args[i]
                else:
                    new_args.append(args[i])
            i += 1

        cmd = [sys.executable, str(GENERATE), project_dir] + new_args
    else:
        # Try to pass through verbatim — the new CLI handles most old flags
        cmd = [sys.executable, str(GENERATE)] + args

    r = subprocess.run(cmd, capture_output=True, text=True)
    out = r.stdout.strip()
    err = r.stderr.strip()

    # Try to parse JSON output for clean passthrough
    if out:
        try:
            parsed = json.loads(out)
            print(json.dumps(parsed, indent=2))
        except json.JSONDecodeError:
            print(out)
    else:
        print(err, file=sys.stderr)

    # If the result contains "error" at top level or non-zero exit, forward it
    if r.returncode != 0 and not out:
        sys.exit(r.returncode)
    elif out:
        try:
            parsed = json.loads(out)
            if isinstance(parsed, dict) and parsed.get("error"):
                sys.exit(1)
            if isinstance(parsed, dict) and parsed.get("ok") is False:
                sys.exit(1)
        except json.JSONDecodeError:
            pass


if __name__ == "__main__":
    main()
