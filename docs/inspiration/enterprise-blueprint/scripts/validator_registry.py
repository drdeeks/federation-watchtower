#!/usr/bin/env python3
"""
Validator Registry — maps project type → phase → validator script.
Used by enforce_blueprint.py to assign the correct validator per phase gate.
"""

from pathlib import Path

VALIDATORS_DIR = Path(__file__).parent

# Project type → {phase_index: validator_filename}
VALIDATOR_REGISTRY = {
    # Default: agent/crew/backend (what we built for mv-maestro)
    "agent-crew": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_core_services.py",
        2: "validate_phase2_runtime_agents.py",
        3: "validate_phase3_persistence_hardening.py",
        4: "validate_phase4_integration.py",
    },
    # Web applications (React, Next.js, Vue, Svelte, Astro, Remix, Gatsby)
    "web-app": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_api.py",
        2: "validate_phase2_frontend_web.py",
        3: "validate_phase3_persistence_hardening.py",
        4: "validate_phase4_integration_web.py",
    },
    # Web3 DApps (frontend + smart contracts)
    "web3-dapp": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_api.py",
        2: "validate_phase2_frontend_web.py",
        3: "validate_phase3_smart_contracts.py",
        4: "validate_phase4_integration_web3.py",
    },
    # Mobile apps (Flutter primary, React Native secondary)
    "mobile-flutter": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_api.py",
        2: "validate_phase2_mobile_flutter.py",
        3: "validate_phase3_mobile_hardening.py",
        4: "validate_phase4_integration_mobile.py",
    },
    "mobile-react-native": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_api.py",
        2: "validate_phase2_mobile_react_native.py",
        3: "validate_phase3_mobile_hardening.py",
        4: "validate_phase4_integration_mobile.py",
    },
    # Desktop apps (Tauri, Electron, Wails)
    "desktop-tauri": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_rust.py",
        2: "validate_phase2_desktop_tauri.py",
        3: "validate_phase3_desktop_hardening.py",
        4: "validate_phase4_integration_desktop.py",
    },
    "desktop-electron": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_node.py",
        2: "validate_phase2_desktop_electron.py",
        3: "validate_phase3_desktop_hardening.py",
        4: "validate_phase4_integration_desktop.py",
    },
    "desktop-wails": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_go.py",
        2: "validate_phase2_desktop_wails.py",
        3: "validate_phase3_desktop_hardening.py",
        4: "validate_phase4_integration_desktop.py",
    },
    # CLI tools (Rust, Go, Python, Node)
    "cli-rust": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_cli_rust.py",
        2: "validate_phase2_cli_rust.py",
        3: "validate_phase3_cli_hardening.py",
        4: "validate_phase4_integration_cli.py",
    },
    "cli-go": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_cli_go.py",
        2: "validate_phase2_cli_go.py",
        3: "validate_phase3_cli_hardening.py",
        4: "validate_phase4_integration_cli.py",
    },
    "cli-python": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_cli_python.py",
        2: "validate_phase2_cli_python.py",
        3: "validate_phase3_cli_hardening.py",
        4: "validate_phase4_integration_cli.py",
    },
    "cli-node": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_cli_node.py",
        2: "validate_phase2_cli_node.py",
        3: "validate_phase3_cli_hardening.py",
        4: "validate_phase4_integration_cli.py",
    },
    # Backend services (APIs, microservices)
    "backend-fastapi": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_fastapi.py",
        2: "validate_phase2_backend_fastapi.py",
        3: "validate_phase3_persistence_hardening.py",
        4: "validate_phase4_integration_backend.py",
    },
    "backend-node": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_node.py",
        2: "validate_phase2_backend_node.py",
        3: "validate_phase3_persistence_hardening.py",
        4: "validate_phase4_integration_backend.py",
    },
    "backend-go": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_go.py",
        2: "validate_phase2_backend_go.py",
        3: "validate_phase3_persistence_hardening.py",
        4: "validate_phase4_integration_backend.py",
    },
    "backend-rust": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_backend_rust.py",
        2: "validate_phase2_backend_rust.py",
        3: "validate_phase3_persistence_hardening.py",
        4: "validate_phase4_integration_backend.py",
    },
    # Smart contracts only
    "smart-contracts": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_smart_contracts_core.py",
        2: "validate_phase2_smart_contracts_advanced.py",
        3: "validate_phase3_smart_contracts.py",
        4: "validate_phase4_integration_smart_contracts.py",
    },
    # Data/ML pipelines
    "ml-pipeline": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_ml_data.py",
        2: "validate_phase2_ml_training.py",
        3: "validate_phase3_ml_serving.py",
        4: "validate_phase4_integration_ml.py",
    },
    # Infrastructure/DevOps
    "infra-terraform": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_terraform_core.py",
        2: "validate_phase2_terraform_modules.py",
        3: "validate_phase3_terraform_hardening.py",
        4: "validate_phase4_integration_infra.py",
    },
    # Documentation sites
    "docs-site": {
        0: "validate_phase0_foundation.py",
        1: "validate_phase1_docs_content.py",
        2: "validate_phase2_docs_site.py",
        3: "validate_phase3_docs_hardening.py",
        4: "validate_phase4_integration_docs.py",
    },
}

