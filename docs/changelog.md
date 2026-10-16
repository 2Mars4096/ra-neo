# Changelog

## 2026-10-16 — Enemy buildings, mortar, open-ground prone, frame time, air clearance

- Enemy defenders garrison buildings near objectives; the enemy fires mortar salvos with a warning toast (`test_enemy_garrison` 38/0). Mortar rounds have their own whistle (0.62 s before impact), dirt-fountain burst and 1.4 m crater. A building collapse is no longer also voiced as a tank kill.
- Garrison transit: during the walked entry/exit, spotting, concealment and blast shelter apply per soldier (`test_garrison` 32/0).
- Spatial targeting matches the brute-force reference for sections whose soldiers are spread out (`test_spatial_targeting` passes again). The parcel test skips the authored harbor builder.
- Soldiers under fire with no reachable cover go prone within ~0.5 s and keep firing (open street: 4.4 s -> 0.53 s). Cover searches plan with the standing body, so going prone never blocks a move to cover. Sections stay by a bleeding squadmate instead of walking off to man works.
- Simulation tick ~11% cheaper on the harbor combat profile (mean 8.85 -> 7.86 ms, p95 11.6 -> 10.5 ms, tick-297 spike gone); seeded results bit-identical (`tests/profile_harbor_combat.gd --fingerprint`).
- HARVEST LINE resolves (victory 141.5 s): downed all-severe sections no longer block movement. Attack re-plans skip stalled hulls; detours treat wrecks as obstacles.
- Aircraft climb over harbor structures taller than their cruise altitude (air ceiling from authored buildings and props; `test_scene_air_clearance` 16/0).

## 2026-10-15 — Realistic damage, world destruction, audio, hitch removal

- Infantry wounds (`infantry.gd`). Soldiers go HEALTHY/LIGHT/SEVERE/KIA with per-weapon outcome rolls. HE fragments wound nearby soldiers. SEVERE casualties bleed out unless given buddy aid, and bodies persist. A section whose survivors are all SEVERE stays selectable but is combat-ineffective and is not auto-targeted (`test_wounds`).
- Vehicle damage (`vehicle_damage.gd`). Penetration by facing and range. Component effects: mobility, firepower, crew (bail-out), catastrophic. Wrecks stay visible as dark hulls, block routes for everyone, and give cover (`test_vehicle_damage`).
- World damage (`structure_damage.gd`). Only HE damages buildings: damaged -> breached -> collapsed rubble, with garrison casualties and burials. Field works ignore small arms, depots cook off, and HE cuts wire. Boats can burn or flood, helos crash or force-land, drones are fragile, and HE flattens street furniture. Attack-click (A) a building with HE vehicles to shell it (`test_world_damage`).
- Garrisons fire from windows facing the nearest spotted enemy, with 1.4x range from upper floors.
- Procedural positional audio (`audio_fx.gd`): 30 synthesized sounds, a 16-voice pool with per-category caps, engine/rotor/footstep loops for the nearest units, and ambience. M mutes (`test_audio`).
- Explosions are about 3x larger and layered: flash, fireball, shockwave, debris arcs and a dust column, with camera shake.
- Player FPV strike: 150 supply, 5 drones, 60 s cooldown, aimed at a visible enemy near the click (`test_player_swarm`).
- Hitch removal. Nav-grid re-weighting is incremental and path planning has a per-tick budget. Harbor combat profile: max step 222 -> 70 ms, and only the first tick exceeds 33 ms (`test_hitches`).
- Persistent battlefield remains: craters and scorch stamped into 64 m ground tiles. They are round, irregular and rimmed. Cost stays flat (0.002 ms with 3000 marks), uploads are capped at 2 tiles per frame (13 µs native), and debris is capped at 512 pieces, oldest replaced first. Fireballs have a hot core and dark edges.
- Vehicle follow-ups: abandoned vehicles do not explode, wrecks give infantry cover, repair points restore tracks, gun and crew, and tanks and HE fell the 80 collision trees.
- Cover-search fixes: wall sampling uses the building index, and routes blocked by still squadmates are rejected. test_garrison and test_regroup_recovery now pass.
- Contact tactics: on first fire, soldiers drop within 0.5 s and return fire. They prefer corner and edge cover they can fire from, re-check shelters when a new threat appears, go prone in crossfire, crouch in shelter, and rush one at a time. engage_idle no longer pulls sections out of firing cover (`test_contact_drill`).
- Re-crew or capture abandoned vehicles: right-click with an infantry section, about 4 s of work, and two soldiers board (`test_recrew`).
- FPV drone HUD name, threat tag and dive pose. Craters use smooth B-spline sampling. Audio and presentation-cache timing tests are now robust to machine load.
- Renderer: Metal/Mobile was benchmarked (engine p95 18.6 -> 10.9 ms) but kept off because colours wash out. The project stays on GL Compatibility.

