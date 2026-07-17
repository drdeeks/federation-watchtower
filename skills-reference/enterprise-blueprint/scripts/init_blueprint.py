#!/usr/bin/env python3
"""
enterprise-blueprint — Initialize a new blueprint project

Creates blueprint.md and checklist.md side by side, pre-populated with
all required enterprise sections, rollback tags, module registry placeholder,
change log stub, and phase scaffolding.

Usage:
    python3 scripts/init_blueprint.py <project-name> --path <output-dir>
    python3 scripts/init_blueprint.py <project-name> --path <output-dir> --phases "Pre-Build,Foundation,Auth,Core"
    python3 scripts/init_blueprint.py <project-name> --path <output-dir> --dry-run
    python3 scripts/init_blueprint.py <project-name> --path <output-dir> --json
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

VERSION = "1.0"

DEFAULT_PHASES = [
    "Phase 0: Pre-Build",
    "Phase 1: Foundation",
    "Phase 2: Authentication & Identity",
    "Phase 3: Core Feature Build",
    "Phase 4: Integration Layer",
    "Phase 5: Testing & Hardening",
    "Phase 6: Launch & Live Ops",
]


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def today():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def slugify(text):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower().strip())
    return s.strip("-")


def flag_name(phase_name):
    slug = slugify(re.sub(r"^phase\s*\d+[:\s]*", "", phase_name, flags=re.IGNORECASE))
    return "FEAT_" + slug.upper().replace("-", "_")


def phase_tag(index):
    return f"[PHASE-{index}-v1]"


# ── Blueprint generation ───────────────────────────────────────────────────────

def blueprint_phase_section(i, phase):
    tag = phase_tag(i)
    flag = flag_name(phase)
    lines = [
        f"## {phase}",
        "",
        f"**Section Tag:** `{tag}`",
        f"**Feature Flag:** `{flag}`",
        "**Assigned Agent:** _unassigned_",
        "",
        "### Prerequisites",
        "",
        f"All Phase {i - 1 if i > 0 else 'N/A'} items must be complete, tests passing, and change log entry written.",
        "",
        "### Deliverables",
        "",
        "- [ ] [Define deliverable 1]",
        "- [ ] [Define deliverable 2]",
        "",
        "### Validation Gate",
        "",
        "> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.",
        "",
        "### Rollback Procedure",
        "",
        "1. Disable relevant feature flags immediately (no deployment required).",
        "2. Assess whether a code rollback or flag-only disable resolves the issue.",
        "3. If database migration rollback is required, obtain two-contributor approval.",
        "4. Write a post-incident change log entry within 24 hours.",
        "",
        "---",
        "",
    ]
    return "\n".join(lines)


def generate_blueprint(project_name, phases):
    d = today()
    phase_block = "".join(blueprint_phase_section(i, p) for i, p in enumerate(phases))

    parts = []
    parts.append(f"# {project_name} — ENTERPRISE BLUEPRINT")
    parts.append(f"## Version 1.0 | Document Class: MASTER SPECIFICATION")
    parts.append(f"### Generated: {d}")
    parts.append("")
    parts.append("> **READ FIRST — DOCUMENT AUTHORITY**")
    parts.append("> This document is the single source of truth. No feature may be built,")
    parts.append("> no schema migrated, and no API changed without this document as the")
    parts.append("> authoritative reference. All contributors MUST read Part V (Change")
    parts.append("> Control Protocol) before touching any file. This document's change")
    parts.append("> log is APPEND-ONLY. Prior sections may only be updated via a formal")
    parts.append("> amendment with a corresponding CL entry.")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("## TABLE OF CONTENTS")
    parts.append("")
    parts.append("```")
    parts.append("PART I    — SYSTEM OVERVIEW & ARCHITECTURE")
    parts.append("PART II   — MODULE REGISTRY")
    parts.append("PART III  — SCREEN & FEATURE SPECIFICATIONS")
    parts.append("PART IV   — DATA ARCHITECTURE")
    parts.append("PART V    — CHANGE CONTROL PROTOCOL")
    parts.append("PART VI   — MASTER IMPLEMENTATION CHECKLIST")
    parts.append("PART VII  — QUALITY & COMPLIANCE STANDARDS")
    parts.append("```")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# PART I — SYSTEM OVERVIEW & ARCHITECTURE")
    parts.append("")
    parts.append("> **Rollback Tag:** `[SYS-OVERVIEW-v1]`")
    parts.append("")
    parts.append("## 1.1 Vision Statement")
    parts.append("")
    parts.append("[Describe the product vision in 2-3 sentences. What does it do?")
    parts.append("Who uses it? What is the defining principle of the system?]")
    parts.append("")
    parts.append("## 1.2 High-Level Architecture")
    parts.append("")
    parts.append("```")
    parts.append("┌─────────────────────────────────────────────────────────────┐")
    parts.append("│                     ENTRY LAYER                              │")
    parts.append("└────────────────────┬────────────────────────────────────────┘")
    parts.append("                     │")
    parts.append("┌────────────────────▼────────────────────────────────────────┐")
    parts.append("│                  APPLICATION LAYER                           │")
    parts.append("└────────────────────┬────────────────────────────────────────┘")
    parts.append("                     │")
    parts.append("┌────────────────────▼────────────────────────────────────────┐")
    parts.append("│                   DATA LAYER                                 │")
    parts.append("└─────────────────────────────────────────────────────────────┘")
    parts.append("```")
    parts.append("")
    parts.append("## 1.3 Tech Stack")
    parts.append("")
    parts.append("| Layer | Technology | Rationale |")
    parts.append("|---|---|---|")
    parts.append("| [Layer] | [Technology] | [Why this was chosen] |")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# PART II — MODULE REGISTRY")
    parts.append("")
    parts.append("> **Rollback Tag:** `[MODULE-REGISTRY-v1]`")
    parts.append("> **Rule:** Every change log entry MUST reference at least one Module ID.")
    parts.append("")
    parts.append("| Module ID | Name | Description | Feature Flag |")
    parts.append("|---|---|---|---|")
    parts.append("| MOD-001 | [Name] | [Description] | FEAT_[NAME] |")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# PART III — SCREEN & FEATURE SPECIFICATIONS")
    parts.append("")
    parts.append("> **Rollback Tag:** `[SPECS-v1]`")
    parts.append("> Each specification follows this format:")
    parts.append("> ID, Module Ref, Rollback Tag, Feature Flag, Purpose,")
    parts.append("> Components, Rules, Error States, Fallback.")
    parts.append("")
    parts.append("[Insert screen and feature specifications here]")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# PART IV — DATA ARCHITECTURE")
    parts.append("")
    parts.append("> **Rollback Tag:** `[DATA-ARCH-v1]`")
    parts.append("> **Rule:** All schema changes require a migration file named")
    parts.append("> `YYYYMMDD_NNN_description.sql` with a corresponding rollback file,")
    parts.append("> and must be referenced in the Global Change Log.")
    parts.append("")
    parts.append("## 4.1 Core Database Schemas")
    parts.append("")
    parts.append("[Insert SQL schemas here]")
    parts.append("")
    parts.append("## 4.2 API Contract Specifications")
    parts.append("")
    parts.append("All API endpoints follow: `/api/v1/{resource}/{action}`.")
    parts.append("All responses follow the standard error envelope:")
    parts.append("  success, data, error (code + message), meta (requestId + timestamp).")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# PART V — CHANGE CONTROL PROTOCOL")
    parts.append("")
    parts.append("> **Rollback Tag:** `[CHANGE-CONTROL-v1]`")
    parts.append("> **This section is permanent and non-negotiable.**")
    parts.append("> Every contributor must read this section before making any change.")
    parts.append("")
    parts.append("## Change Log Entry Format")
    parts.append("")
    parts.append("Every entry MUST include all fields below. Entries are permanent.")
    parts.append("No entry may be modified or deleted after writing.")
    parts.append("")
    parts.append("```")
    parts.append("Date        : YYYY-MM-DD HH:MM UTC")
    parts.append("Contributor : [name/handle]")
    parts.append("Modules     : [MOD-XXX, ...]")
    parts.append("Section Tags: [[TAG-NAME-v1], ...]")
    parts.append("Files Changed: [every file changed]")
    parts.append("Description : [What changed and why — minimum 3 sentences]")
    parts.append("Tests Passing: [test names, or 'none — pre-build']")
    parts.append("Phase       : [PHASE-N]")
    parts.append("Rollback Ref: [git commit hash or migration rollback filename]")
    parts.append("```")
    parts.append("")
    parts.append("## Contributor Rules")
    parts.append("")
    parts.append("1. No code merged without a change log entry in the same PR.")
    parts.append("2. No database migration without a rollback migration file.")
    parts.append("3. Feature flags required for every Phase 2+ feature.")
    parts.append("4. Minimum: 1 unit test per new function, 1 integration test per endpoint.")
    parts.append("5. `CHANGELOG.md` CI append-only check must pass on every PR.")
    parts.append("6. No contributor may modify or delete an existing change log entry.")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# PART VI — MASTER IMPLEMENTATION CHECKLIST")
    parts.append("")
    parts.append(phase_block)
    parts.append("---")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# PART VII — QUALITY & COMPLIANCE STANDARDS")
    parts.append("")
    parts.append("> **Rollback Tag:** `[QUALITY-v1]`")
    parts.append("")
    parts.append("## Error Handling Standards")
    parts.append("")
    parts.append("1. Graceful degradation for all non-critical services.")
    parts.append("2. User-facing messages: friendly, non-technical, no stack traces exposed.")
    parts.append("3. Internal logging: full context — requestId, userId, error code, stack.")
    parts.append("4. Retry: exponential backoff on external calls (3 retries: 1s, 2s, 4s).")
    parts.append("5. Circuit breaker: 10 failures in 60s opens circuit for 5 minutes.")
    parts.append("")
    parts.append("## Testing Requirements")
    parts.append("")
    parts.append("- Unit tests: 80% line coverage on all core modules.")
    parts.append("- Integration tests: every API endpoint has success + error case.")
    parts.append("- E2E tests: all critical user flows have passing automated tests.")
    parts.append("")
    parts.append("## Performance Budgets")
    parts.append("")
    parts.append("| Metric | Budget |")
    parts.append("|---|---|")
    parts.append("| Page load LCP (3G) | < 2.0 seconds |")
    parts.append("| API response time p95 | < 500ms |")
    parts.append("| Background job completion | < 60 seconds |")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("# CHANGE LOG")
    parts.append("")
    parts.append("> This section is append-only. No entry may be modified or deleted.")
    parts.append("")
    parts.append("## CL-000 — Document Initialization")
    parts.append("")
    parts.append("```")
    parts.append(f"Date        : {d}")
    parts.append("Contributor : [author]")
    parts.append("Modules     : [MOD-001]")
    parts.append("Section Tags: [[PHASE-0-v1]]")
    parts.append("Files Changed: [blueprint.md, checklist.md]")
    parts.append(f"Description : Initial blueprint created via enterprise-blueprint skill.")
    parts.append(f"              Project: {project_name}. All sections pre-populated with")
    parts.append("              required enterprise structure awaiting content population.")
    parts.append("Tests Passing: none — pre-build")
    parts.append("Phase       : PHASE-0")
    parts.append("Rollback Ref: N/A — initial document creation")
    parts.append("```")

    return "\n".join(parts) + "\n"


def generate_changelog(project_name, phases):
    """Generate standalone CHANGELOG.md from blueprint's changelog section."""
    d = today()
    parts = []
    parts.append(f"# {project_name} — CHANGELOG")
    parts.append("")
    parts.append("> This file is the append-only change log. No entry may be modified or deleted.")
    parts.append("> All entries must follow the format defined in blueprint.md Part V.")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("## CL-000 — Document Initialization")
    parts.append("")
    parts.append("```")
    parts.append(f"Date        : {d}")
    parts.append("Contributor : [author]")
    parts.append("Modules     : [MOD-001]")
    parts.append("Section Tags: [[PHASE-0-v1]]")
    parts.append("Files Changed: [blueprint.md, checklist.md, CHANGELOG.md]")
    parts.append(f"Description : Initial blueprint created via enterprise-blueprint skill.")
    parts.append(f"              Project: {project_name}. All sections pre-populated with")
    parts.append("              required enterprise structure awaiting content population.")
    parts.append("Tests Passing: none — pre-build")
    parts.append("Phase       : PHASE-0")
    parts.append("Rollback Ref: N/A — initial document creation")
    parts.append("```")
    parts.append("")
    return "\n".join(parts) + "\n"


