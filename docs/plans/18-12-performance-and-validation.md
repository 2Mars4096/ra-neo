# 18-12: Decision responsiveness, performance and validation

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** in-progress
**Goal:** Make richer tactical decisions responsive, reproducible and physically consistent while proving their gameplay value and runtime cost.

## Baseline and evidence

M0 implements deterministic shared planning admission, event-triggered review, stale-result rejection and incremental placement searches in [18-1-1](18-1-1-m0-foundation.md). `--group m0` selects focused contracts and `--group tactical` the affected integration gate. Reports distinguish queue/admission counters, path calls and actual A* starts. The historical limitations below remain: admission bounds finite bundles, not one synchronous A* call's CPU time, and no new rendered performance or input-latency acceptance is claimed.

The simulation runs at 30 Hz. [simulation.gd](../../scripts/simulation.gd) refreshes visibility about every 0.3 seconds and maintains route/formation queues; [tactical_director.gd](../../scripts/tactical_director.gd) reviews maneuvers around 0.8–1.1 seconds. Cover/contact logic has shorter cadences. These schedules do not measure end-to-end responsiveness.

[terrain.gd](../../scripts/terrain.gd) `path_job()` runs A* synchronously; `path_job_step()` divides smoothing. M0 admits director, cover, regroup, placement and legacy route bundles through the shared scheduler before starting their synchronous searches. Setup/direct tool calls are exempt. Finite caller limits and counters make this work inspectable; they do not establish a wall-clock cap or worker-thread dispatch.