## 2026-10-15 — Parallel round: vehicle routing, explosions, presentation cost, counter-drone and FPV swarms

- Vehicle routing. Coarse 4 u vehicle cells now stay open when any of 8 sub-points fits the hull; that point becomes the cell's waypoint. Shortcuts keep a 0.3 u margin. Hulls accept passed waypoints. Routes avoid parked units, oncoming tanks pass on their own right, and idle friendlies make way (`Terrain._refresh_land_cell`, `_anchor`, `_path`; `Simulation.standing_bodies`, `make_way`). `tests/probe_vehicle_path.gd`: mean route ratio 1.233 -> 1.017, worst 3.80 -> 1.09, false "no route" 2 -> 0, head-on tank deadlock fixed. The tank grid build at load rose 0.2 -> 0.4 s.
- Explosions (`scripts/effects_explosions.gd`). Distinct tank HE, ATGM/rocket, AT gun, FPV, masonry and generic recipes. Vehicle kills get secondary pops, cook-offs, a lingering smoke column, burning-wreck flicker and a scorch fading over 30-60 s. Bunker and depot kills have their own effects. Engineers die as infantry. Everything is pooled: no per-shot nodes, no dynamic lights. AT gun and bunker shots now report their own kind. `test_effects` 156/0.
- Presentation cost. The HUD draws in three canvases, and the sidebar redraws only on change or at 20 Hz. Fog and minimap repaint only cells that changed. Settled animation joints and unchanged transforms are not rewritten. Harbor ground detail casts no shadows and is merged into tiles (793 -> 300 instances). Headless per-frame scripting fell from 1.73 to 1.02 ms mean, and the worst frame per second from ~5 to ~2 ms. The sim step is unchanged. Its 140-220 ms spikes are nav-grid re-weighting after weather wetness changes, still open.
- Counter-drone. AA is the strong counter, rifles hit drones only up close, and the tank coax is weak. Attack orders on drones work, and AA prioritises aircraft.
- FPV swarms. The new `fpv_drone` flies straight in, hovers to line up, dives and detonates (60 dmg, 4.5 m). From wave 2, each enemy wave brings 4-8 drones, and mid-wave strikes hit the densest visible player cluster. A toast warns on launch. Idle units do not chase strike drones, and the dive is visible. `test_counter_drone` 39/0.

## 2026-10-15 — Hull steering, crushable street furniture, obstacle clearing, garrison fire

- Tanks, AA and boats move only along their hull axis. They turn (pivot when blocked) and back out of jams instead of sliding sideways (`Simulation.hull_step`).
- Tracked vehicles flatten lamps, trolley poles, benches, fences, small trees, bus stops, dumpsters, kiosks, cars and similar props in their way. Each crush refreshes only the local nav cells. Tracked route planning treats these props as passable, so tanks no longer detour around them (`Terrain.crush_props`, `crush_pass`). Tall props topple in the drive direction and low ones flatten, by editing the batched MultiMesh instance in `HarborProps.crush`.
- Engineers clear wire, hedgehogs, sandbags, trenches, berms and nets: right-click the work with engineers selected. Own works give a 50% refund (`FieldOps.clear_site`, `progress_clearing`).
- Garrisons fire: a stale walking value from the walked entry kept soldiers "settling", so they never aimed. Defenders now shift each second to the windows facing the nearest spotted enemy (`Garrison.man_windows`). Capacity scales with building size (2-8 sections). The 35% damage reduction applies to small arms only; tank/ATGM fire does 85%.
- `tests/probe_tank_crush_clear.gd` covers all of the above.
- Proactive engagement: the tactical director only reacted for units on attack orders, so idle units and units that had finished a move ignored enemies seen between rifle range (13) and sight (19). Idle units now close to firing range on a spotted, effective target, leashed 14 m from their post (`TacticalDirector.engage_idle`, phase ENGAGE). This applies to both sides. HOLD, garrisons, soldiers manning works and busy engineers stay put (`tests/probe_engage.gd`).
- Enemy units jammed against player obstacles breach them by fire, then resume their wave (`FieldOps.enemy_breach`).
- Testing economy: harbor starting supply 3200 and income 6/s (doubled).

