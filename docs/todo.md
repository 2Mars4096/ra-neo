# Todo

## Planned tactical expansion — 2026-10-27

Planning documents are prepared; implementation is not started. The user requested plans only. The [action catalogue](tactical-action-catalogue.md) distinguishes existing primitives, partial systems and new actions, with Core/Expansion/Optional delivery scope.

- [ ] [18: Tactical actions and capable individual units](plans/18-unit-tactical-autonomy.md) — master milestones, shared contracts and acceptance gates.
  - [ ] [18-1: Action framework and readiness](plans/18-1-action-framework-and-readiness.md).
  - [ ] [18-2: Infantry fire and movement](plans/18-2-infantry-fire-and-movement.md).
  - [ ] [18-3: Grenades and urban actions](plans/18-3-infantry-grenades-and-urban-actions.md).
  - [ ] [18-4: Coordination and support requests](plans/18-4-coordination-and-support-requests.md).
  - [ ] [18-5: Engineering and field fortifications](plans/18-5-engineering-and-field-fortifications.md).
  - [ ] [18-6: Vehicles and ground support](plans/18-6-vehicles-and-ground-support.md).
  - [ ] [18-7: Air and drone operations](plans/18-7-air-and-drone-operations.md).
  - [ ] [18-8: Naval and shore operations](plans/18-8-naval-and-shore-operations.md).
  - [ ] [18-9: Information and electronic warfare](plans/18-9-information-and-electronic-warfare.md).
  - [ ] [18-10: Logistics, medical and recovery](plans/18-10-logistics-medical-and-recovery.md).
  - [ ] [18-11: Command interface and feedback](plans/18-11-command-interface-and-feedback.md).
  - [ ] [18-12: Performance and validation](plans/18-12-performance-and-validation.md).

## Completed foundation and implementation

- [x] Create the scaffold-dev documentation and Codex-first repository instructions.
- [x] Implement the Godot 4.5.1 tactical mission, squad controls, terrain/combat rules, reinforcement economy, outcomes, and restart.
- [x] Add combined land, air, drone, and naval roles in the slice.
- [x] Add simulation, input, clearance, effects, and scripted mission tests.
- [x] Replace blockout units with original military-inspired equipment; add combat/movement effects and environment detail.

## Completed MVP delivery

- [x] [1: Tactical RTS vertical slice](plans/1-tactical-rts-vertical-slice.md) — playable mission and documented validation.
- [x] [1-1: Effects and clearance](plans/1-1-effects-and-clearance.md) — rendered review and clearance/performance checks passed.
- [x] [1-2: Authentic equipment](plans/1-2-authentic-equipment.md) — models rebuilt, rendered, and checked.

- [x] [2: Tactical decisions and recovery](plans/2-tactical-decisions.md) — retreat, paid recovery, suppression consequences, observed-contact responses, and UI feedback.

- [x] [3: Animation, individual soldiers, and scenarios](plans/3-animation-and-terrain.md) — articulated actors, independent infantry behavior, effects, three selectable landscapes, and validation.

## Latest completed work

- [x] [15: For Every Dawn game name](plans/15-for-every-dawn.md) — project/window title, HUD, launcher, release/report filenames, gallery labels, and documentation renamed; static checks pass (2026-10-23).

- [x] [4: Combat relationships and communications](plans/4-combat-relationships.md) — numerical counters, fragile UAVs, hit/miss resolution, interference, and regression review.

- [x] [5: Vehicle stability and scenario identity](plans/5-stability-and-map-identity.md) — tank motion and genuinely different land layouts.

- [x] [6: Painted military miniatures](plans/6-painted-miniatures.md) — accepted visual direction; shared material, palette, and lighting pass.

## Active reviewed plan

- [x] [17: Distinct battles and persistent regional operations](plans/17-regional-operations.md) — rail/road/coastal logistics, checkpointed expedition and regional ownership, shared elevation proved on Limestone Pass, and Windbreak Fields; functional and native visual checks complete, human balance/performance acceptance remains open (2026-10-25).

- [x] [16: Regional map and shared battlefield authoring](plans/16-regional-map.md) — four-operation atlas, three new physically validated battlefields and visual blueprint editor on `codex/regional-map`; functional and native visual review complete, human balance/performance acceptance remains open (2026-10-23).

