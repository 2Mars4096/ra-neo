# Tactical action catalogue

**Status:** catalogue proposed; M0 foundation implemented and verified (58/58 integration suites).

This index accompanies [master plan 18](plans/18-unit-tactical-autonomy.md). It consolidates the action tables from the linked subplans. The subplans own prerequisites, decision rules, implementation tasks and acceptance scenarios; update this index when those source tables change.

Starting-point counts below describe the 2026-10-27 planning baseline. [M0](plans/18-1-1-m0-foundation.md) now implements readiness, stable/urgent targeting, casualty-aware strength and shared ownership/knowledge/planning contracts. That foundation does not complete the 160 domain entries or enable M1 throwables, support requests or infantry digging.

The catalogue contains **160 action and decision entries**: **81 Core**, **45 Expansion** and **34 Optional**. Starting points are **35 Existing**, **75 Partial** and **50 New**. These are planning entries, not a claim of that many independent new mechanics; domain-specific repair, observation and support choices reuse shared contracts.

## Reading the catalogue

- **Existing:** an authoritative primitive is present; its proposed decision/coordination extension still needs implementation.
- **Partial:** related machinery exists but the described action or policy is incomplete.
- **New:** the action needs a new authoritative gameplay mechanic.
- **Core:** proposed early scope across master milestones M0–M2; not every Core row is a prerequisite for M1.
- **Expansion:** later increments after the shared contracts and first slice work.
- **Optional:** separately gated systems or roster additions; previously deferred stranded-wounded rescue remains here.

All entries inherit player authority, real capability/resources, legitimate knowledge, shared collision/elevation and versioned cancellation rules. Action costs and timings are game-balance parameters. Planning does not enable any action in the running game.

## Coverage

| Subplan | Entries | Core | Expansion | Optional |
|---|---:|---:|---:|---:|
| [18-2: Infantry fire and movement](plans/18-2-infantry-fire-and-movement.md) | 17 | 11 | 5 | 1 |
| [18-3: Infantry grenades and urban actions](plans/18-3-infantry-grenades-and-urban-actions.md) | 14 | 5 | 5 | 4 |
| [18-4: Coordination and support requests](plans/18-4-coordination-and-support-requests.md) | 18 | 12 | 4 | 2 |
| [18-5: Engineering and field fortifications](plans/18-5-engineering-and-field-fortifications.md) | 19 | 9 | 6 | 4 |
| [18-6: Vehicles and ground support](plans/18-6-vehicles-and-ground-support.md) | 20 | 9 | 7 | 4 |
| [18-7: Air and drone operations](plans/18-7-air-and-drone-operations.md) | 20 | 10 | 5 | 5 |
| [18-8: Naval and shore operations](plans/18-8-naval-and-shore-operations.md) | 20 | 8 | 5 | 7 |
| [18-9: Information, observation and electronic warfare](plans/18-9-information-and-electronic-warfare.md) | 15 | 8 | 4 | 3 |
| [18-10: Logistics, medical support and recovery](plans/18-10-logistics-medical-and-recovery.md) | 17 | 9 | 4 | 4 |

## 18-2: Infantry fire and movement

[Full specification and acceptance scenarios](plans/18-2-infantry-fire-and-movement.md)

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| INF-01 | Adopt a protective posture | Existing | Core | Use observed pressure, available space and physical transition time. |
| INF-02 | Choose reachable protective cover | Existing | Core | Compare protection, fire and travel exposure; reserve a slot. |
| INF-03 | Track a useful target | Existing | Core | Retain aim; switch for explicit orders or urgent threats. |
| INF-04 | Reload during a suitable lull | Partial | Core | Prepare independently of target acquisition; coordinate teammates' readiness. |
| INF-05 | Cover a moving teammate | Partial | Core | Require an available weapon, suitable posture and useful fire. |
| INF-06 | Bound to the next position | Partial | Core | Obtain support and a reachable destination; an emergency escape may bypass the support wait. |
| INF-07 | Withdraw in alternating groups | Partial | Expansion | Keep a bounded rearward route and shared objective; never wait indefinitely for support. |
| INF-08 | Peek, fire and return to shelter | Partial | Core | Reserve protected and exposed positions; use a useful shot or observation goal. |
| INF-09 | Leave an ineffective firing position | Existing | Core | Change position after sustained failure or changed threats, with a switching penalty. |
| INF-10 | Watch an assigned sector | Partial | Core | Orient toward a sector or last observation; observation does not imply a known live target. |
| INF-11 | Hold fire for a conditional engagement | New | Expansion | Player-defined conditions and an explicit self-defense policy govern release. |
| INF-12 | Apply bounded suppressive fire | Partial | Expansion | Fire toward a legitimate observed area; spend ammunition and model suppression separately from damage. |
| INF-13 | Maintain useful spacing | Existing | Core | Adapt local separation to cover, passage width and known hazards without breaking the section leash. |
| INF-14 | Screen or accompany another unit | Partial | Expansion | Keep a persistent assignment and bounded offset through the coordination plan. |
| INF-15 | Recover a fallen specialist's equipment | New | Expansion | A reachable, identifiable equipment item and free carrier are required; pickup takes time. |
| INF-16 | Regroup after casualties or separation | Existing | Core | Use original strength and surviving roles; preserve retained orders and bounded recovery. |
| INF-17 | Cross an authored low obstacle | New | Optional | Requires a validated traversal link, clearance and animation; generic walls remain solid. |

