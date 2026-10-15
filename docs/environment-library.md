# Environment category and variant library

The catalogue separates `implemented` existing scene/parcel geometry, `library_ready` reusable builders whose placement is pending, and `planned` unimplemented candidates. `variants` retains the earlier category vocabulary; `variant_aliases` maps those names where needed. Existing implementation means geometry exists in the named source, not that every map uses it or that it has an independent model API. `evidence` is source inspection, not visual acceptance. `library_specs` gives each new builder's bounds and semantics.

## Delivered library

All six original models are in `scripts/environment_variants.gd`. They use the existing cached palettes and `art.bake_model` to produce one static mesh batch per assembly with shared material. No new textures, downloaded assets, lights, animation, physics bodies, RNG or update loops.

| Category / kind | Variant | Distinct geometry | Local X/Z rectangle | Height |
|---|---|---|---|---|
| Industry / `pipe_rack` | `low_cradle` | Two open-ended hollow pipes on low cradles | (-1.6, -0.7, 3.2, 1.4) | 0.62 |
| Industry / `pipe_rack` | `tiered` | Four pipes, two crossbar levels, taller end posts | same | 1.48 |
| Field defences / `sandbags` | `straight` | Three compressed bonded courses with half end bags | (-1.3, -0.4, 2.6, 0.8) | 0.72 |
| Field defences / `sandbags` | `corner` | L return, two additional bags per course | (-1.3, -0.4, 2.6, 1.9) | 0.72 |
| Waterfront / `quay_fender` | `timber_piles` | Three piles, two bolted rubbing beams | (-1.3, -0.4, 2.6, 0.8) | 1.72 |
| Waterfront / `quay_fender` | `rubber_panel` | Ribbed rubber slab on two grounded steel feet | same | 1.36 |

Rectangle tuples are `(x, z, width, depth)` in local units. Heights are geometry extents, not tactical cover values. These are additional assemblies, not aliases for the existing pallets/drums/reel/cabinet/bench/bin/bollard models. Pipe ends have actual inner walls and annular rims; fenders have a distinct mounting and contact face. Sandbags remain stylized beveled blocks rather than cloth simulation.

## Exact API

```gdscript
static func local_footprint(kind: String, variant: String) -> Rect2
static func build(art, parent: Node3D, kind: String, variant: String) -> Node3D
```

`art` is an existing BattleVisuals instance. Reuse it across builds to retain material caching. `build` creates and parents a new model at local origin, batches it, and returns it. Repeated calls create separate assemblies intentionally. Unknown kind/variant returns `null` without adding nodes; `local_footprint` returns an empty rectangle for unknown pairs. `VARIANTS` enumerates valid pairs. Returned metadata: `local_footprint`, `placement_policy = "inside_existing_blocked_parcel"`, `grants_cover = false`.

```gdscript
const SiteElements = preload("res://scripts/environment_variants.gd")
var prop = SiteElements.build(art, parcel_root, "pipe_rack", "tiered")
prop.position = Vector3(local_x, ground_height, local_z)
prop.rotation.y = yaw
```

This example assumes placement has already passed manager checks. Local ground is flat y=0; translate the entire assembly to its supporting surface. No terrain sampling or automatic snapping occurs. Loose bag bases contact the ground; successive courses touch; pipes rest on crossbars; both fender assemblies have grounded supports. Wall-mounted fenders use their quay-toe elevation as datum, not the top of a quay deck.

## Placement and gameplay contract

The manager owns placement and integration. Rotate all four rectangle corners using Godot's Y convention (`Vector2.rotated(-yaw)`), translate them into parcel coordinates, and require the complete footprint plus a small margin inside the existing solid parcel. Check other meshes, facade doors, windows, gates, loading areas and visible entrances as well: being inside a blocker does not prove a plausible or non-overlapping placement. Keep scale at one unless bounds are transformed too.

These builders add **no collision, sight blocking, cover bonus, resource income, damage or destruction**. Existing parcel collision and its existing exterior cover behavior remain authoritative. Do not place them on traversable land or water as standalone obstacles. A future accessible sandbag position needs explicit terrain/cover integration and tactical tests; these decorative models do not deliver that feature.

