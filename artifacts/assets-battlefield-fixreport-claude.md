# Battlefield asset fixes (Claude) — 2026-10-14

**Scope:** findings 2 and 3, plus the battlefield part of finding 4, from `artifacts/assets-cross-review-claude.md`.

**Files I own and changed:** `scripts/assets_battlefield.gd`, `resources/assets_battlefield.json` (descriptions only), `tests/test_assets_battlefield.gd` and this report. I changed no other file. The gallery, the other palette files, the rural assets, the docs and `asset-library-checks.json` belong to the lead or to other workers.

## Changes

**Tent cloth (finding 2)**
- Each bay and slope is now a 3×3 grid that shares vertices with its neighbours. The rafters, ridge and eaves stay taut, and only the centre of each bay sags (0.10 on the ridge tent, 0.08 on the lean-to).
- Adjacent bays share the exact rafter z values, from one `zs` array. This replaces the old 0.08 inset, which opened about 0.16 m diamond slits.
- The ridge tent's side walls hang from the same eave vertices.
- **Lean-to:** `_roof_y` is now a single plane, falling from 2.5 at x=-2 to 1.9 at x=+2. It has one rafter per frame, and the back wall follows that plane. The old 2.52 "ridge" at x=-0.35 is gone.

**Scorch and crater (finding 3)**
- `_irregular()` adds three low harmonics (2, 3 and 5 lobes). It replaces the `sin(i*2.7)` / `sin(i*2.3)` terms, which alternated high and low on every vertex and produced the star and cog shapes.
- **Scorch:** four opaque value bands, ASH → CHAR → SOOT → SINGE. There is no alpha and no texture. The thorn triangles are removed.
- **Streak:** a teardrop. Its +Z half is pulled along a slightly skewed drag direction from `STREAK_ORIGIN`, so the tail narrows rather than fanning out.
- **Crater:** the lip height varies at low frequency, a lighter SPOIL apron sits between the outer edge and the lip, and the rubble facets are irregular rather than every 7th.

**Wreck (bounded improvement)**
- The body is heat-grey (BURNT) rather than near-black ASH.
- The utility hulk's rubber tyres are now rusted bare rims with steel hubs, resting at about the datum. The tracked hulk's track runs and road wheels are rust.
- The side skins are rust, each with a small surviving olive paint scrap offset 12 mm outward.
- The flat olive ground triangle is now a two-part buckled plate folded against the rear. The spare tyre is now a rim.

**Palette (finding 4, battlefield only)**
- There are no `art.models.*` colour reads left (grep count: 0). Colours come from `preload("res://scripts/environment_palette.gd")` plus local neutral constants.
- `_mat()` passes the finish explicitly. Without this, `models.mat()` infers finish by comparing against its team-mutable `canvas`, which made the cached paint depend on build order.
- **Boom:** SAFETY_WHITE bar with nine SAFETY_RED sleeves, 0.196 m so they wrap the 0.18 m bar on all sides.

**Metadata:** I changed descriptions only, on 9 entries. Footprints, heights, collision and placement are unchanged. No geometry needed a bound change.

**Budget:**
- Still one static batch and material per model. The existing "one static batch" and "shared cached batch material" checks pass.
- No textures, lights or extra draw calls.
- Vertex counts, before (from the 15:23 `asset-library-checks.json`) → after:

| Asset | Before | After |
|---|---|---|
| ridge tent | 2278 | 2598 |
| lean_to | 2390 | 1928 |
| scorch (each variant) | 186 | 744 |
| crater (each variant) | 720 | 1008 |
| utility hulk | 1232 | 1626 |
| tracked hulk | 2258 | 2292 |
| boom | 810 | 810 |

## Tests added to `tests/test_assets_battlefield.gd`

I kept the existing raw-mesh nil-index handling in `geometry()` unchanged. The new helpers handle unindexed meshes the same way.

