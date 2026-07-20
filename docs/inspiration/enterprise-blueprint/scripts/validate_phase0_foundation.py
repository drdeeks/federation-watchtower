#!/usr/bin/env python3
"""
Phase 0 Validator: Foundation
Checks for project structure, .gitignore, basic config, licensing, README.
Run by ENFORCER only — not by agent.
"""

import sys
import os
from pathlib import Path


def check_foundation(project_root: Path) -> tuple[bool, list[str]]:
    """Validate Phase 0 foundation deliverables."""
    errors = []
    warnings = []
    
    # 1. .gitignore exists and has proper rules
    gitignore = project_root / ".gitignore"
    if not gitignore.exists():
        errors.append("Missing .gitignore file")
    else:
        content = gitignore.read_text()
        required_patterns = [
            "__pycache__/", "*.pyc", ".venv/", "venv/", "env/",
            ".env", "*.log", "*.tmp", "*.bak", ".DS_Store",
            "dist/", "build/", "*.egg-info/", ".coverage",
            "node_modules/", ".next/", ".nuxt/", "target/",
            "*.iso", "*.img", "*.bin"  # for mv-maestro
        ]
        missing = [p for p in required_patterns if p not in content]
        if missing:
            warnings.append(f".gitignore missing patterns: {', '.join(missing)}")
    
    # 2. README exists
    readme_files = ["README.md", "README.rst", "README.txt", "README"]
    if not any((project_root / f).exists() for f in readme_files):
        errors.append("Missing README file (README.md recommended)")
    
    # 3. License file
    license_files = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENSE.rst", "COPYING"]
    if not any((project_root / f).exists() for f in license_files):
        warnings.append("No LICENSE file found")
    
    # 4. Project configuration (pyproject.toml, package.json, Cargo.toml, go.mod, etc.)
    config_files = [
        "pyproject.toml", "setup.py", "setup.cfg", "package.json",
        "Cargo.toml", "go.mod", "pom.xml", "build.gradle",
        "composer.json", "Gemfile", "requirements.txt"
    ]
    if not any((project_root / f).exists() for f in config_files):
        warnings.append("No project configuration file found (pyproject.toml, package.json, Cargo.toml, etc.)")
    
    # 5. Basic directory structure
    expected_dirs = ["src/", "lib/", "app/", "scripts/", "config/", "docs/", "tests/"]
    existing_dirs = [d for d in expected_dirs if (project_root / d).exists()]
    if len(existing_dirs) < 2:
        warnings.append(f"Sparse directory structure (found: {', '.join(existing_dirs) or 'none'})")
    
    # 6. Version control initialized
    if not (project_root / ".git").exists():
        errors.append("Git repository not initialized (.git missing)")
    
    # 7. Development environment config
    dev_configs = [
        ".env.example", ".env.sample", "config.example.yaml",
        "docker-compose.yml", "docker-compose.yaml", "Dockerfile",
        "devcontainer.json", ".devcontainer/", "Makefile", "justfile"
    ]
    if not any((project_root / f).exists() for f in dev_configs):
        warnings.append("No development environment config found (.env.example, docker-compose.yml, Makefile, etc.)")
    
    # 8. Pre-commit / linting config
    lint_files = [
        ".pre-commit-config.yaml", ".pre-commit-config.yml",
        "ruff.toml", "pyproject.toml",  # ruff config in pyproject.toml
        ".eslintrc*", ".prettierrc*", "stylelint.config.*",
        "clippy.toml", "rustfmt.toml"
    ]
    lint_found = False
    for f in lint_files:
        if list(project_root.glob(f)):
            lint_found = True
            break
    if not lint_found:
        warnings.append("No linting/pre-commit config found (.pre-commit-config.yaml, ruff.toml, .eslintrc, etc.)")
    
    return len(errors) == 0, errors + warnings


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: validate_phase0_foundation.py <step-path>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase0_foundation.py <step-path>", file=sys.stderr)
        sys.exit(1)
    
    step_path = Path(sys.argv[1])
    project_root = step_path.parent.parent
    
    passed, messages = check_foundation(project_root)
    
    for msg in messages:
        level = "ERROR" if not passed else "WARN"
        print(f"[{level}] {msg}")
    
    if passed:
        print("[OK] Phase 0 Foundation validation passed")
        sys.exit(0)
    else:
        print("[FAIL] Phase 0 Foundation validation failed")
        sys.exit(1)


if __name__ == "__main__":
    main()