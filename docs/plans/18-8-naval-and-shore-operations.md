# 18-8: Naval and shore operations

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Make existing corvettes maintain useful sea-control and shore-support assignments, with later transport and recovery actions gated by real gameplay capabilities.

## Baseline and scope

The [corvette](../../resources/units.json) is the only player naval type. [Simulation](../../scripts/simulation.gd) implements water navigation, steering and shooting. [Vehicle damage](../../scripts/vehicle_damage.gd) models fire, flooding, pumping, crew loss and sinking; directed damage-control and port services are new. Existing repair providers accept land units.

[Operation rules](../../scripts/operation_rules.gd) tie South Inlet's supply/victory to shore prerequisites and uncontested ship presence. [Campaign](../../scripts/regional_campaign.gd) deployment parks ships when a domain is unsupported. The tactical director excludes naval units. Catalogue starting points describe primitives, not completed policies.

## Action catalogue

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| SEA-01 | Select a coastal firing position | Partial | Core | Compare a few navigable positions with real range, visibility and escape access. |
| SEA-02 | Hold a sea-control sector | Partial | Core | Maintain the assigned objective area without drifting out to pursue a low-value contact. |
| SEA-03 | Patrol a water corridor | Partial | Core | Preserve waypoint progress and bounded chase limits; respect continuous coastline clearance. |
| SEA-04 | Escort a designated friendly vessel | New | Expansion | Reserve useful offsets, respond to threats and retain the protected vessel's identity. |
| SEA-05 | Support a designated shore force | Partial | Core | Follow progress along accessible water while preserving a useful support relationship. |
| SEA-06 | Answer a shore fire-support request | Partial | Core | Accept only legal targets and firing solutions; observation does not bypass a ridge or building. |
| SEA-07 | Allocate fire against urgent threats | Partial | Core | Consider danger, weapon effect and committed allied fire; keep stable targets otherwise. |
| SEA-08 | Reposition after losing a useful shot | Partial | Core | Retain the support assignment and evaluate a bounded shortlist instead of chasing onto land. |
| SEA-09 | Withdraw while maintaining useful orientation | Existing | Core | Extend hull navigation with a retreat destination and meaningful capability assessment. |
| SEA-10 | Yield at a channel or harbor entrance | Partial | Expansion | Reserve passage and waiting space; prevent opposing vessels from indefinitely blocking each other. |
| SEA-11 | Prioritize onboard damage control | Partial | Expansion | Extend existing fire/pump mechanics with declared crew allocation and a combat-readiness tradeoff. |
| SEA-12 | Request coastal repair or resupply | Partial | Expansion | Requires a compatible service provider and safe docking/stand-off access before acceptance. |
| SEA-13 | Tow or be towed to safety | New | Optional | Requires suitable recovery capability, attachment state and combined navigation envelope. |
| SEA-14 | Embark and land infantry | New | Optional | Requires a transport-capable vessel, capacity, legal embarkation and shoreline exit positions. |
| SEA-15 | Cover an authorized landing | New | Optional | Coordinate a real transport/shore task; never treat ordinary corvettes as passenger carriers. |
| SEA-16 | Deliver supplies to a shore facility | New | Optional | Requires cargo inventories, transfer rates and an eligible receiving facility. |
| SEA-17 | Avoid or clear a known maritime hazard | New | Optional | Requires authored hazard zones, observation rules and a capable clearance unit. |
| SEA-18 | Deploy obscuration or a decoy | New | Optional | Requires fitted equipment and authoritative sensor/effect interactions, with finite charges. |
| SEA-19 | Observe and relay a coastal contact | Partial | Expansion | Publish confidence and observation age; any relay enhancement needs a modeled capability. |
| SEA-20 | Recover survivors or abandoned equipment | New | Optional | Requires rescue capacity and conserved identities; implement only after recovery scope is selected. |

## Decision and execution rules

