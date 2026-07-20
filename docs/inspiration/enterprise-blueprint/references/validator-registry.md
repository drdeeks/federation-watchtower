# Validator Registry — Project-Type → Phase Validator Mapping

Generated from this session's enterprise-blueprint skill work. Maps project types to phase-specific validators that check REAL deliverables per blueprint.

## Registry Structure

```python
VALIDATOR_REGISTRY = {
    "web3-dapp": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_core_services.py", 
        2: "validate_phase2_frontend_web.py",
        3: "validate_phase3_smart_contracts.py",
        4: "validate_phase4_integration_web3.py",
    },
    "web-app": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_api.py",
        2: "validate_phase2_frontend_web.py", 
        3: "validate_phase3_persistence_hardening.py",
        4: "validate_phase4_integration_web.py",
    },
    "mobile-app": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_api.py",
        2: "validate_phase2_mobile_flutter.py",
        3: "validate_phase3_persistence_hardening.py",
        4: "validate_phase4_integration_web.py",
    },
    "agent-crew": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_core_services.py",
        2: "validate_phase2_runtime_agents.py",
        3: "validate_phase3_persistence_hardening.py",
        4: "validate_phase4_integration_validation.py",
    },
    # ... desktop-app, smart-contracts
}
```

## Project Type Detection

From blueprint frontmatter:
```markdown
**Project Type:** `web-app`   # or web3-dapp, mobile-app, agent-crew, etc.
```

## Blueprint-Driven Generator (Primary)

`scripts/blueprint_validator_gen.py` parses **Part VI implementation checklist tables** and generates `validate_phase{N}_blueprint.py` per project. This is the PRIMARY source — project-type registry is fallback only.

## Phase-Specific Validators (Real Deliverables Checked)

### Phase 0 — Foundation (All Types)
`validate_phase0_foundation.py` → `.gitignore` patterns, dir structure, README, LICENSE, pyproject.toml, git init, linting

### Phase 1 — Core Services
| Type | Validator | Key Checks |
|------|-----------|------------|
| agent-crew | `validate_phase1_core_services.py` | API spec (openapi.json), DB config (database.yml), service entry point, /health endpoint, config mgmt, logging, lock files, unit tests |
| web-app/dapp/backend | `validate_phase1_backend_api.py` | Same as above, tailored for web backends |

### Phase 2 — Frontend / Runtime
| Type | Validator | Key Checks |
|------|-----------|------------|
| web-app/dapp | `validate_phase2_frontend_web.py` | **Next.js/Vite/Svelte/Astro/Nuxt/Remix/Gatsby config**, pages/routes, components, TypeScript config, lint/format, build output, accessibility, SEO meta, responsive breakpoints, tests |
| mobile-flutter | `validate_phase2_mobile_flutter.py` | **pubspec.yaml**, platform dirs (android/ios/macos/windows/linux/web), build configs (gradle/Podfile), code signing, Fastlane/Codemagic, flutter analyze/test |
| agent-crew | `validate_phase2_runtime_agents.py` | Agent defs (SOUL.md/agent.json), Dockerfile/process mgmt, crew config, comms (Redis/gRPC), observability, lifecycle scripts |

### Phase 3 — Persistence / Contracts
| Type | Validator | Key Checks |
|------|-----------|------------|
| web3-dapp | `validate_phase3_smart_contracts.py` | **Foundry/Hardhat/Brownie/Ape config**, contracts in contracts/src/, tests, deploy scripts, ABIs (out/artifacts/), gas reports, Slither/Mythril, Etherscan verification |
| general | `validate_phase3_persistence_hardening.py` | Backup/restore scripts, firewall (nftables/iptables), hardening, volumes, secrets (SOPS/age), SSL, audit |

### Phase 4 — Integration
| Type | Validator | Key Checks |
|------|-----------|------------|
| web-app/dapp | `validate_phase4_integration_web.py` | E2E tests (Cypress/Playwright), CI/CD (GitHub Actions), deploy config (k8s/helm/terraform/Docker/vercel/netlify), smoke tests, perf tests (k6/locust), security scans (CodeQL/Semgrep/Trivy), docs, changelog, observability, feature flags |
| agent-crew | `validate_phase4_integration_validation.py` | Same as above + agent-specific integration tests |

## Opt-In Validator Pattern

```bash
# Default: loop-locking ONLY (no validators)
python3 enforce_blueprint.py /project --init

# Opt-in: generates validators from blueprint Part VI tables
python3 enforce_blueprint.py /project --init --with-validators
```

## Key Principles

1. **Blueprint IS source of truth** — Part VI tables drive validation
2. **Project-type registry is FALLBACK** — used only if Part VI tables missing
3. **Enforcer runs validators** — agents NEVER validate their own work
4. **Each project gets its own validators** — generated in `.blueprint-chain/validators/`
5. **Validators are executable** — `chmod +x`, run directly (not `python3 validator.py`)