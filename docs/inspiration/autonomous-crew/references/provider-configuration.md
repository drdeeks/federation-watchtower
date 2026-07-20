# Provider Configuration Pattern

## Overview
The crew-manager.py and autonomous-crew system uses a configurable provider system instead of hardcoded models.

## Configuration File: config/providers.json

```json
{
  "version": "1.0.0",
  "providers": {
    "dashscope": {
      "name": "DashScope (Alibaba Cloud)",
      "api_base": "https://dashscope.aliyuncs.com/api/v1",
      "env_key": "DASHSCOPE_API_KEY",
      "models": {
        "text": ["qwen3-max-preview", "qwen3-235b-a22b-thinking-2507", "qwen-plus-latest", "qwen-turbo-latest"],
        "vision": ["qwen-vl-max-latest", "qwen-vl-plus-latest"],
        "embedding": ["text-embedding-v3"]
      }
    },
    "openai": {
      "name": "OpenAI",
      "api_base": "https://api.openai.com/v1",
      "env_key": "OPENAI_API_KEY",
      "models": {
        "text": ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"],
        "vision": ["gpt-4o", "gpt-4o-mini"],
        "embedding": ["text-embedding-3-large", "text-embedding-3-small"]
      }
    },
    "anthropic": {
      "name": "Anthropic",
      "api_base": "https://api.anthropic.com/v1",
      "env_key": "ANTHROPIC_API_KEY",
      "models": {
        "text": ["claude-opus-4", "claude-sonnet-4", "claude-3-5-sonnet"],
        "vision": ["claude-opus-4", "claude-sonnet-4"],
        "embedding": []
      }
    },
    "local": {
      "name": "Local Models (llama.cpp / Ollama)",
      "api_base": "http://localhost:11434/v1",
      "env_key": "",
      "models": {
        "text": ["qwen3-14b", "qwen3-4b", "llama3.1-8b", "llama3.1-70b"],
        "vision": ["llava-llama3"],
        "embedding": ["nomic-embed-text"]
      }
    }
  },
  "auto_detect": {
    "enabled": true,
    "priority": ["dashscope", "openai", "anthropic", "local"]
  },
  "quotas": {
    "per_model_limit": 1000000,
    "rotation_strategy": "round_robin"
  }
}
```

## Auto-Detection Logic

1. Check environment variables in priority order
2. First provider with valid API key becomes active
3. If no API keys found, falls back to local models
4. Models are selected by role:
   - `lead` / `reasoning` → most capable text model
   - `creative` → best creative model
   - `general` → balanced model
   - `edge` → smallest model (qwen3-4b, qwen3-14b)
   - `embedding` → embedding model

## Usage in crew-manager.py

```python
def _select_model_for_role(self, role: str) -> str:
    """Select best available model for a given role."""
    # Maps role to model category
    role_map = {
        "lead": "reasoning",
        "reasoning": "reasoning", 
        "creative": "creative",
        "general": "text",
        "edge": "edge",
        "embedding": "embedding"
    }
    category = role_map.get(role, "text")
    
    # Get first available model from detected provider
    for provider_name in self.detected_providers:
        provider = self.providers_config["providers"][provider_name]
        models = provider["models"].get(category, [])
        if models:
            return models[0]
    
    return "model-not-configured"
```

## Quota Tracking

Each blueprint.json includes a token_budget section:
```json
{
  "token_budget": {
    "per_model_limit": 1000000,
    "rotation_strategy": "round_robin",
    "models_pool": ["model1", "model2", ...],
    "current_usage": {"model1": 0, "model2": 0}
  }
}
```

## Pitfalls to Avoid

❌ NEVER hardcode model names in scripts
❌ NEVER assume specific provider is available
❌ NEVER use `$HOME/` paths - use ${WORKSPACE_ROOT}
✅ Always read from providers.json
✅ Always auto-detect from environment
✅ Always provide fallback "model-not-configured"