A naval assignment specifies area/force, permitted waters, chase limit and completion condition. SEA-02 exposes objective importance: chasing can break sea control. Mobility, weapons, crew, fire and flooding influence hold, reposition, service or relief decisions. Player hold follows the shared initiative contract.

Use [18-1](18-1-action-framework-and-readiness.md)'s lifecycle and [18-4](18-4-coordination-and-support-requests.md)'s task claims. Requests carry observed target/uncertain area, expiry and accepted effect. Core uses existing gunnery restrictions. Indirect fire and new ammunition require authoritative effect and resource models first.

Candidate evaluation uses execution's hull, coastline and dock rules, including exit connectivity. Avoid oscillation between similar positions. Preserve South Inlet's contested-zone and supply rules.

Boarding/cargo actions reserve provider, capacity and transfer location, conserving identities through cancellation/destruction. Landing needs access, slope, occupancy and legal exit positions. [18-10](18-10-logistics-medical-and-recovery.md) owns inventories/services; this plan owns vessel approach and shoreline transitions.

## Tasks

- [ ] 1. Add naval assignment and local-action adapters to the shared framework, reusing the existing corvette and terrain contracts.
- [ ] 2. Deliver sea-control holding, coastal support-position selection and ordinary retreat on South Inlet.
- [ ] 3. Add legal shore-support requests and persistent follow/support relationships with explicit rejection reasons.
- [ ] 4. Add vessel escort and constrained-channel reservations; preserve independent boat orders and physical movement.
- [ ] 5. Introduce damage-control choices and compatible service infrastructure without granting land repair points implicit naval service.
- [ ] 6. Expand landing, cargo, towing, hazards and rescue only after their roster, resource and physical prerequisites are accepted.

## Acceptance scenarios

1. A corvette assigned to sea control resists a low-value chase that would abandon the sector; a direct player order still overrides the assignment.
2. A shore force moves beyond useful coverage: the corvette finds reachable support water or reports the limit, without crossing a headland.
3. A spotter requests fire behind obstructing terrain: the request is rejected or repositioned under the actual weapon rules.
4. Two vessels enter a constrained channel from opposite directions, negotiate passage and release reservations when one is destroyed or retasked.
5. Fire/flooding and crew loss alter readiness and service choices; damage control trades modeled capacity rather than instantly repairing the hull.
6. An optional landing is canceled, its carrier is lost, or the operation ends: passengers and cargo appear exactly once in the appropriate surviving records.

## Interfaces and presentation

Touchpoints: `simulation.gd`, `terrain.gd`, `operation_rules.gd`, `vehicle_damage.gd`, `field_ops.gd` and `regional_campaign.gd`. [18-9](18-9-information-and-electronic-warfare.md) owns sensing, [18-5](18-5-engineering-and-field-fortifications.md) shore works, [18-11](18-11-command-interface-and-feedback.md) commands and [18-12](18-12-performance-and-validation.md) validation. Dependencies mean minimum contracts, not whole-plan completion.

Repair, cargo and rescue rows reuse [18-10](18-10-logistics-medical-and-recovery.md)'s shared service/identity contracts; naval approach, attachment and shoreline execution remain here.

Reuse the corvette mesh; prototype service/landing/tow/cargo locations with measured envelopes. Damage visuals follow authoritative state. Save approved equipment/cargo; reconstruct local routes and relationships per battlefield. Inland parking preserves units without off-map sailing, repair or resupply.

## Decisions

- Core scope concerns one existing naval class, shore fire and sea control; new vessel classes are separate capability packages.
- Escort and support improve local decisions without changing the independent-battlefield regional design.
- Rescue and maritime hazards are optional expansions, preserving the earlier deferral of a wider stranded-wounded rescue system.

## Notes

Planning only. Catalogue actions are proposed game mechanics, with provisional timing and balance. Native coastal-path, sea-control and mixed-force validation remains required before implementation acceptance.
