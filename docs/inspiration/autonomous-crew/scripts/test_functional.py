#!/usr/bin/env python3
"""
Functional Test Runner for Skill Scripts
Runs actual functional tests with expected outputs, not just syntax checks.
Supports per-script test specs with input/expected-output validation.
"""

import argparse
import json
import subprocess
import sys
import tempfile
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Any, Optional
import re

TEST_TIMEOUT = 60

class FunctionalTestRunner:
    def __init__(self, scripts_dir: Path, test_specs_dir: Path = None):
        self.scripts_dir = scripts_dir.resolve()
        self.test_specs_dir = (test_specs_dir or scripts_dir.parent / "references" / "test-specs").resolve()
        self.results = []
    
    def load_test_spec(self, script_name: str) -> Optional[Dict]:
        """Load test spec for a script. Looks for <script_name>.test.json or <script_name>.test.yaml"""
        for ext in [".test.json", ".test.yaml", ".test.yml"]:
            spec_path = self.test_specs_dir / f"{script_name}{ext}"
            if spec_path.exists():
                if ext == ".test.json":
                    return json.loads(spec_path.read_text())
                else:
                    import yaml
                    return yaml.safe_load(spec_path.read_text())
        return None
    
    def run_script(self, script_path: Path, args: List[str], stdin: str = "", 
                   cwd: Path = None, env: Dict = None) -> Dict[str, Any]:
        """Run a script and capture output."""
        script_path = script_path.resolve()
        cwd = cwd or tempfile.mkdtemp(prefix="functest-")
        
        ext = script_path.suffix.lower()
        if ext == ".py":
            cmd = [sys.executable, str(script_path)] + args
        elif ext == ".sh":
            cmd = ["bash", str(script_path)] + args
        else:
            return {"success": False, "error": f"No runner for {ext}", "stdout": "", "stderr": ""}
        
        test_env = {**os.environ, **(env or {})}
        
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, 
                timeout=TEST_TIMEOUT, cwd=cwd, env=test_env, input=stdin
            )
            return {
                "success": result.returncode == 0,
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr
            }
        except subprocess.TimeoutExpired:
            return {"success": False, "error": f"Timed out after {TEST_TIMEOUT}s", "stdout": "", "stderr": ""}
        except Exception as e:
            return {"success": False, "error": str(e), "stdout": "", "stderr": ""}
    
    def validate_output(self, actual: Dict, expected: Dict) -> List[str]:
        """Validate actual output against expected criteria. Returns list of failures."""
        failures = []
        
        # Check return code
        if "returncode" in expected and actual.get("returncode") != expected["returncode"]:
            failures.append(f"Return code: expected {expected['returncode']}, got {actual.get('returncode')}")
        
        # Check stdout contains
        if "stdout_contains" in expected:
            for substring in expected["stdout_contains"]:
                if substring not in actual.get("stdout", ""):
                    failures.append(f"stdout missing expected substring: {substring}")
        
        # Check stdout regex
        if "stdout_matches" in expected:
            for pattern in expected["stdout_matches"]:
                if not re.search(pattern, actual.get("stdout", "")):
                    failures.append(f"stdout doesn't match pattern: {pattern}")
        
        # Check stdout exact
        if "stdout_exact" in expected:
            if actual.get("stdout", "").strip() != expected["stdout_exact"].strip():
                failures.append(f"stdout exact mismatch:\n  expected: {expected['stdout_exact'][:100]}\n  actual:   {actual.get('stdout', '')[:100]}")
        
        # Check stderr contains
        if "stderr_contains" in expected:
            for substring in expected["stderr_contains"]:
                if substring not in actual.get("stderr", ""):
                    failures.append(f"stderr missing expected substring: {substring}")
        
        # Check stderr empty (clean run)
        if expected.get("stderr_empty") and actual.get("stderr", "").strip():
            failures.append(f"stderr should be empty but got: {actual['stderr'][:200]}")
        
        # Check JSON output structure
        if "json_output" in expected:
            try:
                parsed = json.loads(actual.get("stdout", "{}"))
                for key, val in expected["json_output"].items():
                    if key not in parsed:
                        failures.append(f"JSON output missing key: {key}")
                    elif parsed[key] != val:
                        failures.append(f"JSON output[{key}]: expected {val}, got {parsed[key]}")
            except json.JSONDecodeError:
                failures.append("stdout is not valid JSON")
        
        # Custom validator function name (for complex checks)
        if "custom_validator" in expected:
            validator_name = expected["custom_validator"]
            # Could import and run a validator function here
            pass
        
        return failures
    
    def test_script(self, script_path: Path) -> Dict:
        """Run all tests for a single script."""
        script_name = script_path.stem
        spec = self.load_test_spec(script_name)
        
        if not spec:
            return {
                "script": script_path.name,
                "passed": False,
                "issues": ["No test spec found (.test.json/.test.yaml)"],
                "warnings": ["Create test spec in tests/ directory"]
            }
        
        all_failures = []
        test_results = []
        
        for i, test_case in enumerate(spec.get("tests", [])):
            args = test_case.get("args", [])
            stdin = test_case.get("stdin", "")
            expected = test_case.get("expect", {})
            description = test_case.get("description", f"Test {i+1}")
            
            # Run script
            result = self.run_script(script_path, args, stdin=stdin)
            
            # Validate
            failures = self.validate_output(result, expected)
            
            test_results.append({
                "description": description,
                "passed": len(failures) == 0,
                "failures": failures,
                "actual_returncode": result.get("returncode"),
                "actual_stdout": result.get("stdout", "")[:500],
                "actual_stderr": result.get("stderr", "")[:500]
            })
            
            all_failures.extend(failures)
        
        # Also run basic checks
        basic_issues = []
        
        # Syntax check
        if script_path.suffix == ".py":
            try:
                compile(script_path.read_text(), str(script_path), "exec")
            except SyntaxError as e:
                basic_issues.append(f"Syntax error: line {e.lineno}: {e.msg}")
        elif script_path.suffix == ".sh":
            r = subprocess.run(["bash", "-n", str(script_path)], capture_output=True, text=True)
            if r.returncode != 0:
                basic_issues.append(f"Syntax error: {r.stderr.strip()[:200]}")
        
        # Shebang check
        first_line = script_path.read_text().splitlines()[0].strip()
        if not first_line.startswith("#!"):
            basic_issues.append("Missing shebang")
        
        # Docstring check
        if script_path.suffix == ".py":
            import ast
            doc = ast.get_docstring(ast.parse(script_path.read_text()))
            if not doc or len(doc.strip()) < 20:
                basic_issues.append("Missing or too-short module docstring")
        
        all_failures.extend(basic_issues)
        
        return {
            "script": script_path.name,
            "passed": len(all_failures) == 0,
            "issues": all_failures,
            "test_results": test_results,
            "warnings": []
        }
    
    def run_all(self) -> Dict:
        """Run tests for all scripts."""
        scripts = sorted(
            s for s in self.scripts_dir.rglob("*")
            if s.is_file() and s.suffix.lower() in {".py", ".sh"}
            and "__pycache__" not in s.parts
        )
        
        if not scripts:
            return {"scripts_tested": 0, "passed": 0, "failed": 0, "results": []}
        
        for script in scripts:
            self.results.append(self.test_script(script))
        
        passed = sum(1 for r in self.results if r["passed"])
        return {
            "operation": "functional_test_scripts",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "scripts_tested": len(scripts),
            "passed": passed,
            "failed": len(scripts) - passed,
            "results": self.results
        }


