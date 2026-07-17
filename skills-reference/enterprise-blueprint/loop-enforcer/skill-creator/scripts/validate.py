#!/usr/bin/env python3
"""
Unified Enterprise Skill Validator

Defaults to ENTERPRISE mode (strict validation).
Use --basic flag for lighter validation (production tier).

Checks:
- Frontmatter format and required fields
- Directory structure (scripts/, references/, lessons/, assets/)
- Script minimum: 3 (enterprise), 2 (basic)
- Reference minimum: 5 (enterprise), 3 (basic)
- Lessons/ directory required (enterprise only)
- Body length ≤500 lines (content.split("---", 2)[-1])
- Cross-references: all files linked in SKILL.md
- Placeholder detection (TODO, FIXME, TBD, WIP)
- Hardcoded path detection
- External source verification (web search)
- Script functionality testing (syntax + manual run)
"""

import os
import re
import sys
import json
import subprocess
from pathlib import Path
from typing import Optional, Dict, List, Tuple

# Toolchain scripts import each other as siblings — never litter the skill
# with __pycache__ (a forbidden dir the validator itself would then flag).
sys.dont_write_bytecode = True

try:
    import yaml
except ModuleNotFoundError:
    yaml = None

# Shared skill-root discovery (nested SKILL.md detection)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from skill_root import nested_skill_mds
except ImportError:
    nested_skill_mds = None

# Constants
MAX_SKILL_NAME_LENGTH = 64
MAX_DESCRIPTION_LENGTH = 1024
MIN_DESCRIPTION_LENGTH = 100
ALLOWED_PROPERTIES = {'name', 'description', 'license', 'metadata', 'allowed-tools', 'version'}

PLACEHOLDER_PATTERNS = [
    (r'(?:^|(?<=\s))(?<!`)TODO(?!\w)(?!.*\btodo\b)(?!\s*,)(?!\s+list)', 'TODO marker'),
    (r'\bFIXME\b', 'FIXME marker'),
    (r'(?<!\| )TBD(?!\w)(?! \|)', 'TBD marker'),
    (r'\bWIP\b', 'Work in progress marker'),
    (r'\bcoming\s+soon\b', 'Coming soon placeholder'),
    (r'\binsert\s+(here|text|data|info)\b', 'Insert placeholder'),
    (r'\breplace\s+(this|here)\b', 'Replace placeholder'),
    (r'\byour\s+(name|email|token|key|id)\b', 'Your-<something> placeholder'),
    (r'\blorem\s+ipsum\b', 'Lorem ipsum filler'),
    (r'\b\[YOUR_', 'Template variable placeholder'),
    (r'(?<!\{\})\{\{(?!\{).*?\}\}(?!\})', 'Mustache template variable'),
    (r'<!--\s*(placeholder|todo|fixme)\s*-->', 'HTML comment placeholder'),
    (r'\bNOTE:\s*$', 'Empty NOTE marker'),
]

HARDCODED_PATTERNS = [
    (r'/home/\w+/', 'Hardcoded home directory'),
    (r'/root/', 'Hardcoded root directory'),
    (r'/opt/\w+/', 'Hardcoded /opt path'),
    (r'~/.openclaw/', 'Hardcoded OpenClaw path'),
    (r'~/.hermes/', 'Hardcoded Hermes path'),
    (r'~/.config/opencode/', 'Hardcoded OpenCode path'),
    (r'/tmp/\w+/', 'Hardcoded temp path'),
]

STALE_TEMPLATE_NAMES = {"example.py", "api_reference.md", "example_asset.txt"}

# ─── PATH-AGNOSTIC ENFORCEMENT ──────────────────────────────────────────────
# A skill's executable code must resolve locations dynamically, never assume a
# user-specific home or an absolute mount point. This catches bare literal
# paths under user/mount roots. It deliberately does NOT match:
#   - variable-bearing paths (/media/$USER/..., /mnt/${LABEL}) — the char right
#     after the final slash is required to be alphanumeric, so a `$`/`{` there
#     never matches.
#   - configurable defaults (see _line_allows_hardcoded_path below): shell
#     `:-`/`:=` expansion, or python os.environ.get(...,"default")/getenv.
# System roots (/opt, /etc, /var, /usr, /tmp) are intentionally excluded —
# they are not user- or mount-specific and forcing them into variables adds
# noise without improving portability.
NONPORTABLE_PATH_RE = re.compile(
    r'(?<![\w$])/(?:home|Users|media|mnt|run/media)/[A-Za-z0-9][\w.+-]*'
)


def _line_allows_hardcoded_path(line: str) -> bool:
    """True when a literal path on this line is an overridable default (and so
    effectively portable) or is merely a comment, not live code."""
    s = line.strip()
    if s.startswith(('#', '//', ';', '*', '<!--')):
        return True  # comment / doc line — not executed
    if ':-' in line or ':=' in line:
        return True  # shell parameter-expansion default
    if re.search(r'\b(?:os\.)?(?:environ\.get|getenv)\s*\(', line):
        return True  # python env lookup with a default
    return False


