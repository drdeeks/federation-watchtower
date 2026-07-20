# Validation Lessons

## Lesson 1: Progressive Disclosure
Always keep the SKILL.md body ≤500 lines. Move detailed content to
references/ and link it; the skill description carries the triggers.

## Lesson 2: Enterprise Structure
Enterprise skills require:
- 3+ substantive scripts in scripts/
- 5+ substantive references in references/
- 7 metadata tags (5 for basic tier)
- a functional `__init__.py` with skill metadata
- `references/lessons/` is OPTIONAL in both tiers — but if lessons exist,
  that is the only place they may live

## Lesson 3: External Source Verification
Every external tool/component must have official documentation linked, and
links must resolve (the validator checks internal links; verify_sources.py
checks external ones).

## Lesson 4: Marker Hygiene
Work markers (the words the placeholder scan rejects) must never appear
live in skill content. When documentation needs to *discuss* a marker,
wrap it in inline code formatting — the scanner treats code spans and
fenced blocks as quoted material, not live markers. Rephrase the content;
never weaken the validator.

## Lesson 5: Clean Up Session Residue
Raw shell transcripts pasted into lesson files (unfenced commands, stray
docstring delimiters, absolute home-directory paths) corrupt the lesson
and trip the content scans. A lesson records context, cause, resolution,
and prevention — commands belong inside fenced code blocks with
placeholder-free, portable paths.
