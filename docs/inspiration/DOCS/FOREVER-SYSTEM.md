# THE FOREVER SYSTEM — Foundational Protocol

> Singular source of truth for how every project, skill, agent, and artifact is
> built. This document OUTRANKS every README, SKILL.md, and architecture doc in
> the repository. When anything contradicts this, this wins.
>
> Author: drdeeks. Voice: plain, architectural, no hand-waved syntax.
> Applies to: ALL repos (agent-identity-kit, Canon OS, the five track agents,
> the skills repo, the USB/runtime tooling, and anything built hereafter).

---

## 0. THE ONE IDEA

A system is "forever" when it can accept new layers without breaking its core,
and can be plugged into any other system without rewriting itself.

That single property implies everything else in this document:

- Layerable  → adaptable
- Adaptable  → integrable into anything
- Integrable → platform/path agnostic by nature
- Agnostic   → self-resolving (finds its own resources, hardcodes nothing)
- Self-resolving + layered → robust (a layer fails, the core survives)
- Layered + verifiable → scalable (add layers, trust holds)

If a design satisfies "constantly layerable," it automatically satisfies
"constantly adaptable, integrable, scalable, agnostic, true to core." That is
the whole thesis. Every rule below is a consequence of it.

---

## 1. SINGULAR SOURCE OF TRUTH (hard rule)

One canonical location per concern. Not "a readme mentions it." One file, one
service, one port, one skill — that IS the truth. Everything else references it.

- A concept implemented in code exists in EXACTLY ONE module. No second copy
  with a similar name, no "I'll just re-implement it here." Duplication is the
  primary disease; it is forbidden by structure, not by politeness.
- If two skills/agents both need "enforce character," they DECLARE what they
  enforce and ROUTE through the one runtime that enforces. They do not each
  contain their own enforcement logic.
- Documentation that describes behavior MUST point at the one file that
  implements it. A doc that describes behavior no single file owns is a lie.

**Violation examples (seen in this repo, to be eradicated):**
- `brand_extraction.py` AND `brand_extractor.py` (Canon OS) — two sources,
  zero truth. One must die; the other becomes the singular source.
- `agent-identity-architecture`, `tool-enforcement`, `loop-enforcer`,
  `guardrail-enforcement` skills each re-implement enforcement — four truths,
  none singular. Core enforcement MUST collapse into one runtime (ACK enforcer);
  the skills become declarations, not implementations.

---

## 2. SELF-RESOLVING PATHS (hard rule)

Every component resolves its own paths from: env override → home default →
built-in default. Resolved FRESH on every call, never cached at import, never
hardcoded. This is what makes a thing "plug-in play" — drop it on any machine,
any OS, any container, and it finds itself. No installer ceremony.

- Paths are computed at use-time, not module-load-time.
- No absolute paths in source. No `/home/drdeeks/...` literals.
- Agnostic to where it runs: bare metal, Ventoy USB, container with persistent
  state, CI runner. Same code, different env, zero changes.

---

## 3. LAYERED, NEVER REWRITTEN (hard rule)

Updates stack ON TOP. The base never changes. New behavior = new layer with an
ID. Removing behavior = pop the layer. This is the "forever" guarantee.

- Each layer carries: an ID, a timestamp, what it adds, what it supersedes.
- Rollback is O(1): remove the top layer, core is intact exactly as before.
- The enforcer's `reload()` is the seed of this — but it must become VERSIONED
  layers, not "reload overwrites." Reload that mutates truth is rewrite, not
  layer. Forbidden.
- A layer that changes core behavior without an ID and a supersedes pointer is
  a rewrite disguised as an update. Forbidden.

---

## 4. FAIL-CLOSED, TAMPER-EVIDENT (honest claim)

- **Fail-closed:** when the system is unsure (enforcer unreachable, config
  missing, policy ambiguous) it BLOCKS, not allows. A guard that fails open is
  no guard. This is already correct in ACK; it is mandatory everywhere.
- **Tamper-EVIDENT (not tamper-PROOF):** any change to the core
  (foundations + constitution + habits + policy) changes a published hash and
  is logged + visible. We do NOT claim tamper-proof. A 32-bit string hash is
  detection, not protection. Say "evident," mean "evident."
- The audit trail MUST NOT silently swallow failures. If the enforcer cannot
  write its audit log, that is the moment of maximum need to know — surface it,
  do not `catch {}` it into the void.

---

## 5. PLATFORM / PATH AGNOSTIC + MODULAR (hard rule)

- One standard, many runtimes. ACK proves this works: Node daemon + Python
  client, same policy, same audit, same fail-closed.