def check_hardcoded_paths_in_scripts(skill_path, checks):
    """FAIL a skill whose executable scripts hardcode user/mount-specific
    absolute paths instead of resolving them at runtime. Reference docs get a
    WARN (examples in guides are expected, but real usernames still surface)."""
    scripts_dir = skill_path / "scripts"
    if scripts_dir.is_dir():
        for f in sorted(scripts_dir.rglob("*")):
            if not f.is_file() or f.suffix.lower() not in {".sh", ".py", ".bash", ".zsh", ".ps1"}:
                continue
            rel = f.relative_to(skill_path)
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                if _line_allows_hardcoded_path(line):
                    continue
                m = NONPORTABLE_PATH_RE.search(line)
                if m:
                    checks.append(Check(
                        f"Hardcoded path in script — {rel}:{i}",
                        "FAIL", False,
                        f"'{m.group(0)}' — resolve the mount/home at runtime "
                        "(detect it, or read $HOME / an overridable ${VAR:-default})"
                    ))
                    break  # one finding per file keeps output actionable

    # Reference docs: advisory only, but flag genuine per-user paths loudly.
    refs = skill_path / "references"
    if refs.is_dir():
        user_path_re = re.compile(r'(?<![\w$])/(?:home|Users|media|run/media)/[A-Za-z0-9][\w.-]*/')
        for f in sorted(refs.rglob("*")):
            if not f.is_file() or f.suffix.lower() not in {".md", ".txt", ".html"}:
                continue
            if _is_template_path(f.relative_to(skill_path)):
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            m = user_path_re.search(text)
            if m:
                checks.append(Check(
                    f"Hardcoded path in doc — {f.relative_to(skill_path)}",
                    "WARN", False,
                    f"'{m.group(0)}' — prefer a ${{USB_MOUNT}}/$HOME placeholder so "
                    "readers don't copy a machine-specific path"
                ))

# ─── CL-022: STRICT STRUCTURAL RULES (apply in BOTH basic + enterprise) ────
#
# Allowed top-level items in a skill dir — exactly these 5 (4 fixed + the
# generated .skill zip whose basename matches the skill).
ALLOWED_ROOT_NAMES = {"__init__.py", "SKILL.md", "scripts", "references"}

# Files at root that must be MOVED out (auto_fix relocates them with a
# rename prompt — nothing is ever deleted except cached dirs)
FORBIDDEN_ROOT_FILES = {
    ".gitignore", "README.md", "readme.md", "Readme.md",
    "TODO.md", "TODO", "TODO.txt", "NOTES.md", "NOTES",
    "CHANGELOG.md", "HISTORY.md", "AUTHORS", "LICENSE.txt",
    ".DS_Store", "Thumbs.db",
}

# Cached / VCS / build dirs forbidden anywhere in the skill tree
FORBIDDEN_DIRS = {
    "__pycache__", ".pytest_cache", ".mypy_cache",
    "node_modules", ".git", ".svn", ".hg",
    "__MACOSX", ".cache", "venv", ".venv", "env",
    "dist", "build", ".tox", ".eggs", ".next", ".nuxt",
}

# Bad reference/script filename patterns — non-informative names
BAD_NAME_PATTERNS = [
    (re.compile(r"^reference\d+\.", re.I), "non-informative name 'referenceN.*'"),
    (re.compile(r"^untitled\.", re.I), "non-informative name 'untitled.*'"),
    (re.compile(r"^new[-_ ]doc", re.I), "non-informative name 'new-doc*'"),
    (re.compile(r"^TODO", re.I), "TODO marker file"),
    (re.compile(r"^README", re.I), "README files not allowed inside skill"),
    (re.compile(r"^notes?\.md$", re.I), "non-informative name 'notes.md'"),
    (re.compile(r"^example\d*\.", re.I), "use named example (e.g. 'webhook-example.md')"),
    (re.compile(r"^test\d+\.", re.I), "non-informative name 'testN.*'"),
    (re.compile(r"^placeholder", re.I), "placeholder file"),
    (re.compile(r"^doc\d+\.", re.I), "non-informative name 'docN.*'"),
    (re.compile(r"^file\d+\.", re.I), "non-informative name 'fileN.*'"),
    # CL-041: .gitignore and other VCS metadata never belong in a skill anywhere.
    # If the content is a template that DESCRIBES what to ignore, put it in
    # references/templates/ as a purpose-scoped .md or .txt. If it's tracking
    # real files, it doesn't belong in a skill at all.
    (re.compile(r"^\.gitignore$", re.I), ".gitignore — VCS metadata does not belong in a skill; if template, put in references/templates/ as .md"),
    (re.compile(r"^\.gitattributes$", re.I), ".gitattributes — VCS metadata does not belong in a skill"),
    (re.compile(r"^\.npmignore$", re.I), ".npmignore — package-manager metadata does not belong in a skill"),
    (re.compile(r"^\.dockerignore$", re.I), ".dockerignore — build metadata does not belong in a skill"),
    (re.compile(r"^\.eslintignore$", re.I), ".eslintignore — lint metadata does not belong in a skill"),
    (re.compile(r"^\.prettierignore$", re.I), ".prettierignore — formatter metadata does not belong in a skill"),
]

# Min body chars for a SKILL.md to be "purpose-driven" (after frontmatter)
MIN_SKILL_BODY_CHARS = 200

