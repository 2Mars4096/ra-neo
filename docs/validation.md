# Validation evidence

## Regional operations, persistence and elevation — 2026-10-25

Verified on **Godot 4.5.1.stable.official.f62fdbde1**, Linux, from regional-map commit `342a919` on `codex/regional-operations`. The integration gate passed **14/14 suites**, followed by **9/9 focused suites**; the latter repeats HUD layout and adds campaign scene flow, combat, field geometry, effects, animation, battlefield interface, HUD states and input actions. Final elevation checks were rerun after native rendering corrections. No historical full-suite or hardware-performance rerun is implied.

| Focused verification | Result |
|---|---:|
| Four external maps: physical routes, domains, forces, objectives and sea control | 2,301 checks, 0 failures |
| Facility income, connected forward arrivals, dispatch denial, naval hold and engineer foundations | 50 checks, 0 failures |
| Elevation: navigation/live movement, actual visibility/fire, aircraft, picking and grounded geometry/effects | 58 checks, 0 failures |
| Campaign disk persistence, survivors, wounds, components/hazards, reserves, refunds and failed writes | 66 checks, 0 failures |
| Actual deployment/withdrawal/reload/results/retry/reset and fresh-session resume | 47 checks, 0 failures |
| Atlas modal behavior, five-map layout, input isolation and switching | 89 checks, 0 failures |
| Existing HUD layout | 1,413 checks, 0 failures |
| Existing combat, field geometry, effects and animation | 1,079 / 280 / 224 / 580 checks, 0 failures |
| Existing battlefield interface, HUD states and input actions | 9,698 / 29 / 61 checks, 0 failures |
| Python authoring and editor service | 17 + 9 tests pass |
| Real-browser editor workflows | 7 pass, 0 page errors |
| Regional and Harbor deterministic compilers | Both `--check` commands pass |

The map suite intentionally distinguishes the pass lookout's infantry-only approach from the graded armor routes. It covers real native paths and spawn footprints, and controlled objective states establish loss of logistics benefits, dispatch denial and the simultaneous shore/sea hold. These checks are **not complete AI battles or human balance tests**.

Campaign tests use isolated save files. They exercise actual scene signals and reloads, continued casualty and vehicle damage, sea units parked inland, fire/flood progression, exactly-once purchase refunds, non-stacking ownership effects, startup resume, defeat retry, corrupt primary/backup handling and failed-write rollback. `--script` review/test scenes do not read or write a player's ordinary campaign; the integration test explicitly enables persistence with its own path. Saves restore a deployment checkpoint rather than a running tactical world.

Browser validation covers the fifth map, elevation drawing, height/ramp edits, duplicate/delete, undo/redo, referenced-objective protection and successful Preview. The editor screenshot in temporary artifacts shows an unsaved elevation sample on Windbreak Fields; the shipped agricultural map remains flat. Python validation additionally rejects nonlevel building foundations, invalid mission indices and coastal benefits without their required naval zone.

Native review used **GL Compatibility / llvmpipe software rendering at 1440 × 900**. Actual captures were inspected, exposing and correcting downward mesh winding, ramp/road clipping and false subdivision shading. The staged battlefield views explicitly reveal fog; the briefing and atlas are ordinary UI views. This establishes composition and rendering evidence, **not frame-rate acceptance**.

- [Five-operation atlas](images/regional-operations-atlas.png)
- [Complete mission briefing](images/regional-operations-briefing.png)
- [Limestone lookout elevation](images/regional-limestone-elevation.png)
- [Windbreak Fields](images/regional-windbreak-fields.png)
- [South Inlet sea-control zone](images/regional-sea-control.png)

Reproduce the targeted checks with:

