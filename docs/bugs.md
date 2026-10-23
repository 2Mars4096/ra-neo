# Bugs and failed approaches

## Known limitations

- Release tooling is incomplete in the current source checkout (confirmed during the 2026-10-23 rename): `tools/export_release.py` references absent `export_presets.cfg`, `resources/build_info.json`, and `docs/playtest-readme.txt`. The staging/export path and build-version-dependent release tests require those inputs; changing the release filenames does not establish standalone-export readiness.

- Harbor physical wall profiles currently cover 381 of 478 buildings. The remaining 97 custom/compound buildings retain conservative parcel collision; their courtyard/gateway geometry needs a separate compound-profile pass. Garrison window posts still use merged building bounds for every family, so rotated buildings and bounds including low pieces remain approximate. A parked vehicle can still obstruct a local shelter approach, causing bounded retries instead of a vehicle-aware long detour. Existing crowd and local-path limits still apply.

- The physical-cover pass does not complete performance acceptance. The unchanged cover-search benchmark still exceeds its 25 ms limit at two contact locations (one on the original baseline). The slow `(500,680)` case improved from the initial 89.5 ms regression to 29.1 ms, but its final paired original baseline is 17.3 ms. Overall warm peaks are 28.6/29.1 ms and total benchmark process times are 16.82/21.24 s before/after; see [the measured comparison](plans/14-1-cover-contact.md#performance-review). Full-battle rendered performance remains a separate open gate.

- Combat values are fictional abstractions, not ballistic measurements. Vehicle component damage (`vehicle_damage.gd`: facing/range penetration, mobility/firepower/crew/catastrophic), infantry wound states with HE fragment radius (`infantry.gd`), HE structure damage (`structure_damage.gd`) and FPV/crash blast radii now exist, but their armour, penetration and outcome numbers are not ballistic data. No ammo selection, physical projectile interception, or validated probabilities. UAV one-hit disable applies only to the small recon class.
- Interference uses a scenario-defined radius, not radio propagation. No player-deployed jammers, relay network, frequency/equipment modeling, or UAV return/land failsafe. Friendly tracking remains visible.

- The original tactical missions remain short under scripted policies. Canal Watch adds a counterattack and autonomy; classic skirmish adds production/economy, but supply networks and a broader strategic planner are still absent. Enemy tactical repairs currently have no resource budget.

- Four public battlefields share the Black Sea Coast atlas: Black Sea Harbor, Bayhead Rail Valley, Limestone Pass and South Inlet. Six earlier configurations remain hidden fixtures; the catalog has ten entries while the legacy seven-entry file and its indices stay unchanged. The atlas loads separate operations, with no seamless streaming, cross-map force transfer, campaign, save/load, multiplayer or standalone export packaging. Switching away from a live battle discards its progress after confirmation.
- Regional geography is compressed and fictional, informed by historic coast/valley/settlement references. Atlas connections are selection-map geography, not simulated travel or a current infrastructure survey. Traversable ground remains planar; the pass's low solid rock ridges create barriers and sight constraints without climbable slopes, elevation advantages or high terrain. Rails are static traversable meshes and parked trains are solid scenery; moving rail traffic, bridges and tunnels remain unimplemented.
- The visual editor currently covers the three new battlefield blueprints. Atlas metadata and the original Harbor generator workflow remain separate. Editor placement/connectivity checks are conservative authoring checks, not substitutes for runtime physics tests or human balance review. Source and compiled files are replaced atomically one at a time, with I/O rollback; interruption between replacements can require rebuilding the derived map from its blueprint.
- Squad formations use conservative circular envelopes and local avoidance. This sacrifices tight formations and can cause yielding in congested areas; arbitrary crowd deadlocks are not exhaustively tested.
- Infantry have individual combat/health/position records and procedural articulation, but share squad routing and stable formation slots. The showcase adds local cover selection and procedural flat-ground foot placement; independent long-range paths, uneven-ground foot IK and skeletal animation remain unimplemented.
- Flight uses fixed altitude bands; no takeoff, landing, terrain following, or projectile ballistics.
- Art is original procedural geometry, not photorealistic production assets. Model polish, animation, terrain variety, and human usability review remain future work.
- Fog updates at 0.3-second intervals and uses a coarse terrain field. Terrain architecture is known; enemy unit visibility is restricted.
- macOS headless runs in the restricted CLI environment emit `get_system_ca_certificates` diagnostics. Tests are local, do not use TLS, and the graphics-host runs do not emit that diagnostic.

## Classic skirmish limitations and resolved defects

- First classic mode has HQ, power, refinery, barracks, factory and harvesters. Air/naval production, research, defensive structures, selling, repair commands and HQ rebuilding are not implemented. Destroyed producer queues are lost; cancellation of a living producer refunds the last queued item. Exhausted deposits do not regenerate. The legacy 35-credit player combat bounty remains; economy balance and symmetry need human playtesting.
- Initial fixed enemy building sites could be blocked; search legal nearby sites and reserve infrastructure spending. Count queued harvesters before buying replacements.
- Restrict production exits to the immediate producer area; occupied exits wait rather than falling back to distant spawn positions.
- Congestion exposed an AStar start-cell center lying inside a neighboring body's footprint. Choose a reachable clear start center when rerouting, include individual actors as obstacles, and allow attack orders to reach the detour branch.
- Scripted combat must protect the economy and scout enemy structures. A stationary base-only policy can lose; passing one policy is not balance certification.

## Showcase limitations and resolved defects

- Firing postures are procedural: crouch/aim, reload, pinned prone and rise. Prone requires open footprint clearance; crowded actors stay crouched. Garrisoned buildings (`garrison.gd`), HE-worn sandbags and destructible field works (`structure_damage.gd`) and SEVERE-casualty crawling now exist. No tactical crawling, vaulting or directional cover penetration yet.
- Visual review of the articulated leg solve exposed swapped left/right foot offsets. Corrected the orthogonal-vector sign and added a settled-foot-side regression.


- Broad autonomy currently covers land command groups. Aircraft and ships retain existing movement/support rules. Player review of autonomy clarity and the overall art direction remains open.
- Passing weather is authored and deterministic. No meteorology, elevation, erosion, flooding, physical radio propagation or weather-dependent flight failures.
- A first showcase playthrough stalled at zero-distance maneuver waypoints. Consume arrived waypoints before braking, bound support waits, and avoid repeatedly replacing identical orders in the playthrough fixture.
- The first foot-contact revision tilted boot soles below the plane. Correct the sole offset; focused mesh checks now include every animated frame.
- Weather HUD text overlapped an objective card during rendered review; move it to the free header region.
- A building-detail loop needed an explicit float type in GDScript. Fixed the parse error and reran checks before release.

## Resolved during implementation

### 2026-10-23 — Regional map integration

- Direct legacy-JSON readers and Harbor-ID checks could select the wrong scenery for an external battlefield. `ScenarioCatalog` now preserves legacy indices, adds lightweight regional descriptors and lazily resolves the selected map. Simulation passes that complete configuration to Terrain, and shared city rendering, environment details and ground land-use masks read it.
- Caching external maps for the entire process hid editor saves on redeployment. Each new simulation now rereads only its selected external map, while catalog metadata and legacy fixtures stay cached. Returned configuration copies prevent fixture changes from contaminating another battle.
- Inland operations exposed naval reinforcements that could not spawn on their terrain. Both the HUD choices and purchase validation now honor `available_domains`; Limestone Pass offers land/air forces only.
- Harbor-specific mission widgets omitted goals on new maps, and shared text proposed destroying posts/depots that those maps did not contain. Compiled field operations now display their own mission state, and optional logistics guidance requires authored logistics; other maps show applicable reserve/hold advice.
- Regional browsing now preserves the active simulation and prior pause/render state, blocks gameplay input under the atlas and confirms progress loss before a different operation starts. The live-battle selector uses the same confirmation path; choosing the current field returns without a reload. Missing external map files disable deployment. Native atlas review also caught and corrected a selected-footprint caption overlapping a settlement label.
- Editor review found three state-consistency defects: refresh lost the session token after its URL fragment was removed, cancelling/changing tools during a drag could lose its undo snapshot, and source text/revision could come from different reads. The editor retains its local session token, handles active drags explicitly and hashes the loaded source snapshot. Save validates compiled output and rejects stale source revisions before and after compilation.

These changes reuse the established collision, mobility, visibility and combat rules. Regional validation and native review are recorded in [16: Regional map](plans/16-regional-map.md); existing physics, congestion and performance issues below remain open.

### 2026-10-20 — Physical cover contact

- Sandbag face goals used a 0.85-unit gap, smaller than the standing body's required 0.92-unit clearance. They are now 0.95 units outside the rectangular footprint, including the shared terrain margin.
- Field works were already terrain rectangles but also acted as circular obstacles in slot reservation, actor clearance and avoidance. A real flank runner stalled more than 28 seconds at a terrain-valid waypoint inside the extra circle. Static field works now use their exact terrain geometry; mobile vehicles and soldier bodies retain their collision checks.
- Quiet occupants bypassed failed-route and geometry validation. Naturally sheltered soldiers remained marked sheltered after trench destruction. Both quiet and combat shelter now validate the goal, actual settled protection, leash and approach deadline; clearing also resets stale timers. Partial recovery preserves valid squadmates.
- Restoring partial recovery exposed impossible 1.4-spaced trench goals between bodies requiring 1.55 separation. Centered 1.65-spaced goals fix the actual fit. Individual work goals and route waypoints must also fit the 10-unit leash; otherwise a cleared goal could be reassigned every cover scan.
- Work reservation previously rejected only identical destinations within one section. Distinct slots on contiguous works could be too close, and a second section could reserve a first section's occupied trench slots. Work occupation now preserves spatial separation from all nearby friendly active shelter goals.
- Building colliders used full placement parcels around inset visible walls. Shared ground-body profiles correct supported families without enlarging meshes or moving buildings. Low steps/docks remain movement obstacles but do not grant a wall halo or stop ground shots. Tightening global placement tolerance was avoided because it would change city yaw/layout; body emission has its own tolerance and cache.
- Precise Harbor geometry exposed a coarse-grid infantry shortcut that grazed a wall by about 0.07 units between samples. Coarse-map published routes now use the existing corner guard; the original `test_large_terrain` footprint assertions pass without loosening them. Fine-grid legacy route behavior is retained.
- More precise wall pieces increased false candidates in the original 32-unit obstacle buckets. Narrow movement, cover and sight queries now use a conservative fine index; wide candidate enumeration retains its original order. LOS validates index freshness once per sampled line, and land traversal rejects solid interiors before checking the coastline. Both indexes are maintained during collapse, crushing and rebuilds. Geometry predicates and timing thresholds are unchanged; measured results are in the cover-contact plan.
- Older tests equated one collision rectangle with one building and placed an allegedly uncovered soldier inside a building. Fixtures now check physical body/transform and actual clear ground. The regroup snapshot also caught a medic legitimately finishing eight seconds of aid at the 60-second boundary; the test now verifies the actual pairing and requires treatment plus reunion within its unchanged 12-second bound. Movement and damage assertions remain intact.

See [14-1: Soldiers reach physical cover](plans/14-1-cover-contact.md) for negative controls, native measurements and verification scope.

- Reported tank shaking: removed flat-ground chassis bob, limited rendered hull yaw, retained valid combat targets, and penalized avoidance heading reversals. Static user evidence cannot establish which contributor dominated; dedicated stability checks cover bob and target retention.
- Scenario variations originally reused the ridge/warehouse composition and fixed objectives. Replace Fields/Urban ground layouts, building styles, and objective positions; shoreline and dimensions still remain shared.

- Revised combat exposed an industrial approach deadlock under the unchanged scripted policy. Add throttled body-aware route recalculation, preserving footprint and swept checks.
- Group target selection previously retained the AT launcher range/capability after its operator died. Evaluate surviving members at their actual positions and with their own weapon.
- A local-defense test moved a squad center without moving its actors. Move the test actors too; do not bypass per-soldier range checks.

- Incoming-fire lean initially rotated the entire soldier around the group origin and dipped a foot below ground. Apply lean to the upper body; animated-ground checks cover hit reactions.
- Rotating individual formation slots during turns caused soldiers to exchange places and block one another. Keep assigned world-axis slots stable and rotate actors independently; arrival/separation tests guard this.
- A legacy open-ground damage fixture fell inside the new ruins. Move the fixture and its individual soldiers to genuinely open terrain.
- An animation benchmark recorded no active simulation samples, so its frame figure was not accepted as a gameplay result. Ignore input during benchmarks and record simulated time/sample count.


- Mixing indexed primitive meshes and unindexed authored shells in a render batch dropped hull/roof triangles. Normalize every mesh to indexed topology before merging; triangle-count regression checks cover all equipment types. This was found in close-up render review despite passing footprint bounds tests.

- Ground mesh initially culled from above: corrected material culling and verified renders.
- Initial camera hid starting units beneath the command deck: reframed and later angled the camera; updated screen-space selection tests.
- Model parts submitted separately and minimap tiles redrawn individually: merged rigid geometry, instanced vegetation, cached minimap, then merged equipment paint using vertex colors.
- Visibility recomputation and full-array movement checks were too costly: cached static visibility fields and added spatial buckets for local avoidance.
- Center-only routing allowed geometry intersections: introduced full-footprint paths, swept movement, spawn/formation clearance, and mesh-bound tests.
- Initial drone/corvette radii missed rotor/gun extremities: increased bounds and verified actual vertices, including nested rotor geometry.
- Objective poles and pier geometry needed collision coverage: added shared static constraints and accessible capture destinations.
- Aircraft could meet the height of tall objective props: raised and separated UAV/helicopter bands.
- Enemy presence did not stop final hold progress: final extraction now requires both sectors uncontested by enemies.
- Naval explicit attacks needed a land-target approach point: choose a reachable coastal firing position.
- Explosions showed smoke before the initial flash: smoke has delayed birth and a bounded fade.
- Range circles crossed the header: world annotations now draw beneath the opaque command panels.
- Synthetic input tests initially used the default script viewport size and buffered input delivery: set viewport size explicitly and inject viewport-local events.
- Test code encountered GDScript inference errors with Variant-valued loop variables: replaced ambiguous inferred types with explicit types; check wrapper rejects script errors even with exit code zero.
- Short screenshot runs left synthetic audio playbacks active at exit: render reviews mute audio and effect cleanup stops/releases playback streams.

Keep these records when changing the affected systems; do not revive center-only collision or assume requested window size equals render resolution.

## 2026-10-14 — Shelter visibility correction
- Old cover search sampled only 3.6 units and required a direct unobstructed segment; it frequently missed thin wall bands. Replaced with wall samples, local routes and a 10-unit leash in autonomy scenarios.
- Initial cover implementation expired occupied shelter every eight seconds, causing reselection; retaining valid occupied shelters restored classic regression victory.
- Shelter can block the soldier’s own shot. Peeking and full directional damage cover remain unimplemented. Original three scenarios retain old rules.
- Manual paused render fixtures must explicitly advance animation poses after simulation ticks; otherwise screenshots show stale actor positions.

## Diorama material review
- Initial masonry mask was too frequent/high-contrast at gameplay zoom. Raised exposure threshold and reduced plaster/brick contrast after native review.
- Materials remain procedural; intact box-shaped building volumes, simple vegetation and limited scenery families still constrain reference fidelity.

## Scene color experiment
- Applying sRGB-to-linear conversion globally to baked vertex colors made soldiers and trim too dark in native review. Reverted the global change; only the new pale road surface receives a localized color correction. Do not repeat a global conversion without comparing all material families.

## Revamp integration
- A third additional parcel near (46,23) crowded the showcase approach and caused the scripted mission to time out. Removed it; two peripheral additions passed a 299.9s victory before road rework. More scenery is not automatically better level design.
- New camera smoothing requires paused screenshot fixtures to set both camera_size and camera_zoom_target; otherwise the camera drifts back before capture. Fixtures corrected.
- The original road scheme was duplicated in terrain, shader and detail meshes. Direct-line path shortcuts also erased weighted road detours. Shared road-data and travel-cost checks replace those inconsistencies in the next integrated validation.

- New shadow-detail metadata initially used get_meta with a null default, which Godot treats as missing metadata and logs an error. Guard with has_meta before reading; focused interpolation/shadow checks pass.

## 2026-10-14: shaded-gap order rejection and texture import
The five-unit Canal village gap cannot contain a 5.54-unit rifle squad envelope. Commands were rejected; some formation fallback candidates were clear but disconnected. A bounded reachable alternative now accepts open-ground gap orders. Exact screenshot coordinate is inferred; physical occupancy of the narrow gap remains constrained.

Generated PNG imported without mipmaps by default, producing distracting grain in native rendering. Explicit mipmaps and reduced atlas contrast corrected this; do not judge shader assets from headless imports alone.

Performance remains unresolved: texture-stage runs measured 28.668 and 32.124 ms frame p95; simulation p95 around 21 ms. Do not claim this material pass improves smoothness.

Repeated scenery batching reapplied default shader paint over existing vertex colors/finish. Fixed by preserving already vertex-painted source meshes; test_material_batching verifies color/finish survives a second pass. Native roadside prototype initially failed GDScript type inference for rubber/glass; explicit Color annotations fix it. Reject renders from that failed run.

Full linear conversion of the batched palette made units and trim too dark in the existing art/lighting setup. Kept a deliberate 75% linear / 25% authored-color response, with neutralized ambient/sun balance and reduced ground saturation. This is art calibration rather than a calibrated physical color pipeline.

## 2026-10-14 refinement findings
- Sampled equipment/plaster/soil variation was clamped into near-constant values by incorrect normalization. Normalize against measured source means for the current GL material response; removed artificial square procedural paint flecks and oversized fabric weave.
- A cheap simplified plaster shader removed too much weathering in native review; rejected and restored layered surface treatment.
- Metal first launch spent most benchmark wall time compiling pipelines, leaving only95physics samples. Reject that run for comparison. Benchmark timing now begins after the first frame, then warms for2s.
- Actual Godot MSAA enum2 is4×, while docs said2×. Set enum1 for intended2×.
- Claude Code cross-review attempted via local and Diane host controller; both returned Not logged in. No review result exists.

## 2026-10-14 navigation recovery follow-up
- Interrupted recovery triggered at 7.5-unit spread during legitimate shelter seeking, cancelling it before arrival. Seeking already holds the anchor; exempt it from that immediate trigger while retaining the eight-second stalled-progress recovery. Tactical shelter-then-advance fixture now passes.
- Single-order village run reunites sections and captures the village by 60s, but sections 2/3 remain mutually congested (~20s blocked). Individual wall recovery does not solve all group traffic.
- Withdrawal health thresholds used original squad capacity despite permanent casualties. Corrected to living-member capacity; completion fixture passes. Rally conflicts, silent long withdrawal stall, SUPPORT cover clearing, hidden shelter reservation and nearest-only exposure still need dedicated fixes.
- Sandbox default user-log creation crashed Godot before tests. Use explicit log files in a writable temp dir (`$TMPDIR`; `tools/check.py` creates its own). Passing headless runs still emit the platform certificate-store diagnostic.

## Riverside integration — 2026-10-14

- Whole-cell dynamic obstacle padding did not fix corridor/dock congestion and was removed. Preserve weighted AStar and continuous swept clearance.
- First Riverside review found a freight-road/parcel overlap, a car clipping the high street and a five-item scenario selector. Corrected;96 map checks and the dynamic six-entry HUD regression pass.
- Classic scripted policy lost around 340 seconds because attack-position selection chose a geometrically clear but disconnected pocket. Testing candidate connectivity restores the unchanged mission to victory at371.9 seconds; the focused regression retains target identity and verifies route acceptance.
- Aircraft bands on tall-building maps are 11/13 instead of 7/9. Their authoritative slant-range calculation narrows horizontal reach; this is a balance consequence, not purely visual. Static/pitched/bob-minimum scenery clearance passes across all six scenarios; counterplay balance remains open.

- Native VFX review found giant white cards that headless particle-capacity tests missed. The projection-sign correction was verified natively; final worker revision uses CPU camera-facing bases and normal shader transforms. Native size/presentation checks remain required. A claimed renderer MODEL_MATRIX incompatibility was an unconfirmed worker hypothesis, not established cause.

## Asset-library integration — 2026-10-14

- Fixed native-review defects: tent cloth gaps, periodic star-shaped ground marks, uniform headwall stones, opaque shelter glazing, and neutral colors leaking from the last drawn faction. Asset geometry tests alone did not identify those visual problems.
- Fixed a warehouse sample wrapper that requested an unsupported narrow parcel, and a soot face extending0.1 below the shed datum. Gallery now measures render bounds separately from collision envelopes.
- Three-person squad recovery remains a timing regression: all members reunite, command/collision rules pass and all sections finish by90s, but section1 misses the pre-existing60s checkpoint and arrives67.10s. Broader tactical changes were rejected/reverted because they worsened combat. See artifacts/three-person-recovery.md. Preserve the failing assertion for the next navigation pass.

## Test infrastructure — 2026-10-15

- Tests wrote evidence to hardcoded `/private/tmp` paths. In a sandbox the open returned null, the chained `store_string` raised a SCRIPT ERROR, and `--script` runs hang instead of exiting (test_large_terrain hung until the alarm). Evidence now goes to `res://artifacts/` (gitignored) and every `FileAccess.open` result is null-checked before writing.
- probe_engage, probe_resume, probe_resume_harbor and probe_lethality printed FAIL but exited 0, so wrappers could not see failures. They now `quit(1)` on failure. `tools/check.py` runs them (`--group probes`) along with the 2026-10-14/15 combat suites (`--group combat`), and a timeout counts as a failure instead of aborting the batch.

## 2026-10-16 integration round

- Exact corner sweep in `Terrain.segment_clear` (fixes test_roadside_props' ~1 cm corner clips) was rejected. Applied to grid edges it drops whole routes (the nav grid is built with sampled clearance, so adjacent-cell edges fail; a tank lost its order in test_hitches). Applied only to smoothing shortcuts it slowed infantry sections past the regroup 60 s checkpoint and, for vehicle profiles, left IRON DISTRICT unresolved at 480 s. test_roadside_props keeps its 2 failures; the patch is in `output/team/w3_integration_wip.patch`.
- Classic playthrough loses at ~344 s since the HE-splash and wound-model commits. Cause is balance, not a bug: frontal tank-on-tank penetration chance is ~0 at duel range (760 mm armour vs 520-620 mm gun), enemy ATGMs (700 mm) kill player tanks, and immobilised enemy tanks next to the ore field kill harvesters. Script-only variants all lose or stalemate. Needs a balance decision (e.g. tank far penetration ~700 or nonpen_damage ~0.15, plus a script that mixes ATGMs and guards harvesters).
- `tactical_director.engage_idle` can still pull a whole section out of wall cover when its only shooter loses a target for a moment (seen in test_garrison's halt; currently masked).
- Tick 0 of a harbor battle still costs ~85 ms (simultaneous cover searches plus field_ops setup). Queued routes can cost up to ~16 ms in one tick (`ROUTE_QUEUE_WORK` 180); lowering it trades spike size for route delay.
- Regroup exemption that counted "a known enemy within 25 u" (not just incoming fire) as contact deadlocked all three regroup-mission sections (anchor waits on the leash for soldiers Cover keeps sheltered). Reverted; only rounds received in the last 4 s count.

## 2026-10-18 round

- Classic playthrough outcome is a coin flip across combat seeds; single-seed pass/fail flips with almost any combat change. Judge balance on a seed sweep (default + 11-20), not one seed.
- Regroup recovery's mission part is one chaotic seeded fight; it was made robust with fixtures/bounds, but combat changes can still expose real traffic bugs there (it caught the parked-tank alley jam).
- Gunner-held ATGM guidance (TOW-style) was replaced by fire-and-forget for the Javelin (realism); stretching lock time or lowering seeker odds to rescue classic was rejected.
- A hard tank hold-back outside Javelin reach stalled classic assaults (2/5 wins); kept a milder pull-back.

## 2026-10-18 leftovers

- Harvester jam fix + threat-aware deposits merged 2026-10-19 (693388e) on judgement: realism and harvester losses (82 -> 58, enemy-side 26 -> 1) over scripted-player win rate (24 -> 20 of 29, inside the neutral-control band). Rejected along the way: a dock-spot unload rule (lost loads), a fixed "enemy half" territory rule, and avoiding sightings on home ground (both wrecked the economy).
- Don't gate on the scripted classic bot's win rate (player direction 2026-10-19): the check is now a smoke test. Background: win-rate bars were fragile at 8 seeds/75%: neutral controls (rotating harvester stand points 0.2 rad) drop main from 24/29 to ~19/29 and can fail it. Judge classic changes on 29+ seeds against such controls.
- Wrecks: tanks shove light wrecks and engineers clear any wreck (2026-10-19). Open: AI engineers don't clear wrecks on their own; classic mode has no engineer wreck clearing (like barricades); IFVs can't shove. Single-lane approaches still leave ~20% of a 12-tank column unfired within 180 s.

## 2026-10-20 — Harbor victory after logistics destruction (resolved)

- Destroying all enemy command posts and ammo depots before reserve dispatch correctly prevented the reserve from forming, but also left `counterattack_sent` false forever. The autonomous victory check still required that flag, so holding every objective for the full 90 seconds could never finish the mission.
- The victory check now accepts neutralized authored field logistics as satisfying an unsent reserve requirement. It keeps the full uncontested objective hold, the existing delay for a reserve already dispatched, and the normal rules for maps without authored logistics and legacy missions. No reserve flag or spawning behavior changes.
- Final review reproduced a related full-tick outcome bug: with all player mobile units dead but a friendly support structure alive, objective resolution could replace the defeat set by field operations. Victory assignment now preserves an existing terminal result, with a regression that retains a completed aid post.
- The initial `test_field_victory.gd` fails only the original victory assertion on unchanged main. The expanded suite passes all 43 checks after both fixes and is registered in `tools/check.py`. Seven focused suites pass (1,141 checks, 0 failures) on Godot 4.5.1. The new test uses controlled mission states, not a complete combat playthrough.
