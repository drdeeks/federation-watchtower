# Checklist Generator — Phase & Module Ref Format Requirements

> **Session origin:** 2026-07-13 — ERPv2 Cross-Chain Escrow Wallet blueprint. The `generate_checklist.py` script returned 0 phases and grouped all 8 SPECs under MOD-UNKNOWN because the blueprint format didn't match the generator's regex expectations.

---

## The Fixed Point

**`generate_checklist.py` is NOT to be modified.** The blueprint format must match what the generator expects, not the other way around. Changing the generator to work around one blueprint's formatting breaks every other blueprint in the ecosystem.

---

## Format That Works With the Generator

### Phase Headers

The generator extracts phases from `### PHASE-N: Title` headers (with "PHASE-" prefix):

```markdown
### PHASE-0: Foundation
### PHASE-1: Core Escrow Wallet
### PHASE-2: Cross-Chain Messaging
```

It does **NOT** extract from:
- `### N: Title` (no "PHASE-" prefix)
- `### SPEC-NNN: Title` (these are treated as specs grouped under a single module-derived phase)
- `### Phase N — Title` (only matches if "PHASE-" prefix is present in the regex)

The regex used:
```python
phase_pattern = r"### PHASE-(\d+)[a-z]?: ([^>\n]+)"
```

Case-insensitive match on "PHASE-" is required.

### Optional Phase Metadata

Within a phase section, the generator will also pick up tag/feature-flag metadata if present:

```python
tg = re.search(r"\*\*(?:Section )?Tag:\*\*\s*`?([^`\n]+)`?", section)
fl = re.search(r"\*\*(?:Feature )?Flag:\*\*\s*`?([^`\n]+)`?", section)
```

Both the bare form and the `init_blueprint.py`-scaffolded form are accepted:

```markdown
**Tag:** `[PHASE-0-v1]`
**Flag:** `FEAT_FOUNDATION`
```
```markdown
**Section Tag:** `[PHASE-0-v1]`
**Feature Flag:** `FEAT_FOUNDATION`
```

This metadata is optional — a phase with neither still extracts fine, just with empty `tag`/`flag` fields.

### Module Ref in SPEC Tables

The regex used to extract module references from SPEC sections:

```python
mod_match = re.search(r"\*\*Module Ref\*\s*\|\s*([^\|]+)", section)
```

This expects the **Module Ref** cell to appear as `**Module Ref** | MOD-001` — **WITHOUT a leading pipe character**.

If your table is:
```markdown
| **Module Ref** | MOD-001 |
```

The leading `|` before `**Module Ref**` blocks the match and all specs group under `MOD-UNKNOWN`.

**Workaround (if you must use the generator):**
```markdown
**Module Ref:** MOD-001
```
(Outside the table, as a description list item or bold label)

---

## Workarounds for Complex Blueprints

### Option 1: Write Part VI Manually (Recommended)

Add a **Part VI — Master Implementation Checklist** to your blueprint with explicit phase headers:

```markdown
# PART VI — MASTER IMPLEMENTATION CHECKLIST

## Phase 0 — Foundation

**Section Tag:** `[PHASE-0-v1]` | **Feature Flag:** `FEAT_FOUNDATION`

### Deliverables

- [ ] 0.1 ERC-4337 EntryPoint v0.7 deployed and verified on Base
- [ ] 0.2 ERPEscrowWallet implementation deployed via Foundry
- [ ] 0.3 Beacon proxy factory deployed on Base
...

### Validation Gate

- [ ] All unit tests passing
- [ ] `FEAT_FOUNDATION` enabled on staging
- [ ] Change log entry written
```

Then run the generator — it will find the `### Phase 0` headers and produce a correct checklist.

### Option 2: Adjust SPEC Table Format

If your blueprint uses SPEC sections and you want the generator to work:

1. Ensure phase headers use `### PHASE-N: Title` format (not SPEC-NNN)
2. In SPEC tables, avoid leading pipe on Module Ref row:
   ```markdown
   **Module Ref** | MOD-001
   **Feature Flag** | FEAT_EXAMPLE
   ```
   (No `|` at start of line)

---

## Generator Limitations Summary

| Limitation | Consequence | Workaround |
|------------|-------------|------------|
| Only parses `### PHASE-N: Title` | `### SPEC-NNN` or `### N: Title` returns 0 phases | Add Part VI with `### Phase N` headers |
| Module ref regex blocks on leading `|` | All specs → MOD-UNKNOWN | Use `**Module Ref:** MOD-XXX` outside table |
| Groups all SPECs by module, loses phase order | Checklist phases = module groups, not build order | Manual Part VI preserves intended sequence |
| No Part VI → no phases found | Generator produces empty checklist | Part VI is mandatory for checklist generation |

**Bottom line:** The generator is for SIMPLE blueprints with direct `### PHASE-N` headers. For SPEC-heavy, module-grouped, cross-cutting blueprints — **write Part VI manually**. It's faster and more accurate.

---

## ERPv2 Reference Pattern

The ERPv2 Cross-Chain Escrow Wallet blueprint now uses:
- Part I–V: Full specification (1053 lines)
- Part VI: Manual master checklist with 8 explicit phases (Phase 0–7)
- Part VII: Quality standards (performance budgets, circuit breakers, testing requirements)
- Checklist generated from Part VI → 272 lines, 80+ deliverables, validation gates

This is the reference pattern for future complex blueprints.

---

## MV Maestro USB Integration Reference Pattern

The MV Maestro USB Integration blueprint follows the same pattern:
- Part I–V: Full specification (system overview, module registry, feature specs, data architecture)
- Part VI: Manual master checklist with 6 explicit phases (Phase 0–5: Foundation, Profile Engine, Menu System, Hemlock Integration, Testing, Launch)
- Part VII: Quality standards
- Checklist generated from Part VI

**Key learning:** The init_blueprint.py scaffold generates Part VI with `### PHASE-N: Title` headers that the checklist generator CAN parse. The problem was that the MV Maestro blueprint template from init_blueprint.py was using generic placeholder deliverables instead of actual USB+Hemlock-specific deliverables. When populating Part VI, replace placeholders with real deliverables but KEEP the `### PHASE-N: Title` header format.