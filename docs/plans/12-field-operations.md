# 12: Field operations and smooth play

**Status:** in-progress
**Goal:** Make the current battlefield run on one supply budget with engineer-built tactical support, and diagnose/fix measured sources of lag.

## Tasks
- [ ] Profile the actual scene and separate simulation, presentation and rendering cost.
- [ ] Replace Riverside's on-map factory/refinery/power/harvester loop with off-map purchases and a single supply balance.
- [ ] Add three-person engineers and four functional deployables: sandbag cover, observation, repair point and aid post.
- [ ] Require paid, reachable, timed construction by a living engineer; respect collisions, interruptions and destruction.
- [ ] Provide clear purchase/build/placement/progress/cancel UI with no current-mode macro-economy controls.
- [ ] Inspect native gameplay and validate construction, support functions, orders and performance.

## Decisions
- Current user direction supersedes the earlier classic-economy focus. Legacy classic code remains for future macro economy and regression fixtures; it is hidden from the normal mode selector.
- All costs use supply. No resource harvesting, power economy or on-map production prerequisites in Riverside field operations.
- Provisional costs/build times: cover60/8s, observation90/10s, repair140/15s, aid110/12s. Engineers120. These are game-balance choices, not real-world construction estimates.
- Structures occupy authored shared footprints, need engineer work and can be destroyed. Repair/aid do not resurrect casualties. Terrain and explicit command authority stay central.
- No performance claim until measurements identify costs. Feature removal alone is not treated as proof of a smooth game.
