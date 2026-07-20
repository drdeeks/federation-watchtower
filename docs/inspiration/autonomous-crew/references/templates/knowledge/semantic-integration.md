# Semantic Search Integration (Turbopuffer)

## Overview
Optional semantic vector search layer for fuzzy recall across crew knowledge base. Integrates with Turbopuffer + OpenAI embeddings.

## Prerequisites

```bash
# Environment variables required
export TURBOPUFFER_API_KEY="your-api-key"
export OPENAI_API_KEY="your-openai-key"
export CREW_SEMANTIC_ENABLED=true
```

## Architecture

```
Crew Knowledge Base (.md files)
         │
         ▼
┌─────────────────────────────────────┐
│      Indexer (crew-indexer.sh)      │
│  - Chunks documents (3500 chars)    │
│  - 350 char overlap                 │
│  - Extracts metadata                │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│    OpenAI text-embedding-3-large    │
│    3072 dimensions                  │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│        Turbopuffer Namespace        │
│    Vector store + metadata filter   │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│         Search Queries              │
│  - Semantic (vector similarity)     │
│  - BM25 (keyword)                   │
│  - Hybrid (RRF fusion)              │
└─────────────────────────────────────┘
```

## Chunking Strategy

- **Chunk size**: 3500 characters
- **Overlap**: 350 characters (10%)
- **Why overlap**: Preserves context at boundaries
- **Chunk IDs**: `{doc_id}:chunk-{n}`
- **Parent tracking**: Each chunk stores `parent_id`

## Metadata Stored Per Chunk

```json
{
  "id": "dec-architecture-auth-oauth-001:chunk-0",
  "parent_id": "dec-architecture-auth-oauth-001",
  "source": "shared",
  "agent_id": "ui-a1b2",
  "doc_type": "decision",
  "category": "architecture",
  "tags": ["auth", "oauth", "security"],
  "timestamp": "2026-07-05T14:32:17Z",
  "title": "OAuth2 Token Refresh Strategy",
  "content": "Chunk text content..."
}
```

## Search Modes

### Semantic Search (Vector Similarity)
```bash
bash crew-indexer.sh semantic-search "how do we handle token expiry"
```
Best for: Conceptual queries, finding related content without exact keywords.

### BM25 Search (Keyword)
```bash
bash crew-indexer.sh search "oauth authentication" --category architecture
```
Best for: Specific terms, names, exact phrases.

### Hybrid Search (RRF Fusion)
```bash
bash crew-indexer.sh hybrid-search "oauth refresh token"
```
Best for: General recall - combines both approaches.

**RRF Formula:**
```
RRF_score = Σ 1/(k + rank)
k = 60 (default)
```

## Indexing Commands

```bash
# Full rebuild with semantic vectors
CREW_SEMANTIC_ENABLED=true bash crew-indexer.sh rebuild --semantic

# Incremental index (default)
bash crew-indexer.sh index

# Agent-specific index
bash crew-indexer.sh index-agent ui-a1b2
```

## Cost Estimates

| Component | Cost |
|-----------|------|
| Turbopuffer storage | ~$0.10 per million vectors/month |
| OpenAI embeddings | ~$0.13 per million tokens |
| Typical crew (500 docs) | ~$0.50-2.00 initial, $0.05-0.20/month |
| Queries | Negligible |

## Integration with Recall Discipline

Per `recall-discipline.md` pattern, agents MUST search before acting:

```bash
# In AGENTS.md or crew startup script
⚠️ MANDATORY: Search Crew Knowledge FIRST

bash crew-indexer.sh hybrid-search "<main topic>" 20
```

## Search Logging

All searches logged for verification:
```
2026-07-05T14:32:17Z | HYBRID  | results= 10 | "oauth token refresh"
2026-07-05T14:35:22Z | SEMANTIC| results= 15 | "how do we handle token expiry"
```

Check compliance"

## Fallback Behavior

If semantic search unavailable:
1. Log warning
2. Fall back to keyword search
3. Continue with reduced recall

## Configuration

```bash
# Enable semantic search
export CREW_SEMANTIC_ENABLED=true

# Custom chunk size (optional)
export CREW_CHUNK_SIZE=3500
export CREW_CHUNK_OVERLAP=350

# Custom embedding model (optional)
export OPENAI_EMBEDDING_MODEL="text-embedding-3-large"

# Turbopuffer namespace (optional)
export TURBOPUFFER_NAMESPACE="crew-knowledge"
```

## Verification

```bash
# Check index status
bash crew-indexer.sh status

# Test semantic search
bash crew-indexer.sh semantic-search "token refresh strategy"

# Verify vectors exist
ls -la crew/index/semantic/
# vectors.faiss
# metadata.json
```