# Hardcoded credentials in scripts — always a FAIL
HARDCODED_SECRETS_PATTERN = re.compile(
    r'(api_key|apikey|secret|password|token)\s*=\s*["\'][a-zA-Z0-9]{10,}',
    re.IGNORECASE
)

# Guardrail-system artifacts (monitor/gate tooling) are OPAQUE to the
# validator: legitimate at the skill root, never counted against structure,
# never moved, never deleted. Anywhere else → WARN and ask the user.
GUARDRAIL_ARTIFACTS = {
    ".loop-log.jsonl", ".gate.json", ".loop.lock",
    ".monitor.json", ".autowatch.json",
}

# Check model
class Check:
    def __init__(self, name, severity, passed, detail=""):
        self.name = name
        self.severity = severity   # "FAIL" or "WARN"
        self.passed = passed
        self.detail = detail

    def __repr__(self):
        status = "PASS" if self.passed else self.severity
        mark = "✓" if self.passed else ("✗" if self.severity == "FAIL" else "⚠")
        line = f"  {mark} [{status}] {self.name}"
        if self.detail and not self.passed:
            line += f"\n         → {self.detail}"
        return line

# Helpers
def extract_frontmatter(content: str) -> Tuple[Optional[str], str]:
    lines = content.splitlines()
    if not lines or lines[0].strip() != '---':
        return None, content
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            frontmatter = '\n'.join(lines[1:i])
            body = '\n'.join(lines[i+1:])
            return frontmatter, body
    return None, content

def parse_frontmatter(frontmatter_text: str) -> Optional[Dict]:
    if yaml is not None:
        try:
            return yaml.safe_load(frontmatter_text)
        except yaml.YAMLError:
            return None
    frontmatter = {}
    for line in frontmatter_text.splitlines():
        if ':' in line:
            key, value = line.split(':', 1)
            frontmatter[key.strip()] = value.strip()
    return frontmatter

def has_pattern(text, *patterns):
    return any(bool(re.search(p, text, re.IGNORECASE | re.MULTILINE)) for p in patterns)

# ─── CL-022: strict structural validators (apply in BOTH basic + enterprise) ─

def _is_template_path(rel_path) -> bool:
    """A file is a template if it lives under references/templates/ — exempt
    from bad-name + min-content rules because templates are blank-by-design."""
    parts = rel_path.parts if hasattr(rel_path, "parts") else str(rel_path).split("/")
    return "references" in parts and "templates" in parts

def _check_init_functional(init_path) -> Tuple[bool, str]:
    """__init__.py must be non-empty, valid Python, and contain real content."""
    if not init_path.is_file():
        return False, "missing"
    try:
        content = init_path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError as e:
        return False, f"read error: {e}"
    if len(content) < 5 or content in {"", "pass", "# placeholder"}:
        return False, "empty / pass-only / placeholder"
    try:
        import ast
        ast.parse(content)
    except SyntaxError as e:
        return False, f"syntax error: {e.msg}"
    return True, "ok"

