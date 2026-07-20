# Checklist Tool Consolidation

## What Changed

`enforce_blueprint.py` was **deleted** and its functionality merged into `generate_checklist.py`.

## Before

```
blueprint.md ──→ generate_checklist.py ──→ checklist.md
                                            └──→ checklist-data.json
                                                     └──→ enforce_blueprint.py --init
                                                              enforce_blueprint.py verify
                                                              enforce_blueprint.py complete
```

Two separate scripts — `generate_checklist.py` writes outputs, `enforce_blueprint.py` reads them to manage chain state.

## After

```
blueprint.md ──→ generate_checklist.py generate ──→ checklist.md
                                                     └──→ checklist-data.json ←──── init
                                                                                   verify
                                                                                   complete
                                                                                   status
```

One unified script. Subcommands for everything: `generate`, `init`, `verify`, `complete`, `status`, `check`, `menu`, `generate-validators`.

## Why

- Single source of truth is enforced at the tool level too — no second tool that could drift
- Simpler mental model: one entry point, one help page, one set of docs
- Backward compat maintained: old `--init`, `--status`, `--phase`, `--step`, `--verify`, `--complete` flags still work when passing a project directory as positional arg

## Legacy Paths

Any code that calls `enforce_blueprint.py` should be updated to call `generate_checklist.py` with the same positional args. The old `--blueprint` and `--checklist` flags are accepted but ignored (documented as such).
