# Performance repairs — 2026-10-14

Implemented only `scripts/terrain.gd`, the proposal/comment portion of `scripts/field_ops.gd`, two new focused test/diagnostic scripts, and this report. FieldOps outside proposal/comment is byte-identical to the saved pre-change source. No HUD, build/cancel/tick/purchase, simulation, check.py, tracking documents, or native benchmark changes. No delegation, native/windowed test, or GPU timing was used.

## Repairs

**Lazy weather weights.** Navigation grids retain their geometry and instance identity. A weather-band epoch invalidates cached weight layers, but only the requested land grid receives new point weights. Its metadata records the epoch. Unrequested grids remain untouched until `nav_grid` is called for them; all path searches acquire their grid through that method. Monotonic epochs also handle returning to an earlier wetness band. Sea/air grids do not acquire land costs.

Profiles requested later in the same band use the band's first-query wetness sample, so an already cached profile does not acquire different weights merely because refresh was deferred. Weight generation temporarily applies that sample synchronously and restores live wetness before returning; movement still reads live wetness. A sea-query-first boundary is covered. Explicit `navigation.clear()` / `navigation_weights.clear()` remains supported; newly built grids receive current geometry, and cleared weight layers start a coherent new sample. Weight-cache initialization is tracked separately from an empty cache awaiting its first lazy request.

**Cached placement validation.** Proposal no longer replaces `terrain.navigation` or appends a temporary dynamic structure rectangle. It sends the existing cached path search a temporary exclusion circle with radius:

```text
half rectangle diagonal + engineer section radius + 0.27
```

This encloses the entire structure rectangle and engineer clearance (including the existing 0.12 obstacle and 0.15 grid padding). Existing `terrain.path` temporarily marks local excluded cells and restores them on all exits; continuous segment-to-circle checks also constrain direct paths and smoothing. Workpoints retain their existing 16 candidate positions and must pass section/terrain clearance plus living displaced-member checks. Existing actual-body site checks, visibility, supply, assignment, communication and availability gates remain. Proposal still does not change orders, funds or units; build still revalidates before charging/spawning, and its explicit-order semantics are unchanged.

**Tradeoff:** the enclosing circle is more conservative than a rectangle at its side midpoints. Tight sites or approaches that an exact rectangle search could admit may now be rejected; placement routes are not claimed byte-identical. This avoids unsafe corner cutting and requires no new rectangular search implementation. First cold access or real construction/destruction invalidation can still build a grid once. Repeated previews on unchanged geometry no longer build one grid each.

## Actual headless validation

Godot `4.5.1-stable (official)`, explicit logs in `/private/tmp`, all exit 0:

| Suite | Checks | Failures |
|---|---:|---:|
| `tests/test_performance_repair.gd` (new) | 4,323 | 0 |
| `tests/test_field_ops.gd` | 204 | 0 |
| `tests/test_field_ops_edges.gd` | 20 | 0 |
| `tests/test_mobility.gd` | 22 | 0 |
| `tests/test_road_routing.gd` | 9 | 0 |
| Total | 4,578 | 0 |

The new suite verifies untouched stale grids until requested, stable grid identity, exact full-grid weights/solids and routes versus eager requesting, wetness round trips, deferred same-band sampling, sea-first transitions, live wetness restoration, explicit obstacle/cache invalidation, all four placement kinds, whole-rectangle swept route/workpoint clearance, preview state preservation, no preview cache growth, displaced live/dead bodies, occupied workpoints, visibility rejection, disconnected routes and grid restoration after failed searches. Existing suites exercise actual construction ticks, completion, cancellations, explicit orders, atomic rejection, destruction, healing and weighted movement.

Tests use full-grid state hashes for restoration/equality, and dense samples plus the implementation's analytic circle-segment exclusion for proposed-rectangle route safety. They do not exhaust every possible map/body arrangement.