def check_strict_structure(skill_path, checks):
    """Enforce: root must contain ONLY __init__.py, SKILL.md, scripts/,
    references/, and <skill_name>.skill. Lessons → references/lessons/.
    Templates → references/templates/ (read-only). No junk dirs anywhere."""
    skill_name = skill_path.name
    allowed = ALLOWED_ROOT_NAMES | {f"{skill_name}.skill"}

    for item in skill_path.iterdir():
        if item.name in allowed:
            continue
        if item.name in GUARDRAIL_ARTIFACTS:
            # Opaque guardrail-system file — legitimate at root, hands off.
            continue
        if item.name.endswith(".skill"):
            # Foreign .skill archive at root (not matching this skill's name)
            checks.append(Check(
                "Foreign .skill archive at root",
                "FAIL", False,
                f"Found: {item.name} — only <skill_name>.skill belongs here"
            ))
            continue
        if item.is_dir():
            if item.name == "lessons":
                checks.append(Check(
                    "lessons/ at root", "FAIL", False,
                    f"Must be inside references/lessons/  ({item.name}/)"
                ))
            elif item.name == "templates":
                checks.append(Check(
                    "templates/ at root", "FAIL", False,
                    f"Must be inside references/templates/  ({item.name}/)"
                ))
            elif item.name == "assets":
                # assets/ is NOT permitted anywhere in a skill (CL-040 rule).
                # Output-file assets belong INSIDE the specific scripts/ or
                # references/ subtree that uses them, purpose-scoped by filename.
                checks.append(Check(
                    "assets/ at root — not permitted anywhere", "FAIL", False,
                    "Move its contents into the scripts/ or references/ "
                    "subtree that consumes them, with purpose-scoped "
                    "filenames, then remove the emptied directory."
                ))
            elif item.name in FORBIDDEN_DIRS:
                checks.append(Check(
                    "Forbidden directory", "FAIL", False,
                    f"Cached/VCS dir: {item.name}/"
                ))
            else:
                checks.append(Check(
                    "Unexpected directory at root", "FAIL", False,
                    f"Only 'scripts/' and 'references/' allowed — got: {item.name}/"
                ))
        else:
            if item.name in FORBIDDEN_ROOT_FILES:
                checks.append(Check(
                    "Forbidden root file", "FAIL", False,
                    f"Move out of root and rename purpose-scoped: {item.name}"
                ))
            else:
                checks.append(Check(
                    "Unexpected file at root", "FAIL", False,
                    f"Only __init__.py, SKILL.md, <skill_name>.skill allowed — got: {item.name}"
                ))

    # CL-041: scripts/ must be flat. No subdirectories allowed inside it.
    # If a skill's scripts genuinely need a nested tool (e.g., an embedded
    # CLI project), that tool belongs as its own skill or the essential logic
    # should be flattened into scripts/ with purpose-scoped names.
    scripts_root = skill_path / "scripts"
    if scripts_root.is_dir():
        for item in scripts_root.iterdir():
            if item.is_dir():
                rel = item.relative_to(skill_path)
                checks.append(Check(
                    f"Subdirectory in scripts/ — {item.name}",
                    "FAIL", False,
                    f"Path: {rel} — scripts/ must be flat. Either promote this "
                    "subdirectory to its own top-level skill, or flatten its "
                    "essential scripts into scripts/ with purpose-scoped filenames."
                ))

    # Guardrail artifacts anywhere BELOW root — hands off, but ask the user
    for gf in skill_path.rglob("*"):
        if gf.is_file() and gf.name in GUARDRAIL_ARTIFACTS and gf.parent != skill_path:
            rel = gf.relative_to(skill_path)
            checks.append(Check(
                "Guardrail artifact in unexpected location", "WARN", False,
                f"{rel} — guardrail files belong at the skill root. "
                "Was this intentional? (validator/auto-fix will not touch it)"
            ))

    # Forbidden dirs anywhere in the tree (not just root)
    for root, dirs, _ in os.walk(skill_path):
        for d in dirs:
            if d in FORBIDDEN_DIRS:
                rel = Path(root).joinpath(d).relative_to(skill_path)
                checks.append(Check(
                    "Cached/junk dir found", "FAIL", False,
                    f"Path: {rel}"
                ))
            # CL-040: assets/ is banned ANYWHERE in a skill, not just root.
            if d == "assets":
                rel = Path(root).joinpath(d).relative_to(skill_path)
                if str(rel) != "assets":  # root case already reported above
                    checks.append(Check(
                        "Nested assets/ dir — not permitted anywhere", "FAIL", False,
                        f"Path: {rel} — move contents inline into the "
                        "consuming scripts/ or references/ file with a "
                        "purpose-scoped filename."
                    ))

    # Templates must be in references/templates/, not elsewhere
    for tpl_candidate in skill_path.rglob("templates"):
        if not tpl_candidate.is_dir():
            continue
        if tpl_candidate.parent != skill_path / "references":
            rel = tpl_candidate.relative_to(skill_path)
            if rel != Path("references/templates"):
                checks.append(Check(
                    "templates/ in wrong location", "FAIL", False,
                    f"Found: {rel} — must be at references/templates/"
                ))

    # CL-040: references/ may ONLY contain files + these two subdirs.
    # Anything else at references/ root is a FAIL.
    ALLOWED_REFS_SUBDIRS = {"templates", "lessons"}
    refs = skill_path / "references"
    if refs.is_dir():
        for item in refs.iterdir():
            if item.is_dir() and item.name not in ALLOWED_REFS_SUBDIRS:
                checks.append(Check(
                    f"Unexpected subdirectory in references/",
                    "FAIL", False,
                    f"Only 'templates/' and 'lessons/' allowed — got: "
                    f"references/{item.name}/"
                ))

def check_bad_names(skill_path, checks):
    """Reject reference1.md / example.md / TODO.* / README* / etc. in
    references/ and scripts/. Templates are exempt."""
    for sub in ("references", "scripts"):
        sub_dir = skill_path / sub
        if not sub_dir.is_dir():
            continue
        for f in sub_dir.rglob("*"):
            if not f.is_file():
                continue
            rel = f.relative_to(skill_path)
            if _is_template_path(rel):
                continue
            for pat, why in BAD_NAME_PATTERNS:
                if pat.search(f.name):
                    checks.append(Check(
                        f"Bad filename in {sub}/", "FAIL", False,
                        f"{rel}: {why}"
                    ))
                    break

def check_init_py_functional(skill_path, checks):
    """__init__.py must be a real, functional Python module."""
    init_py = skill_path / "__init__.py"
    ok, detail = _check_init_functional(init_py)
    if not ok:
        checks.append(Check(
            "__init__.py not functional", "FAIL", False,
            detail + " — should export __skill__ + __version__ at minimum"
        ))

def check_lessons_optional(skill_path, checks):
    """Lessons are OPTIONAL in both basic + enterprise. If present, must be
    inside references/lessons/. This REPLACES the old enterprise-only
    'lessons required' rule."""
    # Root-level check is handled by check_strict_structure;
    # also make sure there's no /lessons/ elsewhere (e.g., scripts/lessons/)
    refs = skill_path / "references"
    for d in skill_path.rglob("lessons"):
        if not d.is_dir():
            continue
        rel = d.relative_to(skill_path)
        # OK location: directly under references/
        if d.parent == refs:
            continue
        # Anywhere else is wrong
        checks.append(Check(
            "lessons/ in wrong location", "FAIL", False,
            f"Found: {rel} — must be at references/lessons/"
        ))

