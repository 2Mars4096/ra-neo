# 9: Town-scale performance

**Status:** in-progress
**Goal:** Establish a measured path from the demo battlefield to town-scale battles with thousands of individually tracked troops.

## Tasks
- [x] 1. Introduce spatial combat/sight candidate queries and indexed ID lookup, shared per squad, with deterministic selection and exhaustive-search equivalence checks.
- [x] 2. Exercise range-query scaling at 250, 500, 1,000 and 2,000 records; distinguish this from full simulation/render capacity.
- [ ] 3. Replace fixed world dimensions and hard-coded navigation/minimap bounds with scenario-sized terrain chunks and a town road/sector layout.
- [ ] 4. Profile full simulation at increasing entity counts: perception, local steering, autonomous decisions, path requests and allocation pressure.
- [ ] 5. Add distance-dependent animation/detail, instanced repeated geometry, bounded effects and budgeted AI/path work while retaining individual identity and command responsiveness.
- [ ] 6. Validate a town-scale mixed battle with command latency, frame/simulation p95, memory, congestion and gameplay checks.

## Decisions
- User confirmed the later goal is thousands of troops on a town-sized battlefield.
- 250/500/1,000/2,000 are proposed measurement stages, not demonstrated full-battle capacities.
- First optimization reuses the spatial movement index for targeting; below 64 group records the simpler scan avoids index-query overhead. Selection order stays stable for seeded combat.
- Reduced visual detail must not merge individual health, targets or casualties into a single decorative squad.

## Notes
- Scenario dimensions now drive navigation, fog and UI bounds; legacy maps remain 96 × 72. Synthetic 144 × 108 infrastructure checks pass in [9-1](9-1-navigation-recovery.md). Authored-map integration, chunks and town-scale acceptance remain open.
- Synthetic query benchmarks use positions outside that demo extent to measure the index only. They do not test navigation, animation, rendering or full combat at thousands of troops.
- Broad autonomy and actor steering still contain global scans. Rendering remains thousands of draw calls in the 100-entity stress scene; these need further work.

- Shelter correction follow-up: 100-entity rainy frame p95 22.042 ms, simulation p95 11.072 ms. Individual route search adds work; full actor-scale benchmarking and scheduling remain open. No large-battle capacity claim.

- Current100-member CPU fixture now halves total simulation work with actual-body spatial queries and equivalent steering/eligibility shortcuts.600tick elapsed10.209→5.272s, state-identical; native default-display framep9525.091ms. This improves the current scene, not a demonstrated town-scale capacity.
