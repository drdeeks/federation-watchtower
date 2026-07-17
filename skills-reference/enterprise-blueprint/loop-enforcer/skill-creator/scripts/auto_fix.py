#!/usr/bin/env python3
"""
auto_fix.py — structural auto-fixer for a skill directory.

Split out from validate.py so validate.py stays purely read-only (anyone can
run it any time to check status). All mutation lives here — invoked directly
or via skill_enhance.py.

Contract (CL-042 — never delete):
  MAY DELETE only:
    - Cached/VCS/build dirs (__pycache__, .git, node_modules, ...) — pure caches
    - Empty directories left behind by a move
  MAY MOVE (always preserves content, never clobbers an existing target):
    - lessons/ → references/lessons/
    - templates/ → references/templates/ (then chmod 0444)
    - any stray root file → references/ or scripts/ by extension
    - foreign .skill archives (name != skill) → references/templates/ with a
      rename prompt; the skill's own <name>.skill stays where it is
    - bad-name / forbidden files WITH CONTENT → moved to the correct dir,
      validator still FAILS with a rename hint (the fixer can't pick a good
      name for you — you rename it)
  NEVER:
    - Deletes ANY file, empty or not
    - Overwrites an existing file (collision targets get a numeric suffix)
    - Touches guardrail artifacts (.gate.json, .loop-log.jsonl, ...)
    - Overwrites a non-empty __init__.py (creates one only if MISSING)
    - Modifies file CONTENTS — only file LOCATIONS (except creating a
      missing __init__.py and chmod on templates)

An enterprise validation can still FAIL after auto_fix runs (e.g. bad names
remain). That's by design: auto_fix corrects what's safe, the human rectifies
the rest.

Usage:
  python3 auto_fix.py <skill_dir> [--dry-run] [--json]
"""
import argparse
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import List

sys.dont_write_bytecode = True  # keep __pycache__ out of skill trees

# Import shared helpers from validate.py — single source of truth for
# structural definitions.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate import (
    FORBIDDEN_DIRS,
    FORBIDDEN_ROOT_FILES,
    ALLOWED_ROOT_NAMES,
    GUARDRAIL_ARTIFACTS,
    _is_template_path,
)

SCRIPT_EXTS = {".py", ".sh", ".bat", ".exe", ".ps1", ".js", ".ts", ".mjs", ".cjs"}


def _unique_target(target: Path) -> Path:
    """Never clobber: if target exists, append -relocated-N before suffix."""
    if not target.exists():
        return target
    stem, suffix = target.stem, target.suffix
    n = 1
    while True:
        candidate = target.parent / f"{stem}-relocated-{n}{suffix}"
        if not candidate.exists():
            return candidate
        n += 1


def _move(src: Path, dest: Path, fixes: List[str], skill_path: Path,
          dry_run: bool, note: str = ""):
    dest = _unique_target(dest)
    if not dry_run:
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dest))
    fixes.append(
        f"{'[dry-run] would move' if dry_run else 'moved'}: "
        f"{src.relative_to(skill_path)} → {dest.relative_to(skill_path)}"
        + (f" ({note})" if note else "")
    )


