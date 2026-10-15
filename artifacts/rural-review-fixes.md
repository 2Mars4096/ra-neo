# Rural review corrections — 2026-10-14

## Implemented scope

Addresses Claude review issue 5 and the rural portion of issue 4 in `assets-cross-review-claude.md`. All 16 existing rural/vegetation variants remain available. Only these four assigned files were edited:

- `scripts/assets_rural.gd`: replace irrigation bank boxes with closed trapezoidal sections (0.76 m toe width, 0.20 m crest width, 0.36 m height). Earth crests retain soil color; the bed is darker damp-colored earth. Replace flattened foliage spots with small tapered grass blades. Concrete lining has eight light concrete pours, six full-section bank joints and three bed joints; sluice hardware remains steel.
- `resources/assets_rural.json`: describe the revised geometry/materials and retain the bounded, above-datum placement contract.
- `tests/test_assets_rural.gd`: retain all existing bounds/batching/metadata checks and null-index support; add actual bank-vertex slope/crest checks, bed contrast, light concrete/joint checks, and neutral color/finish build-order regression for all 16 variants.
- `artifacts/rural-review-fixes.md`: this implementation and evidence record. Shared tracking documents were left untouched under the explicit four-file ownership restriction.

Rural color references now use preloaded `res://scripts/environment_palette.gd` constants matching the prior neutral style. Shared palette, glass values, vehicle builders and shaders were not edited. Canvas-colored rural tubes explicitly request their existing 0.12 finish: the shared material helper otherwise infers this finish from the last faction's canvas color. This local correction preserves baked finish as well as RGB across build orders.

## Checks actually performed

Ran the requested command with the actual Godot executable:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/ruralfix.log --script tests/test_assets_rural.gd
```

- Engine: `4.5.1.stable.official.f62fdbde1`.
- Exit status: **0**.
- Result: **ASSETS RURAL: 2457536 checks, 0 failures**.
- Log: `/private/tmp/ruralfix.log`. Godot emitted the platform `get_system_ca_certificates` / `ret != noErr` diagnostic; no script parse/runtime errors or assertion failures were reported.
- Actual raw and baked vertices of all 16 models pass their declared XYZ bounds, grounded minimum-Y datum, six cardinal/oblique rotations, and translated/oriented footprint checks. Irrigation bounds remain 5.0 × 2.0 m horizontally with height ceilings 0.55 m (earth) and 1.35 m (sluice); these are enforced envelopes, not measured tight heights.
- Both earth bank meshes have crests narrower than their bases on both sides; the actual bed material is darker than the bank material. The lined variant passes light-concrete material and cross-section/bed joint counts.
- After real tank builds in orders `[1,0,1]` and `[0,1,0]`, all 16 variants match the fresh baseline's entire baked color arrays, including finish alpha. Both cold and reused material caches are exercised: 96 asset rebuild comparisons.
- Existing checks still verify deterministic geometry, triangle preservation, cached materials, one rigid batch, and repeat-bake color preservation. Unindexed surfaces retain their null-index handling.
- Source inspection confirms rural code no longer reads `art.models` color fields; shared geometry/material helper calls remain.

## Evidence limits and unresolved acceptance

Headless evidence establishes geometry, bounds, authored material contrast and palette independence. It does **not** establish visual readability at card or gameplay zoom. Claude issue 5's rendered drainage/field reading remains open pending an authorized rendered review; no new screenshots, native windows or benchmarks were run. Light concrete and sloped banks are implemented design choices, not a claim of visual acceptance.

The models remain bounded raised assemblies on a flat y=0 gallery datum. Damp color does not simulate water; neither model excavates terrain or adds runtime collision/cover. No map integration or performance claim is made. Issue 4's other asset families and safety-color acceptance are outside this assignment. There was no blocker to the assigned implementation or required headless check.