```sh
python3 tools/check.py --group regional
python3 tools/check.py test_field_geometry test_combat.gd test_effects.gd test_animation.gd test_input_actions test_hud_states test_battlefield_interface test_regional_campaign_ui test_hud_layout
python3 -m unittest discover -s tools -p 'test_regional_*.py'
python3 tools/build_region_maps.py --check
python3 tools/build_harbor_map.py --check
./tools/play.sh --audio-driver Dummy --script tests/regional_operations_review.gd
./tools/play.sh --audio-driver Dummy --script tests/elevation_native_review.gd
```

The regional group now includes the campaign UI suite, so a fresh complete run selects 15 suites. Set `GODOT_BIN` to the pinned executable. The two capture scripts require a graphical display. Human pacing/balance, long-session economy, broad hardware performance, detailed suspension/foot IK and full tactical save/load remain open.

## Regional atlas and authoring — 2026-10-23

Verified on **Godot 4.5.1.stable.official.f62fdbde1**, Linux, from the renamed game's `e97e82f` baseline plus the regional implementation. This is a focused integration pass; it does not claim a rerun of every historical suite below.

| Verification | Result |
|---|---|
| Regional physics and mission gates | 1,841 checks, 0 failures |
| Regional atlas, switching and restart | 77 checks, 0 failures |
| Existing HUD layout | 1,413 checks, 0 failures |
| Existing presentation cache | 20 checks, 0 failures |
| Field operations, scenario dimensions, road network, Harbor gameplay, Harbor visuals, field victory, large terrain | All 7 affected suites pass, 0 failures |
| Python authoring validation | 11 tests pass |
| Python editor API and file-write behavior | 9 tests pass |
| Real-browser editor workflows | 9 workflows pass, 0 browser errors |
| Harbor and regional deterministic output | Both compiler `--check` commands pass |

Regional physics checks use all three compiled maps. They verify exact initial and reserve force counts, legal unit footprints, infantry and tracked routes from both insertion areas to every objective, boat approaches on South Inlet, rejected inland boat purchases, ridge movement/sight blocking, shared building rendering, and isolated ground configuration when returning to Harbor. Tracked-route checks apply the existing crushable-furniture rule; collision tolerances were not relaxed to make the maps pass. Controlled infantry capture tests exercise incomplete progress, ownership, reserve grace, the full 60-second hold requirement, eventual victory and no repeated reserve deployment. **These mission checks are state-based regressions, not full human or AI battle playthroughs.**

The UI suite exercises the actual scene transition from Harbor to Limestone Pass and restart on the selected battlefield, alongside retained simulation/pause state while browsing, protected live switching, missing-map handling, input isolation, zoom/pan and 1120 × 720, 1440 × 900 and 1920 × 1080 layouts. Mission guidance was corrected after native review found that the new maps were being told to destroy nonexistent logistics posts.

The editor was run against temporary copies of the blueprints and compiled outputs using the real Python backend and Playwright with Chrome for Testing 131. The browser review loaded all three maps, refreshed the session, cancelled an unfinished drag, dragged a road vertex with undo/redo, rejected an invalid objective without writing, previewed without saving, saved and reloaded both outputs, rejected an external-edit conflict and checked a smaller desktop layout. API tests separately cover unauthorized requests, invalid/nonfinite JSON, path restrictions, validation failure, conflicting revisions and rollback after a simulated output-write failure. User project maps were not changed by browser save tests.

Native Godot captures use **GL Compatibility / llvmpipe software rendering**. Nine battlefield views (overview, medium, detail for each map) were captured and inspected, plus the atlas. The selected composition images deliberately reveal fog and label that state; they are not normal starting visibility. The editor image is an actual browser capture. Evidence:

- [Regional atlas](images/regional-atlas.png)
- [Map editor](images/regional-editor.png)
- [Bayhead Rail Valley](images/regional-rail-valley.png)
- [Limestone Pass](images/regional-limestone-pass.png)
- [South Inlet](images/regional-south-inlet.png)

Reproduce the functional and authoring gates with:

```sh
python3 tools/check.py --group regional
python3 -m unittest discover -s tools -p 'test_regional_*.py'
python3 tools/build_region_maps.py --check
python3 tools/build_harbor_map.py --check
```

