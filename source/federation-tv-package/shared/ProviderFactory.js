// ProviderFactory — auto-selects real or mock provider based on environment.
// Usage: const provider = createProvider({ model: 'qwen3-max-preview' });

import { DashScopeProvider } from './DashScopeProvider.js';
import { MockDashScopeProvider } from './MockDashScopeProvider.js';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

/**
 * Create a DashScope provider, using real API if key is available.
 * @param {Object} opts - { model, handlers } — handlers for mock mode
 * @returns {DashScopeProvider|MockDashScopeProvider}
 */
export function createProvider(opts = {}) {
  const apiKey = process.env.DASHSCOPE_API_KEY;
  const useReal = apiKey && apiKey.startsWith('sk-') && apiKey.length > 20;

  if (useReal) {
    console.log(`  [Provider: REAL] Using DashScope API (${opts.model || 'qwen-plus-latest'})`);
    return new DashScopeProvider({
      apiKey,
      defaultModel: opts.model || 'qwen-plus-latest',
    });
  } else {
    console.log(`  [Provider: MOCK] No valid DASHSCOPE_API_KEY found`);
    return new MockDashScopeProvider({
      defaultModel: opts.model || 'qwen-plus-latest',
      handlers: opts.handlers || {},
    });
  }
}

/**
 * Load .env file from project root or hackathon root.
 */
export function loadEnv() {
  const home = process.env.HOME;
  const candidates = [
    join(home, 'hermes-agent/workspaces/hackathon-2026/.env'),
    join(process.cwd(), '.env'),
  ];

  for (const envPath of candidates) {
    if (existsSync(envPath)) {
      const content = readFileSync(envPath, 'utf8');
      for (const line of content.split('\n')) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          const key = trimmed.slice(0, eqIdx).trim();
          const val = trimmed.slice(eqIdx + 1).trim();
          if (!process.env[key]) process.env[key] = val;
        }
      }
      return envPath;
    }
  }
  return null;
}