## 18-3: Infantry grenades and urban actions

[Full specification and acceptance scenarios](plans/18-3-infantry-grenades-and-urban-actions.md)

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| GRN-01 | Throw a fragmentation grenade | New | Core | Use finite inventory, a valid trajectory, useful expected effect and a final ally-risk check. |
| GRN-02 | Throw a smoke grenade | New | Core | Place a screen for a concrete movement or observation task; consider obstructed friendly vision. |
| GRN-03 | Use a stun/concussion payload | New | Expansion | Requires a declared temporary status and occlusion model; no guaranteed disabling through walls. |
| GRN-04 | Deploy a distraction device | New | Optional | Creates an observable uncertain cue; enemies investigate according to their own knowledge and intent. |
| GRN-05 | Deploy illumination | New | Optional | Requires a meaningful darkness/visibility system; reveals the deployment as well as the lit area. |
| URB-01 | Stage and enter a garrison | Existing | Core | Reserve doorway and occupancy slots; coordinate the queue and leave capacity for exit. |
| URB-02 | Assign useful firing windows | Existing | Core | Match weapons and known threats to available posts; avoid duplicate assignments. |
| URB-03 | Shift between firing apertures | Partial | Expansion | Reserve the next post and model a bounded transition; no instant protection-changing relocation. |
| URB-04 | Guard an entrance or exit | Partial | Expansion | Keep a persistent sector and self-defense policy without blocking friendly passage. |
| URB-05 | Contest an occupied building | Partial | Expansion | Use a staged exterior/entrance encounter with explicit occupancy limits and a cancelable approach. |
| URB-06 | Evacuate a failing building | Partial | Core | React to known structural damage under normal initiative; retain the defense objective. |
| URB-07 | Coordinate passage through a created breach | New | Expansion | Wait for a real accessible opening, then reserve movement capacity; destruction alone is insufficient. |
| URB-08 | Search a recently occupied structure | New | Optional | Resolve authored observation points and uncertain contact memory; never reveal all occupants automatically. |
| URB-09 | Occupy an authored elevated post | Partial | Optional | Requires valid floor/access geometry and height-aware sight, fire and evacuation rules. |

## 18-4: Coordination and support requests

[Full specification and acceptance scenarios](plans/18-4-coordination-and-support-requests.md)

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| COOP-01 | Call nearby backup | Partial | Core | Request an existing authorized reserve; bounded area and no purchase implied |
| COOP-02 | Answer a backup request | Partial | Core | Accept only when capability, route and assignment allow; reserve one responder |
| COOP-03 | Cover another unit's movement | Partial | Core | Verify available weapon, ammunition and useful observation/fire lane |
| COOP-04 | Request replacement cover | New | Core | Support loss triggers a replacement or changed movement, not duplicate claims |
| COOP-05 | Maintain an escort/protection assignment | Partial | Core | Persistent protected-unit reference and bounded separation |
| COOP-06 | Request reconnaissance | Partial | Core | Ask for an observation area; completion requires useful sensed information |
| COOP-07 | Request anti-air protection | Partial | Core | Dispatch an available protecting unit without emptying a higher-priority guard |
| COOP-08 | Request local smoke support | New | Expansion | Request an effect and duration; actual provider owns inventory and release |
| COOP-09 | Request suppression or fire support | Partial | Expansion | Location knowledge, permitted provider and ally-risk checks; finite assignment |
| COOP-10 | Request engineer clearing/fortification | Partial | Core | Site/task reference and authorized construction allowance required |
| COOP-11 | Request medical assistance | Partial | Core | Local existing care first; stranded rescue remains gated Optional scope |
| COOP-12 | Request repair or ammunition service | Partial | Core | Choose a capable reachable provider; no free replenishment |
| COOP-13 | Request a relief or reserve handover | New | Expansion | New defender must be ready before old defender leaves when feasible |
| COOP-14 | Coordinate a short advance or withdrawal | Partial | Expansion | Reserve movers and supporters with explicit stop/failure conditions |
| COOP-15 | Report unavailable or delayed support | New | Core | Explain no provider, route, communication or resource; bounded retry |
| COOP-16 | Cancel support and resume assignment | Partial | Core | Resume only an unchanged valid assignment, never a superseded order |
| COOP-17 | Request transport or recovery towing | New | Optional | Requires actual transport/tow capabilities and capacity first |
| COOP-18 | Request additional purchased reinforcements | Partial | Optional | Suggest an existing purchase or use an explicitly delegated spending cap |