- Each module is independently swappable. A module that cannot be removed
  without breaking others was not modular — it was coupled. Redesign it.
- "Plugin" is not a string in a doc. A plugin is a registered, loadable unit
  the running system actually calls. ACK's Hermes/OpenCode hook is currently a
  suggestion in a string (lines 253–277 of hooks/identity.js). That is NOT
  integration. It must become a real registered plugin before it counts.

---

## 6. CONTINUOUSLY-REMINDED CHARACTER (the missing layer)

Enforcement today is NEGATIVE: block bad actions. That cannot stop DRIFT —
the agent slowly contradicting its own purpose file by file (the Canon OS
disease). Drift needs an AFFIRMATIVE layer.

- A `foundations.yaml` holds 3–7 POSITIVE statements of who the agent is
  (e.g. "I track every file I create and never leave duplicates," "I record
  what I did and why before I move on"). Separate from constitution (hard
  constraints) and enforcer.yaml (gates).
- At EVERY pre-tool-call, the enforcer re-asserts the relevant foundation into
  the agent's working context — not just logs it. Current code only emits a
  `reflection` on DENIAL. Invert it: reminder fires on EVERY action, affirming
  character affirmatively.
- The enforcer watches for character-drift SIGNALS in the action itself — e.g.
  creating a second file near-identical to an existing one. That is a
  positive-policy violation, not a hard-constraint violation. Warn + remind, do
  not necessarily deny.
- `character_hash` (renamed from `identity_hash`) hashes foundations +
  constitution + habits together, so any change to "who I am" is visible.

---

## 7. VERIFIABLE WITHOUT READING CODE (the non-coder leverage)

The author of these systems cross-references and reads, but does not hand-format
syntax. Therefore truth MUST be observable without opening a file:

- Every project runs its own tests in CI on every change. Green badge = truth.
  Red badge = stop. The badge is the source of truth for "does it work," not
  the README's self-praise.
- ACK currently runs 7/8 tests (one fails on environment isolation, not logic).
  It has NO CI. That is a violation of this rule. Fix the test, add CI, badge
  it. Until then, ACK is "claimed working," not "verified working."
- A system that cannot prove it works is not forever. It is hoped.

---

## 8. THE BINDING MAP (how the pieces relate)

```
FOREVER-SYSTEM.md          ← the contract (this file). Outranks all.
        │
        ├── skills repo     ← the LAYERED implementation. Each skill = one layer.
        │     └── ALL enforcement routes through ONE runtime, never re-implemented.
        │
        ├── agent-identity-kit (ACK)  ← the runtime that ENFORCES the contract.
        │     └── enforcer daemon = the singular enforcement core.
        │
        └── the six projects (Canon OS + 5 track agents)  ← CONSUMERS.
              They plug INTO ACK as layers. They do NOT each rebuild enforcement.
```

The waste to eliminate: five agents + Canon OS each re-implementing a half-built
foundation instead of plugging into the one forever-system. One core. Many
consumers. Zero duplicated truth.

---

## 9. DEFECTS KNOWN AT TIME OF WRITING (to be closed, not hidden)

1. ACK audit log silently swallows errors (bare `catch {}` in two places).
   Violates §4. Surface the failure.
2. ACK "tamper-proof" claim is false; it is tamper-EVIDENT at best. Violates §4.
   Change the claim, upgrade the hash to sha256 minimum.
3. ACK Claude-allow test fails on environment isolation (no test workspace).
   Violates §7. Fix the test to inject its own config.
4. Canon OS has duplicate `brand_extraction`/`brand_extractor`. Violates §1.
   Collapse to one.
5. ACK Hermes/OpenCode hook is a string, not a registered plugin. Violates §5.
   Make it real.
6. No CI on ACK or any project. Violates §7. Add it.

---

## 10. THE TEST OF "FOREVER"

Before shipping any artifact, it must answer YES to all:

- [ ] One source of truth for every concept it touches? (§1)
- [ ] Resolves its own paths, no hardcoded absolutes? (§2)
- [ ] Updates add layers, never rewrite core? (§3)
- [ ] Fails closed; tamper-EVIDENT (not -proof)? (§4)
- [ ] Platform/path agnostic; plugins are real, not suggested? (§5)
- [ ] Affirmatively reminds character at every action? (§6)
- [ ] Proves it works via CI badge, not prose? (§7)

Any NO = not forever yet. Keep layering until all YES.

---

*This document is itself a layer: v1, supersedes nothing, authored by drdeeks.
Amend by adding a new numbered section or a new layer pointer — never by
silent edit of an existing rule's meaning.*
