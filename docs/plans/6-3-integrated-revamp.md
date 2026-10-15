# 6-3: Integrated battlefield and command interface revamp

**Parent:** [6-painted-miniatures](6-painted-miniatures.md)
**Status:** in-progress
**Goal:** Turn the accepted town/canal/village references into clearer architecture and a coherent playable RTS interface while improving presentation cost.

## Tasks
- [x] Confirm all three references; user permits a full revamp and parallel team work.
- [x] Replace oversized HUD with compact resource, selection, command and production surfaces; verify actual hit regions.
- [x] Replace repeated intact buildings with differentiated architectural families and connected ground detail.
- [x] Verify smooth wheel zoom and trackpad input, including limits and UI exclusion.
- [x] Reduce repeated animation/update work without changing authoritative simulation.
- [x] Integrate, inspect native screenshots, run behavior/input/clearance regressions, then isolated graphics benchmark.

## Ownership
Native in-session agents: hud_revamp owns HUD/helpers/layout test; environment_revamp owns environment helpers and optional showcase layout; performance_camera owns battle/animation/project settings/zoom test. Manager owns integration in visuals, test runner, rendered review and tracking documents. This is a non-Git project: changes use disjoint shared files and are reviewed together rather than Git commits. External CLI launch was unavailable because its backend DNS failed; native agents are operational.

## Acceptance
Functional controls across supported resolutions, wheel in/out, no click-through panels, surviving classic production and tactical scenarios. Inspect gameplay zoom and close detail. Keep world props consistent with collision. Report frame median/p95 and simulation p95; target remains 16.7 ms. Reference fidelity and player approval cannot be established by unit tests.

## Baseline
Latest isolated rainy 100-member benchmark: median 7.001 ms, frame p95 24.835 ms, simulation p95 10.731 ms, 3,994 draw calls. Saved artifacts/benchmark-pre-revamp.json. No claim of low resource use or thousand-unit readiness.

## Road-first correction (user steering)
The user rejected arbitrary road strips and requested a coherent map-generation sequence plus research. Reopen layout work: geography/water and destinations → connected main/local road network → parcels/frontage → buildings → dressing. Validate gameplay access and clearance before detail. A shared authored road graph will drive visible roads and road-speed classification. This is a dependency-driven showcase redesign, not a general procedural city generator or civilian traffic simulation.

