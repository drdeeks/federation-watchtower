#!/usr/bin/env python3
"""
Phase 4 Validator: Integration & Validation
Checks for end-to-end tests, integration tests, CI/CD, deployment configs.
Run by ENFORCER only — not by agent.
"""

import sys
from pathlib import Path


def check_integration_validation(project_root: Path) -> tuple[bool, list[str]]:
    """Validate Phase 4 integration & validation deliverables."""
    errors = []
    warnings = []
    
    # 1. Integration tests
    integration_tests = [
        "tests/integration/", "test/integration/", "tests/e2e/", "test/e2e/",
        "tests/functional/", "test/functional/", "cypress/", "playwright/",
        "tests/api/", "test/api/"
    ]
    integration_found = any((project_root / p).exists() for p in integration_tests)
    if not integration_found:
        warnings.append("No integration/e2e tests found (tests/integration/, tests/e2e/, cypress/, playwright/)")
    
    # 2. CI/CD pipeline
    cicd_files = [
        ".github/workflows/", ".gitlab-ci.yml", ".gitlab/ci/",
        "Jenkinsfile", ".circleci/", "azure-pipelines.yml",
        ".drone.yml", ".woodpecker.yml", "bitbucket-pipelines.yml",
        ".buildkite/", "config/ci/"
    ]
    cicd_found = any((project_root / p).exists() for p in cicd_files)
    if not cicd_found:
        errors.append("No CI/CD pipeline found (.github/workflows/, .gitlab-ci.yml, Jenkinsfile, etc.)")
    
    # 3. Deployment configuration
    deploy_configs = [
        "kubernetes/", "k8s/", "helm/", "charts/", "manifests/",
        "deploy/", "deployment/", "infrastructure/", "terraform/",
        "pulumi/", "cloudformation/", "ansible/", "scripts/deploy.sh"
    ]
    deploy_found = any((project_root / p).exists() for p in deploy_configs)
    if not deploy_found:
        warnings.append("No deployment configuration found (k8s/, helm/, terraform/, deploy.sh, etc.)")
    
    # 4. Smoke tests / post-deploy validation
    smoke_tests = [
        "tests/smoke/", "test/smoke/", "scripts/smoke.sh",
        "scripts/health-check.sh", "scripts/validate-deploy.sh",
        "scripts/post-deploy.sh"
    ]
    if not any((project_root / p).exists() for p in smoke_tests):
        warnings.append("No smoke tests/post-deploy validation found (tests/smoke/, scripts/smoke.sh, etc.)")
    
    # 5. Contract tests (if microservices)
    contract_tests = [
        "tests/contract/", "test/contract/", "pact/", "contracts/",
        "pact/", "consumer-driven-contracts/"
    ]
    # Only warn if service structure exists
    has_services = (project_root / "services/").exists() or (project_root / "src/services/").exists()
    if has_services and not any((project_root / p).exists() for p in contract_tests):
        warnings.append("Microservices detected but no contract tests found (tests/contract/, pact/)")
    
    # 6. Performance / load tests
    perf_tests = [
        "tests/performance/", "test/performance/", "tests/load/",
        "k6/", "locustfile.py", "jmeter/", "gatling/",
        "scripts/load-test.sh", "scripts/benchmark.sh"
    ]
    if not any((project_root / p).exists() for p in perf_tests):
        warnings.append("No performance/load tests found (k6, locust, JMeter, tests/performance/)")
    
    # 7. Security scanning in CI
    security_scanning = [
        "trivy", "snyk", "sonarqube", "codeql", "bandit",
        "safety", "dependabot", "github/codeql-action",
        "aquasecurity/trivy-action", "snyk/actions"
    ]
    security_in_ci = False
    cicd_dir = project_root / ".github" / "workflows"
    if cicd_dir.exists():
        for f in cicd_dir.glob("*.yml"):
            try:
                if any(s in f.read_text().lower() for s in security_scanning):
                    security_in_ci = True
                    break
            except:
                pass
    
    cicd_gitlab = project_root / ".gitlab-ci.yml"
    if not security_in_ci and cicd_gitlab.exists():
        try:
            if any(s in cicd_gitlab.read_text().lower() for s in security_scanning):
                security_in_ci = True
        except:
            pass
    
    if not security_in_ci:
        warnings.append("No security scanning in CI/CD (Trivy, Snyk, CodeQL, Bandit, etc.)")
    
    # 8. Documentation completeness
    docs = [
        "docs/", "documentation/", "README.md", "CONTRIBUTING.md",
        "ARCHITECTURE.md", "DESIGN.md", "API.md", "DEPLOYMENT.md",
        "RUNBOOK.md", "OPERATIONS.md", "ADR/"
    ]
    docs_found = any((project_root / d).exists() for d in docs)
    if not docs_found:
        warnings.append("Minimal documentation (expected docs/, README.md, ARCHITECTURE.md, DEPLOYMENT.md)")
    
    # 9. Changelog / release notes
    changelog = [
        "CHANGELOG.md", "CHANGES.md", "RELEASES.md", "HISTORY.md",
        "docs/changelog.md", "docs/releases/"
    ]
    if not any((project_root / c).exists() for c in changelog):
        warnings.append("No changelog/release notes found (CHANGELOG.md, RELEASES.md)")
    
    return len(errors) == 0, errors + warnings


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: validate_phase4_integration_validation.py <step-path>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase4_integration_validation.py <step-path>", file=sys.stderr)
        sys.exit(1)
    
    step_path = Path(sys.argv[1])
    project_root = step_path.parent.parent
    
    passed, messages = check_integration_validation(project_root)
    
    for msg in messages:
        level = "ERROR" if not passed else "WARN"
        print(f"[{level}] {msg}")
    
    if passed:
        print("[OK] Phase 4 Integration & Validation validation passed")
        sys.exit(0)
    else:
        print("[FAIL] Phase 4 Integration & Validation validation failed")
        sys.exit(1)


if __name__ == "__main__":
    main()