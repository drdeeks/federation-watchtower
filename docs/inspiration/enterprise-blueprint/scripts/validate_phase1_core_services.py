#!/usr/bin/env python3
"""
Phase 1 Validator: Core Services / Backend
Checks for API specs, database config, service definitions, health checks.
Run by ENFORCER only — not by agent.
"""

import sys
import os
from pathlib import Path


def check_core_services(project_root: Path) -> tuple[bool, list[str]]:
    """Validate Phase 1 core services/backend deliverables."""
    errors = []
    warnings = []
    
    # 1. API specification / contract
    api_specs = [
        "docs/api.yaml", "docs/api.yml", "docs/openapi.yaml", "docs/openapi.yml",
        "api/spec.yaml", "api/spec.yml", "swagger.yaml", "swagger.yml",
        "docs/swagger.yaml", "spec/openapi.yaml", "contracts/api.yaml"
    ]
    api_found = any((project_root / p).exists() for p in api_specs)
    if not api_found:
        warnings.append("No API specification found (OpenAPI/Swagger: docs/api.yaml, api/spec.yaml, etc.)")
    
    # 2. Database configuration
    db_configs = [
        "config/database.yaml", "config/database.yml", "config/db.yaml",
        "config/db.yml", "config/postgres.yaml", "config/mysql.yaml",
        "config/mongodb.yaml", "config/redis.yaml", "prisma/schema.prisma",
        "alembic.ini", "migrations/", "db/schema.sql", "schema.prisma",
        "drizzle.config.ts", "knexfile.js", "config/orm.yaml"
    ]
    db_found = any((project_root / p).exists() for p in db_configs)
    if not db_found:
        errors.append("No database configuration found (config/database.yaml, prisma/schema.prisma, alembic.ini, etc.)")
    
    # 3. Service definitions / entry points
    service_files = [
        "src/main.py", "src/app.py", "src/server.py", "src/api.py",
        "app/main.py", "app/app.py", "app/server.py",
        "server.py", "main.py", "api.py",
        "src/index.js", "src/index.ts", "server.js", "server.ts",
        "app.js", "app.ts", "main.go", "cmd/server/main.go",
        "Application.java", "Main.java", "Program.cs"
    ]
    service_found = any((project_root / p).exists() for p in service_files)
    if not service_found:
        warnings.append("No clear service entry point found (src/main.py, app/main.py, server.js, main.go, etc.)")
    
    # 4. Health check / readiness endpoints - simple check
    health_indicators = ["/health", "/healthz", "/ready", "/live", "/ping"]
    health_found = False
    
    # Only check a few key files for speed
    key_files = [
        project_root / "src/main.py", project_root / "app/main.py",
        project_root / "src/app.py", project_root / "server.py",
        project_root / "main.py", project_root / "api.py"
    ]
    for f in key_files:
        if f.exists():
            try:
                content = f.read_text().lower()
                if any(h in content for h in health_indicators):
                    health_found = True
                    break
            except:
                pass
    
    if not health_found:
        warnings.append("No health/readiness endpoint detected (expected /health, /ready, /healthz, etc.)")
    
    # 5. Configuration management
    config_mgmt = [
        "config/", "settings.py", "settings.yaml", "settings.yml",
        "config.yaml", "config.yml", "config.toml", "config.json",
        ".env", ".env.local", ".env.development", ".env.production",
    ]
    config_found = any((project_root / p).exists() for p in config_mgmt)
    # Also check for dotenv usage in a few key files
    dotenv_used = False
    for f in key_files:
        if f.exists():
            try:
                if "dotenv" in f.read_text().lower() or "pydantic_settings" in f.read_text().lower():
                    dotenv_used = True
                    break
            except:
                pass
    if not config_found and not dotenv_used:
        warnings.append("No configuration management found (config/, .env, pydantic-settings, dynaconf, etc.)")
    
    # 6. Logging configuration
    logging_configs = [
        "config/logging.yaml", "config/logging.yml", "logging.yaml",
        "logging.yml"
    ]
    logging_found = any((project_root / p).exists() for p in logging_configs)
    logging_in_code = False
    for f in key_files:
        if f.exists():
            try:
                content = f.read_text().lower()
                if "logging.basicconfig" in content or "structlog" in content or "loguru" in content:
                    logging_in_code = True
                    break
            except:
                pass
    if not logging_found and not logging_in_code:
        warnings.append("No logging configuration detected (config/logging.yaml, structlog, loguru, etc.)")
    
    # 7. Dependency management / lock files
    lock_files = [
        "requirements.txt", "requirements.lock", "Pipfile.lock",
        "poetry.lock", "pyproject.lock", "package-lock.json",
        "yarn.lock", "pnpm-lock.yaml", "Cargo.lock", "go.sum",
        "composer.lock", "Gemfile.lock"
    ]
    lock_found = any((project_root / f).exists() for f in lock_files)
    if not lock_found:
        warnings.append("No dependency lock file found (requirements.txt, poetry.lock, package-lock.json, Cargo.lock, etc.)")
    
    # 8. Unit tests exist
    test_dirs = ["tests/", "test/", "spec/", "__tests__/"]
    unit_tests = any((project_root / d).exists() for d in test_dirs)
    if not unit_tests:
        warnings.append("No test directory found (tests/, test/, spec/)")
    
    return len(errors) == 0, errors + warnings


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: validate_phase1_core_services.py <step-path>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase1_core_services.py <step-path>", file=sys.stderr)
        sys.exit(1)
    
    step_path = Path(sys.argv[1])
    project_root = step_path.parent.parent
    
    passed, messages = check_core_services(project_root)
    
    for msg in messages:
        level = "ERROR" if not passed else "WARN"
        print(f"[{level}] {msg}")
    
    if passed:
        print("[OK] Phase 1 Core Services validation passed")
        sys.exit(0)
    else:
        print("[FAIL] Phase 1 Core Services validation failed")
        sys.exit(1)


if __name__ == "__main__":
    main()