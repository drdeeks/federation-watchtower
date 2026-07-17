#!/usr/bin/env python3
"""
Skill Packager — Creates/updates .skill files (ZIP archives) from skill directories.

Responsibilities:
  - Read version from SKILL.md frontmatter
  - Auto-bump patch version on each package
  - Write bumped version back to SKILL.md
  - Clean nested .skill files before packaging
  - Force overwrite by default
  - Track manifest with version history
"""


import sys
import json
import re
import argparse
import zipfile
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

try:
    import yaml
except ModuleNotFoundError:
    yaml = None


class SkillPackager:
    def __init__(self, skills_root: Path, output_dir: Optional[Path] = None):
        self.skills_root = skills_root.resolve()
        self.output_dir = (output_dir or skills_root).resolve()
        self.results = {
            "operation": "package_skills",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "success",
            "details": {}
        }

    # ── Frontmatter / Version Helpers ─────────────────────────────

    def extract_frontmatter(self, content: str) -> Tuple[Optional[str], str]:
        """Extract YAML frontmatter and body from SKILL.md content."""
        lines = content.splitlines()
        if not lines or lines[0].strip() != "---":
            return None, content
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                frontmatter = "\n".join(lines[1:i])
                body = "\n".join(lines[i + 1:])
                return frontmatter, body
        return None, content

    def parse_version(self, version_str: str) -> List[int]:
        """Parse semver string into [major, minor, patch]."""
        parts = str(version_str).strip().split(".")
        result = []
        for p in parts:
            try:
                result.append(int(p))
            except ValueError:
                result.append(0)
        while len(result) < 3:
            result.append(0)
        return result[:3]

    def bump_patch(self, version_str: str) -> str:
        """Bump patch version. e.g. 0.0.3 -> 0.0.4"""
        v = self.parse_version(version_str)
        v[2] += 1
        return ".".join(str(x) for x in v)

    def read_version(self, skill_dir: Path) -> str:
        """Read current version from SKILL.md frontmatter."""
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            return "0.0.0"
        content = skill_md.read_text(encoding="utf-8", errors="replace")
        frontmatter_text, _ = self.extract_frontmatter(content)
        if frontmatter_text is None:
            return "0.0.0"
        if yaml is not None:
            try:
                fm = yaml.safe_load(frontmatter_text)
                if isinstance(fm, dict):
                    return str(fm.get("version", "0.0.0"))
            except Exception:
                pass
        # Fallback: regex
        m = re.search(r'^version:\s*["\']?([^"\']+)', frontmatter_text, re.MULTILINE)
        return m.group(1).strip() if m else "0.0.0"

    def write_version(self, skill_dir: Path, new_version: str) -> bool:
        """Write bumped version back to SKILL.md frontmatter."""
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            return False
        content = skill_md.read_text(encoding="utf-8", errors="replace")
        # Replace version line in frontmatter (only top-level, not indented metadata)
        def _replace_version(m):
            return f"version: {new_version}"
        new_content = re.sub(
            r'^version:\s*["\']?[^"\'\n]+["\']?\s*$',
            _replace_version,
            content,
            count=1,
            flags=re.MULTILINE,
        )
        if new_content == content:
            # No version line found — insert after first --- line
            lines = content.splitlines()
            insert_idx = 0
            for i, line in enumerate(lines):
                if line.strip() == "---" and i > 0:
                    insert_idx = i
                    break
            lines.insert(insert_idx, f"version: {new_version}")
            new_content = "\n".join(lines)
        skill_md.write_text(new_content, encoding="utf-8")
        return True

    def sync_init_version(self, skill_dir: Path, new_version: str) -> bool:
        """Keep root __init__.py's __version__ in lockstep with SKILL.md."""
        init_py = skill_dir / "__init__.py"
        if not init_py.is_file():
            return False
        try:
            content = init_py.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return False
        # Prefer the module-level `VERSION = "x.y.z"` constant (skills whose
        # __version__ aliases it, like skill-creator itself). Only if that
        # style is absent fall back to a literal `__version__ = "x.y.z"` —
        # and anchor to line start so version strings embedded inside
        # scaffolding templates are never rewritten.
        new_content, n = re.subn(
            r'(?m)^(VERSION\s*=\s*["\'])[^"\']+(["\'])',
            rf'\g<1>{new_version}\g<2>',
            content,
            count=1,
        )
        if n == 0:
            new_content = re.sub(
                r'(?m)^(__version__\s*=\s*["\'])[^"\']+(["\'])',
                rf'\g<1>{new_version}\g<2>',
                content,
                count=1,
            )
        if new_content != content:
            init_py.write_text(new_content, encoding="utf-8")
            return True
        return False

    # ── File Filtering ────────────────────────────────────────────

    def should_include(self, file_path: Path, skill_dir: Path) -> bool:
        """Determine if file should be included in package."""
        excluded_dirs = {
            ".git", "__pycache__", ".pytest_cache", ".mypy_cache",
            ".tox", "node_modules", ".venv", "venv", "dist", "build",
        }
        # NOTE: .exe is a VALID scripts/ type per the validator allowlist —
        # never exclude it. Compiled/derived junk only.
        excluded_suffixes = {
            ".pyc", ".pyo", ".pyd", ".so", ".dll", ".class",
            ".log", ".cache", ".tmp", ".swp", ".swo", "~",
        }

        # Never include .skill files (prevents nested .skill archives)
        if file_path.suffix.lower() == ".skill":
            return False

        # Check excluded directories
        for part in file_path.relative_to(skill_dir).parts:
            if part in excluded_dirs:
                return False

        # Check excluded suffixes
        if file_path.suffix.lower() in excluded_suffixes:
            return False

        # Skip ALL hidden files — no .gitignore exception (VCS metadata never
        # belongs in a skill per BAD_NAME_PATTERNS; the validator FAILs it)
        if file_path.name.startswith("."):
            return False

        return True

    def find_nested_skill_files(self, skill_dir: Path) -> List[str]:
        """Report .skill files nested BELOW root. They are never deleted —
        should_include() already keeps them out of the archive; auto_fix.py
        relocates them with a rename prompt."""
        skill_name = skill_dir.name
        nested = []
        for f in skill_dir.rglob("*.skill"):
            if f.is_file() and not (f.parent == skill_dir
                                    and f.name == f"{skill_name}.skill"):
                nested.append(str(f.relative_to(skill_dir)))
        return nested

    # ── Packaging ─────────────────────────────────────────────────

    def package_skill(self, skill_name: str, overwrite: bool = True, bump: bool = True) -> Dict:
        """Package a single skill into .skill file with version bump."""
        skill_dir = self.skills_root / skill_name

        if not skill_dir.exists():
            return {"skill": skill_name, "status": "failed", "error": "Skill directory not found"}

        if not (skill_dir / "SKILL.md").exists():
            return {"skill": skill_name, "status": "failed", "error": "No SKILL.md found"}

        # Report (never delete) nested .skill files
        nested = self.find_nested_skill_files(skill_dir)

        # Version tracking
        old_version = self.read_version(skill_dir)
        if bump:
            new_version = self.bump_patch(old_version)
            self.write_version(skill_dir, new_version)
            self.sync_init_version(skill_dir, new_version)
        else:
            new_version = old_version

        # Output .skill file inside skill directory
        skill_file = skill_dir / f"{skill_name}.skill"

        if skill_file.exists() and not overwrite:
            return {"skill": skill_name, "status": "skipped", "reason": "File exists, use --overwrite"}

        files_added = 0
        total_size = 0
        tmp_file = skill_dir / f"{skill_name}.skill.tmp"

        try:
            # Write to a temp file first so a failure mid-zip never destroys
            # the previous archive; replace atomically on success.
            with zipfile.ZipFile(tmp_file, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
                for file_path in skill_dir.rglob("*"):
                    if file_path.is_file() and self.should_include(file_path, skill_dir):
                        archive_path = f"{skill_name}/{file_path.relative_to(skill_dir)}"
                        zf.write(file_path, archive_path)
                        files_added += 1
                        total_size += file_path.stat().st_size
            tmp_file.replace(skill_file)

            return {
                "skill": skill_name,
                "status": "success",
                "output": str(skill_file),
                "version": new_version,
                "previous_version": old_version,
                "version_bumped": bump and old_version != new_version,
                "files": files_added,
                "size_bytes": total_size,
                "size_kb": round(total_size / 1024, 1),
                "nested_skill_files": nested,
            }

        except Exception as e:
            if tmp_file.exists():
                tmp_file.unlink()  # partial temp only — old archive untouched
            return {"skill": skill_name, "status": "failed", "error": str(e)}

    def package_all(self, overwrite: bool = True, bump: bool = True, filter_names: Optional[List[str]] = None) -> Dict:
        """Package all skills in the skills root."""
        results = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "skills_root": str(self.skills_root),
            "output_dir": str(self.output_dir),
            "packaged": [],
            "skipped": [],
            "failed": [],
            "total_files": 0,
            "total_size_bytes": 0,
            "versions_bumped": 0,
        }

        skill_dirs = []
        for item in self.skills_root.iterdir():
            if item.is_dir() and not item.name.startswith("."):
                if (item / "SKILL.md").exists():
                    skill_dirs.append(item.name)

        if filter_names:
            skill_dirs = [s for s in skill_dirs if s in filter_names]

        for skill_name in sorted(skill_dirs):
            result = self.package_skill(skill_name, overwrite=overwrite, bump=bump)

            if result["status"] == "success":
                results["packaged"].append(result)
                results["total_files"] += result["files"]
                results["total_size_bytes"] += result["size_bytes"]
                if result.get("version_bumped"):
                    results["versions_bumped"] += 1
            elif result["status"] == "skipped":
                results["skipped"].append(result)
            else:
                results["failed"].append(result)

        self.results["details"] = results

        if results["failed"]:
            self.results["status"] = "partial"

        return self.results

    # ── Manifest ──────────────────────────────────────────────────

    def write_manifest(self, results: Dict, manifest_path: Optional[Path] = None) -> Path:
        """Write packaging manifest with version history."""
        if manifest_path is None:
            manifest_path = self.output_dir / ".skill-manifest.json"

        # Load existing manifest
        manifest = {}
        if manifest_path.exists():
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            except Exception:
                manifest = {}

        if "skills" not in manifest:
            manifest["skills"] = {}

        manifest["last_packaged"] = results.get("timestamp")
        manifest["total_packaged"] = len(results.get("packaged", []))

        for r in results.get("packaged", []):
            name = r["skill"]
            entry = manifest["skills"].get(name, {})
            entry["current_version"] = r.get("version", "0.0.0")
            entry["previous_version"] = r.get("previous_version", "0.0.0")
            entry["last_packaged"] = results.get("timestamp")
            entry["files"] = r.get("files", 0)
            entry["size_bytes"] = r.get("size_bytes", 0)
            if "history" not in entry:
                entry["history"] = []
            entry["history"].append({
                "version": r.get("version"),
                "timestamp": results.get("timestamp"),
                "files": r.get("files", 0),
            })
            # Keep last 20 entries
            entry["history"] = entry["history"][-20:]
            manifest["skills"][name] = entry

        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return manifest_path


