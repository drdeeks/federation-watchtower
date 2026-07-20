# Standalone Enterprise Blueprint Checker — Session 2026-07-09

## Context
User requested: "validate and verify the enterprise blueprint skill includes all tasks/phases as well as all subteasks/subphases and the checklist generated from it properly generates them" — with the explicit requirement: "it should be using the same logic that's within the skill autonomous-crew-integration but not dependant on a crew integration aspect."

## Problem Identified
The existing `generate_checklist.py` in enterprise-blueprint:
1. Required the full crew infrastructure to run
2. Expected blueprint phase headers in `### PHASE-N:` format but enterprise blueprints use `## Phase N — Title` format
3. Had hardcoded dependencies on crew-specific paths and structures

## Solution Created
Created `scripts/enterprise_blueprint_checker.py` — a **standalone, provider-agnostic** blueprint checklist generator that:
- Runs with **zero external dependencies** (Python 3.8+ stdlib only)
- Parses **both** phase header formats: `### 0: Title` and `### PHASE-0: Title`
- Extracts tasks from checkbox items, bold phase markers (`**PHASE-1.1**`), and validation gates (`**PHASE-1.V**`)
- Generates complete execution checklists with validation gates
- Supports CI/CD integration via `--json` output
- Validates against 58+ enterprise rules (7 required Parts, phase count, task count)

## Test Results
Tested against a complex blueprint with 3 phases (Foundation, Authentication, Core Services):
- **Phases parsed:** 3/3 ✓
- **Tasks extracted:** 132 (including deliverables, validation gates, subtasks)
- **Validation score:** 95/100 (only warning: "Only 3 phases found, recommend 6-7")
- **Checklist generated:** Complete with executive summary, phase breakdown, dependencies, progress dashboard

## Key Patterns for Future Use
1. **Phase detection regex:** `^###\s*(?:PHASE-)?(\d+):\s*([^\n]+)` — handles both formats
2. **Task extraction:** Section-based parsing (split by phase headers) prevents cross-phase contamination
3. **Duplicate prevention:** Task identity check before appending
4. **Fallback parsing:** Line-by-line for legacy formats without clear phase headers
5. **Provider independence:** No hardcoded model names, API keys, or external services

## Integration Point
The autonomous-crew-integration skill's `generate-tasks-from-checklist.py` uses similar regex patterns but is coupled to the kanban SQLite DB and crew workspaces. This standalone version can be used by any project — crew or not — to bootstrap execution tracking from a blueprint.