## 18-5: Engineering and field fortifications

[Full specification and acceptance scenarios](plans/18-5-engineering-and-field-fortifications.md)

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| ENG-01 | Dig shallow infantry protection | New | Core | Require equipment, eligible ground and delegated defense; consume work time. |
| ENG-02 | Construct a staged fighting trench | Existing | Core | Build authored segments with stage-specific protection. |
| ENG-03 | Connect trench segments | Partial | Expansion | Validate junctions, entrances, capacity and physical transitions. |
| ENG-04 | Build sandbag protection | Existing | Core | Choose an authorized face with reachable soldier slots. |
| ENG-05 | Build and orient a vehicle berm | Existing | Core | Match the defense direction; validate slope, hull space and approach. |
| ENG-06 | Place wire | Existing | Core | Preserve friendly passage and existing tracked crushing. |
| ENG-07 | Place vehicle barriers | Existing | Core | Preserve access gaps and shared mobility-profile obstruction. |
| ENG-08 | Install concealment netting | Existing | Expansion | Require an authorized site and declared concealment effect; visual camouflage alone changes no detection. |
| ENG-09 | Improve an occupied building | Partial | Expansion | Supported structures share protection, capacity and destruction data. |
| ENG-10 | Repair damaged field works | Partial | Expansion | Reserve supplies and access; restore integrity without recreating destroyed geometry for free. |
| ENG-11 | Clear wire or a field barrier | Existing | Core | Reach a valid work point; enemy work requires knowledge. |
| ENG-12 | Clear a vehicle wreck | Existing | Core | Retain timed work; coordinate passage and competing recovery jobs. |
| ENG-13 | Open a designated wall passage | Partial | Expansion | Only tagged breachable geometry; create and validate an actual portal before routing through it. |
| ENG-14 | Survey and mark a suspected hazard | New | Optional | Requires hazard sensing and uncertain knowledge; discovery is not automatic global disclosure. |
| ENG-15 | Place an authored mine zone | New | Optional | Requires explicit area authorization, finite inventory, discoverability and consistent friendly interaction. |
| ENG-16 | Clear a known mine zone | New | Optional | Requires the hazard contract, safe work access and interruptible progress; never remove unseen hazards globally. |
| ENG-17 | Establish a limited crossing | New | Optional | Authored crossing sockets, load/domain limits and navigation links precede a bridge or temporary span. |
| ENG-18 | Build observation or support posts | Existing | Expansion | Authorized jobs retain distinct observation, repair, aid and supply rules. |
| ENG-19 | Dismantle and salvage friendly works | Existing | Core | Explicitly assigned removal preserves current partial refund rules and avoids double refunds. |

## 18-6: Vehicles and ground support

[Full specification and acceptance scenarios](plans/18-6-vehicles-and-ground-support.md)

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

## 18-7: Air and drone operations

[Full specification and acceptance scenarios](plans/18-7-air-and-drone-operations.md)

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

## 18-8: Naval and shore operations

[Full specification and acceptance scenarios](plans/18-8-naval-and-shore-operations.md)

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

## 18-9: Information, observation and electronic warfare

