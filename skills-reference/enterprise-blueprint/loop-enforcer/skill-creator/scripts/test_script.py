#!/usr/bin/env python3
"""
Script functionality testing — syntax, shebang, docstring, help-surface, and
dry-run capability checks for every script in a skill's scripts/ directory.

Safety contract:
  - NEVER executes a script bare (a mutating script run with no args could
    change real state). Execution is limited to `--help`, in an isolated
    temporary working directory, with a timeout.
  - Checks syntax per language: py_compile for .py, `bash -n` for .sh.
  - Reports (as a warning, not a failure) scripts that expose no --dry-run
    flag, per the project rule that every mutating script should support one.

Usage:
    python3 test_script.py <skill_dir_or_scripts_dir> [--json] [--dry-run]
"""
import argparse
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Tuple

RUN_TIMEOUT = 30
TESTABLE_EXTS = {".py", ".sh", ".bat", ".ps1", ".js", ".mjs", ".cjs", ".ts"}


def check_syntax(script_path: Path) -> Tuple[bool, List[str]]:
    """Language-appropriate syntax check."""
    issues = []
    ext = script_path.suffix.lower()
    if ext == ".py":
        # builtin compile() checks syntax WITHOUT writing a __pycache__
        # bytecode file into the skill tree (py_compile does, and the
        # validator rightly flags that as a junk dir)
        try:
            source = script_path.read_text(encoding="utf-8", errors="replace")
            compile(source, str(script_path), "exec")
        except SyntaxError as e:
            issues.append(f"Syntax error: line {e.lineno}: {e.msg}")
        except Exception as e:
            issues.append(f"Syntax check failed: {e}")
    elif ext == ".sh":
        try:
            r = subprocess.run(["bash", "-n", str(script_path)],
                               capture_output=True, text=True, timeout=RUN_TIMEOUT)
            if r.returncode != 0:
                issues.append(f"Syntax error: {r.stderr.strip()[:200]}")
        except FileNotFoundError:
            pass  # no bash on this platform — skip, don't fail
        except subprocess.TimeoutExpired:
            issues.append("bash -n timed out")
    # Other extensions: no reliable local syntax checker — structural checks only
    return len(issues) == 0, issues


def check_shebang(script_path: Path) -> Tuple[bool, List[str]]:
    issues = []
    if script_path.suffix.lower() in {".bat", ".ps1", ".exe"}:
        return True, []  # Windows formats don't use shebangs
    try:
        first_line = script_path.read_text(
            encoding="utf-8", errors="replace").splitlines()[0].strip()
    except (OSError, IndexError):
        return False, ["Empty file or unreadable"]
    if not first_line.startswith("#!"):
        issues.append("Missing shebang")
    elif not any(k in first_line for k in ("python", "bash", "sh", "node", "env")):
        issues.append(f"Unrecognized shebang: {first_line}")
    return len(issues) == 0, issues


def check_docstring(script_path: Path) -> Tuple[bool, List[str]]:
    """Python: module docstring. Shell: leading comment block."""
    issues = []
    ext = script_path.suffix.lower()
    try:
        text = script_path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        return False, [f"Unreadable: {e}"]
    if ext == ".py":
        try:
            import ast
            doc = ast.get_docstring(ast.parse(text))
            if not doc:
                issues.append("Missing module-level docstring")
            elif len(doc.strip()) < 20:
                issues.append("Docstring too short (< 20 chars)")
        except SyntaxError:
            pass  # syntax check reports this
    elif ext == ".sh":
        lines = text.splitlines()[1:6]
        if not any(l.strip().startswith("#") and len(l.strip()) > 3 for l in lines):
            issues.append("No header comment describing the script's purpose")
    return len(issues) == 0, issues


def check_dry_run_support(script_path: Path) -> bool:
    """Does the script expose a --dry-run flag (project convention)?"""
    try:
        text = script_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return bool(re.search(r"--dry[-_]run|DRY_RUN", text))