### Research and decisions
- [Parish & Müller, Procedural Modeling of Cities (2001)](https://people.eecs.berkeley.edu/~sequin/CS285/PAPERS/Parish_Muller01.pdf): geographic/land-use inputs precede roads, lots and buildings. Apply the dependency order, not their full L-system implementation.
- [Craig Mesaros, Mannheim development](https://craigmesaros.com/projects/VgqJVP): block out roads, city blocks, sight lines and elevation before final asset polish. Test routes before adding detail.
- [Wargaming level design process](https://wargaming.com/en/news/creating_levels/): test the gameplay blueprint, add coherent assets, then revalidate collision and load. Use native scene and route tests as gates; screenshots alone are insufficient.
- Berlin map-development page was blocked by a JavaScript/cookie challenge; the accessible first-party examples above are used instead.

### Recursive checkpoint
Trigger: roads arbitrary, UI still weird. Concrete cause: duplicated hardcoded road strips, roads attached after buildings, path shortcuts ignore cost; HUD remains a flat bottom dashboard. Artifact: connected road graph and tested preferred routes; classic sidebar native screenshot. Decision: replace shared road source and move HUD composition to sidebar. Kill result: disconnected road visuals, lanes blocked by buildings, broken missions or more decorative panels without clearer hierarchy.

## Integrated evidence and visual judgment
27 behavior/input suites pass after mobility profiles. New native comparisons are in artifacts/revamp-review.html. All three approved concepts and actual close/normal views were inspected. Visual acceptance is **not met**: settlement remains sparse, intact proportions repeat, ground/vegetation and lighting lack the reference richness. Sidebar is an inferred classic RTS layout because concepts have no complete HUD. Reference comparison is a delivery artifact, not a claim of parity. Next visual work must finish a cohesive street block rather than scatter more trim.

Road speed profiles are gameplay approximations: infantry, tracked and wheeled use different open/mud/rough penalties. Actual traversal and route costs share profile data. Access is domain/footprint-based. Individual soldiers fit narrower gaps than vehicles; squad routing still uses its formation footprint. No automatic columns, traffic, bridge load limits or slope physics.

Validation is complete for the current increment, but plan status remains in-progress because visual acceptance and performance target are unmet. Detailed report: [validation](../validation.md).

Final isolated benchmark: 24.673 ms frame p95, 18.431 ms median, 11.585 ms simulation p95, 2,194 draw calls. Draw submissions fell ~45%, but frame timing remains variable and target unmet. Do not treat intermediate 20.002 ms result as stable performance.

## Texture and inaccessible-gap correction
- [x] Reproduce narrow village-gap order rejection and disconnected formation fallback; preserve full body clearance.
- [x] Resolve open-ground gap clicks to reachable nearby positions within six units; show adjusted-order feedback. Closed yards remain blocked.
- [x] Add original generated albedo atlas to plaster, equipment, soil and asphalt; mipmap/filter and inspect native world/equipment captures.
- [ ] Full reference-quality material/asset acceptance: existing mesh silhouettes, repeated facades, roof detail and foliage still fall short. This increment does not close overall visual acceptance.

First unfiltered atlas render was rejected due to grain/shimmer; explicit mipmap import fixed it. Asphalt exposure was retuned from native review.

- [x] Add flush road-edge paving, drainage grates, rural shoulders and village crossing from road purpose; skip intersecting road/building/water centers. Native screenshots inspected.
- [ ] Expand coherent roadside object families: lights/signs, shop entrances and street furniture; industrial loading/service equipment; rural boundaries/drainage; canal infrastructure. Large objects require shared collision, access and performance review.

- [x] Add two parked vehicles and three streetlights per showcase/skirmish map with shared mesh/navigation bounds, no live light nodes.
- [x] Fix second-pass batching color/finish loss; normalize batched palette and ground saturation; inspect muted lighting against all four user references.
- [x] Extend sampled material families to roof tiles, galvanized sheet, brick and canvas; remove duplicate geometric roof ribs.

Final behavior run: 30 suites pass, including material re-batching and 21,639 roadside-prop checks. Major composition/asset fidelity remains open.

Latest post-material/props benchmark: 36.061 ms frame p95, 22.665 ms simulation p95; performance acceptance remains open and regressed from prior revamp.

## Measured refinement and independent review
- [x] Profile actual soldier/group collision work; spatially index bodies, update immediately, score steering before collision, share safe eligibility checks. Compare identical authoritative state and RNG against exhaustive queries.
- [x] Compose adjoining stepped town parcels, differentiated townhouse/service wing, dressed courtyards/farm pergolas/workshop areas; add exposed ruined construction. Validate135,920 mesh vertices inside prior blockers.
- [x] Correct atlas normalization that clamped material variation; remove artificial square paint speckles, reduce fabric scale, mute faction paint and soften shadow darkness.
- [x] Independent Codex visual examination; address material scale and repeated massing feedback. Full reference matching remains open.
- [ ] Claude visual examination: both normal and Diane host launches returned 'Not logged in'; no Claude acceptance claimed. This active run received configured profiles as disabled and no team bridge.

CPU evidence: artifacts/simulation-profile-comparison.json. Clean600-tick workload10.209s→5.272s; p9523.143→12.689ms, identical final unit-state SHA256. This is headless CPU performance, not rendered FPS.

Distant infantry shadows use one instanced soft contact layer above camera size45, with full animated shadows restored on zoom-in. Unit geometry and behavior remain unchanged. MSAA was4× (enum2) despite prior documentation saying2×; set actual2× (enum1). Benchmark clock now starts after the first rendered frame to exclude startup pipeline compilation, followed by a20s run whose first2s are warmup. Metal was evaluated only, not made default.

Final integrated check:32suites pass. Default-pacing frame p9525.091ms; target remains unmet. Independent Codex review still rates full style alignment partial. See validation.md for exact protocol and Claude authentication limitation.
