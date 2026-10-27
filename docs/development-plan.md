# Development Plan

## Vision

Build a Godot RTS with the pace and approachable command of Red Alert 2, expressed through modern combined arms and an original setting. Infantry, armor, aircraft, naval forces, and drones should have complementary jobs. Terrain should create decisions about scouting, concealment, flanking, cover, and routes.

Easy control is a core requirement: the player commands intent at squad or group level, sees what will happen, and receives clear feedback when an order cannot be carried out.

## Quality and speed

Treat AAA quality as a long-term bar for cohesive art, animation, sound, interface, tactical readability, responsiveness, and stability. Establish that bar in a small representative slice before multiplying maps and units. Placeholder assets are acceptable during mechanics work and must be identified as such.

Interpret speed as both smooth gameplay and fast development iteration. Prefer a playable change that can be evaluated over a large untested subsystem. No completion schedule, budget, or achieved quality level is established yet.

## Milestones and exit gates

| Milestone | Scope | Exit gate |
|---|---|---|
| 0 — Scaffold | Instructions, tracking, game direction, first plan | Documentation exists and links resolve; complete |
| 1 — Tactical slice | One map, squad command, infantry, armor, reconnaissance drone, basic opponent | Playable objective with terrain-dependent outcomes and captured performance measurements |
| 2 — Combined arms | Aircraft, ships, shore interactions, sensors, anti-air and drone counterplay | Every domain has useful roles, clear limits, and consistent controls |
| 3 — Skirmish loop | Resources, construction, production, reinforcements, opponent strategy | Complete start-to-finish match with readable economic and combat decisions |
| 4 — Production slice | Cohesive art, audio, animation, effects, UI, onboarding | Representative map meets agreed visual and usability review criteria |
| 5 — Scale and release readiness | Larger battles, hardware coverage, settings, exports, stability | Repeatable performance and regression checks pass on supported configurations |

The [tactical slice](plans/1-tactical-rts-vertical-slice.md) now runs as Coastal Spear. Aircraft, naval support, anti-air, supply, and reinforcements are also implemented in this scenario; broader combined-arms balance remains future work; a first classic construction economy now exists in the fifth mode. Human playtesting should guide the next milestone. See [measured validation](validation.md).

## Provisional measurable targets

These are provisional acceptance targets. Actual results and measurement limitations are recorded in [validation](validation.md); they are not promises for untested hardware.

- 1080p at 60 FPS on a declared baseline machine; record p95 frame time against a 16.7 ms target and report spikes separately.
- Selection/order feedback visible within 100 ms, measured independently of travel or path completion.
- Initial profiling scenario: 20 commanded groups and approximately 100 visible individual entities, then step the load upward.
- Complete a short objective scenario using box selection, control groups, contextual right-click, queued orders, and attack-move.
- Demonstrate that a covered route and a scouting/flanking route produce distinct, explainable outcomes under reproducible conditions.

## Pending choices

The implemented baseline uses Godot 4.5.1, GL Compatibility, desktop mouse-and-keyboard controls, and an elevated 3D camera for local single-player. The measured machine is an Apple M4 Pro. Supported release hardware/platforms, final art pipeline, battle scale, multiplayer, deeper campaign scope and production budget remain open. A local checkpoint/outcome campaign is implemented; broader strategic simulation is undecided. These implementation choices are provisional and can be revisited after human playtesting.

## Current improvement track

The current increment deepens distinct battlefield decisions, carries expedition losses and supply between operations, proves elevation on the pass, and adds one open-maneuver battlefield. The 10–15 minute battle remains a design goal; controlled tests do not establish human pacing, balance or replay value. Production animation and representative hardware performance remain open.

## Current delivery focus

### Tactical action planning — 2026-10-27

The user requested a master plan and subplans for richer individual decisions across infantry, vehicles, air, naval and support units, explicitly including grenades, backup requests and trench digging. [Plan 18](plans/18-unit-tactical-autonomy.md) and its [action catalogue](tactical-action-catalogue.md) define that proposed work. This is planning-only authorization; no new action is implemented by the document set.