Set `GODOT_BIN` to the 4.5.1 executable if it is not on the path. `tests/regional_native_review.gd` and `tests/regional_ui_review.gd` capture the real game with a graphical display; the authoring tool needs Python 3 and a desktop browser. The regional suites are also included in the default discovery and release selection.

No frame-rate, full-combat balance or supported-hardware acceptance was claimed for the October 23 increment. At that point ground remained planar and the atlas only selected operations; the October 25 entry above records the later elevation and campaign work. Railcars remain static. The [regional guide](regional-map.md) records the compressed geography and source attribution; prior performance findings below remain historical and unresolved where marked.

## Integrated team revamp — 2026-10-14

- Full **27 suites pass** after shared roads and mobility profiles. HUD: 1,080 layout checks; zoom: 11; road graph: 34,812; mobility: 22; routing: 9. Showcase/Classic scripted victories pass. After final foliage and shadow-only changes, focused render-interpolation/shadow restoration passes and clearance passes **135,780 checks**.
- Native actual gameplay captures in artifacts/revamp-{tactical,classic,detail-3,detail-4}.png; comparisons against all three generated targets in artifacts/revamp-review.html. These are scene reviews, not human gameplay acceptance. Current scene does not meet reference fidelity; sparse frontage, repeated proportions, vegetation/ground layers and lighting remain gaps. Sidebar is an inferred direction, not approved by the references (which have no HUD).
- Final isolated rainy 1080p / 100-member / 35-group benchmark on M4 Pro: median **18.431 ms**, p95 **24.673 ms**, simulation p95 **11.585 ms**, **2,194 draw calls**, uncapped rendering / 30Hz physics. Target16.7ms remains unmet. Pre-revamp p95 was24.835ms with3,994 draw calls. The draw reduction is clear; frame-time improvement is not stable enough to claim smoothness fixed.
- Intermediate integrated run before shadow detail: p95 25.905ms /3,997 calls. Shadow-detail trial: p9520.002ms /2,219 calls; final repeat24.673ms /2,194calls shows variability. Do not cherry-pick the faster sample. Normal play has60FPS cap; these benchmarks explicitly disable it. No measured CPU/GPU utilization, memory or thousands-entity capacity claim.
- Mobility multipliers are gameplay assumptions. Physical footprint/domain govern accessibility; individual soldier passage test does not mean whole squads automatically form columns. No bridge capacity, slope/traction simulation, traffic or general procedural town generator.

## 2026-10-14 — Diorama materials

Native scene renders compile and show the revised surfaces. Clearance: 126,928 checks, zero failures. Latest rainy Canal Watch 100-entity/35-group benchmark at 1920×1080, M4 Pro, Compatibility: frame p50 13.55 ms, p95 **24.12 ms**, simulation p95 10.627 ms. Target 16.7 ms remains unmet; preceding run was 22.042 ms. 20-second window with 2-second warmup. No full behavior rerun: changes are shaders, color and facade trim.


## 2026-10-14 — Individual shelter correction

- Full runner: 21 suites pass. Unchanged classic policy wins at 538.1 simulated seconds with three friendly structures surviving.
- Cover fixture: individual travel reaches 9.51 game units; independent arrival, separation, scenery clearance, staggered seeking, order cancellation and unseen-contact behavior pass. Additional shelter-retention regression passes.
- Native before/during/after frames: `artifacts/cover-0.png`, `cover-30.png`, `cover-120.png`. Controlled enemy firing cooldown isolates movement; this is not human play acceptance.
- Rainy Canal Watch benchmark, M4 Pro, Godot 4.5.1 Compatibility, 1920×1080 render, 100 friendly entities/35 groups: frame p50 11.344 ms, p95 **22.042 ms**; simulation p95 11.072 ms, 3,888 draw calls. 20 seconds with 2-second warmup. Target 16.7 ms remains unmet; this pass does not demonstrate scalability to thousands.
- New individual shelter routes are limited to Canal Watch and Frontier Skirmish. No peeking, crawling, vaulting or interior navigation claim.


