# Creator Delegation Contract

How skill-installer validates without owning any validation rules.

## The rule

skill-creator's `scripts/validate.py` is the **single source of truth** for
what a valid skill is. skill-installer must never fork, copy, embed, or
re-implement any of its rules. When skill-creator's standards evolve, the
installer is automatically current because every verdict comes from a live
subprocess call — there is nothing here to drift out of sync.

History note: earlier versions of this skill embedded a copied ruleset and
even base64-encoded pattern data to evade the hardcoded-path scan. Both are
exactly the class of validator-cheating this contract exists to prevent.
Rules live in one place; everyone else asks.

## Locator order

`validate_install.py:find_validator()` resolves the validator in this
order, first hit wins:

1. `$SKILL_CREATOR_DIR` — explicit override, points at the skill-creator dir
2. Sibling directory — `<skills-root>/skill-creator` next to this skill
3. `$OPENCODE_SKILLS_DIR/skill-creator`
4. `~/.config/opencode/skills/skill-creator` — legacy default location
5. **The bundled copy** — `scripts/validate.py` inside this skill

A live candidate counts only if `scripts/validate.py` exists inside it. If
nothing resolves at all, validation returns a hard error and **the install
is refused** — the installer never proceeds unvalidated and never invents
rules of its own.

## The bundled copy (standalone mode)

So that nobody is forced to install two skills, skill-installer ships a
**byte-identical copy** of skill-creator's `validate.py` (and its
`skill_root.py` dependency) inside its own `scripts/`. A recipient who grabs
only `skill-installer.skill` gets working validation out of the box.

Rules for the copy — this is distribution, not forking:

- It must stay **byte-identical** to skill-creator's validator. Verify with
  a hash compare; any difference means it's stale or was tampered with.
- It is **never edited in place**. When skill-creator's validator changes,
  the copy is overwritten wholesale from the source.
- A live skill-creator, when present, always wins over the bundled copy
  (it carries the freshest rules).

## Delegation call

```bash
python3 <skill-creator>/scripts/validate.py <skill_dir> --json [--basic]
```

- Installs validate at **basic** tier by default (a third-party skill need
  not be enterprise to be installable); pass `--enterprise` to gate harder.
- The JSON verdict's `valid` field is authoritative. `fails` and `checks`
  are relayed for diagnostics.
- Both the pre-install check and the post-install re-check use the same
  delegation path.

## Consumers inside this skill

| Caller | Uses |
|---|---|
| `scripts/validate_install.py` | CLI entry — locate + delegate + relay verdict |
| `scripts/install_skill.py` | pre-install gate and post-install re-check |
| `scripts/batch_install.py` | inherits via `install_skill.py` |
| `scripts/validate.py` | self-check of skill-installer through the same path |
