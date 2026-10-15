# 9-1: Regroup recovery and scenario dimensions

**Parent:** [9-town-scale-performance](9-town-scale-performance.md)
**Status:** in-progress
**Goal:** Recover separated soldiers under one player order and make navigation/UI bounds follow scenario dimensions.

## Tasks
- [x] Inspect and preserve interrupted regroup recovery and tests; validate before extending.
- [x] Review primary-source navigation approaches and select a bounded incremental implementation.
- [x] Validate continuous wall recovery, command authority, actor clearance and spatial-index equivalence.
- [x] Fix recovery prematurely interrupting a valid shelter trip; use surviving-member capacity for withdrawal health thresholds.
- [x] Implement `terrain.world_size: Vector2`, `terrain.fog_grid_size: Vector2i`, and scenario `size: [width,height]`, default 96×72.
- [x] Replace navigation/cost/temporary-body bounds, fog, camera pan, minimap and base/rally bounds; test synthetic 144×108 shore_x128.
- [ ] Validate manager-authored sixth scenario and adapted render assets after they arrive.
- [ ] Resolve remaining group congestion; sections 2/3 reunite but remain blocked near each other at 60 seconds.

## Decisions
- [Godot 4.5 navigation overview](https://docs.godotengine.org/en/4.5/tutorials/navigation/navigation_introduction_2d.html) distinguishes weighted point/grid routing from mesh navigation and notes the latter's large-world benefits. A mesh rewrite would require footprint, collision and movement integration validation. Keep the established grid for this increment.
- [Godot 4.5 AStarGrid2D](https://docs.godotengine.org/en/4.5/classes/class_astargrid2d.html) provides regions, diagonal rules, solids and weights. Retain cached per-domain/radius/mobility grids, conservative group envelopes, cost-preserving string pulling, distinct reachable destination slots, and existing throttled group obstacle replanning. This is the chosen group strategy, not a new flow field or navmesh system.
- Interrupted actor recovery caches route waypoints and retries at most once per second for a stable destination; changed commands/goals invalidate that cache. Accepted return routes stay within the 10-unit leash and total length 28. Search still uses the map grid: these are route/retry bounds, not a measured global CPU budget.
- Squad anchors pause for recovery and resume after live-member spread falls below 2.8. Valid shelter seeking already pauses the anchor, so the 7.5-unit return trigger must not cancel it; an eight-second stalled-progress trigger remains.
- No teleportation, columns, smaller clearance, actor-index replacement, native benchmark or performance improvement claim.

## Evidence and limitations
- Ten headless suites exit zero: gap navigation (2,746), road routing (9), actor spatial (1,447), cover behavior, tactical flexibility (42), legacy scenario playthroughs, classic, camera zoom (11), scenario dimensions (34), regroup recovery (14,435).
- [Check manifest](../../artifacts/navigation-checks.json), [regroup evidence](../../artifacts/regroup-recovery.json), [dimension evidence](../../artifacts/scenario-dimensions.json); per-suite logs alongside the manifest. Commands: `./tools/play.sh --headless --log-file /tmp/ra-TEST.log --script tests/TEST.gd`.
- Single original attack-move [1,2,3,4] plus the existing scout move: section 1 completes its order; all live members of sections 1–3 reunite; village is player-owned at 60 seconds. Sections 2/3 still have orders and approximately 20 seconds blocked. No all-unit arrival claim.
- The sixth scenario is absent at validation (five configs). The 144×108 fixture exercises the same terrain constructor through an optional config override; this is infrastructure evidence, not authored-map gameplay/render acceptance. Minimap click conversion and fog dimensions are checked headlessly, not visually.
- Prior withdrawal rally conflicts, silent long withdrawal stalls, SUPPORT clearing cover, hidden enemy shelter reservations and nearest-only exposure remain unresolved in this focused increment. Only the capacity threshold issue was corrected and tested.
- The initial default-log launch crashed in the sandbox; explicit /tmp log paths work. Godot prints a macOS certificate-store diagnostic even on passing runs. No native benchmarks were launched.

## Integrated follow-up

- Three original infantry attack-move orders finish by90s; no reissue, teleport or clearance reduction.
- Actual Riverside economy tests include production, multiple moving harvester deliveries, cross-town travel, fog/minimap/zoom.
- Distinct withdrawal slots, support-cover retention and bounded stalled withdrawal release address cross-review findings.
- Attack positions now require reachable paths; unchanged classic mission wins371.9s. See [follow-up evidence](../../artifacts/classic-regression-followup.md).
- This remains cached weighted AStar with bounded local recovery, not proof of arbitrary crowd deadlock freedom or thousands-unit performance.