def main():
    parser = argparse.ArgumentParser(description="Package skills into .skill files (ZIP archives)")
    parser.add_argument("--skills-root", required=True, help="Root directory containing skill directories")
    parser.add_argument("--output-dir", help="Output directory for .skill files (default: skills-root)")
    parser.add_argument("--skill", help="Package specific skill only")
    parser.add_argument("--skills", nargs="+", help="Package specific skills only")
    parser.add_argument("--overwrite", action="store_true", default=True, help="Overwrite existing .skill files (default: true)")
    parser.add_argument("--no-overwrite", action="store_false", dest="overwrite", help="Don't overwrite existing")
    parser.add_argument("--bump", action="store_true", default=True, help="Auto-bump patch version (default: true)")
    parser.add_argument("--no-bump", action="store_false", dest="bump", help="Don't bump version")
    parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    packager = SkillPackager(Path(args.skills_root), Path(args.output_dir) if args.output_dir else None)

    if args.skill:
        result = packager.package_skill(args.skill, overwrite=args.overwrite, bump=args.bump)
        results = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "skills_root": str(packager.skills_root),
            "output_dir": str(packager.output_dir),
            "packaged": [result] if result["status"] == "success" else [],
            "skipped": [result] if result["status"] == "skipped" else [],
            "failed": [result] if result["status"] == "failed" else [],
            "total_files": result.get("files", 0) if result["status"] == "success" else 0,
            "total_size_bytes": result.get("size_bytes", 0) if result["status"] == "success" else 0,
            "versions_bumped": 1 if result.get("version_bumped") else 0,
        }
    elif args.skills:
        result = packager.package_all(overwrite=args.overwrite, bump=args.bump, filter_names=args.skills)
        results = result
    else:
        result = packager.package_all(overwrite=args.overwrite, bump=args.bump)
        results = result

    # Write manifest
    manifest_path = packager.write_manifest(results)

    if args.json:
        results["manifest"] = str(manifest_path)
        print(json.dumps(results, indent=2))
    else:
        details = results.get("details", results)
        print(f"=== Skill Packaging Report ===")
        print(f"Skills root: {details.get('skills_root', args.skills_root)}")
        print(f"Output dir: {details.get('output_dir', args.skills_root)}")
        print(f"Packaged: {len(details.get('packaged', []))}")
        print(f"Skipped: {len(details.get('skipped', []))}")
        print(f"Failed: {len(details.get('failed', []))}")
        print(f"Versions bumped: {details.get('versions_bumped', 0)}")
        print(f"Total files: {details.get('total_files', 0)}")
        print(f"Total size: {details.get('total_size_bytes', 0) / 1024:.1f} KB")
        print(f"Manifest: {manifest_path}")
        print()

        for r in details.get("packaged", []):
            bump_info = f" (v{r.get('previous_version')} -> v{r.get('version')})" if r.get("version_bumped") else ""
            nested = f" [⚠ {len(r.get('nested_skill_files', []))} nested .skill NOT packaged — run auto_fix]" if r.get("nested_skill_files") else ""
            print(f"  ✓ {r['skill']}: v{r.get('version', '?')} | {r['files']} files, {r['size_kb']} KB{bump_info}{nested}")

        for r in details.get("skipped", []):
            print(f"  ⊘ {r['skill']}: {r.get('reason', 'skipped')}")

        for r in details.get("failed", []):
            print(f"  ✗ {r['skill']}: {r.get('error', 'failed')}")

    has_failures = bool(details.get("failed", []))
    sys.exit(1 if has_failures else 0)


if __name__ == "__main__":
    main()
