# 18-2: Infantry fire and movement

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Make individual soldiers prepare, observe, fight, move and assist one another coherently while preserving the player's objective.

## Baseline and scope

At regional-operations `f5916e8`, [infantry](../../scripts/infantry.gd), [cover behavior](../../scripts/cover_behavior.gd) and [the tactical director](../../scripts/tactical_director.gd) already implement individual wounds, aim, magazines, cover, corner firing, staggered movement, contact reactions, flanking, aid and dragging. Long-distance navigation remains section-based. The new policies below are unimplemented.

The [foundation plan](18-1-action-framework-and-readiness.md) owns corrections for quiet reloads, survivor-relative strength and competing action priorities. This plan owns the soldier behaviors using them.

## Action catalogue

These are individual executors of shared assignments. Medical actions and ammunition transfer are catalogued under the recovery plan's SUP IDs.

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

## Decision and execution rules

Each soldier has one primary action and compatible readiness work. Roles reserve availability so decisions cannot count a member twice. Support claims record sector, partner and expiry; losing ammunition, firing opportunity or consciousness invalidates them. A bound can pause, find another helper or choose an urgent escape. Mutual waiting must have a timeout.

Peeking uses two reachable positions and swept clearance. Protection follows actual position and posture. Repeated peeking cannot arbitrarily reset enemy preparation. New player orders replace the action; committed shots still resolve.

Suppression fire uses an observed area or valid contact memory, a duration, ammunition budget and stop conditions. Friendly crossings, stale knowledge or canceled support trigger reconsideration. Damage still follows shared exposure rules. Existing local aid and dragging remain; stranded-wounded rescue stays optional under [recovery](18-10-logistics-medical-and-recovery.md).

## Tasks

- [ ] 1. Integrate the foundation action contract and separate assigned strength, effective strength, healing capacity and readiness; preserve existing wound bookkeeping.
- [ ] 2. Deliver INF-01 through INF-06 and INF-13 as one three-person encounter: independent reload, stable target tracking, valid cover reservations and verified supporting availability.
- [ ] 3. Add INF-08 through INF-10 with bounded position candidates, contact memory and explicit failure reasons; profile cover work before widening searches.
- [ ] 4. Integrate INF-16 with the recovery plan's SUP-08 through SUP-12 and caregiver reservations; verify that treatment cannot silently remove all available support.
- [ ] 5. Add expansion actions through shared coordination and inventory contracts; introduce equipment identity before INF-15 and ammunition-transfer SUP-04.
- [ ] 6. Consider INF-17 only after authored navigation links and terrain contracts exist; document unsupported obstacle types.
- [ ] 7. Pass the acceptance scenarios and native presentation review, then update implementation and measured-validation records.

## Dependencies and code touchpoints

[18-1](18-1-action-framework-and-readiness.md) supplies action state; [18-4](18-4-coordination-and-support-requests.md) assignments; [18-9](18-9-information-and-electronic-warfare.md) contact memory; [18-10](18-10-logistics-medical-and-recovery.md) inventories/medical services; [18-11](18-11-command-interface-and-feedback.md) initiative; [18-12](18-12-performance-and-validation.md) budgets/telemetry. Integration points: `Infantry.move`, `Cover._update`, `Simulation.infantry_combat`, `section_weapon`, `TacticalDirector.update` and `contact_drill`.

## Acceptance scenarios

- Three soldiers, one empty magazine and one moving member: a claimed covering member must remain genuinely available, or the claim must fail visibly.
- Two nearby enemy sections: stable tracking completes useful shots while an explicit target or urgent threat can still take precedence.
- Cover destroyed during a peek: protection and reservations disappear correctly; the soldier adopts a feasible fallback.
- Specialist falls: the launcher stays attached to its equipment record until a survivor completes recovery; interruption cannot duplicate it.
- Casualty during a bound followed by a player retreat: aid, support and routes release correctly; the retained order is not restored over the new command.

## Decisions

- Keep detailed actions under a small number of player intents. Most soldiers' choices are automatic within delegated initiative.
- New timing and scoring values are provisional game-balance parameters. Validate action completion and visible responsiveness before changing weapon preparation times.
- Both factions use the same capability and knowledge rules.

## Notes

Use current rigs with placeholder watching, reloading, covering and pickup poses. Peeking requires real actor displacement; cosmetic leaning grants no protection. No implementation or new performance result accompanies this plan.
