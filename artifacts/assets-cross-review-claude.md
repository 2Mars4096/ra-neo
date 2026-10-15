# Claude asset cross-review — 2026-10-14

This is a read-only review. The lead implements any fixes. I wrote only this report. I kept the miniature direction and material quality in `docs/art-authenticity-review.md` and am not proposing coarser assets. The gallery is not a map, and library assets do not add collision automatically. I take both as given and do not report them as defects.

## Evidence base

- **Capture freshness:** I waited for the new native capture. The circulation card now prints `1.2 × 1.2 × 0.1`, the formatted dimensions. Every `asset-gallery-*.png` file is 1440×900 and timestamped 15:23:59–15:24:01. `asset-library-checks.json` (15:23:19) shows 100 entries, 658,669 checks and 0 failures. I did not run those checks; they come from the existing artifact. I rechecked the timestamps before writing this report and none had changed.
- **Images inspected:** all 12 gallery pages. Detailed review of rural-1, waterfront-1/2, field_defences-1/2, damage-1 and architecture-1. Readability skim of the other five categories.
- **Source read:** `scripts/asset_library.gd`, `tools/asset_gallery.gd`, `tests/test_asset_library.gd`, `assets_battlefield.gd`, `assets_rural.gd`, `assets_waterfront.gd` (builders and lifebuoy), `environment_variants.gd`, `assets_existing.gd:13`, `unit_models.gd:8–14,319–323`, `visuals.gd:19,331`, the three asset handoffs and `docs/art-authenticity-review.md`.
- **Not performed:** no tests, native, headless or browser runs, no source or image edits, no delegation.
- **Assumptions:** Godot's orthographic camera uses its default `KEEP_HEIGHT` aspect. I read real-world conventions (lifebuoy and boom colours, burnt-out hulks) from general knowledge, not from project sources.

## Five prioritized fixes

### 1. P1: The gallery hides or crops the defining faces of focus assets

**Images:**
- On `field_defences-2`, the only row stretches to roughly 348×696 px. Both sandbag cards are cropped and neither end of the wall is visible.
- "Open supply shelter" (lean_to) is almost identical to the ridge tent, because the camera sees its closed +Z back wall.
- "Open rescue station" reads as a blank olive board on a post, with the buoy hidden behind it.

**Source:**
- `tools/asset_gallery.gd:59–60` sets EXPAND_FILL on the card and the container, so the card's aspect ratio changes on sparse pages.
- `:69` sizes the camera on height only and always places it at `center+Vector3(16,23,25)`.
- The builders face the working side toward -Z:
  - `assets_battlefield.gd:130–136`: curtains at z=-2.4, back wall at +2.4.
  - `assets_waterfront.gd:215,219`: cabinet back at z=0.22, buoy at -0.04.
  - `environment_variants.gd:87`: fender working face -Z.
  - `assets_rural.gd:4`: vehicles face -Z.
- Displayed heights are overstated:
  - `asset_library.gd:31` hardcodes 1.8 for sandbags, which reach only 0.72 (3 courses × 0.24, `environment_variants.gd:71–77`), and for the low-cradle pipe rack, whose top is about 0.62.
  - `assets_existing.gd:13` gives 2.5 to the bollard and the quay bay, but the bay renders as a low plank.
  - The test checks only `local.y <= height+0.05` (`test_asset_library.gd:39`), so it cannot catch an overstated height.

**Relation to Codex #3:** this agrees with Codex's point about height and +Z views, which Codex cites as `assets_existing.gd:15` (actual line 13). It adds the crop and the hidden working faces.

**Acceptance:**
- Every card keeps a fixed aspect, or the camera fits both axes. The sandbag ends are visible with a margin.
- The cards show the -Z working face, or there is a front/back toggle. The lean-to opening and the rescue buoy are readable.
- The displayed height is the measured render maximum within ±0.1. The test also enforces a lower bound.

### 2. P1: Supply-tent roofs have see-through holes along every rafter

**Image:** in `field_defences-1`, both tents show pale lens-shaped slits running from ridge to eave at each frame line.

**Source:** in `assets_battlefield.gd:126–127`, each bay's mid-sag vertices sit at `z+0.08` and `z+0.88`, while the ridge and eave run from `z` to `z+0.96`. Adjacent bays therefore leave an uncovered diamond about 0.16 m wide at mid-slope, covered only by a 0.028 m beam (`:119–120`).

Also, the lean_to roof (`:118–119`) goes from a high eave of 2.5 to a "ridge" of 2.52 at x=-0.35, then falls to 1.9. That makes a near-flat plane plus a slope, which reads as a gable rather than a single-pitch lean-to.

**Acceptance:**
- The cloth is continuous between bays. The sag can stay as long as it does not open gaps.
- No background is visible through the roof from either side.
- The lean_to has one monotonic roof pitch, so it is distinguishable from the ridge tent in silhouette.

