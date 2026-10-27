# 18-6: Vehicles and ground support

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Make ground vehicles choose useful fighting positions, preserve their remaining capabilities, and cooperate with the force they support.

## Baseline and scope

At `f5916e8`, [vehicle damage](../../scripts/vehicle_damage.gd) models armor facing, components, crew, immobilization, abandonment and re-crewing. [Simulation](../../scripts/simulation.gd) already supplies hull steering, retreat reversing, clearance, targeting and directional berm protection. The land [director](../../scripts/tactical_director.gd) can flank and withdraw, but does not select hull orientation or repair destinations from capability loss. Existing target retention can delay recognition of a newly urgent threat.

The initial roster remains tank and AA vehicle. A transport, recovery vehicle, ammunition carrier or specialist engineering vehicle requires an explicit capability definition and model envelope. The label IFV does not establish a passenger compartment. Catalogue starting points describe available primitives; every proposed policy still requires implementation and validation.

## Action catalogue

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| VEH-01 | Orient hull toward significant threats | Partial | Core | Score known threats and useful firing direction; retain turn rate and swept clearance. |
| VEH-02 | Reverse to nearby protection | Existing | Core | Extend retreat reversing to bounded repositioning without discarding the assignment. |
| VEH-03 | Occupy a useful berm or hull-down position | Partial | Core | Reuse directional protection; require a reachable position and a useful shot. |
| VEH-04 | Maintain useful engagement distance | Partial | Core | Compare a few local positions; prevent continuous forward/backward oscillation. |
| VEH-05 | Alternate movement and covering fire | Partial | Expansion | Coordinate with an actually ready partner through a reserved movement role. |
| VEH-06 | Support an infantry advance | Partial | Expansion | Maintain a bounded support relationship; avoid crushing the infantry's movement corridor. |
| VEH-07 | Escort a designated unit or convoy | New | Expansion | Follow persistent identity and reserved offsets; a new order cancels the relationship. |
| VEH-08 | Maintain AA protection of a force | Partial | Core | Preserve coverage of the assigned force and permit urgent air-threat target switching. |
| VEH-09 | Yield or pass at a bottleneck | Existing | Core | Extend existing give-way rules with stable priority and a timeout; never bypass collision. |
| VEH-10 | Request an obstacle cleared | Partial | Expansion | Report the obstruction to an eligible engineer; hold or reroute while awaiting a response. |
| VEH-11 | Select a better target and avoid excess committed fire | Partial | Core | Retain a useful aim; weigh urgency, effectiveness and uncertain allied shot commitments. |
| VEH-12 | Withdraw for capability repair | Partial | Core | A mobile vehicle with a disabled gun selects reachable authorized support, not just a rally point. |
| VEH-13 | Defend while immobilized | Existing | Core | Retain feasible fire and request support; disabled tracks cannot execute a withdrawal. |
| VEH-14 | Re-crew or capture an abandoned hull | Existing | Expansion | Reuse physical approach and crew transfer; coordinate escort and equipment availability. |
| VEH-15 | Deploy a smoke screen | New | Expansion | Requires fitted launchers, finite charges and the shared authoritative obscurant model. |
| VEH-16 | Choose ammunition or fire mode | New | Optional | Add only after inventory and weapon compatibility exist; costs and switch time are visible. |
| VEH-17 | Embark or disembark a section | New | Optional | Requires a transport capability, capacity ledger, safe approach and legal exit positions. |
| VEH-18 | Tow a disabled vehicle | New | Optional | Requires compatible recovery equipment, attachment state and combined-body navigation. |
| VEH-19 | Resupply and resume a vehicle assignment | Partial | Optional | General vehicle ammunition/fuel and service providers must be implemented first. |
| VEH-20 | Withdraw crew from an untenable hull | Partial | Expansion | Extend automatic abandonment with an explicit survival policy and conserved crew records. |

## Decision and execution contract

Use [18-1](18-1-action-framework-and-readiness.md) for lifecycle and priorities. An assignment identifies the supported force or area; a local action selects position, hull facing and movement mode. Keep turret and hull state separate. Assess known threats together so facing a minor contact does not expose the vehicle to a major one.

Evaluate a bounded shortlist of current, reverse, berm and route-connected positions, using execution's elevation, footprint, range and line-of-fire rules. Reserve destinations and passage. Short movements still consume a pathfinding budget.

Capability loss determines feasible actions: immobilized vehicles may fire or request recovery; mobile unarmed vehicles may seek support. Repair obeys the service contract. Smoke, passengers and towing require capabilities, conserved equipment and explicit interruption outcomes.

## Tasks

- [ ] 1. Connect current target, damage and orientation facts to the common action selector; preserve explicit focus targets and hard-hold constraints.
- [ ] 2. Deliver VEH-01/02/03/04/08/09/11 as a tank-plus-AA encounter using the existing map, meshes and weapons.
- [ ] 3. Deliver capability-based survival, repair requests and return-to-assignment behavior with [18-4](18-4-coordination-and-support-requests.md) and [18-10](18-10-logistics-medical-and-recovery.md).
- [ ] 4. Add persistent escort, infantry support and obstacle-clearance requests; test loss or retasking of either participant.
- [ ] 5. Integrate smoke after the minimum [18-9](18-9-information-and-electronic-warfare.md) sensor contract and [18-3](18-3-infantry-grenades-and-urban-actions.md) emitter/effect interface; other grenade actions are independent.
- [ ] 6. Scope transport, selectable ammunition and towing as separate optional increments after their physical and resource prerequisites exist.

## Acceptance scenarios

1. A stationary tank receives threats from two directions, chooses a defensible orientation and retains a useful shot without repeated pivoting.
2. AA already engaging a ground target responds to a newly observed urgent drone, then resumes its protective assignment.
3. A tank with a disabled gun reaches a valid repair provider; an immobilized tank stays put and requests assistance. Neither silently changes its capabilities.
4. Infantry crosses a narrow road while two vehicles yield, advance and regain formation without overlap or permanent deadlock.
5. A repair destination disappears or becomes inaccessible: the action releases reservations, reports failure and chooses a bounded fallback.
6. Optional passenger and tow fixtures conserve identities, capacity and damage through cancellation, destruction, deployment checkpoints and operation transfer.

## Interfaces and presentation

Touchpoints: `simulation.gd`, `tactical_director.gd`, `vehicle_damage.gd`, `field_ops.gd`, terrain and `resources/units.json`. [18-5](18-5-engineering-and-field-fortifications.md) owns engineering services, [18-4](18-4-coordination-and-support-requests.md) task claims, [18-11](18-11-command-interface-and-feedback.md) commands and [18-12](18-12-performance-and-validation.md) validation. Dependencies require their minimum interfaces, not completion of entire subplans.

Service and re-crewing rows reuse [18-10](18-10-logistics-medical-and-recovery.md)'s shared contracts; this plan adds vehicle-specific approach, capability decisions and physical recovery execution, not another service ledger.

Reuse current models; placeholder tow/boarding/smoke attachments declare their dimensions. Hull visuals follow authoritative orientation. Regional saves migrate equipment, crew and passengers without duplicating parked units; local escorts and routes restart per battlefield.

## Decisions

- Local autonomy follows player initiative and a bounded operating area; delegated support does not authorize new purchases.
- Core actions improve the existing roster. Optional equipment creates explicit costs and counterplay before additional models are commissioned.
- Durations, candidate counts and engagement distances are provisional game parameters to tune through the acceptance fixtures.

## Notes

Planning only. No gameplay implementation or measured speed improvement is claimed. Expansion and optional rows depend on the master plan's release gates.