## 2026-10-14 — Walked garrison entry, tighter sandbag cover, build resume

- Garrison entry and exit are walked. Soldiers queue at the doorway and pass through the wall one at a time, hidden once inside. Leaving reverses it, with soldiers stepping out to formation spots before the order continues. States show ENTERING/EXITING. A garrisoned section's ring encircles its building and its label sits above the roof.
- Sandbag (tactical cover) footprint is 2.8 x 1.0 to match the visible wall (was 2.8 x 2.0). Cover slots sit 0.85 m past the friendly face, so soldiers hug the wall.
- Engineers with a site to build (assigned or queued) no longer go off to man nearby works. Right-click an unfinished friendly work with engineers selected to resume building it.

- Infantry sections no longer block other units as 2.65 m circles. Against other units, a section takes its formation footprint (2.0) for spawn spacing and move slots. On contact it counts as its individual soldiers: tanks are checked against the soldiers, a section anchor is one soldier wide against vehicles, and blocked-unit detours avoid real bodies rather than squad circles. Soldiers from different sections squeeze past at 0.7 clearance in both steering and regroup paths. Squadmates may always step apart. The 2.65 terrain envelope is unchanged.
- No mutual locks: a tank or soldier may always make a move that opens distance from the body it overlaps. A tank and an ATGM section deployed together used to freeze each other. Clicking any visible soldier now selects its section; before, only the section's abstract centre point was clickable.
- Graceful passing: each soldier looks 3.5 m ahead and sidesteps bodies of other sections or vehicles early. Everyone passes on their own right, so oncoming soldiers don't mirror each other. Soldiers also ease off speed when someone is right in front. A section's centre point veers its formation around groups ahead with a soft steering cost. Last-resort brushing past keeps a 0.65 m floor. In the head-on crossing probe, closest approach went 0.24 -> 1.09 m, squeeze soldier-ticks 119 -> 27, and crossing time 8.1 -> 6.9 s.
- Head-on sections pass through each other (`tests/probe_crossing.gd`). A section and a tank cross a packed five-section block, and six sections ordered to one point all arrive (`tests/probe_crowd.gd`).

## 2026-10-14 — Cover use, garrisons, lag stalls

- Halted sections man nearby own works: soldiers file into trenches and along the friendly side of sandbag lines (away from the threat or enemy side) without needing contact. Trench/hedgehog interiors count as protective cover in the under-fire search.
- Garrison: right-click a city building with infantry to enter (capacity 1-2 sections); soldiers hold window posts, take 35% damage and 30% suppression, see +6 m; any order leaves. `tests/test_garrison.gd`.
- Sandbag cover renders as a straight full-length wall so dragged segments join into a line. Passive enemy works are not auto-targeted (right-click to force attack). Queued drag segments show QUEUED; RESUME switches the engineers to them; idle engineers continue their line. Enemy waves start at 90 s with a warning; idle defenders strike intruders near their posts.
- Lag: the soldier navigation grid is prebuilt at load (it was built lazily mid-fight, ~0.35 s freeze); segment checks sample at 0.9 x radius and path smoothing has a bounded look-ahead (previously quadratic, 100-340 ms stalls). Busy 84-unit harbor fight: mean step 12.5 -> 9.3 ms, worst 342 -> 168 ms, >60 ms stalls 21 -> 4. Sun uses one orthogonal shadow map instead of four cascades (native timing not yet re-measured).
- Reverted an attempted infantry section radius reduction (2.65 -> 1.4): it broke district reachability and wave orders.

## 2026-10-14 — Enemy assault waves, drag-to-install works, wire and trench behaviour