- **Neutral paint:**
  - Every variant's baked vertex colours must match between a fresh `Visuals`, one that built a team-1 tank first, and one with a team-1 rifle built in between two environment builds.
  - There is a precondition check that the team build really mutates `models.marking/canvas/olive`.
- **Boom:** must contain SAFETY_RED and SAFETY_WHITE paint, with red on both the +Z and -Z faces.
- **Roof continuity:**
  - About 4,900 vertical rays per tent: 119 z steps of 0.04 that cross every rafter seam, × 41 x samples. They are tested only against triangles painted CANVAS, so rafter beams cannot mask a gap.
  - Every ray must hit cloth above 1.7.
  - The lean-to's height must fall strictly across x at every z, with more than 0.4 rise at the bay centre. The ridge tent must rise to the ridge and fall after it.
- **Decal outlines:**
  - The outline is taken from baked vertices in 24 angular bins. It must have ≤10 slope reversals, and the max/min radius ratio must exceed 1.08.
  - Scorch: at least 3 paint values, and an outer edge lighter than the ASH core.
  - Streak: its tail must be more than 1.8× its head extent, measured from the core centroid. Tail width beyond 75% of the length must be under 0.5× the head width.
  - Craters: the same outline test on their y=0 rim, normalised by footprint.
- **Wrecks:** no RUBBER paint.
- **Stable bounds:**
  - Raw and baked AABBs must be equal.
  - The declared height must be no more than 0.3 above the built maximum; the worst case is the swing gate at 0.257. This sits alongside the existing XZ, vertical, rotated and grounded checks.

## Checks performed and outcomes

All runs used Godot 4.5.1 headless, without any windowed native process.

| Run | Result |
|---|---|
| Baseline, old builder and old test | `BATTLEFIELD ASSETS: 1216254 checks, 0 failures` |
| New test against the **old** builder | 36 failures. Slits and pitch on both tents; star or cog outlines on both scorches and both craters; streak drag and taper; boom bands; rubber on both wrecks; faction-dependent paint on 9 variants. This shows the regressions catch the reviewed defects. |
| New test, first version of the new builder | 1 failure: streak taper (a radial stretch fanned the tail). Fixed with a teardrop stretch. |
| Final | `BATTLEFIELD ASSETS: 1265274 checks, 0 failures` |
| Lead's `tests/test_asset_palette.gd` (read-only; writes nothing) | `ASSET PALETTE: 100 checks, 0 failures` |
| `resources/assets_battlefield.json` | Parses as valid JSON |

## Deviations, assumptions and unresolved items

- **Log path deviation:** the required `--log-file /private/tmp/battlefix.log` crashed Godot's logger (signal 11 in `RotatedFileLogger`), because the sandbox does not allow writing there. Running outside the sandbox was declined. Every run instead used `--log-file /tmp/claude-501/battlefix.log` (the sandbox `$TMPDIR`); the palette run used `battlefix-palette.log`.
- **No rendered image evidence.** Headless runs do not render, so how the fixes look is unverified. That covers cloth sag shading, the band value steps against map terrain, how strong the rust and paint scrap read, and the boom red at gameplay zoom. The lead's next gallery capture is needed. Reverse-angle and gameplay-zoom views are also still open.
- **Not run:** `tests/test_asset_library.gd`, because it overwrites the lead-owned `artifacts/asset-library-checks.json`. Its vertex totals for the battlefield assets are therefore stale until the lead reruns it. My suite checks stricter bounds than its `≤height+0.05` check.
- **Assumptions:**
  - The test's `baked_paint()` mirrors the paint encoding in `visuals.gd` `bake_model`, with a tolerance of 0.006 for 8-bit colours.
  - Real-world colour cues come from general knowledge, not project sources: red/white booms, rusted burnt-out hulks without tyres, lighter crater spoil.
- `_mat()` still calls `art.models.mat()`. For colours with zero finish, it relies on none of my neutral colours equalling a team `canvas` value. The neutral-paint regressions guard this.
