// DashScopeProvider — shared Qwen Cloud API client for all hackathon projects.
// OpenAI-compatible endpoint: https://dashscope.aliyuncs.com/compatible-mode/v1
//
// Usage:
//   import { DashScopeProvider } from '../shared/DashScopeProvider.js';
//   const provider = new DashScopeProvider(); // reads DASHSCOPE_API_KEY from env
//   const result = await provider.complete('Hello', { model: 'qwen-plus-latest' });

export class DashScopeProvider {
  #apiKey;
  #baseUrl;
  #defaultModel;
  #timeout;
  #maxRetries;
  #callLog = [];

  /**
   * @param {Object} config
   * @param {string} config.apiKey - DashScope API key (or env DASHSCOPE_API_KEY)
   * @param {string} config.baseUrl - API endpoint (default: dashscope.aliyuncs.com)
   * @param {string} config.defaultModel - Default model (default: qwen-plus-latest)
   * @param {number} config.timeout - Request timeout in ms (default: 60000)
   * @param {number} config.maxRetries - Max retry attempts (default: 3)
   */
  constructor(config = {}) {
    this.#apiKey = config.apiKey || process.env.DASHSCOPE_API_KEY;
    this.#baseUrl = (config.baseUrl || process.env.DASHSCOPE_BASE_URL || 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1').replace(/\/$/, '');
    this.#defaultModel = config.defaultModel || 'qwen-plus-latest';
    this.#timeout = config.timeout || 60000;
    this.#maxRetries = config.maxRetries || 3;

    if (!this.#apiKey) {
      throw new Error(
        'DashScope API key required. Set DASHSCOPE_API_KEY environment variable.\n' +
        'Get your key at: https://dashscope.console.aliyun.com/'
      );
    }
  }

  /**
   * Send a chat completion request to Qwen via DashScope.
   * @param {string|Array} prompt - Text prompt or messages array
   * @param {Object} opts - { model, temperature, maxTokens, topP, tools, responseFormat, system }
   * @returns {Promise<{content: string, model: string, usage: Object, finishReason: string}>}
   */
  async complete(prompt, opts = {}) {
    const model = opts.model || this.#defaultModel;
    const messages = this.#buildMessages(prompt, opts.system);
    const body = {
      model,
      messages,
      temperature: opts.temperature ?? 0.7,
      max_tokens: opts.maxTokens ?? 4096,
      top_p: opts.topP ?? 0.9,
      ...(opts.tools && { tools: opts.tools }),
      ...(opts.responseFormat && { response_format: opts.responseFormat }),
    };

    const startTime = Date.now();
    let lastError;

    for (let attempt = 1; attempt <= this.#maxRetries; attempt++) {
      try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), this.#timeout);

        const response = await fetch(`${this.#baseUrl}/chat/completions`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.#apiKey}`,
          },
          body: JSON.stringify(body),
          signal: controller.signal,
        });

        clearTimeout(timer);

        if (!response.ok) {
          const errorBody = await response.text();
          const error = new Error(`DashScope ${response.status}: ${errorBody}`);
          error.statusCode = response.status;
          error.errorBody = errorBody;
          throw error;
        }

        const data = await response.json();
        const choice = data.choices?.[0];
        if (!choice) throw new Error('No choices returned from DashScope');

        const elapsed = Date.now() - startTime;
        const result = {
          content: choice.message?.content || '',
          model: data.model || model,
          usage: data.usage || { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
          finishReason: choice.finish_reason || 'stop',
          toolCalls: choice.message?.tool_calls || null,
          elapsed,
          raw: data,
        };

        this.#callLog.push({ model, elapsed, tokens: result.usage.total_tokens, timestamp: new Date() });
        return result;
      } catch (error) {
        lastError = error;
        if (attempt < this.#maxRetries) {
          const delay = Math.min(1000 * 2 ** (attempt - 1), 10000);
          await new Promise(r => setTimeout(r, delay));
        }
      }
    }

    throw lastError;
  }

  /**
   * Stream a chat completion. Yields content chunks.
   * @param {string|Array} prompt
   * @param {Object} opts
   * @yields {{content: string, model: string, done: boolean}}
   */
  async *stream(prompt, opts = {}) {
    const model = opts.model || this.#defaultModel;
    const messages = this.#buildMessages(prompt, opts.system);
    const body = {
      model,
      messages,
      temperature: opts.temperature ?? 0.7,
      max_tokens: opts.maxTokens ?? 4096,
      stream: true,
    };

    const response = await fetch(`${this.#baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.#apiKey}`,
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      throw new Error(`DashScope stream ${response.status}: ${await response.text()}`);
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const data = line.slice(6).trim();
          if (data === '[DONE]') return;
          try {
            const parsed = JSON.parse(data);
            const delta = parsed.choices?.[0]?.delta;
            if (delta?.content) {
              yield { content: delta.content, model, done: false };
            }
          } catch { /* skip malformed chunks */ }
        }
      }
    }
  }

  /**
   * Build messages array from prompt + system message.
   */
  #buildMessages(prompt, system) {
    const messages = [];
    if (system) messages.push({ role: 'system', content: system });
    if (typeof prompt === 'string') {
      messages.push({ role: 'user', content: prompt });
    } else if (Array.isArray(prompt)) {
      messages.push(...prompt);
    } else {
      throw new Error('Prompt must be string or messages array');
    }
    return messages;
  }

  /**
   * Get the best model for a specific role.
   */
  static modelForRole(role) {
    const MODEL_MAP = {
      // Reasoning
      'orchestrator':    'qwen-plus-latest',
      'reasoning':       'qwen3-max-preview',
      'adversarial':     'qwen-plus-latest',
      // Coding
      'coder':           'qwen3-coder-plus',
      'fast-coder':      'qwen3-coder-flash-2025-07-28',
      // General
      'balanced':        'qwen-plus-latest',
      'fast':            'qwen3-coder-flash-2025-07-28',
      'structured':      'qwen3-30b-a3b-instruct',
      // Vision
      'vision':          'qwen-vl-max-latest',
      'vision-balanced': 'qwen-vl-plus-latest',
      // Translation
      'translation':     'qwen-mt-turbo',
    };
    return MODEL_MAP[role] || 'qwen-plus-latest';
  }

  /** Get call history */
  getCallLog() { return [...this.#callLog]; }
  getModel() { return this.#defaultModel; }
  getBaseUrl() { return this.#baseUrl; }
  hasKey() { return !!this.#apiKey; }
}
