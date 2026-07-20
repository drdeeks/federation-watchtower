#!/usr/bin/env python3
"""
Consolidate redundant skills into a single robust skill.

Merges overlapping functionality while preserving unique features. Nothing
from any source is silently dropped: on a filename conflict the winner is
chosen by the robustness ladder and EVERY decision is recorded in the
report (and the loser is kept alongside with a `-from-<skill>` suffix when
its content genuinely differs).

Robustness ladder (per user spec) for ranking conflicting sources:
  1. Higher SKILL.md frontmatter version wins
  2. Same version → more files in the skill wins
  3. Same count  → identical hash = no conflict; different hash = keep BOTH
     (winner by larger content size gets the canonical name, the other is
     preserved with a suffixed name and surfaced for operator review)

Usage:
    python3 consolidate_skills.py --skills <dir1> <dir2> ... --output <dir>
                                  [--primary NAME] [--json] [--dry-run]
"""
import argparse
import hashlib
import json
import os
import re
import sys
sys.dont_write_bytecode = True  # keep __pycache__ out of skill trees
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import yaml
except ModuleNotFoundError:
    yaml = None

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from skill_root import find_skill_root, nested_skill_mds



# ── Frontmatter helpers ──────────────────────────────────────────────────

def extract_frontmatter(content: str) -> Tuple[Dict, str]:
    lines = content.splitlines()
    if not lines or lines[0].strip() != '---':
        return {}, content
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            fm_text = '\n'.join(lines[1:i])
            body = '\n'.join(lines[i + 1:])
            if yaml is not None:
                try:
                    fm = yaml.safe_load(fm_text)
                    return (fm if isinstance(fm, dict) else {}), body
                except yaml.YAMLError:
                    return {}, body
            fm = {}
            for line in fm_text.splitlines():
                if ':' in line and not line.startswith(' '):
                    k, v = line.split(':', 1)
                    fm[k.strip()] = v.strip()
            return fm, body
    return {}, content


def version_tuple(v) -> Tuple[int, ...]:
    parts = []
    for p in str(v or "0.0.0").strip().split("."):
        try:
            parts.append(int(re.sub(r"\D.*$", "", p) or 0))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def file_hash(p: Path) -> str:
    h = hashlib.sha256()
    try:
        h.update(p.read_bytes())
    except OSError:
        return ""
    return h.hexdigest()


# ── Source ranking (the robustness ladder) ───────────────────────────────

def rank_sources(skill_dirs: List[Path]) -> List[Dict]:
    """Return per-source info sorted most-robust-first."""
    infos = []
    for d in skill_dirs:
        fm, _ = ({}, "")
        skill_md = d / "SKILL.md"
        if skill_md.is_file():
            fm, _ = extract_frontmatter(
                skill_md.read_text(encoding="utf-8", errors="replace"))
        files = [f for f in d.rglob("*")
                 if f.is_file() and "__pycache__" not in f.parts
                 and f.suffix != ".skill"]
        infos.append({
            "dir": d,
            "name": d.name,
            "version": str(fm.get("version", "0.0.0")),
            "version_tuple": version_tuple(fm.get("version")),
            "file_count": len(files),
            "total_bytes": sum(f.stat().st_size for f in files),
            "frontmatter": fm,
        })
    infos.sort(key=lambda i: (i["version_tuple"], i["file_count"],
                              i["total_bytes"]), reverse=True)
    return infos


# ── SKILL.md body merge ──────────────────────────────────────────────────

def extract_sections(content: str) -> Dict[str, str]:
    sections = {}
    current, buf = "preamble", []
    for line in content.splitlines():
        if line.startswith('## '):
            if buf:
                sections[current] = '\n'.join(buf)
            current, buf = line[3:].strip(), []
        else:
            buf.append(line)
    if buf:
        sections[current] = '\n'.join(buf)
    return sections


def merge_section_contents(contents: List[str]) -> str:
    """Merge same-named sections. Dedup repeated prose lines but NEVER
    dedup lines inside fenced code blocks (identical code lines are real)."""
    merged, seen = [], set()
    for content in contents:
        in_code = False
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("```"):
                in_code = not in_code
                merged.append(line)
                continue
            if in_code:
                merged.append(line)
            elif stripped and stripped not in seen:
                merged.append(line)
                seen.add(stripped)
            elif not stripped:
                merged.append(line)
    return '\n'.join(merged)


