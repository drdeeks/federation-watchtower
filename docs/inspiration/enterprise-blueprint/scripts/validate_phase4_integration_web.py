#!/usr/bin/env python3
"""
Phase 4 Validator: Integration Web (E2E, CI/CD, Deploy, Perf, Security, Docs, Changelog)
Checks for end-to-end tests, CI/CD pipelines, deployment configs, smoke tests,
performance tests, security scans, documentation, changelog.
Run by ENFORCER only — not by agent.
"""

import sys
import json
import subprocess
from pathlib import Path

def find_project_root(start: Path) -> Path:
    for p in [start] + list(start.parents):
        if (p / ".github").exists() or (p / "docker-compose.yml").exists() or \
           (p / "docker-compose.yaml").exists() or (p / "k8s").exists() or \
           (p / "helm").exists() or (p / "terraform").exists() or \
           (p / "tests").exists() or (p / "e2e").exists():
            return p
    return start

def check_e2e_tests(root: Path):
    dirs = ["tests/e2e", "e2e", "cypress", "playwright", "test/e2e", "tests/integration", "integration"]
    for d in dirs:
        p = root / d
        if p.exists() and any(p.rglob("*")):
            configs = ["cypress.config.ts", "playwright.config.ts", "jest.config.ts", "vitest.config.ts", "pytest.ini", "conftest.py"]
            found = [c for c in configs if (p / c).exists() or (root / c).exists()]
            return True, f"E2E/Integration tests: {d}/" + (f" (config: {', '.join(found)})" if found else "")
    return False, "No E2E/integration test directory (tests/e2e/, e2e/, cypress/, playwright/, tests/integration/)"

def check_ci_cd(root: Path):
    wf_dir = root / ".github/workflows"
    if not wf_dir.exists():
        for f in [".gitlab-ci.yml", "azure-pipelines.yml", "Jenkinsfile", ".circleci/config.yml", ".buildkite/pipeline.yml", "drone.yml", ".woodpecker.yml"]:
            if (root / f).exists():
                return True, f"CI/CD: {f}"
        return False, "No CI/CD (.github/workflows/, .gitlab-ci.yml, azure-pipelines.yml, Jenkinsfile, etc.)"
    
    workflows = list(wf_dir.glob("*.yml")) + list(wf_dir.glob("*.yaml"))
    if not workflows:
        return False, "No workflow files in .github/workflows/"
    
    stages = []
    for wf in workflows:
        content = wf.read_text()
        name = wf.stem
        if "test" in content.lower() and ("run:" in content or "steps:" in content):
            stages.append("test")
        if "build" in content.lower() or "compile" in content.lower():
            stages.append("build")
        if "deploy" in content.lower() or "release" in content.lower():
            stages.append("deploy")
        if "security" in content.lower() or "scan" in content.lower() or "audit" in content.lower():
            stages.append("security")
        if "lint" in content.lower() or "format" in content.lower():
            stages.append("lint")
        if "e2e" in content.lower() or "integration" in content.lower() or "cypress" in content.lower() or "playwright" in content.lower():
            stages.append("e2e")
    
    unique = list(set(stages))
    return True, f"CI/CD: {len(workflows)} workflows ({', '.join(unique) if unique else 'basic'})"

def check_deploy_config(root: Path):
    configs = []
    # Docker
    if (root / "Dockerfile").exists() or any(root.glob("Dockerfile*")):
        configs.append("Dockerfile")
    if (root / "docker-compose.yml").exists() or (root / "docker-compose.yaml").exists():
        configs.append("docker-compose")
    if (root / ".dockerignore").exists():
        configs.append(".dockerignore")
    # Kubernetes
    if (root / "k8s").exists() or (root / "kubernetes").exists():
        configs.append("k8s/")
    if (root / "helm").exists():
        configs.append("helm/")
    if (root / "skaffold.yaml").exists():
        configs.append("skaffold")
    # Terraform
    if (root / "terraform").exists() or (root / "infra").exists():
        configs.append("terraform/")
    # Cloud platforms
    if (root / "vercel.json").exists():
        configs.append("vercel.json")
    if (root / "netlify.toml").exists():
        configs.append("netlify.toml")
    if (root / "cloudbuild.yaml").exists():
        configs.append("cloudbuild")
    if (root / "serverless.yml").exists() or (root / "serverless.yaml").exists():
        configs.append("serverless")
    if (root / "fly.toml").exists():
        configs.append("fly.io")
    if (root / "railway.toml").exists():
        configs.append("railway")
    if (root / "render.yaml").exists():
        configs.append("render")
    if (root / "Procfile").exists():
        configs.append("Procfile")
    # Ansible
    if (root / "ansible").exists() or (root / "playbook.yml").exists():
        configs.append("ansible")
    
    if configs:
        return True, f"Deploy config: {', '.join(configs)}"
    return False, "No deployment config (Dockerfile, docker-compose, k8s/, helm/, terraform/, vercel.json, netlify.toml, serverless, fly.toml, etc.)"