def run_help(script_path: Path) -> Tuple[bool, List[str], str]:
    """Invoke `<script> --help` in an isolated temp cwd. Never runs bare."""
    script_path = script_path.resolve()  # cwd is a temp dir — path must be absolute
    ext = script_path.suffix.lower()
    if ext == ".py":
        cmd = [sys.executable, str(script_path), "--help"]
    elif ext == ".sh":
        cmd = ["bash", str(script_path), "--help"]
    else:
        return True, [], ""  # no safe generic runner — skip execution
    issues = []
    output = ""
    with tempfile.TemporaryDirectory(prefix="skilltest-") as tmp:
        try:
            r = subprocess.run(cmd, capture_output=True, text=True,
                               timeout=RUN_TIMEOUT, cwd=tmp)
            output = (r.stdout + r.stderr).strip()
            # Accept rc 0, or a nonzero rc that still printed usage text
            # (argparse exits 2 for unknown flag but proves the script loads)
            if r.returncode != 0 and not re.search(r"usage|help|options",
                                                   output, re.I):
                issues.append(
                    f"--help exited {r.returncode} with no usage text: "
                    f"{output[:200]}"
                )
        except subprocess.TimeoutExpired:
            issues.append(f"--help timed out after {RUN_TIMEOUT}s")
        except FileNotFoundError as e:
            issues.append(f"Interpreter unavailable: {e}")
        except Exception as e:
            issues.append(f"Execution failed: {e}")
    return len(issues) == 0, issues, output


def test_script(script_path: Path) -> Dict:
    all_issues, warnings = [], []

    ok, issues = check_syntax(script_path)
    if not ok:
        all_issues.extend(f"Syntax: {i}" for i in issues)

    ok, issues = check_shebang(script_path)
    if not ok:
        all_issues.extend(f"Shebang: {i}" for i in issues)

    ok, issues = check_docstring(script_path)
    if not ok:
        all_issues.extend(f"Docstring: {i}" for i in issues)

    ok, issues, output = run_help(script_path)
    if not ok:
        all_issues.extend(f"Runtime: {i}" for i in issues)

    if not check_dry_run_support(script_path):
        warnings.append("No --dry-run flag detected (project convention "
                        "for mutating scripts)")

    return {
        "script": script_path.name,
        "passed": len(all_issues) == 0,
        "issues": all_issues,
        "warnings": warnings,
        "help_output": output[:300],
    }


def main():
    ap = argparse.ArgumentParser(
        description="Test every script in a skill (syntax/shebang/docstring/"
                    "--help; never executes bare)")
    ap.add_argument("target", help="Skill dir or scripts/ dir")
    ap.add_argument("--json", action="store_true", help="JSON output")
    ap.add_argument("--dry-run", action="store_true",
                    help="List what would be tested without running anything")
    args = ap.parse_args()

    target = Path(args.target)
    if not target.exists():
        print(f"Error: {target} does not exist", file=sys.stderr)
        sys.exit(1)
    scripts_dir = target / "scripts" if (target / "scripts").is_dir() else target

    scripts = sorted(
        s for s in scripts_dir.rglob("*")
        if s.is_file() and s.suffix.lower() in TESTABLE_EXTS
        and "__pycache__" not in s.parts
    )
    if not scripts:
        print(f"No scripts found in {scripts_dir}")
        sys.exit(0)

    if args.dry_run:
        print(f"[dry-run] would test {len(scripts)} script(s):")
        for s in scripts:
            print(f"  • {s.relative_to(scripts_dir)}")
        sys.exit(0)

    results = [test_script(s) for s in scripts]
    passed = sum(1 for r in results if r["passed"])

    if args.json:
        print(json.dumps({
            "operation": "test_scripts",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "scripts_tested": len(scripts),
            "passed": passed,
            "failed": len(scripts) - passed,
            "results": results,
        }, indent=2))
    else:
        for r in results:
            print(f"  {'✓' if r['passed'] else '✗'} {r['script']}")
            for issue in r["issues"]:
                print(f"    - {issue}")
            for w in r["warnings"]:
                print(f"    ⚠ {w}")
        print(f"\nResults: {passed}/{len(results)} scripts passed")

    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