# ── Checklist generation ───────────────────────────────────────────────────────

def checklist_phase_section(i, phase):
    tag = phase_tag(i)
    flag = flag_name(phase)
    prior = f"Phase {i - 1}" if i > 0 else "N/A"
    lines = [
        f"## {phase}",
        "",
        f"**Section Tag:** `{tag}` | **Feature Flag:** `{flag}`",
        "**Status:** `NOT STARTED` | **Assigned Agent:** _unassigned_",
        f"**Prerequisite:** {prior} status must be `COMPLETE` and change log entry written.",
        "",
        "### Pre-Phase Gate",
        "",
        "Confirm all of the following before starting:",
        "",
        f"- [ ] Prior phase change log entry is written and appended to `CHANGELOG.md`.",
        "- [ ] All prior phase tests are passing in CI.",
        f"- [ ] Feature flags for `{flag}` are set to `disabled` in production.",
        "- [ ] Database migration rollback files for this phase are prepared.",
        "- [ ] Agent assignment for this phase is confirmed in `assignments.json`.",
        "",
        "### Implementation Steps",
        "",
        "> Each step must be completed, tested, and logged before proceeding.",
        "",
        "- [ ] **Step 1:** [First concrete implementation action]",
        "  - _Example:_ Create migration `YYYYMMDD_001_[table_name].sql` with rollback `_ROLLBACK.sql`.",
        "  - _Validation:_ Migration applies and rolls back cleanly on a fresh database.",
        "  - _Rollback Ref:_ Execute `YYYYMMDD_001_ROLLBACK.sql`.",
        "",
        "- [ ] **Step 2:** [Next implementation action]",
        "  - _Example:_ Implement `POST /api/v1/[resource]` with standard error envelope.",
        "  - _Validation:_ Unit test passes: `[module].[feature].[scenario]`.",
        "  - _Rollback Ref:_ Revert the route file; redeploy.",
        "",
        "- [ ] **Step 3:** [Continue for all steps specific to this phase]",
        "  - _Example:_ Enable feature flag on staging; run smoke test suite.",
        "  - _Validation:_ All Phase smoke tests pass; no p95 regression > 20%.",
        "  - _Rollback Ref:_ Disable feature flag; no code change required.",
        "",
        "### Phase Validation Gate",
        "",
        "All of the following must be true before this phase is marked `COMPLETE`:",
        "",
        "- [ ] All implementation steps above are checked.",
        "- [ ] All tests introduced in this phase are passing in CI.",
        f"- [ ] `{flag}` is confirmed enabled on staging, disabled on production.",
        "- [ ] Change log entry for this phase is written and appended.",
        "- [ ] Blueprint updated to reflect any deviations from specification.",
        "- [ ] Assigned agent has signed off (name + date below).",
        "",
        "### Agent Sign-Off",
        "",
        "```",
        f"Phase {i} Sign-Off:",
        "  Agent     : _________________",
        "  Date      : _________________",
        "  Notes     : _________________",
        "```",
        "",
        "---",
        "",
    ]
    return "\n".join(lines)