- [ ] [14: Harbor city realism](plans/14-harbor-city-realism.md) — district layout, 27 building families, city decor, tier-1 engineers done; old-town continuity, microdistrict density, native review and performance open.

- [x] [14-1: Soldiers reach physical cover](plans/14-1-cover-contact.md) — reachable sandbag goals, shared physical building profiles and stale/blocked occupation recovery; native arrivals verified and 24 selected integration suites pass. The 97 complex-building fallbacks and remaining cover-cost timing failures are documented follow-ups (2026-10-20).

- [x] Harbor victory after pre-reserve logistics destruction; objective/hold, dispatched-reserve timing, and defeat precedence covered, current-game documentation corrected (7 focused suites, 1,141 checks, 0 failures; 2026-10-20).

- [ ] [13: Black Sea Harbor](plans/13-black-sea-harbor.md) — user-authorized one huge Sevastopol-inspired theatre; shared assets, polygonal bays, irregular districts and measured scale.

- [ ] [12: Field operations and smooth play](plans/12-field-operations.md) — current priority: one supply, off-map purchases, engineer tactical support, measured lag fixes.

- [x] Three-person squad timing regression resolved (test_regroup_recovery 0 failures, 2026-10-18).

- [x] [11: Structured asset library](plans/11-asset-library.md) —100 callable models/10 categories, native gallery, metadata, placement contracts and Codex/Claude review fixes.

- [ ] [10: Riverside battlefield](plans/10-riverside-battlefield.md) — authored larger town, distinct approaches, effects and category/variant library; integrated validation in progress.

- [ ] [6-3: Integrated revamp](plans/6-3-integrated-revamp.md) — team changes integrated: sidebar, shared roads/mobility, architecture and zoom; visual acceptance and 16.7 ms target remain open.

- [ ] [9-1: Navigation recovery and dimensions](plans/9-1-navigation-recovery.md) — single-order regroup and real Riverside economy/navigation checks pass; full-match and native acceptance remain open.

- [ ] [9: Town-scale performance](plans/9-town-scale-performance.md) — first spatial targeting optimization and synthetic query checks; large maps/full-battle scaling remain open.

- [x] [8: Classic RTS skirmish](plans/8-classic-skirmish.md) — user-added economy, construction, production, enemy base and annihilation victory; automated and rendered validation complete, balance review pending.

- [ ] [7: Combined-arms showcase](plans/7-combined-arms-showcase.md) — implemented showcase autonomy, local cover, articulated firing postures, terrain/weather and material pass; human review and performance acceptance remain open.

## Open player requests (2026-10-15)

- [x] Hitch reduction: spread nav-grid re-weighting (wetness change, 140-220 ms stalls) over frames and incrementally process queued path smoothing.
- [ ] Pathfinding execution: initial A* still runs synchronously; complete the shared work budget and measure remaining spikes before choosing isolated workers ([18-12](plans/18-12-performance-and-validation.md)). The earlier combined checkbox overstated background pathfinding.
- [ ] Renderer: Metal/Mobile measured 2026-10-15: engine process p95 18.6 -> 10.9 ms, frame p95 unchanged (~26 ms, sim-bound); harbor looks identical but Canal Watch and effect colours wash out (linear vs sRGB colour pipeline). Stayed on GL Compatibility; recalibrate colours before switching.
- [x] Explosion VFX: ~3x larger, layered flash/fireball/shockwave/debris/dust column, camera shake; native screenshot review loop.
- [x] World damage: buildings (damaged -> breached -> collapsed rubble, garrison casualties), field works degrade under HE, boats (flooding/engine/fire), helicopters (forced landing/crash), drones fragile, HE destroys nearby props/trees.
- [x] Vehicle follow-ups incl. re-crew/capture of abandoned vehicles: abandoned vehicles should not explode; wreck cover for infantry; field repair of components.
- [x] Player-bought drone swarm strike (HUD purchase).
- [x] Test failures fixed (garrison cover search; regroup counts occupying/in-contact cover within leash): garrison "halted section takes cover against buildings (1 of 3)"; regroup recovery (3) - design call: halted cover distance vs 2.8 m regroup limit.
- [x] Timing checks made load-robust (test_audio calibrated, test_presentation_cache controlled clock).
- [x] Large group orders: click resolves 8 slots, rest per tick (40-unit click ~5 ms idle).
- [x] Harvester jam fix + threat-aware deposits merged (see bugs.md for the trade-off).
- [ ] Testing economy: restore normal supply (1600, 3/s) when testing ends (player: keep doubled for now).
- [x] Infantry sections sent to one point spread to distinct spots; stacked idle sections step apart.
- [ ] Deferred by player: wounded marker / bleed-out countdown, rescue of stranded wounded.

