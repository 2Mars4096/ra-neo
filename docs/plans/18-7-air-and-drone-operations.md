# 18-7: Air and drone operations

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Give reconnaissance aircraft, gunships and strike drones distinct missions that react to known threats while preserving believable flight, sensing and resource constraints.

## Baseline and scope

The roster contains an unarmed UAV, gunship and FPV strike drone in [units.json](../../resources/units.json). [Simulation](../../scripts/simulation.gd) supplies commands, targeting, skyline clearance and FPV approach/acquire/dive. [Field operations](../../scripts/field_ops.gd) distributes swarm targets; [vehicle damage](../../scripts/vehicle_damage.gd) models gunship component failure and crashes. The [director](../../scripts/tactical_director.gd) excludes non-land units.

Ordinary UAV/gunship batteries, fuel, ammunition inventories, landing sites, service pads and transport seats are not established mechanics. FPV endurance already exists. Its current pursuit of a live assigned target requires particular review when introducing a consistent knowledge model. Existing primitives in the catalogue do not mean the proposed mission policy is implemented.

## Action catalogue

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| AIR-01 | Observe a designated area | Partial | Core | Select a feasible observation position and remain inside the assigned operating area. |
| AIR-02 | Patrol a bounded route or sector | Partial | Core | Reuse waypoint movement with stable route progress and explicit interruption rules. |
| AIR-03 | Scout ahead of a moving force | Partial | Core | Search a bounded corridor using known information; do not reveal unvisited enemies. |
| AIR-04 | Follow a protected force as its sensor | New | Core | Maintain useful sight coverage and separation instead of chasing its exact center. |
| AIR-05 | Avoid a known threat region | New | Core | Trade observation value against remembered risk; unknown AA does not enter the score. |
| AIR-06 | Hand observation to another scout | New | Expansion | Confirm replacement coverage before departing when practical; release stale claims. |
| AIR-07 | Select a gunship firing position | Partial | Core | Require useful range, actual line of fire, skyline clearance and an exit route. |
| AIR-08 | Disengage and reassess an attack | Partial | Core | Retain the assignment while withdrawing from observed danger or lost capability. |
| AIR-09 | Respond to a support request | Partial | Expansion | Accept an eligible target/area task with confidence, cost and expiry; reject unsupported requests. |
| AIR-10 | Hold or circulate without crowding | Partial | Core | Reserve separated feasible positions; no zero-cost continuous movement loop. |
| AIR-11 | Adapt flight to terrain and structures | Existing | Core | Preserve the existing skyline/elevation contract during every new mission action. |
| AIR-12 | Allocate strike drones across targets | Existing | Core | Improve existing assignment using expected useful effect and uncertain committed attacks. |
| AIR-13 | Search after losing a strike target | Partial | Expansion | Use last known position and a bounded search; reacquisition needs an allowed sensor or report. |
| AIR-14 | Cancel or abort an uncommitted strike | Partial | Expansion | Define the last reversible phase; terminal commitment cannot teleport or refund the munition. |
| AIR-15 | Select an emergency landing destination | Partial | Expansion | Existing damage determines remaining controllability; choose only reachable legal surfaces. |
| AIR-16 | Land and relaunch at a service site | New | Optional | Requires a landing-capable type, occupancy reservation, physical approach and departure clearance. |
| AIR-17 | Return for energy or fuel | New | Optional | Requires explicit inventory and a compatible replenishment site; no unexplained refills. |
| AIR-18 | Rearm and resume a sortie | New | Optional | Introduce finite stores, service cost and mission persistence before enabling automatic return. |
| AIR-19 | Operate a reconnaissance or relay payload | New | Optional | Model fitted payload, sensing/emission tradeoff and link capacity before offering the action. |
| AIR-20 | Pick up or deliver a transported section | New | Optional | Requires a transport aircraft and shared passenger identity/landing contracts. |

## Decision and knowledge rules

Use [18-1](18-1-action-framework-and-readiness.md)'s versioned mission lifecycle. UAVs value coverage; gunships value firing opportunities; FPVs commit a consumable attack. Each mission has an area/recipient, risk limit, information source, completion condition and fallback.

Threat avoidance uses [18-9](18-9-information-and-electronic-warfare.md)'s timestamped contacts. Distinguish local acquisition, reports and seeker state. Remembered danger can influence routes, not reveal unseen movement. Radio loss preserves received intent and local responses; holding, return or bounded search requires a declared capability-specific policy.

Retain authoritative footprint/elevation checks and existing flight bands. Avoidance cannot fly through geometry or invent altitude capabilities. Bound candidate search and penalize needless replanning.

Release rechecks knowledge and friendly exposure. Prelaunch cancellation releases reservations; postlaunch cancellation respects control/commitment limits. Impacts still affect units entering the area afterward. Consumed drones remain consumed.

## Tasks

- [ ] 1. Add role-specific mission adapters to [18-1](18-1-action-framework-and-readiness.md), preserving existing ordinary commands and the FPV execution sequence.
- [ ] 2. Deliver observation, patrol, force-following and known-threat avoidance with the existing UAV.
- [ ] 3. Deliver gunship position selection, capability-aware disengagement and support tasks through [18-4](18-4-coordination-and-support-requests.md).
- [ ] 4. Reconcile FPV live-target pursuit, contact loss, allocation and irreversible commitment with the shared knowledge and consumable-effect contracts.
- [ ] 5. Extend controllable emergency landings without changing unavoidable crashes into guaranteed safe recoveries.
- [ ] 6. Add optional landing, energy, rearm, payload or transport mechanics only as separately validated capability packages with [18-10](18-10-logistics-medical-and-recovery.md).

## Acceptance scenarios

1. A scout follows a moving force while retaining useful observation and clearance; retasking either party ends or updates the relationship cleanly.
2. Known AA changes a scout's choice; an unseen AA unit does not. A stale contact decays rather than remaining a permanent exclusion.
3. A gunship supports a reported contact, loses a legal firing solution and repositions or rejects the task without firing through terrain.
4. A strike target disappears behind cover or loses valid tracking: no hidden live coordinates leak into the chosen action.
5. Two FPVs receive assignments, one target is destroyed and cancellation arrives during different phases: consumed inventories and terminal effects remain consistent.
6. A link outage, destroyed service site or unsafe landing area produces the declared fallback without infinite waiting.

## Interfaces and presentation

Touchpoints: `simulation.gd`, `field_ops.gd`, `vehicle_damage.gd`, elevation, `resources/units.json` and `regional_campaign.gd`. [18-11](18-11-command-interface-and-feedback.md) owns Observe/Patrol/Support intent; [18-12](18-12-performance-and-validation.md) verifies bounded sensing, search, replay and reaction latency. Dependencies mean minimum interface slices, not whole-plan completion.

Optional energy/rearm rows reuse [18-10](18-10-logistics-medical-and-recovery.md)'s service ledger; aircraft landing, provider compatibility and sortie execution remain here.

Reuse current meshes with simple mission/sensor/uncertainty indicators. Optional landing, payload and transport art declares collision/attachment metadata. Regional saves preserve equipment and condition; local missions restart per battlefield. Unsupported domains remain parked without off-map sortie simulation.

## Decisions

- Core scope makes the current three air roles useful through persistent assignments and informed local choices.
- Energy, generic aircraft ammunition, service pads and transport are optional new systems, not assumptions embedded in Core decisions.
- Observation and threat uncertainty are gameplay state. Rendering, AI and player feedback consume the same state.

## Notes

Planning only. All search durations, risk weights and service costs remain provisional game parameters. Scenario completion and performance need native validation before any readiness claim.
