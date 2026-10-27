# 18: Tactical actions and capable individual units

**Status:** not-started
**Goal:** Expand meaningful actions across all unit domains and make units choose, coordinate and execute them promptly under clear player intent.

## Planning baseline

Prepared 2026-10-27 from `codex/regional-operations` at `f5916e8`, with the previous review of `main` at `e97e82f`. This document set completes the requested planning work; every implementation task remains unstarted. It does not authorize gameplay implementation or establish measured improvements. The documentation branch is `codex/unit-tactics-plans`.

The user explicitly requested a broader repertoire including grenades, calls for backup and digging trenches, extending beyond infantry to other units. Preserve the existing approachable RTS controls, individual casualties, shared physical rules and independent regional battlefields.

## Baseline to extend

| Area | Present in the reviewed code | Planned change |
|---|---|---|
| Infantry | Individual aim, wounds, posture, ammunition cycles, local cover, corner firing, buddy aid and garrisoning | Readiness outside the firing branch; genuine role coordination; throws, local digging, specialist transfer and richer urban decisions |
| Land tactics | Retained orders, local flank/support/withdrawal, reservations and contact drills | Explicit action priorities, casualty-aware strength, persistent assignments and typed support requests |
| Vehicles | Armor facing, component damage, reverse movement, wrecks, repair points and re-crewing | Position/orientation choices, capability-aware missions and sustained protection/support roles |
| Air and sea | Domain movement, sensing, targeting, damage and FPV strikes | Dedicated observation, protection, support and withdrawal policies |
| Engineers | Paid construction of trenches, sandbags, wire, berms, nets and support posts; barrier/wreck clearing | Better work selection, protected work, infantry hasty positions and progressive upgrades |
| Information | Fog, team-visible contacts, local sensing under radio loss and enemy-site memory | Timestamped mobile contacts, explicit smoke/sensor semantics and bounded shared facts |
| Operations | Supply, off-map purchase queue and persisted regional roster/checkpoints | Persist new durable equipment/resources without duplicating charges or saving transient tactical jobs |

Evidence: [simulation](../../scripts/simulation.gd), [infantry](../../scripts/infantry.gd), [cover](../../scripts/cover_behavior.gd), [director](../../scripts/tactical_director.gd), [field operations](../../scripts/field_ops.gd), [vehicle damage](../../scripts/vehicle_damage.gd), [campaign](../../scripts/regional_campaign.gd). Some earlier plan checkboxes describe historical scope; implementation is the baseline for this plan.

## Plan map

| Plan | Responsibility | First usable result |
|---|---|---|
| [18-1: Action framework and readiness](18-1-action-framework-and-readiness.md) | Orders, capability, action lifecycle, interruption and stable choices | Reliable reload, targeting and casualty-aware response |
| [18-2: Infantry fire and movement](18-2-infantry-fire-and-movement.md) | Soldier execution and section roles | An available member covers a moving or reloading teammate |
| [18-3: Grenades and urban actions](18-3-infantry-grenades-and-urban-actions.md) | Throwables, exposure cycles and bounded urban interactions | A visible, interruptible throw with authoritative effects |
| [18-4: Coordination and support requests](18-4-coordination-and-support-requests.md) | Persistent assignments, backup and support delivery | One eligible nearby responder accepts and completes a request |
| [18-5: Engineering and field fortifications](18-5-engineering-and-field-fortifications.md) | Digging, construction, clearing and supported work | Infantry create a hasty position; engineers improve the defense |
| [18-6: Vehicles and ground support](18-6-vehicles-and-ground-support.md) | Armor, ground roles and vehicle missions | Vehicles choose facing, short reposition and useful support |
| [18-7: Air and drone operations](18-7-air-and-drone-operations.md) | Recon, gunship and drone missions | Observe/protect assignments with known-threat responses |
| [18-8: Naval and shore operations](18-8-naval-and-shore-operations.md) | Sea control, coastal support and ship survival | A corvette maintains useful, navigable support coverage |
| [18-9: Information and electronic warfare](18-9-information-and-electronic-warfare.md) | Contact memory, sensors, smoke and communications | Decisions use shared, legitimate observations |
| [18-10: Logistics, medical and recovery](18-10-logistics-medical-and-recovery.md) | Readiness resources, aid, repair and persistence | Opt-in replenishment/repair followed by assignment resumption |
| [18-11: Command interface and feedback](18-11-command-interface-and-feedback.md) | Intent controls, previews and legible reasons | Rich behavior remains accessible with few commands |
| [18-12: Performance and validation](18-12-performance-and-validation.md) | Scheduling, budgets, correctness and acceptance | Reproducible interaction tests and separate latency/performance evidence |

The [action catalogue](../tactical-action-catalogue.md) consolidates the domain tables. **Existing** means an underlying primitive exists, not that the proposed behavior is complete; **Partial** means related machinery exists; **New** means a new authoritative action is needed. **Core**, **Expansion** and **Optional** indicate delivery priority, not present availability. Core actions are distributed across the milestones below; they are not all prerequisites for the first playable increment.

## Tasks