[14-1's historical cover-cost comparison](14-1-cover-contact.md) records unresolved 26.5 ms and 29.1 ms cases against a 25 ms limit. [profile_harbor_busy.gd](../../tests/profile_harbor_busy.gd) requires sustained two-sided contact before measuring headless CPU work. Neither measures current rendered FPS.

## Scheduling and execution contract

Separate inexpensive reactions from planning. An observed threat, lost cover, casualty, failed capability or accepted order marks affected units for review. Stop unsafe actions or retain protection while a route is pending. Preserve aiming, turning, reload and travel time.

Use deterministic priority, age and stable-ID tie-breaks, with reserved capacity for urgent work and service for ordinary requests. Include contact gathering, candidate evaluation, formation resolution, local cover routes, flanks, regrouping and full routes in the audit. A short route in dense geometry is not automatically cheap. Reuse local situation summaries and versioned geometry results; invalidate only affected data.

Budgeted admission alone cannot cap one long synchronous A* call. Measure that risk separately. If needed, later introduce bounded spatial decomposition or worker-owned navigation snapshots. Current shared grids temporarily mutate obstacles during queries, so indiscriminate parallel calls are unsuitable. Godot's [AStarGrid2D documentation](https://docs.godotengine.org/en/4.5/classes/class_astargrid2d.html) restricts concurrent access; its [navigation guidance](https://docs.godotengine.org/en/4.5/tutorials/navigation/navigation_optimizing_performance.html) recommends avoiding redundant queries and spreading updates.

### M0 work audit

The scheduler admits **finite caller bundles**, not one token per A* start. Its counters must be read alongside Terrain's actual search counts. The implementation audit found these worst-case loops; these are code limits, not measured CPU costs:

| Admitted work | Maximum per bundle |
|---|---:|
| Formation / attack-placement continuation | 64 candidate probes and 4 connectivity/path queries per step |
| Individual cover / regroup | 6 / 9 path calls |
| Give-way / ordinary order / flank | 6 / 2 / 2 path calls |
| Cover-bound destination | 21 path calls |
| Classic base approach / delivery / collection / staging | 16 / 16 / 14 / 4 path calls |
| Engineer continuation | 48 path calls |
| Blocked-route recovery including occupied arrival alternatives | 50 path calls |
| Crowded spawn placement | Up to 576 path calls per unit; dispatch admits one authored batch |

Bound/flank searches take admission before their complete finite loop. Taking a token for each candidate and restarting at candidate zero on denial was rejected: a later reachable candidate could starve forever. Denied engineer, production, reserve and re-crewing work remains pending before any paid/once-only commitment.

The largest legacy bundles and synchronous grid searches remain performance risks. A later measured optimization can split spawn jobs by unit/ring/angle and retain `{done,pos}` progress, while preserving paid queues and dispatch identity. M0 makes these paths share admission and exposes their cost; it does not certify a tight frame-time bound.

Any worker proposal needs order/terrain version checks, obsolete-result rejection and a deterministic commit/replay contract. Authoritative decisions must not change with camera visibility, presentation level, frame rate or wall-clock scheduling. Pure performance refactors preserve seeded state traces; intentional behaviour changes receive explicit new expectations.

## Proposed measures and gates

These are initial acceptance targets to validate on declared fixtures and hardware, not achieved results. Record observation delay separately from reaction scheduling and physical execution.

| Measure | Proposed gate or required report |
|---|---|
| Observed urgent event to review admission | Within one simulation tick for an eligible affected unit. |
| Cheap emergency response | Within two ticks of a known event when a legal immediate action exists; record blocked reasons. |
| Accepted command acknowledgement | Rendered feedback within the existing 100 ms target; report p50/p95/max separately from path completion. |
| Planner service | Report queue age, oldest request, rejected/expired work and starvation; every job completes, fails or remains visibly pending under a bounded policy. |
| Useful action completion | Report completion, interruption and repeated-failure rates by action ID, including failure reasons. |
| Readiness and targeting | Time unable to fire by cause, target switches, discarded aim, duplicate committed shots and simultaneous unavailable squad members. |
| Runtime cost | Per-stage CPU p50/p95/max, allocations, path counts and candidate counts; separate cold setup from warm sustained combat. |
| Rendered performance | Retain the provisional 16.7 ms frame-p95 target at declared 1080p/hardware; report spikes and existing failures honestly. |
| Conservation and authority | Zero unexplained duplicate resources, roles, refunds, unauthorized purchases or expired-order resumptions. |

## Validation ladder

1. **Contracts:** prerequisites, resource reservation/consumption, cancellation, terminal outcomes, request expiry and order-version precedence. Test meaningful state transitions rather than implementation structure.
2. **Physical actions:** doorway/cover clearance, throw collision, smoke occlusion, blast screening, field-work placement, slope and coastline rules. Effects and UI must agree with authoritative outcomes.
3. **Cooperation:** ready covering partner, casualty/reload conflict, urgent threat preemption, persistent escort assignment and support-provider loss.
4. **Information:** stale contacts never follow hidden units; both sides obey declared sensing; area effects use physical outcomes without revealing hidden identities to planners.
5. **Campaign:** old-save migration, partial inventory, specialist loss, parked domains, retry and repeated outcome save with exactly-once accounting.
6. **Playability and load:** native interaction, sustained active combat, representative force counts, CPU/render profiling and human evaluation of command clarity.

## Battlefield fixtures

| Fixture | Combined acceptance problem |
|---|---|
| Black Sea Harbor | Multiple sections seek cover while one reloads, one aids and a grenade is canceled before release; blocked doors and destroyed cover remain physical. |
| Limestone Pass | Observation and firing agree across elevation; a proposed support route respects unit-specific slopes and never borrows hidden contact positions. |
| Bayhead Rail Valley | Supply route loss invalidates a service destination; backup requests select an eligible existing responder without draining every defended position. |
| South Inlet | Drone observation, AA protection and ship support cooperate; water/land boundaries and regional parked-roster rules remain intact. |
| Windbreak Fields | Many units receive contact events together; urgent reactions remain prompt, ordinary jobs avoid starvation and formations do not oscillate. |

Use fixed seeds and ordinary commands for integration runs. Add scale steps from the declared small reference encounter to larger forces; do not infer thousands-unit capacity from a small benchmark. Include camera-offscreen equivalence and slower rendering rates. Compare matched before/after runs without competing benchmarks and retain exact build/engine/configuration metadata.

## Tasks

- [ ] 1. Establish an unchanged baseline and instrument event, decision, route and action timestamps without altering outcomes.
- [x] 2. Audit direct expensive-call sites and introduce shared deterministic scheduling with [18-1](18-1-action-framework-and-readiness.md). M0 covers current executors; finite bundle and synchronous-search limits are recorded above.
- [x] 3. Add focused regressions for explicit-target precedence, urgent AA switching, quiet reload, casualty strength and action-priority conflicts. All 10 M0 suites pass within the 58-suite integration gate.
- [ ] 4. Gate each first action slice on its domain fixtures, shared physical/information invariants and [18-11](18-11-command-interface-and-feedback.md) native command review.
- [ ] 5. Validate [18-4](18-4-coordination-and-support-requests.md) request lifecycle and [18-10](18-10-logistics-medical-and-recovery.md) resource/campaign transactions.
- [ ] 6. Profile sustained mixed-action encounters; fix demonstrated bottlenecks before raising action or force counts.
- [ ] 7. Review human reports of hesitation, unwanted overrides and unclear reasons; tune doctrine and commitment rules against recorded examples.

## Decisions

- Keep existing clearance, correctness and timing thresholds visible. A new feature does not silently waive a failing gate.
- Native captures support presentation review; input traces and interactive tests verify selected interactions. Headless tests prove selected simulation properties, and rendered benchmarks establish performance only for their stated setup.
- Debug overlays may show action, reason, uncertainty and queue age; normal play uses concise feedback. Placeholders must communicate release, movement, protection and completion clearly enough to test.

## Notes

The [M0 validation record](../validation.md#m0-tactical-foundation--2026-10-30) includes one valid 900-tick current-build Harbor CPU sample: 29.816 ms p95, 354.828 ms maximum, and 29 ticks above the 33.333 ms simulation interval. The largest tick contains 328.504 ms in field operations; the director's maximum is 112.376 ms. Finer attribution and splitting expensive synchronous work remain open before adding load. There is no paired speedup comparison or rendered-performance acceptance. Touchpoints include simulation/director/cover/navigation modules, tests, profilers and validation records.
