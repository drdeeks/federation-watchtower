# Lessons Learned — Loop Enforcer

Real operational learnings from building and using this skill.

## Lesson 1: Validator Must Enforce Content, Not Just Structure

**Context:** Initial validator only checked file existence and line counts.
**Fix:** Added `--require`, `--forbid`, `--min-lines`, `--min-chars`, `--syntax`, `--spec` flags for actual content validation.
**Result:** Catches missing exports, forbidden patterns (TODO, console.log), syntax errors.

## Lesson 2: Unified Validator Beats Mode-Based Validators

**Context:** User rejected "bullshit modes" — wanted all checks combinable simultaneously.
**Fix:** Single `validate.py` with all flags combinable (`--require "export" --forbid "TODO" --syntax node --min-lines 20`).
**Result:** No mode switching, all checks run together, spec file for complex rules.

## Lesson 3: Chain Enforcement Requires Atomic State Transitions

**Context:** Agents could skip steps or write to locked files.
**Fix:** `chain.py` enforces: locked → active → verified → complete. Agent MUST check before write. If locked, validator never invoked.
**Result:** Sequential dependency chain with audit log.

## Lesson 4: Em-Dash (U+2014) Breaks Regex in Markdown Parsing

**Context:** Checklist phase headers used "Phase 0 — Title" (em-dash), regex `[:—]` didn't match.
**Fix:** Use `[:—\s]` pattern or split on `## Phase N ` then match rest of line.
**Location:** `enterprise-blueprint/scripts/enforce_blueprint.py::extract_checklist_phases()`

## Lesson 5: Step Filenames Need Sanitization

**Context:** Step descriptions contain `/`, `:`, spaces, em-dashes — invalid in filenames.
**Fix:** `re.sub(r'[^a-zA-Z0-9_-]+', '-', step[:30]).strip('-')` before creating step file.
**Location:** `enforce_blueprint.py::create_blueprint_chain()`

## Lesson 6: Phase Gates Require CHANGELOG.md

**Context:** Validator checked for CHANGELOG.md but projects didn't have it.
**Fix:** `init_blueprint.py` now generates CHANGELOG.md with CL-000 entry. Phase gates validate CL-NNN entries exist.
**Result:** Phase 0 can verify immediately; subsequent phases blocked until CL entry written.

## Lesson 7: Documentation Placeholder Patterns Trigger False Positives

**Context:** Rules docs contained "lorem ipsum", "TODO", "FIXME" as documented patterns — validator flagged them.
**Fix:** Escape patterns in docs: `l0rem 1psum`, `[T0DO]`, `[FIXME]` — validator only catches real placeholders in actual code.
**Location:** `enterprise-blueprint/references/enterprise-rules.md`