- Escalating two-pronged enemy waves from the NE staging area (first at 150 s, every 115 s, up to 8): scout drone ahead, main body attack-moves on the player's forward base, a flank group detours 70 u off-axis; broken waves (<30% strength) withdraw. Waves stop when enemy command posts and depots fall. Extra garrison rifles and a tank per objective. Player starts with 1,600 supply and 3/s for build-up.
- Drag to install: sandbags, wire, trench and anti-tank obstacles lay axis-snapped lines; nets tile an area. Cost scales with segments; one engineer section builds queued segments in turn; preview shows each segment and total cost.
- Wire is an infantry navigation barrier (cells touched by the belt are solid for infantry; crawling through only when no route exists). Soldiers inside a dug trench crouch and stand in it.

## 2026-10-14 — Enemy defences, armed emplacements, queueing and map realism round

- Enemy holds prepared positions per objective (wire, trenches, MG bunkers, AT gun pits, hedgehogs, command posts, ammo depots; 22 works) with trench garrisons and a 7-unit armoured reserve. The reserve only forms while an enemy command post or depot survives. `tests/test_enemy_defences.gd` (21 checks).
- New armed emplacements usable by both sides: MG bunker and AT gun pit fire with their weapon alias once complete; command post and ammo depot added. Field-works grid holds 14 works at 1280×800.
- Reinforcements queue: repeated clicks queue paid units, deployed every 3 s; crowded entries wait; right-click removes one with refund.
- Camera clamps by the real visible ground corners (no strip beyond the map edge); fog of war is a neutral shroud instead of a navy layer that made land read as water.
- Map: touching old-town party walls and corner nudging, microdistrict slab rows along the block axis, civic squares free of yard clutter, deterministic 15% damage near objectives, narrower drawn carriageways with kerbed pavements (navigation width unchanged), clustered tree crowns, a detailed bronze monument.
- Codex and Claude district reviews (`output/team/district-review-*.md`) agree on remaining issues: old-town continuity, residential road widths, yard surfaces and wall continuity.
- Native benchmark over the old town: frame p50 16.5 ms, p95 19.8 ms, 550 draw calls (GPU-bound; shadows next).

## 2026-10-14 — Realistic harbor city, building families and engineer works

- Diagnose the artificial harbor: fixed street spacing plus an 11-type cycle. Add [city design rules](harbor-city-design.md): district morphology, scale, building/decor contracts, engineer tiers and the deferred off-map logistics formula.
- Add 27 parametric building families (`city_buildings*.gd`: limestone rows/corners, Stalinist block, cathedral, panel 5/9, school, private houses, garages, port sheds, barracks, fort ruin), each with damaged/ruined states, plus 38 city decor assets with MultiMesh rendering and 96 u building tiles.
- Recompile Black Sea Harbor by district (473 buildings, 1,920 decor placements, oriented collision rects). Old-town continuity and microdistrict density remain open.
- Add engineer wire, anti-tank obstacles (hard vehicle barrier), trench, hull-down berm, camouflage net and forward supply point; T rotates linear works. Codex cross-review fixed forward-entry, footprint, berm-direction, camouflage-while-firing and preview issues. 108 engineer checks pass.
- Native capture, realism cross-review of the full map and performance measurement are not yet done.

## 2026-10-14 — Field operations and measured performance repairs

- Riverside defaults to one supply pool and off-map purchases. Add three-person engineers and timed cover, observation, repair and aid structures; defer macro economy and hide its legacy mode.
- Paid sites preserve work when interrupted, can resume with a free/replacement engineer and refund unused work on cancellation. Previews use observed occupancy; physical commit checks prevent overlap without spending on failure.
- Cache minimap terrain classification; use lazy weather-weight refresh, cached preview paths and local navigation-cell updates for field geometry. Completing cover changes protection without changing underlying ground firmness or rebuilding path costs.
- Actual native construction proof shows engineer travel and completion; UI includes costs, progress, Resume, Cancel/refund and specific interruption reasons. Legacy tests now pin their original fixtures rather than relying on the changed default mode.
- Timing evidence remains mixed: single-shadow-map diagnostic reduces busy-scene draw calls1082→923 and frame p95 21.236→18.435ms, but still misses16.7ms. Production adoption requires visual inspection; no complete lag-fix claim.
- User now requests one huge Sevastopol-inspired fictional theatre; implementation continues under plan13 rather than further enlarging Riverside.


## 2026-10-14 — Structured asset library and review corrections

