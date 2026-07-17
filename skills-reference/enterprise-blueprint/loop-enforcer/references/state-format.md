# Chain State Format

## JSON Structure

```json
{
  "name": "my-chain",
  "project": "/absolute/path/to/project",
  "created_at": "2026-07-04T00:00:00Z",
  "steps": [
    {
      "index": 0,
      "path": "/absolute/path/to/file1.js",
      "state": "complete",
      "validator": null,
      "created_at": "2026-07-04T00:00:00Z",
      "verified_at": "2026-07-04T00:01:00Z",
      "completed_at": "2026-07-04T00:01:30Z",
      "attempts": 1
    },
    {
      "index": 1,
      "path": "/absolute/path/to/file2.js",
      "state": "active",
      "validator": "/path/to/validator.py",
      "created_at": "2026-07-04T00:00:00Z",
      "verified_at": null,
      "completed_at": null,
      "attempts": 0
    }
  ]
}
```

## State Values

| Value | Meaning | Next Allowed |
|---|---|---|
| `locked` | Cannot be touched | → `active` (when prior completes) |
| `active` | Ready to write | → `pending_verify` (via verify) |
| `pending_verify` | Verification running | → `verified` or `active` (retry) |
| `verified` | Passed validation | → `complete` (via complete) |
| `complete` | Done | Terminal state |

## Log Format

```
[2026-07-04T00:00:00Z] Chain created with 5 steps
[2026-07-04T00:01:00Z] VERIFIED: /path/to/file1.js (attempt 1)
[2026-07-04T00:01:00Z] ACTIVATED: /path/to/file2.js
[2026-07-04T00:01:30Z] COMPLETED: /path/to/file1.js
```
