#!/usr/bin/env python3
"""
Phase 1 Validator: Backend API (FastAPI/Express/NestJS/Django/Go/Rust)
Checks for API spec, database config, service entry point, health checks, config mgmt, logging, lock files.
Run by ENFORCER only — not by agent.
"""

import sys
import json
import subprocess
from pathlib import Path

def find_project_root(start: Path) -> Path:
    for p in [start] + list(start.parents):
        # Python
        if (p / "pyproject.toml").exists() or (p / "requirements.txt").exists() or (p / "setup.py").exists():
            return p
        # Node
        if (p / "package.json").exists():
            return p
        # Go
        if (p / "go.mod").exists():
            return p
        # Rust
        if (p / "Cargo.toml").exists():
            return p
        # Java
        if (p / "pom.xml").exists() or (p / "build.gradle").exists() or (p / "build.gradle.kts").exists():
            return p
    return start

def check_api_spec(root: Path):
    # OpenAPI/Swagger specs
    for pat in ["**/openapi.json", "**/openapi.yaml", "**/swagger.json", "**/swagger.yaml", "**/api-spec/*.json", "**/api-spec/*.yaml", "**/docs/api/*.json", "**/docs/api/*.yaml"]:
        if list(root.glob(pat)):
            return True, f"API spec found: {pat}"
    # Check for FastAPI auto-generated
    for f in root.glob("**/*.py"):
        try:
            content = f.read_text()
            if "FastAPI" in content and ("openapi" in content.lower() or "swagger" in content.lower()):
                return True, f"FastAPI with OpenAPI: {f}"
        except:
            pass
    # Check for NestJS/Swagger
    for f in root.glob("**/*.ts"):
        try:
            content = f.read_text()
            if "@nestjs/swagger" in content or "SwaggerModule" in content:
                return True, f"NestJS Swagger: {f}"
        except:
            pass
    return False, "No API spec (OpenAPI/Swagger) found"

def check_db_config(root: Path):
    configs = [
        "config/database.yml", "config/database.yaml",
        "config/db.yml", "config/db.yaml",
        "src/config/database.py", "src/config/db.py",
        "prisma/schema.prisma", "drizzle.config.ts",
        "alembic.ini", "migrations/",
        "knexfile.js", "knexfile.ts",
        "typeorm.config.ts", "ormconfig.json",
        "datasource.ts", "database.ts",
        "config/application.yml", "config/application.yaml",  # Spring
        "application.properties",  # Spring
        "resources/application.yml",
    ]
    for c in configs:
        if (root / c).exists():
            return True, f"DB config: {c}"
    # Check env files
    for env in [".env", ".env.example", ".env.template"]:
        if (root / env).exists():
            content = (root / env).read_text()
            if any(k in content for k in ["DATABASE_URL", "DB_", "POSTGRES_", "MYSQL_", "MONGO_", "REDIS_"]):
                return True, f"DB config in {env}"
    return False, "No database configuration found"

def check_service_entry(root: Path):
    # Python
    for pat in ["**/main.py", "**/app.py", "**/server.py", "**/api.py", "**/run.py", "src/main.py", "app/main.py"]:
        for f in root.glob(pat):
            try:
                content = f.read_text()
                if any(kw in content for kw in ["FastAPI", "Flask", "Django", "Starlette", "aiohttp", "uvicorn", "gunicorn"]):
                    return True, f"Python entry: {f}"
            except:
                pass
    # Node
    for pat in ["**/index.js", "**/index.ts", "**/main.ts", "**/server.ts", "**/app.ts", "src/index.ts", "src/main.ts"]:
        for f in root.glob(pat):
            try:
                content = f.read_text()
                if any(kw in content for kw in ["express", "fastify", "koa", "nestjs", "hono", "elysia", "createServer", "listen("]):
                    return True, f"Node entry: {f}"
            except:
                pass
    # Go
    for f in root.glob("**/main.go"):
        try:
            content = f.read_text()
            if "func main()" in content and any(kw in content for kw in ["http.ListenAndServe", "gin.", "echo.", "fiber.", "chi.", "mux.", "net/http"]):
                return True, f"Go entry: {f}"
        except:
            pass
    # Rust
    for f in root.glob("**/main.rs"):
        try:
            content = f.read_text()
            if "fn main()" in content and any(kw in content for kw in ["actix_web", "axum", "warp", "rocket", "tide", "salvo"]):
                return True, f"Rust entry: {f}"
        except:
            pass
    # Java Spring
    for f in root.glob("**/*Application.java"):
        try:
            content = f.read_text()
            if "@SpringBootApplication" in content:
                return True, f"Spring Boot: {f}"
        except:
            pass
    return False, "No service entry point found (main.py, index.ts, main.go, main.rs, *Application.java)"

