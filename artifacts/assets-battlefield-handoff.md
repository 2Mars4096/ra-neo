# Battlefield asset library handoff

Status: source and metadata complete; native validation and visual acceptance pending.

## Scope and ownership

Created only these assigned paths (all four were absent on initial inspection):
- scripts/assets_battlefield.gd
- resources/assets_battlefield.json
- tests/test_assets_battlefield.gd
- artifacts/assets-battlefield-handoff.md

No existing file was replaced. No map, gameplay, central catalogue, tracking document, light, texture, image asset, live unit or simulation code was changed. No native process or child agent was launched. Read/write operations and static checks used the existing Node tool. Lead owns integration, labelled gallery, tracking updates and Codex/Claude visual cross-review. The user's asset-library-first priority takes precedence over the older map-first active plan; no map expansion was attempted here.

## API and catalogue

Preload scripts/assets_battlefield.gd. Static build(art, parent, kind:String, variant:String) returns a local-origin Node3D, or null for an unknown pair without adding nodes. Supply the existing BattleVisuals instance. Static specs()->Array reads fresh dictionaries from the assigned JSON list; caller changes do not persist. Models bake once through art.bake_model and reuse art.material / art.models.mat caches.

Footprint is [minimum local X, minimum local Z, width, depth]; height is a conservative maximum above flat local y=0. Rotations must rotate the whole envelope. All entries have cover:false and placement:[flat_ground,library_only]. Collision values solid/flat/overhead are descriptive placement classifications only. No CollisionObject3D, navigation blockers or cover registrations are created. Overhead models still contain physical-looking poles and stakes that an integrator must account for. Entrance coordinates identify a visual front opening, not a tested navigable route.

| Family | Variant A | Variant B | Category |
|---|---|---|---|
| concrete_barrier | jersey | linked_blocks | field_defences |
| filled_wire_basket | single | stepped | field_defences |
| checkpoint_gate | boom | swing | field_defences |
| supply_tent | ridge | lean_to | field_defences |
| antenna | tripod | panel_mast | field_defences |
| camouflage_net | low_drape | high_ridge | field_defences |
| scorch_mark | radial | streak | damage |
| wreck | utility_hulk | tracked_hulk | damage |
| crater | shallow | elongated | damage |

Geometry includes sloped concrete, fabric-lined wire baskets with top grids, gate braces/counterweight, bay-folded tent cloth and grounded stakes, antenna tripod shoes, open woven net ribbons on four/six poles, torn partial wreck skins/cabin ribs and grounded debris. Scorch/crater models sit above unchanged flat ground. Crater darkness and a shallow raised lip suggest a depression; there is no excavation. Wrecks are standalone static assemblies, not copies of live actors. Material colors come from the existing muted palette and nearby environment materials; existing shared shaders may sample existing atlases, but this work adds no textures or lights. Two-sided authored panels use explicit reverse faces and shared materials.

## Checks actually performed

- Inspected active plan, todo, recent changelog, architecture, bugs, environment_variants.gd, visuals.gd, unit_models.gd and existing environment variant tests.
- JSON parse/schema/cardinality checks passed: 18 unique kind/variant pairs, nine families, two variants each; required fields present and bounds dimensions positive.
- Static dispatch-to-metadata family/selector comparison passed.
- Independently mirrored 1,986 authored net/crater/scorch vertex positions in JavaScript; all fit their metadata envelopes. This checks the mirrored arithmetic only, not emitted Godot geometry, tubes, boxes or batching.
- Source delimiter/string balance checks passed for both new GDScript files. This is not a GDScript parser check.
- Manual dimension inspection corrected boom gate height from 1.50 to 1.60 to contain its 1.54-high pedestal post. Other dimensions were inspected but remain unverified by engine execution.

## Native regression suite supplied, NOT RUN

Lead should run with the repository's pinned Godot 4.5.1 executable:

    godot --headless --path . --script tests/test_assets_battlefield.gd

Replace godot with the verified executable path used by this repository. The suite exits nonzero on failure and prints BATTLEFIELD ASSETS counts. It checks all raw and baked surface vertices against full XYZ bounds, flat datum contact, six yaw rotations plus translation, raw/baked triangle-count preservation, mesh-only model hierarchy, one static batch/material, palette reuse, deterministic repeat builds, variant geometric differences, metadata parity, invalid input rejection and rebatch vertex-paint preservation. Tent/net/antenna cases also check multiple ground-contact components. These are not physical stability or route-clearance proofs. The 24,000-vertex per-model guard is a provisional ceiling, not a measured rendering budget.

## Required integration and review

1. Run the supplied native suite; fix any parser, mesh, bounds or batching failures in these assigned files before claiming bounds pass. Run relevant existing material/environment regressions after integration.
2. Add the 18 JSON records to the lead-owned catalogue and labelled gallery. Keep all instances library-only until explicit terrain/navigation placement is implemented elsewhere.
3. Render each labelled variant with scale context, overview and close three-quarter views, plus the reverse side of tent/net/wreck panels. Inspect wire readability, cloth folds, net sag/foot contact, silhouette differences, dark wreck cavity, crater lip grounding and scorch visibility. Flat dressing is intended for local y=0 placement; uneven/sloped ground is unsupported.
4. Codex and Claude independently review actual renders. Record concrete findings and fixes. Neither rendered inspection nor Claude cross-review happened in this assignment; no visual acceptance is claimed.
5. Update lead-owned active plan/todo/changelog and architecture/catalogue tracking with this delivery and outstanding validation. Central docs were deliberately left untouched to respect exclusive file ownership.

Acceptance still open: Godot parse/build, every emitted vertex bounds/rotation tests, runtime batching/material evidence, native visual plausibility, Codex/Claude cross-review and integration. No performance, production-quality, gameplay collision or cover claim is made.
