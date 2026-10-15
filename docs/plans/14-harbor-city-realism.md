# 14: Harbor city realism

**Status:** in-progress
**Goal:** Replace the evenly cycled harbor parcels with district-specific urban morphology, era-appropriate building families and land-use decor; define engineer tasks and the deferred off-map logistics model.

Design contract: [harbor-city-design.md](../harbor-city-design.md).

## Tasks
- [x] 1. Diagnose artificial layout and write district/building/decor/engineer/logistics rules.
- [x] 2. Shared contracts: `scripts/city_buildings.gd` dispatcher, `resources/assets_city.json` decor ids, gallery registration.
- [x] 3. Urban families (centre, microdistrict, civic) — `scripts/city_buildings_urban.gd`; 13 families, damage 0–2, ≤7.9k triangles.
- [x] 4. Works families (private sector, port, rural, misc) — `scripts/city_buildings_works.gd`; 14 families, damage 0–2, ≤5.8k triangles.
- [x] 5. Decor models, MultiMesh/chunk rendering of decor and buildings (38 decor ids; 400 props → 5 MultiMesh nodes; buildings in 96 u tiles).
- [x] 6. District-based compiler: 473 buildings, 1,920 decor placements, 958 oriented collision rects; reproducible `--check`.
  - [ ] 6-1. Old town: continuous street walls (touching rows, corner buildings, closed courtyards) instead of isolated boxes.
  - [ ] 6-2. Microdistrict: denser 5/9-storey slab groups forming yards (currently 9 panel_5 + 5 panel_9).
- [x] 7. Tier-1 engineer tasks: wire, anti-tank obstacles, trench, vehicle berm, camouflage net, forward supply point (`tests/test_engineer_works.gd`).
  - [x] 7-1. Codex cross-review ([report](../../output/team-briefs/engineer-review-codex.md)); fixes plus hard vehicle barrier for hedgehogs.
  - [ ] 7-2. Clear obstacle / breach / mines / fortify building (tier 2; map-prop clearing needs instanced-prop removal).
- [ ] 8. Integrate, native capture, Codex/Claude realism cross-review, performance check.

## Decisions
- Keep current water polygons, arterials, objectives and insertion points; the user accepted the overall map.
- Building footprints use ≈0.6× real horizontal scale; storey 2.7 u.
- Rotated buildings must not create oversized AABB blockers.
- Off-map economy is documented only; `field_income` stays fixed until the macro layer.

- Non-solid works are terrain zones (speed per mobility profile, cover class, concealment), not body blockers; their units use collision layer `field_zone`. Zone changes update only local navigation weights.
- Linear works rotate 90° with T during placement.

## Round 2 (2026-10-14)
- [x] Enemy prepared defences, armed emplacements (bunker, AT gun), command post, ammo depot.
- [x] Purchase queue with right-click refund.
- [x] Camera edge clamp, neutral fog, civic squares, monument and tree detail, narrower drawn roads.
- [ ] Infantry garrison of city buildings (enter, cover, fire from windows, eject on destruction).
- [ ] Destructible city buildings (HP by size; damaged → ruined model; tile mesh rebuild; rubble collision).
- [ ] Review fixes: old-town gable runs (partly done), residential road widths in generator, yard surfaces, continuous walls, port shed yaw, anchored decor.

## Handoff (2026-10-14 wrap-up)

Passing: harbor layout 45,276 / gameplay 291 / visuals 9.8M, engineer works 108, field ops 420, HUD layout 1,086, asset library 1.0M, assets city 1,654, city urban/works (worker runs). Not yet done:

| Next task | Owner files | Done when |
|---|---|---|
| 6-1 Old-town perimeter blocks | `tools/build_harbor_map.py`, blueprint, harbor tests | rows touch along block edges (gaps ≤1 u), corner buildings, open inner courtyards; layout PNG reads as continuous street walls |
| 6-2 Microdistrict density | same | 25–40 panel_5/panel_9 in parallel/perpendicular groups with yards, playgrounds, parking |
| 8 Native capture + review | `tests/harbor_native_review.gd` (written, never run) | run windowed outside sandbox; Codex + Claude review the 8 district PNGs; fix top issues |
| 8 Performance | benchmark on harbor | frame p95 and draw calls measured with 473 buildings + 1,920 props |
| 7-2 Tier-2 engineers | `field_ops.gd`, `harbor_props.gd` | clear rubble/wreck props, breach walls, mines, fortify building |
| Logistics | design only | implement `income = base × production × transport × (1 − interdiction) + sectors` when macro layer starts |

Worker briefs and launcher: `output/team-briefs/` (`compiler.txt`, `urban.txt`, `works.txt`, `decor.txt`, `engineer_review.txt`, `launch.py`).

## Notes
- Non-Git workspace: workers share files by strict ownership.
- `tests/test_field_geometry.gd` ends by writing `/private/tmp/field-geometry-proof.json`, which the sandbox denies; it then hangs. Environment issue, not a regression.
