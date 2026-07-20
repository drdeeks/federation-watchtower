#!/usr/bin/env python3
"""
Phase 3 Validator: Smart Contracts (Foundry/Hardhat/Brownie/ApeWorX)
Checks for framework config, contracts, tests, deploy scripts, ABIs, gas, static analysis, verification.
Run by ENFORCER only — not by agent.
"""

import sys
import os
import json
import subprocess
from pathlib import Path

def find_project_root(start: Path) -> Path:
    for p in [start] + list(start.parents):
        if (p / "foundry.toml").exists() or \
           (p / "hardhat.config.ts").exists() or \
           (p / "hardhat.config.js").exists() or \
           (p / "brownie-config.yaml").exists() or \
           (p / "ape-config.yaml").exists() or \
           (p / "truffle-config.js").exists() or \
           (p / "contracts").exists() or \
           (p / "src").exists():
            return p
    return start

def run_cmd(cmd, cwd, timeout=60):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, shell=isinstance(cmd, str))
        return r.returncode == 0, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return False, "", str(e)

def check_framework_config(root: Path):
    configs = [
        ("foundry.toml", "Foundry"),
        ("hardhat.config.ts", "Hardhat (TS)"),
        ("hardhat.config.js", "Hardhat (JS)"),
        ("brownie-config.yaml", "Brownie"),
        ("ape-config.yaml", "ApeWorX"),
        ("truffle-config.js", "Truffle"),
        ("woke.toml", "Woke"),
        ("slither.config.json", "Slither"),
    ]
    found = []
    for fname, label in configs:
        if (root / fname).exists():
            found.append(label)
    if found:
        return True, f"Framework: {', '.join(found)}"
    return False, "No smart contract framework config (foundry.toml, hardhat.config.*, brownie-config.yaml, ape-config.yaml, truffle-config.js)"

def check_contracts_dir(root: Path):
    dirs = ["contracts", "src", "src/contracts", "contracts/src", "programs"]
    for d in dirs:
        p = root / d
        if p.exists() and any(p.glob("*.sol")) or any(p.glob("*.vy")) or any(p.glob("*.rs")):
            sols = list(p.glob("**/*.sol")) + list(p.glob("**/*.vy")) + list(p.glob("**/*.rs"))
            return True, f"Contracts: {d}/ ({len(sols)} files)"
    return False, "No contracts directory with source files (checked contracts/, src/, programs/)"

def check_tests(root: Path):
    dirs = ["test", "tests", "test/", "tests/", "contracts/test", "src/test", "test/foundry", "test/hardhat"]
    for d in dirs:
        p = root / d
        if p.exists() and (any(p.glob("*.sol")) or any(p.glob("*.ts")) or any(p.glob("*.js")) or any(p.glob("*.py")) or any(p.glob("*.rs"))):
            return True, f"Tests: {d}/"
    return False, "No test directory with test files (test/, tests/, contract/test, src/test)"

def check_deploy_scripts(root: Path):
    dirs = ["script", "scripts", "deploy", "deployments", "script/deploy", "scripts/deploy", "migrations"]
    for d in dirs:
        p = root / d
        if p.exists() and any(p.iterdir()):
            files = list(p.glob("**/*"))
            return True, f"Deploy scripts: {d}/ ({len(files)} files)"
    return False, "No deploy scripts (script/, scripts/, deploy/, deployments/, migrations/)"

def check_abis_artifacts(root: Path):
    dirs = ["out", "artifacts", "build", "out/", "artifacts/", "build/", "artifacts/contracts"]
    for d in dirs:
        p = root / d
        if p.exists() and any(p.glob("*.json")):
            return True, f"ABIs/artifacts: {d}/"
    return False, "No ABIs/artifacts (run forge build, hardhat compile, brownie compile)"

def check_gas_reports(root: Path):
    # Foundry gas snapshots
    if (root / "gas-snapshot.json").exists():
        return True, "Gas snapshot: gas-snapshot.json"
    if (root / ".gas-snapshot").exists():
        return True, "Gas snapshot: .gas-snapshot"
    # Hardhat gas reporter
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
            if "hardhat-gas-reporter" in deps:
                return True, "Gas reporter: hardhat-gas-reporter configured"
        except:
            pass
    # Brownie gas
    if (root / "brownie-config.yaml").exists():
        return True, "Brownie: gas reporting available"
    return False, "No gas reporting (Foundry gas-snapshot.json, hardhat-gas-reporter, or Brownie)"

