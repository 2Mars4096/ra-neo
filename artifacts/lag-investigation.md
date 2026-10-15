# Lag investigation — 2026-10-14

CPU evidence points first to movement and occasional synchronous path/AI work. It does **not** establish that removing the classic economy fixes lag. No production source, tracking docs, check.py, or native benchmark was changed by this investigation.

## Scope and reproducibility

New runner: `tools/profile_field_ops.gd`. It refuses non-headless execution and requires a prepared frozen diagnostic copy. Despite the filename, these measurements concern legacy-classic Riverside and busy Canal Watch, **not completed FieldOps gameplay**.

Frozen copy: `/private/tmp/ra-neo-lag-20261014`; uninstrumented comparison: `/private/tmp/ra-neo-lag-baseline`. Initial source manifest: `/private/tmp/ra-neo-lag-20261014/source-hashes.json`, SHA256 `fa85d0b585daf381d72e0abbcb70cac86d980f8c6fa008f50d514529336938db`. The copy verified every listed file against both source and destination immediately after copying. Assets, resources, shaders, scene scripts, project settings and existing import cache were copied; production was only read.

**Transitional-source caveat:** simulation and scenario edits landed concurrently before the freeze. `simulation.gd` referenced a not-yet-created `field_ops.gd`, and scenario 5 already declared `field_ops`. In the temporary copies only, scenario 5 mode was set to `classic`; a diagnostic FieldOps stub asserts that construction/population/tick/purchase cannot execute and permits `pause_builder` only with an empty field_ops dictionary. All other frozen scenario data was retained. This is a reconstructed legacy-mode fixture on the frozen Riverside geometry, not a byte-identical historical build or a test of the new mode. Both measured copies use these same adaptations. Main should repeat against the completed integrated build.

Instrumentation wraps original methods: rename body to `_lag_original_<method>`, call it with identical arguments, record monotonic elapsed microseconds, and return its original result. A generated `tools/phase_probe.gd` holds static sample arrays. This covers early returns without editing function logic. The initial preparer is retained at `/private/tmp/prepare_field_profile.py`; it records the original freeze, but its first void-return detector required correction for `->void` without spaces. The final runnable copies, rather than rerunning that initial preparer against changing production, are the reproduction inputs.

Wrapped functions:

- Simulation: tick, sight, tactical updates, group movement, infantry combat, actor/group spatial rebuilds.
- Infantry: movement, regroup state, regroup destinations; tactical director update; classic tick.
- Terrain: path, cached navigation-grid access, weight-layer creation. Follow-up labels cache misses and weather refreshes independently.
- Presentation: battle process, unit synchronization, fog update, event consumption; HUD draw/sidebar/minimap; follow-up animation pose.

All times are **inclusive**. Child path costs overlap movement/AI; sidebar includes minimap; pose is inside sync_units. Do not add these totals or p95s as independent frame costs. Wrapper timing excludes its own final record append but includes nested instrumentation overhead. Static-memory deltas include retained sample arrays and caches and are not allocation-rate or leak measurements.

