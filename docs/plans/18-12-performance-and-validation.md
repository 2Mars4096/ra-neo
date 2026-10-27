# 18-12: Decision responsiveness, performance and validation

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Make richer tactical decisions responsive, reproducible and physically consistent while proving their gameplay value and runtime cost.

## Baseline and evidence

The simulation runs at 30 Hz. [simulation.gd](../../scripts/simulation.gd) refreshes visibility about every 0.3 seconds and maintains route/formation queues; [tactical_director.gd](../../scripts/tactical_director.gd) reviews maneuvers around 0.8–1.1 seconds. Cover/contact logic has shorter cadences. These schedules do not measure end-to-end responsiveness.

[terrain.gd](../../scripts/terrain.gd) `path_job()` runs A* synchronously; `path_job_step()` divides smoothing. Director flank/bound searches, combat cover and individual regrouping also call paths directly. Some idle cover work has a separate budget. These useful limits do not constitute a complete budget or worker-thread dispatch.

[14-1's historical cover-cost comparison](14-1-cover-contact.md) records unresolved 26.5 ms and 29.1 ms cases against a 25 ms limit. [profile_harbor_busy.gd](../../tests/profile_harbor_busy.gd) requires sustained two-sided contact before measuring headless CPU work. Neither measures current rendered FPS.

## Scheduling and execution contract

Separate inexpensive reactions from planning. An observed threat, lost cover, casualty, failed capability or accepted order marks affected units for review. Stop unsafe actions or retain protection while a route is pending. Preserve aiming, turning, reload and travel time.

Use deterministic priority, age and stable-ID tie-breaks, with reserved capacity for urgent work and service for ordinary requests. Include contact gathering, candidate evaluation, formation resolution, local cover routes, flanks, regrouping and full routes in the audit. A short route in dense geometry is not automatically cheap. Reuse local situation summaries and versioned geometry results; invalidate only affected data.

Budgeted admission alone cannot cap one long synchronous A* call. Measure that risk separately. If needed, later introduce bounded spatial decomposition or worker-owned navigation snapshots. Current shared grids temporarily mutate obstacles during queries, so indiscriminate parallel calls are unsuitable. Godot's [AStarGrid2D documentation](https://docs.godotengine.org/en/4.5/classes/class_astargrid2d.html) restricts concurrent access; its [navigation guidance](https://docs.godotengine.org/en/4.5/tutorials/navigation/navigation_optimizing_performance.html) recommends avoiding redundant queries and spreading updates.

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
- [ ] 2. Audit direct expensive-call sites and introduce shared deterministic scheduling with [18-1](18-1-action-framework-and-readiness.md).
- [ ] 3. Add focused regressions for explicit-target precedence, urgent AA switching, quiet reload, casualty strength and action-priority conflicts.
- [ ] 4. Gate each first action slice on its domain fixtures, shared physical/information invariants and [18-11](18-11-command-interface-and-feedback.md) native command review.
- [ ] 5. Validate [18-4](18-4-coordination-and-support-requests.md) request lifecycle and [18-10](18-10-logistics-medical-and-recovery.md) resource/campaign transactions.
- [ ] 6. Profile sustained mixed-action encounters; fix demonstrated bottlenecks before raising action or force counts.
- [ ] 7. Review human reports of hesitation, unwanted overrides and unclear reasons; tune doctrine and commitment rules against recorded examples.

## Decisions

- Keep existing clearance, correctness and timing thresholds visible. A new feature does not silently waive a failing gate.
- Native captures support presentation review; input traces and interactive tests verify selected interactions. Headless tests prove selected simulation properties, and rendered benchmarks establish performance only for their stated setup.
- Debug overlays may show action, reason, uncertainty and queue age; normal play uses concise feedback. Placeholders must communicate release, movement, protection and completion clearly enough to test.

## Notes

No benchmark or measured speedup is claimed by this plan. Touchpoints include simulation/director/cover/navigation modules, tests, profilers and validation records. Module boundaries and budgets remain implementation decisions informed by measurement.
