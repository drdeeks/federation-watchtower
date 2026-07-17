---
name: feedback-validator-vs-content
description: "When a validator flags substantive content, rephrase the content — don't soften the validator. Validators encode rules deliberately."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: eb376b9a-bf69-4ed6-9d5a-9d799c698dcf
---

When a strict validator flags something in a skill or doc, the fix is to **rephrase the content** so it conveys the same meaning without tripping the rule. Do NOT relax the validator's rule, add exemptions, or carve out allowlists.

**Why:** validators encode a deliberate policy. If a skill is about task tracking and uses the word "TODO" as a meta-concept, the skill author can re-word it ("task marker", "open-task token", wrap in backticks) and still convey the meaning. Once you add validator exemptions for "the skill is about this", the rule erodes by 1000 cuts.

**How to apply:**
- Validator flags `TODO` in SKILL.md → wrap in backticks (`` `TODO` ``) or rename concept ("task marker", "open-task token")
- Validator flags placeholders → choose wording that doesn't pattern-match (e.g. "sample input" instead of "your input here")
- Validator flags description-field wording → reword the frontmatter description
- NEVER edit the validator's regex / patterns / allowlist to make a specific skill pass
- This applies to `skill-scan-validate-resolver/scripts/validate.py` and any similar lint/policy tooling