Coastal Spear is a runnable tactical MVP with original stylized military equipment. It is not a production-quality AAA release. Automated playthroughs and rendered inspection establish the checks below; human playtesting remains open.

## Current release: classic skirmish, showcase and scaling foundation

All **20 suites pass** on Godot 4.5.1. Classic checks cover harvest delivery, placement rejection, construction, prerequisite enforcement, queues/refunds, power slowdown/recovery, bounded deployment, structure destruction, new model footprints and actual viewport input. The ordinary-command skirmish policy wins at **554 simulated seconds**, with 23 kills, 15 losses and three own structures remaining. Earlier policies lost or stalled; this is one regression policy, not a balance or enjoyment certification. The existing 35-credit player kill reward remains in this prototype.

Canal Watch wins at **189.3 seconds**, exercising nine flanks, 30 support decisions and two withdrawals, with its capture-triggered counterattack. Original scenario victories are 104.6 / 118.8 / 122.2 seconds. Clearance: **126,928 checks**, zero failures; minimum sampled margin 0.0801667. Motion: 4,301 checks; the smallest sampled height is −0.0000000894 from floating-point rounding. These checks do not prove every possible crowd configuration safe.

Weather, articulated crouch/prone/rise, knee/ankle poses, varied building forms/materials, and the skirmish controls received native rendered inspection. [Skirmish](../artifacts/classic.png), [stance study](../artifacts/stances.png), [equipment](../artifacts/equipment-study.png). Staged screenshot FPS counters are not performance measurements. Human art, control and enjoyment acceptance remains open; assets remain procedural prototype work.

### Optimization evidence and limits

Spatial combat/sight candidates and indexed unit lookup replace repeated whole-list work. Seeded A/B runs compare targeting, health, position, RNG state, visibility and explored fog with the exhaustive reference. Small scenes retain simple scans below 64 group records to avoid query overhead.

Synthetic range-query p95, microseconds, 100 queries per size:

| Records | Exhaustive | Spatial | Average returned candidates |
|---|---:|---:|---:|
| 250 | 66 | 42 | 10.86 |
| 500 | 128 | 46 | 11.76 |
| 1,000 | 259 | 46 | 12.36 |
| 2,000 | 521 | 50 | 12.66 |

These are synthetic spatial-query measurements on a dispersed layout, **not thousands of troops simulated or rendered in a battle**. They exclude index rebuild, pathfinding, actor AI and rendering. Dense gatherings can return much larger candidate sets. [Raw query report](../artifacts/spatial-scaling.json).

Latest native rainy-showcase benchmark on Apple M4 Pro: actual **1920×1080** render target, 1440×900 window, 35 groups / 100 friendly entities; frame median **14.807 ms**, frame p95 **21.724 ms**, simulation p95 **7.953 ms**, 1,147 rendered frames and 541 simulation samples, 3,888 draw calls. Twenty-second run, two-second warmup excluded. The prior same-scene p95 was 20.954 ms; this sample establishes **no frame-rate improvement**. It still misses 16.7 ms. The query optimization targets larger populations; rendering/animation and remaining global scans require further work. No full classic-match performance or thousand-entity capacity claim is made. [Raw benchmark](../artifacts/benchmark.json).

The current world remains 96 × 72 simulation units. [Town-scale plan](plans/9-town-scale-performance.md) tracks scenario-sized terrain, navigation, rendering detail, budgeted decisions and full-battle validation. Earlier results below are historical builds.

## Vehicle stability, map identity, and miniature art pass

All 11 behavior/layout suites passed after the tank and map changes. Added regression: a valid target remains locked as another moves closer, target death releases the lock, and the chassis has zero artificial vertical bob over 90 pose samples. All three revised maps complete: Coast 97.6s, Fields 115.8s, Urban 122.2s. The user's still image cannot establish which source dominated the reported shaking; normal gameplay review remains valuable.