- [ ] 1. M0 — Stabilize current decisions: establish action contracts, minimal timestamped observation records, quiet reloads, explicit-target precedence, urgent threat overrides, original-strength assessment and a complete work budget; add the first diagnostic scenarios.
- [ ] 2. M1 — Deliver the infantry defense slice: coordinated cover/reload/movement, one fragmentation payload and optical smoke, a nearby backup request, and a hasty fighting position with an engineer upgrade. Integrate compact controls and resource persistence for the enabled features.
- [ ] 3. M2 — Give each existing domain a role: vehicle facing/short reposition and repair return, recon observation, AA protection, gunship support and corvette coastal support. Verify interruption and resumption across mixed forces.
- [ ] 4. M3 — Expand coordinated operations: richer urban actions, specialist transfer, field-work coordination, memory-driven investigation, shared fire commitments and delegated sustainment.
- [ ] 5. Evaluate Optional catalogue items individually after the earlier slices pass. Create deeper implementation plans only for the next selected increment.
- [ ] 6. Complete cross-map playtesting, performance evidence, campaign compatibility and presentation acceptance before describing the expanded repertoire as delivered.

## Milestone exit gates

| Milestone | Demonstration | Exit evidence |
|---|---|---|
| M0 | An AA vehicle reacts to a newly observed drone; a quiet soldier reloads; a depleted section recognizes its losses; new orders cancel stale choices | Focused deterministic regressions, decision traces and unchanged geometry/order semantics |
| M1 | At a Harbor crossroads one member covers, another throws or moves, another prepares a position; a nearby reserve answers a request and later resumes its job | No duplicate resource consumption, valid blast/smoke/cover effects, readable activity, interrupted-action tests and native play review |
| M2 | The same assignment logic works with vehicles in Fields, observation in Pass and sea support in Inlet | Role-specific functional fixtures, domain/route limits, and a playable combined-arms encounter |
| M3 | Support, urban interactions and supply decisions work together under losses, jamming and destroyed geometry | Multi-system stress fixtures, campaign save/retry tests and human review of unnecessary micro and action churn |

Planning and testing run in parallel with each milestone; validation is not postponed until all new actions exist. Performance targets in the development plan remain provisional and unmet where already recorded. Preserve a declared baseline and report regressions separately from the long-term 16.7 ms frame-p95 goal.

## Shared contracts and ownership

| Contract | Owner | Consumers |
|---|---|---|
| Action state, order version, reservations and capability/fact records | 18-1 | Every domain |
| Task request, claim, acknowledgement and completion | 18-4 | Infantry, engineers, vehicles, air, sea and support |
| Throw release, projectile collision and payload deployment | 18-3 | Infantry; later emitter/launcher adapters |
| Smoke, observation confidence, communication and threat knowledge | 18-9 | Every decision and weapon/sensor legality check |
| Persistent resources, replenishment and campaign migration | 18-10 | Throws, support services, vehicle/air/sea extensions |
| Authored/dynamic work geometry and construction progress | 18-5 | Movement, cover, sight, editor and presentation |
| Command vocabulary and visible acknowledgement | 18-11 | Every action and request |
| Work scheduler and acceptance measurements | 18-12 with 18-1 | All queries and executors |

Dependencies refer to the minimal contracts needed for a slice, not completion of another subplan's entire catalogue. Start with 18-1 plus the minimal observation, UI and instrumentation adapters from 18-9/11/12; then enable 18-4 and domain executors. Existing repair, construction and damage providers can satisfy an early adapter. Optional transports, new artillery units or advanced EW must not block ordinary grenade, backup or digging work.

## Decisions

- Player intent defines permitted autonomy. Local details may be automatic; purchases, expensive construction and major reassignment require explicit orders or a previously delegated budget/assignment.
- Use one action lifecycle and small bounded candidate sets. Keep purposeful commitment, emergency interrupts and resumable assignment context together.
- Evaluate decisions from sensed or communicated information. Hidden enemy positions, future projectile impacts and unseen damage states are not decision inputs.
- Preserve speed, aiming, collision, elevation and resource rules. A responsive decision can begin before an expensive route finishes; it cannot teleport or skip weapon preparation.
- Actions have tradeoffs: time, exposure, limited equipment, displaced fire/support and opportunity cost. Numerical ranges and durations are gameplay parameters to tune, not claims of real combat accuracy.
- First digging uses constrained work-site geometry, not arbitrary terrain deformation. New animations and models begin as clearly specified placeholders tied to authoritative state.
- Full transport fleets, new artillery/aircraft/ship classes, mine warfare, physical bridge construction, extensive interiors and stranded-wounded evacuation remain separately gated Optional scope.
- The existing single-supply field mode and one-live-battle regional model remain the integration boundary. Durable roster/resources may persist; tactical orders, temporary smoke and request queues do not silently become world-save features.

## Notes

No implementation duration or hardware capacity is promised. The first implementation session should recheck the branch head, reproduce the relevant review findings and select M0/M1 tasks. The broad catalogue records the intended design space; it is not an instruction to implement every item at once.
