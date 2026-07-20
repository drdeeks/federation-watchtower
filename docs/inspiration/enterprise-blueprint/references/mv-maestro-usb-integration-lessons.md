# MV Maestro USB Integration — Blueprint Lessons (Session 2026-07-13)

## Context
Blueprint created for merging MV Maestro (68+ commands, Textual TUI, 6 modules) with USB-Hemlock portable compute platform (Ventoy, persistence, SSH/alias managers) into a single unified profile.

## Key Requirements from User
- **Single `mm` command** — auto-detects USB-boot / USB-mounted / native; presents contextual menu
- **Categories 1-9** = MV Maestro native; **Category 10** = USB (visible when USB detected); **Category 11** = Hemlock (only with `-H` flag)
- **USB directory fully consumed** — no separate `usbctl`, `alias_manager.sh`, `ssh_host_manager.sh`, `sysman.sh`, `lib/*` as standalone scripts
- **Persistence bake-in** — exact copy of entire MV Maestro runtime baked into `/persistence/.maestro/` at volume creation/update; enables true portability

## Blueprint Structure That Worked
- **Part VI phases** formatted as `### PHASE-N: Title` (not `### PHASE-N` bare header)
- **Part III SPEC headers** renamed to `### Spec-NNN:` (lowercase) to avoid generator Try 2 matching
- **Module registry** includes MOD-011 `PersistenceBakeIn` for the bake-in requirement
- **Feature flags** renamed to `FEAT_*` pattern (not `FEAT_PROFILE` etc.)

## Checklist Generator Gotchas
The generator has a 3-try priority chain:

| Try | Matches | Output |
|-----|---------|--------|
| 1 | Part VI with `### PHASE-0\n\n**Section Tag:**` | Only 1st phase (bug: separator expects `## ` not `### `) |
| 2 | `### SPEC-NNN:` | One phase per module (blocks Try 3) |
| 3 | `### PHASE-N: Title` (fallback) | All phases, but generic "Implement {title}" tasks |

**Working config:** Part VI uses `### PHASE-N: Title` + Part III uses `### Spec-NNN:` (lowercase). Generator skips Try 1 (no bare PHASE header), skips Try 2 (no SPEC- headers), falls to Try 3 → extracts all 6 phases correctly.

## Bake-In Specification Added to Blueprint
**New SPEC-004B** (Persistence Volume Bake-In):
- Triggers on VolumeCreate, VolumeResize, ProfileApply
- Copies: bash_enhanced.sh, modules/*.sh (6), menu_tui.py, docker_tui.py, lib/*.sh (7), usbctl, hemlock-tui, alias_manager.sh, ssh_host_manager.sh, sysman.sh
- Writes to `/persistence/.maestro/` with exact directory structure
- Patches PROFILE_DIR in menu_tui.py and bash_enhanced.sh
- Validation gate: bash -n all .sh, python3 -m py_compile all .py, mm resolves
- Version stamp: `/persistence/.maestro/.version` (git commit + timestamp)
- USB profile JSON includes `baked_maestro: {enabled: true, path, version, entry_point}`
- Hemlock images NOT baked (too large); falls back to USB drive or /tmp

## Phase Mapping
| Phase | Feature Flag | Core Work |
|-------|--------------|-----------|
| 0 | FEAT_FOUNDATION | Copy modules, patch menu_tui.py, create unified bash_enhanced.sh |
| 1 | FEAT_PROFILE_ENGINE | mm command, USB env detection, HEMLOCK_DIR resolver, per-device config |
| 2 | FEAT_MENU_SYSTEM | Category 10 (USB), Category 11 (Hemlock/-H), quick aliases mm10/mm11 |
| 3 | FEAT_HEMLOCK_INTEGRATION | hemlock-tui/status/deploy/doctor/images/volumes submenu |
| 4 | FEAT_TESTING | validate_menu.sh full run, usbctl validate, persistence cycle, dry-run |
| 5 | FEAT_LAUNCH | Final install, alias activation, docs, all flags enabled |

## Validation Result
- `validate_blueprint.py`: 34/34 passed, 0 FAIL, 0 WARN (Enterprise Grade)
- `generate_checklist.py`: 6 phases found, 11 modules (including MOD-011)

## Files Produced
- `${USB_MOUNT}/projects/hemlock-usb/docs/mv-maestro-usb-integration/blueprint.md` — 66KB, 1149 lines
- `${USB_MOUNT}/projects/hemlock-usb/docs/mv-maestro-usb-integration/checklist.md` — 2.8KB, 78 lines