def check_static_analysis(root: Path):
    tools = []
    # Slither
    if (root / ".slither.config.json").exists() or (root / "slither.config.json").exists():
        tools.append("Slither (config)")
    for wf in (root / ".github/workflows").glob("*.yml") if (root / ".github/workflows").exists() else []:
        content = wf.read_text()
        if "slither" in content.lower() or "crytic/slither" in content:
            tools.append("Slither (CI)")
            break
    # Mythril
    if (root / "mythril.config.json").exists():
        tools.append("Mythril (config)")
    # Foundry forge test includes basic analysis
    if (root / "foundry.toml").exists():
        tools.append("Foundry (forge test)")
    # Aderyn
    if (root / "aderyn.config.yaml").exists():
        tools.append("Aderyn")
    # Solhint
    if (root / ".solhint.json").exists() or (root / "solhint.config.json").exists():
        tools.append("Solhint")
    # Woke
    if (root / "woke.toml").exists():
        tools.append("Woke")
    # Securify
    if (root / "securify.yaml").exists() or (root / ".securify").exists():
        tools.append("Securify")
    # MythX
    if (root / "mythx.yml").exists() or (root / ".mythx.yml").exists():
        tools.append("MythX")
    if tools:
        return True, f"Static analysis: {', '.join(tools)}"
    return False, "No static analysis (Slither, Mythril, Aderyn, Solhint, Woke, MythX, or forge test in CI)"

def check_verified_contracts(root: Path):
    # Check CI for verification
    for wf in (root / ".github/workflows").glob("*.yml") if (root / ".github/workflows").exists() else []:
        content = wf.read_text().lower()
        if "etherscan" in content or "verify" in content or "sourcify" in content:
            return True, "Contract verification in CI (Etherscan/Sourcify)"
    # Hardhat verify plugins
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
            if "@nomicfoundation/hardhat-verify" in deps or "hardhat-etherscan" in deps:
                return True, "Verification plugin: @nomicfoundation/hardhat-verify or hardhat-etherscan"
        except:
            pass
    # Foundry forge verify
    if (root / "foundry.toml").exists():
        return True, "Foundry: forge verify available"
    # Brownie verify
    if (root / "brownie-config.yaml").exists():
        return True, "Brownie: verification available"
    return False, "No contract verification setup (Etherscan, Sourcify, forge verify, hardhat-verify)"

def check_networks_config(root: Path):
    # Foundry
    if (root / "foundry.toml").exists():
        content = (root / "foundry.toml").read_text()
        if "[rpc_endpoints]" in content or "[profile." in content:
            return True, "Foundry: rpc_endpoints/profiles configured"
    # Hardhat
    for f in ["hardhat.config.ts", "hardhat.config.js"]:
        if (root / f).exists():
            content = (root / f).read_text()
            if "networks:" in content or "networks =" in content:
                return True, f"Hardhat: networks configured in {f}"
    # Brownie
    if (root / "brownie-config.yaml").exists():
        content = (root / "brownie-config.yaml").read_text()
        if "networks:" in content:
            return True, "Brownie: networks configured"
    # ApeWorX
    if (root / "ape-config.yaml").exists():
        content = (root / "ape-config.yaml").read_text()
        if "networks:" in content or "ecosystems:" in content:
            return True, "ApeWorX: networks/ecosystems configured"
    return False, "No network configuration (RPC endpoints, chain IDs, profiles)"

def check_dependencies(root: Path):
    # Foundry lib/ + remappings
    if (root / "lib").exists() and any((root / "lib").iterdir()):
        return True, "Foundry: lib/ dependencies"
    if (root / "remappings.txt").exists():
        return True, "Foundry: remappings.txt"
    # Node-based (Hardhat/Brownie/Truffle/Ape)
    pkg = root / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
            libs = ["@openzeppelin/contracts", "solmate", "forge-std", "ds-test", "vrf", "chainlink", "@openzeppelin/contracts-upgradeable", "erc721a", "solady", "foundry-devops"]
            found = [l for l in libs if l in deps]
            if found:
                return True, f"Node deps: {', '.join(found)}"
        except:
            pass
    # Brownie packages
    if (root / "brownie-config.yaml").exists():
        return True, "Brownie: packages in config"
    return False, "No dependencies (Foundry lib/ + remappings.txt, or npm deps like @openzeppelin/contracts, solmate, forge-std)"

