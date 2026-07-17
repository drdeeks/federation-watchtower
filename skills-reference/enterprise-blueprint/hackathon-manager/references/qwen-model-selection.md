# Qwen Model Selection Guide — Hackathon Projects

## Model Tiers

### Tier 1: Heavy Reasoning (complex planning, multi-step analysis)
- `qwen3-235b-a22b-thinking-2507` — Best for orchestrators, workflow decomposition
- `qwen3-235b-a22b` — Strong reasoning without thinking mode
- `qwen3-max-preview` — Flagship general reasoning

### Tier 2: Balanced (execution, moderate complexity)
- `qwen-plus-latest` — Reliable all-rounder
- `qwen3-30b-a3b-instruct` — Efficient for structured operations
- `qwen3-32b` — Mid-tier, good for batch processing

### Tier 3: Fast (UI, simple tasks, high throughput)
- `qwen3-coder-flash-2025-07-28` — Fast code generation
- `qwen3-coder-plus` — Strong code generation
- `qwen3-coder-plus-2025-07-22` — Earlier version, still capable

### Vision-Language (image analysis, multimodal)
- `qwen-vl-max-latest` — Best vision understanding
- `qwen-vl-plus-latest` — Balanced vision
- `qwen3-vl-32b-thinking` — Reasoning about images

## Role-to-Model Mapping (5-Project Hackathon)

| Role | Model | Why |
|------|-------|-----|
| Workflow Orchestrator | qwen3-235b-a22b-thinking-2507 | Complex multi-step planning |
| Memory Agent Brain | qwen3-max-preview | Reasoning about memory lifecycle |
| Creative Director | qwen3-max-preview | Narrative and creative decisions |
| Visual Composer | qwen-vl-max-latest | Storyboarding, frame analysis |
| Code Generator | qwen3-coder-plus | API integrations, connectors |
| Fast Coder | qwen3-coder-flash-2025-07-28 | UI components, boilerplate |
| Adversarial Analyst | qwen3-235b-a22b | Finding failure modes |
| Balanced Executor | qwen-plus-latest | Reliable step execution |
| Structured Data | qwen3-30b-a3b-instruct | Graph operations, indexing |
| Policy Engine | qwen-plus-latest | Rule enforcement, compliance |
| Translation | qwen-mt-turbo | Multi-language support |

## Token Budget Considerations

- Track 2 (AI Showrunner) has highest token allowance — use premium models freely
- Track 1 (MemoryAgent) needs efficient models for high-volume memory operations
- Track 4 (Autopilot) balances reasoning cost with execution reliability
- Track 5 (EdgeAgent) should minimize cloud calls — cache aggressively

## API Cost Optimization

1. Use `temperature: 0.1-0.3` for factual/analytical tasks (less retries)
2. Use `max_tokens` conservatively — don't request 4096 for a 100-token answer
3. Batch similar requests when possible
4. Cache embeddings and analysis results
5. Use cheaper models for simple classification, expensive for complex reasoning
