#!/usr/bin/env python3
"""
Phase 2 Validator: Frontend Web (React/Next.js/Vue/Svelte/Astro)
Checks for framework config, pages, components, build, lint, types, accessibility.
Run by ENFORCER only — not by agent.
"""

import sys
import os
import json
import subprocess
from pathlib import Path

def find_project_root(start: Path) -> Path:
    """Walk up to find package.json or framework config."""
    for p in [start] + list(start.parents):
        if (p / "package.json").exists() or \
           (p / "next.config.js").exists() or \
           (p / "vite.config.ts").exists() or \
           (p / "nuxt.config.ts").exists() or \
           (p / "svelte.config.js").exists() or \
           (p / "astro.config.mjs").exists():
            return p
    return start

def run_cmd(cmd, cwd, timeout=10):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, shell=isinstance(cmd, str))
        return r.returncode == 0, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return False, "", str(e)

def check_package_json(root: Path):
    pkg = root / "package.json"
    if not pkg.exists():
        return False, "Missing package.json"
    try:
        data = json.loads(pkg.read_text())
        name = data.get("name", "unknown")
        scripts = data.get("scripts", {})
        deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
        return True, f"package.json: {name} | scripts: {list(scripts.keys())} | deps: {len(deps)}"
    except Exception as e:
        return False, f"Invalid package.json: {e}"

def check_lockfile(root: Path):
    for lf in ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb"]:
        if (root / lf).exists():
            return True, f"Lockfile: {lf}"
    return False, "Missing lockfile (package-lock.json, yarn.lock, pnpm-lock.yaml, or bun.lockb)"

def check_framework_config(root: Path):
    configs = [
        ("next.config.js", "Next.js"),
        ("next.config.mjs", "Next.js (ESM)"),
        ("vite.config.ts", "Vite"),
        ("vite.config.js", "Vite"),
        ("nuxt.config.ts", "Nuxt 3"),
        ("nuxt.config.js", "Nuxt 3"),
        ("svelte.config.js", "SvelteKit"),
        ("astro.config.mjs", "Astro"),
        ("astro.config.ts", "Astro"),
        ("remix.config.js", "Remix"),
        ("gatsby-config.js", "Gatsby"),
    ]
    found = []
    for fname, label in configs:
        if (root / fname).exists():
            found.append(label)
    if found:
        return True, f"Framework config: {', '.join(found)}"
    return False, "No recognized framework config (Next.js, Vite, Nuxt, SvelteKit, Astro, Remix, Gatsby)"

def check_pages_routes(root: Path):
    # Next.js (app/ or pages/)
    # Vite/React (src/pages/, src/routes/)
    # SvelteKit (src/routes/)
    # Nuxt (pages/)
    # Astro (src/pages/)
    # Remix (app/routes/)
    patterns = [
        "app/**/page.{tsx,jsx,ts,js}",
        "pages/**/*.{tsx,jsx,ts,js}",
        "src/pages/**/*.{tsx,jsx,ts,js}",
        "src/routes/**/*.{tsx,jsx,ts,js,svte}",
        "app/routes/**/*.{tsx,jsx,ts,js}",
    ]
    for pat in patterns:
        if list(root.glob(pat)):
            return True, f"Routes/pages found via {pat}"
    return False, "No pages/routes found (checked app/, pages/, src/pages/, src/routes/, app/routes/)"

def check_components(root: Path):
    dirs = ["components", "src/components", "app/components", "ui", "src/ui"]
    for d in dirs:
        if (root / d).exists() and any((root / d).iterdir()):
            return True, f"Components dir: {d}"
    return False, "No components directory found (components/, src/components/, ui/, src/ui/)"

def check_tsconfig(root: Path):
    for f in ["tsconfig.json", "tsconfig.app.json", "tsconfig.base.json"]:
        if (root / f).exists():
            try:
                data = json.loads((root / f).read_text())
                strict = data.get("compilerOptions", {}).get("strict", False)
                return True, f"TypeScript: {f} | strict: {strict}"
            except:
                return True, f"TypeScript: {f} (parse error)"
    return False, "Missing tsconfig.json"

