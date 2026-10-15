# Rural / vegetation library handoff

Date: 2026-10-14. Status: implementation saved; Godot 4.5.1 headless checks passed; native visual acceptance pending.

## Owned deliverables

- `scripts/assets_rural.gd`: original reusable static Godot geometry, eight kinds × two variants = **16 models**.
- `resources/assets_rural.json`: standalone list of 16 metadata dictionaries in the requested schema.
- `tests/test_assets_rural.gd`: focused headless geometry/material regression, **executed and passed: 2,304,281 checks, zero failures**.
- This handoff.

The four assigned paths did not exist at initial inspection. No previous rural files were overwritten. Existing files, shared catalog, map, test runner and project tracking documents were left unchanged because this assignment restricts ownership to these four paths. Lead should record integration in the shared plan/todo/changelog. No delegation or windowed Godot process was launched. The user clarified that headless execution is authorized and required; the suite has now run successfully.

## API and placement contract

```gdscript
const Rural = preload("res://scripts/assets_rural.gd")
var model:Node3D = Rural.build(art, gallery_parent, "tractor", "cab_utility")
var metadata:Array = Rural.specs()
```

`art` is the existing Visuals helper. Invalid kind/variant pairs return null before adding a node. Successful models have identity local transform, ground datum Y=0, dimensions in world metres and a single call to `art.bake_model`. Geometry uses existing `art.box`, `art.models.box`, `tube`, `shell` and their cached materials. Vehicles and drawbars face -Z. No lights, new textures, collision objects, cover registration, animation, terrain editing or map placement are created.

The JSON `collision` field is descriptive **placement classification only**, not gameplay collision. `flat` grasses/reeds still have visual height. All `cover` values are false. Footprints are conservative local XZ rectangles, with declared upper height. Solid/flat metadata does not authorize scattering assets into traversable lanes. No asset needs an entrance marker. Each `specs()` call reads a fresh metadata list, so callers cannot mutate shared state; bulk integrations can retain their own copy.

## Gallery labels and distinctions

| Kind | Variant A | Variant B | Geometry distinction |
|---|---|---|---|
| orchard | open_crown | trained_row | Three forked trees with broad lateral crown lobes / narrow trained crowns with stakes, end posts and wires |
| hedgerow | mixed_shrubs | laid_bank | Rooted irregular shrub row / raised low bank with laid stems and stakes |
| irrigation_ditch | earth_banks | lined_sluice | Dry earth banks with tufts / lined bed joints, gate, posts and screw handle |
| tractor | open_utility | cab_utility | Seat and roll bar / framed enclosed cab and roof; both have differentiated wheels, engine, grille, fenders, exhaust and hitch |
| farm_trailer | flatbed | grain_tipper | Single axle, timber platform and end racks / tandem axle, open grain body, ribs and stowed ram |
| grass_patch | short_sward | dry_tussocks | Fifteen short low tufts / nine taller separated tussocks |
| reed_bed | rushes | cattails | Branched pale seed panicles / dark cylindrical seed heads |
| broken_tree | snapped_snag | fallen_bough | Standing broken trunk and splinters / rooted stump beside fallen trunk with snapped twigs |

Orchards, ditches, tractors and trailers use category `rural`; hedgerows, grasses, reeds and broken trees use `vegetation`. Canopies use closed asymmetric lobed geometry, not single spherical heads. Both ditches sit above the datum: they **do not excavate the terrain** and have no simulated or rendered flowing water.

## Checks actually performed

- Read the existing environment builder/tests, Visuals batching/material cache, UnitModels primitives and current repository plan/architecture.
- Python JSON validation **passed**: 16 unique kind/variant pairs, eight kinds with exactly two variants each; exact required keys; permitted categories/classifications; positive footprint sizes/heights; nonempty placement tags; all cover flags false.
- Python source checks **passed**: metadata/builder kind parity, two metadata variants for each dispatch branch, one bake call, and lexical delimiter balance in builder/test. Delimiter balance is not GDScript compilation.
- Source inspection confirmed the eight dispatch branches, explicit variant geometry, use of the existing cached material helpers and bake path, and absence of gameplay registration/new textures/lights.
- Manually traced conservative extents and supports. Corrected tilted grass stems to start above a grounded vertical foot, hedge stems to meet grounded root collars, tractor axles to align with wheel centers, and trailer spring blocks to connect axles to the frame. This is source reasoning, **not measured Godot mesh evidence**.
- The initial handoff incorrectly treated the no-native-process constraint as excluding headless execution. After the user clarified it excludes windowed renders only, ran the exact authorized command below with Godot `v4.5.1.stable.official.f62fdbde1`.
- Fixed the lead-reported test failure: an unindexed mesh returns a null `Mesh.ARRAY_INDEX` slot, which cannot be assigned directly to `PackedInt32Array`. Triangle counting now accepts null or empty indices and uses vertex count for these valid unindexed surfaces, while using index count for indexed surfaces. Added complete-triple checks; actual mesh inspection remains intact.
- Headless result: **`ASSETS RURAL: 2304281 checks, 0 failures`**, process exit **0**. Reviewed `/private/tmp/rural-check.log`: no `SCRIPT ERROR` or `FAIL:` output. All 16 builds, raw/baked bounds, rotated bounds, grounded datum, topology counts and material checks passed. No model or metadata changes were needed after correcting index handling.
- The run emitted the known macOS certificate-discovery diagnostic (`get_system_ca_certificates`, `ret != noErr`). It did not prevent the suite from completing; it is not a geometry-test failure.
- No windowed native capture, performance measurement or Codex/Claude visual cross-review was performed. Visual acceptance remains open.

## Executed test coverage and reproduction

Executed with the pinned Godot 4.5.1:

```sh
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . --log-file /private/tmp/rural-check.log --script tests/test_assets_rural.gd
```

Require exit zero, an `ASSETS RURAL:` marker with zero failures, and no `SCRIPT ERROR` or `FAIL:` output; engine exit status alone is insufficient. This new suite is **not** registered in `tools/check.py` yet.

The executed suite checks all actual surface vertices before and after baking against full XYZ bounds, finite coordinates, contact with Y=0, and six translated cardinal/oblique rotations. It also checks identity origins, one rigid mesh/surface, triangle preservation across batching, complete triangle triples, baked paint, second-bake paint/vertex preservation, deterministic repeat builds, shared batch-material identity, palette-cache stability, distinct vertex signatures between variants, all 16 metadata entries, invalid-input rejection and absence of physics/light nodes. Bounds acceptance for these fixtures is now supported by engine execution. This does not establish rendered appearance or physical support for every connected component.

## Remaining acceptance work

1. Headless build/bounds/topology acceptance completed. Lead should retain the executed result when integrating the suite and rerun if integration changes geometry or helpers.
2. Build a labelled gallery from the JSON. Provide oblique overview and close views of both variants, plus rear/side tractor, trailer underside/drawbar, ditch gate and tree roots. Space cells using each footprint; put reeds on a visible supporting bank datum.
3. Perform independent Codex and Claude visual reviews of those native captures. Review crown silhouette, plant density, tractor wheel contact/fender clearance/cab scale, trailer support and empty body readability, ditch-bank seams, fallen-log contact and miniature material consistency. Neither reviewer has accepted these assets yet.
4. Lead integrates metadata and registers the focused suite, then updates shared tracking. Prioritize completing the categorized asset library before further map expansion.

Visual limitations: opaque stylized crowns/blades and cab glazing, static wheels/gates/trailer bodies, intentionally dry channel beds, and no LOD or collision implementation. Believable scale and construction are design intent pending native review. No production-quality, gameplay-cover or performance claim is made.
