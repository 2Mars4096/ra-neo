# For Every Dawn

A playable, local single-player Godot RTS prototype about securing a coastal corridor with infantry, armor, reconnaissance drones, gunships, and naval fire support. Inspired by the pace and readable command of classic RTS games, with original procedural models, a painted military miniature visual direction, and a modern military setting.

## Play

Requires **Godot 4.5.1**. On this Mac, double-click **`Play For Every Dawn.command`**, or run:

```sh
./tools/play.sh
```

Alternatively, import `project.godot` in Godot and press F6 on `scenes/main.tscn` or F5 for the project. The launcher detects `/Applications/Godot.app`; elsewhere set `GODOT_BIN` to the engine executable. No third-party runtime packages or asset downloads are required.

Upgrading an older checkout: [Godot's per-project user-data folder](https://docs.godotengine.org/en/4.5/tutorials/io/data_paths.html#accessing-persistent-user-data-user) now uses `For Every Dawn`. Local preferences start fresh; previous settings and diagnostic reports remain in the old folder.

A new campaign opens in **Black Sea Harbor**; an existing campaign returns to its last operation briefing. Press **Deploy**, or open **Region** to choose one of five independent battlefields on the Black Sea Coast atlas. One supply pool buys off-map reinforcements and engineer-built support. There are no factories, refineries, harvesters or power requirements in this mode. In Harbor, capture **Harbor Approach**, **Old Town** and **Freight Yard**, and hold all three objectives uncontested for **90 seconds**. You can prevent its enemy reserve from deploying by destroying all its command posts and ammo depots before it launches.

Select the **engineer section**, choose **Cover**, **Observation**, **Repair** or **Aid**, then click a visible clear site. Supply is charged only for an accepted site. The engineer must reach its work position and remain available while construction progresses. New orders pause work; unfinished sites can be resumed by an available engineer or cancelled for the unused-cost refund. Completed support can be destroyed.

| Field work | Supply / work time | Function |
|---|---|---|
| Sandbag cover | 60 / 8 s | Infantry cover around its perimeter |
| Observation post | 90 / 10 s | Ground vision, subject to terrain and weather |
| Repair point | 140 / 15 s | Repairs nearby land vehicles after disengagement |
| Aid post | 110 / 12 s | Heals surviving infantry; no resurrection |
| Concertina wire | 40 / 6 s | Slows infantry; tracked vehicles crush it |
| Anti-tank obstacles | 70 / 10 s | Hedgehogs stop tracked and wheeled vehicles; infantry pass with cover |
| Fighting trench | 50 / 10 s | Infantry cover inside the trench |
| Vehicle berm | 60 / 12 s | Hull-down: less damage from ground fire to the front and sides |
| Camouflage net | 40 / 6 s | Units underneath are spotted at half range while not firing |
| Forward supply point | 150 / 18 s | Land reinforcements arrive here while it is safe and connected |
| MG bunker | 180 / 22 s | Concrete pillbox that fires on and pins infantry |
| AT gun pit | 160 / 16 s | Dug-in anti-tank gun against armour and boats |
| Command post | 130 / 16 s | 28 m observation |
| Ammo depot | 120 / 14 s | Supply dump (the enemy's counterattack depends on its own) |

Press **T** while placing wire, obstacles, trenches or sandbags to turn them 90°. Drag while placing these to lay a whole line (nets: drag an area); cost scales with the number of segments and the engineers build them in turn. Reinforcement tiles queue: click repeatedly for several units (paid on click), right-click a tile to remove one with a refund.

On Black Sea Harbor each objective is a prepared enemy position: wire, trenches, an MG bunker, AT guns, hedgehogs and garrisoned defenders. Destroy **both enemy command posts and both ammo depots** to prevent further reserve and assault-wave spawns; forces already deployed remain in the battle. The current assault schedule starts at **90 seconds**, repeats every **95 seconds**, and allows up to **10 waves** while enemy logistics survives.

Harbor’s initial force has **3,200 supply** and **6/sec** base income; extra engineer sections cost **120**. Later campaign deployments use the surviving force and saved supply balance. Scenario budgets, infrastructure income and regional benefits remain provisional balance values. Six earlier scenario configurations remain as hidden development and regression fixtures. The previous classic economy is deferred for future work.

## Regional operations and editor

The atlas offers five separate operations. They do not need adjacent boundaries or matching roads. Select an area, inspect its briefing, then deploy. **Region** pauses the current battle; returning resumes it. Choosing another battlefield during play asks you to **Withdraw and open briefing**: surviving mobile forces and unspent supply carry forward while that battle’s tactical state is discarded.

| Battlefield | Size | Tactical problem and local infrastructure | Final hold |
|---|---|---|---:|
| Black Sea Harbor | 1024 × 768 | Dense urban fighting and port approaches; destroying enemy command posts and ammo depots stops new dispatch | 90 s |
| Bayhead Rail Valley | 448 × 320 | Station adds +2 supply/s; sorting yard adds +4/s and connected forward arrivals; eastern junction cuts enemy dispatch | 75 s |
| Limestone Pass | 448 × 320 | Infantry climb the ridge lookout while vehicles use gentler routes; upper hamlet adds +2/s; hamlet and crossroads together cut dispatch | 45 s |
| South Inlet | 448 × 320 | Shore control and a ship in the marked sea lane jointly open +4/s coastal supply and enable the final hold | 60 s |
| Windbreak Fields | 576 × 384 | Open fields, windbreaks and three maneuver corridors; grain exchange adds +3/s and forward arrivals; east checkpoint cuts dispatch | 55 s |

All land objectives must remain owned and uncontested during the final hold. The existing reserve-resolution condition also applies. Local facility benefits stop when their required positions become contested or are lost. A cut route stops future dispatch; enemy units already on the map remain active. Inland operations accept land and air forces. Harbor and South Inlet also accept ships.

**Limestone Pass now has walkable elevation.** Ground height affects sight, fire, travel speed and the slopes each mobility class can use. The lookout’s steep approach favors infantry; the upper hamlet has a broader terrace and graded vehicle access. Other maps keep their authored flat ground. Heights confer physical observation and route advantages, without an artificial damage multiplier.

### What the campaign remembers

Deployment checkpoints and completed outcomes are saved locally. Survivors replace the next map’s authored starting army. Soldier casualties, wounds and remaining bleed time, vehicle integrity and component damage, ammunition, fire and flooding carry across deployments. Units that cannot enter a battlefield—such as ships on an inland operation—wait in reserve for a compatible map. Paid reinforcements that have not arrived are refunded once when the operation ends.

Victory secures a location and grants its benefit on later deployments: Harbor **+1 supply/s**, Rail Valley **+2/s**, South Inlet **+1/s**, Windbreak Fields **+1/s**, and Limestone Pass **+45 seconds before the first enemy reserve dispatch**. Each location contributes once; replaying it does not stack its reward. Withdrawal or defeat releases that location.

**Retry operation** after defeat restores the deployment checkpoint. **New campaign** in the atlas requires confirmation before resetting saved forces, supply and ownership. The save covers operational progress; it does not restore a mid-battle world. Closing during a battle returns to its deployment checkpoint. Enemy positions, orders, constructed works, destruction and elapsed tactical time reset on redeployment, and parked reserves do not simulate while off-map.

### Map editor

The editor covers **Bayhead Rail Valley, Limestone Pass, South Inlet and Windbreak Fields**. Double-click **`Map Editor.command`** on macOS, or run:

```sh
./tools/edit_region.sh
```

Draw or reshape roads, railway lines, water, districts, solid ridges and walkable elevation. The elevation inspector sets plateau height and ramp width; buildings need level terraces. The editor also supports landmarks, registered props, physical footprints, undo/redo and blueprint import/export. Expand **Operation rules** in the battlefield inspector to edit logistics and mission prerequisites. **Preview** validates without saving; **Save & build** rejects invalid or stale edits before writing the source and playable map. Redeploy to load the result.

See the [regional guide](docs/regional-map.md) for campaign rules, editor controls, geography sources and verification. Harbor retains its original generator. Rails and parked wagons remain static scenery; moving trains, bridges, tunnels and amphibious unloading are not implemented. Human balance, long-session play and hardware performance remain open acceptance work.

## Controls

| Input | Action |
|---|---|
| Click / drag | Select a section / box-select |
| Shift + select | Add/remove selection |
| Right-click ground / visible enemy | Move / attack |
| A, then click | Attack-move |
| Shift + order | Queue orders |
| S | Stop and hold |
| R | Retreat to staging area; safe recovery costs supply |
| Ctrl or Cmd + 1–9 / 1–9 | Assign / recall group |
| Tab | Select all sections |
| Arrows / screen edges | Pan |
| Wheel or trackpad pinch / F | Smooth zoom (24–220 on regional battlefields; 24–84 on small legacy maps) / focus selection |
| Minimap left / right click | Pan / issue order |
| Space / Esc | Tactical pause; Esc also cancels targeting |
| F1 / M | Guide / mute audio |
| Region button | Browse the coast; return to the current battle or choose another operation |

Retreating units stop firing and withdraw faster. In Field Operations, use aid/repair posts to restore health after disengagement; rally-point healing belongs to the older tactical modes. Heavily suppressed sections fire more slowly and cannot advance capture progress.

The command deck shows supply, reinforcements, selected-unit health/state, and mission progress. Selected orders have destination markers; a single section shows its weapon range or UAV sight radius.

Rifles cannot chip away at armored hulls. The small UAV is hard to hit but disabled by one successful rifle hit; AA provides better tracking and is recruitable. In the hidden **Urban** fixture, the marked EXCHANGE jammer blocks new orders and reconnaissance uploads. Units keep their last orders and defend locally; capture EXCHANGE to restore communications. See [combat rules and limitations](docs/combat-design.md).

## Implemented

- Terrain-aware land/sea routing, woods cover and movement costs, sight blockers, fog of war, shared reconnaissance, suppression, and rear-armor damage.
- Rifle and anti-tank sections, tanks, anti-air vehicles, drones, gunships, and corvettes. Infantry are commanded as squads, with individually simulated soldiers, casualties, targeting, and firing cadence.
- Enemy defenders and reserve waves, supply/purchases, objectives, victory/defeat, and restart.
- Harbor building garrisons with window fire; high-explosive building damage, breaches and collapse; infantry wounds, buddy aid and casualty movement. Severely wounded soldiers can crawl toward their section or be dragged/carried by squadmates.
- Articulated infantry, independently tracking turrets, wheel/rotor motion, recoil, damage smoke, missile trails, and terrain-sensitive movement.
- Original equipment geometry, an angled RTS camera, textured terrain, industrial scenery, muzzle flashes, impacts, sparks, explosions, delayed smoke, dust, wakes, animated water, and synthesized audio.
- Conservative model envelopes, safe deployment/formation slots, swept unit clearance, scenery clearance, and separated aircraft altitude bands.
- Five-operation regional atlas, persistent expedition and supply, unique secured-location benefits, battlefield-specific logistics, and a validated editor for four external maps.
- Walkable plateau/ramp terrain with profile-dependent slopes, height-aware sight/fire and grounded rendering, first authored on Limestone Pass.

This is a **tactical MVP**, not an AAA release. It contains eleven scenario configurations on a shared map framework: **five regional battlefields are available in normal play; six legacy fixtures are hidden**. Movement/combat and opponent behavior remain simplified, and the art is procedural. Multiplayer, tactical-world save/load, continuous regional travel, full skeletal animation and production assets are not implemented. The local operational campaign saves deployment checkpoints and outcomes. Building garrisons are abstracted; detailed room-by-room interior gameplay, general tactical crawling and vaulting are not implemented. Human usability testing and broader hardware coverage remain open.

## Verify

```sh
python3 tools/check.py
python3 tools/check.py --group regional
python3 tools/build_region_maps.py --check
python3 -m unittest discover -s tools -p 'test_regional_*.py'
./tools/play.sh --audio-driver Dummy --script tests/render_review.gd
./tools/play.sh --audio-driver Dummy --script tests/model_review.gd
./tools/play.sh --audio-driver Dummy -- --benchmark
```

Checks exercise simulation, viewport controls/restart, model clearance, bounded effects, and a complete scripted mission through normal commands. Render review writes PNGs into `artifacts/`; the equipment study is a close-up art review. Benchmarking renders at 1920×1080, excludes two seconds of warmup, and records wall-clock frame intervals over a 20-second run. The effects snapshot includes staged VFX; it is a visual review, not a separate gameplay result.

See [validation evidence](docs/validation.md), [architecture](docs/architecture.md), [review decisions](docs/review-ledger.md), [known limitations](docs/bugs.md), and [roadmap](docs/development-plan.md).

See [unit states and landscape references](docs/unit-state-design.md) for implemented cues and remaining limitations.

## Canal Watch (legacy showcase)

This scenario is hidden in normal play. Run `./tools/play.sh --script tests/showcase_launch.gd`, then press **Deploy**, to inspect the legacy fixture. Mixed land groups given attack-move can choose supporting positions, flank, withdraw under pressure and regroup toward the retained objective. New received commands replace the plan; **S** holds position and **R** explicitly retreats. Select one section to read its reason; orange routes show autonomous maneuvers, teal routes show player orders. Soldiers choose nearby cover individually.

Capture the village to trigger a warned counterattack, then secure both sectors and defend. Rain builds after 25 seconds, reduces sight to 80%, and leaves slower wet soil after clearing. Firm roads/yards retain speed; cover and buildings still affect sight and protection. The header reports weather and sight. Terrain is planar and weather/combat values are designed abstractions.

See [showcase design](docs/showcase-design.md), [visual target](artifacts/showcase-target.svg), and [validation](docs/validation.md). Automated checks are not a substitute for player review of fun, clarity or art quality.

Showcase infantry settle and face their target before firing, crouch to aim, reload individually, and go prone when pinned if their extended footprint is clear. Combat-effective soldiers rise before moving. Nearby building exteriors can be chosen as cover. The current harbor garrison and casualty systems are described above.

## Scale status

Town-sized warfare with thousands of individual troops is the later target. Current spatial targeting/sight queries and unit-ID lookup are a first optimization; synthetic query tests are separate from full-battle capacity. Black Sea Harbor is authored at **1024×768 world units**; map dimensions do not establish that troop capacity. A historical 100-entity 1080p stress result was 25.091 ms frame p95, above 16.7 ms; it is not a measurement of the current harbor build. See [the scale plan](docs/plans/9-town-scale-performance.md) and [validation](docs/validation.md).

Individual shelter movement is implemented in the current harbor operation and the hidden **Canal Watch** and **Frontier Skirmish** fixtures: idle/attack-moving infantry react to known threats, run to separate nearby shelter slots and settle before firing. Select the section to see shelter routes. Explicit Move, Hold and Retreat constrain this behavior. See the [request audit](docs/request-audit.md) for remaining work.

Halted soldiers can occupy friendly sandbags and trenches at reachable, separated positions. They abandon destroyed shelter and retry failed approaches; squadmates with valid cover can stay in place. Harbor's common rectangular building families use the visible ground walls for exterior cover and movement clearance. Low steps and loading docks block walking without acting as full-height protective walls. Custom compound buildings still use conservative parcel boundaries; see the [cover-contact review](docs/plans/14-1-cover-contact.md) for verified scope and before/after measurements.

The authentic-diorama material pass adds weathered plaster/masonry, varied tile roofs, oxidized sheet metal and equipment dust while preserving the miniature presentation. [Preview](artifacts/diorama-materials.png).

The current HUD uses a right command sidebar with minimap, reinforcements, engineer construction and selection orders. Wheel/pinch zoom operates over the battlefield, including tactical pause. Normal rendering is capped at 60 FPS; benchmark mode is uncapped. The legacy Canal Watch and Frontier Skirmish fixtures use connected road definitions shared with movement costs. This remains a procedural-art prototype; performance and art acceptance are open.

Tight open-ground move clicks resolve to a nearby reachable position when possible; the HUD reports “Nearest accessible position.” Solid building bodies and authored obstacles block ordinary ground routes; infantry can enter eligible harbor buildings through garrison orders.

Performance diagnostics: `--headless --script tests/profile_simulation.gd` measures deterministic simulation CPU work. `--script tests/showcase_launch.gd -- --benchmark` measures the rendered stress scene after first-frame startup. Render benchmarks report VSync/MSAA so differently paced runs are not confused. Distant infantry use instanced contact shadows; close zoom restores detailed animated shadows.

Navigation recovery now pauses separated sections while soldiers take bounded routes back around walls. The single-order village regression reunites soldiers and captures the sector, though group congestion remains. Scenario configs can set `size: [width,height]`; omitted size stays 96×72. Earlier navigation, fog, camera pan and minimap checks covered a synthetic 144×108 extent. Current harbor-scale acceptance is separate; see [navigation validation](docs/plans/9-1-navigation-recovery.md), [the harbor plan](docs/plans/13-black-sea-harbor.md) and [validation](docs/validation.md).

## Riverside Town (legacy fixture)

The hidden sixth configuration is an authored 144×108 battlefield with a central town, western shelter approach and eastern freight district. It now uses field operations with one supply pool, off-map reinforcements and engineers; its earlier classic-economy design is historical. Buildings have explicit family/facing choices; roads, civilian vehicles and service props use shared terrain footprints. See [design history](docs/plans/10-riverside-battlefield.md) and [field operations](docs/plans/12-field-operations.md).

Run `./tools/play.sh --script tests/town_launch.gd` to inspect this legacy map. Native review scripts are `tests/town_review.gd` (actual starting view plus explicitly fog-disabled composition inspections) and `tests/effects_review.gd` (staged effects including battle event integration).

Rifle squads default to three individually tracked soldiers in a centred triangular formation. Squad-level HP, damage budget and cost are retained; each casualty therefore removes a larger share.

## Environment asset gallery

Run `./tools/play.sh --script tools/asset_gallery.gd` to inspect the categorized library. Use the category menu, Inspect/Rotate, or shared-scale comparison. The offline searchable review is [asset-library.html](artifacts/asset-library.html). These are original engine models with variant IDs and bounds, not image mockups. Most new variants remain library-ready until authored placement and gameplay collision are installed. See [the asset contract](docs/environment-library.md).