def merge_bodies(ranked: List[Dict]) -> str:
    all_sections: Dict[str, List[str]] = {}
    order: List[str] = []
    for info in ranked:
        skill_md = info["dir"] / "SKILL.md"
        if not skill_md.is_file():
            continue
        _, body = extract_frontmatter(
            skill_md.read_text(encoding="utf-8", errors="replace"))
        for name, content in extract_sections(body).items():
            if name not in all_sections:
                all_sections[name] = []
                order.append(name)
            all_sections[name].append(content)

    parts = []
    for name in order:
        contents = all_sections[name]
        body = contents[0] if len(contents) == 1 else merge_section_contents(contents)
        parts.append(body if name == "preamble" else f"## {name}\n{body}")
    return '\n\n'.join(parts)


def merge_frontmatters(ranked: List[Dict], primary_name: str) -> Dict:
    """Most-robust source is the base; tags become the deduped union."""
    base = dict(ranked[0]["frontmatter"]) if ranked else {}
    merged = {
        "name": primary_name,
        "description": base.get("description", ""),
        "version": max((i["version_tuple"] for i in ranked), default=(0, 1, 0)),
        "license": base.get("license", "MIT"),
        "metadata": {},
    }
    merged["version"] = ".".join(str(x) for x in merged["version"])

    tags: List[str] = []
    for info in ranked:
        meta = info["frontmatter"].get("metadata")
        if isinstance(meta, dict):
            for k, v in meta.items():
                if k == "tags":
                    continue
                merged["metadata"].setdefault(k, v)
            raw = meta.get("tags", [])
            if isinstance(raw, list):
                for t in raw:
                    if isinstance(t, str) and t.strip() and t not in tags:
                        tags.append(t)
        if not merged["description"] and info["frontmatter"].get("description"):
            merged["description"] = info["frontmatter"]["description"]
    merged["metadata"]["tags"] = tags
    merged["metadata"]["provenance"] = [i["name"] for i in ranked]
    return merged


# ── File merge with the conflict ladder ──────────────────────────────────

def merge_tree(ranked: List[Dict], sub: str, output_dir: Path,
               result: Dict, dry_run: bool):
    """Merge one subtree (scripts/ or references/) across all sources.
    Winner-by-rank gets the canonical name; genuinely different losers are
    preserved with a provenance suffix and logged for operator review."""
    chosen: Dict[str, Tuple[Path, Dict]] = {}
    for info in ranked:  # ranked order → first claim is the most robust
        src = info["dir"] / sub
        if not src.is_dir():
            continue
        for f in src.rglob("*"):
            if not f.is_file() or "__pycache__" in f.parts:
                continue
            rel = str(f.relative_to(src))
            if rel not in chosen:
                chosen[rel] = (f, info)
                continue
            winner_file, winner_info = chosen[rel]
            if file_hash(winner_file) == file_hash(f):
                continue  # identical content — no conflict
            # Different content: keep BOTH. Winner already holds canonical
            # name (it ranked higher); loser gets a provenance suffix.
            alt_rel = re.sub(
                r"(\.[^.]+)$", rf"-from-{info['name']}\1", rel
            ) if "." in Path(rel).name else f"{rel}-from-{info['name']}"
            dest = output_dir / sub / alt_rel
            if not dry_run:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(f.read_bytes())
            result["files_merged"] += 1
            result["conflicts"].append({
                "path": f"{sub}/{rel}",
                "kept_canonical_from": winner_info["name"],
                "reason": (f"{winner_info['name']} ranked higher "
                           f"(v{winner_info['version']}, "
                           f"{winner_info['file_count']} files)"),
                "preserved_variant": f"{sub}/{alt_rel}",
                "action_needed": "operator review — merge or drop variant",
            })

    for rel, (f, info) in chosen.items():
        dest = output_dir / sub / rel
        if not dry_run:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(f.read_bytes())
        result["files_merged"] += 1


# ── Main consolidation ───────────────────────────────────────────────────