After introducing the miniature paint material, geometry/clearance was checked again: 126,888 checks, no failures, minimum sampled margin 0.0801667. Native equipment and three terrain renders compile cleanly and were inspected. [Equipment](../artifacts/equipment-study.png), [Fields](../artifacts/scenario-1.png), [Urban](../artifacts/scenario-2.png). Terrain views deliberately reveal the map for art review.

Latest 1080p stress run on Apple M4 Pro: frame median 10.435 ms, frame p95 **21.644 ms**, simulation p95 9.591 ms; 1,563 rendered frames, 544 simulation samples, 19.7 simulated seconds, 35 groups / 98 living friendly entities, 2,027 draw calls. The 16.7 ms target remains unmet. This sample does not isolate shader cost from simulation/host scheduling effects. Earlier performance numbers below belong to earlier builds.

## Latest combat and communications pass

All ten suites pass on Godot 4.5.1. Combat/communications: 1,064 checks; simulation: 41; input: 21; geometry/clearance: 135,171 (minimum margin 0.0800359); effects: 6; tactics: 15; animation: 508; individuals: 1,807; baseline mission and all three scenarios complete. The actor fixture now uses an infantry target because rifles correctly refuse armored hulls. A separate EW fixture moves both group and actor positions to preserve physical range checks.

In the seeded 1,000-attempt moving-UAV sample, 74 rifle shots hit. Every hit disables the UAV and every miss preserves HP. This verifies the configured game rules, not empirical accuracy. Immunity, command rejection, retained orders, disconnected local defense, suppressed reconnaissance uploads, and restoration on capture are covered.

Unchanged-policy victories: Coast 78.7 seconds, Fields 77.3, Urban 114.0. The urban route previously stalled for the entire 480-second test; throttled body-aware detours resolve that case. These short matches still do not demonstrate long-term strategic depth.

[Native UI review](../artifacts/combat-relationships.png) shows the added AA button, link status, and interference footprint. Final stress run: actual 1920×1080 on Apple M4 Pro; median 10.257 ms, frame p95 **17.747 ms**, simulation p95 **8.753 ms**; 1,552 rendered samples, 540 simulation samples, 19.6 simulated seconds, 35 groups and 98 living friendly entities. This **misses** the provisional 16.7 ms frame target. Removing hot-loop dictionary copies reduced simulation p95 from 10.001 ms in the first pass; that earlier pass also emitted an exit-time ObjectDB leak warning, absent in the final run. Further profiling remains open. Historical measurements below refer to earlier builds.

## Latest animation / individual-entity / scenario pass

All nine suites pass: simulation 41 checks; viewport input 21; group geometry/clearance 125,600; effects 6; tactics 15; animation/timing/terrain 508; individual actors 1,007; baseline playthrough; and all three scenario playthroughs. Minimum group clearance margin is 0.0800268 world units. Individual tests cover asynchronous shots, localized casualties, survivor-only recovery, separation, terrain clearance, and arrival. Animated tests sample articulation and hit reactions; they do not prove every possible mesh intersection absent.

Scripted victories: Coastal Spear 86.4 seconds, Harvest Line 73.4 seconds, Iron District 127.0 seconds. These use the same basic policy and remain much shorter than the proposed richer match. Scenario layouts and the briefing selector were rendered and inspected. [Motion sample](../artifacts/motion-12.png) shows the articulated models; the live game is needed to judge timing. [Scenario reports](../artifacts/scenarios.json) record outcomes. Terrain survey images intentionally reveal the map and are authoring views.

Latest active-simulation 1080p benchmark: frame median **10.628 ms**, frame p95 **16.384 ms**, simulation p95 **8.016 ms**, 1,648 rendered samples and 547 simulation samples over 19.8 simulated seconds. Final frame: 2,114 draw calls, 35 group records, 95 living friendly entities counted from individual soldier HP. This local Apple M4 Pro sample narrowly meets the 16.7 ms provisional frame target; it establishes little headroom and is not a cross-platform claim. Older numbers below are historical. The authoritative latest data is [benchmark.json](../artifacts/benchmark.json).

