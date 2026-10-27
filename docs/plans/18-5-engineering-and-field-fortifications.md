# 18-5: Engineering and field fortifications

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Let infantry prepare limited local protection and engineers construct, maintain and alter useful battlefield positions through delegated, physical work.

## Baseline and scope

[Field operations](../../scripts/field_ops.gd) already provides paid construction, lines/queues, interruption/resume, refunds and barrier/wreck clearing. [Definitions](../../resources/field_units.json) include trenches, sandbags, berms, wire, barriers, nets and support posts. `sync_obstacles` publishes cover/movement/concealment effects; regional construction validates elevation.

Ordinary infantry digging, controlled wall passages, minefields and bridges need new contracts. Existing trenches are authored zones. This plan extends the current construction system.

## Action catalogue

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

## Infantry digging and engineer work

A delegated defense intent may permit shallow infantry positions. Eligibility depends on equipment, ground, slope, access and available security. Asphalt, structures, water and unsupported ground reject digging. Preparation costs time and authored inventory; spending remains within [18-11 authority](18-11-command-interface-and-feedback.md).

Engineers build deeper or reinforced positions through existing jobs. Sites retain footprint, access slots, owner, stage, integrity and material accounting. Planned, started, partially usable and complete stages publish geometry and protection together. Unfinished markers grant no full protection. Interruptions retain earned progress, completed physical work and paid sites while releasing the builder.

Core digging uses bounded terrain zones. Soldier placement and visuals must agree with protection geometry. If depth cannot be represented, present an explicit prepared-position abstraction. Continuous terrain deformation is outside Core.

## Delegation, shared geometry and persistence

[18-4 requests](18-4-coordination-and-support-requests.md) assign compatible engineers to real work points. Jobs report waiting/working/unsafe status, request security and release claims on cancellation or loss. Idle engineers select only authorized work; existing defenses require explicit dismantling assignments.

Placement considers firing faces, friendly routes, work/casualty access and vehicle width. Cover, exposure, navigation, rendering and destruction share geometry; changes invalidate affected caches and reservations. Wall breaches create actual traversal portals while retaining building ownership/destruction. Clearing and recovery arbitrate one claim per wreck.

Regional saves preserve forces/outcomes, not tactical works. New inventories use the campaign schema; works reset with a fresh tactical battlefield until tactical-world saving exists. Operation transfers create no free construction.

## Tasks

- [ ] 1. Integrate the [18-1 action contract](18-1-action-framework-and-readiness.md), preserving payment, refund, clearing and progress invariants.
- [ ] 2. Deliver ENG-01 and staged ENG-02 on eligible open ground, using shared work stages and one selected defense intent.
- [ ] 3. Connect useful placement and passage reservations for ENG-04 through ENG-07; share safe work/cover roles with [18-2 infantry](18-2-infantry-fire-and-movement.md).
- [ ] 4. Integrate ENG-11, ENG-12 and ENG-19 into the request lifecycle; cover builder loss, replacement, interrupted access and competing jobs.
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

Touchpoints: `FieldOps`, `Terrain`, `StructureDamage`, campaign inventories. Placeholder work poses and stage meshes require documented collision envelopes. [18-10](18-10-logistics-medical-and-recovery.md) owns medical behavior. This is unimplemented planning.
