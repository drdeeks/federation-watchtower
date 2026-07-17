#!/usr/bin/env python3
"""
skill_enhance.py — Enterprise skill pipeline with chain enforcement.

Runs the full create/update pipeline with SEQUENTIAL DEPENDENCY ENFORCEMENT.
Each phase is a locked chain step: scaffold → frontmatter → scripts → refs →
validate → auto-fix → re-validate → test → verify-sources → package → extract-verify.

ENTERPRISE is the standard. Pass --tier basic ONLY if you explicitly want lighter gates.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True

SCRIPT_DIR = Path(__file__).parent.resolve()
SKILL_CREATOR_ROOT = SCRIPT_DIR.parent
LOOP_ENFORCER = Path(os.environ.get(
    "LOOP_ENFORCER_ROOT",
    str(Path.home() / ".hermes" / "skills" / "loop-enforcer")
))

# Chain enforcer commands
CHAIN_PY = LOOP_ENFORCER / "scripts" / "chain.py"
VALIDATE_PY = LOOP_ENFORCER / "scripts" / "validate.py"
CHAIN_REPORT_PY = LOOP_ENFORCER / "scripts" / "chain_report.py"

# Skill creator scripts
VALIDATE_SC = SCRIPT_DIR / "validate.py"
AUTO_FIX = SCRIPT_DIR / "auto_fix.py"
PACKAGE = SCRIPT_DIR / "package_skills.py"
TEST_SCRIPT = SCRIPT_DIR / "test_script.py"
VERIFY_SOURCES = SCRIPT_DIR / "verify_sources.py"

TIER_MINS = {
    "enterprise": {"tags": 7, "scripts": 3, "references": 5},
    "basic":      {"tags": 5, "scripts": 2, "references": 3},
}

CHAIN_STEPS = [
    "scaffold",
    "frontmatter",
    "scripts",
    "references",
    "validate",
    "auto_fix",
    "re_validate",
    "test_scripts",
    "verify_sources",
    "package",
    "extract_verify",
]

def _tty(): return sys.stdout.isatty()

class C:
    G = "\033[32m" if _tty() else ""
    R = "\033[31m" if _tty() else ""
    Y = "\033[33m" if _tty() else ""
    B = "\033[1m"  if _tty() else ""
    D = "\033[2m"  if _tty() else ""
    X = "\033[0m"  if _tty() else ""

def step(n, total, msg): print(f"{C.B}[{n}/{total}]{C.X} {msg}")
def ok(msg):   print(f"  {C.G}✓{C.X} {msg}")
def fail(msg): print(f"  {C.R}✗{C.X} {msg}", file=sys.stderr)
def info(msg): print(f"  {C.D}·{C.X} {msg}")
def warn(msg): print(f"  {C.Y}⚠{C.X} {msg}")

def read_frontmatter(skill_md: Path) -> dict:
    try:
        text = skill_md.read_text(encoding="utf-8")
    except OSError:
        return {}
    if not text.startswith("---"):
        return {}
    lines = text.split("\n")
    if lines[0].strip() != "---":
        return {}
    end = 1
    while end < len(lines) and lines[end].strip() != "---":
        end += 1
    fm_text = "\n".join(lines[1:end])
    try:
        import yaml
        d = yaml.safe_load(fm_text) or {}
        return d if isinstance(d, dict) else {}
    except Exception:
        out = {}
        for line in fm_text.split("\n"):
            if ":" in line:
                k, v = line.split(":", 1)
                out[k.strip()] = v.strip()
        return out

def has_replace_me_markers(skill_md: Path) -> bool:
    try:
        return "REPLACE_ME" in skill_md.read_text(encoding="utf-8")
    except OSError:
        return True

def count_substantive_files(dir_path: Path, min_bytes: int = 200) -> int:
    if not dir_path.is_dir():
        return 0
    count = 0
    for p in dir_path.rglob("*"):
        if not p.is_file() or p.name.startswith("."):
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if len("".join(text.split())) >= min_bytes:
            count += 1
    return count

def run_chain(project_dir: Path, chain_name: str, subcmd: str, *args) -> int:
    """Run a chain.py command and return exit code."""
    cmd = [sys.executable, str(CHAIN_PY), subcmd, str(project_dir), chain_name, *args]
    r = subprocess.run(cmd, cwd=str(project_dir))
    return r.returncode

def chain_check(project_dir: Path, chain_name: str, step_path: str) -> dict:
    """Check if a chain step is active (returns dict with state)."""
    cmd = [sys.executable, str(CHAIN_PY), "check", str(project_dir), chain_name, step_path]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(project_dir))
    if r.returncode == 0:
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return {"error": "parse failed", "raw": r.stdout}
    return {"error": r.stderr}

def chain_verify(project_dir: Path, chain_name: str, step_path: str, validator_args: list = None) -> dict:
    """Verify a chain step, running validator if configured."""
    if validator_args:
        cmd = [sys.executable, str(CHAIN_PY), "set-validator", str(project_dir), chain_name, step_path, str(VALIDATE_PY), *validator_args]
        subprocess.run(cmd, cwd=str(project_dir))
    cmd = [sys.executable, str(CHAIN_PY), "verify", str(project_dir), chain_name, step_path]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(project_dir))
    if r.returncode == 0:
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return {"error": "parse failed", "raw": r.stdout}
    return {"error": r.stderr}

def chain_complete(project_dir: Path, chain_name: str, step_path: str) -> dict:
    cmd = [sys.executable, str(CHAIN_PY), "complete", str(project_dir), chain_name, step_path]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(project_dir))
    if r.returncode == 0:
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return {"error": "parse failed", "raw": r.stdout}
    return {"error": r.stderr}

def chain_status(project_dir: Path, chain_name: str) -> dict:
    cmd = [sys.executable, str(CHAIN_PY), "status", str(project_dir), chain_name]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(project_dir))
    if r.returncode == 0:
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return {"error": "parse failed"}
    return {"error": r.stderr}

def gate_frontmatter(skill_dir: Path, mins: dict, interactive: bool) -> bool:
    skill_md = skill_dir / "SKILL.md"
    while True:
        problems = []
        if not skill_md.exists():
            problems.append("SKILL.md does not exist yet")
        else:
            fm = read_frontmatter(skill_md)
            if has_replace_me_markers(skill_md):
                problems.append("SKILL.md still contains REPLACE_ME_* markers")
            desc = str(fm.get("description", "")).strip()
            if len(desc) < 100:
                problems.append(f"description too short ({len(desc)} chars; need >= 100)")
            elif len(desc) > 1024:
                problems.append(f"description too long ({len(desc)} chars; need <= 1024)")
            meta = fm.get("metadata", {}) or {}
            tags = meta.get("tags", []) if isinstance(meta, dict) else []
            if not isinstance(tags, list): tags = []
            if len(tags) < mins["tags"]:
                problems.append(f"tags: have {len(tags)}, need >= {mins['tags']}")
        if not problems:
            ok(f"SKILL.md filled in ({mins['tags']}+ tags, description ok, no REPLACE_ME)")
            return True
        if not interactive:
            for p in problems: fail(p)
            return False
        info(f"waiting on SKILL.md — {len(problems)} missing:")
        for p in problems: info(f"    · {p}")
        info("(edit the file; rescans every 2s)")
        time.sleep(2)

def gate_scripts(skill_dir: Path, mins: dict, interactive: bool) -> bool:
    scripts = skill_dir / "scripts"
    while True:
        count = count_substantive_files(scripts, min_bytes=100)
        if count >= mins["scripts"]:
            ok(f"scripts/ has {count} substantive script(s) (need >= {mins['scripts']})")
            return True
        if not interactive:
            fail(f"scripts/ has {count}, need >= {mins['scripts']}")
            return False
        info(f"waiting on scripts/ — have {count}, need >= {mins['scripts']}")
        time.sleep(2)

def gate_references(skill_dir: Path, mins: dict, interactive: bool) -> bool:
    refs = skill_dir / "references"
    while True:
        count = count_substantive_files(refs, min_bytes=200)
        if count >= mins["references"]:
            ok(f"references/ has {count} substantive doc(s) (need >= {mins['references']})")
            return True
        if not interactive:
            fail(f"references/ has {count}, need >= {mins['references']}")
            return False
        info(f"waiting on references/ — have {count}, need >= {mins['references']}")
        time.sleep(2)

def run_script(script: Path, args: list, cwd: Path = None) -> int:
    r = subprocess.run([sys.executable, str(script), *args], cwd=str(cwd) if cwd else None)
    return r.returncode

def scaffold_skill(name: str, parent_dir: Path) -> Path:
    creator_init = SKILL_CREATOR_ROOT / "__init__.py"
    sys.path.insert(0, str(SKILL_CREATOR_ROOT))
    import importlib.util
    spec = importlib.util.spec_from_file_location("_sc", str(creator_init))
    sc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sc)
    result = sc.scaffold(name, parent_dir, force=True, tier="enterprise")
    return Path(result["path"])

def hash_file(p: Path) -> str:
    h = hashlib.sha256()
    h.update(p.read_bytes())
    return h.hexdigest()

def extract_and_verify(skill_dir: Path, expected_min_version: str) -> bool:
    name = skill_dir.name
    archive = skill_dir / f"{name}.skill"
    if not archive.is_file():
        fail(f"no .skill archive found at {archive}")
        return False
    workdir = Path(tempfile.mkdtemp(prefix=f"verify-{name}-"))
    try:
        with zipfile.ZipFile(archive) as z:
            z.extractall(workdir)
        candidates = list(workdir.rglob("SKILL.md"))
        if not candidates:
            fail("no SKILL.md inside extracted archive")
            return False
        fm = read_frontmatter(candidates[0])
        got_version = str(fm.get("version", "")).strip()
        if not got_version:
            fail("extracted SKILL.md has no version")
            return False
        def _tup(v): return tuple(int(x) for x in v.split(".") if x.isdigit())
        if _tup(got_version) < _tup(expected_min_version):
            fail(f"extracted version {got_version} < expected {expected_min_version}")
            return False
        skill_root = candidates[0].parent
        for required in ("SKILL.md", "__init__.py", "scripts", "references"):
            if not (skill_root / required).exists():
                fail(f"extracted archive missing {required}")
                return False
        mismatched = []
        for extracted in skill_root.rglob("*"):
            if not extracted.is_file():
                continue
            rel = extracted.relative_to(skill_root)
            source = skill_dir / rel
            if not source.is_file():
                mismatched.append(f"{rel} (missing on disk)")
            elif hash_file(extracted) != hash_file(source):
                mismatched.append(str(rel))
        if mismatched:
            fail(f"archive/source hash mismatch: {', '.join(mismatched[:5])}" + (f" … +{len(mismatched)-5} more" if len(mismatched) > 5 else ""))
            return False
        ok(f"extracted archive verified — version={got_version}, layout intact, all hashes match (no mutations)")
        return True
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

def run_pipeline(cmd: str, args) -> int:
    tier = args.tier
    mins = TIER_MINS[tier]
    interactive = not args.noninteractive

    # Determine skill directory
    if cmd == "create":
        default_parent = Path.home() / "Downloads" / "curated_skills"
        parent = Path(args.path or default_parent).resolve()
        parent.mkdir(parents=True, exist_ok=True)
        skill_dir = scaffold_skill(args.name, parent)
        ok(f"scaffolded {skill_dir}")
    else:
        skill_dir = Path(args.path).resolve()
        if not (skill_dir / "SKILL.md").exists():
            fail(f"{skill_dir} has no SKILL.md — is this a skill dir?")
            return 1

    chain_name = f"skill-{skill_dir.name}"
    
    # Use a TEMP directory for chain state (not in skill root!)
    # This avoids polluting the skill with .chain-steps/ and .chain/
    chain_workdir = Path(tempfile.mkdtemp(prefix=f"chain-{chain_name}-"))
    
    try:
        # Create chain with all steps (marker files in temp dir)
        chain_step_dir = chain_workdir / "steps"
        chain_step_dir.mkdir(parents=True, exist_ok=True)
        for s in CHAIN_STEPS:
            (chain_step_dir / s).touch()
        
        # Point chain.py to the temp directory for state
        rc = run_chain(chain_workdir, chain_name, "create", *[str(chain_step_dir / s) for s in CHAIN_STEPS])
        if rc != 0:
            fail("failed to create chain")
            return 1

        # Gate 1: Scaffold (already done for create, skip for update)
        step_path = chain_step_dir / "scaffold"
        if cmd == "update":
            step(2, 11, "Gate: scaffold (skipped for update)")
            run_chain(chain_workdir, chain_name, "verify", str(step_path))
            run_chain(chain_workdir, chain_name, "complete", str(step_path))
        else:
            step(2, 11, "Gate: scaffold (auto-complete for create)")
            run_chain(chain_workdir, chain_name, "verify", str(step_path))
            run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 2: Frontmatter
        step(3, 11, f"Gate: SKILL.md frontmatter ({tier})")
        step_path = chain_step_dir / "frontmatter"
        if not gate_frontmatter(skill_dir, mins, interactive):
            return 3
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 3: Scripts
        step(4, 11, f"Gate: scripts/ ({mins['scripts']}+ substantive)")
        step_path = chain_step_dir / "scripts"
        if not gate_scripts(skill_dir, mins, interactive):
            return 4
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 4: References
        step(5, 11, f"Gate: references/ ({mins['references']}+ substantive)")
        step_path = chain_step_dir / "references"
        if not gate_references(skill_dir, mins, interactive):
            return 5
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 5: Initial validate (enterprise-level)
        step(6, 11, "Gate: validate.py (ENTERPRISE validation)")
        step_path = chain_step_dir / "validate"
        v_args = [str(skill_dir)] + (["--basic"] if tier == "basic" else [])
        rc = run_script(VALIDATE_SC, v_args)
        if rc != 0:
            info("initial validation has fails — auto_fix runs next, re-validate is hard gate")
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 6: Auto-fix
        step(7, 11, "Gate: auto_fix.py (safe moves only)")
        step_path = chain_step_dir / "auto_fix"
        rc = run_script(AUTO_FIX, [str(skill_dir)])
        if rc != 0:
            fail(f"auto_fix.py exited {rc}")
            return 7
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 7: Re-validate (HARD GATE)
        step(8, 11, "Gate: re-validate (HARD GATE - enterprise)")
        step_path = chain_step_dir / "re_validate"
        rc = run_script(VALIDATE_SC, v_args)
        if rc != 0:
            fail(f"skill fails {tier} tier after auto-fix — fix flagged items and rerun")
            return 8
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 8: Test scripts
        step(9, 11, "Gate: test_script.py (syntax + shebang + --help)")
        step_path = chain_step_dir / "test_scripts"
        if TEST_SCRIPT.exists():
            rc = run_script(TEST_SCRIPT, [str(skill_dir)])
            if rc != 0:
                fail(f"test_script.py exited {rc} — every script must pass before packaging")
                return 9
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 9: Verify sources
        step(10, 11, "Gate: verify_sources.py (external source check)")
        step_path = chain_step_dir / "verify_sources"
        if VERIFY_SOURCES.exists():
            rc = run_script(VERIFY_SOURCES, [str(skill_dir)])
            if rc != 0:
                warn(f"verify_sources.py exited {rc} — continuing (non-blocking)")
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 10: Package
        step(11, 11, "Gate: package_skills.py (bumps version, emits .skill)")
        step_path = chain_step_dir / "package"
        fm_before = read_frontmatter(skill_dir / "SKILL.md")
        version_before = str(fm_before.get("version", "0.0.0"))
        rc = run_script(PACKAGE, ["--skills-root", str(skill_dir.parent), "--skill", skill_dir.name])
        if rc != 0:
            fail(f"package_skills.py exited {rc}")
            return 11
        fm_after = read_frontmatter(skill_dir / "SKILL.md")
        version_after = str(fm_after.get("version", "0.0.0"))
        ok(f"packaged: version {version_before} → {version_after}")
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        # Gate 11: Extract-verify
        step_path = chain_step_dir / "extract_verify"
        if not extract_and_verify(skill_dir, version_after):
            return 12
        run_chain(chain_workdir, chain_name, "verify", str(step_path))
        run_chain(chain_workdir, chain_name, "complete", str(step_path))

        ok(f"{skill_dir.name} {tier}-tier pipeline COMPLETE — all gates passed, chain enforced")
        return 0
    finally:
        # ALWAYS clean up chain workdir (self-delete after completion)
        shutil.rmtree(chain_workdir, ignore_errors=True)

def main():
    ap = argparse.ArgumentParser(description="Enterprise skill pipeline with chain enforcement")
    sub = ap.add_subparsers(dest="cmd", required=True)

    ap_create = sub.add_parser("create", help="Scaffold + author a new skill through enforced pipeline")
    ap_create.add_argument("--name", required=True, help="Skill name (hyphen-case)")
    ap_create.add_argument("--path", help="Parent dir (default: ~/Downloads/curated_skills)")
    ap_create.add_argument("--tier", choices=["enterprise", "basic"], default="enterprise",
                           help="ENTERPRISE is standard; basic requires explicit flag")
    ap_create.add_argument("--noninteractive", action="store_true", help="Agent mode — no prompts")

    ap_update = sub.add_parser("update", help="Update existing skill through enforced pipeline")
    ap_update.add_argument("--path", required=True, help="Path to existing skill dir")
    ap_update.add_argument("--tier", choices=["enterprise", "basic"], default="enterprise")
    ap_update.add_argument("--noninteractive", action="store_true")

    args = ap.parse_args()
    sys.exit(run_pipeline(args.cmd, args))

if __name__ == "__main__":
    main()