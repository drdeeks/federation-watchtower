# Consolidation Patterns Reference

## Table of Contents

- [When to Consolidate](#when-to-consolidate)
- [Consolidation Patterns](#consolidation-patterns)
- [Merge Rules](#merge-rules)
- [Conflict Resolution](#conflict-resolution)
- [Post-Consolidation Checklist](#post-consolidation-checklist)

## When to Consolidate

| Scenario | Action |
|----------|--------|
| Same functionality, different names | Merge |
| Overlapping features (50-70%) | Consolidate |
| Similar triggers/use cases | Review for merge |
| One skill is subset of another | Absorb into parent |

## Consolidation Patterns

### Pattern 1: Full Merge
**When:** Skills have >70% overlap
**Action:** Combine all content into single skill

```
skill-a/ + skill-b/ → merged-skill/
├── SKILL.md (combined frontmatter + body)
├── scripts/ (unique scripts from both)
└── references/ (combined references)
```

### Pattern 2: Absorption
**When:** Skill B is subset of Skill A
**Action:** Add Skill B's unique features to Skill A

```
skill-a/ absorbs skill-b/
├── SKILL.md (skill-a with skill-b features added)
├── scripts/ (skill-a scripts + skill-b unique scripts)
└── references/ (combined)
```

### Pattern 3: Feature Extraction
**When:** Skill has too many responsibilities
**Action:** Extract features into focused skills

```
monolithic-skill/ → focused-skill-a/
                 → focused-skill-b/
                 → focused-skill-c/
```

### Pattern 4: Common Core
**When:** Multiple skills share common functionality
**Action:** Extract shared code into base skill

```
skill-a/ + skill-b/ + skill-c/
    ↓
common-core/
├── SKILL.md
└── scripts/
    └── shared.py

skill-a/ (imports common-core)
skill-b/ (imports common-core)
skill-c/ (imports common-core)
```

## Merge Rules

### Frontmatter Merging
1. Use primary skill's name
2. Combine descriptions (keep unique triggers)
3. Preserve metadata from both
4. Use most permissive license

### Content Merging
1. Preserve all unique sections
2. Deduplicate common content
3. Maintain consistent formatting
4. Update all internal links

### Script Merging
1. Keep unique scripts
2. Rename conflicts with prefix
3. Combine shared functionality
4. Update imports/references

### Reference Merging
1. Keep unique references
2. Rename conflicts with skill prefix
3. Update all cross-references
4. Remove duplicates

## Conflict Resolution

| Conflict | Resolution |
|----------|------------|
| Same filename | Rename with skill prefix |
| Same section | Merge content, keep unique parts |
| Contradictory info | Keep more specific/recent |
| Different formats | Standardize to primary skill format |

## Post-Consolidation Checklist

- [ ] All unique features preserved
- [ ] No duplicate content
- [ ] All references updated
- [ ] Scripts work standalone
- [ ] Frontmatter accurate
- [ ] Description reflects all features
- [ ] Internal links valid
- [ ] No hardcoded paths