def check_smoke_tests(root: Path):
    dirs = ["tests/smoke", "smoke", "scripts/smoke", "scripts/health", "tests/health"]
    for d in dirs:
        p = root / d
        if p.exists() and any(p.rglob("*")):
            return True, f"Smoke/health tests: {d}/"
    # Check package.json scripts
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            scripts = data.get("scripts", {})
            for k in ["smoke", "health", "postdeploy", "verify:deploy", "test:smoke"]:
                if k in scripts:
                    return True, f"Smoke script: npm run {k}"
        except:
            pass
    # Check Makefile
    if (root / "Makefile").exists():
        content = (root / "Makefile").read_text()
        if "smoke" in content or "health" in content:
            return True, "Smoke target in Makefile"
    return False, "No smoke/health tests (tests/smoke/, scripts/smoke/, or package.json smoke script)"

def check_perf_tests(root: Path):
    dirs = ["tests/perf", "tests/performance", "perf", "performance", "k6", "locust", "jmeter", "artillery", "wrk"]
    for d in dirs:
        p = root / d
        if p.exists() and any(p.rglob("*")):
            return True, f"Performance tests: {d}/"
    # Check package.json
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            scripts = data.get("scripts", {})
            for k in ["perf", "performance", "load", "k6", "locust", "artillery"]:
                if k in scripts:
                    return True, f"Perf script: npm run {k}"
        except:
            pass
    # Check for k6/locust configs
    for f in ["k6.js", "k6.ts", "locustfile.py", "artillery.yml", "artillery.yaml"]:
        if (root / f).exists():
            return True, f"Perf config: {f}"
    return False, "No performance/load tests (tests/perf/, k6, locust, artillery, jmeter, or perf script)"

def check_security_scans(root: Path):
    tools = []
    wf_dir = root / ".github/workflows"
    if wf_dir.exists():
        for wf in wf_dir.glob("*.yml"):
            content = wf.read_text().lower()
            if "codeql" in content or "github/codeql" in content:
                tools.append("CodeQL")
            if "sonarqube" in content or "sonarsource" in content:
                tools.append("SonarQube")
            if "semgrep" in content:
                tools.append("Semgrep")
            if "bandit" in content:
                tools.append("Bandit")
            if "eslint" in content and "security" in content:
                tools.append("ESLint security")
            if "trivy" in content:
                tools.append("Trivy")
            if "snyk" in content:
                tools.append("Snyk")
            if "dependabot" in content:
                tools.append("Dependabot")
            if "grype" in content or "syft" in content:
                tools.append("Grype/Syft")
            if "hadolint" in content:
                tools.append("Hadolint")
            if "checkov" in content:
                tools.append("Checkov")
            if "tfsec" in content:
                tools.append("tfsec")
            if "kubeaudit" in content or "kubescore" in content:
                tools.append("Kubeaudit")
            if "cosign" in content or "sigstore" in content:
                tools.append("Cosign/Sigstore")
            if "sbom" in content:
                tools.append("SBOM")
    # Config files
    if (root / ".semgrep.yml").exists() or (root / "semgrep.yml").exists():
        tools.append("Semgrep (config)")
    if (root / ".bandit").exists() or (root / "bandit.yaml").exists():
        tools.append("Bandit (config)")
    if (root / "sonar-project.properties").exists():
        tools.append("SonarQube (config)")
    if (root / ".snyk").exists():
        tools.append("Snyk (config)")
    if (root / "trivy.yaml").exists() or (root / ".trivy.yaml").exists():
        tools.append("Trivy (config)")
    if tools:
        return True, f"Security scans: {', '.join(set(tools))}"
    return False, "No security scanning (CodeQL, Semgrep, SonarQube, Bandit, Trivy, Snyk, Dependabot, Grype, Checkov, tfsec, etc.)"

def check_documentation(root: Path):
    docs = []
    if (root / "docs").exists() and any((root / "docs").rglob("*.md")):
        docs.append("docs/")
    if (root / "README.md").exists():
        docs.append("README.md")
    if (root / "CONTRIBUTING.md").exists():
        docs.append("CONTRIBUTING.md")
    if (root / "ARCHITECTURE.md").exists() or (root / "architecture.md").exists():
        docs.append("ARCHITECTURE.md")
    if (root / "API.md").exists() or (root / "api.md").exists() or (root / "docs/api").exists():
        docs.append("API docs")
    if (root / "CHANGELOG.md").exists() or (root / "CHANGES.md").exists() or (root / "HISTORY.md").exists():
        docs.append("CHANGELOG.md")
    if (root / "LICENSE").exists() or (root / "LICENSE.md").exists() or (root / "LICENSE.txt").exists():
        docs.append("LICENSE")
    if (root / "mkdocs.yml").exists() or (root / "docusaurus.config.ts").exists() or (root / "vitepress.config.ts").exists():
        docs.append("doc site config")
    if docs:
        return True, f"Documentation: {', '.join(docs)}"
    return False, "No documentation (docs/, README.md, CONTRIBUTING.md, ARCHITECTURE.md, API docs, CHANGELOG.md, LICENSE, mkdocs/docusaurus/vitepress)"

