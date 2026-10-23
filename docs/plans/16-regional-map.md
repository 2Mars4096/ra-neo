# 16: Regional map and shared battlefield authoring

**Status:** completed
**Goal:** Place Harbor and three distinct, physically consistent battlefields in one navigable region, with a visual editor that compiles the same authoritative geometry used by play.

## Tasks

- [x] 1. Review the existing geography, generator, asset contracts and physics.
- [x] 2. Create `codex/regional-map` from the current renamed game on `main`.
- [x] 3. Generalize scenario resolution and Harbor rendering without changing legacy scenario indices.
- [x] 4. Add a regional atlas with battlefield selection and safe return to the current battle.
- [x] 5. Author a rail valley, mountain pass and sea-dominant inlet with connected, purposeful infrastructure.
- [x] 6. Add visual blueprint editing, undo/redo, placement inspection, validation and deterministic compilation.
- [x] 7. Verify routes, domain restrictions, collisions, supply/mission behavior, UI and native appearance.
- [x] 8. Record evidence and limitations, update user documentation and deliver the separate branch.

## Decisions

- The user's 2026-10-23 request explicitly authorizes regional expansion. Earlier suggestions to defer expansion do not override it.
- Keep Harbor as the existing central battlefield. The regional layer loads one tactical battlefield at a time; it does not simulate all battlefields together or imply campaign persistence.
- Use the existing Sevastopol-inspired broad geography: a long harbor, its inland rail/river corridor, southeastern limestone valleys and a separate narrow southern inlet. Distances and detailed streets are authored/compressed for play, not a modern geographic survey.
- Reuse existing city families, their ground-body geometry, asset footprint contracts, water classification, mobility costs, cover and garrison systems.
- Ground remains planar. Mountains form solid, sight-blocking ridge masses and traversable passes under existing rules; they do not introduce fictitious high-ground combat bonuses or walkable slopes.
- Rail routes and parked rolling stock use the existing asset system. Moving trains and strategic rail logistics are outside this increment.
- Keep legacy `resources/scenarios.json` unchanged; new compiled maps are separate files resolved by a small shared catalog.
- The previous project had a deterministic generator and asset gallery, but no general visual map editor. The new editor edits blueprints and compiles shared collision rather than creating a competing placement system.

## Notes

See the [regional-map guide](../regional-map.md) and [validation entry](../validation.md) for commands, sources and measured results. Regional physics: 1,841 checks; regional UI: 77; HUD: 1,413; presentation cache: 20; all zero failures. Seven additional affected runtime suites passed. Python authoring/editor suites pass 20 tests, and the real-browser editor review passed nine workflows without browser errors. Both compilers reproduce their checked-in output. Native Godot composition, atlas and editor screenshots are in `docs/images/`.

Mission completion tests establish legal capture, reserve timing and the authored hold gate using controlled state; they are not full AI or human battle playthroughs. Software-rendered screenshots establish visual evidence, not frame-rate acceptance. Existing performance and human-playtest acceptance remain separate from this completed implementation increment.