def check_nested_skill_mds(skill_path, checks):
    """A skill has exactly ONE SKILL.md — at its root. Any other is a
    nested skill that must be merged out or promoted to its own directory."""
    if nested_skill_mds is None:
        return
    for nested in nested_skill_mds(skill_path):
        rel = nested.relative_to(skill_path)
        checks.append(Check(
            "Nested SKILL.md", "FAIL", False,
            f"{rel} — only the root SKILL.md is allowed. Analyze the nested "
            "skill: merge its content into this skill or promote it to its "
            "own top-level skill directory."
        ))

def check_templates_readonly(skill_path, checks):
    """references/templates/ files must be read-only (templates are copied
    out for use, never edited in place)."""
    tpl = skill_path / "references" / "templates"
    if not tpl.is_dir():
        return
    for f in tpl.rglob("*"):
        if not f.is_file():
            continue
        try:
            mode = f.stat().st_mode
        except OSError:
            continue
        if mode & 0o222:  # any write bit set
            rel = f.relative_to(skill_path)
            checks.append(Check(
                "Template not read-only", "FAIL", False,
                f"{rel} — templates must be chmod 0444 (auto-repairable "
                "via the pipeline)"
            ))

def check_secrets_in_scripts(skill_path, checks):
    """Hardcoded credentials in any script are always a FAIL."""
    scripts_dir = skill_path / "scripts"
    if not scripts_dir.is_dir():
        return
    for f in scripts_dir.rglob("*"):
        if not f.is_file():
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        m = HARDCODED_SECRETS_PATTERN.search(text)
        if m:
            rel = f.relative_to(skill_path)
            checks.append(Check(
                "Hardcoded secret in script", "FAIL", False,
                f"{rel} — assignment of a literal credential "
                f"('{m.group(1)}'). Read secrets from env/config instead."
            ))

def check_placeholders_all_files(skill_path, checks, skill_md_content):
    """No placeholder content anywhere in the skill — not just SKILL.md.

    - references/ docs (.md/.txt/.html): same PLACEHOLDER_PATTERNS as
      SKILL.md, skipping fenced code blocks and inline code spans in
      markdown (the same escape the SKILL.md scan's backtick lookbehind
      provides — documentation may DISCUSS markers in code formatting).
    - scripts/: comment-prefixed work markers only, so a validator or
      scanner that legitimately *defines* marker patterns in string
      literals doesn't self-match.
    - references/templates/ and blank-by-design files are exempt.
    """
    refs = skill_path / "references"
    if refs.is_dir():
        for f in refs.rglob("*"):
            if not f.is_file() or f.suffix.lower() not in {".md", ".txt", ".html"}:
                continue
            rel = f.relative_to(skill_path)
            if _is_template_path(rel):
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            in_code_block = False
            for line in text.splitlines():
                stripped = line.strip()
                if stripped.startswith("```"):
                    in_code_block = not in_code_block
                    continue
                if in_code_block:
                    continue
                # Inline code spans are quoted material, not live markers
                scan_line = re.sub(r"`[^`]*`", "", line)
                for pattern, description in PLACEHOLDER_PATTERNS:
                    if re.search(pattern, scan_line, re.IGNORECASE):
                        checks.append(Check(
                            f"Placeholder in reference — {rel}",
                            "FAIL", False,
                            f"{description}: '{stripped[:60]}'"
                        ))
                        break
                else:
                    continue
                break  # one finding per file keeps output readable

    comment_marker = re.compile(r"(?:#|//|<!--|;)\s*(TODO|FIXME|XXX|HACK)\b", re.I)
    scripts_dir = skill_path / "scripts"
    if scripts_dir.is_dir():
        for f in scripts_dir.rglob("*"):
            if not f.is_file():
                continue
            rel = f.relative_to(skill_path)
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            m = comment_marker.search(text)
            if m:
                checks.append(Check(
                    f"Placeholder marker in script — {rel}",
                    "FAIL", False,
                    f"Comment contains {m.group(1).upper()} — finish or "
                    "remove the marked work before validating."
                ))

def check_internal_links(skill_path, checks, skill_md_content):
    """Relative links in SKILL.md must point at files that exist."""
    for link_text, link_url in re.findall(r'\[([^\]]+)\]\(([^)]+)\)', skill_md_content):
        if link_url.startswith(("http", "#", "mailto:")):
            continue
        if len(link_url) > 200 or not link_url.isprintable():
            continue
        try:
            if not (skill_path / link_url).exists():
                checks.append(Check(
                    "Broken internal link in SKILL.md", "FAIL", False,
                    f"[{link_text}]({link_url}) — target does not exist"
                ))
        except (OSError, ValueError):
            pass

def check_duplicate_sections(checks, skill_md_content):
    """Duplicate ## section names in SKILL.md indicate a botched merge."""
    seen = set()
    for s in re.findall(r'^##\s+(.+)$', skill_md_content, re.MULTILINE):
        key = s.strip().lower()
        if key in seen:
            checks.append(Check(
                "Duplicate section in SKILL.md", "FAIL", False,
                f"'## {s.strip()}' appears more than once"
            ))
        seen.add(key)

