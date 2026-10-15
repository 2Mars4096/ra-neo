# Current experience review: realism, inconvenience, procedural giveaways (Claude, independent)

Date: 2026-10-14. Read-only. No source edits, tests, native/browser runs or timed work.

## What was inspected

| Source | What was read |
|---|---|
| `artifacts/town-gameplay.png`, `town-inspection-overview/street/yard.png` (native, 14:32, with pulled frontages and quay) | Viewed at full size |
| `artifacts/effects-review-*.png` + sheet (native, 14:26) | Captured after the CPU-card effects change (`scripts/effects.gd` 14:18, shaders 14:19). `a0`, `a4`, `a5-rolling` and `b1` viewed at full size. |
| `output/browser/5b135c70b48a1635/browser_1791959099562.png` (AoE II DE), `…155304.png` (RA2), `…187564.png` (Songs of Syx) | Reference screenshots |
| `docs/art-authenticity-review.md` | Authenticity study |
| Source | `scripts/hud.gd` (minimap, overlays), `scripts/battle.gd` (camera, `ui_action`, input), `scripts/visuals.gd`, `scripts/environment_detail.gd`, `scripts/effects.gd` |

**What improved since 14:18:** the yard now has a visible quay coping with bollards along the river, and several main-street parcels are closer to the road. The earlier white-sheet effect fault is gone in the 14:26 frames. Effects now distinguish rifle tracers from the tank blast and show ATGM trails, water spouts and wreck smoke.

**Paving correction acknowledged.** Paving and gutters do exist: `environment_detail.gd` builds town kerbside slabs and gutters (`_road_edges`, lines 33–56) and parcel aprons (lines 10–18). The issues below are about their visibility and uniformity, not their absence.

## Issues (prioritized, max 5)

### 1. The classic match starts with the camera at map centre, away from the player's base (UX)

**Evidence (source):**
- `battle.gd:55` sets `camera_focus=(world_size.x/2, 0, world_size.y/2+5)`, which is (72, 59) on Riverside, with `camera_size` 72 (`battle.gd:18`).
- `ui_action("begin")` (`battle.gd:440–443`) only unpauses and posts "Build a refinery near your HQ…". It does not move the camera.
- No other start path sets `camera_focus`. Its only other writers are the clamp (144–145), edge pan (235–236), minimap click (457) and the F key on a selection (549). `classic.gd` never touches the camera.

**Evidence (derived):**
- The Riverside HQ is at (10, 97) (`town-design-review.json` `bases[0].hq`).
- With the fixed camera offset (26, 64, 46), the HQ lies about 72 m along screen-right from the start focus. At size 72 the battlefield half-width is about 49 m, so the HQ starts off-screen and the opening view is fogged town.
- This is calculated from the camera math, not observed in a capture: `town-gameplay.png` is a harness view that moves the camera to (25, 84).

**Why it matters:** in RA2 and AoE the opening frame is your own base. Here the first instruction points at an HQ the player cannot see.

**Correction:** in classic mode, centre `camera_focus` on team 0's HQ once, at scene setup after the HQ is spawned (or in `ui_action("begin")`), and leave the zoom unchanged.

**Acceptance:** after DEPLOY on Riverside Town and Frontier Skirmish (the two `mode: classic` scenarios), `camera.unproject_position(hq)` lies inside the central 60 % of `hud.battlefield_rect()`. Non-classic scenarios keep their current opening view.

### 2. Leftover hard-coded "spawn zone" cyan lines on every non-coast map

**Evidence (source):** `visuals.gd:300–303`, commented "Spawn zone markings", unconditionally adds three thin `BLUE` (`#72dac8`) strips: x = 8 and x = 22 over z 51–65, plus z = 65 over x 8–22. Unlike the posts on line 304, they are not gated by style or scenario.

**Evidence (images):**
- **Riverside:** the bright cyan U-shape is visible in the farm approach in `town-inspection-overview.png` (left), and in fog in `town-gameplay.png` (top centre). Riverside's player base is at the far southwest (HQ 10, 97), so the "zone" marks nothing.
- **Canal Watch:** the same lines appear in the effects frames (cyan diagonal top-left of `a0`–`a6`, and the rectangle in `a5-gameplay-zoom`).

**Why it matters:** it's the brightest saturated line on the terrain, reads as a deploy or build zone that doesn't exist, and is an obvious authoring leftover.

**Correction:** gate the block to scenarios that actually use that deployment area (e.g. a `spawn_zone` rect in `scenarios.json`, absent for Riverside), or delete it. Do not repaint it.

**Acceptance:** Riverside builds zero `BLUE` boxes at y=0.025. The overview capture shows no cyan lines outside selection rings. Scenarios that keep a zone draw it at their authored rect.

### 3. The map reads as a floating slab: wide off-map void at normal zoom

