# Common Chain Workflows

## Sequential File Build

The most common pattern. Files must be created in dependency order.

```bash
# Create chain
chain.py create my-project build \
  src/config.js \
  src/db.js \
  src/store.js \
  src/api.js \
  src/routes.js \
  src/index.js \
  public/index.html \
  public/app.js

# Agent workflow
chain.py check my-project build src/config.js  # → "active"
# ... write src/config.js ...
chain.py verify my-project build src/config.js  # → runs validator
chain.py complete my-project build src/config.js  # → unlocks src/db.js

# Next file auto-unlocked
chain.py check my-project build src/db.js  # → "active"
```

## Test-After-Each

Each source file has a paired test that must pass before the next source file unlocks.

```bash
chain.py create my-project tdd \
  src/utils.js tests/utils.test.js \
  src/db.js tests/db.test.js \
  src/api.js tests/api.test.js
```

## Blueprint-Guided Build

Follow a blueprint's phase order. Each phase is a step.

```bash
chain.py create my-project phases \
  blueprint-phase1.md \
  blueprint-phase2.md \
  blueprint-phase3.md

chain.py set-validator my-project phases blueprint-phase1.md scripts/validate_phase1.py
```

## Additive-Only Enforcement

Chain enforces that nothing is destroyed. Each step appends or creates new files.

```bash
# Chain tracks what was created at each step
# If a step tries to delete or overwrite a completed step, verification fails
# The validator script can enforce this rule
chain.py set-validator my-project build src/api.js scripts/validate_additive.py
```
