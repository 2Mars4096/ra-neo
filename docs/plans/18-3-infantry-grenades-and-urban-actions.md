# 18-3: Infantry grenades and urban actions

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Add purposeful throwable and building interactions with finite resources, shared physical effects and understandable player authority.

## Baseline and scope

The [garrison system](../../scripts/garrison.gd) provides doorway entry and windows; [cover](../../scripts/cover_behavior.gd) provides corner fire; [structure damage](../../scripts/structure_damage.gd) provides breach states, collapse and blasts. `BREACHED` does not establish a walkable opening. The [simulation](../../scripts/simulation.gd) has delayed missiles, but no general throwable action or authoritative smoke screen.

This plan owns throwable delivery and building interactions. [18-9](18-9-information-and-electronic-warfare.md) owns smoke sensing; [18-5](18-5-engineering-and-field-fortifications.md) owns physical openings. Core uses authored entrances and abstract occupancy. Detailed rooms and independent upper-floor navigation remain optional.

## Action catalogue

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

## Throwable contract

A request identifies payload, actor, area, reason and authorization. Check capability, inventory, legitimate knowledge, game range, release position, trajectory and friendly exposure. Reserve one item and an action slot; recheck clearance, allies and command version before release.

The authoritative lifecycle is prepare, release, travel, activate and expire. Pre-release cancellation returns the reservation; release consumes it once. Subsequent orders or the thrower's death cannot delete the object. Deterministic travel uses bounded swept collision against buildings, elevation and relevant bodies. Collisions follow authored payload rules; rich bouncing is optional. Visual arcs follow authoritative trajectories.

Blast exposure must account for walls, openings, garrisons and height before reusing wound/damage handlers. The current radius helper does not establish that contract. Separate damage and suppression; apply one declared friendly-fire policy to both factions and previews. Automatic throws reject unacceptable ally exposure. Allies entering after release remain subject to the actual effect.

Smoke creates a versioned world volume consumed by sensors, targeting and presentation through 18-9. Declare optical/seeker interactions explicitly. Lifetime, cost and spread are game parameters; particles cannot determine gameplay. Reactions use observed/communicated danger rather than hidden impact coordinates or unseen countdowns.

## Urban execution rules

Entry, windows and exit share navigation reservations. New orders cancel uncommitted entry and provide exits for occupants. The first contested-building model exposes progress and occupancy changes without room simulation. Failed entry releases its doorway; integrity changes invalidate affected candidates and routes.

Evacuation distinguishes delegated defense from [explicit hard hold](18-11-command-interface-and-feedback.md). Survivors seek a bounded defensive position or request support through [18-4](18-4-coordination-and-support-requests.md). They must not immediately return to the unsafe building.

## Tasks

- [ ] 1. Define payload data, inventory reservations and authoritative throwable state through [18-1](18-1-action-framework-and-readiness.md) and [18-10](18-10-logistics-medical-and-recovery.md); preserve regional save validation for new inventory fields.
- [ ] 2. Build GRN-01 in one exterior fixture, including canceled preparation, collision, valid blast exposure, enemy parity and a synchronized placeholder arc.
- [ ] 3. Add GRN-02 only with the 18-9 smoke query contract; connect it to a concrete covered movement and backup scenario.
- [ ] 4. Extend URB-01, URB-02 and URB-06, including concurrent entry/exit requests and a damaged-building response.
- [ ] 5. Add GRN-03 and contested-entry/breach coordination after status effects and authored portals pass their own checks.
- [ ] 6. Keep distraction, illumination, search and elevated-post expansions gated on the sensing and geometry systems they need.
- [ ] 7. Run the acceptance cases and [18-12 validation](18-12-performance-and-validation.md), then tune inventory, reaction and effect parameters from playtests.

## Acceptance scenarios

- A teammate crosses before release: the throw delays, changes candidate or cancels without losing inventory.
- Thrower dies after release: the projectile finishes once; pause/resume and identical seeds preserve outcomes.
- A grenade strikes an intact wall: its effect follows actual impact and exposure; protected occupants receive no unexplained through-wall hit.
- Smoke interrupts observation during a joint advance: both factions lose the declared sensing capability while remembered contacts remain uncertain.
- A garrison starts evacuating as another section approaches its entrance: reservations avoid overlap and both groups retain valid orders.
- A breach closes or becomes blocked before arrival: the queued entry stops safely and requests another route.

## Decisions

- Grenades are occasional tactical commitments with finite inventory, not an automatic cooldown spam loop.
- Keep core urban interactions readable from the RTS camera. Full room simulation is outside the first delivery.
- Authored action parameters express fictional game balance; no real-world equipment specifications are required.

## Notes

Touchpoints: `Simulation`, `Garrison`, `StructureDamage`, `Terrain`, inventories and pooled effects. Use placeholder payload meshes, throw poses, landing cues and smoke volumes independent of authoritative state. No gameplay code or native validation accompanies this plan.
