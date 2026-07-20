# Checklist Generator Priority Chain

The `generate_checklist.py` script uses a 3-try priority chain to extract phases from a blueprint. Understanding this priority chain is critical to getting the right output.

## The 3-Try Priority Chain

### Try 1: Part VI Complex Pattern

**Trigger:** Finds `# PART VI — MASTER IMPLEMENTATION CHECKLIST` header.

**Pattern:** 
```python
phase_pattern = r"### (PHASE-\d+)\s*\n\n\*\*Section Tag:\*\* ... \*\*Assigned Agent:\*\* ... \n\n### Prerequisites\n\n... \n\n### Deliverables\n\n... \n\n### Validation Gate\n\n> ... \n\n### Rollback Procedure\n\n(.*?)(?:\n\n---\n\n## |\n\n---\n\n# PART VII|\Z)"
```

**Known bug:** The regex starts with `### PHASE-` (level 3) but the phase separator expects `## ` (level 2). This means only the FIRST phase is extracted from Part VI; subsequent phases are missed. When this happens, the returned 1-phase early-exit blocks all other tries.

**Workaround:** Ensure the Part VI pattern does NOT match at all (so the code falls through to try 2/3). This happens naturally when your Part VI format uses `### PHASE-N: Title` (with a colon/title after the header) instead of the bare `### PHASE-N` plus `**Section Tag:**` structure the regex expects.

### Try 2: SPEC Headers

**Trigger:** Any `### SPEC-(\d+):` header anywhere in the blueprint.

**Pattern:** `### SPEC-(\d+): ([^>\n]+)`

**Behavior:** Groups SPECs by module (extracted via `**Module Ref** | MOD-XXX` format). Creates one phase per module. If no modules match (all MOD-UNKNOWN), creates 1 phase with all SPECs as tasks.

**Blocks:** Try 3 (PHASE headers) will NOT run if try 2 finds any SPEC headers.

**Workaround:** If you want PHASE-based output instead of SPEC-based, rename SPEC headers to NOT match the regex, e.g.:
- `### Spec-NNN:` (lowercase 'p')
- `### FEATURE SPEC-NNN:`
- `### FS-NNN:`

### Try 3: PHASE Headers (Fallback)

**Trigger:** No SPEC headers found.

**Pattern:** `### PHASE-(\d+)[a-z]?: ([^>\n]+)`

**Behavior:** Finds all `### PHASE-N: Title` headers in the document. Extracts tasks from `**Deliverables**` sections (if the section boundary captures them correctly).

**Section boundary bug:** Uses `self.content.find("### ", section_start + 1)` to find the end of each phase section. This finds the NEXT `### ` header in the entire document, which may be `### Prerequisites` (a sub-header within the same phase) rather than the next phase header. This truncates the section to just the header + metadata lines, missing deliverables and tasks. Result: each phase gets a single fallback task "Implement {title}" instead of extracted deliverables.

## Summary Table

| Try | What it matches | When it runs | Output type | 
|-----|----------------|-------------|-------------|
| 1 (Part VI) | `### PHASE-0\n\n**Section Tag:**` | After `# PART VI —` header | Phases from Part VI (but only 1st phase) |
| 2 (SPEC) | `### SPEC-001:` | Always if any SPEC headers exist | One phase per module |
| 3 (PHASE) | `### PHASE-0: Setup` | Only if SPEC headers are absent | Phases from headers, fallback tasks |

## Recommended Workflow

For complex blueprints with both SPEC sections (Part III) and Phase sections (Part VI):

1. Use `### Spec-NNN:` (lowercase) for Part III SPEC headers to avoid try 2 matching
2. Use `### PHASE-N: Title` format for Part VI phase headers with unique titles
3. Write Part VI deliverables manually as checklist items
4. Run `generate_checklist.py` — it will use try 3 and produce PHASE-based output
5. The tasks will be generic ("Implement {title}") — accept this or write deliverables manually
