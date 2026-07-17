# Testing Framework with Safety Wrapper

## Overview
This document describes the comprehensive testing framework added in PHASE-10, including unit tests, integration tests, E2E tests, and Playwright browser tests, all wrapped with the safety-test-framework.sh.

---

## Architecture

### Core Safety Wrapper
`scripts/safety-test-framework.sh` provides:
- **Confirmation prompts** for all destructive test actions
- **Dry-run mode** (`--dry-run` / `-n`) — preview without executing
- **Error recovery** — retry, modify, skip, rollback, diagnostics
- **Automatic rollback** on failure
- **Dry-run toggle** in menus (`d` key)
- **Verbose mode** toggle (`v` key)
- **Safe command execution** with timeout/retry/circuit breaker
- **Atomic file operations** with rollback
- **Lock management** with timeout

### Test Runner
`scripts/test-runner.sh` orchestrates all test types:

```bash
# Run all tests
hemlock test-all

# Individual test suites
hemlock test-unit        # 25+ function validations
hemlock test-integration # 6 scenarios
hemlock test-e2e         # 8 workflows
hemlock test-playwright  # 18 browser scenarios
```

---

## Test Types

### Unit Tests (`test-unit`)
Validates individual functions across all modules:
- `validate_agent_id`, `validate_crew_id`, `validate_project_id`
- `validate_telegram_token`, `validate_json`, `validate_ruleset_json`
- `validate_auth_profiles_schema`, `check_command`, `check_commands`
- `validate_file_path`, `validate_model_backend`, `validate_gguf_file`
- `check_dependencies_health`, `check_ram_availability`, `check_ram_threshold`
- `atomic_write`, `atomic_copy`, `acquire_lock`, `release_lock`
- `allocate_port_atomic`, `push_rollback`, `execute_rollback`, `clear_rollback`
- `verify_ollama_service`, `test_model_load`

### Integration Tests (`test-integration`)
Tests cross-module workflows:
- `test_agent_lifecycle` — create → attach → detach → delete
- `test_crew_orchestration` — crew CRUD + agent attachment
- `test_model_management` — list/download/load/unload/handoff
- `test_builder_codes` — builder code update propagation
- `test_auto_start` — auto-start sequence + gateway health
- `test_self_heal` — self-healing recovery

### E2E Tests (`test-e2e`)
Full workflow tests:
- `test_full_agent_lifecycle` — create → configure → use → checkpoint → handoff → offload
- `test_crew_collaboration` — multi-agent crew workflow
- `test_model_handoff_workflow` — load → handoff under load
- `test_auto_start_recovery` — auto-start → health check
- `test_self_heal_recovery` — heartbeat stale → restart → recover
- `test_builder_code_propagation` — update → verify across agents
- `test_killswitch_recovery` — killswitch → auto-start
- `test_offload_recovery` — offload → reattach

### Playwright Tests (`test-playwright`)
Browser-based E2E tests (18 scenarios):
- Gateway health endpoint
- Gateway status page
- Agent Management API (list, create, attach/detach)
- Model Management API (list, load/unload, handoff)
- Crew Management API (create, attach/detach)
- Self-heal API
- Killswitch API + recovery

---

## Safety Features in Testing

### Confirmation Prompts
Every destructive test action prompts:
```
⚠  DESTRUCTIVE ACTION
This will delete test agent data. Continue? [y/N]:
```

### Dry-Run Mode
```bash
# Preview what would run
DRY_RUN=true hemlock test-all
# Or toggle in menu with 'd' key
```

### Error Recovery Options
When a test fails:
1. **Retry** — Same parameters
2. **Retry modified** — Adjust parameters
3. **Skip** — Continue to next test
4. **Rollback** — Execute rollback stack
5. **Diagnostics** — Show full diagnostics
6. **Exit** — Abort test suite

### Automatic Rollback
On any failure, rollback stack executes in reverse order:
```bash
push_rollback "rm -f /tmp/test-agent-data"
# ... test runs ...
# On failure:
execute_rollback  # Runs: rm -f /tmp/test-agent-data
```

