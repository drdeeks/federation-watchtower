# Provider Tag Remapping

Canonical skill tags live in `metadata.tags` in SKILL.md frontmatter — **the source of
truth, never altered**. Different provider harnesses consume tags from their own metadata
block; a skill that only carries canonical tags passes validation but is invisible to a
provider's promotion/surfacing logic. `skill_enhance.py` closes that gap: before packaging,
it copies canonical tags into each relevant provider block (additive, idempotent).

## Supported providers

| Provider | Tag block written | Detection signals (env) | Official site / docs |
|----------|-------------------|-------------------------|----------------------|
| Hermes | `metadata.hermes.tags` | any `HERMES_*` var, or `HEMLOCK_MODE=full\|hermes` | <https://nousresearch.com> · <https://github.com/NousResearch> |
| OpenClaw | `metadata.openclaw.tags` | any `OPENCLAW_*` var, or `HEMLOCK_MODE=full\|openclaw` | <https://openclaw.ai> · <https://docs.openclaw.ai> |
| OpenAI | `metadata.openai.tags` | any `OPENAI_*` var | <https://openai.com> · <https://platform.openai.com/docs> |

## How it runs

- **Agent/pipeline (non-interactive):** automatic — providers are detected from the
  environment and remapped silently before the package gate. No prompts.
- **Explicit:** `skill_enhance.py update --path <skill> --provider hermes --provider openclaw`
  (repeatable flag; overrides detection).
- **No provider found:** the skill ships with canonical tags only, and the pipeline says so —
  informative, never forced.

## Frontmatter shape after remap

```yaml
metadata:
  tags: [a, b, c, d, e, f, g]      # canonical — source of truth
  hermes:
    tags: [a, b, c, d, e, f, g]    # copied — consumed by the runtime skill registry
  openclaw:
    tags: [a, b, c, d, e, f, g]    # copied — reserved for OpenClaw promotion
```

## Rules

1. Canonical `metadata.tags` is never modified by the remap.
2. Remap is additive: existing keys inside a provider block are preserved; only `tags` is set.
3. Idempotent: rerunning produces no change when blocks already match canonical.
4. Threshold policy is unchanged: ≥7 tags enterprise, ≥5 basic — validated against canonical.
5. New providers: add a row here (with official doc links) and extend `SUPPORTED_PROVIDERS`
   in `scripts/skill_enhance.py`; contributions of provider schemas are welcome via PR to
   the skills repo.
