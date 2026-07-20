# Workflow Guide
## Table of Contents

- [Overview](#overview)
- [Initial Setup](#initial-setup)
- [Searching](#searching)
- [Managing Links](#managing-links)
- [Maintenance](#maintenance)
- [Configuration](#configuration)
- [Best Practices](#best-practices)


## Overview

This guide covers the complete workflow for using the knowledge-indexer skill.

## Initial Setup

### Step 1: Index Documentation

```bash
# Index all documentation in the workspace
bash scripts/knowledge-indexer.sh index
```

This will:
- Scan for README files
- Index markdown files
- Index text files
- Index scripts
- Index configuration files
- Index agent files
- Index documentation links

### Step 2: Verify Index

```bash
# Check indexing status
bash scripts/knowledge-indexer.sh status

# List all indexed documents
bash scripts/knowledge-indexer.sh list
```

## Searching

### Basic Search

```bash
# Search for a keyword
bash scripts/knowledge-indexer.sh search "agent"

# Search for a phrase
bash scripts/knowledge-indexer.sh search "agent management"
```

### Search Results

Results include:
- Document path
- Document type (markdown, json, python, etc.)
- Matching keywords
- Preview of content
- Score based on keyword matches

## Managing Links

### Add Documentation Links

```bash
# Add a link with category
bash scripts/knowledge-indexer.sh add-link "https://docs.example.com" "Example Docs" core

# Add a link without category (defaults to general)
bash scripts/knowledge-indexer.sh add-link "https://example.com" "Example Site"
```

### Remove Links

```bash
bash scripts/knowledge-indexer.sh remove-link "https://docs.example.com"
```

## Maintenance

### Incremental Update

```bash
# Update index with new/changed files
bash scripts/knowledge-indexer.sh update
```

### Full Rebuild

```bash
# Rebuild entire index from scratch
bash scripts/knowledge-indexer.sh rebuild
```

## Configuration

The knowledge base configuration is stored at `docs/knowledge-base/config.json`:

```json
{
  "version": "1.0.0",
  "indexing": {
    "enabled": true,
    "schedule": "manual",
    "auto_update": false,
    "interval_hours": 24
  },
  "sources": {
    "markdown": true,
    "text": true,
    "json": true,
    "yaml": true,
    "python": true,
    "bash": true,
    "links": true
  },
  "excludes": [
    "node_modules",
    "__pycache__",
    ".git",
    "*.log",
    "*.tmp",
    "*~"
  ],
  "search": {
    "min_word_length": 3,
    "max_results": 20,
    "fuzzy_search": true
  }
}
```

## Best Practices

1. **Regular Indexing**: Run `index` or `update` periodically to keep the knowledge base current
2. **Use Categories**: Categorize documentation links for better organization
3. **Review Search Results**: Check search results to verify indexing quality
4. **Exclude Sensitive Files**: Ensure sensitive files are in the exclusion list
