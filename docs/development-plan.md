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

The implemented baseline uses Godot 4.5.1, GL Compatibility, desktop mouse-and-keyboard controls, and an elevated 3D camera for local single-player. The measured machine is an Apple M4 Pro. Supported release hardware/platforms, final art pipeline, battle scale, multiplayer, campaign scope, and production budget remain open. These implementation choices are provisional and can be revisited after human playtesting.

## Current improvement track

The first tactical increment adds retreat/recovery, suppression consequences, and local enemy response. Next implement the proposed village/ridge/port match and supply/forward-base choices, followed by animation and a representative art area. The 10–15 minute battle remains a design goal; current automated victories are much shorter.

The animation/landscape pass now adds individual infantry actors, procedural state-driven articulation, weapon travel effects, and three selectable fictional scenario variants. This is not the larger strategic village/ridge/port match: supply routes, forward-base choices, contextual cover autonomy, persistent wrecks, and production animation remain open.

## Current delivery focus

### Regional expansion — 2026-10-23

The user now requests a larger regional map containing distinct battlefields, grounded in believable city, transport and infrastructure layout, with editor improvements first where useful. [Plan 16](plans/16-regional-map.md) implements this increment on `codex/regional-map`: the Black Sea Coast atlas, the existing Harbor operation, and three new rail-valley, limestone-pass and coastal-inlet maps. The region establishes their geographic relationship and loads one tactical operation at a time. Persistent campaign state and continuous cross-map simulation remain future work.

The visual blueprint editor and deterministic compiler share the existing building profiles, asset footprints, road and coastline rules with runtime. New content must pass domain, placement, connection and native route checks without relaxing clearance rules. The geographic reference is the broad Sevastopol / Heraclean Peninsula pattern; detailed streets and tactical extents are original compressed layouts. Ground remains planar, rocks form solid obstacles, and rolling stock is stationary. Human balance/art review and the unresolved performance target remain separate acceptance gates. See the [regional guide](regional-map.md) and [validation](validation.md).

### Earlier delivery increments

The reviewed [combined-arms showcase](plans/7-combined-arms-showcase.md) integrates broad land-unit autonomy, individual movement, animation, a canal-village mission, and user-added terrain/weather and material improvements. Systems are proven in this fourth scenario before expanding all maps. Human play/art acceptance and the 16.7 ms performance target remain open.

The user expanded delivery to a [classic skirmish](plans/8-classic-skirmish.md): finite harvesting, construction, power, queues, enemy base building and annihilation victory. This complements the showcase rather than replacing it. Air/naval production, research and broader economic balance remain subsequent work.

## User-confirmed scale direction

The later battlefield should cover a small town and support thousands of individually tracked troops. [Town-scale performance](plans/9-town-scale-performance.md) begins with targeting queries and an explicit scaling ladder. The current fixed 96 × 72 map and approximately 100-entity rendered stress case do not establish that capacity. Preserve individual behavior while pursuing spatial queries, chunked navigation and cheaper distant presentation.

## Current authoring priority — 2026-10-14

The user prioritizes a comprehensive categorized asset library and shared placement rules before further map expansion. Complete native asset/cross-review first, then build editor/generator workflows from the same contracts. The future whole-town target is square-kilometre scale; establish world-unit/physical-scale conventions, district morphology and navigation/render budgets before claiming that scale. The current sixth map is144×108; a proposed512×384 successor is deferred, not implemented. Buildings should follow distinct historic core, residential, freight and rural patterns, not one-object-per-grid-cell spacing.

## Current battlefield economy — 2026-10-14

User defers macro economy until later. Riverside now targets a single supply currency, off-map reinforcement purchase and engineer-built tactical cover/observation/repair/aid. Factories, refineries, harvesters and power are outside the active battlefield mode. Legacy classic code is retained for future work and regression fixtures, not presented as current gameplay. Smoothness remains an acceptance requirement requiring profiling evidence.

## Large-map continuation — 2026-10-14

The user now authorizes expansion after asset-library work: one huge Sevastopol-inspired fictional harbour map combining the trial maps. This supersedes the previous map-expansion deferral. Keep single-supply field operations and engineer support. The first authored target is1024×768; geography, district composition, route correctness and native performance must be validated, not inferred from dimensions.
