# Riverside Town: read-only cross-review of map art (Claude)

Date: 2026-10-14. Reviewer did not edit code, run native Godot or run tests for this review.

## Inputs actually inspected

| Input | What was read |
|---|---|
| `artifacts/art-directions/A-dense-town.png`, `B-canal-works.png`, `C-village-edge.png` and `prompts.md` | All three approved concept references. Per `prompts.md`, they are concept targets, not runtime parity or performance commitments. |
| `artifacts/town-inspection-overview.png`, `-street.png`, `-yard.png` (native, 14:18:20) | Viewed at full size, together with `town-gameplay.png` from the same run. |
| `resources/scenarios.json` (index 5) | Parcels and architecture, roads, districts, woods, footpaths, resource fields |
| `resources/environment_catalog.json`, `docs/environment-library.md`, `scripts/environment_variants.gd` | Category and variant library: implemented, library-ready and planned items |
| `scripts/visuals.gd` (showcase parcel loop), `scripts/environment_detail.gd` (land-use mask, frontage aprons), `scripts/roadside_props.gd` (scenario 5 rows) | Code that places and dresses districts |
| `docs/plans/10-riverside-battlefield.md`, `artifacts/town-design-review.json` | Stated layout intent and its own frontage measurements |

Derived figures below come from `resources/scenarios.json` (computed read-only).
- Built parcel area is 1,358 m² out of 13,824 m² of land (x < shore 128), which is **9.8 %**.
- **Old town:** 11 parcels, 19.6 % of its district bounds built.
- **Freight quarter:** 7 parcels, 21.3 %.
- **Farm approach:** 1 parcel, 5.0 %.
- **Southwest depot:** 0 parcels. That is intended, because it holds the base build space.
- Twenty parcels reuse 11 building families. Warehouse appears 3×; every other family appears 1–2×.

## What already works (keep)

- **Road hierarchy and district roles are authored, not scattered.** The named road graph, four districts with stated roles, the western footpath route, a central short-but-exposed route and an eastern freight route all match the plan. None of the parcels sits on a road (`road_blocker_hits: []`).
- **Facades face their roads.** Every `facing` in the architecture list points to an adjacent road, and the street capture confirms it: cafe awnings, terrace shopfronts and the chapel with its cemetery all turn toward the street.
- **Building art quality per parcel is close to direction A.** Terracotta roofs, stucco/brick mixes, shutters, awnings, solar panels and damaged corner states read well at street zoom (`town-inspection-street.png`).
- **Damage is localized and believable inside parcels.** The shelled house, corner collapse, roofless barn and gutted shed all read clearly.
- **The library is honest.** The catalogue separates `implemented`, `library_ready` and `planned`. Fenders and sandbags are not falsely claimed as placed.

## Blockers (contradict "purposeful layout, not arbitrary expansion" or a core approved reference)

1. **Buildings float in lots instead of forming street frontage.**
   - **Evidence:** in `town-design-review.json`, `frontages[].road_distance_along_facing` is 4.0–6.5 m for 18 of 20 parcels and 1.0–1.5 m for only two. The design review's own native note says: "street-facing parcels remain separated from road edges by grass".
   - **What the images show:** in the overview and street captures, each building sits alone, centred in a rectangular lot. The lot has a thin dark border band that reads like a plinth or empty court.
   - **References:** A and B both build to the pavement line, as continuous rows with party walls and courtyards behind walls. C puts walls and gates on the road edge.
   - **Effect:** an inflated grid with one object per cell. This is the main source of the "arbitrary expansion" impression.

2. **Super-blocks are mostly empty ground with no stated use.**
   - **Coverage:** 9.8 % built overall, about 20 % in the town districts. The references read as roughly half or more built, counting yards and walls; that comparison is visual judgement, not a measurement.
   - **Example:** in the street capture, the blocks bounded by the market (x48), cross (x72) and through-road (y54) are large grass quads with a single 8×8–9×9 parcel each.
   - **What's missing:** these spaces have no gardens, yards, parking, walls, hedges or fields, so the space has no purpose a player can read. The land-use mask (town soil, freight gravel, field) only tints the ground and, at these zooms, still reads as uniform dark olive.