[Full specification and acceptance scenarios](plans/18-9-information-and-electronic-warfare.md)

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| INT-01 | Observe and classify a contact | Existing | Core | Use actual sensors, geometry and range; allow an initially uncertain type. |
| INT-02 | Retain and age a lost contact | Partial | Core | Store the last observation and an expanding uncertainty area; never follow hidden coordinates. |
| INT-03 | Share a contact report | Existing | Core | Attach source, timestamp and confidence; sharing obeys the available link. |
| INT-04 | Watch an assigned sector | Partial | Core | Allocate attention to a bounded arc; ordinary peripheral detection remains explicit. |
| INT-05 | Investigate a sound cue | New | Expansion | Move toward an approximate area only when initiative permits; a sound supplies no exact target. |
| INT-06 | Hold fire to preserve concealment | Partial | Expansion | Requires player policy; define the self-defence exception and exposure after firing. |
| INT-07 | Mark an observed area for support | Partial | Core | Report observation age and uncertainty to the request broker, without promising a responder. |
| INT-08 | Reassess sight and aim through smoke | New | Core | Apply one authoritative optical-occlusion model to acquisition, tracking and UI. |
| INT-09 | Warn nearby partners of danger | Partial | Core | A local warning may work without radio; recipients receive only what the sender perceived. |
| INT-10 | Relay a report between separated groups | New | Expansion | Requires an eligible relay and a bounded delivery model; prevent duplicate reports. |
| INT-11 | Reposition to restore communications | Partial | Expansion | Stay inside the assigned leash and evaluate exposure; do not abandon a hard hold. |
| INT-12 | Execute a lost-link instruction | Existing | Core | Continue the last accepted intent or a preselected safe fallback; keep local defence available. |
| INT-13 | Jam a designated communications area | Partial | Optional | Existing scripted jamming is the baseline; controllable equipment, costs and counterplay are new. |
| INT-14 | Change an emitter's operating mode | New | Optional | Only after emission detection has gameplay meaning; switching has a visible trade-off. |
| INT-15 | Verify a suspected decoy | New | Optional | Requires a decoy mechanic and additional observations; no special access to true entity labels. |

## 18-10: Logistics, medical support and recovery

[Full specification and acceptance scenarios](plans/18-10-logistics-medical-and-recovery.md)

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| SUP-01 | Return for ammunition and resume | Partial | Core | Opt-in for player units; choose a reachable source and retain an order version. |
| SUP-02 | Reserve service at a supply point | Existing | Core | Extend replenishment with a bounded queue; do not promise unavailable service. |
| SUP-03 | Request a supply delivery | New | Expansion | Requires an actual authorized provider, stock and delivery route. |
| SUP-04 | Transfer compatible ammunition locally | New | Expansion | Move inventory between holders once; respect reserve minima and interrupted transfer rules. |
| SUP-05 | Select support from remaining capabilities | Partial | Core | A mobile unarmed vehicle and an immobilized armed one need different help. |
| SUP-06 | Seek a suitable repair position | Partial | Core | Reachable service capability and known route risk matter more than nearest distance. |
| SUP-07 | Perform component repair | Existing | Expansion | Extend existing timed repairs with job ownership, capacity and interruption accounting. |
| SUP-08 | Prioritize nearby casualties | Partial | Core | Consider urgency, exposure and available coverage; avoid assigning every able member. |
| SUP-09 | Stabilize a squadmate | Existing | Core | Preserve present treatment and wound rules; share role availability with the squad. |
| SUP-10 | Drag a casualty into nearby shelter | Existing | Core | Preserve real movement and the section leash; an unsafe route may be rejected. |
| SUP-11 | Carry a casualty with the section | Existing | Core | Carrying reduces available people and movement capability; no invisible duplicate casualty. |
| SUP-12 | Receive aid-post treatment | Existing | Core | Reserve access when crowded and reconsider if the post becomes unsafe or is destroyed. |
| SUP-13 | Re-crew or capture an abandoned hull | Existing | Expansion | Commit eligible personnel explicitly; preserve the current hull/component constraints. |
| SUP-14 | Arrange recovery of an immobilized vehicle | Partial | Optional | Clearing a wreck already exists; moving a recoverable hull needs a new recovery provider and physical contract. |
| SUP-15 | Replace lost crew or personnel | Partial | Optional | Existing component repair includes crew restoration; a general replacement system needs roster and supply rules. |
| SUP-16 | Replenish fuel or battery capacity | New | Optional | Requires the corresponding finite resource and a compatible service source first. |
| SUP-17 | Collect stranded wounded outside the section | New | Optional | Previously deferred by the player; remains parked until separately activated. |

## Shared foundations

- [18-1: Action framework and readiness](plans/18-1-action-framework-and-readiness.md): one lifecycle and capability/reservation contract.
- [18-11: Command interface and feedback](plans/18-11-command-interface-and-feedback.md): compact intent, context actions and understandable state.
- [18-12: Performance and validation](plans/18-12-performance-and-validation.md): event response, bounded work, physical/information invariants and measured acceptance.

Prepared against regional-operations baseline `f5916e8` on 2026-10-27. No new gameplay behavior or measured performance is represented by this index.
