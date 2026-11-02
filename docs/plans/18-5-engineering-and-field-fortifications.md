# 18-5: Engineering and field fortifications

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** in-progress
**Goal:** Let infantry prepare limited local protection and engineers construct, maintain and alter useful battlefield positions through delegated, physical work.

## Baseline and scope

[Field operations](../../scripts/field_ops.gd) already provides paid construction, lines/queues, interruption/resume, refunds and barrier/wreck clearing. [Definitions](../../resources/field_units.json) include trenches, sandbags, berms, wire, barriers, nets and support posts. `sync_obstacles` publishes cover/movement/concealment effects; regional construction validates elevation.

[M1 section 4](18-2-1-4-hasty-positions-and-upgrades.md) delivers local infantry digging and a paid engineer upgrade on `codex/m1-section-4`, continuing section 3 at `57f7fa8`. Existing and new trenches use authored terrain zones. General engineer dispatch, connected works, controlled wall passages, minefields and bridges remain outside this checkpoint.

## Action catalogue

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| ENG-01 | Dig shallow infantry protection | New | M1.4 | One rifle/AT/engineer member, nearby clear level soil, 18 seconds, no supply charge. |
| ENG-02 | Construct a staged fighting trench | Existing | M1.4 | Reinforce the same hasty site: one engineer, 50 supply, ten seconds; publish protection by stage. |
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

## Infantry digging and engineer work

M1.4 accepts explicit local work through `Simulation.issue_dig(ids, point)` and `upgrade_position(ids, site_id)`. Rifle, AT and engineer sections assign one available member to a clear, sufficiently level 7 × 2 soil footprint; the others remain available. Roads, structures, water and blocked access reject digging before commitment. Digging costs 18 seconds of actual work and no supply. The unfinished survey grants no cover; completion grants ordinary infantry cover and 120 maximum integrity.

An engineer reinforces the same site for the existing trench price of 50 supply and ten seconds of work. Completion grants dug-in protection and 320 maximum integrity; incoming damage remains. Interrupted upgrades retain hasty protection, progress and paid materials. Repeating current work preserves its actor and assignment; resuming paid work cannot charge twice. Cancellation and salvage refund only purchased materials, once. Broader engineer jobs continue to use the existing construction system.

Field-position jobs share actor/site claims and existing Resume/Cancel/clearing adapters. Pressure and hull yielding pause work; replacement orders release it. Accepted work clears obsolete reserve, wreck-recovery and spacing state, and ordinary automatic spacing respects the work anchor. Whole-footprint geometry, stage protection and procedural survey/earth/trench meshes share the same site. The work pose remains a placeholder. No terrain excavation is simulated. Jobs are capped at 64 and living sites at 96; work approaches and assignments have deadlines.

## Delegation, shared geometry and persistence

Generalized engineer dispatch through [18-4 requests](18-4-coordination-and-support-requests.md) remains planned. M1.4 uses explicit work orders, reports waiting/working/unsafe states and releases claims on cancellation or loss. Existing defenses require explicit dismantling assignments. M1.5 supplies contextual work buttons/hotkeys; M1.6 verifies digging and one paid upgrade alongside covering, grenades, smoke and reserve return in Harbor. Tactical works stay outside the campaign save.

Broader placement work must account for firing faces, friendly routes, work/casualty access and vehicle width. Cover, exposure, navigation, rendering and destruction must share geometry, with changes invalidating affected caches and reservations. Planned wall breaches must create actual traversal portals while retaining building ownership/destruction. Clearing and recovery must arbitrate one claim per wreck.

Regional saves preserve forces/outcomes, not tactical works. New inventories use the campaign schema; works reset with a fresh tactical battlefield until tactical-world saving exists. Operation transfers create no free construction.

## Tasks

- [ ] 1. Integrate the [18-1 action contract](18-1-action-framework-and-readiness.md), preserving payment, refund, clearing and progress invariants.
  - [x] M1.4 field positions use actor/site claims, accepted-order authority, retained progress and payment-aware refunds.
- [x] 2. Deliver the M1.4 ENG-01 and staged ENG-02 subset on eligible open ground through explicit local work orders; contextual controls are supplied by M1.5.
- [ ] 3. Connect useful placement and passage reservations for ENG-04 through ENG-07; share safe work/cover roles with [18-2 infantry](18-2-infantry-fire-and-movement.md).
- [ ] 4. Integrate ENG-11, ENG-12 and ENG-19 into the request lifecycle; cover builder loss, replacement, interrupted access and competing jobs.
  - [x] Route existing field-position Resume/Cancel/dismantling through compatible workers and shared work ownership; generalized dispatch remains open.
- [ ] 5. Add connected trenches, repairs and building improvements after geometry/accounting gates pass.
- [ ] 6. Implement tagged wall portals jointly with [18-3 urban actions](18-3-infantry-grenades-and-urban-actions.md); validate collision, sight, fire and structure collapse together.
- [ ] 7. Keep mine zones, surveys, clearance and crossings optional until sensing, authored assets and navigation-link prerequisites are complete.
- [ ] 8. Pass [18-12 validation](18-12-performance-and-validation.md), inspect native visuals and measure costs before expanding construction density.

## Acceptance scenarios

- Digging on soil, road, slope and water accepts only supported sites; rejected attempts consume nothing.
- Interrupt every work stage: protection matches progress, replacements resume and refunds remain bounded.
- A barrier crossing a friendly route preserves its designated gap or rejects before payment.
- A tank and nearby infantry reach berm/cover slots without overlap or terrain bypass.
- Competing wreck clearing/recovery requests produce one claim; completion invalidates the other safely.
- A building collapses after a portal opens: movement, cover, sight and rendering update together.

## Decisions

- Basic infantry preparation and specialist engineering share construction contracts but have different capabilities and scale.
- Combat pressure may pause work; the authorized job remains resumable.
- Rates, costs and protection are provisional; both factions share physical/knowledge rules.

## Notes

Touchpoints: `FieldPositions`, `FieldOps`, `Terrain`, `StructureDamage`, campaign inventories. [18-10](18-10-logistics-medical-and-recovery.md) owns medical behavior. The [section 4 plan](18-2-1-4-hasty-positions-and-upgrades.md) records checkpoint verification; broader engineering, native/hardware acceptance and construction-density expansion remain open here.
