# Blueprint Required Sections Checklist

## PART I — System Overview
- Vision Statement (1.1)
- Architecture section
- Tech Stack section

## PART II — Module Registry
- Module ID column (MOD-NNN)
- Feature Flag column (FEAT_*)
- Module descriptions with ownership

## PART III — Specifications
- Screen specs with SCR-NNN
- Module refs (MODULE REF)
- Rollback tags per screen
- Feature flags per screen
- Purpose, Components, Rules, Error States, Fallback

## PART IV — Data Architecture
- Core Database Schemas (SQL)
- API Contracts (REST endpoints)
- Migration Naming Convention (V{NNN}__<description>.sql + rollback files)

## PART V — Change Control
- Change Log Entry Format (9 fields)
- Contributor Rules (min 6)
- Rollback Procedure Hierarchy (4 levels)

## PART VI — Implementation Checklist
- PHASE-N with rollback tags
- Prerequisites, Feature Flags
- Validation gates per phase
- Exit Criteria + Rollback Procedure

## PART VII — Quality & Compliance
- Error Handling Standards (5-level hierarchy)
- Testing Requirements (unit/integration/e2e/security)
- Performance Budgets (p95 targets)