def auto_fix_skill(skill_path, dry_run: bool = False) -> List[str]:
    """Apply CONSERVATIVE structural fixes (move, never delete files)."""
    fixes = []
    skill_path = Path(skill_path).resolve()
    skill_name = skill_path.name
    refs = skill_path / "references"
    scripts = skill_path / "scripts"

    # 1. Purge cached/junk dirs anywhere (pure caches — the only deletion)
    for root, dirs, _ in os.walk(skill_path, topdown=True):
        for d in list(dirs):
            if d in FORBIDDEN_DIRS:
                full = Path(root) / d
                if not dry_run:
                    shutil.rmtree(full, ignore_errors=True)
                fixes.append(
                    f"{'[dry-run] would delete' if dry_run else 'deleted'} "
                    f"cache dir: {full.relative_to(skill_path)}"
                )
                dirs.remove(d)

    # 2. Ensure scripts/ + references/
    for d in (refs, scripts):
        if not d.is_dir():
            if not dry_run:
                d.mkdir(exist_ok=True)
            fixes.append(f"created {d.name}/")

    # 3. Foreign .skill archives (root archive <skill_name>.skill stays put;
    #    the packager regenerates it — we never delete an archive)
    for sk in list(skill_path.rglob("*.skill")):
        if not sk.is_file():
            continue
        if sk.parent == skill_path and sk.name == f"{skill_name}.skill":
            continue
        _move(sk, refs / "templates" / sk.name, fixes, skill_path, dry_run,
              note="foreign .skill archive — rename or extract, do not nest")

    # 4. Forbidden root files: MOVE to references/ (never delete, even empty)
    for forbidden in sorted(FORBIDDEN_ROOT_FILES):
        p = skill_path / forbidden
        if p.is_file():
            _move(p, refs / f"relocated-{forbidden.lstrip('.')}", fixes,
                  skill_path, dry_run, note="rename required — purpose-scoped")

    # 5. Root lessons/ + templates/ → references/{lessons,templates}/
    for sub in ("lessons", "templates"):
        root_sub = skill_path / sub
        if root_sub.is_dir():
            target = refs / sub
            if target.exists():
                for item in list(root_sub.rglob("*")):
                    if item.is_file():
                        rel = item.relative_to(root_sub)
                        _move(item, target / rel, fixes, skill_path, dry_run)
                if not dry_run and not any(root_sub.rglob("*")):
                    shutil.rmtree(root_sub, ignore_errors=True)
            else:
                if not dry_run:
                    shutil.move(str(root_sub), str(target))
                fixes.append(f"moved {sub}/ → references/{sub}/")

    # 6. Relocate stray root entries (guardrail artifacts stay untouched)
    allowed = ALLOWED_ROOT_NAMES | {f"{skill_name}.skill"}
    for item in list(skill_path.iterdir()):
        if item.name in allowed or item.name in GUARDRAIL_ARTIFACTS:
            continue
        if item.name.endswith(".skill"):
            continue  # step 3 handled
        if item.is_dir():
            target = refs / item.name
            if target.exists():
                for f in list(item.rglob("*")):
                    if f.is_file():
                        rel = f.relative_to(item)
                        _move(f, target / rel, fixes, skill_path, dry_run)
                if not dry_run and not any(item.rglob("*")):
                    shutil.rmtree(item, ignore_errors=True)
            else:
                if not dry_run:
                    shutil.move(str(item), str(target))
                fixes.append(f"moved root dir → references/{item.name}/")
        else:
            dest_dir = scripts if item.suffix.lower() in SCRIPT_EXTS else refs
            _move(item, dest_dir / item.name, fixes, skill_path, dry_run,
                  note="stray root file")

    # 7. Empty assets/ containers: remove empty dir only; non-empty is left
    #    for the human (validator FAILs it with redistribution guidance)
    for assets_dir in list(skill_path.rglob("assets")):
        if not assets_dir.is_dir():
            continue
        contents = list(assets_dir.iterdir())
        if not contents:
            if not dry_run:
                assets_dir.rmdir()
            fixes.append(
                f"removed empty assets/: {assets_dir.relative_to(skill_path)}"
            )
        else:
            fixes.append(
                f"LEFT non-empty assets/: {assets_dir.relative_to(skill_path)} "
                f"({len(contents)} items) — redistribute into scripts/ or "
                "references/ with purpose-scoped names (validator FAILs it)"
            )

    # 8. chmod 0444 on templates
    tpl = refs / "templates"
    if tpl.is_dir():
        changed = 0
        for root, _, files in os.walk(tpl):
            for f in files:
                p = Path(root) / f
                try:
                    if p.stat().st_mode & 0o222:
                        if not dry_run:
                            p.chmod(0o444)
                        changed += 1
                except OSError:
                    pass
        if changed:
            fixes.append(
                f"{'[dry-run] would chmod' if dry_run else 'chmod'} 0444 on "
                f"{changed} template file(s)"
            )

    # 9. __init__.py: CREATE only if MISSING. Never overwrite a non-empty one.
    init_py = skill_path / "__init__.py"
    if not init_py.exists():
        version = "0.1.0"
        skill_md = skill_path / "SKILL.md"
        if skill_md.is_file():
            try:
                text = skill_md.read_text(encoding="utf-8", errors="replace")
                import re as _re
                m = _re.search(r'^version:\s*["\']?([^"\'\n]+)', text, _re.M)
                if m:
                    version = m.group(1).strip()
            except OSError:
                pass
        if not dry_run:
            init_py.write_text(
                f'"""\n{skill_name} skill package metadata.\n\n'
                f'Re-exports skill identity for programmatic discovery.\n"""\n\n'
                f'__skill__ = "{skill_name}"\n'
                f'__version__ = "{version}"\n'
                f'__all__ = ["__skill__", "__version__"]\n',
                encoding="utf-8"
            )
        fixes.append("created missing __init__.py")

    return fixes


def main():
    ap = argparse.ArgumentParser(
        description="Conservative structural auto-fixer (move, never delete)")
    ap.add_argument("skill_dir", help="Skill directory to fix")
    ap.add_argument("--dry-run", action="store_true",
                    help="Report what would change without touching anything")
    ap.add_argument("--json", action="store_true", help="JSON output")
    args = ap.parse_args()

    applied = auto_fix_skill(args.skill_dir, dry_run=args.dry_run)

    if args.json:
        print(json.dumps({
            "operation": "auto_fix",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "skill": str(Path(args.skill_dir).resolve()),
            "dry_run": args.dry_run,
            "fixes": applied,
            "count": len(applied),
        }, indent=2))
    else:
        mode = " (dry run)" if args.dry_run else ""
        print(f"[auto_fix]{mode} {len(applied)} fix(es):")
        for f in applied:
            print(f"  • {f}")
    sys.exit(0)


if __name__ == "__main__":
    main()
