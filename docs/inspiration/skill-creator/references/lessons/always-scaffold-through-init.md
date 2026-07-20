---
name: feedback-always-use-skill-creator-to-init
description: "When creating any new skill, invoke skill-creator's init/scaffold/validate/package tooling. Never hand-craft a skill directory from scratch; skill-creator IS the systematic process."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: eb376b9a-bf69-4ed6-9d5a-9d799c698dcf
---

Any new skill must be created THROUGH `skill-creator`'s tooling, not by hand-crafting `SKILL.md` + `scripts/` + `references/` files directly.

Correct flow:

1. `python3 _curated/skill-creator/scripts/init_skill.py <name> --path <destination>`
   → generates canonical skeleton: `SKILL.md` with proper frontmatter, `__init__.py`, `scripts/`, `references/`
2. Edit `SKILL.md` and add resources
3. `python3 _curated/skill-creator/scripts/validate.py <destination>/<name>` — verify structural + substance rules
4. `python3 _curated/skill-creator/scripts/verify_sources.py <destination>/<name>` — confirm external sources cited
5. `python3 _curated/skill-creator/scripts/package_skills.py --skills-root <destination> --skill <name>` — bump version + emit .skill archive
6. Autowatch commits it (once watcher is running)

**Why:** in CL-040 I hand-crafted `autowatch/SKILL.md` and `scripts/autowatch.py` directly without invoking `skill-creator`'s init. That skipped the standardized scaffolding, missed the __init__.py generation, and bypassed the version-registry the packager tracks. Skill-creator IS the systematic process — bypassing it means the new skill exists outside the process and will drift.

**How to apply:**
- Before writing any file for a new skill, first run `init_skill.py` and get the scaffold
- Fill in the scaffold content, don't create fresh from empty
- Always end with `package_skills.py` so version tracking + manifest is consistent
- If `init_skill.py` doesn't exist yet (it's referenced in skill-creator SKILL.md but the script wasn't recovered from backup), CREATE it in skill-creator/scripts/ before creating new skills — the missing script is itself a bug in skill-creator that needs fixing
- When writing skills for OTHER tools (like Hemlock agents or USB management), those tools should still invoke skill-creator internally rather than reimplementing skill scaffolding