# Aliases for convenience
VALIDATOR_REGISTRY["agent"] = VALIDATOR_REGISTRY["agent-crew"]
VALIDATOR_REGISTRY["crew"] = VALIDATOR_REGISTRY["agent-crew"]
VALIDATOR_REGISTRY["backend"] = VALIDATOR_REGISTRY["backend-fastapi"]
VALIDATOR_REGISTRY["frontend"] = VALIDATOR_REGISTRY["web-app"]
VALIDATOR_REGISTRY["web"] = VALIDATOR_REGISTRY["web-app"]
VALIDATOR_REGISTRY["dapp"] = VALIDATOR_REGISTRY["web3-dapp"]
VALIDATOR_REGISTRY["contracts"] = VALIDATOR_REGISTRY["smart-contracts"]
VALIDATOR_REGISTRY["mobile"] = VALIDATOR_REGISTRY["mobile-flutter"]
VALIDATOR_REGISTRY["desktop"] = VALIDATOR_REGISTRY["desktop-tauri"]
VALIDATOR_REGISTRY["cli"] = VALIDATOR_REGISTRY["cli-rust"]
VALIDATOR_REGISTRY["ml"] = VALIDATOR_REGISTRY["ml-pipeline"]
VALIDATOR_REGISTRY["infra"] = VALIDATOR_REGISTRY["infra-terraform"]
VALIDATOR_REGISTRY["docs"] = VALIDATOR_REGISTRY["docs-site"]

def get_validator_map(project_type: str) -> dict:
    """Get phase→validator mapping for a project type. Falls back to agent-crew."""
    return VALIDATOR_REGISTRY.get(project_type, VALIDATOR_REGISTRY["agent-crew"])

def get_validator_path(project_type: str, phase_index: int) -> Path | None:
    """Get full path to validator script for project type + phase."""
    validator_map = get_validator_map(project_type)
    filename = validator_map.get(phase_index)
    if filename:
        path = VALIDATORS_DIR / filename
        if path.exists():
            return path
    return None

def list_supported_types() -> list:
    """Return unique project types (excluding aliases)."""
    # Filter out aliases (values that are references to other keys)
    primary = set()
    for k, v in VALIDATOR_REGISTRY.items():
        # Only include if v is a dict (not a reference)
        if isinstance(v, dict):
            primary.add(k)
    return sorted(primary)

def validate_registry() -> dict:
    """Check which validators exist vs missing."""
    result = {"existing": [], "missing": []}
    for ptype, phases in VALIDATOR_REGISTRY.items():
        if not isinstance(phases, dict):
            continue
        for phase_idx, filename in phases.items():
            path = VALIDATORS_DIR / filename
            if path.exists():
                result["existing"].append(f"{ptype}[phase-{phase_idx}] -> {filename}")
            else:
                result["missing"].append(f"{ptype}[phase-{phase_idx}] -> {filename}")
    return result

if __name__ == "__main__":
    import json
    print("Supported project types:")
    for t in list_supported_types():
        print(f"  - {t}")
    print("\nRegistry validation:")
    vr = validate_registry()
    print(f"  Existing: {len(vr['existing'])}")
    print(f"  Missing: {len(vr['missing'])}")
    for m in vr["missing"][:20]:
        print(f"    MISSING: {m}")
    if len(vr["missing"]) > 20:
        print(f"    ... and {len(vr['missing']) - 20} more")