#!/usr/bin/env python3
"""
validate.py — Unified configurable enforcing validator for loop-enforcer chains.

ALL CHECKS ARE AVAILABLE ALWAYS. Enable/disable per-check via flags or spec file.

Usage:
    python3 validate.py <path> [options...]

Flags (can combine freely):
    --min-lines N        Minimum line count (default: 10)
    --min-chars N        Minimum character count (default: 100)
    --require "pat"      Required pattern (can repeat)
    --forbid "pat"       Forbidden pattern (can repeat)
    --no-placeholders    Disable placeholder check (default: enabled)
    --syntax node|python|json|auto|off  Syntax checker (default: auto)
    --spec file.json     Load all config from JSON spec

Spec file (JSON):
{
  "min_lines": 50,
  "min_chars": 500,
  "no_placeholders": true,
  "required_patterns": ["class ", "export ", "async "],
  "forbidden_patterns": ["TODO", "FIXME", "console.log", "debugger"],
  "syntax_check": "node",
  "custom_checks": [
    {"type": "regex", "pattern": "class\\s+\\w+", "message": "Must contain class"},
    {"type": "function_count", "min": 3, "message": "Need 3+ functions"},
    {"type": "class_count", "min": 1, "message": "Need at least 1 class"},
    {"type": "export_count", "min": 2, "message": "Need 2+ exports"}
  ]
}

Exit 0 = pass, non-zero = fail with descriptive error.
"""
import sys, os, re, json, subprocess

def load_spec(path):
    with open(path) as f:
        return json.load(f)

def check_basic(path):
    if not os.path.exists(path):
        return False, f"File does not exist: {path}"
    if not os.path.isfile(path):
        return False, f"Not a file: {path}"
    size = os.path.getsize(path)
    if size == 0:
        return False, f"File is empty: {path}"
    return True, f"{size} bytes"

def check_structure(path, content, spec):
    lines = content.splitlines()
    chars = len(content)

    min_lines = spec.get("min_lines", 10)
    if len(lines) < min_lines:
        return False, f"Too few lines: {len(lines)} < {min_lines}"

    min_chars = spec.get("min_chars", 100)
    if chars < min_chars:
        return False, f"Too few chars: {chars} < {min_chars}"

    if spec.get("no_placeholders", True):
        ph = re.findall(r'\[placeholder\]|\[Define\s|\[Describe\s|\[Insert\s|TODO|FIXME|XXX|HACK', content, re.IGNORECASE)
        if ph:
            return False, f"Placeholders/TODOs: {ph[:5]}"

    return True, f"{len(lines)} lines, {chars} chars"

def check_patterns(content, spec):
    required = spec.get("required_patterns", [])
    for p in required:
        if p not in content:
            return False, f"Missing required: {p}"

    forbidden = spec.get("forbidden_patterns", [])
    for p in forbidden:
        if p in content:
            return False, f"Forbidden found: {p}"

    return True, f"Patterns OK ({len(required)} required, {len(forbidden)} forbidden)"

def check_custom(content, spec):
    for check in spec.get("custom_checks", []):
        ctype = check.get("type")
        msg = check.get("message", "Custom check failed")

        if ctype == "regex":
            if not re.search(check.get("pattern", ""), content):
                return False, f"{msg}: '{check.get('pattern')}' not found"
        elif ctype == "function_count":
                    # Count function definitions (JS/Python) including methods, arrow functions
                    funcs = re.findall(
                        r'\bfunction\s+\w+|'
                        r'\bdef\s+\w+|'
                        r'(?:const|let|var)\s+\w+\s*=\s*(?:async\s*)?\(|'
                        r'(?:async\s+)?function\s+\w+|'
                        r'\b\w+\s*:\s*(?:async\s*)?\(|'  # method: name() {}
                        r'\b\w+\s*\([^)]*\)\s*\{',      # method shorthand
                        content
                    )
                    if len(funcs) < check.get("min", 1):
                        return False, f"{msg}: {len(funcs)}/{check.get('min')}"

        elif ctype == "class_count":
            classes = re.findall(r'\bclass\s+\w+', content)
            if len(classes) < check.get("min", 1):
                return False, f"{msg}: {len(classes)}/{check.get('min')}"

        elif ctype == "export_count":
            exports = re.findall(r'\bexport\s+(?:default\s+)?(?:const|function|class|let|var)\s+\w+', content)
            if len(exports) < check.get("min", 1):
                return False, f"{msg}: {len(exports)}/{check.get('min')}"

    return True, "Custom checks passed"