## Latest tactical increment

All six suites pass after retreat/recovery and opponent-response changes: simulation 41, viewport input 19, geometry/clearance 95,828, effects 4, tactical behavior 15. The ordinary-command mission wins in 75.1 simulated seconds with 6 kills and 4 losses. Minimum sampled clearance margin is 0.0800695. Updated rendered command feedback was inspected. Historical performance figures below belong to the previous MVP, not a fresh benchmark of this behavior change. The short scripted win remains a design limitation.

## Initial MVP regressions

`python3 tools/check.py` passes on Godot 4.5.1:

| Suite | Result |
|---|---|
| Simulation | 41 checks, zero failures |
| Viewport controls and restart | 18 checks, zero failures |
| Model geometry, deployment, dense movement, redirection, naval passage | 94,801 checks, zero failures |
| Effects pool, delayed smoke, expiry/reuse | 4 checks, zero failures |
| Complete mission through ordinary commands/purchases | Victory at 65 simulated seconds, 7 kills, 3 losses |

The minimum sampled body-separation margin was 0.08023 world units. Each equipment type preserves its authored triangle count after batching and fits its conservative footprint. These tests do not prove that every possible crowd arrangement is free of clipping or deadlock. See [known limitations](bugs.md).

Raw reports: [checks](../artifacts/checks.json), [clearance](../artifacts/clearance.json), [mission](../artifacts/playthrough.json).

## Render review

Inspected the [equipment study](../artifacts/equipment-study.png), [battlefield](../artifacts/combat.png), and [effects](../artifacts/effects.png). The automated review also captures [briefing](../artifacts/briefing.png), [orders](../artifacts/orders.png), [victory](../artifacts/victory.png), and [defeat](../artifacts/defeat.png). The effects image stages a shot/explosion to inspect timing and visibility; it is not a separate gameplay outcome. Short capture scripts advance simulation between renders, so their on-screen FPS counter is not a benchmark.

Close-up review caught missing custom hull surfaces caused by mixing indexed and unindexed meshes in batches. Normalizing topology restored hulls and industrial roofs, and seven triangle-preservation regressions now guard the fix.

## Performance

The benchmark uses the installed Godot editor binary, GL Compatibility renderer, Apple M4 Pro, an actual 1920×1080 render target displayed in a 1440×900 window, and a 20-second run with the first two seconds excluded. It measures monotonic wall-clock intervals between rendered process frames. The report records 35 groups and approximately 96 visible friendly members; units move and fight, so population changes during the sample. This is a local sample, not a supported-hardware guarantee or long-duration soak test.

| Final metric | Result |
|---|---|
| Rendered frame median / p95 | 6.868 / 14.130 ms |
| Simulation p95 | 11.364 ms |
| Sampled frames | 2,595 |
| Final-frame draw calls | 377 |

Frame p95 met the provisional 16.7 ms target in this run. Simulation p95 remains a scaling concern; this sample does not establish headroom for larger armies. Final measurements are recorded in [benchmark.json](../artifacts/benchmark.json). The earlier detailed-model run measured 19.433 ms frame p95 and 973 draw calls. Merging painted parts and using local movement-neighbor buckets reduced rendering and avoidance work.

The [input timing report](../artifacts/input-latency.json) measures ten synthetic viewport right-clicks to the next completed render, with five sections selected and navigation grids warmed. The latest p95 was 101.229 ms (nine of ten samples were at most 32.943 ms), narrowly above the provisional 100 ms target. This small sample was captured while headless regressions also ran, so it includes host contention; retain the shortfall rather than claiming a clean latency pass. It excludes physical mouse/display latency and is separate from path completion time.

## Remaining validation

Human assessment of authenticity, command clarity, difficulty, congested movement, and enjoyment; larger battles; other GPUs/platforms; standalone exports; prolonged sessions. Headless macOS checks emit an unrelated system-certificate diagnostic in the restricted CLI environment; no script errors or assertion failures occurred. Native graphics reviews complete without that diagnostic.

