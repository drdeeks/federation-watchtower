# Lessons Learned — Loop Enforcer

Real operational learnings from building and using this skill.

## Lesson 1: Validator Must Enforce Content, Not Just Structure

**Context:** Initial validator only checked file existence, line count, and placeholder patterns.

**Problem:** Agent could write garbage (2 lines, no class, has placeholder) and pass verification.

**Fix:** Unified `validate.py` with required patterns, forbidden patterns, min chars, syntax check, custom checks.

**Takeaway:** A chain enforcer is only as good as its validator. If the validator doesn't enforce what the file SHOULD contain, the chain is theater.

## Lesson 2: Structural Validation Does Not Equal Semantic Quality

**Context:** Skill passed `validate.py` (structural) but failed manual review per `standards.md`.

**Problem:** Automated validator only checks file counts and extensions, not content quality.

**Fix:** Must run `verify_sources.py`, manual review checklist, and actually test scripts.

**Takeaway:** "Enterprise Grade" from structural validator is necessary but not sufficient.

## Lesson 3: Chain State Must Be Atomic

**Context:** Early versions wrote state file directly, causing corruption on crash.

**Problem:** Half-written state left chain in inconsistent state.

**Fix:** Write to `.tmp` then `os.replace()` for atomic writes.

**Takeaway:** State persistence is a critical section. Treat it like one.

## Lesson 4: Validators Need Config, Not Hardcoded Rules

**Context:** First version had three separate validator scripts for different checks.

**Problem:** Unmaintainable, couldn't combine checks, wasted tokens.

**Fix:** Single `validate.py` with composable flags and JSON spec file.

**Takeaway:** Configurable greater than hardcoded. One script with options beats multiple scripts.

## Lesson 5: Agent Must Check Before Write

**Context:** Without enforcement, agents write to locked files.

**Problem:** Chain state says "locked" but agent writes anyway.

**Fix:** Chain state is the source of truth. Agent MUST call `chain.py check` before any file write. If locked → STOP.

**Takeaway:** The tool enforces; the agent must obey. Both parts required.

## Validator Design Principles (Encode in Future Skills)

1. **Composable flags over modes** — every check independently enableable
2. **Spec file for complexity** — JSON spec for CI/CD, flags for ad-hoc
3. **Descriptive errors** — "Missing required: export class" not "Validation failed"
4. **Syntax checking built-in** — node, python, json auto-detected
5. **Custom checks extensible** — regex, function_count, class_count, export_count
6. **Zero dependencies** — Python stdlib only, works anywhere

## Chain Enforcer Patterns That Work

| Pattern | Use Case |
|---|---|
| Sequential build | src/config → src/db → src/api → src/routes |
| TDD pairs | src/utils.js → tests/utils.test.js → src/db.js → tests/db.test.js |
| Blueprint phases | phase1.md → phase2.md → phase3.md (with phase validators) |
| Additive enforcement | Validator checks git diff for deletions on completed steps |

## Files That Embody These Lessons

- `scripts/validate.py` — unified validator with all checks composable
- `scripts/chain.py` — enforcement engine with atomic state + audit log
- `references/agent-integration.md` — agent MUST check before write
- `references/design-principles.md` — additive-only, verification gates, atomic writes