def check_syntax(path, syntax):
    if syntax in ("off", "none", ""):
        return True, "Syntax check disabled"

    if syntax == "auto":
        ext = os.path.splitext(path)[1]
        if ext in (".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"):
            syntax = "node"
        elif ext in (".py",):
            syntax = "python"
        elif ext in (".json",):
            syntax = "json"
        else:
            return True, f"Syntax skipped (unknown ext: {ext})"

    # Resolve commands from env vars with sensible defaults
    cmd_map = {
        "node": os.environ.get("VALIDATE_NODE", "node"),
        "python": os.environ.get("VALIDATE_PYTHON", sys.executable),
        "json": os.environ.get("VALIDATE_JSON", "python3"),
    }
    cmd = cmd_map.get(syntax)
    if not cmd:
        return True, f"Unknown syntax: {syntax}"

    args = {"node": ["--check"], "python": ["-m", "py_compile"], "json": ["-m", "json.tool"]}.get(syntax, [])
    try:
        result = subprocess.run([cmd, *args, path], capture_output=True, text=True, timeout=15)
        if result.returncode != 0:
            return False, f"Syntax error: {result.stderr.strip()[:300]}"
    except subprocess.TimeoutExpired:
        return False, "Syntax check timed out"
    except FileNotFoundError:
        return False, f"Checker not found: {cmd}"

    return True, f"Syntax OK ({syntax})"

def parse_args():
    """Parse CLI into a spec dict."""
    spec = {
        "min_lines": 10,
        "min_chars": 100,
        "no_placeholders": True,
        "required_patterns": [],
        "forbidden_patterns": [],
        "syntax_check": "auto",
        "custom_checks": [],
    }

    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    path = sys.argv[1]

    # --spec loads everything
    if "--spec" in sys.argv:
        idx = sys.argv.index("--spec")
        spec.update(load_spec(sys.argv[idx + 1]))
        return path, spec

    # Flags override/add to defaults
    i = 2
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == "--min-lines":
            spec["min_lines"] = int(sys.argv[i + 1])
            i += 2
        elif arg == "--min-chars":
            spec["min_chars"] = int(sys.argv[i + 1])
            i += 2
        elif arg == "--require":
            spec["required_patterns"].append(sys.argv[i + 1])
            i += 2
        elif arg == "--forbid":
            spec["forbidden_patterns"].append(sys.argv[i + 1])
            i += 2
        elif arg == "--no-placeholders":
            spec["no_placeholders"] = False
            i += 1
        elif arg == "--syntax":
            spec["syntax_check"] = sys.argv[i + 1]
            i += 2
        elif arg == "--custom-regex":
            spec["custom_checks"].append({
                "type": "regex",
                "pattern": sys.argv[i + 1],
                "message": sys.argv[i + 2] if i + 2 < len(sys.argv) and not sys.argv[i + 2].startswith("--") else "Regex check failed"
            })
            i += 2 if i + 2 >= len(sys.argv) or sys.argv[i + 2].startswith("--") else 3
        elif arg == "--custom-funcs":
            spec["custom_checks"].append({
                "type": "function_count",
                "min": int(sys.argv[i + 1]),
                "message": f"Need {sys.argv[i + 1]}+ functions"
            })
            i += 2
        else:
            i += 1

    return path, spec

def main():
    if "--dry-run" in sys.argv:
        print("[DRY RUN] Validation checks only, no external calls")
        sys.argv.remove("--dry-run")

    path, spec = parse_args()

    ok, msg = check_basic(path)
    if not ok:
        print(msg)
        sys.exit(1)

    with open(path) as f:
        content = f.read()

    ok, msg = check_structure(path, content, spec)
    if not ok:
        print(msg)
        sys.exit(1)

    ok, msg = check_patterns(content, spec)
    if not ok:
        print(msg)
        sys.exit(1)

    ok, msg = check_custom(content, spec)
    if not ok:
        print(msg)
        sys.exit(1)

    ok, msg = check_syntax(path, spec.get("syntax_check", "auto"))
    if not ok:
        print(msg)
        sys.exit(1)

    print(f"OK: {path} ({msg})")
    sys.exit(0)

if __name__ == "__main__":
    main()