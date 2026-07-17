---
name: feedback-version-guard-overwrites
description: Never overwrite a skill (or any versioned artifact) with a lower-version copy. Compare semver first; overwrite only if source > destination. Every skill change also warrants a git commit so history stays granular.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: eb376b9a-bf69-4ed6-9d5a-9d799c698dcf
---

When merging / overwriting skills from any source (USB import, another host directory, a downloaded set), **always compare `SKILL.md` frontmatter `version` before overwriting**. Overwrite only when source version > destination version.

Also: every skill update — no matter how small — deserves its own git commit. The skill collection should be linkable to a GitHub repo (e.g. `drdeeks/skills`), and un-committed accumulation is exactly how that repo goes stale.

**Why:** during CL-039, running a bulk drdeeks overwrite blindly replaced our just-merged `skill-creator` v2.1.0 with drdeeks' v0.0.10 (an older, less-complete version). Full 816-line validator got replaced with a 96-line "quick" validator. Recovered from the docker-context backup, but only by luck — could have lost hours of merge work permanently.

**How to apply:**

1. **Overwrite gate:** before `cp -a src target`, read `src/SKILL.md` and `target/SKILL.md` frontmatter versions. Parse as semver. If `src_ver < target_ver`, SKIP (or ASK the user); log the skip in the operation report.
2. **Fold this into `skill-creator/scripts/consolidate_skills.py`** (per ad-hoc-scripts-belong-in-skills memory) so any batch merge that touches skills goes through the version-guard, not through a raw `cp -a` loop.
3. **Git checkpoint per skill change:**
   - After ANY successful edit to a skill (edit, upgrade, package, consolidate), commit that skill's directory with a message like `<skill-name>: v<X.Y.Z> — <one-line reason>`.
   - Keeps history granular; makes GitHub sync trivial.
   - Applies to skill-creator's tooling: every script that modifies a skill should trigger (or offer to trigger) a commit at the end.
4. **When bulk-restoring from a backup** (like docker-context or a tar snapshot), still apply the version-guard — don't assume the backup is newer than what's live.

**Failure signature to detect:** if you find yourself running `rm -rf target && cp -a src target` in a loop, stop and add the version check first.
