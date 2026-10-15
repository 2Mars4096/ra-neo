# 6-2: Scene structure and smooth presentation

**Parent:** [6-painted-miniatures](6-painted-miniatures.md)
**Status:** in-progress
**Goal:** Address weak silhouettes and frame pacing rather than another surface-only pass.

## Recursive checkpoint
- Trigger: user sees little improvement and lag.
- Concrete meaning: repeated intact boxes, uniform vegetation, thousands of draw submissions, 30 Hz displayed movement.
- Artifact/test: native scene with broken rooflines/exposed construction; isolated benchmark; interpolation and clearance regressions.
- Kill result: only color changes visible or added scenery increases draw overhead.
- Scale trigger: inspect one working scene before extending the asset family.
- Decision changed: rebuild building components, batch static geometry, interpolate presentation. No new gameplay systems.
- Dispatch-ready task: implement locally in ruined_building.gd, visuals.gd, battle.gd and unit_animation.gd; no delegation.
- Keep: scene structure and frame pacing. Defer: production asset replacement and whole-town expansion.

## Tasks
- [x] Research modular environment construction and Godot instancing.
- [x] Add collapsed building variant with wall thickness, openings, remnant floor, roof and debris.
- [x] Batch showcase building meshes; revise vegetation clusters.
- [x] Interpolate display positions while retaining fixed-rate authoritative simulation.
- [x] Native review, focused regressions and isolated performance measurement (target still unmet).

## Research applied
[Lee Perry, Modular Level and Component Design](https://docs.unrealengine.com/4.26/udk/Three/rsrc/Three/ModularLevelDesign/ModularLevelDesign.pdf): choose component scale for gameplay, vary components, test assembled environments early. Applied as structural variants instead of further staining intact boxes.
[Godot 4.5 MultiMesh optimization](https://docs.godotengine.org/en/4.5/tutorials/performance/using_multimesh.html): instance repeated geometry to reduce submissions. Vegetation stays instanced; unique building components are merged by material.

## Limits
Ruins remain impassable collapsed footprints; exposed upper floors are visual construction detail, not occupiable interiors. No claim of reference-quality finished art. Presentation interpolation introduces at most one simulation-tick display delay and does not alter combat or movement authority.

## Current evidence / user steering
Input (21 checks) and render-interpolation fixture pass. Native initial structure view inspected. Isolated benchmark: frame median 6.85 ms, p95 22.332 ms, simulation p95 11.05 ms. More validation remains. User requested generated reference figures and selection before expansion; A/B/C are stored under artifacts/art-directions. All three options accepted. Continued implementation and full HUD revamp are tracked in [6-3](6-3-integrated-revamp.md).

Integrated pre-revamp checks: 22 suites pass, including render interpolation. Latest isolated frame p95 24.835 ms, simulation p95 10.731 ms; 100 members, 3,994 draw calls. No performance acceptance claimed.
