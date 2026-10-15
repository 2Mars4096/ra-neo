# 1-1: Visual effects and model clearance

**Parent:** [1: Tactical RTS vertical slice](1-tactical-rts-vertical-slice.md)
**Status:** completed
**Goal:** Deliver readable combat effects and prevent model intersections in representative ground, air, and naval scenarios.

## Tasks

- [x] Derive conservative unit footprints from actual model geometry; test mesh vertices against collision radii.
- [x] Use footprint-aware A* paths, safe formation destinations and spawn placement, and swept dynamic clearance checks.
- [x] Share tree positions between visuals and navigation; include piers, warehouses, containers, ridge geometry, and objective poles.
- [x] Separate UAV and helicopter altitude bands above all scenery.
- [x] Add pooled muzzle flashes, impacts, sparks, explosions, delayed smoke, vehicle dust, wakes, animated water, and synthetic combat audio.
- [x] Correct overlay draw order so range indicators do not cross command panels.
- [x] Recheck rendered effects, full mission, input, geometry stress tests, and 1080p frame timing after final changes.
- [x] Record final evidence and remaining limits in tracking docs.

## Review criteria

- Technical artist: visible footprints fit conservative collision envelopes; elevated units clear scenery and each other vertically.
- Navigation engineer: no overlapping live bodies or solid-geometry intersections during dense deployment, turns, mixed orders, and naval passage; orders must still finish.
- VFX artist: flash, debris, and smoke have distinct timing; effects communicate hits without obscuring unit identity or health.
- UI/UX designer: orders, unit state, and command controls remain legible through combat and tactical pause.
- Performance engineer: fixed particle budget, material-batched models, instanced vegetation, cached visibility/minimap; validate actual render dimensions rather than requested window size.

## Evidence

94,801 checks passed, including triangle preservation for all seven equipment types. The normal-command mission won in 65 simulated seconds. Final rendered frame p95 was 14.130 ms at 1080p on Apple M4 Pro. See [validation](../validation.md) for artifacts, methods, input-latency shortfall, and remaining limits. These are representative checks, not proof of every possible collision-free arrangement.
