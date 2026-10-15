# Waterfront asset handoff — 2026-10-14

Status: all 18 models pass the executed Godot 4.5.1 headless suite; gallery and visual cross-review pending.

## Scope and recovery

All four assigned paths were absent at initial inspection. Created only these files; shared catalogue, gallery, map, tracking documents and runtime placements were not changed. Initial work used the JavaScript filesystem API without native execution. Following the user's clarification that headless tests are authorized and required, ran the specified Godot headless command twice. No windowed GUI renders or delegated agents were launched. This follow-up changed only the owned test and handoff; builder and metadata needed no geometry corrections after execution.

The assignment is interpreted as **nine kinds × two variants = 18 models**.

## Deliverables

- scripts/assets_waterfront.gd: original static Godot assemblies, static build(art,parent,kind:String,variant:String)->Node3D and static specs()->Array. Invalid pairs return null without adding a node. Models begin at the local origin and bake through the existing material cache into a static batch. The builder reads its own JSON metadata.
- resources/assets_waterfront.json: 18 flat list records using the requested schema. Categories are industry/waterfront. Collision strings classify prospective placement only; no physics/navigation objects or cover are created. Entrances are omitted because these are props, not enterable structures.
- tests/test_assets_waterfront.gd: standalone SceneTree test for Godot 4.5.1; executed successfully, including indexed/unindexed ray-helper regression fixtures.
- This handoff.

| Kind | Variants | Construction distinction |
|---|---|---|
| pipe_stack | paired_large, pyramid | Two large hollow pipes vs six tangent stacked pipes; supported sleepers/chocks; reuses existing original annular pipe primitive |
| gantry | fixed, travelling | Grounded baseplates vs four wheels; braced uprights, I beam, shifted trolley, cables and open hook |
| tyre_fender | single, double | One vs two actual open tyres with hangers and supported mounts |
| railings | straight, corner | Three-post rail vs return; shared corner post, toe plates and baseplates |
| access_ladder | wall, guarded | Wall stand-offs/rungs vs connected half-hoop safety cage |
| mooring_rope | coil, bollard | Layered rope coil/tail vs twin bitts with connected rope turns |
| small_boat | rowing, outboard | Open tapered hull, three benches/oars/rowlocks vs two benches/transom motor/tiller/leg/propeller |
| barge | flat_deck, cargo_hold | Blunt lighter with timber deck vs visible ribbed floor and raised open coaming |
| lifebuoy | post, cabinet | Open torus with bands and tied grab rope on hook vs supported open-front rescue cabinet |

## Placement contract

Dimensions use existing scene units, provisionally treated as metre-like. Every model declares a conservative full x/z envelope and height, with minimum geometry y=0. Wall fixtures mount toward +Z, with the working side toward -Z. Boat bow is -Z. **Boat/barge y=0 is the dry gallery hull bottom, not a waterline.** Their descriptions explicitly require a later immersion choice. No buoyancy, drive animation, collision, cover or gameplay interaction is claimed. Gantry overhead classification does not assert navigable clearance.

Existing muted art/material calls are reused; no new textures, shaders or lights. Torus parts use the existing cached equipment material path. Boats have actual outer/inner hull faces and floors, not a capped solid hull. Decorative ropes are static and are not a physical mooring solution.

## Checks actually performed

- Read session tracking context, active plan 10, existing environment variants, art box/material/batching implementation, tube/material cache and the existing environment-variant test.
- JavaScript filesystem readback and JSON parse: 18 entries, nine requested kinds, two unique variants each; schema dimensions, categories, cover false, placement strings and all four hull immersion descriptions checked.
- Static source delimiter nesting and absence of new light/collider/texture construction checked; selected hull rim/rear normal directions checked with vector arithmetic.
- **638 static assertions passed** (most count individual source delimiters; this is not 638 runtime geometry checks).
- Reviewed authored dimensions/support connections manually; corrected hull winding, avoided degenerate floor fan triangles, joined lifebuoy grab ropes, grounded cargo coaming and removed the duplicated railing corner post. These are source-level corrections, not evidence of rendered quality.

## Executed native validation and fixed failure

The lead's initial execution found a script error assigning a null Mesh.ARRAY_INDEX slot to PackedInt32Array for unindexed geometry. The helper now initializes an empty PackedInt32Array and copies the slot only when non-null. Added actual SurfaceTool triangle fixtures for indexed and unindexed topology, each checking a known hit and miss, so broken ray handling cannot silently pass hollow-part tests.

The executed test visits every raw and baked vertex, checking finite coordinates, full xyz metadata bounds and ground datum; then applies six yaw rotations and a translated/raised origin. It checks source-coordinate retention through batching, deterministic repeats, second-pass batching, cached material reuse, one material batch, geometry budgets, metadata parity, invalid-input side effects and distinct variant signatures. Geometry ray tests probe pipe bores, torus holes and open boat/hold floors. All passed; no bounds, bore or hull failures remained after fixing index handling.

Executed from repository root:

    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/waterfront-check.log --script tests/test_assets_waterfront.gd

- Engine: Godot v4.5.1.stable.official.f62fdbde1.
- First run after null-slot fix: 497328 checks, 0 failures, exit 0.
- Final run including six ray-helper regression assertions: **WATERFRONT ASSETS: 497334 checks, 0 failures**, exit 0.
- Both runs emitted a macOS system CA-certificate startup diagnostic at get_system_ca_certificates (os_macos.mm:991). No script errors appeared; the suite completed. This diagnostic remains outside the owned asset scope and is not claimed fixed.
- Latest engine log: /private/tmp/waterfront-check.log. Headless geometry validation does not establish rendered appearance, performance or visual review acceptance.

## Lead integration and review remaining

1. Headless parser and dedicated geometry suite now pass. Re-run after any integration edits.
2. Integrate the JSON into the comprehensive library catalogue and create the labelled gallery. Retain all 18 unique kind/variant labels and category groupings; library-first scope does not require map placement.
3. Capture dry gallery overview plus pipe-end, hook/support, tyre-hole, cage, rope and open-hull detail angles. Use side views to inspect datum/support contacts, and top/oblique views to inspect hollow forms, gunwales, benches and drive differences. A render must confirm winding/culling and readability; static checks cannot.
4. Have Codex and Claude independently inspect those actual renders, record findings and fix accepted issues. Neither native Codex visual review nor Claude cross-review was performed in this worker session.
5. Lead updates shared plan/todo/changelog and catalogue status; those files are outside this worker's ownership. No performance measurement or AAA-quality claim is made.

Acceptance met: all 18 models build and pass native bounds, datum, rotations, bore/hull, variant, batching and material-reuse tests. Acceptance still open: labelled gallery integration, rendered quality/support inspection, and Codex/Claude cross-review.
