# 18-10: Logistics, medical support and recovery

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** in-progress
**Goal:** Help units maintain combat readiness, obtain appropriate support and resume their assignment without duplicate resource spending or loss of campaign state.

## Baseline and ownership

[infantry.gd](../../scripts/infantry.gd) implements wounds, stabilization, dragging, carrying and treatment. [field_ops.gd](../../scripts/field_ops.gd) supplies aid/repair posts and obstacle/wreck clearing. [vehicle_damage.gd](../../scripts/vehicle_damage.gd) implements component repair and re-crewing/capture. [simulation.gd](../../scripts/simulation.gd) has finite AT missiles, nearby replenishment and enemy automatic return. Player automatic return and general finite reserve ammunition are absent.

[regional_campaign.gd](../../scripts/regional_campaign.gd) now saves a version-2 roster: M0 adds assigned strength, stable member IDs, partial magazines and equipment ownership to the existing wounds, missiles, damage, supply and deployment checkpoints. Version-1 migration and specialist-loss/resource-conservation fixtures are part of [18-1-1](18-1-1-m0-foundation.md). Reload/action timers and tactical contacts remain transient. This plan owns later replenishment, service accounting and equipment migration, using [18-1](18-1-action-framework-and-readiness.md) reservations and [18-4](18-4-coordination-and-support-requests.md) requests. Domain plans own movement/execution.

## Action catalogue

An existing primitive still needs the proposed selection, coordination or accounting work.

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

## Service and resource rules

Separate original strength, effective personnel, wounds and recoverable health. `Infantry.capacity()` excludes downed/dead members; retain its healing purpose rather than using it for original strength. Equipment belongs to holders or recoverable world records; [18-2](18-2-infantry-fire-and-movement.md) and [18-3](18-3-infantry-grenades-and-urban-actions.md) own recovery/consumption actions.

A service job contains requester, provider, reserved capacity, destination, resource, progress, interruption reason and assignment version. An immobilized vehicle cannot drive to a post; an aid post cannot repair a gun. Local aid retains existing safety conditions. Leaving an assignment requires delegated initiative; newer orders invalidate automatic return.

Use one transaction identity across reservation, consumption, delivery, cancellation and refund. Grenade executors consume at release; replenishment requires an explicit source. Refund only unconsumed reservations. Define destroyed-stock, partial-work and interrupted-transfer outcomes; restarting cannot generate stock. Preserve the single-supply economy initially. General ammunition/fuel stocks require later capacities and replenishment rules.

Use the shared request broker, limit claims, expire abandoned jobs and reassess lost providers. [18-5](18-5-engineering-and-field-fortifications.md) owns obstacle/wreck clearing; this plan coordinates access and service accounting.

## Persistence contract

Inventory, specialist ownership and new classes require versioned roster migration. Define conservative old-save defaults, retain casualty slots and preserve backups on failure. Cover checkpoints, retry, repeated outcome saving, parked domains and failed writes. Deduplicate purchased-but-undelivered resources before refunds.

Unrecovered world equipment is lost when the battlefield ends unless a separately implemented salvage rule explicitly extracts it. Rebuilding a section or applying migration defaults cannot restore a lost launcher or other specialist item. A recovered item persists on its surviving holder; retry restores exactly the pre-battle checkpoint and its equipment state.

Optional transport shares one durable carriage relation here: each section has one deployed, embarked, parked or lost state and at most one stable carrier ID. The roster represents that section once; seat counts and domains are derived from the same relation. For the first transport increment, passengers remain with an incompatible parked carrier and receive no off-map simulation; the player must disembark them at a legal site before leaving if they should deploy independently next time. The atlas must show that consequence before confirming withdrawal. Carrier loss resolves passengers once under the declared survival model, never by retaining a second free section. Domain plans own actual boarding/landing movement.

Requests, reservations, smoke and construction positions end with the battlefield. Inventory persists at existing checkpoint/outcome boundaries. Parked forces receive no healing, replenishment or timer progression without an explicit operational rule.

Distinguish in-battle cancellation from ending the whole tactical simulation. Before an operation transition, release unconsumed reservations, settle completed service transactions once and normalize durable holder/passenger records. Already released equipment stays consumed; unresolved transient projectiles/effects end with the departing battlefield without a refund or off-map continuation. Snapshot this settled state through the existing outcome-save contract. A failed save or transition preserves the existing recoverable session and must not repeat settlement charges on retry.

## Tasks

- [ ] 1. Audit medical strength and capability checks; implement the minimal service/reservation contract with the action framework.
- [ ] 2. Deliver opt-in AT resupply-and-return, capability-aware repair selection and safe service queues using current facilities.
- [ ] 3. Integrate buddy-aid/drag/carry roles with covering and movement assignments; preserve the deferred evacuation scope.
- [ ] 4. Add throwable replenishment and persistent equipment fields with transaction and migration tests before grenades enter a regional campaign.
  - [x] M0 existing-roster magazine/equipment/assigned-strength persistence and version-1 migration. Throwable stock and replenishment remain M1.
- [ ] 5. Extend re-crewing and optional delivery/transfer jobs after actual providers and stock exist.
- [ ] 6. Evaluate recovery vehicles, personnel replacement and finite fuel/batteries as separately enabled expansion work.
- [ ] 7. Pass [18-12](18-12-performance-and-validation.md) accounting, persistence and congestion gates; expose concise status through [18-11](18-11-command-interface-and-feedback.md).

## Acceptance scenarios

- An empty AT team at Rail Valley obtains supply and resumes its assignment; a newer order cancels that return, and a destroyed source produces one revised request.
- A Harbor casualty and concurrent reload preserve covering capacity; treatment cannot resurrect a dead member.
- A disabled-gun tank seeks suitable support; an immobilized tank requests assistance instead of receiving an impossible route.
- Two units compete for one supply allocation; cancellation, provider loss and repeated processing cannot duplicate inventory or refunds.
- Transfer from South Inlet to Limestone Pass parks incompatible ships and preserves inventory/damage. Retry restores the deployment checkpoint with no extra supplies.
- With optional transport enabled, an embarked land section transfers inland with its incompatible carrier: both park, exactly one section identity survives, and the atlas explains its unavailable status. Legal disembarkation before transfer makes the same section independently deployable.
- An AT specialist falls: compare recovered and unrecovered launcher outcomes on withdrawal, migration and checkpoint retry. Lost equipment never reappears through default squad reconstruction.

## Decisions

- Automatic support operates inside delegated authority; it does not independently purchase reinforcements or begin expensive construction.
- Use existing posts and service markers first; future provider placeholders require footprints, attachment points and capacity.

## Notes

Baseline: `f5916e8`. Selection policies, transactions and migrations are planned; gameplay, saves and economy remain unchanged.