Proposed sequence: stabilize readiness/targeting/action ownership; prove an infantry defense slice with throwables, support and preparation; give existing vehicle/air/sea units persistent roles; then expand urban, engineering and sustainment decisions. Keep shared physical/information rules, a compact command interface and measured responsiveness in every increment. New transport classes, generalized fuel, towing, minefields, full interiors and wider evacuation remain gated optional scope. The existing regional operations below remain the implemented baseline.

### Regional operations — 2026-10-25

The user explicitly accepts independent battlefields without adjacent boundaries. [Plan 17](plans/17-regional-operations.md) continues the map branch on `codex/regional-operations`: five selectable operations, functional local supply/dispatch objectives, joint shore-and-sea control, an operational campaign, walkable pass terrain and Windbreak Fields. The earlier [Plan 16](plans/16-regional-map.md) supplies the atlas and shared authoring foundation.

Campaign saves contain deployment checkpoints and outcomes, including survivors, wounds, damage, parked incompatible units, supply and unique secured-location benefits. They do not resume a mid-battle world or simulate travel between maps. A defeat retry restores its deployment checkpoint; resetting the campaign requires atlas confirmation. This keeps the strategic layer small enough to support the tactical game.

The visual editor and deterministic compiler share runtime building profiles, asset footprints, coastlines and terrain data. Elevation authoring includes plateau/ramp controls and a level-building check. Native tests remain authoritative for profile-specific slope access. Expand further when a map introduces a useful decision and passes route, mission and visual checks; boundary continuity is not an acceptance requirement.

Geography remains an original compressed interpretation of broad Sevastopol / Heraclean Peninsula relationships. Ground relief is currently authored on Limestone Pass; rail traffic is stationary, and bridges, tunnels and amphibious unloading remain future mechanisms. Human playtesting, long-session economy, visual acceptance and the unresolved frame-time target are separate gates. See the [regional guide](regional-map.md) and [validation](validation.md).

### Earlier delivery increments

The reviewed [combined-arms showcase](plans/7-combined-arms-showcase.md) integrates broad land-unit autonomy, individual movement, animation, a canal-village mission, and user-added terrain/weather and material improvements. Systems are proven in this fourth scenario before expanding all maps. Human play/art acceptance and the 16.7 ms performance target remain open.

The user expanded delivery to a [classic skirmish](plans/8-classic-skirmish.md): finite harvesting, construction, power, queues, enemy base building and annihilation victory. This complements the showcase rather than replacing it. Air/naval production, research and broader economic balance remain subsequent work.

## User-confirmed scale direction

The later battlefield should cover a small town and support thousands of individually tracked troops. [Town-scale performance](plans/9-town-scale-performance.md) begins with targeting queries and an explicit scaling ladder. The current Harbor extent of 1024 × 768 and the historical approximately 100-entity rendered stress case do not establish that capacity. Preserve individual behavior while pursuing spatial queries, chunked navigation and cheaper distant presentation.

## Earlier authoring priority — 2026-10-14

The user prioritizes a comprehensive categorized asset library and shared placement rules before further map expansion. Complete native asset/cross-review first, then build editor/generator workflows from the same contracts. The future whole-town target is square-kilometre scale; establish world-unit/physical-scale conventions, district morphology and navigation/render budgets before claiming that scale. At that stage the sixth map was 144×108 and a 512×384 successor was deferred; later Harbor and regional-map work superseded that extent. Buildings should follow distinct historic core, residential, freight and rural patterns, not one-object-per-grid-cell spacing.

## Current battlefield economy — 2026-10-14

User defers macro economy until later. Riverside now targets a single supply currency, off-map reinforcement purchase and engineer-built tactical cover/observation/repair/aid. Factories, refineries, harvesters and power are outside the active battlefield mode. Legacy classic code is retained for future work and regression fixtures, not presented as current gameplay. Smoothness remains an acceptance requirement requiring profiling evidence.

## Large-map continuation — 2026-10-14

The user now authorizes expansion after asset-library work: one huge Sevastopol-inspired fictional harbour map combining the trial maps. This supersedes the previous map-expansion deferral. Keep single-supply field operations and engineer support. The first authored target is1024×768; geography, district composition, route correctness and native performance must be validated, not inferred from dimensions.