- Prioritize assets/rules before further map enlargement at user request. Add72 original environment variants across nine environment categories, registry adapters for28 existing assets, and a labelled native gallery covering100 models/10 categories including architecture.
- Add metadata footprints, placement contexts, access/drainage checks, conservative overhead-assembly reservation and separate measured render bounds. Library builds do not install physics or tactical cover.
- Codex/Claude visual reviews identify shelter glazing, regular rip-rap, tent seams, star-like damage marks, palette dependence, drainage geometry and gallery framing. Supported fixes pass native gallery and asset tests; no full reference-parity claim.
- Fix initial classic camera focus on the player HQ, explain full production queues, remove ungrounded legacy cyan deployment lines, and add22 usability checks.
- Default rifle squads use3 members with a shared model/simulation formation. Preserve total squad HP/damage/cost. Final50-suite run passes49; only the preserved first-section60s arrival assertion fails at67.10s. All sections complete by90s; movement acceptance remains open.


## 2026-10-14 — Authored Riverside and bounded recovery

- Add a 144×108 sixth classic scenario with twenty parcels, explicit architecture/facing, road hierarchy, districts and four resource fields. Dimensions propagate through world/water/weather, navigation, fog and camera. Layout review corrects freight clearance, southern road continuity and contested expansion access.
- Bounded individual regroup and congestion recovery complete the original three infantry attack-move orders by 90 seconds without order reissue or teleportation. Distinct withdrawal slots and stalled-withdrawal release preserve intent.
- Correct construction search bounds and choose reachable unloading sides; real Riverside fixtures validate paid production and moving deliveries for both teams. Connectivity-tested firing positions restore the unchanged classic mission to victory at371.9s. Riverside full-match balance remains open.
- Add categorized reusable environment variants with measured mesh bounds. Integrate layered effects and district ground composition. Native effect captures pass after correcting billboard projection;41 integrated suites pass before the final frontage/quay adjustments.


## 2026-10-14 — Regroup recovery and scenario-size infrastructure

- Preserve interrupted bounded actor AStar return paths and squad regroup pauses; fix premature cancellation of valid shelter seeking. Single-order 60s village fixture captures the sector and reunites sections 1–3; sections 2/3 still show group congestion.
- Read scenario size with 96×72 defaults; adapt navigation weights/exclusions, fog, camera pan, minimap, rally/base bounds and naval spawning. Synthetic 144×108 checks pass; manager-authored sixth map is not yet present.
- Use surviving-member health capacity for withdrawal thresholds. Ten focused headless suites pass; see [9-1 evidence and limits](plans/9-1-navigation-recovery.md). No native benchmark or render-acceptance claim.

## 2026-10-14 — Profiled simulation and composed parcels

- Reduce measured600-tick CPU workload10.209s→5.272s through actor-body spatial queries, immediate relocation, steering rejection ordering, shared eligibility and reduced terrain allocations. Final authoritative state remains identical; add1,447 equivalence checks.
- Replace repeated intact boxes with stepped paired shops and distinct townhouse/service wing, farm pergolas, planted courtyards and workshop context. Add exposed ruined rafters/joists;135,920 bounds checks pass.
- Correct clamped atlas variation, remove square paint speckles, reduce fabric texture scale, mute equipment colors, soften shadows and replace square leaves with folded/tapered opaque leaves at equal triangle count.
- Use an instanced distant infantry contact-shadow layer; preserve close animated shadows. Correct MSAA documentation/config mismatch to actual2×. Separate benchmark startup from steady runtime and add cost/memory/vsync metadata.
- Final default-pacing frame p95 is25.091ms, with1,222 draw calls;32suites pass. Headless CPU work falls48% with identical state.
- Independent Codex art review identified remaining gaps; Claude Code authentication prevented cross-model review. No claim of full reference parity.

## 2026-10-14 — Material atlas and reachable gap orders

