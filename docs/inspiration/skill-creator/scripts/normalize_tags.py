#!/usr/bin/env python3
"""normalize_tags.py — strip install-time provider tag blocks from SKILL.md.

The REPO ships STANDARD tags only (metadata.tags). Provider blocks
(metadata.hermes.tags / metadata.openclaw.tags / metadata.openai.tags) are
INSTALL-TIME state written by skill_enhance.py or the runtime seeder so the
harness picks the skill up — they must never persist in the canonical repo.

Runs automatically from the repo's post-commit hook (see guardrail flow), so
nothing is ever converted back by hand. Only provider `tags` keys are removed;
any other keys inside a provider block are preserved (empty blocks dropped).

Usage:
  normalize_tags.py <SKILL.md | skill dir | skills root> [more paths...]
  normalize_tags.py --check <paths...>   # report only, exit 1 if dirty
"""
import sys
from pathlib import Path

sys.dont_write_bytecode = True

PROVIDERS = ("hermes", "openclaw", "openai")


def find_skill_mds(path: Path):
    if path.is_file() and path.name == "SKILL.md":
        yield path
    elif path.is_dir():
        direct = path / "SKILL.md"
        if direct.is_file():
            yield direct
        else:
            for child in sorted(path.iterdir()):
                sub = child / "SKILL.md"
                if sub.is_file():
                    yield sub


def normalize(skill_md: Path, write: bool = True) -> bool:
    """Return True if the file had provider tag blocks (dirty)."""
    try:
        import yaml
    except ImportError:
        print(f"[normalize-tags] pyyaml missing — cannot process {skill_md}", file=sys.stderr)
        return False
    text = skill_md.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return False
    try:
        end = text.index("\n---", 3)
    except ValueError:
        return False
    fm = yaml.safe_load(text[3:end]) or {}
    meta = fm.get("metadata")
    if not isinstance(meta, dict):
        return False
    dirty = False
    for p in PROVIDERS:
        blk = meta.get(p)
        if isinstance(blk, dict) and "tags" in blk:
            del blk["tags"]
            dirty = True
            if not blk:
                del meta[p]
    if dirty and write:
        new_fm = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True,
                                default_flow_style=False).rstrip()
        skill_md.write_text(f"---\n{new_fm}\n{text[end + 1:]}", encoding="utf-8")
    return dirty


def main() -> int:
    args = sys.argv[1:]
    check_only = "--check" in args
    paths = [a for a in args if a != "--check"]
    if not paths:
        print(__doc__)
        return 2
    dirty_files = []
    for arg in paths:
        for md in find_skill_mds(Path(arg).resolve()):
            if normalize(md, write=not check_only):
                dirty_files.append(md)
                action = "would strip" if check_only else "stripped"
                print(f"[normalize-tags] {action} provider tag blocks: {md}")
    if not dirty_files:
        print("[normalize-tags] clean — standard tags only")
    return 1 if (check_only and dirty_files) else 0


if __name__ == "__main__":
    sys.exit(main())
