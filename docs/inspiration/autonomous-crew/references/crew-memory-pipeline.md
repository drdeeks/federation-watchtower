# Crew Memory Pipeline Reference
# Memory pipeline configuration and operations for crew agents

## Pipeline Overview

```
daily/ (14 days) → weekly/ (12 weeks) → long-term/MEMORY.md (permanent)
                          ↓
                    knowledge-index.json
```

## Daily Memory

**Path:** `memory/daily/YYYY-MM-DD.md`
**Format:** Markdown with timestamped entries
**Retention:** 14 days

**Entry Types:**
- SESSION - general session notes
- DECISION - architectural/design decisions
- NOTE - general notes
- ERROR - errors and issues encountered
- INSIGHT - patterns and learnings discovered
- LESSON - promoted lessons
- PATTERN - recurring patterns

**Wikilinks:** `[[entity]]` syntax for knowledge graph

## Weekly Memory

**Path:** `memory/weekly/YYYY-WNN.md`
**Format:** Markdown with curated sections
**Retention:** 12 weeks

**Sections:**
- Insights
- Decisions
- Knowledge Links

**Promotion Criteria:**
- Daily file older than 7 days
- Not already promoted (checked by date marker)
- Contains promotion keywords: LESSON, INSIGHT, DECISION, PATTERN, ERROR, SUCCESS

## Long-Term Memory

**Path:** `memory/long-term/MEMORY.md`
**Format:** Markdown with dated sections
**Retention:** Permanent

**Structure:**
- Header: `# Long-Term Memory`
- Sections by week: `## YYYY-WNN`
- Promoted entries with date headers
- Separator: `---`

## Knowledge Index

**Path:** `memory/knowledge-index.json`
**Format:** JSON with entity → entries mapping
**Extraction:** From daily wikilinks `[[entity]]`
**Context:** 100 chars before/after link
**Deduplication:** Per entity per date
**Query:** `grep [[entity]] from knowledge-index.json`

## Crew Shared Memory

**Path:** `shared/knowledge-index.json`
**Purpose:** Cross-agent knowledge index for crew-wide queries
**Update:** On any agent's index update
**Conflict Resolution:** Latest timestamp wins

## Curation Automation

**Script:** `memory_curator.py` per agent
**Schedule:** Daily at 02:00 UTC (configurable)
**Actions:**
- Curate daily to weekly
- Promote weekly to long-term
- Update knowledge index
- Emit curation metrics

**Shared Curator:** `shared-memory-curator.py` for crew-wide curation