def check_health_endpoint(root: Path):
    patterns = ["/health", "/healthz", "/ready", "/live", "/ping", "health_check", "healthcheck"]
    # Check Python
    for f in root.glob("**/*.py"):
        try:
            content = f.read_text()
            if any(p in content for p in patterns):
                return True, f"Health endpoint in {f}"
        except:
            pass
    # Check Node
    for f in root.glob("**/*.{js,ts}"):
        try:
            content = f.read_text()
            if any(p in content for p in patterns):
                return True, f"Health endpoint in {f}"
        except:
            pass
    # Check Go
    for f in root.glob("**/*.go"):
        try:
            content = f.read_text()
            if any(p in content for p in patterns):
                return True, f"Health endpoint in {f}"
        except:
            pass
    return False, "No health/readiness endpoint found"

def check_config_mgmt(root: Path):
    configs = [
        "config/", "src/config/", "conf/", "settings/",
        "pyproject.toml",  # Pydantic Settings
        ".env", ".env.example", ".env.template",
        "config.yaml", "config.yml", "config.toml",
        "application.yml", "application.yaml", "application.properties",
        "config.js", "config.ts", "config.json",
        "src/config/index.ts", "src/config/index.js",
    ]
    for c in configs:
        p = root / c
        if p.exists():
            return True, f"Config management: {c}"
    return False, "No config management (config/, .env, pyproject.toml, application.yml, etc.)"

def check_logging(root: Path):
    # Python
    for f in root.glob("**/*.py"):
        try:
            content = f.read_text()
            if "logging.config" in content or "structlog" in content or "loguru" in content or "logging.basicConfig" in content:
                return True, f"Python logging: {f}"
        except:
            pass
    # Node
    for f in root.glob("**/*.{js,ts}"):
        try:
            content = f.read_text()
            if any(l in content for l in ["winston", "pino", "bunyan", "console.log", "logger"]):
                return True, f"Node logging: {f}"
        except:
            pass
    # Config files
    for f in ["logging.yaml", "logging.yml", "logback.xml", "log4j2.xml", "log4j.properties"]:
        if (root / f).exists():
            return True, f"Logging config: {f}"
    return False, "No logging configuration found"

def check_lock_files(root: Path):
    locks = [
        "poetry.lock", "Pipfile.lock", "requirements.lock", "uv.lock",
        "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb",
        "go.sum", "Cargo.lock",
        "pom.xml", "build.gradle",  # Maven/Gradle have implicit locking
    ]
    for l in locks:
        if (root / l).exists():
            return True, f"Lock file: {l}"
    return False, "No dependency lock file (poetry.lock, package-lock.json, go.sum, Cargo.lock, etc.)"

def check_unit_tests(root: Path):
    dirs = ["tests", "test", "spec", "__tests__", "src/__tests__", "src/test"]
    for d in dirs:
        if (root / d).exists() and any((root / d).rglob("*")):
            return True, f"Test dir: {d}/"
    # Check package.json scripts
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            if "test" in data.get("scripts", {}):
                return True, "npm test script"
        except:
            pass
    # Python
    for f in ["pytest.ini", "pyproject.toml", "tox.ini"]:
        if (root / f).exists():
            return True, f"Python test config: {f}"
    # Go
    for f in root.glob("**/*_test.go"):
        return True, f"Go test: {f}"
    # Rust
    if (root / "Cargo.toml").exists():
        return True, "Rust (cargo test)"
    return False, "No unit tests (tests/ dir, test scripts, pytest.ini, *_test.go, Cargo.toml)"

def validate(project_root: str) -> int:
    root = find_project_root(Path(project_root))
    print(f"[validate_phase1_backend_api] Checking: {root}")

    checks = [
        ("API spec (OpenAPI/Swagger)", check_api_spec),
        ("Database config", check_db_config),
        ("Service entry point", check_service_entry),
        ("Health/readiness endpoint", check_health_endpoint),
        ("Config management", check_config_mgmt),
        ("Logging", check_logging),
        ("Dependency lock file", check_lock_files),
        ("Unit tests", check_unit_tests),
    ]

    failed = []
    for name, fn in checks:
        ok, msg = fn(root)
        status = "✓" if ok else "✗"
        print(f"  {status} {name}: {msg}")
        if not ok:
            failed.append(name)

    if failed:
        print(f"\nFAILED: {len(failed)}/{len(checks)} checks failed: {', '.join(failed)}")
        return 1
    print(f"\nPASSED: All {len(checks)} checks passed")
    return 0

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: validate_phase1_backend_api.py <project_root>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase1_backend_api.py <project_root>")
        sys.exit(2)
    sys.exit(validate(sys.argv[1]))