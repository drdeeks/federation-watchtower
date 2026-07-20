# Skill Creator — Enterprise Standards

Complete reference for enterprise-grade skill validation, scoring, pillar definitions, quality checklist, reusable patterns, and the enterprise SKILL.md structure.

## Table of Contents

1. [The 8 Enterprise Pillars](#1-the-8-enterprise-pillars)
2. [Scoring System](#2-scoring-system)
3. [Validation Levels](#3-validation-levels)
4. [Quality Checklist](#4-quality-checklist)
5. [Permissions Validation](#5-permissions-validation)
6. [Information Quality](#6-information-quality)
7. [Reusable Script Patterns](#7-reusable-script-patterns)
8. [Metadata Flexibility](#8-metadata-flexibility)
9. [Enterprise SKILL.md Structure](#9-enterprise-skillmd-structure)
10. [Consolidation Precision Protocol](#10-consolidation-precision-protocol)

---

## 1. The 8 Enterprise Pillars

Every enterprise-grade skill MUST include these components:

| # | Pillar | Weight | What It Means | Minimum Requirement |
|---|---|---|---|---|
| 1 | **Frontmatter** | 20% | Valid YAML, required keys, naming | Valid `name` + `description`, 100-1024 chars |
| 2 | **Structure** | 15% | Directory layout, file organization | `scripts/` (2+ files), `references/` (3+ files) |
| 3 | **Content** | 20% | Comprehensive, accurate, clear | No TODOs, all sections have content, <500 lines |
| 4 | **Agnostic** | 15% | No hardcoded paths, cross-platform | Environment variables, portable file operations |
| 5 | **Sources** | 10% | Documented, verified, current | Documentation URLs, API endpoints, version numbers |
| 6 | **Syntax** | 10% | Working code, proper error handling | Valid Python/Bash/Node syntax, stdlib only |
| 7 | **Enterprise** | 15% | Provider compat, free-first, output stats | All 8 pillar sections present in SKILL.md |
| 8 | **Accessibility** | 5% | Clear triggers, good descriptions | Progressive disclosure, references for deep docs |

### Conditional Components (include when applicable)

| Component | When Required |
|---|---|
| Multi-Agent Coordination | Skill may run as concurrent instances |
| Scheduling / Cron | Skill involves recurring tasks |
| Analytics Framework | Skill produces measurable outcomes |
| A/B Testing Protocol | Skill has tunable parameters |

## 2. Scoring System

### Pillar Scores

| Pillar | Weight | Pass Criteria |
|---|---|---|
| Frontmatter | 20% | Valid YAML, required keys, naming conventions |
| Structure | 15% | Proper directory layout, minimum file counts |
| Content | 20% | Comprehensive, accurate, clear, no placeholders |
| Agnostic | 15% | No hardcoded paths, hostnames, or secrets |
| Sources | 10% | Documented, verified, current |
| Syntax | 10% | Working code, proper error handling |
| Enterprise | 15% | Provider compat, free-first, output stats, error handling |
| Accessibility | 5% | Clear triggers, good descriptions |

### Calculation

```
score = Σ (pillar_score × weight)
```

Each pillar returns `passed` (1.0) or `failed` (0.0). The total score is the sum of `(passed × weight)` across all pillars.

### Validation Levels

| Rating | Score Range | FAIL Count | WARN Count |
|---|---|---|---|
| **Enterprise Grade** | 90-100% | 0 | 0-5 |
| **Production Ready** | 75-89% | 0 | 6-10 |
| **Needs Hardening** | 60-74% | 1-3 | Any |
| **Not Enterprise** | <60% | 4+ | Any |

## 3. Validation Levels

### Automated Validation

```bash
# Enterprise validation (all pillars, scored)
python3 scripts/validate_pro.py /path/to/skill --verbose

# Quick validation (frontmatter, structure only)
python3 scripts/validate.py /path/to/skill

# Batch validation (all skills in directory)
python3 scripts/validate_pro.py /path/to/skills/ --json
```

### Manual Review Checklist

- [ ] Content accuracy
- [ ] Use case coverage
- [ ] Example quality
- [ ] Reference completeness
- [ ] No stale template files
- [ ] Every script and reference mentioned in SKILL.md

### Source Verification

```bash
python3 scripts/verify_sources.py /path/to/skill --check-urls
```

## 4. Quality Checklist

### Structure (FAIL = must fix)

- SKILL.md exists with YAML frontmatter (`name` + `description`)
- Description 100-1024 characters, contains WHAT + WHEN + triggers
- `scripts/` has 2+ `.py`, `.sh`, `.js`, or `.ts` files
- `references/` has 3+ `.md`, `.txt`, `.json`, `.yaml`, `.yml`, or `.csv` files
- Directory name matches frontmatter `name`
- No stale template files (`example.py`, `api_reference.md`, `example_asset.txt`)
- Every script and reference mentioned in SKILL.md
- `metadata.openclaw` section present in frontmatter

### SKILL.md Quality

- Body <500 lines (progressive disclosure)
- 6+ top-level sections (## headers)
- Provider Compatibility, Free-First, Output Statistics, Error Handling, Scripts table, Key References sections all present
- No `TODO`/`FIXME`/`WIP`/coming-soon markers remaining
- At least 1 Workflow section
- No empty/sparse sections (<20 chars content)

### Script Quality

- Shebang line (`#!/usr/bin/env python3`)
- Module docstring with usage
- CLI argument support
- Error handling with try/except
- No hardcoded secrets (`api_key="..."`, `secret="..."`, etc.)
- `--dry-run` and `--status` support for setup/deploy scripts
- Valid Python/Bash/Node syntax

### Reference Quality

- Files >100 lines have table of contents
- Each file covers one concern (not mixed topics)
- Cross-references where relevant
- Contains procedures/schemas/examples, not just descriptions
- `references/lessons/` populated with operational lessons learned

## 5. Permissions Validation

### Required Standards

| Type | Permission | Description |
|---|---|---|
| Directories | `755` (rwxr-xr-x) | Owner write, all read/execute |
| Files | `644` (rw-r--r--) | Owner write, all read |
| Secrets dir | `755` (NOT 700) | Group-accessible for collaboration |

### Forbidden Permissions

| Permission | Reason |
|---|---|
| `700` on directories | Locks out co-developers and group members |
| `777` on anything | World-writable, security risk |
| `600` on non-secrets | Blocks group access unnecessarily |

## 6. Information Quality

### Completeness Checks

| Check | Description |
|---|---|
| **API Endpoints** | All endpoints documented with method, path, body, response |
| **Code Examples** | Every function has at least one working example |
| **Error States** | All error conditions documented with codes and messages |
| **Configuration** | All env vars, config files, and options listed |
| **Prerequisites** | Dependencies, versions, and setup steps documented |

### Robustness Checks

| Check | Description |
|---|---|
| **Edge Cases** | Boundary conditions and error handling covered |
| **Idempotency** | Repeated operations don't cause side effects |
| **Rollback** | Every state change has a documented reversal |
| **Timeout** | Long operations have timeout and retry behavior |
| **Graceful Degradation** | Fallback behavior when dependencies unavailable |

### Accuracy Checks

| Check | Description |
|---|---|
| **API URLs** | Endpoints respond with expected status codes |
| **Code Syntax** | All code examples parse without errors |
| **Version Numbers** | Match current releases |
| **No Placeholder Secrets** | Example keys clearly marked as examples |

## 7. Reusable Script Patterns

### Script Skeleton

```python
#!/usr/bin/env python3
"""
[Skill] — [Purpose]

Usage:
    python3 script.py <command> [options]
    python3 script.py --help
    python3 script.py --dry-run
"""

import json, sys
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path.home() / ".skill-name"
CONFIG_PATH = STATE_DIR / "config.json"

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def append_jsonl(filepath, record):
    Path(filepath).parent.mkdir(parents=True, exist_ok=True)
    with open(filepath, "a") as f:
        f.write(json.dumps(record) + "\n")

COMMANDS = {"help": lambda: print(__doc__), "status": do_status}

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd in ("--help", "-h"): cmd = "help"
    if cmd == "--dry-run": print("[DRY RUN]"); return
    COMMANDS.get(cmd, lambda: print(f"Unknown: {cmd}"))()

if __name__ == "__main__":
    main()
```

### Queue Processor Pattern

```python
QUEUE = STATE_DIR / "queue.jsonl"
RETRY = STATE_DIR / "retry_queue.jsonl"
FAILED = STATE_DIR / "permanent_failures.jsonl"
MAX_RETRIES = 3

# pending → processing → completed
#              ↓ failure
#         retry (retries < 3)
#              ↓ retries >= 3
#         permanent_failures
```

### Health Checker Pattern

```python
def check_service(name, check_fn):
    start = time.time()
    try:
        result = check_fn()
        return {"service": name, "status": "healthy", "ms": round((time.time()-start)*1000)}
    except Exception as e:
        return {"service": name, "status": "unhealthy", "error": str(e)}
```

### Command Pattern

Multi-function scripts with subcommands:

```python
COMMANDS = {
    "process": do_process,
    "status": do_status,
    "retry": do_retry,
}

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd in ("--help", "-h"): cmd = "help"
    COMMANDS.get(cmd, lambda: print(f"Unknown: {cmd}"))()
```

### Pipeline Pattern

Stage-isolated queues (pending → processing → completed → retry → failed):

```python
# Stage isolation
QUEUE_FILE = STATE_DIR / "queue.jsonl"
PROCESSING_FILE = STATE_DIR / "processing.jsonl"
COMPLETED_FILE = STATE_DIR / "completed.jsonl"
RETRY_FILE = STATE_DIR / "retry.jsonl"
FAILED_FILE = STATE_DIR / "failed.jsonl"

# No state collision between concurrent runs
```

### Declarative Config Pattern

Cron definitions as data arrays + deploy function:

```python
CRONS = [
    {"name": "scan", "schedule": "0 */4 * * *", "command": "python3 scan.py"},
    {"name": "process", "schedule": "0 */2 * * *", "command": "python3 pipeline.py process"},
    {"name": "report", "schedule": "0 23 * * *", "command": "python3 report.py"},
]

def deploy_crons():
    for cron in CRONS:
        # Deploy each cron definition
        pass
```

## 8. Metadata Flexibility

Skills must include a `metadata` section with at least one provider-specific harness. The validator accepts any of these:

| Harness | Use Case | Example Fields |
|---------|----------|----------------|
| `openclaw` | OpenClaw/Hemlock agents | `version`, `category`, `complexity`, `tags` |
| `openai` | OpenAI-compatible (ChatGPT, vLLM, LM Studio) | `type`, `parameters`, `endpoints` |
| `anthropic` | Claude API / Anthropic | `model`, `tools`, `max_tokens` |
| `google` | Gemini / Vertex AI | `model`, `extensions`, `project` |
| `mistral` | Mistral / Le Chat | `model`, `functions`, `agents` |
| `harness` | Generic fallback for any provider | `version`, `category`, `tags` |

**Minimum requirement**: At least one harness section must exist. Include the harnesses you actively test against. The `openclaw` section is recommended as the default for cross-platform compatibility.

## 9. Enterprise SKILL.md Structure

```markdown
---
name: skill-name
description: "[WHAT]. [PROVIDER compat]. [FREE-FIRST]. [WHEN to use]."
metadata:
  openclaw:
    version: "1.0"
    category: infrastructure
    complexity: enterprise
  openai:
    type: function
    parameters:
      - name: command
        type: string
  hermes:
    tags: [automation, tools]
    category: devops
version: 0.0.1
---

# Skill Name
[1-2 sentence overview]

## Provider Compatibility
[Table: Provider | Compatibility | Notes]

## Free-First Strategy
[Cost tier table + escalation rule]

## Core Stack
[Table: Component | Role | Cost | Free Alternative]

## Workflow: [Primary]
[Steps with reference links]

## Scripts
[Table: Script | Purpose]

## Enforced Output Statistics
[JSON format spec]

## Error Handling
[Error table + reference link]

## Enhancement Hooks
[Table: Skill | Enhancement | When]

## Key References
[Bulleted links with "when to read" guidance]

## Sources
[Table: Source | URL | Last Verified]
```

## 10. Consolidation Precision Protocol

### When Merging Skills

1. **Read ALL source files completely** before writing anything
2. **Map content to sections** — identify where each piece belongs
3. **Deduplicate** — same information in multiple sources, keep one copy
4. **Preserve unique features** — never drop skill-specific functionality
5. **Merge common modules** — shared code goes in shared location
6. **Update all references** — internal links point to new structure
7. **Verify completeness** — every source file's content appears somewhere
8. **Test consolidated skill** — validate structure and content

### Consolidation Checklist

- [ ] All source SKILL.md files read completely
- [ ] All reference files copied (no duplicates)
- [ ] All scripts merged (no conflicts)
- [ ] YAML frontmatter merged with combined description
- [ ] Content organized logically (not just appended)
- [ ] Duplicate sections removed
- [ ] Internal cross-references updated
- [ ] No information lost from any source
- [ ] Permissions set correctly (755/644)
- [ ] Validation passes on consolidated skill

### Methodical Precision Rules

| Rule | Description |
|---|---|
| **Exhaustive Read** | Read every file in every source skill before writing |
| **Section Mapping** | Create a mapping of where each section goes |
| **Lossless Merge** | Every piece of information must appear in output |
| **Conflict Resolution** | When sources disagree, document both and pick one |
| **Reference Integrity** | All links must resolve to valid targets |
| **Backward Compatibility** | Existing users can find equivalent content |
