# Skill Creator — Workflow Design Patterns

Patterns for structuring workflows, conditional logic, and multi-step procedures within skills.

## Table of Contents

1. [Workflow Structures](#1-workflow-structures)
2. [Decision Trees](#2-decision-trees)
3. [Conditional Branching](#3-conditional-branching)
4. [Multi-Phase Workflows](#4-multi-phase-workflows)

---

## 1. Workflow Structures

### Sequential Workflow

Best for: linear processes where steps must execute in order.

```markdown
## Workflow: Process Data

### Step 1: Validate Input
Check file format, size, and encoding. Reject unsupported formats with clear error message.

### Step 2: Extract Content
Parse the validated file using [tool]. Output structured data.

### Step 3: Transform
Apply business rules to the extracted data.

### Step 4: Output
Generate the final artifact and report statistics.
```

### Branching Workflow

Best for: processes where the path depends on input characteristics.

```markdown
## Workflow Decision Tree

1. Determine the input type:
   - **If PDF**: → See [Workflow: PDF Processing](#workflow-pdf-processing)
   - **If DOCX**: → See [Workflow: DOCX Processing](#workflow-docx-processing)
   - **If image**: → See [Workflow: Image Processing](#workflow-image-processing)
2. All paths converge at: → [Step: Quality Check](#quality-check)
```

### Parallel Workflow

Best for: independent subtasks that can run concurrently.

```markdown
## Workflow: Full Analysis

Execute these in parallel:
1. **Audio analysis** — Extract frequency features (see scripts/analyze.py)
2. **Visual generation** — Generate 3D scene (see references/scene-guide.md)
3. **Metadata extraction** — Parse file metadata

When all complete → Merge results into final report.
```

## 2. Decision Trees

Use decision trees when the agent must choose between approaches based on context.

### Pattern: Input-Driven Decision

```markdown
## Approach Selection

Evaluate the request and select the approach:

| If the user wants... | Then use... | Because... |
|---|---|---|
| Simple text extraction | `pdfplumber` | Fast, reliable for text-heavy PDFs |
| Form field extraction | `scripts/extract_fields.py` | Handles AcroForm and XFA |
| Visual layout preservation | `pdf2image` + OCR | Maintains spatial relationships |
| Batch processing | `scripts/pipeline.py` | Parallel processing with retry |
```

### Pattern: Capability-Gated Decision

```markdown
## Tool Selection

1. Check if `playwright` MCP is available:
   - **Yes**: Use browser automation for dynamic content
   - **No**: Fall back to `firecrawl` or static fetch
2. Check if target requires authentication:
   - **Yes**: Use stored credentials from config
   - **No**: Proceed with anonymous access
```

## 3. Conditional Branching

### Pattern: Quality Gate

Insert quality checks between phases to catch issues early:

```markdown
## Quality Gate: Post-Generation Check

Before proceeding to the next phase:
1. Verify output file exists and is non-empty
2. Validate output format matches specification
3. Check output size is within expected range (±50%)

**If any check fails**: Log the failure, attempt recovery, report to user.
**If all pass**: Proceed to next phase.
```

### Pattern: Escalation Chain

```markdown
## Error Escalation

1. **Attempt primary approach** (preferred tool)
2. If primary fails → **Attempt fallback** (alternative tool)
3. If fallback fails → **Attempt manual workaround** (documented procedure)
4. If all fail → **Report to user** with diagnostic information and suggested next steps
```

## 4. Multi-Phase Workflows

### Pattern: Build Bottom-Up

For skills with complex outputs, build foundational components first:

```markdown
## Creation Workflow

### Phase 1: Foundation
Build the core data structures and utilities.
- Create config schema
- Initialize state directories
- Validate environment

### Phase 2: Core Logic
Implement the primary functionality.
- Build processing pipeline
- Implement transformation rules
- Add output formatting

### Phase 3: Hardening
Add resilience and polish.
- Error handling for all failure modes
- Performance optimization
- Output statistics enforcement

### Phase 4: Packaging
Prepare for distribution.
- Run validation (`validate_enterprise.py`)
- Package (`package_skill.py`)
- Test with real use cases
```

### Pattern: Iterative Refinement

```markdown
## Improvement Workflow

1. **Use** the skill on a real task
2. **Observe** where it struggles or produces suboptimal results
3. **Diagnose** whether the issue is:
   - Missing context → Add to SKILL.md or references/
   - Repeated boilerplate → Extract to scripts/
   - Wrong approach → Update workflow decision tree
4. **Fix** the identified issue
5. **Validate** the fix doesn't break other workflows
6. **Repeat** from step 1
```