## 2026-10-14 — Texture and road-context correction
30 regression suites passed after integrating gap fallback, static cars/lamps and sampled material sources. Follow-up material batching check passes after palette calibration. Native captures: artifacts/revamp-detail-3.png, revamp-detail-4.png, equipment-study.png. Review: artifacts/material-review.html. Gap regression: 2,746 checks. Roadside footprint/access regression: 21,639 checks. Full-body clearance regression remains passing.

Compared the actual renders with all A/B/C references and the user-supplied damaged-town image. Textures/palette and road context changed, but full reference fidelity is not achieved. Remaining: repeated building masses, sparse gardens/service yards, simplified character/equipment geometry, authored UV-specific wear. No AAA or low-resource claim.

Final integrated 100-member rainy benchmark: Apple M4 Pro, 1920×1080 target, uncapped GL Compatibility, 27.103 ms median / 36.061 ms frame p95, 22.665 ms simulation p95, 2,213 draw calls. Prior runs varied 24.296–32.124 ms; target remains missed and the final measurement is a regression versus the previous 24.673 ms. No claim of smoothness or improvement from materials.

## 2026-10-14 — Profiled refinement delivery
32 suites pass, including actor-index equivalence (1,447 checks) and architectural parcel bounds (135,920 vertex checks); follow-up shadow interpolation and encoded material checks pass.

CPU-only same600-tick workload:10.209→5.272seconds, simulation p9523.143→12.689ms; full final unit/member state hash identical. See artifacts/simulation-profile-comparison.json.

Final default-display GL benchmark:25.091ms frame p95,12.024ms median,12.357ms simulation p95,1.831ms presentation-script p95;1,222 draw calls. 1920×1080 target,1440×900 window, M4Pro,100 initial members/99 surviving,30Hz physics, VSync enabled, render cap removed, actual2×MSAA. Startup now excluded before a20s run with first2s discarded; the previous36.061ms record used the earlier startup window, so avoid claiming a strict frame-time percentage improvement.16.7ms target still unmet.

Separate VSync-disabled diagnostic:21.635ms frame p95; not default pacing. Engine static allocation counter72.21MB, texture memory counter63.30MB; these are separate Godot counters, not total resident memory or whole-machine resource usage. Monitor definitions: [Godot performance monitors](https://docs.godotengine.org/en/4.5/classes/class_performance.html).

Metal Mobile evaluation did not reliably meet target (warm28.152ms frame p95), so default remains GL Compatibility. Cold Metal result with95physics samples rejected because startup compilation dominated the window.

Independent Codex visual review: material normalization, quiet cloth and varied rooflines improved; full reference alignment still partial due simplified equipment/characters/vegetation and insufficient connected urban context. Claude Code via normal and Diane host launcher returned Not logged in; cross-model acceptance remains blocked.

## Asset-library integration — 2026-10-14

-100 callable assets across10 categories,72 new variants plus28 existing adapters/variants; all100 measured/native-rendered with no missing individual preview. See `artifacts/asset-library.html`, `asset-manifest.json`, `asset-capture.json` and `asset-library-checks.json`.
- Actual50-suite `tools/check.py` run:49 pass; `test_regroup_recovery.gd` retains one failed60s arrival assertion (67.10s observed). Do not report a clean game regression run. All other asset, classic mission, collision, input and scenario suites pass.
- Native gallery callbacks (filter/page/inspect/rotate/back) pass headlessly; native cards/working faces were inspected. Rendering is cached per preview until geometry/view changes. No native FPS benefit inferred from that design.
- The24.815ms Canal Watch frame-p95 diagnostic in `benchmark-riverside-integration-4-member.json` predates the three-member change and may overlap worker testing. It is not accepted as an isolated current-build performance result. Full current-battle smoothness and km²/large-force capacity remain unvalidated.
