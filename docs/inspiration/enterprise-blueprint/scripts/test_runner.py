#!/usr/bin/env python3
"""
test_runner.py — Runs REAL test suites, not syntax checks.
Forever System §7: Verifiable without reading code. CI badge = truth.

Detects project type and runs native test suite:
- Python: pytest
- Rust: cargo test
- Node: npm test
- Go: go test ./...
- etc.

Returns exit code 0 = pass, non-zero = fail. CI consumes this.
"""

import json
import os
import sys
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class TestRunner:
    """Detects project type and runs appropriate test suite."""

    def __init__(self, project_dir: Path):
        self.project_dir = Path(project_dir).resolve()
        self.results = []

    def detect_project_type(self) -> List[str]:
        """Detect all project types present. Returns list of detected types."""
        types = []

        # Python
        if (self.project_dir / "pyproject.toml").exists() or \
           (self.project_dir / "setup.py").exists() or \
           (self.project_dir / "requirements.txt").exists() or \
           list(self.project_dir.glob("*.py")):
            types.append("python")

        # Rust
        if (self.project_dir / "Cargo.toml").exists():
            types.append("rust")

        # Node.js
        if (self.project_dir / "package.json").exists():
            types.append("node")

        # Go
        if (self.project_dir / "go.mod").exists():
            types.append("go")

        # Java/Maven
        if (self.project_dir / "pom.xml").exists():
            types.append("java")

        # Java/Gradle
        if (self.project_dir / "build.gradle").exists() or \
           (self.project_dir / "build.gradle.kts").exists():
            types.append("java-gradle")

        # .NET
        if list(self.project_dir.glob("*.csproj")) or \
           list(self.project_dir.glob("*.sln")):
            types.append("dotnet")

        # Makefile
        if (self.project_dir / "Makefile").exists() or \
           (self.project_dir / "makefile").exists():
            types.append("make")

        return types

    def run_python_tests(self, args: List[str] = None) -> Tuple[int, str]:
        """Run pytest with sensible defaults."""
        cmd = ["pytest", "-x", "-v", "--tb=short"]
        if args:
            cmd.extend(args)
        else:
            # Default: run all tests, fail fast, show traceback on failure
            pass
        return self._run_cmd(cmd)

    def run_rust_tests(self, args: List[str] = None) -> Tuple[int, str]:
        """Run cargo test."""
        cmd = ["cargo", "test"]
        if args:
            cmd.extend(["--", *args])
        return self._run_cmd(cmd)

    def run_node_tests(self, args: List[str] = None) -> Tuple[int, str]:
        """Run npm test."""
        cmd = ["npm", "test"]
        if args:
            cmd.extend(["--", *args])
        return self._run_cmd(cmd)

    def run_go_tests(self, args: List[str] = None) -> Tuple[int, str]:
        """Run go test."""
        cmd = ["go", "test", "./..."]
        if args:
            cmd.extend(args)
        return self._run_cmd(cmd)

    def run_java_maven_tests(self, args: List[str] = None) -> Tuple[int, str]:
        """Run mvn test."""
        cmd = ["mvn", "test"]
        if args:
            cmd.extend(args)
        return self._run_cmd(cmd)

    def run_java_gradle_tests(self, args: List[str] = None) -> Tuple[int, str]:
        """Run gradle test."""
        gradle = "./gradlew" if (self.project_dir / "gradlew").exists() else "gradle"
        cmd = [gradle, "test"]
        if args:
            cmd.extend(args)
        return self._run_cmd(cmd)

    def run_dotnet_tests(self, args: List[str] = None) -> Tuple[int, str]:
        """Run dotnet test."""
        cmd = ["dotnet", "test"]
        if args:
            cmd.extend(args)
        return self._run_cmd(cmd)

    def run_make_tests(self, args: List[str] = None) -> Tuple[int, str]:
        """Run make test."""
        cmd = ["make", "test"]
        if args:
            cmd.extend(args)
        return self._run_cmd(cmd)

    def _run_cmd(self, cmd: List[str]) -> Tuple[int, str]:
        """Run command and return (exit_code, output)."""
        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.project_dir),
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )
            output = result.stdout + result.stderr
            return result.returncode, output
        except subprocess.TimeoutExpired:
            return -1, "TIMEOUT: Test suite exceeded 5 minutes"
        except FileNotFoundError as e:
            return -1, f"COMMAND NOT FOUND: {e.filename}"

    def run_all(self, args: List[str] = None) -> Dict:
        """Run all detected test suites. Returns aggregated results."""
        types = self.detect_project_type()

        if not types:
            return {
                "success": False,
                "error": "No recognized project type detected",
                "project_dir": str(self.project_dir),
                "types_detected": [],
                "results": []
            }

        all_passed = True
        all_results = []

        for ptype in types:
            if ptype == "python":
                code, output = self.run_python_tests(args)
            elif ptype == "rust":
                code, output = self.run_rust_tests(args)
            elif ptype == "node":
                code, output = self.run_node_tests(args)
            elif ptype == "go":
                code, output = self.run_go_tests(args)
            elif ptype == "java":
                code, output = self.run_java_maven_tests(args)
            elif ptype == "java-gradle":
                code, output = self.run_java_gradle_tests(args)
            elif ptype == "dotnet":
                code, output = self.run_dotnet_tests(args)
            elif ptype == "make":
                code, output = self.run_make_tests(args)
            else:
                code, output = -1, f"Unknown type: {ptype}"

            passed = code == 0
            all_passed = all_passed and passed

            all_results.append({
                "type": ptype,
                "passed": passed,
                "exit_code": code,
                "output": output[-5000:] if len(output) > 5000 else output  # Truncate long output
            })

        return {
            "success": all_passed,
            "project_dir": str(self.project_dir),
            "types_detected": types,
            "results": all_results
        }


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Run REAL test suites for detected project type(s)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run all tests in current directory
  python test_runner.py .

  # Run with extra args passed to test runner
  python test_runner.py . -- -k "not slow"

  # JSON output for CI
  python test_runner.py . --json

  # Only run specific type
  python test_runner.py . --type python -- -v

