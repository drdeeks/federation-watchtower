---
name: feedback-import-scope
description: "When user asks to \"bring over\" or \"copy\" a directory, import ALL of it. Only remove specific named items when they explicitly say which."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: eb376b9a-bf69-4ed6-9d5a-9d799c698dcf
---

When user asks to "bring over", "copy", "import", or "pull in" a directory of content from a USB / external source, **import the whole tree**. Do not selectively pick out one piece and drop the rest.

Even if the immediate purpose is a cross-reference on one item (e.g., skill-creator), the user's broader intent is usually to have all the source material available for follow-up consolidation and merging.

**Why:** in a session where user said "copy the skills directory located at <usb>/AGENT-ESSENTIALS/skills/ in place those next to the other ones", I copied 217 skills, then after cross-referencing skill-creator I deleted the entire `_usb_import` tree — losing 216 skills the user wanted to keep for later consolidation. User was confused and had to correct me.

**How to apply:**
- When user says "delete the old copy" after a cross-reference, delete ONLY the specific skill that was cross-referenced, not the whole import tree
- Preserve any imported material until the user explicitly tells me the whole tree is done
- If unsure whether "delete X" means "delete only X" vs "delete the whole thing X came from", ask before removing
- For same-named-skill overlaps between imported and existing sets, MERGE / dedupe (keep the more-complete version + surface differences); don't blindly overwrite either side
- For similar-but-not-identical variants (e.g., `8004`, `8004scan`, `8004scan-webhooks`), keep as separate directories for later manual consolidation; don't force-merge on name-similarity alone