3. **The riverfront has no built edge, even though the layout depends on it.**
   - **Roads:** `quay_n`, `quay_mid`, `quay_s` and three "quayside service road" edges run along x=123.
   - **What the yard capture shows:** a pale sand strip, then a flat cyan band with a ruler-straight edge. There is no quay wall, embankment, ladders, railings or moored craft. Only three 0.6 m bollards exist, and they are not legible at inspection zoom.
   - **Library status:** `quay_edge`, `small_boat` and `barge` are `planned`; `quay_fender` is `library_ready` but unplaced.
   - **Why it's a blocker:** direction B, the canal-works identity, is essentially absent, and the "quayside" road has no visible reason to exist.

## Remaining visual gaps (important, not blocking on their own)

4. **Visible copy-paste in the freight quarter.** The yard capture shows two identical warehouse parcels side by side, both facing east, with the same roof, the same white office block and the same dock stock. Mirror one, change its roof state or tone, or swap the design. The integrated `try_warehouse_rack` rack is too low to break the repetition at this zoom.
5. **Road hierarchy is defined in the data but not visible.** Through roads (6 m), connectors (5–5.5 m) and quayside service roads (4.5 m) all render as the same asphalt with the same dashes. There are no kerbs, pavements or gutters, and only one zebra crossing is visible, at the cross junction. In A, B and C, kerbed pavements and crossings frame the movement lanes.
6. **Plots have no boundary layer.** The town districts have no low walls, railings, gates or hedges dividing plots. These are the single strongest repeated element in A and C. `hedgerow`, `guardrail` and `footpath` remain `planned`.
7. **The farm approach is sparse.** It is shelter-belt rows of small, widely spaced lollipop trees on a flat field tint. C reads as an orchard, vineyard, gardens, greenhouse, ditch with culvert, and fences. `raised_beds`, `polytunnel`, `hay_bales` and `field_gate` exist only inside the single farmstead parcel. `orchard`, `hedgerow`, `irrigation_ditch` and `tractor` are planned. The rows are justified as managed planting but don't read as belts that provide screening.
8. **Freight yards are thin.** A few pallets, drums, a reel, a cabinet and a van sit on open gravel. B's loading identity (containers, stock stacks, forklift, gantry, rail and pipe runs) is not legible yet. `shipping_container` and `forklift` are listed as implemented in parcel code, but neither was visible in these captures.
9. **Damage stops at the parcel boundary.** No rubble spills into the street at the corner collapse, and there are no static craters or scorch marks (catalogue: `planned`). A uses street-side rubble to tell a damage story at junctions.
10. **Palette and light.** Overall value is dark and desaturated (olive grass, grey asphalt, deep navy water and fog) compared with A's and C's warm overcast daylight. This is a lighting/grade observation from the captures; no measurement was taken.
11. **Unexplained overlays.** Thin teal polyline overlays appear on the ground in the overview (left, near the farm approach) and in the gameplay capture. I did not identify their source. If they are build-zone or sector guides, they are fine. If they are leftover debug output, remove them. This is an assumption to verify, not a finding.

## Suggested direction (design only; owners decide)

- **Pull frontage to the road:** set the facing edge to about 0.5–1.5 m from the kerb, or fill the setback with a purpose: paved forecourts with cafe tables and planters, front-garden walls with gates, or loading aprons. Prefer **terrace rows** with shared side walls on the high street and market streets over single centred houses.
- **Subdivide each super-block:** street-facing parcels, then rear yards or gardens enclosed by walls or hedges, then a service lane or courtyard. Use only implemented items until planned ones land.
- **Build the river edge as one authored element:** a continuous masonry quay wall along x≈126–128 between `quay_n` and `quay_s`, with bays for the library fenders and one moored workboat or barge. Keep the navigable water and the shore definition (`is_water = x ≥ shore_x`) unchanged.
- **Differentiate the road hierarchy visually:** kerbs and pavements on town roads, gravel shoulders on freight and quayside roads, and crossings at both market and cross junctions.
- **Break the warehouse twin:** mirror it or vary its state, and add one container stack per freight yard.

## Limits of this review

- **Native frames cover only four views:** paused, before battle, at camera sizes 44, 70 and 100, with fog disabled in the three inspection views. Units, effects and weather states were not reviewed here.
- **"Reference parity" is a design judgement.** The references are concept art and are not required to match one-to-one.
- **Quantities are from authored data,** not rendered pixel coverage.
- **Unverified by me:** navigation and route connectivity (reported fixed elsewhere), the attack-position fix, classic mission results and performance.
