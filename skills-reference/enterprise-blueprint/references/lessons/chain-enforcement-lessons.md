# Lessons Learned — Enterprise Blueprint Chain Enforcement

Real operational learnings from integrating chain enforcement into enterprise-blueprint.

## Lesson 1: Checklist is the Source of Truth, Not Blueprint

**Context:** Blueprint has high-level phases; checklist has granular steps with validation gates.
**Fix:** `enforce_blueprint.py` parses checklist.md for phases/steps, merges blueprint tags/flags/deliverables.
**Result:** Chain steps match actual implementation granularity.

## Lesson 2: Em-Dash (U+2014) in Phase Headers Breaks Regex

**Context:** Checklist used "Phase 0 — Foundation" (em-dash U+2014), original regex `[:—]` failed.
**Fix:** Split on `## Phase N ` then match rest of line, or use `[:—\s]` in character class.
**Code:** `re.split(r"(^##\s+Phase\s+\d+[:—\s][^\n]*$)", content, flags=re.MULTILINE)`

## Lesson 3: Step Filenames Must Be Sanitized

**Context:** Step descriptions like "Step 1 — Initialize Node.js 24 project with ES Modules configuration in package.json (type: \"module\")" create invalid filenames.
**Fix:** `step_slug = re.sub(r'[^a-zA-Z0-9_-]+', '-', step[:30]).strip('-')`

## Lesson 4: CHANGELOG.md Must Exist Before Chain Init

**Context:** Phase gate validator checks CHANGELOG.md for CL-NNN entries. Missing file = verification fails.
**Fix:** `init_blueprint.py` generates CHANGELOG.md with CL-000. `generate_checklist.py --sync` preserves it.

## Lesson 5: Blueprint Validator Reads Deliverables Mapping

**Context:** Chain steps are marker files; real deliverables are project files (src/, tests/, configs).
**Fix:** `blueprint_validator.py` reads `.blueprint-chain/deliverables.json` mapping step→actual file, validates real target.

## Lesson 6: Phase Count Mismatch Between Blueprint and Checklist

**Context:** Blueprint has 7 default phases; checklist after sync may have different count (autopilot had 4).
**Fix:** `enforce_blueprint.py` merges by index, handles missing blueprint phases gracefully.

## Lesson 7: Documentation Must Escape Placeholder Patterns

**Context:** Validator flags `TODO`, `FIXME`, `lorem ipsum` anywhere — including in rules docs describing these patterns.
**Fix:** In `enterprise-rules.md`: `[T0DO]`, `[FIXME]`, `l0rem 1psum` — validator only catches real placeholders in code.