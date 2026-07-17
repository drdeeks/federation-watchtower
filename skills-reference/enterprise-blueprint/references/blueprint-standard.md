# Blueprint Standard Reference (v2)

Complete specification of the enterprise blueprint structure: required parts,
section anatomy, rollback tag conventions, module registry format, screen
specification format, change log protocol, and quality thresholds.

## Table of Contents

1. [Required Document Structure](#1-required-document-structure)
2. [Document Header Standard](#2-document-header-standard)
3. [Part-by-Part Specification](#3-part-by-part-specification)
4. [Rollback Tag Convention](#4-rollback-tag-convention)
5. [Module Registry Format](#5-module-registry-format)
6. [Screen & Feature Specification Format](#6-screen--feature-specification-format)
7. [Change Log Protocol](#7-change-log-protocol)
8. [Amendment Procedure](#8-amendment-procedure)
9. [Quality Thresholds](#9-quality-thresholds)
10. [Minimum Completeness Requirements](#10-minimum-completeness-requirements)

---

## 1. Required Document Structure

Every enterprise blueprint MUST contain exactly these seven parts in order.

```
PART I    — SYSTEM OVERVIEW & ARCHITECTURE
PART II   — MODULE REGISTRY
PART III  — SCREEN & FEATURE SPECIFICATIONS
PART IV   — DATA ARCHITECTURE
PART V    — CHANGE CONTROL PROTOCOL
PART VI   — MASTER IMPLEMENTATION CHECKLIST
PART VII  — QUALITY & COMPLIANCE STANDARDS
CHANGE LOG (appended after Part VII)
```

## 2. Document Header Standard

```markdown
# Project Name — ENTERPRISE BLUEPRINT
## Version N.N | Document Class: MASTER SPECIFICATION
### Generated: YYYY-MM-DD

> **READ FIRST — DOCUMENT AUTHORITY**
> [Authority statement — minimum 2 sentences]
```

## 3. Part-by-Part Specification

### Part I — System Overview & Architecture

| Subsection | Requirement |
|---|---|
| 1.1 Vision Statement | 2-3 sentences on what, who, and defining principle |
| 1.2 High-Level Architecture | **50+ line ASCII diagram** with box-drawing characters (┌┐└┘├┤┬┴┼─│) |
| 1.3 Tech Stack | Table: Layer, Technology, Rationale |
| 1.4 Architectural Principles | 6 numbered items |
| 1.5 System Components | Table: Component, Role, Technology, Location |

**The ASCII architecture diagram is MANDATORY.** A simple text description is not sufficient.

### Part II — Module Registry

Table with exactly four columns: Module ID, Name, Description, Feature Flag.
Module IDs: `MOD-NNN` (zero-padded). **Minimum 3 modules.**

### Part III — Screen & Feature Specifications

ALL fields are mandatory:
```
FEATURE ID, MODULE REF, ROLLBACK TAG, FEATURE FLAG,
PURPOSE, COMPONENTS (5+), RULES (5+), ERROR STATES (3+), FALLBACK
```

**Minimum 3 feature specifications** per blueprint.

### Part IV — Data Architecture

| Subsection | Requirement |
|---|---|
| 4.1 Core Database Schemas | SQL CREATE TABLE statements (minimum 3 tables) |
| 4.2 API Contract Specifications | Endpoint list: method, path, description (minimum 3) |

Every table: PRIMARY KEY, created_at, updated_at.

### Part V — Change Control Protocol

9-field entry format, 6+ contributor rules, rollback hierarchy, migration naming: `YYYYMMDD_NNN_description.sql`

### Part VI — Master Implementation Checklist

Every phase MUST have: Section Tag, Feature Flag, Prerequisite, **Deliverables**, **Validation Gate**, Rollback Procedure.

### Part VII — Quality & Compliance Standards

- 5-level error hierarchy: Input Validation → API → Module → Network → System
- Testing: unit ≥80%, integration, E2E
- Performance budgets with **concrete metric values** (e.g., "200ms", "1GB")
- Circuit breaker / retry policy

## 4-8. Rollback Tags, Module Registry, Spec Format, Change Log, Amendment

See enterprise-rules.md for full detail.

## 9. Quality Thresholds

| Rating | FAIL | WARN |
|---|---|---|
| Enterprise Grade | 0 | 0-4 |
| Production Ready | 0 | 5-9 |
| Needs Hardening | 0 | 10-14 |
| Incomplete | 1-3 | any |
| Not Enterprise Grade | 4+ | any |

## 10. Minimum Completeness Requirements

| Requirement | Minimum | Enforcement |
|---|---|---|
| Document length | 1500+ lines | FAIL |
| ASCII architecture diagram | 50+ lines, box-drawing chars | FAIL |
| Modules defined | 3+ | WARN |
| Feature specifications | 3+ with all fields | FAIL |
| SQL table schemas | 3+ | WARN |
| API endpoints | 3+ | WARN |
| Phase deliverables + gates | 3+ each | FAIL |
| Error handling levels | 5-level hierarchy | WARN |
| Performance budgets | 6+ concrete metrics | WARN |
| Rollback procedures | 1 per phase | WARN |
| Change log entries | 1+ with 9 fields | FAIL |
| No TODOs/placeholders | 0 [TODO], ≤5 [Define...] | WARN |
