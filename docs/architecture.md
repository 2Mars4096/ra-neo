# Architecture

## Implemented stack

- Godot **4.5.1-stable**, GDScript, GL Compatibility renderer, 2× MSAA.
- Local single-player 3D scene; elevated orthographic camera; mouse/keyboard UI.
- Fixed 30 Hz authoritative simulation. Effects and HUD run on rendered frames.
- Development and graphics checks run on macOS / Apple M4 Pro. Other platforms are not validated.
- Original procedural geometry, shaders, generated material atlas and synthesized audio. No external asset dependency, physics plugin, or third-party framework.

## Modules

| File | Responsibility |
|---|---|
| `project.godot`, `scenes/main.tscn` | Engine settings and entry point |
| `scripts/simulation.gd` | Commands, squads, damage, targeting, knowledge, suppression, economy, objectives, opponent waves, terminal states |
| `scripts/cover_behavior.gd` | Bounded individual shelter search, reservations, commitment and routes for autonomy scenarios |
| `scripts/terrain.gd` | Shared scenery definitions, cover/visibility, clearance-aware domain navigation |
| `scripts/battle.gd` | Input dispatch, camera, scene synchronization, order feedback, fog, effect events, benchmark |
| `scripts/hud.gd` | Briefing, command deck, selection/range/order overlays, minimap, results |
| `scripts/unit_models.gd` | Original military-inspired equipment meshes and materials |
| `scripts/visuals.gd` | World geometry, instanced vegetation, water/terrain shaders, rigid-mesh batching |
| `scripts/effects.gd` | Fixed 640-slot particle pool, effect timing and synthesized combat audio |
| `resources/units.json` | Unit roles, combat/movement stats, prices, visible member counts, radii, and flight altitude |
| `tests/`, `tools/check.py` | Behavior, input/restart, clearance, effects, playthrough, and rendered reviews |
| `tools/play.sh`, `Play RA Neo.command` | Source-project launchers; not exported standalone binaries |
| `artifacts/` | Generated measurements and review screenshots |

## Simulation and navigation

Squads remain command/navigation groups. Infantry soldiers now have independent positions, health, weapon cooldowns, target acquisition, targeting, facing, suppression, hit reactions, and casualties in `scripts/infantry.gd`. They follow stable local slots inside a conservative group envelope, with terrain and peer-separation checks; the showcase adds bounded local cover selection, but not independent long-range pathfinding. Squad HP is the sum of surviving members. Repair heals living soldiers and never resurrects casualties. Ground, sea, UAV, and helicopter bodies have distinct collision layers. The UAV and helicopter use altitude bands above the tallest scenery. Collision radii cover the actual mesh vertices, including guns and rotors, rather than only the chassis.

Navigation uses Godot AStarGrid2D, with cached one-meter grids per movement domain and radius. Paths only simplify when the entire footprint clears geometry. Footprint tests include ridges, warehouses, shared tree positions, piers, containers, objective poles, map edges, and coastline. A spatial hash narrows dynamic avoidance checks; swept movement prevents bodies stepping through each other. Deployment and formation slots reserve safe space. Crowded units may yield; this is not a full rigid-body vehicle or infantry navigation simulation. In autonomy scenarios, an infantry section's definition radius (2.65) is only its terrain envelope. Against other units it uses `Simulation.crowd_radius` (2.0) for spawn and slot spacing, and its soldiers' bodies for contact: anchors skip other sections, vehicles test soldiers, and detours avoid soldiers. Cross-section soldier clearance is 0.7 x body sum.

Team knowledge is updated every 0.3 seconds. Ground line of sight respects blockers; elevated reconnaissance can reveal beyond them. Targeting still respects weapon line of fire. The fog/minimap terrain field is cached by observer cell; target detection uses current positions. Explicit pursuit remembers the last visible target position rather than tracking hidden live movement.

Combat uses the explicit seven-by-seven effectiveness matrix in `resources/combat.json`. Eligibility, slant range, acquisition, seeded hit probability, and on-hit damage are separate stages. Rifles cannot damage armored hulls; a successful rifle hit disables the small UAV. Motion/range/suppression affect accuracy, cover mitigates infantry damage, and front/side/rear facings affect eligible armor damage. Resolution occurs immediately at the shot event; projectile travel remains presentation. See `docs/combat-design.md`.

## Presentation and performance

