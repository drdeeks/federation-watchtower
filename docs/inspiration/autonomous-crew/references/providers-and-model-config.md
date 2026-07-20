# Provider Configuration & Model Selection

## Overview

All model selection is **configurable** via `config/providers.json` — no hardcoded models anywhere in the codebase.

## Provider Configuration Structure

```json
{
  "providers": [
    {
      "name": "dashscope",
      "type": "openai_compatible",
      "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
      "models": {
        "qwen3-max-preview": {
          "role": "creative",
          "quota_daily": 1000,
          "max_tokens": 32768,
          "context_window": 131072
        },
        "qwen3-235b-a22b-thinking-2507": {
          "role": "reasoning",
          "quota_daily": 500,
          "max_tokens": 32768,
          "context_window": 131072
        },
        "qwen-vl-plus-latest": {
          "role": "vision",
          "quota_daily": 200,
          "max_tokens": 4096,
          "context_window": 32768
        },
        "text-embedding-v3": {
          "role": "embedding",
          "quota_daily": 20000,
          "dimensions": 1024
        }
      }
    },
    {
      "name": "openai",
      "type": "openai",
      "base_url": "https://api.openai.com/v1",
      "models": {
        "gpt-4o": {"role": "creative", "quota_daily": 1000},
        "gpt-4o-mini": {"role": "fast", "quota_daily": 5000},
        "text-embedding-3-large": {"role": "embedding", "quota_daily": 20000, "dimensions": 3072}
      }
    },
    {
      "name": "anthropic",
      "type": "anthropic",
      "base_url": "https://api.anthropic.com/v1",
      "models": {
        "claude-sonnet-4-20250514": {"role": "reasoning", "quota_daily": 500},
        "claude-3-5-haiku-20241022": {"role": "fast", "quota_daily": 2000}
      }
    },
    {
      "name": "local",
      "type": "llama_cpp",
      "base_url": "http://localhost:8080/v1",
      "models": {
        "qwen2.5-72b-instruct": {"role": "creative", "quota_daily": -1},
        "qwen2.5-32b-instruct": {"role": "reasoning", "quota_daily": -1},
        "nomic-embed-text": {"role": "embedding", "quota_daily": -1, "dimensions": 768}
      }
    }
  ],
  "role_mappings": {
    "creative": "qwen3-max-preview",
    "reasoning": "qwen3-235b-a22b-thinking-2507",
    "fast": "qwen3-235b-a22b-thinking-2507",
    "embedding": "text-embedding-v3",
    "vision": "qwen-vl-plus-latest"
  },
  "defaults": {
    "provider": "dashscope",
    "fallback_provider": "local"
  }
}
```

## Auto-Detection via Environment Variables

| Env Var | Provider | Models Enabled |
|---------|----------|----------------|
| `DASHSCOPE_API_KEY` | dashscope | All DashScope models |
| `OPENAI_API_KEY` | openai | All OpenAI models |
| `ANTHROPIC_API_KEY` | anthropic | All Anthropic models |
| (none) | local | Local llama.cpp/ollama models |

Priority order: DashScope → OpenAI → Anthropic → Local

## Role-Based Model Selection

The `crew-manager.py` uses role mappings from `providers.json` to assign models to agent types:

| Agent Role | Model Role | Example Model |
|------------|------------|---------------|
| Director/Lead | creative | qwen3-max-preview |
| Composer/Writer | creative | qwen3-max-preview |
| Engineer/Reviewer | reasoning | qwen3-235b-a22b-thinking-2507 |
| Embedding engine | embedding | text-embedding-v3 |
| Vision tasks | vision | qwen-vl-plus-latest |
| Fast iteration | fast | qwen3-235b-a22b-thinking-2507 |

## Usage in Scripts

```python
# Load providers config
import json
from pathlib import Path

providers_path = Path("config/providers.json")
with open(providers_path) as f:
    config = json.load(f)

# Get model for role
def get_model_for_role(role: str) -> str:
    provider_name = config["defaults"]["provider"]
    provider = next(p for p in config["providers"] if p["name"] == provider_name)
    model_key = config["role_mappings"].get(role, config["role_mappings"]["creative"])
    return model_key

# Check quota
def check_quota(role: str) -> bool:
    model_key = get_model_for_role(role)
    # Check against model.json usage
    pass
```

## Model Quota Tracking (model.json)

At workspace root, `model.json` tracks per-model usage:

```json
{
  "models": {
    "qwen3-max-preview": {
      "daily_limit": 1000,
      "current_usage": 47,
      "last_reset": "2026-07-09T00:00:00Z",
      "projects": {
        "mnemosyne": 12,
        "aires": 25,
        "autopilot": 10
      }
    }
  },
  "project_budgets": {
    "mnemosyne": {
      "creative": 100,
      "reasoning": 50,
      "embedding": 200
    }
  }
}
```

The `crew-manager.py` reads this to populate `blueprint.json` with token budgets per agent.