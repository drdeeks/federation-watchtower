# Index Storage Format & Command Semantics

Where the knowledge base lives on disk, what each file holds, and how the
commands mutate it. All paths are relative to the workspace root detected at
startup.

## On-disk layout

```
docs/
└── knowledge-base/
    ├── config.json      # optional — customizes indexing behavior
    └── index.json       # the searchable index (documents, tokens, metadata)
references/
└── links.json           # curated documentation links (url, title, category)
```

- `index.json` — built by `index` / `rebuild`, amended by `index-file` and
  `update`. Holds one entry per indexed document with its extracted text,
  source path/URL, and category.
- `links.json` — managed only by `add-link` / `remove-link`. The `index`
  command reads it to know which external docs to pull in alongside local
  files.
- `config.json` — optional. Create it under `docs/knowledge-base/` to
  customize which paths and extensions get indexed.

## What gets scanned

- Runtime tree: `*.json`, `*.yaml`, `*.yml` config files.
- Agent workspaces: `*.md`, `*.txt`, `*.json`, `*.yaml` up to 2 levels deep
  per agent directory.
- Curated links from `references/links.json`.

## Command semantics

| Command | Reads | Writes | Notes |
|---|---|---|---|
| `index` | links.json, workspace files | index.json | Full pass; default command |
| `index-file <file>` | one file | index.json | Adds/refreshes a single entry |
| `update` | index.json, changed files | index.json | Incremental — skips unchanged docs |
| `rebuild` | links.json, workspace files | index.json | Discards the old index first |
| `search <query>` | index.json | — | Full-text match, prints hits |
| `list` | index.json | — | Enumerates indexed documents |
| `add-link` / `remove-link` | links.json | links.json | Does NOT reindex — run `update` after |
| `status` | all of the above | — | Shows counts, paths, last-run info |

## Incremental vs rebuild

`update` trusts the existing `index.json` and only touches changed files —
fast, safe for scheduled runs (`--schedule daily`). `rebuild` is the recovery
path when the index is corrupt or the config's scan rules changed: it drops
`index.json` and starts clean. Prefer `update` in automation; reserve
`rebuild` for manual invocation.

## Safety

The indexer only ever writes inside `docs/knowledge-base/` and
`references/links.json`. It never modifies the documents it indexes. See
[safety-practices.md](safety-practices.md) for the enforcement details and
[critical-file-protection.md](critical-file-protection.md) for the protected
path list.
