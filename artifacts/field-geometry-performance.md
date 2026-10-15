# Incremental field geometry — 2026-10-14

Implemented `BattleTerrain.update_field_geometry(blocks:Array, covers:Array)->bool` in `scripts/terrain.gd`. New validation/performance fixture: `tests/test_field_geometry.gd`. This assignment changed no FieldOps, simulation, HUD, existing tests, tracking documents, or native benchmark files. The other owner integrated the API into FieldOps during this work; the final existing FieldOps suites ran against that shared implementation.

## Contract and implementation

- Copies and deduplicates incoming rectangle arrays. Array ordering or duplicate entries do not trigger an occlusion change.
- Returns true when physical reservation rectangles are added/removed; returns false for cover-only completion/removal and unchanged reservations. The caller can use true to clear visibility caches. Comparison is by rectangle membership, not geometric simplification of differently partitioned but equivalent unions.
- Computes the symmetric difference of old/new physical rectangles. For each already cached land grid, grows changed rectangles by that grid's **actual construction radius + 0.27** (the existing 0.15 navigation padding plus 0.12 rectangle clearance). It visits the union of affected cells, clamped to map bounds, once per grid.
- Recomputes each affected cell with authoritative `traversable` after installing new blocks. This retains all remaining static buildings, overlapping field blocks, trees, poles, shoreline, quay and roadside exclusions. Removal never blindly marks cells open.
- Cached grid identities remain stable. Sea/air solid grids are untouched. No full obstacle-grid rebuild occurs for completion or no-change calls.
- Grid creation now stores `navigation_radius` metadata. Cache keys round radii to two decimals; the updater does **not** reconstruct a radius from that key. A dedicated boundary case proves that radius 1.23456 is retained instead of approximating it as 1.23.
- Cover changes invalidate weight layers and advance the existing lazy weight epoch, using a coherent current wetness sample. Each requested land grid receives current costs through `nav_grid`; untouched grids defer cost work. Geometry-only changes on Riverside do not invalidate costs because Riverside does not infer cover from unfinished dynamic blocks. Other showcase maps do infer cover from dynamic rectangles and correctly invalidate costs on such changes.
- The API is synchronous and must run outside an active path query's temporary exclusions, consistent with current simulation execution. It updates the fine navigation grids used by paths, not the legacy coarse `land`/`sea` fields or visibility caches owned by the caller.

## Headless tests actually run

Godot **4.5.1-stable (official)**. All six suites exited 0:

| Suite | Checks | Failures |
|---|---:|---:|
| New `test_field_geometry.gd` | 280 | 0 |
| `test_performance_repair.gd` | 1,293 | 0 |
| `test_field_ops.gd` | 204 | 0 |
| `test_field_ops_edges.gd` | 20 | 0 |
| `test_mobility.gd` | 22 | 0 |
| `test_road_routing.gd` | 9 | 0 |
| Total | 1,828 | 0 |

The new test compares **every cell's solid flag and weight** across six cached grids against an independently constructed fresh terrain oracle. The oracle assigns physical/cover arrays directly and builds new grids; it does not invoke the new updater. Land routes are compared exactly after each operation. Cases include placement, completion, overlapping placement/completion/removal, cover removal, reordered/duplicate arrays, map-edge clipping, removal of all structures, unchanged data, caller-array mutation, same-band delayed weights after a weather transition, sea-first access, other-showcase automatic cover, and a non-rounded-radius boundary.

Fixtures include independent static buildings, roadside rectangles and trees overlapping the edited region. Checks also retain original grid references, bound local solid work, assert zero traversal work on cover-only changes, and verify no cache growth. Assertion counts aggregate full-grid comparisons; they are not counts of the millions of individual property comparisons inside those assertions. The existing performance-repair suite samples route segments, so its count can vary when the concurrently integrated proposal logic returns shorter routes.

Command used for each named suite (replace filename and log suffix):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/field-geometry-test_field_geometry.log --script tests/test_field_geometry.gd
```

Logs: `/private/tmp/field-geometry-<suite-name>.log`. Raw measured operation data: `/private/tmp/field-geometry-proof.json`. Successful runs contain the known macOS certificate diagnostic and no GDScript/assertion failures. No GPU/windowed/native test or delegated worker was launched.

## CPU proof and limitations

One final local synchronous headless sample per operation, Riverside 144×108. Four land grids (three mobility profiles, four exact radius/profile combinations), one sea and one air grid are prewarmed. A subclass counts calls to authoritative `traversable`. Fresh-build comparison constructs the same six grids after assigning identical arrays. Constructor/setup time and correctness comparisons are outside the recorded timing intervals. Timings are not frame times, confidence intervals, or proof of uncontended host execution.

| Operation | Local update ms | Local solid checks | All deferred weight requests ms | Fresh six-grid build ms |
|---|---:|---:|---:|---:|
| Add structure | 2.197 | 484 | 0.018 | 586.588 |
| Complete cover | 0.009 | 0 | 237.337 | 676.312 |
| Add overlapping structure | 0.890 | 259 | 0.014 | 560.019 |
| Complete overlapping cover | 0.017 | 0 | 215.399 | 584.299 |
| Reorder/duplicate unchanged input | 0.015 | 0 | 0.033 | 597.427 |
| Remove first overlapping structure/cover | 2.559 | 484 | 242.178 | 537.373 |
| Remove remaining cover only | 0.009 | 0 | 210.488 | 621.710 |
| Add map-edge structure | 0.383 | 161 | 0.014 | 645.993 |
| Remove all remaining structures | 2.227 | 420 | 0.013 | 574.986 |
| No change | 0.004 | 0 | 0.012 | 588.379 |

Each fresh six-grid build performs **93,312** solid evaluations. The incremental placement/removal operations perform **161–484**, with zero on completion/no-change. Grid identity preservation and exact oracle equivalence support the reduction independently of host timing variability.

**Remaining cost:** cover completion still invalidates mobility cost layers. Forcing all grids to refresh immediately costs **210–242 ms** in this fixture. The repair removes obstacle reconstruction; it does not eliminate full-map cost-layer generation or guarantee hitch-free completion. Normal lazy requesting may spread that cost across frames, but that was not measured here. Incremental cover-cost patching or further scheduling would be separate work. No 16.7 ms frame-p95, input-latency, large-match, or GPU claim is made.

## Source labels and handoff

Hashes of the tested owned source and key fixture input:

- `scripts/terrain.gd`: `91f2dbdf59c987f6dd5180009167eded4ea2879f3af0a46b3189ee7a3c322954`
- `tests/test_field_geometry.gd`: `bc707ff104358d914ba92b26cd845ffe6de33b228378c1974f30585a0898fc7e`
- `resources/scenarios.json`: `b7d55f536f97e37ba52dfa7eca9a83e1dff184a5e35d470f920de8379931607a`

Pre-change owned terrain source is retained at `/private/tmp/terrain-before-field-geometry.gd`. The comparison oracle is a fresh instance of tested terrain with no cached grids, rather than an older whole-game snapshot. Other integration work continued in the shared workspace; these hashes label this result, not a frozen release build.

Scoped implementation and targeted validation are complete. Main retains integration tracking and full-suite/native acceptance. The remaining cost-layer spike above is explicit and unresolved; no required scoped API/correctness criterion is blocked.