def check_ci_cd(root: Path):
    wf_dir = root / ".github/workflows"
    if not wf_dir.exists():
        return False, "No CI/CD (.github/workflows/)"
    workflows = list(wf_dir.glob("*.yml")) + list(wf_dir.glob("*.yaml"))
    if not workflows:
        return False, "No workflow files in .github/workflows/"
    checks = []
    for wf in workflows:
        content = wf.read_text()
        if "forge test" in content or "forge build" in content or "forge fmt" in content or "forge snapshot" in content:
            checks.append("forge test/build/fmt/snapshot")
        if "hardhat test" in content or "hardhat compile" in content or "hardhat coverage" in content:
            checks.append("hardhat test/compile/coverage")
        if "brownie test" in content:
            checks.append("brownie test")
        if "slither" in content.lower():
            checks.append("slither")
        if "foundry" in content.lower() and "install" in content.lower():
            checks.append("foundry install")
        if "audit" in content.lower() or "security" in content.lower():
            checks.append("security audit")
    if checks:
        return True, f"CI/CD: {', '.join(set(checks))}"
    return False, "Workflows exist but no contract test/build/lint/security steps found"

def check_license_spdx(root: Path):
    for sol in root.glob("**/*.sol"):
        try:
            content = sol.read_text()
            if "SPDX-License-Identifier" in content:
                return True, f"SPDX license in {sol.relative_to(root)}"
        except:
            pass
    for vy in root.glob("**/*.vy"):
        try:
            content = vy.read_text()
            if "SPDX-License-Identifier" in content:
                return True, f"SPDX license in {vy.relative_to(root)}"
        except:
            pass
    return False, "No SPDX-License-Identifier in contracts"

def check_natspec(root: Path):
    for sol in root.glob("**/*.sol"):
        try:
            content = sol.read_text()
            if "@notice" in content or "@dev" in content or "@param" in content or "@return" in content:
                return True, f"NatSpec in {sol.relative_to(root)}"
        except:
            pass
    return False, "No NatSpec documentation (@notice, @dev, @param, @return)"

def check_contract_sizes(root: Path):
    # Check for size limits in CI or config
    if (root / "foundry.toml").exists():
        content = (root / "foundry.toml").read_text()
        if "bytecode_size_limit" in content or "max_contract_size" in content:
            return True, "Foundry: bytecode_size_limit configured"
    for wf in (root / ".github/workflows").glob("*.yml") if (root / ".github/workflows").exists() else []:
        content = wf.read_text()
        if "contract-size" in content.lower() or "bytecode" in content.lower() or "size-limit" in content.lower():
            return True, "Contract size check in CI"
    return False, "No contract size limits (Foundry bytecode_size_limit or CI check)"

def validate(project_root: str) -> int:
    root = find_project_root(Path(project_root))
    print(f"[validate_phase3_smart_contracts] Checking: {root}")

    checks = [
        ("framework config", check_framework_config),
        ("contracts dir", check_contracts_dir),
        ("tests", check_tests),
        ("deploy scripts", check_deploy_scripts),
        ("ABIs/artifacts", check_abis_artifacts),
        ("gas reports", check_gas_reports),
        ("static analysis", check_static_analysis),
        ("contract verification", check_verified_contracts),
        ("networks config", check_networks_config),
        ("dependencies", check_dependencies),
        ("CI/CD", check_ci_cd),
        ("SPDX license", check_license_spdx),
        ("NatSpec docs", check_natspec),
        ("contract sizes", check_contract_sizes),
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
        print("Usage: validate_phase3_smart_contracts.py <project_root>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase3_smart_contracts.py <project_root>")
        sys.exit(2)
    sys.exit(validate(sys.argv[1]))