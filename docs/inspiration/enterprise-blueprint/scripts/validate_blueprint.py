#!/usr/bin/env python3
"""
Blueprint Validation Script
Validates INTEGRATION_BLUEPRINT.md against enterprise requirements.
"""

import re
import sys
import json
from datetime import datetime
from pathlib import Path


class BlueprintValidator:
    def __init__(self, blueprint_path):
        self.path = Path(blueprint_path)
        self.content = self.path.read_text()
        self.results = []

    def check(self, name, condition, severity="FAIL", detail=""):
        passed = bool(condition)
        self.results.append({
            "name": name,
            "severity": severity,
            "passed": passed,
            "detail": detail if not passed else ""
        })
        return passed

    def run(self):
        # Document basics
        self.check("blueprint.md exists and is readable", self.path.exists() and self.path.is_file())
        
        # Version & Date
        self.check("Version number in document header", bool(re.search(r"Version:\s*", self.content)))
        self.check("Date in document header", bool(re.search(r"Date:\s*\d{4}-\d{2}-\d{2}", self.content)), "WARN")
        
        # READ FIRST preamble
        self.check("READ FIRST / Document Authority preamble", "READ FIRST" in self.content or "Document Authority" in self.content)

        # Required PARTs
        parts = ["PART I", "PART II", "PART III", "PART IV", "PART V", "PART VI", "PART VII"]
        for part in parts:
            self.check(f"Contains {part}", part in self.content)

        # Rollback tags
        phase_tags = len(re.findall(r"\[PHASE-\d+-v\d+\]", self.content))
        self.check("At least 1 PHASE rollback tag present", phase_tags >= 1)
        
        section_tags = len(re.findall(r"\[.*?-v\d+\]", self.content))
        self.check("6+ section rollback tags across the document", section_tags >= 6, "WARN")
        
        # Specific rollback tags
        required_tags = ["SYS-OVERVIEW-v1", "MODULE-REGISTRY-v1", "SPECS-v1", "DATA-ARCH-v1", "CHANGE-CONTROL-v1", "QUALITY-v1"]
        for tag in required_tags:
            self.check(f"Rollback tag [{tag}] present", tag in self.content, "WARN")

        # Module Registry
        mod_count = len(re.findall(r"MOD-\d{3}", self.content))
        self.check("At least 1 module defined (MOD-NNN)", mod_count >= 1)
        self.check("3+ modules defined", mod_count >= 3, "WARN")
        
        # Feature flags
        feat_count = len(re.findall(r"FEAT_[A-Z_]+", self.content))
        self.check("Feature flags (FEAT_*) referenced", feat_count >= 1)
        self.check("3+ feature flags defined", feat_count >= 3, "WARN")
        
        # Change Log
        self.check("CHANGE LOG section present", "CHANGE LOG" in self.content.upper())
        cl_count = len(re.findall(r"CL-\d{4}", self.content))
        self.check("At least one CL-NNN entry present", cl_count >= 1)
        
        # Data Architecture
        self.check("Database schema defined in Part IV", "CREATE TABLE" in self.content, "WARN")
        self.check("API contracts defined in Part IV", "/v1/" in self.content, "WARN")
        self.check("Migration naming convention stated", re.search(r"V\{NNN\}__", self.content), "WARN")
        
        # Quality Standards
        self.check("p95 performance budget specified", "p95" in self.content.lower(), "WARN")
        self.check("Test coverage target specified", "80%" in self.content or "coverage" in self.content.lower(), "WARN")
        self.check("Circuit breaker / retry policy specified", "circuit breaker" in self.content.lower() or "retry" in self.content.lower(), "WARN")
        
        # Placeholders
        todo_count = self.content.count("[TODO")
        self.check("No [TODO] markers remaining", todo_count == 0, "WARN")
        
        placeholder_count = self.content.count("TODO") + self.content.count("FIXME") + self.content.count("TBD") + self.content.count("WIP")
        self.check("Minimal unfilled placeholders", placeholder_count == 0, "WARN")
        
        # Document size
        line_count = len(self.content.splitlines())
        self.check("Document is substantial (>100 lines)", line_count > 100, "WARN")

        # Summary
        total = len(self.results)
        passed = sum(1 for r in self.results if r["passed"])
        failed = sum(1 for r in self.results if not r["passed"] and r["severity"] == "FAIL")
        warned = sum(1 for r in self.results if not r["passed"] and r["severity"] == "WARN")

        return {
            "operation": "validate",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "blueprint": str(self.path),
            "checks": self.results,
            "summary": {"total": total, "passed": passed, "failed": failed, "warned": warned},
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
        }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 validate_blueprint.py <blueprint.md> [--json]")
        sys.exit(1)
    
    blueprint_path = sys.argv[1]
    as_json = "--json" in sys.argv
    
    validator = BlueprintValidator(blueprint_path)
    result = validator.run()
    
    if as_json:
        print(json.dumps(result, indent=2))
    else:
        for check in result["checks"]:
            status = "✓" if check["passed"] else "✗"
            sev = check["severity"]
            print(f"[{status}] [{sev}] {check['name']}")
            if check["detail"]:
                print(f"       {check['detail']}")
        
        print(f"\nSummary: {result['summary']['passed']}/{result['summary']['total']} passed, "
              f"{result['summary']['failed']} failed, {result['summary']['warned']} warned")