# DashScope Provider Pattern — Reusable Across Qwen Projects

## DashScopeProvider (Real API)

OpenAI-compatible wrapper for DashScope API. Supports chat completions, streaming, retries.

```js
export class DashScopeProvider {
  #apiKey; #baseUrl; #defaultModel; #timeout; #maxRetries;

  constructor(config = {}) {
    this.#apiKey = config.apiKey || process.env.DASHSCOPE_API_KEY || process.env.ALIBABA_CODING_PLAN_API_KEY;
    this.#baseUrl = (config.baseUrl || process.env.DASHSCOPE_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1').replace(/\/$/, '');
    this.#defaultModel = config.defaultModel || 'qwen-plus-latest';
    this.#timeout = config.timeout || 60000;
    this.#maxRetries = config.maxRetries || 3;
    if (!this.#apiKey) throw new Error('DashScope API key required');
  }

  async complete(prompt, opts = {}) {
    const model = opts.model || this.#defaultModel;
    const messages = this.#buildMessages(prompt, opts.system);
    const body = {
      model, messages,
      temperature: opts.temperature ?? 0.7,
      max_tokens: opts.maxTokens ?? 4096,
      ...(opts.responseFormat && { response_format: opts.responseFormat }),
    };
    // Retry with exponential backoff
    for (let attempt = 1; attempt <= this.#maxRetries; attempt++) {
      try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), this.#timeout);
        const response = await fetch(`${this.#baseUrl}/chat/completions`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${this.#apiKey}` },
          body: JSON.stringify(body), signal: controller.signal,
        });
        clearTimeout(timer);
        if (!response.ok) throw new Error(`DashScope ${response.status}: ${await response.text()}`);
        const data = await response.json();
        return { content: data.choices?.[0]?.message?.content || '', model: data.model || model, usage: data.usage || {} };
      } catch (error) {
        if (attempt < this.#maxRetries) await new Promise(r => setTimeout(r, Math.min(1000 * 2 ** (attempt - 1), 10000)));
        else throw error;
      }
    }
  }

  static modelForRole(role) {
    const MAP = {
      'orchestrator': 'qwen3-235b-a22b-thinking-2507',
      'coder': 'qwen3-coder-plus',
      'reasoning': 'qwen3-max-preview',
      'balanced': 'qwen-plus-latest',
      'fast': 'qwen3-coder-flash-2025-07-28',
      'adversarial': 'qwen3-235b-a22b',
      'structured': 'qwen3-30b-a3b-instruct',
      'vision': 'qwen-vl-max-latest',
    };
    return MAP[role] || 'qwen-plus-latest';
  }
}
```

## Constructor Pattern for Mock/Real Swap

Always accept both config and instance to enable testability:

```js
class MyAgent {
  #provider;
  constructor({ providerConfig = {}, provider = null }) {
    this.#provider = provider || new DashScopeProvider(providerConfig);
  }
}
```

Usage:
```js
// Real
const agent = new MyAgent({ providerConfig: { defaultModel: 'qwen3-max-preview' } });
// Mock (for demo/testing)
const agent = new MyAgent({ provider: new MockProvider() });
```

## DashScope API Endpoints

- Standard: `https://dashscope.aliyuncs.com/compatible-mode/v1`
- Coding plan: `https://coding-intl.dashscope.aliyuncs.com/v1`
- Format: OpenAI-compatible chat completions
- Auth: `Authorization: Bearer <api_key>`

## Environment Variables

- `DASHSCOPE_API_KEY` or `ALIBABA_CODING_PLAN_API_KEY` — API key
- `DASHSCOPE_BASE_URL` — endpoint override

## Common Pitfalls

- API keys expire — always have a mock fallback for demos
- Different endpoints for different plans (standard vs coding)
- `response_format: { type: 'json_object' }` enables JSON mode
- Timeout should be 60s+ for complex reasoning models
- Retry with exponential backoff (1s, 2s, 4s, max 10s)
