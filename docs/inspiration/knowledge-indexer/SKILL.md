---
name: knowledge-indexer
description: 'Indexes documentation links and builds a searchable knowledge base for
  the entire codebase, similar to Cursor''s codebase indexing. Supports manual and
  scheduled indexing, incremental updates, and full-text search. Provider-agnostic:
  works with any LLM backend. Free-first: starts with $0 tools before requiring paid
  services. Use when: indexing documentation, searching codebase, building knowledge
  base, managing documentation links, finding relevant files.'
license: MIT
metadata:
  tags:
  - index the documentation
  - search the codebase
  - build a knowledge base
  - codebase indexing
  - full-text documentation search
  - manage documentation links
  - incremental index update
  openclaw:
    category: productivity
    priority: high
  hermes:
    category: utility
    related_skills:
    - tool-enforcement
    - agent-memory
  providers:
  - openai
  - claude
  - mistral
  - gemini
  - hermes
  - copilot
  - any
version: 0.0.7
---

# Knowledge Indexer

## Overview

Documentation indexer that builds a searchable knowledge base for the entire codebase. Features:
- Index documentation links from multiple sources
- Build searchable knowledge base
- Support for manual and scheduled indexing
- Incremental updates
- Full-text search capability

## Workspace Detection

Scripts detect workspace automatically by scanning (in order):
1. Environment variables: `AGENT_HOME`, `AGENT_WORKSPACE`, `WORKSPACE`
2. Common paths: `/opt/${PACKAGE_NAME}/`, `/data/agents/`, `~/agents/`, etc.
3. Walk up from script location looking for `SOUL.md`, `agent.json`, `MEMORY.md`
4. First argument if provided

## When to Use This Skill

- When you need to find documentation across a large codebase
- When building a knowledge base for reference
- When indexing documentation links
- When searching for relevant files by keyword

## Prerequisites

- Bash shell
- Python 3.6+
- jq (optional, for JSON formatting)

## Commands

| Command | Purpose |
|---------|---------|
| `index` | Index all documentation (default) |
| `index-file <file>` | Index a specific file |
| `search <query>` | Search the knowledge base |
| `update` | Update existing index (incremental) |
| `rebuild` | Rebuild entire index from scratch |
| `list` | List all indexed documents |
| `add-link <url> <title> [category]` | Add a documentation link |
| `remove-link <url>` | Remove a documentation link |
| `status` | Show indexing status |

## Workflow

### Step 1: Index Documentation

```bash
bash scripts/knowledge-indexer.sh index
```

### Step 2: Search Knowledge Base

```bash
bash scripts/knowledge-indexer.sh search "agent management"
```

### Step 3: Add Documentation Links

```bash
bash scripts/knowledge-indexer.sh add-link "https://docs.example.com" "Example Docs" core
```

### Step 4: Check Status

```bash
bash scripts/knowledge-indexer.sh status
```

## Scripts

| Script | Purpose | Path |
|--------|---------|------|
| knowledge-indexer.sh | Main indexing system | scripts/knowledge-indexer.sh |

## Safety Practices

- Never index files containing credentials or secrets
- Respects exclusion patterns (node_modules, .git, etc.)
- See [safety-practices.md](references/safety-practices.md) for details

## Free-First Strategy

| Tier | Cost | Stack | Escalation Criteria |
|---|---|---|---|
| **Tier 0** | $0/mo | Bash + Python + filesystem | Default — covers all individual use |
| **Tier 1** | $0-5/mo | + CI/CD automated indexing | When validating 10+ codebases automatically |
| **Tier 2** | $5-20/mo | + Hosted knowledge service | When distributing across a team or org |

## Enforced Output Statistics

After each indexing operation, report:
- Number of files indexed
- Number of keywords extracted
- Number of documentation links
- Last indexed timestamp

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| Knowledge base not indexed | No index exists | Run `index` command |
| File not found | Path doesn't exist | Check file path |
| Python not found | Missing dependency | Install Python 3.6+ |

## Provider Compatibility

| Provider | Compatibility | Notes |
|---|---|---|
| Claude (Anthropic) | Full | Tool use, MCP servers |
| OpenAI / ChatGPT | Full | Function calling, assistants |
| Mistral / Vibe | Full | Tool calling, script execution |
| Gemini (Google) | Full | Extensions, Vertex AI |
| Hermes (Nous) | Full | Tool-use fine-tuned |
| GitHub Copilot | Partial | Code generation; use external runner for scripts |
| Any LLM + tools | Full | All scripts are plain Python, provider-independent |


## Enhancement Hooks

| Skill | Enhancement | When to Add |
|-------|-------------|-------------|
| `skill-creator` | Basic skill creation | When creating simple skills |
| `skill-creator-pro` | Enterprise upgrade | When upgrading to enterprise |
| `html-report` | Visual validation dashboard | When auditing many skills |
| `xlsx` | Export validation results | When tracking skill quality metrics |


## Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/pipeline.py` | knowledge-indexer script | Run with python3 |
| `scripts/setup.py` | knowledge-indexer script | Run with python3 |
## Key References

- [safety-practices.md](references/safety-practices.md)
- [workflow-guide.md](references/workflow-guide.md)
- [error-handling.md](references/error-handling.md)
- [critical-file-protection.md](references/critical-file-protection.md)
- [index-storage-format.md](references/index-storage-format.md) — on-disk layout, command semantics, incremental vs rebuild