def main():
    ap = argparse.ArgumentParser(description="Functional test runner for skill scripts")
    ap.add_argument("scripts_dir", help="Path to scripts/ directory or skill root")
    ap.add_argument("--test-specs", help="Path to test specs directory (default: scripts/tests/)")
    ap.add_argument("--json", action="store_true", help="JSON output")
    ap.add_argument("--script", help="Test only a specific script")
    args = ap.parse_args()
    
    scripts_dir = Path(args.scripts_dir)
    # Auto-detect scripts subdirectory
    if (scripts_dir / "scripts").is_dir():
        scripts_dir = scripts_dir / "scripts"
    test_specs_dir = Path(args.test_specs) if args.test_specs else scripts_dir.parent / "references" / "test-specs"
    
    runner = FunctionalTestRunner(scripts_dir, test_specs_dir)
    
    if args.script:
        script_path = scripts_dir / args.script
        if not script_path.exists():
            print(f"Script not found: {script_path}", file=sys.stderr)
            sys.exit(1)
        result = runner.test_script(script_path)
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print(f"{'✓' if result['passed'] else '✗'} {result['script']}")
            for issue in result["issues"]:
                print(f"  - {issue}")
            for tr in result.get("test_results", []):
                print(f"  {'✓' if tr['passed'] else '✗'} {tr['description']}")
                for f in tr["failures"]:
                    print(f"    - {f}")
        sys.exit(0 if result["passed"] else 1)
    
    result = runner.run_all()
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        for r in result["results"]:
            print(f"{'✓' if r['passed'] else '✗'} {r['script']}")
            for issue in r["issues"]:
                print(f"  - {issue}")
            for tr in r.get("test_results", []):
                print(f"  {'✓' if tr['passed'] else '✗'} {tr['description']}")
                for f in tr["failures"]:
                    print(f"    - {f}")
        print(f"\nResults: {result['passed']}/{result['scripts_tested']} scripts passed")
    
    sys.exit(0 if result["failed"] == 0 else 1)


if __name__ == "__main__":
    import os
    main()