Exit codes:
  0 = all test suites passed
  1 = one or more test suites failed
  2 = error (no project type detected, command not found, etc.)
"""
    )
    parser.add_argument("path", nargs="?", default=".", help="Project directory")
    parser.add_argument("--json", action="store_true", help="Output JSON for CI")
    parser.add_argument("--type", choices=["python", "rust", "node", "go", "java", "java-gradle", "dotnet", "make"],
                        help="Force specific project type (skip detection)")
    parser.add_argument("--no-detect", action="store_true", help="Skip auto-detection, use --type only")
    parser.add_argument("extra_args", nargs=argparse.REMAINDER, help="Extra args passed to test runner")

    args = parser.parse_args()

    project_dir = Path(args.path).resolve()

    if not project_dir.exists():
        result = {"success": False, "error": f"Path not found: {project_dir}"}
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print(f"ERROR: {result['error']}", file=sys.stderr)
        sys.exit(2)

    runner = TestRunner(project_dir)

    if args.type and args.no_detect:
        # Force single type
        types = [args.type]
    else:
        types = runner.detect_project_type()
        if args.type:
            types = [args.type] + [t for t in types if t != args.type]

    if not types:
        result = {
            "success": False,
            "error": "No recognized project type detected",
            "project_dir": str(project_dir),
            "types_detected": [],
            "results": []
        }
    else:
        all_passed = True
        all_results = []

        for ptype in types:
            if ptype == "python":
                code, output = runner.run_python_tests(args.extra_args)
            elif ptype == "rust":
                code, output = runner.run_rust_tests(args.extra_args)
            elif ptype == "node":
                code, output = runner.run_node_tests(args.extra_args)
            elif ptype == "go":
                code, output = runner.run_go_tests(args.extra_args)
            elif ptype == "java":
                code, output = runner.run_java_maven_tests(args.extra_args)
            elif ptype == "java-gradle":
                code, output = runner.run_java_gradle_tests(args.extra_args)
            elif ptype == "dotnet":
                code, output = runner.run_dotnet_tests(args.extra_args)
            elif ptype == "make":
                code, output = runner.run_make_tests(args.extra_args)
            else:
                code, output = -1, f"Unknown type: {ptype}"

            passed = code == 0
            all_passed = all_passed and passed

            all_results.append({
                "type": ptype,
                "passed": passed,
                "exit_code": code,
                "output": output[-5000:] if len(output) > 5000 else output
            })

        result = {
            "success": all_passed,
            "project_dir": str(project_dir),
            "types_detected": types,
            "results": all_results
        }

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        # Human output
        if result["success"]:
            print(f"✓ ALL TESTS PASSED ({len(result['results'])} suite(s))")
            for r in result["results"]:
                print(f"  ✓ {r['type']}")
        else:
            print(f"✗ TESTS FAILED")
            for r in result["results"]:
                status = "✓" if r["passed"] else "✗"
                print(f"  {status} {r['type']} (exit {r['exit_code']})")
                if not r["passed"] and r["output"]:
                    print(f"    Output: {r['output'][:200]}...")

    sys.exit(0 if result["success"] else 1)


if __name__ == "__main__":
    main()