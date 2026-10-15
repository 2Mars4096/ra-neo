# Street review fixes — 2026-10-14

Implemented supported visual findings 4 and 5 only. Edited `scripts/assets_street.gd`, `resources/assets_street.json`, `tests/test_assets_street.gd` and this handoff. Registry, gallery, other builders and shared tracking documents remain lead-owned.

## Changes

- **Glazed shelter:** removed its two opaque blue pane boxes. Back/end openings now have two thin, double-sided planes in one separate cached `StandardMaterial3D` alpha-blended batch: pale green-grey tint, alpha 0.18, roughness 0.18, specular 0.65. The existing bench, posts, roof, advert case and timetable remain in the shared opaque batch. No lights, emission, textures or vehicle-material changes. Glass is appended after opaque baking because the current shared baker converts StandardMaterial3D to opaque vertex paint. Do not rebake the completed assembly with that baker without preserving this exception.
- **Headwall rip-rap:** replaced the evenly spaced border with eleven explicitly positioned/sized/rotated stones in asymmetric side pockets. A seeded generator varies stone shape only; placement does not use random scatter. Exposed central ground and gaps remain beyond the apron. Existing footprint and height remain valid; metadata descriptions now describe both changes.
- **Tests:** exact batch expectations are now two for the glazed shelter, one for each other street model. Bounds, rotations, vertex budgets and repeat-build determinism include every batch. Added pane coverage/nondegeneracy, alpha, two-sidedness, no emission/texture/shadow, cached material reuse, unchanged opaque pickup batching, stone ground contact and exposed discharge-ground checks. The optional CPU raster is explicitly documented as opaque-only and cannot validate transparency; it was not run.

## Actual validation

Executed Godot **4.5.1.stable.official.f62fdbde1**, headless:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Volumes/data/Dropbox/Projects/ra-neo --log-file /private/tmp/streetfix.log --script tests/test_assets_street.gd
```

Final result: **432,168 checks, 0 failures**, exit 0, covering all 20 street variants. First run before the added discharge-ground assertions also passed (432,145 checks). No script/parse errors appeared. Both runs emitted a macOS `get_system_ca_certificates` startup error (`ret != noErr`); the final suite completed despite it. Log: `/private/tmp/streetfix.log`.

Measured geometry from the final run:

| Asset | Vertices across batches | X | Z | Y |
|---|---:|---|---|---|
| Glazed shelter | 1,288 | −1.75…2.44 | −0.90…0.90 | 0…2.66 |
| Pipe headwall | 2,229 | −1.92…1.90 | −0.48…1.62 | 0…2.42 |

## Batch cost and remaining acceptance

The shelter exception adds **one transparent surface/batch per visible shelter per camera pass**, containing **12 submitted vertices / four triangles**, with one material shared across builds. It has no shadow casting or enabled depth prepass. The opaque shelter batch remains one; the other 19 street assets remain one batch each. Thus N visible shelters add at most N transparent color submissions per ordinary camera pass before any engine batching/culling; multiple camera views scale this count. These are structural cost bounds, not measured draw calls or frame timings. Transparent fill cost depends on projected pane area and overlapping shelters.

Alpha 0.18 permits the already-present interior/background to contribute through broad panes; actual glass readability, lighting response and transparent sorting still require the lead's rendered gallery review. Headwall composition also awaits the lead's fresh capture. No windowed/native render, benchmark, full registry suite or gameplay integration test was run. The registry suite writes a lead-owned artifact and was deliberately left for integration. No rendered acceptance or performance claim is made.