- Fix repeated scenery batching overwriting existing vertex colors/finish with default shader paint; add regression.
- Add original generated plaster/paint/asphalt/soil and tile/sheet-metal/canvas/brick atlases to runtime shaders, explicit mipmaps and anisotropic sampling. Preserve equipment finish classes and faction colors; add restrained canvas weave. Inspect actual overview, detail and equipment renders.
- Replace outright rejection of tight open-ground clicks with a bounded reachable-position search. Preserve solid building/yard footprints. Formation and crowded spawning now check connectivity. Add 2,746-check gap regression and adjusted-order feedback.
- Add road-purpose paving, shoulders, drainage grates and a village crossing; keep these surfaces flush and batched. Larger roadside object families remain open.
- Add one sedan, one service van and three streetlights per showcase map using shared collision footprints; validate 21,639 checks. All 30 suites pass.
- Retune palette/ground saturation and light balance after native comparisons.
- Full reference fidelity remains unmet: this is a material-source improvement, not bespoke production models.

## 2026-10-14 — Team revamp, road routing and command sidebar

- Integrate separate HUD, environment and performance/camera workstreams in this non-Git workspace. User explicitly authorized team work and a full revamp.
- Replace bottom dashboard with right RTS sidebar, original cached equipment portraits, road-aware minimap and compact resource rail; preserve production/construction/queue controls. Test 1,080 layout assertions across three resolutions.
- Add smooth wheel/pinch zoom (24–84), paused zoom, actual HUD exclusion, cached animation rig references, and normal 60 FPS ceiling (benchmark uncapped).
- Replace duplicated road strips with shared connected destination graphs, junctions and declared widths. Preserve travel-cost detours through path smoothing; add infantry/tracked/wheeled surface and weather costs shared by movement and planning. Cache weights separately from collision geometry.
- Add architectural families and two additional Canal Watch parcels; reject a third after a mission timeout. Replace round foliage spheres with instanced opaque leaf clusters. Substantial scenery remains collision-backed; enclosed yards are not traversable interiors.
- Add wide-zoom fine-part shadow suppression, restoring those shadows close up. Full 27-suite run passes; subsequent focused interpolation/shadow and clearance tests pass (135,780 checks). Final performance below is tracked in validation.md.
- Inspect all approved concepts against actual close/overview gameplay. artifacts/revamp-review.html records major remaining gaps: sparse settlement composition, repeated proportions, ground detail and material/lighting quality. Visual acceptance remains open; no reference-parity claim.

## 2026-10-14 — Structural scenery and art-direction options

- Implement collapsed building component variant, per-building material batching and revised instanced foliage; add presentation-only position interpolation between simulation ticks. Input and focused interpolation checks pass; final integrated clearance review remains pending.
- Isolated rainy benchmark: 22.332 ms frame p95, 6.85 ms median, 11.05 ms simulation p95. Still misses target; earlier process concurrency prevents attributing the difference solely to code.
- Generate three reference concepts with built-in imagegen: dense town, canal works and village edge. User selection pending; concepts are not implemented screenshots. Pause further scenery expansion for selection.

## 2026-10-14 — Authentic diorama surface pass

- Add layered plaster/masonry, damp staining, varied roof courses, oxidation and subtle surface relief; preserve painted miniature presentation.
- Add equipment dust/wear, distance-filtered ground aggregate, lintels and occasional faded shutters.
- Native review reduced excessive plaster chipping; 126,928 clearance checks pass. This is a material/facade increment, not a production-asset replacement.

## 2026-10-14 — Visible individual shelter behavior

- Replace short-radius formation adjustments with bounded individual routes to reserved shelter positions; sample actual building edges and reject exposed wall faces.
- Stagger seeking, retain valid shelters, settle before firing and respect explicit order overrides. Display selected soldier shelter paths and status.
- Fix repeated shelter expiration discovered by the classic mission regression; unchanged policy wins at 538.1s. All 21 suites pass, with native cover frames reviewed.
- Audit prior requests and separate implemented prototypes from outstanding art, behavior, production and scale work in request-audit.md.

## 2026-10-14 — Classic skirmish and scaling foundation

- [validation] All 20 suites pass; classic policy victory at 554s. Synthetic 2,000-record range-query p95 is 50 µs versus 521 µs exhaustive. Current 100-entity rendered frame p95 is 21.724 ms: target remains unmet, with no measured frame-rate gain.