Suggested bounded compositions, subject to actual parcel fit:

- Workshop service edge: choose one pipe-rack variant parallel to a side wall, near stock/loading activity; leave the loading door and apparent forklift path visible. Avoid adding another drums/pallets cluster just to fill gaps.
- Disused depot or ruined supply parcel: choose one straight sandbag stack or corner inside its blocked boundary. The corner can frame stored supplies, but must not suggest a soldier can enter an impassable yard.
- Working quay: choose one fender assembly per small wall bay, rear +Z toward the quay wall and working face -Z toward water. Require an existing blocked shoreline parcel and correct toe elevation. If no such support exists, skip placement rather than intrude into navigable water.

No random world scatter or runtime placement list is supplied. A/B/C references suggest objects grouped around real work: A's frontage/service areas, B's industrial stock and quay protection, C's modest rural supply context. All three reference images and the current `artifacts/town-inspection-yard.png` were inspected. The current yard shows repeated workshop parcels and detached stock; a rack against a service wall is a targeted composition suggestion, not proof of reference parity. Fenders primarily serve B; sandbags are a restrained battlefield addition, not a claim that all references depict them.

## Verification and remaining work

Godot 4.5.1 command:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --log-file /private/tmp/ra-environment-variants.log \
  --script tests/test_environment_variants.gd
```

Result: **34,694 checks, zero failures**. Checks cover every baked vertex against local and translated/rotated bounds, ground and maximum-height limits, assembly ground contact, all 19 corner-bag support heights, distinct variant geometry, one batch per assembly, shared/cached material reuse, bounded vertex count, catalogue membership and invalid inputs. This is geometry/API evidence; the per-bag support check is not a general physics/contact solver.

The first invocation without `--log-file` crashed in Godot's log rotation after failing to open the sandboxed user log. The explicit writable log avoids that failure. The successful headless run emitted a macOS certificate-store warning; no test failed.

Placement, integrated collision/cover regression, native rendered model review and reference-quality acceptance remain pending with the manager. No native timing or performance measurement was run. Shared tracking/architecture/terrain/visual/scenario files and roadside_props were deliberately left to their owner; this document is the workstream handoff.


## Unified asset library (2026-10-14)

`asset_library.gd` exposes 100 stable IDs: 72 new variants, six earlier variants and 22 existing building/roadside models. Ten categories include architecture. New families are defined in `resources/assets_street.json`, `assets_rural.json`, `assets_waterfront.json` and `assets_battlefield.json`; builders match those names under `scripts/`. `environment_catalog.json` distinguishes library-ready from map-integrated content.

- `entries()` returns specs; `find(id)` returns one record.
- `build(art,parent,id)` creates original geometry. It installs **no gameplay collision**.
- `footprint(id,position,yaw)` gives a conservative transformed placement rectangle.
- `placement_issues(id,position,yaw,world,reserved,surface,supported,context)` checks bounds, context tags, reserved corridors, entry access and receiving drainage zones. Context keys are `tags`, `access_zones` and `drainage_zones` (arrays of Rect2 for zones).
- Overhead assemblies currently reserve their **whole footprint** as non-traversable pending separate ground-support/clearance integration. The term overhead does not grant passage below poles/gantries.
- `render_bounds(model)` measures the emitted meshes separately from conservative placement envelopes.

Launch `./tools/play.sh --script tools/asset_gallery.gd`. Filter categories, page through variants and select Inspect for an enlarged view with 90-degree rotation. The shared-scale toggle holds one camera width across all cards to compare proportions. Capture via `-- --capture-gallery`; then run `python3 tools/build_asset_review.py` for the offline searchable `artifacts/asset-library.html`. Captures are real native model renders, camera-fitted per card—not equal world-scale images or gameplay placements.

EnvironmentPalette fixes neutral colors independent of which faction was drawn last. A dedicated shelter-glass batch is the exception to single-opaque-batch construction; it adds four triangles and no shadow. No asset adds its own light.

Further large-map construction remains deferred at the user's explicit request to complete the assets/rules first. This is an asset registry and authoring-validation foundation, not a finished visual map editor, automatic town generator, or km² performance validation.
