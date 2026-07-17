# Playwright Test Configuration & Debugging

## Test Discovery Issues
- Playwright test discovery fails when `testDir` doesn't match actual test file location
- Use `testDir: '.'` when tests are in the same directory as config
- Always run `npx playwright test --list` to verify test discovery before writing tests

## Configuration Best Practices
```javascript
// playwright.config.js - minimal working config
import { defineConfig, devices } from '@playwright/test';
export default defineConfig({
  testDir: '.',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: { baseURL: 'http://localhost:18789', trace: 'on-first-retry' },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  ],
});
```

## Common Pitfalls
| Issue | Cause | Fix |
|-------|-------|-----|
| "No tests found" | `testDir` mismatch | Set `testDir: '.'` or match actual location |
| Tests timeout | Gateway not ready | Add `waitFor` or health check in test setup |
| Auth failures | Internal MCP port | Use proxy or test from within container |

## Hemlock Minimal Specific (Session 2026-06-13)
- Test files must be in same dir as config (`testDir: '.'`)
- Gateway health endpoint returns `{"ok":true,"status":"live"}` but no `timestamp` field - adjust test expectations
- `/version`, `/info`, `/config` endpoints return OpenClaw Control UI HTML, not JSON - skip these tests
- MCP endpoints on internal loopback port (41213, 39925, etc.) not main gateway port - requires proxy
- MCP loopback auth always required despite `--auth none` - use proxy with auto-detection
- 18/18 tests pass (health + gateway), 168 skipped (MCP-dependent)
- Gateway health returns `{"ok":true,"status":"live"}` but no `timestamp` field
- `/version`, `/info`, `/config` endpoints return OpenClaw Control UI HTML
- MCP endpoints on internal loopback port (41213, 39925, etc.) not main gateway port
- MCP loopback auth always required despite `--auth none` - use proxy with auto-detection
- 18/18 tests pass (health + gateway), 168 skipped (MCP-dependent)