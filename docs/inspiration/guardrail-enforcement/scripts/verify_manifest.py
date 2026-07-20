#!/usr/bin/env python3
"""
Guardrail Manifest Verifier — cross-check manifest ↔ skills ↔ git
=================================================================

Cross-verifies the three sources of truth in a curated-skills repository so they
cannot silently drift apart:

  1. **The manifest** (``.skill-manifest.json``) — the packager's record of every
     skill's ``current_version`` and update history.
  2. **The skills on disk** — each skill's own ``SKILL.md`` frontmatter version,
     and the set of skill directories actually present.
  3. **Git** — the repository that tracks the byte-level hashes of every file, and
     the auto-commit history ("<skill> version bumped to vX.Y.Z") produced by the
     monitor.

It reports, as failures unless noted:

  * **version_mismatch** — manifest ``current_version`` ≠ the on-disk SKILL.md
    version for a skill.
  * **missing_in_manifest** — a skill directory exists on disk with a SKILL.md but
    is absent from the manifest (a newly-added skill the packager hasn't recorded
    yet). This is how the system surfaces "another skill was added".
  * **missing_on_disk** — the manifest names a skill whose directory is gone.
  * **uncommitted** (warning) — a skill has changes not committed to git, so its
    tracked hash is stale relative to the working tree.
  * **no_version_commit** (warning) — git history has no
    "<skill> version bumped to v<current>" commit for the manifest's current
    version (the auto-commit never ran or the message differs).
  * **locked** (info) — a skill currently holds a ``.loop.lock`` (mid-authoring),
    which explains and excuses an uncommitted/mismatch state.

Because git stores the content hashes, a clean (all-committed) working tree whose
versions reconcile with the manifest means the manifest, the files, and the
tracked hashes are all mutually consistent. Path-agnostic: the repo root is
``--repo`` or the current directory.
"""

import argparse
import json
import re
import subprocess
import sys
sys.dont_write_bytecode = True  # never litter skills with __pycache__ (validator FAIL)
from datetime import datetime, timezone
from pathlib import Path

MANIFEST_NAME = ".skill-manifest.json"
VERSION_RE = re.compile(r"^version:\s*[\"']?([^\"'\r\n]+?)[\"']?\s*$", re.MULTILINE)


def utcnow():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def read_skill_version(skill_md):
    try:
        text = skill_md.read_text(errors="ignore")
    except OSError:
        return None
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            text = text[:end]
    m = VERSION_RE.search(text)
    return m.group(1).strip() if m else None


def git(repo, *args):
    try:
        proc = subprocess.run(["git", "-C", str(repo), *args],
                              capture_output=True, text=True)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except FileNotFoundError:
        return 127, "", "git not found"


def is_git_repo(repo):
    rc, _, _ = git(repo, "rev-parse", "--is-inside-work-tree")
    return rc == 0


def discover_skills(repo):
    """Immediate subdirectories that contain a SKILL.md."""
    found = {}
    for child in sorted(repo.iterdir()):
        if child.is_dir() and (child / "SKILL.md").is_file():
            found[child.name] = child
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description="Cross-verify manifest ↔ skills ↔ git.")
    parser.add_argument("--repo", help="Skills repo root (default: current directory).")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--strict", action="store_true",
                        help="Treat warnings (uncommitted / no_version_commit) as failures.")
    args = parser.parse_args(argv)

    repo = Path(args.repo).expanduser().resolve() if args.repo else Path.cwd().resolve()
    if not repo.is_dir():
        raise SystemExit(f"error: not a directory: {repo}")

    findings = []
    have_git = is_git_repo(repo)

    manifest_path = repo / MANIFEST_NAME
    manifest = {}
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text()).get("skills", {})
        except json.JSONDecodeError as exc:
            findings.append({"skill": None, "type": "manifest_corrupt", "severity": "fail", "detail": str(exc)})
    else:
        findings.append({"skill": None, "type": "manifest_missing", "severity": "fail",
                         "detail": f"{MANIFEST_NAME} not found in {repo}"})

    on_disk = discover_skills(repo)

    # 1. manifest ↔ disk reconciliation
    for name, meta in manifest.items():
        current = meta.get("current_version")
        if name not in on_disk:
            findings.append({"skill": name, "type": "missing_on_disk", "severity": "fail",
                             "detail": f"manifest lists {name} v{current} but the directory is absent"})
            continue
        disk_version = read_skill_version(on_disk[name] / "SKILL.md")
        locked = (on_disk[name] / ".loop.lock").exists()
        if disk_version != current:
            findings.append({"skill": name, "type": "version_mismatch",
                             "severity": "info" if locked else "fail",
                             "detail": f"manifest={current} SKILL.md={disk_version}"
                                       + (" (locked, mid-authoring)" if locked else "")})

    # 2. disk ↔ manifest (new skills not yet recorded)
    for name, path in on_disk.items():
        locked = (path / ".loop.lock").exists()
        if locked:
            findings.append({"skill": name, "type": "locked", "severity": "info",
                             "detail": "holds .loop.lock (mid-authoring; excluded from strict checks)"})
        if name not in manifest:
            findings.append({"skill": name, "type": "missing_in_manifest",
                             "severity": "info" if locked else "fail",
                             "detail": f"{name} present on disk but not in manifest "
                                       f"(new skill — run skill_enhance to record it)"})

    # 3. git integrity: working tree committed + version commit exists
    if have_git:
        for name, path in on_disk.items():
            if (path / ".loop.lock").exists():
                continue  # mid-authoring, skip git strictness
            rc, out, _ = git(repo, "status", "--porcelain", "--", name)
            if rc == 0 and out:
                findings.append({"skill": name, "type": "uncommitted", "severity": "warn",
                                 "detail": f"{len(out.splitlines())} uncommitted path(s) under {name}/"})
            current = manifest.get(name, {}).get("current_version")
            if current:
                # Look for the monitor's auto-commit for this version.
                rc, out, _ = git(repo, "log", "--oneline", "--grep",
                                 f"{name} version bumped to v{current}")
                if rc == 0 and not out:
                    findings.append({"skill": name, "type": "no_version_commit", "severity": "warn",
                                     "detail": f"no commit 'v{current}' for {name} in git history"})
    else:
        findings.append({"skill": None, "type": "not_a_git_repo", "severity": "warn",
                         "detail": f"{repo} is not a git repo — hash tracking unavailable"})

    fails = [f for f in findings if f["severity"] == "fail"]
    warns = [f for f in findings if f["severity"] == "warn"]
    if args.strict:
        fails += warns
        warns = []

    status = "verified" if not fails else "failed"
    report = {
        "operation": "verify_manifest",
        "timestamp": utcnow(),
        "repo": str(repo),
        "git": have_git,
        "skills_on_disk": sorted(on_disk),
        "skills_in_manifest": sorted(manifest),
        "findings": findings,
        "summary": {"fail": len(fails), "warn": len(warns), "total": len(findings)},
        "status": status,
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        icon = {"fail": "✗", "warn": "⚠", "info": "·"}
        for f in findings:
            who = f["skill"] or "(repo)"
            print(f"[{icon.get(f['severity'], '?')}] {who}: {f['type']} — {f['detail']}")
        print(f"\n{status}: {len(fails)} fail, {len(warns)} warn "
              f"({len(on_disk)} skills on disk, {len(manifest)} in manifest)")

    return 0 if status == "verified" else 1


if __name__ == "__main__":
    sys.exit(main())