- [x] Enemy uses buildings and mortar; open-ground prone; air clearance over tall structures; HARVEST LINE fixed; ~11% cheaper tick (2026-10-16).
- [x] Classic playthrough: realistic armour/Javelin + combined-arms script; VICTORY (economy unchanged).
- [x] Roadside-props corner clips fixed (published edges bent at skipped grid nodes).
- [x] engage_idle holds 4 s in cover after losing a target.
- [x] Smarter contact tactics: contact drill, fire-from-cover corner slots, shelter re-evaluation, crossfire prone, crouch in cover, one-at-a-time rushes.

## Next development priorities

- [ ] Meet the provisional 16.7 ms frame-p95 target; see validation.md for the current rainy-showcase measurement.

- [ ] Build the proposed village/ridge/port match with supply routes, forward-base choices, and strategic counterattacks; current baseline policy still wins quickly.
- [ ] Extend showcase foot planting and local cover with independent long-range soldier navigation and production animation assets.

- [ ] Repeat input-latency measurement without competing tests; investigate the 101.229 ms tail sample against the 100 ms target.

- [ ] Human playtesting of command clarity, camera framing, difficulty, and congestion.
- [ ] Production art/animation/audio pipeline, more varied terrain, and more representative battlefields.
- [ ] Larger-force navigation and performance testing; additional hardware/platforms and standalone exports.
- [ ] Extend classic skirmish with air/naval production, defenses, research and economic balance.
- [ ] Decide multiplayer and any broader campaign scope beyond the implemented lightweight regional expedition.

## Showcase acceptance remaining
- [ ] Player review: autonomy clarity, mission enjoyment, and refined art direction.
- [ ] Performance: meet 16.7 ms frame p95 in the declared busy 1080p scene.
- [ ] Later art production: bespoke characters/vegetation, richer material assets and terrain relief. Current procedural refinement is not AAA art.

## Latest player-feedback correction
- [x] [7-1: Visible shelter movement](plans/7-1-visible-cover.md) — separate routed destinations, staggered movement, settling, order overrides and HUD paths.
- [ ] Extend verified shelter behavior to the original three scenarios; implement peeking and review shelter-to-engagement transitions.
- [ ] Review remaining user requests in [request audit](request-audit.md).

## Authentic diorama art
- [x] [6-1: Weathered materials](plans/6-1-authentic-diorama.md) — plaster/masonry, roofs, metal, equipment dust, ground aggregate and facade detail.
- [ ] Bespoke damaged structures, interiors, varied vegetation and terrain assets matching the reference quality.

## Scene rebuild and reference selection
- [ ] [6-2: Scene rebuild and smooth presentation](plans/6-2-scene-rebuild.md) — structural variants and display interpolation verified; reference-quality art remains open.
- [x] User acceptance of all generated A/B/C art directions in artifacts/art-directions before further scenery expansion.

- [ ] Build one fully composed street block against [reference comparison](../artifacts/revamp-review.html), including continuous frontage, entrances, gardens and grounded materials before propagating more scenery.

- [x] Correct rejected narrow-gap orders with bounded reachable destinations and connectivity-checked deployment/formation fallbacks.
- [x] Integrate filtered generated material atlas; retain overall reference-quality acceptance as open.

- [ ] Coherent roadside objects beyond paving: lamps/signs, parked service vehicles, loading bays, fences/hedges and canal infrastructure, with shared collision.

- [x] Initial civilian sedan/service van/streetlight family with collision and native review; broader coherent streetscape still open.

- [x] Profile and halve CPU work in the100-member deterministic scene while preserving exact authoritative state; actor-index equivalence checks added.
- [x] Differentiate town/shop/farm/workshop parcels within collision envelopes; add broken construction and courtyard context.
- [ ] Complete reference-quality art acceptance; current Codex and Claude reviews both ran. Remaining gaps include connected frontage, purposeful block interiors, vegetation and equipment surface detail.
