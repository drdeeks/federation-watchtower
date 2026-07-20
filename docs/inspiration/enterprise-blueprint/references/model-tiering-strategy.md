# Model Tiering Strategy — Token-Optimized Pipeline
#
# FOREVER SYSTEM §6: "A `foundations.yaml` holds 3–7 POSITIVE statements of who
# the agent is... At EVERY pre-tool-call, the enforcer re-asserts the relevant
# foundation into the agent's working context — not just logs it."
#
# This document IS the foundations for model assignment. The enforcer reminds:
# "You are ui-a1b2. Phase 3 uses qwen3.5-flash for iteration. Thinking OFF."
#
# Created: 2026-07-14
# Source: interactive_setup.py, agent-model-map-template.yaml
# Layer: model-tiering-v1

---

## THE PRINCIPLE

**Every agent uses TWO models per task type:**
- **ITERATION model** (flash/turbo): Fast, cheap, used during revision loops (80% of invocations)
- **FINAL model** (plus/max): Expensive, used ONLY when artifact passes evaluation (20%)

**Token savings: ~60-70% reduction** by using flash for 80% of invocations.

---

## CANONICAL MODEL TIERS

### Text Models — Reasoning & Writing

| Tier | Qwen | OpenAI | Anthropic | Use Case | Cost | Invocations | Thinking |
|------|------|--------|-----------|----------|------|-------------|----------|
| **Maximum Reasoning** | qwen3-max | o1-pro | claude-opus-4 | Executive vision, final review, prompt optimization | Highest | 2-3/project | Enable for synthesis |
| **Strong Reasoning** | qwen3.5-plus | o1 | claude-sonnet-4 | Planning, writing, structure | Medium | 5-10/project | Disable unless structural |
| **Fast Iteration** | qwen3.5-flash | gpt-4o-mini | claude-haiku-3.5 | Revision loops, quick eval, format validation | Lowest | Unlimited | ALWAYS disable |
| **Bulk Operations** | qwen-turbo | gpt-3.5-turbo | claude-haiku-3 | Log parsing, file validation, metadata extraction | Minimal | Unlimited | ALWAYS disable |

### Vision Models — Visual Understanding & Evaluation

| Tier | Qwen | OpenAI | Anthropic | Use Case | Cost | Invocations |
|------|------|--------|-----------|----------|------|-------------|
| **High Precision** | qwen3-vl-plus | gpt-4o | claude-opus-4 | Quality review, composition analysis | High | 3-5/scene |
| **Fast Analysis** | qwen3-vl-flash | gpt-4o-mini | claude-sonnet-4 | Reference analysis, quick checks | Low | Unlimited |

### Image Generation — Storyboards & Key Frames

| Tier | Model | Use Case | Cost | Strategy |
|------|-------|----------|------|----------|
| **Iteration** | wan2.2-t2i-flash | Storyboard drafts, composition testing | Low/gen | Generate 2-3 variants, pick best, discard rest |
| **Final** | wan2.6-t2i | Final storyboard frames, key frames | Medium/gen | Generate only after iteration approved |
| **Editing** | wan2.6-image | Style transfer, character consistency | Medium/gen | Use reference images from prior shots |

### Video Generation — Core Pipeline (Wan / HappyHorse)

| Tier | Model | Use Case | Cost | Resolution | Duration | Strategy |
|------|-------|----------|------|------------|----------|----------|
| **Iteration** | wan2.6-i2v-flash | Quick motion previews, timing checks | Low/clip | 720p | 2-3s | Generate short clips first, validate motion |
| **Quality** | wan2.7-i2v | Final video shots for assembled drama | High/clip | 1080p | 5-10s | Generate only after flash preview passes review |
| **Text-to-Video** | wan2.6-t2v | Establishing shots, abstract sequences | Medium/clip | 720p-1080p | 5-10s | Use when no key frame reference exists |
| **With Audio** | wan2.7-t2v | Hero shots with auto-dubbing | Highest | 720p/1080p | 5-10s | Reserve for audio-critical shots |
| **Keyframe** | wan2.2-kf2v-flash | Transitions between defined frames | Low | 720p | 5s | Use first+last frame from storyboard |

### Audio Models — Voice & Music

| Tier | Model | Use Case | Cost |
|------|-------|----------|------|
| **Voice Iteration** | cosyvoice-v3-flash | Dialogue drafts, timing tests | Low |
| **Voice Final** | cosyvoice-v3-plus | Final narration and dialogue | Medium |
| **Style Voice** | qwen3-tts-instruct-flash | Emotion-specific performance | Low |

---

## PHASE → MODEL ASSIGNMENT MATRIX