Rigid parts are merged per articulated joint, carrying paint in vertex colors. `scripts/unit_animation.gd` drives individual leg/upper-body/weapon joints, road wheels, turrets, barrel recoil, helicopter/UAV rotors, aircraft lean, and ship roll from authoritative state, displacement, and simulation time. Vegetation is instanced. World materials batch repeated detail; the minimap uses a cached texture. Visual effects reuse a fixed particle pool rather than allocating a node per particle. Expensive navigation grids are prepared during mission setup.

The benchmark forces a 1920×1080 render target even if the desktop clamps the window size. Reports include actual render/window dimensions, adapter, engine, frame p50/p95, simulation p95, draw calls, and force size. This is an editor-binary local benchmark, not a release-build hardware certification.

## Verification and references

Run `python3 tools/check.py`. The wrapper checks result markers and script errors as well as exit status, because Godot can return zero after a script load failure. Interactive commands are in the README. Tests use sampled scenario checks; they do not prove absence of every possible clipping or navigation problem.

Built-in engine practices: [AStarGrid2D](https://docs.godotengine.org/en/4.5/classes/class_astargrid2d.html) and [MultiMesh instancing](https://docs.godotengine.org/en/4.5/tutorials/performance/using_multimesh.html). Repository tracking remains in `docs/` with hierarchical plans; Git has not been initialized.

Mesh batching indexes every source surface before appending it, preserving both primitive and authored shell triangles. The clearance suite also verifies pre/post-batching triangle counts for each equipment type.

## Tactical recovery increment

Retreat orders use existing footprint-aware routing and group formation slots, move 20% faster, and disable firing. Recovery is automatic within 10 world units of the team's domain-specific rally point, with no active order, six seconds without damage, and no team-visible enemy within 24 units. It restores up to 6 HP/s; friendly repair costs 0.25 supply/HP, while enemy repair has no shared budget. Heavy suppression multiplies the next firing interval by 1.8 and prevents friendly capture progress. Ground defenders reconsider idle responses every three seconds using team-visible contacts within 26 units; low-health units withdraw, recover, and return to their original position. This is local behavior, not a strategic planner.

## Scenario and weapon presentation

`resources/scenarios.json` defines six selectable fictional landscapes/modes, obstruction/wood/ruins/mud rectangles, sector names, and hold duration. Scenario selection on the briefing reloads the scene; restart retains the selection. Ruins give infantry cover; soft ground halves ground movement speed. Ground shader patches use those same rectangles. Navigation grids use terrain travel-time weights; direct shortcuts and smoothing compare sampled travel costs as well as footprint clearance.

Shots require initial target acquisition. Each rifle soldier fires separately with a fraction of the old section damage; the AT team consists of a launcher operator and rifle assistant. Damage and casualties resolve at the shot event. A bounded 128-entry projectile presentation queue renders travel and delayed impacts within three fixed pools (480 volume, 256 glow, 48 ground instances); it does not implement physical projectile hit detection. Benchmark runs ignore command input and report simulated time/sample count to distinguish active simulation from accidental pauses.

## Interference and congestion

The industrial scenario config enables an EXCHANGE area jammer. `comms_blocked` gates all remote orders including stop/retreat and disables sensor uploads. `contact_known` uses local observation for disconnected combat and pursuit. Existing orders survive loss of radio. Capturing the objective disables the emitter. Friendly position tracking remains available as a usability abstraction. The HUD displays link loss and the pre-briefed interference footprint.

After 1.5 seconds blocked, moving groups may replan around nearby bodies at most once every three seconds. `terrain.path` temporarily marks dynamic exclusion circles on its cached grid, restores those cells before returning, and respects them during path simplification. Swept geometry/body clearance remains authoritative.

## Scenario identity and stable vehicle motion

Scenario config now supplies objective coordinates, landscape style, and harbor presence as well as obstacle/cover geometry. Terrain poles use those objective coordinates; Fields disables both rendered and collidable harbor props. The ground shader and building generator select rural parcels/barns or asphalt/flat-roof urban blocks. Scenario `shore_x` and optional `size: [width,height]` define the shoreline and extent; omitted size retains 96×72. Tracked hull presentation turns at a bounded rate with no artificial vertical bob; turrets remain independent. Automatic target acquisition retains an eligible target until lost, while avoidance scoring penalizes heading reversals.

## Painted miniature materials

`shaders/miniature.gdshader` is shared by equipment and batched solid scenery. Surface colors are baked into vertex colors before joint-level merging. Broad paint variation, upper-face highlights, matte response, and softened light bands provide the initial miniature style without adding geometry or per-part draw calls. Ground/water retain their dedicated shaders.

## Canal Watch integration

`TacticalDirector` overlays bounded maneuvers on retained player orders for the showcase's land units. Accepted replacement commands cancel maneuvers; hold/retreat constrain them. Decisions use known contacts, team support, commitments and deadlines. Support cooldowns and arrival handling prevent indefinite wait loops.

Showcase infantry reserve nearby cover and check their swept movement against terrain, soldiers and vehicles. Long-range navigation remains squad based. Procedural feet preserve world contact during stance; this is flat-ground animation, not skeletal IK. Vehicle speed/facing are smoothed; this is not a physics drivetrain.

`weather.gd` supplies a deterministic front: rain builds at 25–40s, clears at 105–130s, soil dries by 230s. Rain reduces sight to 80% in discrete bands used both for contacts and cached fog. Wet open soil loses up to 12% speed; mud loses 25% of its dry speed; authored firm roads/yards retain full speed. Cached route weights refresh at wetness bands without rebuilding obstacle geometry; actual traversal speed uses live wetness. These are gameplay approximations. `weather_visuals.gd` uses 256 fixed rain instances driven by simulation time, so pause freezes rain; smoke wind does not change authoritative projectile damage.

The showcase uses varied roof/facade geometry and `architecture.gdshader` for plaster, tile and metal surfaces. Equipment batching encodes finish in vertex-color alpha (opaque shader): paint, metal, rubber and glass retain distinct roughness. Geometry and shader details are original. Existing three scenarios retain layout and combat behavior; shared equipment material improvements apply globally.

### Firing readiness and posture
Showcase soldiers settle, turn, crouch and acquire aim before firing. Reloads and motion reset preparation; each actor keeps separate timing. Pinned actors can go prone only if a 1.15-unit circular footprint clears nearby bodies and terrain. The increased footprint participates in movement checks. Rising delays movement. Building exterior bands join woodland/ruins as local cover candidates; solid buildings still block firing lines. Cover protection remains an abstract band, not per-material penetration or building interiors.

Legs now have knee and foot joints. A two-link flat-ground solve bends knees toward the front and keeps boots level through stance; the prone pose uses a separate joint configuration. No skeletal skinning, uneven terrain IK, vaulting or crawling system is claimed. Distant-group broad-phase rejection uses a conservative 7.2-unit bound around an actor sweep; precise collision tests still decide nearby clearance.

## Classic skirmish

`scripts/classic.gd` owns the fifth mode's economy, building placement, construction, power, production queues, harvesters, enemy purchases and all-structures-destroyed outcomes. `resources/classic_units.json` extends definitions only for this mode. Existing tactical scenarios keep their reinforcement/flag rules.

Finite fields lose stock when gathered; harvesting income arrives when cargo returns to a completed refinery; the existing 35-credit player kill bounty is retained. HQs provide basic power; shortages slow production to 35%. Each producer has a five-item queue, charges on enqueue, refunds the last item on cancellation, and waits when its local exits are occupied. Destroyed queues are lost. Construction creates vulnerable structures immediately and refreshes navigation/sight caches; completed structures enable production. Substantial scenery and constructed structures use shared blocker geometry. Small visual trim does not grant cover.

The enemy buys from its own wallet, builds legally, replaces harvesters with queued replacements counted, and attacks the disclosed starting-base region or observed structures. This is a deterministic skirmish opponent, not an adaptive strategic planner. Ground attacks use reachable standoff positions for blocked structure footprints. Airfield/naval production and research remain later work.

## Scaling foundation

Unit IDs resolve through an authoritative dictionary populated by spawn; individual records remain shared with the ordered unit list. Combat and sight acquire nearby candidates through the existing 8-unit spatial buckets across all collision layers, then applies unchanged visibility, weapon and hit rules. A squad shares its candidate list across individual soldiers. Combat query radius includes actual member displacement, and sorted IDs preserve deterministic tie order. Live movement maintains buckets; direct outside-tick calls fall back to the exhaustive reference. Fog-cell unions skip repeated observer cache keys within an update. Small scenes below 64 group records also retain the cheaper simple scan. `tests/test_spatial_targeting.gd` compares seeded combat with the exhaustive path and measures synthetic query scaling; it is not full large-battle validation.

### Individual shelter routing
In autonomy scenarios, actors may route within a 10-unit squad leash to separately reserved shelter slots. Wall destinations must screen an observed threat; vegetation/rubble remain abstract partial cover. At most half a section seeks at once; squad movement waits during seeking/settling. Explicit move/hold/retreat and group maneuvers constrain local initiative. Bounded failed attempts retry, occupied shelter is retained, and actors settle before firing. This is local AStar routing, not independent world-scale soldier planning.

### Authentic diorama surface pass
Architecture uses original world-projected procedural plaster/masonry, damp, tile and oxidation patterns with screen-space surface-gradient relief. Equipment keeps joint batching with restrained dust and wear. Ground aggregate fades with pixel footprint. Facade trim remains within clearance padding; no changed navigation or destruction model.

### Structural scenery and display interpolation
`ruined_building.gd` builds impassable collapsed building variants with upper openings, remnant floors and debris. Showcase buildings merge by material. `battle.gd` snapshots positions before fixed ticks; rendering interpolates group and soldier positions without changing simulation records. Paused display uses authoritative positions. All three generated art directions are accepted; integrated revamp validation is tracked in plan 6-3.

### Road-led scene and sidebar revamp
`road_network.gd` reads authored named destination nodes and width/purpose edges from scenarios. `environment_detail.gd` renders the same capsules used by terrain road classification; old showcase shader roads are removed. This is a constrained authored network, not a general town generator. `architectural_block.gd` builds shop, farm/service-yard and workshop families within solid parcels; yards remain impassable. Weather updates shared cost layers and cached land-grid weights without recreating collision grids.

HUD uses a fixed-width right command sidebar and thin resource rail. Actual opaque regions govern hit testing; `battlefield_rect()` defines unobstructed annotation/minimap bounds. Original equipment portraits are baked offline by `tools/generate_hud_portraits.gd`, loaded once as PNGs, and require no live preview renderers. The minimap caches a road mask from the shared network. Camera wheel/pinch zoom uses frame-rate-independent smoothing over 24–84 orthographic size; HUD/modal input is excluded. Normal rendering is capped at 60 FPS; the declared benchmark explicitly removes this cap. Animation caches node references and avoids per-soldier dictionary copies while preserving authoritative simulation.

Named mobility profiles distinguish infantry, tracked and wheeled terrain penalties. Simulation movement, individual shelter routes and tactical maneuvers pass the same profile; grid caches include profile as well as radius/domain. Physical clearance and movement domains govern access independently of cost. These are explicit gameplay multipliers, not measured traction physics.

Foliage shares opaque leaf-cluster meshes through MultiMesh, avoiding alpha-card overdraw. Fine articulated mesh shadows are suppressed above camera size 45 and restored closer; body/building shadows remain. Shadow changes do not alter mesh visibility, collision or animation.

### Shared sampled materials and gap orders
Original generated assets/materials/diorama-atlas.png supplies albedo detail to equipment, plaster, ground and road shaders. Shared sampler and batched material instances preserve draw submission structure; mirrored quadrant interior UVs and mipmaps limit seams/shimmer. Roughness and canvas weave remain authored. Road segment/junction materials share world coordinates.

Open-ground land commands whose desired position cannot fit the unit search at most six units for a reachable safe alternative. Solid-parcel/water clicks remain invalid. Formation fallback and displacement of crowded spawns from legal origins check route connectivity. This does not shrink units, unlock fenced yards or implement narrow-column movement.

Road-purpose-driven flush paving, gutter/grate and crossing details are merged into existing static batches. These flat details create no new collision. Larger roadside objects are not implemented by this pass.

RoadsideProps uses a small shared authored layout for cars and lamps. Terrain includes their conservative rectangles in static navigation; rendered components fit those footprints. Models batch once per prop without live lights. Repeated batching preserves encoded vertex colors and finish. Baked palettes use a partially linearized art response; ambient/sun colors and ground saturation are calibrated visually, not physically measured. A second generated atlas adds tile, sheet metal, brick and canvas.

### Actor collision and presentation refinement
A4-unit actor-body index stores references to individual soldiers and land vehicles. It rebuilds each tick, updates immediately after each actor move, and accepts mid-tick spawns. Swept local queries retain the exact collision tests; an exhaustive mode remains for equivalence fixtures. Steering candidates which cannot beat the current score skip collision evaluation. Contact/weapon eligibility is shared within a squad combat call while range, line of fire, casualties and firing remain individual.

At camera size>45, infantry keep their animated meshes but use one instanced soft contact-shadow draw instead of many small shadow-map submissions. Close view restores full shadow casting. No health/identity/behavior aggregation. Actual MSAA is2×. Benchmark begins after first frame, uses a20s run with the first2s discarded; it records driver-independent script cost, engine monitor time, memory counters and VSync mode.

Parcels retain existing collision footprints while using varied connected masses and courtyard/service details. Foliage keeps128 triangles per cluster with tapered folded geometry. Materials remain original sampled/procedural hybrids calibrated in GL Compatibility; alternative renderer validation does not imply identical color response.

### Scenario dimensions and actor return recovery
`terrain.world_size` is Vector2; `terrain.fog_grid_size` is Vector2i with ceil(size/2); fine navigation uses ceil(size) cells. SIZE/GRID constants remain legacy defaults. Cached weights and temporary actor exclusions use instance bounds. Fog, minimap world conversion and camera pan use the same extent. Camera zoom limits remain 24–84. Terrain construction optionally accepts a complete config override for isolated fixtures.

Group movement retains conservative footprint AStar routes and local steering. Actors can cache bounded return routes within their ten-unit leash, with stable-goal retries at one-second intervals. An anchor pauses for reunion, then resumes its retained command. Seeking shelter is allowed to finish until stalled; no actor teleport or clearance reduction. See plan 9-1 for regression evidence and remaining group congestion. This changes behavior and does not establish a speedup.

## Riverside authored layout and effect integration

Scenario `architecture` entries align with parcel indices and select explicit building design/facing. `districts`, `footpaths` and `resource_fields` express authored land-use, approaches and economies; they do not imply a generic procedural town generator. World extents drive water, weather, ground, fog and camera. Weighted cached AStar remains authoritative; bounded actor regroup paths and local congestion recovery complement it without teleporting or bypassing swept clearance.

Environment catalogue entries distinguish implemented, library-ready and planned variants. Library models have local footprint contracts and no implicit collision/cover: placement must satisfy existing blockers or explicitly integrate new shared terrain data.

Effects use volume/glow/ground MultiMesh pools, 128 projectiles, 96 delayed cues and 12 wreck emitters. Cosmetic travel delays impact presentation; authoritative damage still resolves at the shot. Battle passes launch/impact water classification and target kind. Native billboard rendering must be checked in addition to headless capacity tests.

## Callable environment asset registry

`asset_library.gd` unifies JSON-backed street, rural, waterfront and battlefield builders with adapters for existing architectural/roadside families. `environment_palette.gd` isolates environmental color from mutable faction palettes. Each ID has a placement envelope and context; emitted render bounds are measured separately. Placement validation reads context tags, receiving drainage and entrance access zones, preserving conservative whole-footprint blocking for overhead assemblies pending part-level integration. Geometry creation alone installs no navigation/physics.

`tools/asset_gallery.gd` supplies native category browsing, enlarged/rotated inspection and shared-scale comparison; native capture writes category sheets, per-model previews, metadata and source hashes. `tools/build_asset_review.py` creates the offline search/filter review from those artifacts. No general visual map editor is implemented; the harbor town is generated deterministically by `tools/build_harbor_map.py` from district rules.

## Field Operations mode

Riverside (scenario5, now the default) uses `field_ops.gd` and `field_units.json`. `sim.field_ops` is populated while `sim.classic` stays empty. One supply balance funds off-map reinforcement spawning and engineer construction. The old classic mode remains as hidden scenario4 and frozen legacy test fixtures.

Engineers use three articulated infantry actors and explicit construction assignments. Field units are stationary, destroyable structures with `build_left`, builder/work-point state and shared rectangle blockers. Completed sandbags provide terrain cover; observation adds normal sight; repair/aid apply disengaged healing without resurrecting soldiers. Construction appearance is synchronized by `field_models.gd` from authoritative progress.

Non-solid engineer works (wire, hedgehogs, trench, berm, net) are terrain zones: `terrain.field_zones` hold per-profile speed multipliers, cover classes, concealment and a berm front, indexed in 8 m buckets. Their units use collision layer `field_zone`, so they never act as bodies. Hedgehogs additionally make navigation cells solid for tracked/wheeled grids and `movement_clear` refuses vehicle entry. Zone changes refresh only local navigation weights/solids. A completed, unthreatened and route-connected forward supply point replaces the land insertion for purchases.

Harbor city buildings come from `city_buildings.gd` (design table, height caps, dispatch) with `city_buildings_urban.gd` and `city_buildings_works.gd` as parametric builders; decor comes from `assets_city.gd`/`assets_city.json`. Harbor props render as MultiMesh groups and buildings are chunk-merged per ~96 u tile. Rules: [harbor-city-design.md](harbor-city-design.md).

HUD terrain classification is cached by `minimap_background.gd`, invalidated by map/dynamic geometry changes; fog tint still updates. Navigation weather weights refresh lazily per requested grid. Proposal paths reuse cached navigation with conservative temporary exclusions rather than reconstructing whole grids for every hover. These CPU-work reductions are distinct from native frame-rate acceptance.
