// MockDashScopeProvider — simulates Qwen responses for demo/testing.
// Replace with DashScopeProvider when real API key is available.

export class MockDashScopeProvider {
  #defaultModel;
  #callCount = 0;
  #handlers = new Map();

  constructor(config = {}) {
    this.#defaultModel = config.defaultModel || 'qwen-plus-latest';
    // Register custom handlers
    if (config.handlers) {
      for (const [key, handler] of Object.entries(config.handlers)) {
        this.#handlers.set(key, handler);
      }
    }
  }

  async complete(prompt, opts = {}) {
    this.#callCount++;
    const model = opts.model || this.#defaultModel;
    await new Promise(r => setTimeout(r, 50 + Math.random() * 100));
    const content = this.#generateResponse(prompt, opts);
    return {
      content,
      model,
      usage: { prompt_tokens: Math.floor(prompt.length / 4), completion_tokens: Math.floor(content.length / 4), total_tokens: Math.floor((prompt.length + content.length) / 4) },
      finishReason: 'stop',
      toolCalls: null,
      raw: { id: `mock-${this.#callCount}`, object: 'chat.completion' },
    };
  }

  async *stream(prompt, opts = {}) {
    const response = await this.complete(prompt, opts);
    for (const word of response.content.split(' ')) {
      yield { content: word + ' ', model: opts.model || this.#defaultModel, done: false };
    }
    yield { content: '', model: opts.model || this.#defaultModel, done: true };
  }

  #generateResponse(prompt, opts) {
    const lower = prompt.toLowerCase();
    // Check registered handlers first
    for (const [key, handler] of this.#handlers) {
      if (lower.includes(key.toLowerCase())) {
        return typeof handler === 'function' ? handler(prompt, opts) : JSON.stringify(handler);
      }
    }
    // Default response
    return JSON.stringify({ processed: true, message: 'Mock response', timestamp: new Date().toISOString() });
  }

  registerHandler(key, handler) { this.#handlers.set(key, handler); }
  getModel() { return this.#defaultModel; }
  getBaseUrl() { return 'mock://dashscope'; }
  getCallCount() { return this.#callCount; }
  hasKey() { return true; }
}
