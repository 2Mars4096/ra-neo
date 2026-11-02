# 18-2-1-2: Grenades and smoke

**Parent:** [18-2-1: M1 infantry defense](18-2-1-m1-infantry-defense.md)
**Status:** completed
**Goal:** Add finite infantry throws and authoritative optical smoke while preserving covering roles, player commands and physical exposure.

## Scope and baseline

This delivery completes section 2 on `codex/m1-section-2`, continuing completed section 1 at `d10682e`. It reuses the section 2 code from `26480fb`, retains section 1's corrected covering-fire and explicit/urgent target priorities, and corrects stale throw cleanup and smoke visibility during integration. The reviewed checkpoint is prepared for commit and publication.

Section 2 supplies the simulation command/preview API, bounded defensive-frag policy, projectile/smoke state and placeholder presentation. Contextual buttons, hotkeys and player-facing previews remain section 5. Regional inventory persistence and save migration remain section 6. Backup, digging and additional urban mechanics are separate work.

## Implementation components

| Component | Implementation | Acceptance |
|---|---|---|
| 1. Carried stock and claims | One frag and one smoke per newly capable member; reserve the actor and item during preparation. | Explicit empty inventory and casualties cannot regenerate stock; cancellation does not spend it; release spends once. |
| 2. Preparation and authority | One eligible thrower per group request, alternate-member selection, interruptible preparation and opt-in defensive frag. | New commands, lost support or unsafe allies cancel uncommitted work; Hold fire grants only the explicit throw; automatic decisions use observed threats and useful current cover. |
| 3. Flight and activation | Deterministic arcs, swept terrain/body collision, actual-impact blast and existing wound/suppression handlers. | No tunneling through thin geometry, no effect centered on a missed aim point, no unexplained wall/garrison/height bypass, and released objects survive retasking or thrower loss. |
| 4. Smoke and observations | Fixed authoritative cylinders shared by acquisition, firing, known-contact and fog queries. | Both factions lose blocked optical access, elevated rays can clear the cloud, deployment/expiry invalidate caches, and hidden movement does not refresh remembered contacts. |
| 5. Presentation and integration | Pooled payload meshes and smoke, a temporary throw pose, bounded queues and current regression evidence. | Presentation follows world state; section 1 covering/order behavior still passes; current tests and any native review are recorded separately from performance or balance claims. |

## Tasks

- [x] 1. Recover the section 2 implementation and tests onto the completed section 1 branch.
- [x] 2. Review stock, actor/item claims, group selection, explicit authority and defensive-frag preparation; prevent an obsolete canceled job from releasing roles now owned by a newer action.
- [x] 3. Review swept collision and blast exposure, including ally crossings and post-release survival.
- [x] 4. Review smoke sensing, fog/cache invalidation and covering-fire integration for ground and elevated observers; use exposed living member bodies with indexed/exhaustive parity, including wide sections.
- [x] 5. Check placeholder presentation and run the affected functional gate; record current source hashes and reproduced defects.
- [x] 6. Update tracking and prepare the reviewed section 2 checkpoint for commit and push.

## Behavior contract

- A throw request uses `Simulation.issue_throw(ids, payload, point)` and the shared `Throwables.preview_selection` rules. One accepted group request selects one eligible actor; a blocked nearest actor must not hide another valid choice.
- Preparation reserves rather than consumes stock. Release owns the single decrement and world projectile. An accepted replacement order releases the uncommitted actor/item claims; already released projectiles remain active. Delayed cleanup may release a member's cooperation roles only while that job still owns the member.
- Defensive frag is off by default. Enabling the simulation policy permits only a bounded stationary opportunity against at least two observed, exposed infantry with useful covering support. The release checks the current opportunity, support, path and allied exposure again. Smoke remains explicit.
- Blast follows actual impact and physical exposure. Both factions reject known allied risk before release, while allies entering the blast after release can still be hit.
- Smoke blocks optical rays within its actual volume for either faction. Acquisition and jammed local observation use exposed living member bodies, including members of wide sections beyond the anchor's ordinary query footprint. Indexed and exhaustive paths agree. Smoke does not erase contact memory, provide hidden live coordinates or alter already released fire-and-forget missile guidance.
- The initial balance values are fictional: 18-unit throw range; smoke radius 4.5, height 4 and lifetime 18 seconds. They are tuning parameters, not measured balance results.

## Verification

Use Godot 4.5.1. `python3 tools/check.py --group m1` selects `test_infantry_coordination.gd`, `test_throwables.gd` and `test_m1_optics.gd` at this checkpoint. Select affected targeting, readiness, action, garrison, elevation, visibility and projectile checks from `--group tactical` as appropriate.

The [current functional report](../evidence/m1-02-checks.json) records **22/22 selected tactical/core suites passing in 173 seconds**, without script or assertion failures. Its **280 M1 assertions** comprise 79 coordination, 145 throwable and 56 optics checks, all passing. The report records the actual selected suites, outputs and source hashes.

Two identical-test controls establish regression sensitivity:

- Before the stale-cleanup correction, the final throwable test reports **145 checks, 2 failures**; the corrected source reports **145 checks, 0 failures**.
- The final optics test against historical `26480fb` reports **56 checks, 11 failures**; current source reports **56 checks, 0 failures**.

Native Godot 4.5.1 review using OpenGL/llvmpipe completed **three captures, zero failures**, and all captures were visually inspected: [preparation](../images/m1-section2-01-preparation.png), [airborne fragmentation grenade](../images/m1-section2-02-flight.png) and [seven-puff smoke](../images/m1-section2-03-smoke.png). The [native review record](../evidence/m1-02-native-review.json) retains its authoritative state. This fixture drives the simulation API; it does not establish the later section 5 player controls.

These results verify functional integration and placeholder presentation. They do not establish frame rate, human playtest acceptance or balance. Campaign inventory persistence remains section 6.

## Decisions

- Preserve section 1's actual covering weapon/target behavior and player-order priority while adding throwable actor ownership.
- Use shared command and preview validation so later UI can expose the same acceptance rules.
- Retain physical collision and faction-symmetric friendly-fire rules; rendering does not decide hits or visibility.
- Keep preparation/projectile limits at 64 each, smoke at 32, and automatic review at at most two due sections per tick. These code bounds do not establish frame-time acceptance.

## Notes

There is no grenade refill service, room/interior throw system, ricochet/bouncing simulation or new sensor type in this section. Inventory is tactical until section 6 carries it across operation outcomes/retries. The wider urban, support and field-position catalogues remain open.
