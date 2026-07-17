---
name: feedback-reject-self-declared-placeholders
description: "If a skill's own SKILL.md declares itself a PLACEHOLDER, skip it. Don't import, don't tier, don't ship. Applies even when pulling from a trusted remote."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: eb376b9a-bf69-4ed6-9d5a-9d799c698dcf
---

If a skill's own SKILL.md contains the words `PLACEHOLDER`, `Status: PLACEHOLDER`, `This skill needs to be completed`, `stub`, `TBD` (as a status marker), or similar self-declared incomplete-state text, **do not import it**. Skip it during pulls from any source — remote git, USB, local directory, tarball.

**Why:** during CL-040 I pulled a `skills` skill from `drdeeks/skills` remote whose SKILL.md literally opened with `**Status:** PLACEHOLDER - This skill needs to be completed`. I filed it under `in-progress/` reasoning "we'll deal with it later." User immediately corrected: placeholders never enter the working set, regardless of tier. The no-stubs policy applies to imports too, not just to authored content.

**How to apply:**
- Any import script (pulling from remote, from USB, from another dir) MUST grep SKILL.md for self-declared placeholder markers BEFORE writing the destination file. If any marker matches, skip + report the skip.
- Applies at every tier: not just `curated/`, not just `basic/`, but also `in-progress/`. Placeholders don't belong anywhere.
- The specific patterns to reject (case-insensitive):
  - `PLACEHOLDER` appearing as a status label (e.g. `**Status:** PLACEHOLDER`, `Status: PLACEHOLDER`)
  - `This skill needs to be completed`
  - `Placeholder for` at the start of a `description:` field
  - `## Placeholder Notice` or similar section headers
- Fold this into `skill-creator/scripts/import_from_source.py` (once that exists) as a pre-write gate.

**What this does NOT apply to:**
- References to the concept of placeholders in prose (e.g. "the validator detects placeholder patterns") — those are describing behavior, not declaring the skill itself incomplete.
- Skills whose *content* has placeholder-tier scripts but SKILL.md is substantive — those get flagged by the validator's per-file substance check, not by this import filter.