def generate_checklist(project_name, phases):
    d = today()
    phase_block = "".join(checklist_phase_section(i, p) for i, p in enumerate(phases))

    parts = []
    parts.append(f"# {project_name} — ENTERPRISE CHECKLIST")
    parts.append(f"## Version 1.0 | Coexists with: blueprint.md")
    parts.append(f"### Generated: {d}")
    parts.append("")
    parts.append("> **CHECKLIST AUTHORITY**")
    parts.append("> This checklist is the enforcement companion to blueprint.md. It may")
    parts.append("> not diverge — every blueprint amendment requires a corresponding")
    parts.append("> checklist update in the same commit. Checked items are immutable;")
    parts.append("> corrections require a new line with explanation, never erasure.")
    parts.append(">")
    parts.append("> **Status values:** `NOT STARTED` | `IN PROGRESS` | `BLOCKED` | `COMPLETE`")
    parts.append("> **Blocking rule:** No phase may begin until the prior phase is `COMPLETE`.")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append("## GLOBAL PREREQUISITES")
    parts.append("")
    parts.append("Before any phase begins:")
    parts.append("")
    parts.append("- [ ] Repository created with `/app`, `/lib`, `/db`, `/contracts`, `/tests`, `/docs`.")
    parts.append("- [ ] `CHANGELOG.md` created with append-only CI enforcement check.")
    parts.append("- [ ] `global_change_log` database table created with INSERT-only trigger.")
    parts.append("- [ ] All module IDs registered in `modules` config table.")
    parts.append("- [ ] Feature flags system initialized; all flags default to `disabled`.")
    parts.append("- [ ] CI/CD pipeline configured: test → lint → build → staging deploy.")
    parts.append("- [ ] Monitoring and error tracking connected to staging environment.")
    parts.append("- [ ] `assignments.json` populated for at least Phase 0.")
    parts.append("")
    parts.append("---")
    parts.append("")
    parts.append(phase_block)
    parts.append("---")
    parts.append("")
    parts.append("## GLOBAL COMPLETION CRITERIA")
    parts.append("")
    parts.append("The project is production-complete when:")
    parts.append("")
    parts.append("- [ ] All phase statuses are `COMPLETE`.")
    parts.append("- [ ] All feature flags are enabled in production.")
    parts.append("- [ ] Performance budgets verified by load test (results in change log).")
    parts.append("- [ ] Security audit of all auth and payment flows is complete.")
    parts.append("- [ ] Data export and deletion (GDPR compliance) is verified.")
    parts.append("- [ ] Post-launch monitoring dashboards live and alerting configured.")
    parts.append("- [ ] Final change log entry written documenting the production launch.")

    return "\n".join(parts) + "\n"


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Initialize an enterprise blueprint + checklist project."
    )
    parser.add_argument("project_name", help="Project name (used in headings)")
    parser.add_argument("--path", required=True, help="Output directory")
    parser.add_argument(
        "--phases",
        default=None,
        help="Comma-separated list of phase names (default: 7-phase standard set)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing files")
    parser.add_argument("--json", action="store_true", help="Output JSON statistics only")
    args = parser.parse_args()

    started = now_iso()
    phases = (
        [p.strip() for p in args.phases.split(",")]
        if args.phases
        else DEFAULT_PHASES
    )
    output_dir = Path(args.path)
    blueprint_path = output_dir / "blueprint.md"
    checklist_path = output_dir / "checklist.md"
    changelog_path = output_dir / "CHANGELOG.md"
    metadata_path = output_dir / "project.json"

    status = "dry_run" if args.dry_run else "success"
    error = None

    if not args.dry_run:
        try:
            output_dir.mkdir(parents=True, exist_ok=True)
            blueprint_path.write_text(
                generate_blueprint(args.project_name, phases), encoding="utf-8"
            )
            checklist_path.write_text(
                generate_checklist(args.project_name, phases), encoding="utf-8"
            )
            changelog_path.write_text(
                generate_changelog(args.project_name, phases), encoding="utf-8"
            )
            metadata = {
                "project": args.project_name,
                "slug": slugify(args.project_name),
                "phases": phases,
                "version": VERSION,
                "created_at": started,
                "blueprint": str(blueprint_path),
                "checklist": str(checklist_path),
                "changelog": str(changelog_path),
                "assignments": str(output_dir / "assignments.json"),
            }
            metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
        except Exception as exc:
            status = "failed"
            error = str(exc)

    result = {
        "operation": "init_blueprint",
        "timestamp": now_iso(),
        "status": status,
        "project": args.project_name,
        "details": {
            "phases": len(phases),
            "phase_names": phases,
            "output_dir": str(output_dir),
            "dry_run": args.dry_run,
            "files_created": (
                [] if args.dry_run
                else [str(blueprint_path), str(checklist_path), str(changelog_path), str(metadata_path)]
            ),
        },
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
    }
    if error:
        result["error"] = error

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if args.dry_run:
            print("[DRY RUN] Would create:")
            print(f"  {blueprint_path}")
            print(f"  {checklist_path}")
            print(f"  {changelog_path}")
            print(f"  {metadata_path}")
            print(f"  Phases ({len(phases)}): {', '.join(phases)}")
        elif status == "success":
            print(f"[OK] Blueprint initialized: {output_dir}")
            print(f"  blueprint.md  → {blueprint_path}")
            print(f"  checklist.md  → {checklist_path}")
            print(f"  CHANGELOG.md  → {changelog_path}")
            print(f"  project.json  → {metadata_path}")
        else:
            print(f"[ERROR] {error}")
            sys.exit(1)

        print()
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