**Evidence (source):** `update_camera` (`battle.gd:143–148`) clamps the focus to a fixed 12/8 m margin regardless of zoom. Visible ground at size 72 spans roughly ±49 m across and ±47 m along the view, and `MAX_ZOOM` is 84. Near any edge, much of the view is navy void plus the slab's side face.

**Evidence (images; pixel shares are visual estimates):**
- `effects-review-a0…a6` at size 36: roughly the lower-left third is void and slab edge.
- `town-gameplay.png` at size 70: roughly 40 % is void.

**Why it matters:** AoE and RA2 never show the edge of the world as a cliff. The tabletop plinth is the clearest "this is a generated diorama" tell, and it wastes screen space.

**Correction:**
1. After positioning the camera, project the four battlefield-rect corners to the ground (`world_pos`).
2. If any corner falls outside `[-m, size+m]` (m ≈ 2 m), shift `camera_focus` inward by the largest overflow along each world axis. Repeat at most twice.
3. When the map is smaller than the view at a given zoom, centre it on that axis.

**Acceptance:** at zoom 24, 44, 72 and 84, at all four map corners on Canal Watch and Riverside, no corner projects more than 2 m outside the map (where map ≥ view). The `a0` capture shows no slab edge.

### 4. Vehicle explosions throw a perfectly even "daisy" of identical dust puffs

**Evidence (source):** `effects.gd:786–788`. `vehicle_explosion` emits exactly 10 dust puffs at angles `n*TAU/10 ± 0.2`, all with the same start radius (0.8·scale), speed range 4–7, size range 2.4–3.0 and colour.

**Evidence (images):** `effects-review-a4-fireball.png` and `a5-rolling.png` show an evenly spaced ring of near-identical beige puffs around the burning vehicle.

**Why it matters:** real ground blast dust is a lopsided skirt shaped by terrain and debris. The regular ring is a strong procedural signature next to otherwise authored-looking effects.

**Correction:** keep the bounded budget.
- Emit 6–8 puffs at fully random angles with a minimum separation of about 25°.
- Vary the start radius (0.3–1.2), speed (2–7), size (1.6–3.2) and lifetime per puff.
- Add one or two low, wide skirt puffs merged to one side.
- Leave the flash, fireball, soot and scorch untouched.

**Acceptance:**
- **Test:** across 50 seeded explosions, the sorted angular gaps between dust puffs have a coefficient of variation ≥ 0.35, and puff sizes span at least 1.8×. Existing pool, timing and budget tests stay green.
- **Native:** the `a5` frame shows no regular ring.

### 5. Every parcel gets the same front-and-back paving with a centred grate; kerbs are too faint

**Evidence (source):**
- **Parcel aprons:** `environment_detail.gd:10–18` lays two 0.47 m rows of paving along both the north and south edges of every block, with a 7-bar drain grate centred on each, whatever the parcel's facing.
- **Kerbside slabs:** `_road_edges` (lines 41–56) adds 0.78 m town slabs (`#706c60`) at y = 0.007, which is flush, plus a 0.10 m gutter. There is no upstand, so the slabs cast no shade.

**Evidence (images):**
- `town-inspection-street.png` shows the same paving band and centred dark grate under the north and south sides of each building. The west-facing chapel also gets them on its sides rather than at its entrance.
- The kerbside slabs read only as a faint line along the asphalt. AoE II and Syx streets read through strong edge contrast.

**Why it matters:** identical, facing-agnostic bands repeat across 20 parcels and reveal the generator. Weak kerbs leave lots as grass rectangles instead of plots fronting a street.

**Correction:**
1. Lay the apron only on the parcel's `facing` side, plus the service side for warehouses and gutted sheds, spanning the facade width.
2. Put the grate at a downpipe corner rather than the centre.
3. For town roads, add a 0.10 m kerb upstand on the road side of the existing slab, with a lighter top (about +15 % value over the slab) and a darker face. This is visual only; it adds no collision or cover.

**Acceptance:**
- **Source test:** each parcel's apron rectangles lie on its facing or service sides only.
- **Native at zoom 44:** a continuous light kerb line with a shadowed face is visible along both sides of the high street and through roads.
- **Movement:** the vehicle and infantry movement tests are unchanged.

## Assumptions and limits

- **Issue 1** is derived from source and camera geometry; no real post-DEPLOY native frame of Riverside was inspected.
- **Pixel shares (issue 3)** are visual estimates from the captures, not measurements.
- **All captures are paused staging.** Inspection views disable 3D fog. The minimap and HUD in the three inspection frames are stale, because `town_review.gd` stops `battle` processing after the first capture, so the minimap there is not evidence of game behaviour.
- **The reference screenshots** are judged visually as styles of authentic construction logic, not as parity targets.
- **Not reviewed:** performance, navigation, AI, audio and live input timing.
