# Skill Creator — Output Patterns

Patterns for structuring skill outputs: templates, examples, statistics blocks, and quality standards.

## Table of Contents

1. [Template Patterns](#1-template-patterns)
2. [Example Patterns](#2-example-patterns)
3. [Statistics Output](#3-statistics-output)
4. [Quality Standards](#4-quality-standards)

---

## 1. Template Patterns

### Pattern: Parameterized Template

When a skill generates code or documents, use parameterized templates with clear substitution points:

```python
TEMPLATE = '''
# {title}

Created: {timestamp}
Author: {author}

## Configuration

```json
{{
  "name": "{name}",
  "version": {version}
}}
```
'''

# Usage: TEMPLATE.format(title="My Project", timestamp=now_iso(), ...)
```

Key rules:
- Use `{single_braces}` for template variables
- Use `{{double_braces}}` for literal braces in the output (JSON, etc.)
- Document every template variable in the script's docstring
- Provide sensible defaults for optional variables

### Pattern: Conditional Sections

For templates where sections are included/excluded based on flags:

```python
def generate(config):
    sections = [HEADER_TEMPLATE.format(**config)]
    
    if config.get("include_auth"):
        sections.append(AUTH_SECTION.format(**config))
    
    if config.get("include_analytics"):
        sections.append(ANALYTICS_SECTION.format(**config))
    
    sections.append(FOOTER_TEMPLATE.format(**config))
    return "\n\n".join(sections)
```

### Pattern: Asset-Based Template

When the template is complex (e.g., a full project scaffold), store it in `assets/` rather than inline:

```
skill-name/
├── assets/
│   └── project-template/
│       ├── src/
│       │   └── index.ts
│       ├── package.json
│       └── tsconfig.json
```

The skill copies `assets/project-template/` to the target directory, then patches specific files.

## 2. Example Patterns

### Pattern: Input/Output Examples

Show concrete before/after for each operation the skill supports:

```markdown
## Example: Rotate PDF

**Input**: `document.pdf` (10 pages, portrait)
**Command**: `python3 scripts/rotate_pdf.py document.pdf --angle 90 --pages 1-5`
**Output**: `document_rotated.pdf` (pages 1-5 rotated 90° clockwise, pages 6-10 unchanged)
```

### Pattern: Progressive Complexity

Start with the simplest case, build to advanced:

```markdown
## Examples

### Basic: Single file processing
[simple example with minimal options]

### Intermediate: Batch processing with filtering
[example with multiple files and filter criteria]

### Advanced: Custom pipeline with error recovery
[example with full pipeline, retry logic, custom output format]
```

### Pattern: Realistic User Prompts

Show how real users would trigger the skill:

```markdown
## Trigger Examples

Users may say:
- "Convert this PDF to images"
- "Extract the text from pages 3-7"
- "Merge these three PDFs into one"
- "Fill out this PDF form with these values"

Each triggers a different workflow branch (see Decision Tree above).
```

## 3. Statistics Output

### Per-Operation Statistics

Every skill operation should conclude with structured output:

```json
{
  "operation": "operation_name",
  "timestamp": "2025-01-15T10:30:00Z",
  "status": "success",
  "duration_seconds": 2.3,
  "inputs": {"count": 1, "source": "file_upload", "size_bytes": 1048576},
  "outputs": {"count": 1, "type": "pdf", "size_bytes": 524288},
  "errors": [],
  "metrics": {"pages_processed": 10, "compression_ratio": 0.5},
  "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
}
```

### Aggregated Reports

For skills with scheduled or batch operations:

```json
{
  "operation": "daily_digest",
  "timestamp": "2025-01-15T23:59:00Z",
  "status": "success",
  "period": "daily",
  "metrics": {
    "total_operations": 47,
    "success_rate": 0.957,
    "avg_duration_seconds": 1.8,
    "total_inputs": 47,
    "total_outputs": 45
  },
  "cost": {"tier": 0, "total_usd": 0.0},
  "errors": [{"type": "decode_error", "count": 2}],
  "top_operations": ["rotate", "merge", "extract"]
}
```

### Storage Pattern

```python
def append_jsonl(filepath, record):
    """Append a JSON record to a JSONL file (one record per line)."""
    Path(filepath).parent.mkdir(parents=True, exist_ok=True)
    with open(filepath, "a") as f:
        f.write(json.dumps(record) + "\n")

# Always append — never overwrite
append_jsonl("analytics/run_stats.jsonl", stats)
```

## 4. Quality Standards

### Output Validation Checklist

Before delivering any output, verify:

| Check | Pass Criteria |
|---|---|
| File exists | Output file was created and is non-empty |
| Format correct | Output matches expected format (PDF, JSON, etc.) |
| Size reasonable | Within ±50% of expected size |
| No corruption | File opens/parses without errors |
| Content accurate | Spot-check key content matches input |

### Error Output Standard

When an operation fails, still produce structured output:

```json
{
  "operation": "rotate_pdf",
  "timestamp": "2025-01-15T10:30:00Z",
  "status": "failed",
  "duration_seconds": 0.1,
  "inputs": {"count": 1, "source": "file_upload"},
  "outputs": {"count": 0},
  "errors": [{"type": "decode_error", "message": "File is not a valid PDF"}],
  "cost": {"tier": 0, "amount_usd": 0.0}
}
```

Never silently fail. Always produce a status record, even on failure.
