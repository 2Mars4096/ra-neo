# 15: For Every Dawn game name

**Status:** completed
**Goal:** Adopt the player-selected game name consistently across the project and its launch/review surfaces.

## Tasks
- [x] 1. Audit project settings, live HUD, launcher, export/report names, and documentation.
- [x] 2. Apply For Every Dawn; measure the HUD title so the scenario label follows it without using the old fixed offset.
- [x] 3. Rename the executable source launcher and update gallery/equipment-review labels and release-tool filenames.
- [x] 4. Update tracking documents, check branding consistency and script syntax, and record runtime/export verification limits.

## Decisions
- The commercial game title is **For Every Dawn**; the repository remains `2Mars4096/ra-neo`.
- Preserve real scenario names, repository links, and historical filesystem paths.
- The HUD takes its title from `application/config/name` in `project.godot`.
- Godot's default user-data directory follows the new title. Previous settings and reports remain in their old directory; this change does not migrate or delete them.

## Notes
- Passed: Python AST parsing for changed tools, shell syntax for launchers, executable launcher permission, reference audit, and `git diff --check`.
- Godot is not installed in the editing environment; native startup and rendered title spacing remain unverified here.
- Existing release packaging references missing inputs; see [known limitations](../bugs.md). No standalone builds were produced for this rename.
