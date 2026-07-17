---
name: feedback-verify-beyond-version
description: "Newer version does not mean better version. In consolidations, cross-verify with substance/validation/placeholder/structure checks before overwriting. \"The brother, sister, and parents all vouch\" — not just one signal."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: eb376b9a-bf69-4ed6-9d5a-9d799c698dcf
---

The version-guard rule (never overwrite newer with older) is necessary but not sufficient. Just because a version number is higher does NOT mean the content is more accurate, more complete, or less broken.

In a consolidation or any chaotic-input situation, every "take this version" decision needs to be cross-verified against multiple attributes:

- **Version number** (newer wins, tie-breaker)
- **Validator pass status** (basic + enterprise)
- **Substance check** (no stubs, no placeholders, no CL-038-style padding)
- **Cross-reference completeness** (scripts + refs listed in SKILL.md)
- **Self-declared status** (rejects `PLACEHOLDER`, `TBD`, `incomplete` — see [reject-self-declared-placeholders](feedback_reject_self_declared_placeholders.md))
- **Script functionality** (do the scripts syntax-check + run?)

**Decision matrix** for src-vs-dst comparison during consolidation:

| Src version | Dst version | Src validates | Dst validates | Winner |
|---|---|---|---|---|
| Newer | Older | pass | pass | src |
| Newer | Older | fail | pass | **dst** (don't downgrade quality just to get a version bump) |
| Newer | Older | pass | fail | src |
| Newer | Older | fail | fail | flag to user |
| Same | Same | pass | pass | either (dst by default) |
| Older | Newer | * | * | dst (never overwrite newer with older) |

**Why:** in CL-040 I ran a blind drdeeks bulk overwrite that blew away my merged skill-creator v2.1.0 because drdeeks was checked in as v0.0.10. My "newer = better" heuristic would have caught the version regression. But the user surfaced the deeper point: even if drdeeks had been v3.0.0, that doesn't guarantee the drdeeks version wasn't itself broken/stubbed. Cross-verify.

**How to apply:**
- Add this multi-signal check to `skill-creator/scripts/consolidate_skills.py` and any other bulk overwrite operation
- When importing from a remote / USB / peer directory, run the full validator on BOTH sides before choosing
- Cache the validation result so we're not re-running for every pairwise comparison
- Report the decision explicitly per skill: `overlap agent-mail: src=v1.0.1 (validates), dst=v2.0.0 (fails-substance) → picking src`
- Never trust a single signal
