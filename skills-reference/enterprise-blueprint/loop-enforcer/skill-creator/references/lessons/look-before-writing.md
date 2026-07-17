---
name: feedback-look-before-writing
description: "When user asks \"what's different between X and Y\", LOOK at both files and diff them. Never answer from theory/analogy without checking the actual bytes on disk. Same rule for any comparison, merge, or overwrite."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: eb376b9a-bf69-4ed6-9d5a-9d799c698dcf
---

If the user asks "what's the difference between X and Y" — or ANY comparative question about files/scripts/skills — **read both files, print the actual diff or side-by-side, THEN answer**. Never fall back to a theoretical explanation ("well, X is typically a foo while Y is typically a bar") without opening the actual files first.

**Why:** during CL-040 the user asked "what's different between your init_skill and the init at root?" I answered with a generic Python-package-marker vs scaffolder-script analogy from theory. What they wanted was the CONCRETE diff — because the existing `__init__.py` files in 125 skills are 26-line scaffolders with executable `scaffold()` + `integrate()` functions, NOT the 5-line metadata dumps I assumed. My newly-written `__init__.py` was 5 lines. My newly-written `init_skill.py` was 140 lines and REDUNDANT with what should have lived IN the existing `__init__.py` pattern. If I'd looked first, I'd have found the existing template + built on it rather than duplicating.

**How to apply:**
- Comparative question → `Read` both files (or `diff`, `wc -l`, `head`) BEFORE writing a response
- The response leads with concrete facts (line counts, function names, byte differences), theory second
- If the files are large, sample representatively but LOOK, don't infer
- Extends to overwrites, merges, imports: before overwriting X with Y, read both and know exactly what differs
- The user's phrase for this: "not what the theoretically in plain text without any actual reviewing is the difference"

**Pattern to catch this in real time:**
- If I'm about to write "typically", "conceptually", "in Python conventions", "usually" in a comparison answer — STOP, open the files, and start over with observed facts