### 3. P1: Scorch and crater outlines are regular stars

**Image:** in `damage-1`, both scorches and both craters are crisp multi-point stars or cogs. Small brown "thorn" triangles ring the scorches. "Dragged scorch" reads as a smaller star, not a directional streak. This is the strongest artificial cue in the focus set.

**Source:**
- Scorch (`assets_battlefield.gd:187`): the radius term `0.82+0.13*sin(i*2.7)` steps about 155° per vertex, so it alternates between high and low on every vertex.
- Crater (`:229`): `sin(i*2.3)` steps about 132°, which gives the same effect.
- `:191–193` adds an EARTH triangle at every third vertex, at 1.10× radius.
- The streak variant is just a symmetric ellipse (`:188`).
- The fill is a single flat ASH colour with a hard edge.

**Secondary hulk note:** the hulks keep intact black tyres (`:208`, rubber) and have a flat olive debris triangle lying on the ground (`:223`). Both read as unburnt and paper-like.

**Acceptance:**
- The outline uses low-frequency, non-alternating variation, with no visible periodic points.
- The scorch has a graded edge value with no alpha, which fits the existing panel approach. The streak is asymmetric and tapered from an origin.
- The crater lip reads as irregular spoil, not a cog.
- Checked at gallery and intended gameplay zoom.

### 4. P2: Neutral props borrow the mutable unit palette, and safety items lack safety colours

**Source:**
- These builders take colour from `art.models.olive/canvas/marking`, with this many references each: battlefield 16, rural 11, waterfront 12, environment_variants 1.
- `Art` keeps one shared `models` instance (`visuals.gd:19`). Every unit spawn calls `models.build(model,u.kind,u.team)` (`visuals.gd:331`), which reassigns `olive/edge/canvas/marking` per team (`unit_models.gd:319–323`). Team 1's marking colour is `be7965`.
- An in-map library prop therefore takes the colour of whichever unit was built last. Tents, nets, gates, tractors, hulks and the lifebuoy would show faction tints that depend on build order.
- This is latent for now: the new assets are `gameplay_integrated=false`, and the gallery uses a fresh `Art` per card, so the gallery is not representative of the map.

**Visible now:**
- The boom bar uses `marking` `bdc8b6` (`assets_battlefield.gd:108`) and reads as a pale glowing rod. Real booms are red and white.
- The lifebuoy ring is `canvas` tan (`assets_waterfront.gd:219`) with pale bands, so it reads as a rope wreath. It should be orange or red with white bands.

**Acceptance:**
- Environment builders use their own constant neutral palette, never `art.models.*` team-mutable fields.
- A build after a team-1 unit spawn gives the same vertex colours as a fresh build.
- The boom and lifebuoy use muted but recognizable safety colours that stay distinct from the team colours.

### 5. P2: Irrigation channels read as raised timber or steel troughs

**Image:** in `rural-1`, "Raised-bank irrigation channel" is a rectangular brown box with dark oval spots, and "Lined channel" has near-black walls. Neither reads as a field ditch at card scale.

**Source:**
- `assets_rural.gd:93–95` uses vertical-sided boxes for the banks. The bed and the banks are the same `SOIL` colour.
- The tufts are flattened `_crown` lobes (`:97`).
- The lining uses `art.models.steel` `42494a` (`:95`) where concrete is intended.

The handoff intentionally keeps the bed dry and above the datum (`assets-rural-handoff.md:39,73`). I respect that and am not asking for water.

**Acceptance:**
- Earth banks have sloped (trapezoidal) faces and a darker, damp bed value distinct from the bank tops.
- The lined variant uses a light concrete value with visible joints. It should also avoid the team palette from item 4.
- At card and gameplay zoom, both read as drainage cut into the field, not as containers.

## Observations deliberately not ranked

- Waterfront ladders and fenders stand freestanding in the gallery. `placement_issues` already requires support (`asset_library.gd:73`), so I do not treat this as a defect.
- The camouflage net's regular 0.4 m ribbon grid reads somewhat like a trellis. It is lower priority than the items above.
- Architecture parcels are small in their cards because of the uniform 10.5 height and the `height*1.5` fit. That is covered by item 1's fit fix.
- The rural vehicles and trailers have coherent drawbars, axles and ROPS or cab frames. The orchards, rope coils, boats and barges are readable.
- Codex reviewed circulation, utilities, town_life and industry. That is disjoint from this focus, apart from the shared gallery and height point.

## Unresolved

- I made no reverse-angle or gameplay-zoom capture, so acceptance at gameplay zoom is still open for items 2, 3 and 5.
- The palette leak in item 4 is inferred from source and has not been executed.
- No fixes have been applied or verified.
