# Validation Over Syntax — Deliverable Completeness

## The Problem

Syntax passing (`python -m py_compile`, `node --check`, `go build`) is **necessary but insufficient**. An agent can write syntactically correct code that:
- Doesn't implement the required interface
- Doesn't handle error cases
- Doesn't honor the agent's constitution
- Doesn't deliver what the phase spec promises

## Four-Tier Validation

```python
def validate_deliverable(filepath: Path, spec: DeliverableSpec) -> ValidationResult:
    # TIER 1: Syntax (necessary but insufficient)
    syntax_ok = check_syntax(filepath)
    
    # TIER 2: Contract compliance (interface + behavior)
    contract_ok = check_contract_compliance(filepath, spec.interface)
    
    # TIER 3: Functional completeness (delivers what spec promises)
    functional_ok = run_functional_tests(filepath, spec.test_cases)
    
    # TIER 4: Character alignment (honors agent's constitution)
    character_ok = check_character_alignment(filepath, spec.constitution_principles)
    
    return ValidationResult(
        passed=all([syntax_ok, contract_ok, functional_ok, character_ok]),
        tiers={
            "syntax": syntax_ok,
            "contract": contract_ok,
            "functional": functional_ok,
            "character": character_ok
        }
    )
```

## Tier Details

### Tier 1: Syntax
- Language-specific: `python -m py_compile`, `node --check`, `cargo check`, `go build`
- Binary pass/fail
- **Insufficient alone** — empty function passes syntax

### Tier 2: Contract Compliance
- Function signatures match interface spec
- Return types match (or compatible)
- Error envelope format: `{success, data, error: {code, message}, meta: {requestId, timestamp}}`
- Async signatures properly handled
- Config schema validation

### Tier 3: Functional Completeness
- Runs spec's test cases (provided in checklist/blueprint)
- Handles happy path + error cases
- Meets performance budgets (p95 < 500ms, etc.)
- No partial implementations — delivers full spec promise

### Tier 4: Character Alignment
- Honors agent's constitution principles
- Respects boundaries (no unauthorized workspace access)
- Completes what it starts (no partial deliveries)
- Cites sources (traceability)
- Durability over speed

## Phase Validator Template

```python
#!/usr/bin/env python3
"""Phase {n} Validator — {Phase Title}"""

import sys
from pathlib import Path

project_root = Path(sys.argv[1]).parent.parent

checks = [
    # (relative_path, deliverable_spec)
    ("src/config/index.js", "ConfigLoader with 25+ params, env var support, defaults"),
    ("src/services/logger.js", "Pino structured logging, child loggers, correlation IDs, auto-redaction"),
    ("src/services/metrics.js", "Counter, histogram, gauge, rolling window stats, structured export"),
    ("src/services/health.js", "Subsystem status, latency tracking, aggregate health determination"),
    ("src/services/circuit-breaker.js", "3-state machine (closed/open/half-open), configurable thresholds, fallback activation"),
    (".env.example", "All 25+ env vars documented with descriptions"),
    ("CHANGELOG.md", "CL-001 through CL-XXX present, append-only format"),
    ("package.json", "type: module, scripts: start, dev, test, test:unit, test:integration, test:e2e, test:coverage, demo, lint"),
]

def validate_deliverable(filepath: Path, spec: str) -> bool:
    """Implement Tier 1-4 validation for this deliverable."""
    # Tier 1: Syntax
    if not check_syntax(filepath):
        print(f"✗ {filepath}: Syntax check failed")
        return False
    
    # Tier 2: Contract - verify interface exists
    if not check_contract(filepath, spec):
        print(f"✗ {filepath}: Contract compliance failed")
        return False
    
    # Tier 3: Functional - run phase tests
    if not run_phase_tests(filepath, spec):
        print(f"✗ {filepath}: Functional tests failed")
        return False
    
    # Tier 4: Character - verify constitutional alignment
    if not check_character_alignment(filepath):
        print(f"✗ {filepath}: Character alignment failed")
        return False
    
    print(f"✓ {filepath}: {spec}")
    return True

all_pass = all(validate_deliverable(project_root / path, spec) for path, spec in checks)
sys.exit(0 if all_pass else 1)
```

## Why This Matters

| Approach | Catches |
|----------|---------|
| Syntax only | 5% of defects |
| + Contract | 35% of defects |
| + Functional | 85% of defects |
| + Character | 99% of defects (including boundary violations, partial deliveries) |

**Validation = "Does this deliver what the phase promises?"**
**Syntax = "Is this valid code?"**

These are fundamentally different questions.