# ─── CL-022: auto-fix (called when --fix passed) ────────────────────────────
# CONSERVATIVE CONTRACT (CL-023):
#   --fix may DELETE only:
#     - Junk dirs (__pycache__, .git, node_modules, …) — clearly cache/build
#     - Stale .skill archives (regenerated on next pack)
#     - EMPTY / pure-placeholder files (no content to lose)
#     - Whitespace-only files
#   --fix may MOVE (preserves content):
#     - lessons/ → references/lessons/
#     - templates/ → references/templates/ (chmod 0444)
#     - any root file → references/ or scripts/ by extension
#     - bad-name files WITH CONTENT → moved to correct dir, validator still FAILS
#       with rename hint ("validator can't pick a good name for you — you rename it")
#     - forbidden root files (README.md, TODO.md, etc.) WITH CONTENT → moved to
#       references/ with a note, validator FAILS so user knows
#   --fix NEVER:
#     - Overwrites a non-empty __init__.py (creates one only if MISSING)
#     - Deletes a file that has substance (real content the user might want)
#     - Modifies file CONTENTS — only file LOCATIONS
#
# This means an enterprise validation can still FAIL after --fix runs (e.g.
# bad names remain). That's by design: --fix corrects what's safe, the
# human rectifies the rest.

# auto_fix_skill() lives in auto_fix.py. validate.py stays purely read-only.
# The shim below re-exports it so any legacy caller doing
# `from validate import auto_fix_skill` still works transparently.
def auto_fix_skill(skill_path):
    import importlib.util
    here = Path(__file__).parent
    spec = importlib.util.spec_from_file_location("_af", str(here / "auto_fix.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.auto_fix_skill(skill_path)


# Main validation function
def validate_skill(skill_path: str, basic_mode: bool = False) -> Dict:
    # Resolve so skill_path.name is the real directory name even when the
    # caller passes "." (otherwise the skill's own <name>.skill archive is
    # misreported as foreign).
    skill_path = Path(skill_path).resolve()
    checks = []
    
    # 1. File existence
    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        return {"valid": False, "status": "fail", "issues": ["SKILL.md not found"], "warnings": []}
    
    # 2. __init__.py required
    init_py = skill_path / "__init__.py"
    if not init_py.exists():
        checks.append(Check("Missing __init__.py", "FAIL", False, "Required for production/enterprise"))
    
    # 3. Read and parse SKILL.md
    try:
        content = skill_md.read_text(encoding='utf-8')
    except OSError as e:
        return {"valid": False, "status": "fail", "issues": [f"Could not read SKILL.md: {e}"], "warnings": []}
    
    lines = content.splitlines()
    line_count = len(lines)
    
    # 4. Frontmatter validation
    frontmatter_text, body = extract_frontmatter(content)
    if frontmatter_text is None:
        checks.append(Check("Invalid frontmatter format", "FAIL", False, "Missing opening or closing ---"))
    else:
        frontmatter = parse_frontmatter(frontmatter_text)
        if not frontmatter or not isinstance(frontmatter, dict):
            checks.append(Check("Frontmatter must be a YAML dictionary", "FAIL", False))
        else:
            # Required keys
            if 'name' not in frontmatter:
                checks.append(Check("Missing 'name' in frontmatter", "FAIL", False))
            if 'description' not in frontmatter:
                checks.append(Check("Missing 'description' in frontmatter", "FAIL", False))
            if 'version' not in frontmatter:
                checks.append(Check(
                    "Missing 'version' in frontmatter", "FAIL", False,
                    "Versioning is mandatory — the packager bumps it on "
                    "every pack; start at 0.1.0"
                ))
            
            # Allowed keys
            unexpected = set(frontmatter.keys()) - ALLOWED_PROPERTIES
            if unexpected:
                checks.append(Check(
                    f"Unexpected keys: {', '.join(sorted(unexpected))}",
                    "FAIL", False,
                    f"Allowed: {', '.join(sorted(ALLOWED_PROPERTIES))}"
                ))
            
            # Name validation
            if 'name' in frontmatter:
                name = frontmatter['name']
                if not isinstance(name, str):
                    checks.append(Check("Name must be a string", "FAIL", False))
                elif name.strip():
                    if not re.match(r'^[a-z0-9-]+$', name.strip()):
                        checks.append(Check(
                            f"Name should be hyphen-case", "FAIL", False,
                            f"Got: {name}"
                        ))
                    if len(name.strip()) > MAX_SKILL_NAME_LENGTH:
                        checks.append(Check(
                            f"Name too long ({len(name.strip())} chars)",
                            "FAIL", False,
                            f"Max: {MAX_SKILL_NAME_LENGTH}"
                        ))
            
            # Description validation
            if 'description' in frontmatter:
                desc = frontmatter['description']
                if not isinstance(desc, str):
                    checks.append(Check("Description must be a string", "FAIL", False))
                elif desc.strip():
                    if '<' in desc or '>' in desc:
                        checks.append(Check("Description cannot contain angle brackets", "FAIL", False))
                    if len(desc.strip()) > MAX_DESCRIPTION_LENGTH:
                        checks.append(Check(
                            f"Description too long ({len(desc.strip())} chars)",
                            "FAIL", False,
                            f"Max: {MAX_DESCRIPTION_LENGTH}"
                        ))
                    if len(desc.strip()) < MIN_DESCRIPTION_LENGTH:
                        checks.append(Check(
                            f"Description too short ({len(desc.strip())} chars)",
                            "WARN", False,
                            f"Min: {MIN_DESCRIPTION_LENGTH}"
                        ))

            # CL-040: metadata.tags minimum — 5 basic / 7 enterprise so the
            # skill has enough lexical surface area to auto-trigger in normal
            # conversation. Enforced in BOTH tiers (basic still needs 5).
            min_tags = 5 if basic_mode else 7
            tags = []
            meta = frontmatter.get("metadata")
            if isinstance(meta, dict):
                raw = meta.get("tags", [])
                if isinstance(raw, list):
                    tags = [t for t in raw if isinstance(t, str) and t.strip()]
            if len(tags) < min_tags:
                checks.append(Check(
                    f"metadata.tags requires at least {min_tags} entries "
                    f"({'basic' if basic_mode else 'enterprise'} tier)",
                    "FAIL", False,
                    f"Got {len(tags)}. Each tag should be a distinct natural-"
                    "language phrase that could plausibly auto-trigger this "
                    "skill in conversation."
                ))

    # 5. Directory structure
    scripts_dir = skill_path / "scripts"
    refs_dir = skill_path / "references"
    lessons_dir = skill_path / "lessons"
    assets_dir = skill_path / "assets"

    # CL-041 EXTENSION ALLOWLISTS (per user spec 2026-06-30).
    # scripts/ accepts only executable/script formats.
    # references/ accepts only doc formats — with templates/ subdir exempt
    # from extension check (any file type allowed there, purpose-scoped naming
    # enforced via BAD_NAME_PATTERNS which _is_template_path() intentionally
    # bypasses, since templates are skeletons named for what they template).
    ALLOWED_SCRIPT_EXTS = {".py", ".sh", ".bat", ".exe", ".ps1",
                           ".js", ".ts", ".mjs", ".cjs"}
    ALLOWED_REF_EXTS = {".md", ".txt", ".html", ".pdf"}

    # Scripts directory
    if not scripts_dir.exists():
        checks.append(Check("Missing scripts/ directory", "FAIL", False))
    else:
        script_files = []
        for f in scripts_dir.rglob('*'):
            if not f.is_file():
                continue
            rel = f.relative_to(skill_path)
            if f.suffix.lower() in ALLOWED_SCRIPT_EXTS:
                script_files.append(f)
            else:
                checks.append(Check(
                    f"Wrong file type in scripts/ — {rel}",
                    "FAIL", False,
                    f"Extension '{f.suffix}' not allowed in scripts/. "
                    f"Allowed: {', '.join(sorted(ALLOWED_SCRIPT_EXTS))}. "
                    "Move to references/ (for docs) or references/templates/ "
                    "(for skeletons) and rename with a purpose-scoped name."
                ))
        min_scripts = 2 if basic_mode else 3
        if len(script_files) < min_scripts:
            checks.append(Check(
                f"scripts/ requires at least {min_scripts} script files",
                "FAIL", False,
                f"Found {len(script_files)}"
            ))

    # References directory
    if not refs_dir.exists():
        checks.append(Check("Missing references/ directory", "FAIL", False))
    else:
        ref_files = []
        for f in refs_dir.rglob('*'):
            if not f.is_file():
                continue
            rel = f.relative_to(skill_path)
            # references/templates/ is the ONLY exception — any extension
            # allowed. templates are skeletons named for their purpose
            # (structure.json, .env.example, table-a-graph.pdf, etc.).
            if _is_template_path(rel):
                ref_files.append(f)
                continue
            if f.suffix.lower() in ALLOWED_REF_EXTS:
                ref_files.append(f)
            else:
                checks.append(Check(
                    f"Wrong file type in references/ — {rel}",
                    "FAIL", False,
                    f"Extension '{f.suffix}' not allowed in references/. "
                    f"Allowed: {', '.join(sorted(ALLOWED_REF_EXTS))}. "
                    "Put non-doc files in references/templates/ (any type "
                    "allowed there, purpose-scoped names), or rename with a "
                    "purpose-scoped .md/.txt/.html/.pdf name."
                ))
        min_refs = 3 if basic_mode else 5
        if len(ref_files) < min_refs:
            checks.append(Check(
                f"references/ requires at least {min_refs} reference files",
                "FAIL", False,
                f"Found {len(ref_files)}"
            ))

    # Lessons: OPTIONAL in BOTH modes (CL-022 — was enterprise-required).
    # If present, must be inside references/lessons/ — enforced in
    # check_lessons_optional() called later.
    
    # 6. Body length check
    if frontmatter_text and content.count("---") >= 2:
        body_lines = len(body.strip().split("\n")) if body.strip() else 0
        if body_lines >= 500:
            checks.append(Check(
                "SKILL.md body exceeds 500 lines",
                "FAIL", False,
                f"Got {body_lines} lines - use references/ for detailed docs"
            ))
    
    # 7. Cross-reference check (WARN) — uses the same allowlists so a .html
    # reference or .bat script is checked the same way as any other.
    if scripts_dir.exists():
        for script in scripts_dir.rglob('*'):
            if script.is_file() and script.suffix.lower() in ALLOWED_SCRIPT_EXTS:
                rel_path = script.relative_to(skill_path)
                if f"{rel_path}" not in content:
                    checks.append(Check(
                        f"Script not referenced in SKILL.md",
                        "WARN", False,
                        f"Missing: {rel_path}"
                    ))

    if refs_dir.exists():
        for ref in refs_dir.rglob('*'):
            if not ref.is_file():
                continue
            rel_path = ref.relative_to(skill_path)
            # templates/ is exempt — skeletons don't need SKILL.md mention
            if _is_template_path(rel_path):
                continue
            if ref.suffix.lower() in ALLOWED_REF_EXTS:
                if f"{rel_path}" not in content:
                    checks.append(Check(
                        f"Reference not referenced in SKILL.md",
                        "WARN", False,
                        f"Missing: {rel_path}"
                    ))
    
    # 8. Placeholder detection
    in_code_block = False
    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith('```'):
            in_code_block = not in_code_block
            continue
        if in_code_block:
            continue
        for pattern, description in PLACEHOLDER_PATTERNS:
            if re.search(pattern, line, re.IGNORECASE):
                checks.append(Check(
                    f"Contains {description}",
                    "FAIL", False,
                    f"Line: {stripped[:60]}"
                ))
                break
    
    # 9. Hardcoded path detection
    for pattern, description in HARDCODED_PATTERNS:
        matches = re.findall(pattern, content)
        if matches:
            checks.append(Check(
                f"Hardcoded path found",
                "FAIL", False,
                f"Pattern: {matches[0]}"
            ))
    
    # 10. Stale template detection
    for template in STALE_TEMPLATE_NAMES:
        if (refs_dir / template).exists():
            checks.append(Check(
                f"Stale template file found",
                "WARN", False,
                f"File: {template}"
            ))
    
    # 11. CL-022 strict structural rules — apply in BOTH basic + enterprise
    check_strict_structure(skill_path, checks)
    check_bad_names(skill_path, checks)
    check_init_py_functional(skill_path, checks)
    check_lessons_optional(skill_path, checks)

    # 12. CL-042 whole-skill content rules — apply in BOTH tiers
    check_nested_skill_mds(skill_path, checks)
    check_templates_readonly(skill_path, checks)
    check_secrets_in_scripts(skill_path, checks)
    check_placeholders_all_files(skill_path, checks, content)
    check_hardcoded_paths_in_scripts(skill_path, checks)
    check_internal_links(skill_path, checks, content)
    check_duplicate_sections(checks, content)
    
    # Calculate status
    fails = [c for c in checks if not c.passed and c.severity == "FAIL"]
    warns = [c for c in checks if not c.passed and c.severity == "WARN"]
    status = "fail" if fails else ("warning" if warns else "pass")

    # CL-040: "valid" means "passes the tier gate", which is fails==0.
    # Warnings do NOT invalidate a skill at its tier — they're advisory.
    return {
        "valid": len(fails) == 0,
        "status": status,
        "checks": checks,
        "fails": len(fails),
        "warnings": len(warns)
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Unified Enterprise Skill Validator")
    parser.add_argument("skill_dir", help="Skill directory to validate")
    parser.add_argument("--basic", action="store_true", help="Use basic (production) validation instead of enterprise")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    # validate.py is purely read-only. Structural fixes live in auto_fix.py.
    result = validate_skill(args.skill_dir, args.basic)
    
    if args.json:
        import json
        from datetime import datetime, timezone
        print(json.dumps({
            "operation": "validate",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "skill": args.skill_dir,
            "mode": "enterprise" if not args.basic else "basic",
            "status": result["status"],
            "valid": result["valid"],
            "fails": result["fails"],
            "warnings": result["warnings"],
            "checks": [
                {
                    "name": c.name,
                    "severity": c.severity,
                    "passed": c.passed,
                    "detail": c.detail
                }
                for c in result["checks"]
            ]
        }, indent=2))
    else:
        print(f"\n{'='*62}")
        print(f"  Skill Validation Report {'(BASIC)' if args.basic else '(ENTERPRISE)'}")
        print(f"{'='*62}\n")
        
        for check in result["checks"]:
            print(check)
        
        print(f"\n{'─'*62}")
        print(f"  Status  : {result['status'].upper()}")
        print(f"  Fails   : {result['fails']}")
        print(f"  Warnings: {result['warnings']}")
        print(f"{'─'*62}")

        # CL-040: surface the escape hatch when structural fails exist.
        # validate.py itself never mutates — hint points to skill_enhance.py.
        if result["fails"] > 0:
            structural_tags = (
                "Forbidden", "lessons/", "templates/", "Cached", "Bad filename",
                "__init__.py", "Unexpected", "Foreign .skill", "assets",
            )
            structural_fails = [
                c for c in result["checks"]
                if not c.passed and c.severity == "FAIL"
                and any(tag in c.name for tag in structural_tags)
            ]
            if structural_fails:
                print(f"")
                print(f"  Hint: {len(structural_fails)} of these are structural")
                print(f"        violations that can be auto-repaired. Run the")
                print(f"        full loop via skill_enhance.py to apply them")
                print(f"        (validate.py itself never modifies anything).")
        print(f"")

        sys.exit(0 if result["valid"] else 1)


if __name__ == "__main__":
    main()