---

## Test Reports

### Output Format
Structured JSON report at `test-results/reports/test-<timestamp>.json`:
```json
{
  "timestamp": "2026-06-14T21:40:46.085108+00:00",
  "summary": {
    "passed": 45,
    "failed": 0,
    "skipped": 3,
    "total": 48
  },
  "status": "PASSED"
}
```

### Console Output
Real-time colored output with progress:
```
  ✓ Unit test passed: validate_agent_id
  ✓ Unit test passed: validate_crew_id
  ⚠ Unit test skipped: validate_third_party_tool
  ✗ Integration test failed: test_crew_orchestration
    Error: timeout waiting for agent attach
    [Retry] [Retry modified] [Skip] [Rollback] [Diagnostics] [Exit]
```

---

## Playwright Integration

### Setup
```bash
# Install Playwright (first time)
npm install -g playwright
npx playwright install --with-deps chromium firefox webkit
```

### Test Location
`hemlock-minimal/tests/playwright/hemlock.spec.ts`

### Test Categories
```typescript
test.describe('Hemlock Gateway', () => {
  test('Health endpoint responds', ...)
  test('Gateway status shows healthy', ...)
})

test.describe('Agent Management API', () => {
  test('List agents', ...)
  test('Create agent', ...)
  test('Agent attach/detach', ...)
})

test.describe('Model Management', () => {
  test('List models', ...)
  test('Load/unload model', ...)
})

test.describe('Crew Management', () => {
  test('Create crew', ...)
  test('Attach/detach crew', ...)
})

test.describe('Self-Heal', () => {
  test('Self-heal triggers recovery', ...)
})

test.describe('Killswitch', () => {
  test('Self-heal triggers recovery', ...)
})
```

### Running Playwright Tests
```bash
# Non-interactive
npx playwright test --reporter=json --output-dir=test-results/playwright

# Interactive with UI
npx playwright test --ui

# Debug mode
npx playwright test --debug
```

---

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Test Suite
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup
        run: |
          cd hemlock-minimal
          docker build -f Dockerfile.runtime -t hemlock-runtime .
          docker compose up -d
          sleep 10
      - name: Run Tests
        run: |
          docker exec hemlock-runtime /scripts/test-runner.sh all
      - name: Run Playwright
        run: |
          cd tests/playwright
          npx playwright test --reporter=json
      - name: Upload Reports
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results/
```

---

## Test Data Management

### Test Fixtures
- Created in `/tmp/hemlock-test-<timestamp>/`
- Auto-cleaned on test completion
- Dry-run mode prevents any file creation

### Test Agent Naming
```bash
# Pattern: test-<type>-<timestamp>-<random>
test-ui-1707123456-abc123
test-crew-1707123456-def456
```

---

## Extending Tests

### Adding Unit Tests
```bash
# In test-runner.sh, add to test_functions array
test_functions+=(
    "my_new_function"
    "validate_something_else"
)
```

### Adding Integration Tests
```bash
# In test-runner.sh, add to test_scenarios array
test_scenarios+=(
    "test_my_new_workflow"
)
```

### Adding Playwright Tests
```typescript
// In tests/playwright/hemlock.spec.ts
test('My new feature', async ({ request }) => {
  const response = await request.post('http://localhost:18789/v1/my-endpoint', {
    data: { key: 'value' }
  });
  expect(response.ok()).toBeTruthy();
});
```

---

## Related Files
- `scripts/safety-test-framework.sh` — Core safety wrapper
- `scripts/test-runner.sh` — Test orchestration
- `references/bash-enhanced-troubleshooting.md` — Bash script debugging
- `references/phase-7-8-9-integration.md` — PHASE-7/8/9 integration
- `references/setup-wizard-hemlock.md` — Hemlock deployment

---

## Version History
| Date | Version | Changes |
|------|---------|---------|
| 2026-06-14 | 1.0 | Initial testing framework documentation |