- [gameplay] Add fifth mode with finite deposits, harvest/deliver vehicles, HQ/power/refinery/barracks/factory construction, production queues, prerequisites, low-power slowdown, rally points, refunds and base-destruction outcomes. Retain the prototype player combat bounty; economic balance is provisional.
- [fix] Bound producer exits, reserve actor clearance, prevent building on deposits, count queued replacements, and search legal refinery sites with haul distance considered.
- [navigation] Resolve an obstructed AStar start-cell case, include actor footprints in detours, and allow blocked attack orders to reroute.
- [UI] Add skirmish instructions, construction placement, producer queues and power feedback. Native render reviewed; actual input tests cover production and placement.
- [decor] Review environmental dressing; add rooftop service detail and localized surface damage without narrowing navigable lanes. Full prop library remains future work.
- [optimization] Share spatial combat candidates per squad, use spatial sight queries and indexed unit IDs, and skip duplicate fog-field unions. Preserve brute-force selection order and verify seeded behavior/fog equivalence. Add synthetic 250–2,000-record query measurements; these do not establish full-battle capacity.
- [scope] Record the user-confirmed town/thousands-of-troops direction and remaining navigation, AI, rendering and scale validation work in plan 9.

## 2026-10-13 — Canal Watch showcase

- [gameplay] Add objective-preserving land-group flanks, supporting waits, withdrawal/regroup deadlines, explicit-order overrides, individual cover reservations and collision-aware local movement. Show tactical reasons and route markers.
- [motion] Add showcase acceleration/braking/reversing, flat-ground stance-foot placement and independent reload cycles. Preserve hull/turret separation and existing clearance checks.
- [mission] Add fourth scenario with canal-village geography, alternate routes and a capture-triggered mixed counterattack. Add target sheet/storyboard and focused regression fixtures.
- [weather] Add passing rain front, visibility bands, wet-soil slowdown, firm roads, persistent drying, rain/haze/wind-smoke effects and HUD feedback. Existing scenarios remain dry.
- [art] Vary village and industrial roofs/heights, add facade/roof construction detail, bevel substantial equipment parts and separate rubber/glass/metal/paint finishes. Add plaster, tile and sheet-metal procedural textures.
- [behavior] Add settle/turn/crouch/aim readiness before firing, reload preparation reset, pinned prone with an extended collision footprint, rising delay, and building-edge cover. Articulate knees/ankles and guard correct foot placement.
- [performance] Reject distant groups before detailed actor sweeps while retaining precise local clearance checks.
- [validation] All 16 behavior/geometry suites passed after weather and geometry changes; material render review and final profiling recorded in validation.md. Human acceptance remains open.

## 2026-10-13

- [verify] Inspect painted equipment and three map renders; pass 126,888 post-material clearance checks. Latest stress p95 is 21.644 ms at 1080p; performance remains above target.
- [art] Adopt the user-selected painted military miniature direction. Add a shared matte shader with broad paint variation, upper-face highlights, light dust, and soft lighting bands across batched equipment and solid scenery. Update faction paint and warm/cool lighting; reduce terrain texture noise.


- [fix] Remove synthetic tracked-vehicle vertical bob, bound rendered hull yaw, retain valid targets, and penalize abrupt avoidance heading changes. Reject non-progressing avoidance steps.
- [maps] Author open agricultural parcels/shelter belts and urban street blocks with distinct objective locations, ground treatments, and roof styles. Remove harbor props/collision from Fields. Share objective positions between simulation and collision poles.
- [test] Add chassis/target stability checks; complete all three revised scenario playthroughs.


- [combat] Separate weapon eligibility, slant range, hit probability, and on-hit damage; add seven-by-seven effectiveness data, front/side/rear armor, motion/range/suppression accuracy, and seeded misses. Rifles cannot damage armored hulls; one successful rifle hit disables the fragile small UAV.
- [combat] Check surviving soldiers' actual weapons and ranges for group engagement; add recruitable AA and feedback for ineffective attack orders. Misses no longer display target-hit flashes.
- [feat] Add pre-briefed EXCHANGE radio interference to the industrial scenario. Units retain orders and local defense while remote orders/sensor uploads fail; capture restores the link. Add minimap coverage and selected-unit feedback.
- [fix] Replan around nearby bodies after sustained yielding; resolve the industrial congestion found by unchanged mission regression without relaxing swept clearance.
- [test] Pass ten suites, including 1,064 combat/communications and 135,171 clearance checks; render the interference UI and measure 17.747 ms 1080p frame p95 (16.7 ms target remains unmet).
- [perf] Remove per-member target-check dictionary copies; preserve combat behavior.
- [docs] Record fictional numerical choices, role relationships, communications behavior, and unimplemented physical details in combat-design.md.


