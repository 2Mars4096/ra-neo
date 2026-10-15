# 3: Unit motion, weapon effects, and terrain variety

**Status:** completed
**Goal:** Make unit locomotion and firing preparation readable, improve weapon effects, and add traversable terrain with tactical consequences.

## Tasks
- [x] Articulate infantry legs/upper bodies and armored turrets while retaining geometry batching.
- [x] Drive poses from displacement and simulation time; show bracing, suppression, aiming, and recoil.
- [x] Add target acquisition time before firing and differentiated projectile trails/impact dust.
- [x] Add ruins cover and soft-ground movement penalties with matching surface visuals and HUD labels.
- [x] Check animated geometry envelopes, timing, effects lifecycle, mission completion, and rendered performance.
- [x] Document verified scope and remaining animation limitations.

- [x] Add selectable coast, agricultural-frontier, and industrial-fringe scenario configurations and complete scripted missions in each.
- [x] Replace shared infantry combat with individual health, movement, target/cooldown/aim state, casualties, and survivor-only recovery.
- [x] Verify member separation, formation arrival, localized damage, and staggered fire.

## Decisions
- Use authored procedural articulation for this iteration. No claim of skeletal motion capture or physically accurate locomotion.
- Terrain additions represent low rubble and churned soil, not impassable buildings or height simulation.
- Projectile travel is presentation; authoritative damage remains resolved at the shot event.

## Evidence
Nine suites pass, including 125,600 group clearance checks, 508 animation checks, 1,007 individual-actor checks, and victories in all three variants. Motion samples and the scenario selector were inspected in native renders. See [validation](../validation.md) for the latest active-simulation benchmark and limitations.