def check_lint_format(root: Path):
    checks = []
    if (root / ".eslintrc.js").exists() or (root / ".eslintrc.cjs").exists() or (root / "eslint.config.js").exists() or (root / "eslint.config.mjs").exists():
        checks.append("ESLint")
    if (root / ".prettierrc").exists() or (root / ".prettierrc.json").exists() or (root / "prettier.config.js").exists():
        checks.append("Prettier")
    if (root / ".stylelintrc").exists():
        checks.append("Stylelint")
    if checks:
        return True, f"Lint/format: {', '.join(checks)}"
    return False, "No lint/format config (ESLint, Prettier, Stylelint)"

def check_build_output(root: Path):
    dirs = [".next", "dist", "build", ".svelte-kit", ".output", ".astro"]
    for d in dirs:
        if (root / d).exists():
            return True, f"Build output: {d}/"
    return False, "No build output (run build first)"

def check_accessibility(root: Path):
    # Check for axe-core in devDependencies or test files
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
            if "@axe-core/react" in deps or "axe-core" in deps or "@axe-core/playwright" in deps:
                return True, "Accessibility: axe-core configured"
        except:
            pass
    # Check for test files with a11y
    for pat in ["**/*a11y*.test.{ts,tsx,js,jsx}", "**/*accessibility*.test.{ts,tsx,js,jsx}"]:
        if list(root.glob(pat)):
            return True, "Accessibility tests found"
    return False, "No accessibility testing configured (axe-core, @axe-core/react, or a11y tests)"

def check_seo_meta(root: Path):
    # Check for next-seo, vue-meta, @nuxtjs/seo, svelte-head, astro-seo
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
            seo_pkgs = ["next-seo", "vue-meta", "@nuxtjs/seo", "svelte-head", "astro-seo", "react-helmet", "react-helmet-async"]
            found = [p for p in seo_pkgs if p in deps]
            if found:
                return True, f"SEO meta: {', '.join(found)}"
        except:
            pass
    # Check for head/meta in layout/pages
    for pat in ["**/layout.{tsx,jsx,vue,svelte,astro}", "**/app/layout.{tsx,jsx}"]:
        for f in root.glob(pat):
            content = f.read_text(errors="ignore")
            if "metadata" in content or "head(" in content or "<head>" in content or "useHead" in content:
                return True, f"SEO meta tags in {f.relative_to(root)}"
    return False, "No SEO/meta configuration found"

def check_env_example(root: Path):
    for f in [".env.example", ".env.template", ".env.sample", "env.example"]:
        if (root / f).exists():
            return True, f"Env template: {f}"
    return False, "Missing .env.example (required for CI/deploy)"

def check_test_setup(root: Path):
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            scripts = data.get("scripts", {})
            test_cmd = scripts.get("test") or scripts.get("test:unit") or scripts.get("test:ci")
            if test_cmd:
                return True, f"Test script: {test_cmd}"
        except:
            pass
    # Check for test dirs
    for d in ["tests", "test", "__tests__", "src/__tests__", "cypress", "playwright", "e2e"]:
        if (root / d).exists():
            return True, f"Test dir: {d}/"
    return False, "No test setup (scripts.test or tests/ dir)"

def check_gitignore(root: Path):
    gi = root / ".gitignore"
    if not gi.exists():
        return False, "Missing .gitignore"
    content = gi.read_text()
    required = ["node_modules", ".next", "dist", "build", ".env", "*.log", ".turbo", ".vercel", ".netlify"]
    missing = [r for r in required if r not in content]
    if missing:
        return False, f".gitignore missing: {', '.join(missing)}"
    return True, ".gitignore has required patterns"

def validate(project_root: str) -> int:
    root = find_project_root(Path(project_root))
    print(f"[validate_phase2_frontend_web] Checking: {root}")

    checks = [
        ("package.json", check_package_json),
        ("lockfile", check_lockfile),
        ("framework config", check_framework_config),
        ("pages/routes", check_pages_routes),
        ("components", check_components),
        ("TypeScript", check_tsconfig),
        ("lint/format", check_lint_format),
        ("build output", check_build_output),
        ("accessibility", check_accessibility),
        ("SEO/meta", check_seo_meta),
        ("env template", check_env_example),
        ("test setup", check_test_setup),
        (".gitignore", check_gitignore),
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
        print("Usage: validate_phase2_frontend_web.py <project_root>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase2_frontend_web.py <project_root>")
        sys.exit(2)
    sys.exit(validate(sys.argv[1]))