def check_changelog(root: Path):
    for f in ["CHANGELOG.md", "CHANGES.md", "HISTORY.md", "RELEASES.md"]:
        p = root / f
        if p.exists():
            content = p.read_text()
            if "## [" in content or "### " in content:
                return True, f"Changelog: {f} (structured)"
            return True, f"Changelog: {f}"
    # Check for conventional commits / auto-changelog
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            scripts = data.get("scripts", {})
            if "changelog" in scripts or "release" in scripts:
                return True, f"Changelog script: npm run {scripts.get('changelog', scripts.get('release'))}"
        except:
            pass
    if (root / ".github/workflows").exists():
        for wf in (root / ".github/workflows").glob("*.yml"):
            if "changelog" in wf.read_text().lower() or "release-please" in wf.read_text().lower():
                return True, "Changelog: automated in CI"
    return False, "No CHANGELOG.md (or CHANGES/HISTORY/RELEASES) with structured entries"

def check_monitoring_observability(root: Path):
    tools = []
    # Prometheus/Grafana
    for f in ["prometheus.yml", "prometheus.yaml", "grafana.ini", "grafana.yaml", "alerting.rules.yml", "alerts.yml"]:
        if (root / f).exists() or (root / "monitoring" / f).exists():
            tools.append("Prometheus/Grafana")
            break
    # Datadog
    if (root / "datadog.yaml").exists() or (root / "datadog.yml").exists():
        tools.append("Datadog")
    # New Relic
    if (root / "newrelic.yml").exists():
        tools.append("New Relic")
    # OpenTelemetry
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
            if "@opentelemetry/api" in deps or "@opentelemetry/sdk-node" in deps:
                tools.append("OpenTelemetry (JS)")
        except:
            pass
    py_files = list(root.glob("**/requirements*.txt")) + list(root.glob("**/pyproject.toml")) + list(root.glob("**/setup.py"))
    for pf in py_files:
        try:
            content = pf.read_text()
            if "opentelemetry" in content:
                tools.append("OpenTelemetry (Python)")
                break
        except:
            pass
    # Loki/Promtail
    if (root / "loki.yaml").exists() or (root / "promtail.yaml").exists():
        tools.append("Loki/Promtail")
    # Health endpoints
    for pat in ["**/health*.py", "**/health*.js", "**/health*.ts", "**/health*.go", "**/health*.rs"]:
        if list(root.glob(pat)):
            tools.append("Health endpoints")
            break
    if tools:
        return True, f"Observability: {', '.join(set(tools))}"
    return False, "No observability (Prometheus/Grafana, Datadog, New Relic, OpenTelemetry, Loki, health endpoints)"

def check_feature_flags(root: Path):
    for pat in ["**/flags*.py", "**/flags*.ts", "**/flags*.js", "**/feature-flags*", "**/launchdarkly*", "**/unleash*", "**/growthbook*", "**/flipper*"]:
        if list(root.glob(pat)):
            return True, f"Feature flags: {pat}"
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
            ff_libs = ["launchdarkly-node-server-sdk", "unleash-client", "@growthbook/growthbook", "flipper", "ffjavascript"]
            found = [f for f in ff_libs if f in deps]
            if found:
                return True, f"Feature flag libs: {', '.join(found)}"
        except:
            pass
    return False, "No feature flag system (LaunchDarkly, Unleash, GrowthBook, Flipper, custom)"

def validate(project_root: str) -> int:
    root = find_project_root(Path(project_root))
    print(f"[validate_phase4_integration_web] Checking: {root}")

    checks = [
        ("E2E/Integration tests", check_e2e_tests),
        ("CI/CD pipelines", check_ci_cd),
        ("Deploy config", check_deploy_config),
        ("Smoke/health tests", check_smoke_tests),
        ("Performance tests", check_perf_tests),
        ("Security scans", check_security_scans),
        ("Documentation", check_documentation),
        ("Changelog", check_changelog),
        ("Observability", check_monitoring_observability),
        ("Feature flags", check_feature_flags),
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
        print("Usage: validate_phase4_integration_web.py <project_root>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase4_integration_web.py <project_root>")
        sys.exit(2)
    sys.exit(validate(sys.argv[1]))