Reproduce each suite:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/performance-repair-test_performance_repair.log --script tests/test_performance_repair.gd
```

Other suite logs follow `/private/tmp/performance-repair-<suite-name>.log`. Logs show the known macOS system-certificate diagnostic; successful runs have no GDScript/assertion errors. The full integrated suite was not run by this worker.

## Before/after CPU proof

New reproducible runner: `tests/profile_performance_repair.gd`, headless-only. Sequential baseline and repaired runs use identical frozen scripts/resources except the two owned production files. Cold setup is excluded. These are synchronous CPU operation timings, not rendered frame rates or input latency. Host contention is not independently ruled out; deterministic work counts and matching outputs provide stronger evidence than timing alone.

Weather workload: Riverside 144×108, six warmed grids (three profiles × two radii), eight wetness transitions. Time the first infantry-grid request, then separately request all six grids. Hash all resulting weights and 24 nonempty weighted routes. Placement workload: actual Riverside geometry, one engineer at (14,97), warmed infantry grid, 24 visible previews across all four structures near (25,96); count cache misses using a diagnostic terrain subclass. No production instrumentation is installed.

Final run:

| CPU operation | Before mean / p95 | After mean / p95 |
|---|---:|---:|
| First query after weather-band change (8 samples) | 214.031 / 221.974 ms | 69.907 / 75.219 ms |
| Remaining grid requests immediately afterward (8 batches) | 0.016 / 0.019 ms | 142.145 / 146.713 ms |
| Placement preview (24 samples) | 71.105 / 76.117 ms | 11.262 / 14.652 ms |

- Preview full-grid creations: **24 → 0**. All **24/24** sites accepted in both runs. Units/orders, supply and dynamic obstacles unchanged after preview batches.
- Weather grid creations: **6 → 6**, all from initial warmup. No geometry rebuild at band transitions.
- Total weather work if every stale grid is immediately requested: **1,712.370 → 1,696.415 ms** over eight transitions. This small total-time difference is not treated as a reliable optimization; the repair defers work on unrequested grids. It does not eliminate cost when all grids are needed together.
- First-query mean decreased about **67%** in this fixture; preview mean about **84%**. These are operation-level results from one final pair, not gameplay FPS claims.
- All grid-weight values match before/after: SHA256 `d19307351ca3e0527700abf7b4fe5c2d601efc87ccc3f2b7a9f6916d70555eda`.
- All 24 sampled weighted routes match before/after: SHA256 `d2d6fcca86ff1be1fc3cb47f6b394b00ac8c8e3feeee8951efeb447d603b3d2d`.

An earlier pair also showed zero new preview grids and reduced first-query cost, but varied in absolute times (preview means 83.69 → 11.54 ms). Final numbers above include the sea-first edge-case repair. Small sample p95s, especially eight-transition p95, effectively reflect the maximum sample.

Frozen inputs and final raw results:

- `/private/tmp/performance-repair-baseline/`, manifest SHA256 `66bc64dd91e01d49aa45ee984ccea39db2170f8590097d2d53ad95ccd6231227`
- `/private/tmp/performance-repair-after/`, manifest SHA256 `1f27e25ead2561f1233fb68e768445a8043ca568cb862b60ebc1c50e2ae71fd5`
- Each snapshot contains `source-hashes.json` for scripts/resources/tests.
- `/private/tmp/performance-repair-before-cost-final.json` and matching `.log`
- `/private/tmp/performance-repair-after-cost-final.json` and matching `.log`

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /private/tmp/performance-repair-baseline --log-file /private/tmp/performance-repair-before-cost-final.log --script tests/profile_performance_repair.gd -- --output=/private/tmp/performance-repair-before-cost-final.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /private/tmp/performance-repair-after --log-file /private/tmp/performance-repair-after-cost-final.log --script tests/profile_performance_repair.gd -- --output=/private/tmp/performance-repair-after-cost-final.json
```

Owned source hashes:

| File | Before SHA256 | After SHA256 |
|---|---|---|
| terrain.gd | `a01e66978948d64b6c49c69698264c9552d81d14bfc65779c8a031e622fc6e19` | `cebda66db3d8c2b80b64f9f8f2dd787260f877b5c3cd0ce8a85e2e9dfaa5973d` |
| field_ops.gd | `25fccbdc1f89e97d3711c8a5c24fbf90ba56195c60313686ce89c395a6167f0f` | `3d41e0e0143be049d03b2efeeb57e527a42887ac4aa38ea7c9337797502d7bf0` |

## Limits and integration handoff

Both scoped repairs and targeted validation are complete. Main retains tracking docs/check.py/HUD integration ownership. Remaining acceptance: integrated suite, representative repeated pointer previews in the final HUD, congested/tight-site usability, and isolated native frame/input/GPU measurements. No claim that the 16.7 ms frame target is met: a single-profile weather refresh is still expensive, and the 24-preview fixture does not cover worst-case unreachable-site searches. Broader path budgets, weight-generation optimization and HUD request caching remain separate work.
