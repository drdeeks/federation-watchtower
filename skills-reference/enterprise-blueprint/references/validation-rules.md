# Validation Rules Reference

## Document Structure Validation

### Required Parts (FAIL if missing)
- PART I — System Overview
- PART II — Module Registry
- PART III — Specifications
- PART IV — Data Architecture
- PART V — Change Control
- PART VI — Implementation Checklist
- PART VII — Quality & Compliance

### Rollback Tags
Format: `> **Rollback Tag:** \`[TAG-NAME-v1]\``
- Must appear on each major section
- Tag format: `[SECTION-NAME-v1]` or `[PHASE-N-v1]` or `[MOD-NNN-v1]`
- Minimum 6 section rollback tags
- Minimum 1 PHASE rollback tag per phase

### Module Registry
- Each module: MOD-NNN (NNN = 3-digit zero-padded)
- Required columns: Module ID, Name, Purpose, Feature Flag, Rollback Tag
- Feature Flag format: FEAT_UPPER_SNAKE_CASE
- Minimum 3 modules defined

### Screen Specifications
- Each screen: SCR-NNN (NNN = 3-digit zero-padded)
- Required fields: SCREEN ID, MODULE REF, ROLLBACK TAG, FEATURE FLAG
- Required sections: Purpose, Components, Rules, Error States, Fallback

### Data Architecture
- SQL schemas with proper types (TEXT, TIMESTAMP, JSONB, SERIAL)
- API Contracts: Endpoint, Method, Description, Request, Response
- Migration naming: `V{NNN}__<kebab-case>.sql` + rollback file

### Change Log
Each entry requires 9 fields:
1. Date (ISO 8601 UTC)
2. Contributor
3. Modules [array]
4. Section Tags [array]
5. Files Changed [array]
6. Description (multi-line)
7. Tests Passing [array]
8. Phase
9. Rollback Ref (git commit hash)

Contributor Rules:
1. All changes require CL entry
2. No direct edits without CL entry
3. Append-only — corrections via "Amends CL-NNN"
4. Must cite Module ID + Section Tag
5. Feature flags declared before implementation
6. No phase advance without validation gate PASS
7. Rollback tags updated in same commit

## Validation Script Behavior

### Pass Criteria
- All FAIL checks must PASS
- WARN checks may PASS or FAIL
- 0 FAIL = Enterprise Grade

### Warning Tolerance
- Table of contents missing
- Test coverage target not specified
- Non-critical placeholders

### Fail Fast
- Missing PART sections
- No Module ID column in registry
- No Feature Flag column
- No CHANGE LOG section
- No CL entries

## Testing Requirements
- Unit: ≥ 80% (pytest, bats)
- Integration: 100% critical paths
- E2E: 100% critical user flows
- Security: 100% critical paths

## Performance Budgets
- Model Load Time: < 60s (8B GGUF)
- Model Handoff: < 30s (swap)
- API Response (p95): < 200ms
- Agent Creation: < 10s
- Crew Creation: < 30s
- USB Plug-in → Agent Ready: < 120s