Commands already executed (Godot 4.5.1-stable, dummy/headless rendering):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /private/tmp/ra-neo-lag-20261014 --log-file /private/tmp/field-profile-instrumented.log --script tools/profile_field_ops.gd -- --output=/private/tmp/field-profile-instrumented.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /private/tmp/ra-neo-lag-baseline --log-file /private/tmp/field-profile-baseline.log --script tools/profile_field_ops.gd -- --output=/private/tmp/field-profile-baseline.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /private/tmp/ra-neo-lag-20261014 --log-file /private/tmp/field-profile-detail-fixed.log --script tools/profile_field_ops.gd -- --output=/private/tmp/field-profile-detail.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /private/tmp/ra-neo-lag-20261014 --log-file /private/tmp/field-profile-actor-test.log --script tests/test_actor_spatial.gd
```

Raw JSON/logs and snapshots are local temporary artifacts; the measurements below are retained in this repository report. No native/windowed/GPU timing was launched. No workers were launched. A process-list query was denied by the sandbox, so this worker cannot independently certify host isolation or absence of other app instances. The lead's earlier observation of no running instances is not a measurement throughout these runs.

## Workloads and results

Each simulation runs fixed 1/30-second ticks, 60 warmup ticks followed by 600 measured ticks (20 simulated seconds). Events are cleared each tick, as these fixtures have no live effects consumer. They run faster than real time and do not measure input/display latency. Startup and initial command/path preparation are excluded from tick percentiles.

Riverside: initial classic population, friendly rifle/tank/ATGM attack-move toward (72,45), ends at 22 simulated seconds with eight group records. It is an early small match, not a busy late-game economy or full mission. Busy Canal Watch: original population plus 22 friendly rifle groups, starts at time 45, all friendlies attack-move toward (46,22), ends at time 67 with 35 records. It uses the frozen three-member definitions and differs from the accepted historical four-member/approximately 100-member benchmark. It is not a strict before/after comparison to that record.

| 600 ticks | Uninstrumented total | Uninstrumented mean / p95 / max | Instrumented total | Instrumented p95 / max |
|---|---:|---:|---:|---:|
| Classic Riverside | 731.483 ms | 1.219 / 5.380 / 21.817 ms | 745.567 ms | 5.473 / 11.907 ms |
| Busy Canal Watch | 5,361.373 ms | 8.936 / 14.086 / 101.753 ms | 5,917.166 ms | 16.485 / 140.005 ms |

Single sequential samples, not statistical confidence intervals. Instrumented total is approximately 1.9% / 10.4% higher respectively; this includes instrumentation and host/run variation, not a calibrated overhead correction. Different maxima demonstrate why a single extreme should not be treated as stable performance. Instrumented fixture setup took 494.7 / 953.1 ms respectively and was excluded above.

Final state hashes match across uninstrumented, instrumented, and follow-up runs. The hash covers serialized units/member state, combat RNG state, classic dictionary and credits; it does not prove every internal cache or presentation property identical.

- Riverside: `969ba66a2db1d3aea7121a6e3136dd92bd38e929cec6e1b02729656970119cf1`
- Canal Watch: `e6c8ff293a17e28535f549afcc62ecfe56258195c887b10ff95f7c14d9c0e0e2`

### Where CPU time went

First instrumented run, measured interval only:

| Phase | Riverside calls / total | Busy showcase calls / total | Busy maximum call |
|---|---:|---:|---:|
| Group movement | 795 / 36.574 ms | 10,488 / 1,899.530 ms | 33.914 ms |
| Individual infantry movement | 3,600 / 297.190 ms | 20,624 / 1,790.796 ms | 13.287 ms |
| Infantry combat | 2,400 / 26.236 ms | 17,024 / 515.405 ms | 7.434 ms |
| Path queries, nested in callers | 0 during measured interval | 195 / 461.790 ms | 33.691 ms |
| Tactical director | 600 / 5.905 ms | 600 / 227.714 ms | 122.161 ms |
| Sight/fog union | 60 / 242.845 ms | 60 / 180.605 ms | 8.999 ms |
| Actor spatial rebuild | 600 / 13.687 ms | 600 / 69.003 ms | 0.647 ms |
| Classic economy tick | 600 / 30.654 ms | Not applicable | — |

Group and individual movement together occupy about 62% of instrumented showcase tick total. Riverside sight costs about 33%, with a 10.930 ms maximum call. Its economy costs about 4.1% and at most 0.412 ms per call in this small fixture. Eliminating that subsystem cannot explain away the observed movement and sight work, and these data do not bound a large classic economy.

The director's outlier includes its synchronous downstream work. Its global contact/ally scans, formation searches and flank route candidates are visible in source. The probe does not isolate exactly which branch caused the 122 ms call; assigning all of it to one AStar search would be incorrect.

Follow-up navigation instrumentation found **one weather refresh, 29.939 ms**, during the measured showcase interval, with **no grid cache miss** during that interval. Three mobility weight-layer calls occurred in the first probe. `nav_grid` clears mobility weights at a wetness bucket change, regenerates layers, then rewrites weights in every cached land grid. It does not rebuild obstacle geometry on every path request. At the end, Riverside had one cached grid and showcase three. In the separate early presentation fixture, a cache miss and weather refresh coincided in the same call (~46.5 ms); these labels overlap.

### Presentation CPU and existing native evidence

The dummy-rendered scene ran ten warmup frames and 120 measured manually advanced presentation frames at nominal 60 Hz, with a simulation tick every other frame. This is only two simulated seconds, not a wall-clock 60 FPS test. The scene was real, with automatic simulation/process disabled to avoid duplicate ticks; ordinary HUD drawing was allowed through process_frame.

First probe recorded 120 HUD `_draw` callbacks for 120 battle process calls:

| Callback | Total | Mean | p95 |
|---|---:|---:|---:|
| Battle process | 170.553 ms | 1.421 ms | 3.030 ms |
| Unit synchronization (inside process) | 162.189 ms | 1.352 ms | 2.901 ms |
| HUD draw (outside battle process) | 51.870 ms | 0.432 ms | 2.465 ms |
| Minimap drawing (inside HUD) | 23.720 ms | 0.198 ms | 2.254 ms |

Follow-up animation pose: 3,560 calls, 113.628 ms total, 0.032 ms mean / 0.071 ms p95 per group pose. This is not per frame and is nested inside synchronization. Native animation cost may differ. Dummy-renderer draw calls were zero and are **not** evidence of real draw-call reduction. The existing battle presentation timer excludes the later HUD draw callback and GPU submission/completion.

Accepted historical baseline in `docs/validation.md`: **25.091 ms frame p95**, 12.024 ms median, 12.357 ms simulation p95, 1.831 ms presentation-script p95, 1,222 final-frame draw calls; M4 Pro, GL Compatibility, VSync enabled, render cap removed, actual 2× MSAA, 1920×1080 target displayed in a 1440×900 window, 30 Hz physics. The 16.7 ms target remains missed. The separate VSync-disabled 21.635 ms result is not default pacing. The later 24.815 ms JSON is explicitly unaccepted as an isolated current-build result in validation.md. These cannot establish CPU/GPU attribution on the new mode.

## Scoped optimization candidates and tradeoffs

1. **Prioritize movement work before economy removal.** Cache conservative static terrain classification for repeated actor/sweep samples; reuse per-tick immutable candidate inputs where valid. Preserve immediate actor-index relocation and precise swept body/obstacle checks. Evidence: movement dominates the busy fixture. Any reuse must invalidate on construction/destroyed footprints, movement and changing weather. Expected benefit is less repeated script work; no measured speedup is claimed. Use the existing actor equivalence, clearance and arrival tests; do not reduce collision checks by weakening clearance.
2. **Bound non-urgent AI/path bursts.** Queue autonomous flank/formation route evaluation with deterministic per-tick budgets and retained valid current paths; leave explicit player commands responsive. Director already staggers normal decisions, but synchronous route fan-out still creates outliers. Tradeoff: delayed autonomous reactions and possibly different deterministic trajectories, requiring congestion, cover and mission tests rather than assuming hash equivalence. Path-cache keys must include footprint, mobility, terrain revision, weather band and relevant dynamic exclusions; naive endpoint-only caching is unsafe.
3. **Precompute or stage weather-weight work.** Build upcoming mobility-band weights before committing a band, then atomically expose coherent weights to navigation; avoid a 30 ms synchronous refresh on a requested route. Tradeoff: memory for extra layers and more invalidation complexity. Riverside's 144×108 grid has 15,552 cells versus 6,912 on 96×72; multiplied across radius/profile grids this matters. Arrays and AStar grids are cached, not allocated from scratch each tick. This probe did not measure long-match construction-triggered invalidation.
4. **Separate sight contact updates from cached fog work.** Reuse cached per-observer fields and update unions on observer-cell/weather/terrain changes; preserve exact contact cadence if optimizing without behavior changes. Source currently clears/rebuilds visible_cells and seen_by arrays, and cache size >=512 clears all entries. End-of-run cache sizes were only 62 / 197; a mass cache-clear stall was **not observed**. LRU or bounded incremental eviction is a candidate for longer matches, not a proven cause here.
5. **Split HUD dirtiness and cache static minimap pixels.** Static terrain colors can be rasterized once per terrain revision, then combined with fog at its existing ~0.3-second cadence. Source recreates the minimap image and reclassifies every cell each refresh. Draw HUD chrome/sidebar only when relevant state changes, while keeping selected-unit annotations, camera footprint, hover and dragging responsive. Tradeoff: separate CanvasItems/state invalidation; careless caching gives stale build legality/health. Styles and portraits already have caches; do not claim per-frame StyleBox creation.
6. **Measure animation LOD and native shadows separately.** Source already disables infantry detailed shadows above camera size 45 and uses a contact-shadow MultiMesh; close zoom restores them. A shadow-policy change occurs on threshold crossings, not a recursive mesh search every frame. Unit pose/synchronization still executes each rendered frame. Lower-rate distant pose updates with interpolation may help, but risks foot sliding and stale aim. Static batching/instancing of remaining repeated meshes and close-shadow budgets require isolated native CPU/GPU captures; 1,222 draw calls alone does not prove GPU saturation.

Other source-visible allocation sites include render-history dictionaries and member position arrays every physics tick, temporary director contact/ally/avoid arrays, path/raw/smoothing arrays, and HUD selection/line arrays. We measured phase time, not allocator samples; no allocation-specific percentage is justified. Instrumented memory grew ~1.0 MB / 3.6 MB during the tick windows, including instrumentation arrays, so it cannot establish a leak.

Runtime risks to check in the lead's isolated native comparison: actual render pixels versus window/logical pixels on high-DPI displays; default 60 FPS cap versus benchmark's uncapped mode; VSync pacing; multiple app/test instances; cold shader/import startup; camera crossing the fine-shadow threshold. A 1920×1080 target has 1.6× the pixels of 1440×900. Neither automatic 2× native scaling nor duplicate running instances was demonstrated here. Do not switch renderer or reduce resolution based on these headless numbers alone.

## Checks and unresolved criteria

- Instrumented diagnostic, uninstrumented reference and detailed follow-up completed with exit 0; final simulation-state hashes match in both scenarios.
- Actual headless `test_actor_spatial.gd`: **1,447 checks, zero failures**, on the frozen instrumented copy. This is not the full project suite.
- Initial attempts failed because of the incomplete FieldOps reference and wrapper void parsing; follow-up animation wrapper initially mixed spaces/tabs. These diagnostic-only problems were corrected in the temporary copy before the successful runs. A failed scene-load run was interrupted and produced no accepted JSON. Successful logs contain the known macOS certificate diagnostic, with no script/assertion errors.
- No gameplay optimization was implemented or benchmarked. No claim that new FieldOps, native frame p95, GPU time, input latency, a full Riverside match, larger armies, or the existing 60-second regroup acceptance now passes.
- Main retains integration docs/check.py/native benchmark ownership. Repeat representative early/late Riverside and busy-showcase measurements after the new mode is complete; include process isolation, source hashes, camera/shadow policy, actual render dimensions and population. Native frame pacing/GPU attribution and user-perceived smoothness remain open.