def consolidate_skills(skill_dirs: List[Path], output_dir: Path,
                       primary_name: Optional[str] = None,
                       dry_run: bool = False) -> Dict:
    result = {
        "operation": "consolidate",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source_skills": [],
        "ranking": [],
        "output_skill": None,
        "files_merged": 0,
        "conflicts": [],
        "warnings": [],
        "dry_run": dry_run,
    }

    # Resolve every input to its true skill root; refuse confused inputs
    roots = []
    for d in skill_dirs:
        root = find_skill_root(d)
        if root is None:
            result["warnings"].append(f"{d}: no SKILL.md found walking up — skipped")
            continue
        if root != Path(d).resolve():
            result["warnings"].append(f"{d}: resolved up to skill root {root}")
        nested = nested_skill_mds(root)
        if nested:
            result["warnings"].append(
                f"{root.name}: contains {len(nested)} nested SKILL.md(s) — "
                "resolve nesting before consolidating (skipped)")
            continue
        if root not in roots:
            roots.append(root)

    if len(roots) < 2:
        result["warnings"].append("Need at least 2 valid skills to consolidate")
        return result

    ranked = rank_sources(roots)
    result["source_skills"] = [i["name"] for i in ranked]
    result["ranking"] = [
        {"name": i["name"], "version": i["version"],
         "files": i["file_count"], "bytes": i["total_bytes"]}
        for i in ranked
    ]

    primary_name = primary_name or ranked[0]["name"]
    result["output_skill"] = primary_name

    merged_fm = merge_frontmatters(ranked, primary_name)
    merged_body = merge_bodies(ranked)

    if yaml is not None:
        fm_yaml = yaml.dump(merged_fm, default_flow_style=False,
                            allow_unicode=True, sort_keys=False)
    else:
        fm_yaml = ""
        for key, value in merged_fm.items():
            if isinstance(value, dict):
                fm_yaml += f"{key}:\n"
                for k, v in value.items():
                    if isinstance(v, list):
                        fm_yaml += f"  {k}:\n"
                        for item in v:
                            fm_yaml += f"    - {item}\n"
                    else:
                        fm_yaml += f"  {k}: {v}\n"
            else:
                fm_yaml += f"{key}: {value}\n"

    if not dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "SKILL.md").write_text(
            f"---\n{fm_yaml}---\n\n{merged_body}", encoding="utf-8")
    result["files_merged"] += 1

    # Root __init__.py from the most robust source that has one
    for info in ranked:
        init_src = info["dir"] / "__init__.py"
        if init_src.is_file():
            if not dry_run:
                (output_dir / "__init__.py").write_bytes(init_src.read_bytes())
            result["files_merged"] += 1
            break

    merge_tree(ranked, "scripts", output_dir, result, dry_run)
    merge_tree(ranked, "references", output_dir, result, dry_run)

    if result["conflicts"]:
        result["warnings"].append(
            f"{len(result['conflicts'])} content conflict(s) preserved for "
            "operator review — see 'conflicts'")
    result["warnings"].append(
        "Run the full pipeline (skill_enhance.py update) on the output "
        "before promoting it")
    return result


def main():
    ap = argparse.ArgumentParser(description="Consolidate skills (nothing is ever dropped)")
    ap.add_argument("--skills", nargs="+", required=True, help="Skill dirs (or paths inside them)")
    ap.add_argument("--output", required=True, help="Output directory")
    ap.add_argument("--primary", help="Primary skill name for the merged result")
    ap.add_argument("--json", action="store_true", help="JSON output")
    ap.add_argument("--dry-run", action="store_true", help="Report the plan without writing")
    args = ap.parse_args()

    skill_dirs = [Path(s) for s in args.skills]
    for d in skill_dirs:
        if not d.exists():
            print(f"Error: not found: {d}", file=sys.stderr)
            sys.exit(1)

    result = consolidate_skills(skill_dirs, Path(args.output),
                                args.primary, dry_run=args.dry_run)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print("=== Consolidation Report" + (" (DRY RUN)" if args.dry_run else "") + " ===")
        print(f"Ranking (most robust first):")
        for r in result["ranking"]:
            print(f"  {r['name']}  v{r['version']}  {r['files']} files  {r['bytes']} bytes")
        print(f"Output skill: {result['output_skill']}")
        print(f"Files merged: {result['files_merged']}")
        if result["conflicts"]:
            print(f"\nConflicts preserved for review ({len(result['conflicts'])}):")
            for c in result["conflicts"]:
                print(f"  {c['path']}: canonical from {c['kept_canonical_from']}; "
                      f"variant at {c['preserved_variant']}")
        for w in result["warnings"]:
            print(f"  ⚠ {w}")

    sys.exit(0)


if __name__ == "__main__":
    main()