| Phase | Agent | Create Model | Revise Model | Rationale |
|-------|-------|--------------|--------------|-----------|
| **PHASE-0** Foundation | Executive Director | maximum_reasoning | strong_reasoning | Vision synthesis needs depth |
| | Narrative Architect | strong_reasoning | fast_iteration | Beats need structure, revise fast |
| **PHASE-1** Architecture | Executive Director | maximum_reasoning | strong_reasoning | Holistic review |
| | Narrative Architect | strong_reasoning | fast_iteration | Structure refinement |
| | Screenwriter | strong_reasoning | fast_iteration | Dialogue writing |
| **PHASE-2** Implementation | Screenwriter | strong_reasoning | fast_iteration | Scene writing |
| | Storyboard Artist | vision_fast | vision_fast | Visual iteration |
| | Cinematographer | vision_fast | vision_fast | Reference analysis |
| | Prompt Composer | maximum_reasoning | fast_iteration | Prompt optimization |
| **PHASE-3** Generation | Generation Engine | video_iteration/image_iteration/voice_iteration | (same) | Flash for all generation |
| **PHASE-4** Quality | Quality Reviewer | vision_high | vision_fast | Precision eval, quick checks |
| | Director | maximum_reasoning | fast_iteration | Final approval |
| **PHASE-5** Assembly | Assembly Engine | fast_iteration | fast_iteration | Fast assembly logic |

---

## TOKEN REDUCTION STRATEGIES (Enforced by Model Map)

| Strategy | Description | Token Savings |
|----------|-------------|---------------|
| **Flash-first iteration** | Always generate with flash models first. Upgrade only after evaluation passes. | 40-60% generation |
| **Retrieve don't remember** | Semantic search for relevant context only. Never load full project. | 50-70% input |
| **Working memory isolation** | Each agent loads only its own input artifacts. | 60-80% input |
| **Regenerate only failure** | When QA fails a scene, only that scene regenerates. | 70-90% revision |
| **Thinking OFF by default** | Enable thinking only for creative vision + final review. | 30-50% output |
| **Context caching** | Cache Creative Brief for repeated reference. | 20-30% repeated input |
| **Batch API** | 50% off for non-realtime bulk generation. | 50% applicable gen |
| **Short clips first** | 2-3s flash clips for motion validation before 5-10s quality. | 50-70% video gen |

---

## ENFORCEMENT MECHANICS

### Pre-Tool-Call Reminder (FOREVER §6)
When agent invokes any tool, enforcer injects:

```
[CHARACTER REMINDER] You are ui-a1b2 (ui). 
Current phase: PHASE-3 (Implementation). 
Model: qwen3.5-flash (fast_iteration). 
Thinking: DISABLED. 
Strategy: Flash-first iteration. Retrieve don't remember.
```

### Phase Gate Validation
Before phase transition, enforcer verifies:
1. All checklist items for phase have `verified` state in `.blueprint-chain/`
2. Agent's model usage matches phase_model_map (audit via token logs)
3. Token budget not exceeded (alert at 75%)

### Token Budget Tracking
Per-project token accounting:
```yaml
# In crew-model-map.yaml or agent-model-map.yaml
token_budget:
  total_estimate: 151500
  phases:
    PHASE-0: 7000
    PHASE-1: 4000
    PHASE-2: 49000
    PHASE-3: 74000
    PHASE-4: 15000
    PHASE-5: 2000
  alert_threshold: 0.75  # 75%
  hard_limit: 1.0        # 100%
```

---

## PROVIDER ABSTRACTION

Model tiers are **canonical names** — resolved to provider-specific IDs at runtime:

```yaml
# In agent-model-map.yaml
provider_mapping:
  qwen:
    maximum_reasoning: "qwen3-max"
    fast_iteration: "qwen3.5-flash"
    ...
  openai:
    maximum_reasoning: "o1-pro"
    fast_iteration: "gpt-4o-mini"
    ...
  anthropic:
    maximum_reasoning: "claude-opus-4"
    fast_iteration: "claude-haiku-3.5"
    ...
```

### Runtime Resolution
```python
def resolve_model(tier: str, provider: str = None) -> str:
    provider = provider or os.environ.get("MODEL_PROVIDER", "qwen")
    return model_tiers[provider].get(tier, model_tiers["qwen"][tier])
```

---

## TEMPLATE USAGE

### For New Agent
```bash
python3 scripts/interactive_setup.py ./my-agent --blueprint ./blueprint.md
# Generates: ./my-agent/agent-model-map.yaml
```

### For New Crew
```bash
python3 scripts/interactive_setup.py ./my-crew --blueprint ./blueprint.md
# Generates: ./my-crew/crew-model-map.yaml + each agent's agent-model-map.yaml
```

### Validation
```bash
# Validate model map against skill-creator enterprise standards
python3 .hermes/skills/skill-creator/scripts/skill_enhance.py update \
  --path ./my-agent --tier enterprise --noninteractive
```

---

## LAYER HISTORY (Forever §3)

| Layer ID | Created | Supersedes | Description |
|----------|---------|------------|-------------|
| model-tiering-v1 | 2026-07-14 | none | Initial token-optimized tiering with flash/final pattern |

**To amend:** Create `model-tiering-v2.md` with `Supersedes: model-tiering-v1`.
Rollback = delete v2 file.