- [perf] Final active individual-entity benchmark: 16.384 ms rendered-frame p95 at actual 1080p on Apple M4 Pro, 8.016 ms simulation p95, 95 surviving friendly entities. Confirm simulation sample count and exclude command input during measurement.

- [feat] Replace rigid infantry sections with individual soldier positions, HP/casualties, target acquisition, firing cadence, suppression/reaction state, and survivor-only recovery. Keep squad commands and conservative shared routing.
- [animation] Add articulated legs/upper bodies/weapons, independent turret tracking, cannon recoil, rolling wheel spokes, UAV rotor motion, aircraft lean, and ship roll. Add explicit state priority and bounded hit reactions.
- [vfx] Add bounded moving projectile/missile presentation, delayed impacts, expanding impact dust, water splashes, and damaged-vehicle smoke; infantry losses no longer use vehicle fireballs.
- [feat] Add Coast/Fields/Urban briefing selection backed by scenario data, with varied obstructions, woods, ruins, soft soil, sector names, defenders, and hold times.
- [fix] Keep individual formation slots stable to avoid turn deadlocks; move hit lean to the torso to prevent foot clipping; resize ridge geometry to each scenario's collision region.
- [test] Pass all nine suites: 125,600 group clearance checks, 508 animated-pose/timing checks, 1,007 individual-actor checks, 21 viewport checks, and scripted victories in all three scenarios.


- [feat] Add R/command-deck retreat with separate group destinations, no firing during withdrawal, and paid recovery after disengagement at a safe staging area.
- [feat] Suppression delays firing and blocks friendly capture; enemy ground units respond to team-visible contacts, withdraw at low health, recover, and return to their original positions.
- [fix] Preserve YIELDING movement feedback and guard failed enemy reinforcement placement.
- [ui] Add retreat help, suppression bars, and recovery labels. Keep Tab for select-all.
- [test] Pass 15 tactical checks, 19 viewport input checks, 95,828 geometry/clearance checks, simulation/effects regressions, and 75.1-second scripted victory. The short victory remains evidence that deeper match design is needed.


- [verify] Close the playable MVP with 94,801 geometry/clearance checks, complete mission victory, final equipment/battle screenshots, and 14.130 ms frame p95 at 1080p on Apple M4 Pro. Record the 101.229 ms synthetic-input tail as a remaining measurement shortfall.

- [fix] Preserve authored hull and roof surfaces when batching indexed/unindexed meshes; add equipment triangle-preservation regressions.

- [feat] Build Coastal Spear: a playable Godot 4.5.1 tactical mission with infantry, armor, UAVs, gunships, naval support, cover, vision, suppression, capture, supply, reinforcements, and terminal states.
- [feat] Add RTS selection/orders/groups/queues, camera, minimap, briefing, tactical pause, reinforcement feedback, and restart.
- [fix] Implement model-footprint navigation, safe formations/deployment, swept body clearance, shared scenery bounds, and separate aircraft altitude bands.
- [art] Replace primitive equipment with original military-inspired models; add an angled camera, textured ground, industrial scenery, and revised water/vegetation.
- [feat] Add pooled flashes/impacts/sparks/fire/smoke, movement dust/wakes, animated water, and synthetic combat audio.
- [perf] Cache visibility/minimap data, batch geometry and paint, instance vegetation, and use spatial buckets for movement neighbors.
- [test] Add automated simulation, viewport input/restart, mesh/clearance stress, particle lifecycle, full mission, screenshot review, input timing, and rendered benchmark workflows.
- [docs] Keep expert review decisions and limitations in the review ledger; update architecture, launch instructions, issue history, and active child plans.

- [docs] Initialize the eight-file Codex-first development scaffold with AGENTS.md and linked tracking documents.
- [docs] Record the Godot modern-warfare RTS vision, including infantry, land, air, sea, drones, tactical terrain, accessible squad controls, and quality/performance ambitions.
- [docs] Seed the first tactical skirmish plan, milestone exit gates, proposed architecture, and provisional performance targets; explicitly distinguish planned systems from implemented features.
- [docs] Verify required scaffold files and local Markdown links. No game code or runtime checks exist yet.

