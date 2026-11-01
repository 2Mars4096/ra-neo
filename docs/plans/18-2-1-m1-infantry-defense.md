# 18-2-1: M1 infantry defense

**Parent:** [18-2-infantry-fire-and-movement](18-2-infantry-fire-and-movement.md)
**Status:** in-progress
**Goal:** Deliver coordinated infantry defense with finite grenades, optical smoke, real nearby backup and staged field positions through compact controls.

## Delivery boundary

The user authorized M1 after M0 was implemented and requested implementation sections with partial commits on a separate branch. Work continues from M0 `5850504` on `codex/unit-tactics-m1`. The recovered local implementation comprises `16d820a` and its review commit `6149686`; neither had been published when this pass fetched GitHub. Their prior verified evidence is retained below. Current publication review is in progress, including the remaining combat, support and command-feedback corrections.

This is the M1 vertical slice across plans 18-2/3/4/5/9/10/11/12; it does not complete those plans' full catalogues or enable M2 vehicle, aircraft and naval assignments.

## Implementation sequence

Use the following sections as implementation and review units. M0 is the completed foundation. The recovered commits already contain all six sections; the current pass preserves that work, reviews the remaining integration boundaries and publishes completed checkpoints on the M1 branch. A recovered implementation is not yet a passing result for subsequent edits.

| Section and scope | Dependencies | Source modules and review checks | Current status |
|---|---|---|---|
| **M1.1 — Coordinated cover and movement.** Reserve a genuinely ready covering member; retain its useful position, replace lost support and permit a bounded urgent escape. | M0 action ownership, readiness, observations and planning admission. | `infantry_coordination.gd`, `infantry.gd`, `cover_behavior.gd`; `test_infantry_coordination.gd` checks actual weapon/ray, role loss, movement and order authority. | Implementation recovered; publication review in progress. |
| **M1.2 — Fragmentation and optical smoke.** Finite stock, cancelable preparation, one release charge, swept travel, physical blast and height-aware smoke. | M1.1 for delegated defensive throws; M0 actor/item claims and sensing. | `throwables.gd`, `simulation.gd`, `tactical_effects.gd`; `test_throwables.gd` and `test_m1_optics.gd` check interruption, allies, alternate actors, exposure and altitude-dependent fog. | Implementation recovered; remaining optics correction under review. |
| **M1.3 — Existing-reserve backup.** Delegate a nearby section, claim one responder, require useful service and return only to its unchanged assignment. | M1.1 capability checks; M0 assignment versions, observations and bounded routing. | `support_requests.gd`; `test_support_requests.gd` checks actual support weapons, exclusive leases, radio loss, deadlines and retasking. | Implementation recovered; work-order cancellation boundaries under review. |
| **M1.4 — Hasty positions and engineer upgrades.** Dig free shallow cover, retain interrupted progress, then reinforce the same site with one paid upgrade. | M1.1 covering readiness; M1.3 replacement-order ownership; existing field geometry/accounting. | `field_positions.gd`, `field_ops.gd`, `field_models.gd`; `test_field_positions.gd` plus existing engineering suites check actual protection, covering weapons, accepted/rejected work orders and single payment/refund. | Implementation recovered; support and work integration under review. |
| **M1.5 — Controls and feedback.** Contextual commands, targeting previews, Hold fire, Reserve/Auto Frag toggles and concise real-action status. | M1.1–M1.4 authoritative APIs and rejection reasons. | `tactical_interface.gd`, `battle.gd`, `hud.gd`, `battlefield_interface.gd`; `test_m1_commands.gd` and `test_field_ui.gd` check real input, cancellation, partial radio acknowledgements, backup status and layout. | Implementation recovered; command-feedback correction under review. |
| **M1.6 — Persistence and integration.** Preserve per-member equipment through campaign outcomes/retry and migrate old saves; combine the sections in Harbor, validate and publish. | M1.2 inventory identity; M1.1–M1.5 integration; existing campaign checkpoint boundary. | `regional_campaign.gd`, `tools/check.py`; `test_m1_persistence.gd`, `test_m1_defense.gd`, tactical regression gate and `m1_native_review.gd` check zeros/casualties, migration, concurrent actions and native presentation. | Implementation and prior evidence recovered; current verification, tracking and branch publication pending. |

Complete each correction with its affected checks before committing a checkpoint. M1.6 closes the current review after combined evidence and documentation describe the actual branch state. Human balance, long-session and supported-hardware performance acceptance remain separate open gates.

## Tasks

- [x] 1. Reserve genuinely capable covering partners for individual bounds; revalidate ammunition, readiness, observed threat and actual fire lanes. Preserve the coverer's position and allow replacement or an explicit urgent escape.
- [x] 2. Add finite per-member frag/smoke stock, actor/item claims, interruptible preparation, swept travel, authoritative effects and single release consumption.
- [x] 3. Connect smoke to optical sensing, fog, targeting and height-aware rays; preserve existing released fire-and-forget missile behavior.
- [x] 4. Dispatch one explicitly delegated existing infantry reserve, require useful service, bound its lease/retries and return only to the unchanged assignment.
- [x] 5. Add local infantry digging and an engineer upgrade on the same physical site; preserve unfinished progress, stage protection and single payment/refund accounting.
- [x] 6. Add contextual commands, targeting previews, Hold fire, optional defensive frag delegation, actor poses, smoke/projectile rendering and campaign schema migration.
- [x] 7. Preserve prior combined regression coverage and native Harbor review: 71 passing suite results, 466 M1 checks and four inspected captures; retain the full-run/focused-rerun evidence and remaining limits.
- [x] 8. Update implementation tracking and prepare the isolated M1 review branch.
- [x] 9. Recover the previous candidate review: alternate throwers at blocked corners, actual specialist support weapons, digging/upgrade support cancellation, old engineer-save migration and its native evidence.
- [ ] 10. Finish the six-section publication review: integrate remaining optics, ordinary engineer-work and command-feedback corrections; verify affected behavior, update the evidence and tracking, and commit/push the completed checkpoints to the separate M1 branch.

## Implemented rules

| Area | M1 behavior |
|---|---|
| Cooperation | A coverer must be alive, available, loaded, settled, permitted to fire and able to reach the observed threat with its real weapon ray. It holds its actual firing position and cannot voluntarily top off while a teammate depends on it. Reload, casualty, suppression, smoke or forced hull avoidance invalidate the role. An exposed mover finishes its validated short shelter move if support is lost. An observed threat the section cannot engage can justify a validated local screened shelter move, explicitly labeled unsupported; it cannot justify an exposed flank or override Move/Hold/Retreat. |
| Inventory | New capable infantry start with one frag and one smoke each. A selected group requests one throw, choosing one eligible member. Reservation does not spend stock; release spends once. Lost holders do not donate or regenerate equipment. There is no grenade refill service in M1. |
| Manual throws | G/V selects payload; the next valid point chooses an available member with a safe arc, starts preparation and replaces the selected section's current command with a hold at its position. A blocked nearest member does not hide another member's valid throw. New commands cancel uncommitted work. Hold fire permits only the explicitly requested throw. Released objects survive retasking, casualty and cancellation. |
| Defensive frag | AUTO FRAG is off by default. A settled, free-fire section may use carried frag stock against at least two currently observed, exposed infantry when a useful covering partner is available. Reviews are bounded and releases separated; opportunity, current partner, command, arc and allied exposure are rechecked before release. Smoke remains manual. |
| Flight and blast | Fictional 18-unit range, a deterministic arc, bounded swept collision and stop-on-contact behavior. Blast uses actual impact, per-body exposure, walls, height, garrison protection and existing wounds/suppression. Both factions reject known allied risk before release; allies entering later can be hit. |
| Optical smoke | One fixed cylinder of radius 4.5, height 4 and lifetime 18 seconds. It blocks either team's optical ray and invalidates visibility caches on deployment/expiry. A sufficiently elevated ray can clear it. Presentation follows the authoritative volume; particles do not decide visibility. |
| Backup | RESERVE explicitly delegates a connected idle/held infantry section. B requests existing local assistance without spending or spawning. One provider owns the lease, moves normally, provides four seconds of useful readiness/observation or fire support, then returns to its unchanged held assignment. Copied infantry contacts and unknown frontage require usable rifle stock/range rather than an operator's launcher. New accepted orders, including digging/upgrades, revoke reserve delegation and stale return work. |
| Communication | Accepted support retains its exclusive lease through radio loss, preventing a duplicate dispatch. Lease expiry, provider loss, changed assignments, blocked routes and missing readiness produce bounded failure/return behavior. Remembered contacts are copied facts, not live hidden targets. |
| Hasty position | D accepts nearby clear, sufficiently level soil. One rifle/AT/engineer member approaches and works for 18 seconds; the other members remain available. No supply charge. The unfinished marker gives no protection; completion grants ordinary cover with 120 integrity. |
| Reinforcement | U with an engineer selects a completed shallow position. The existing trench price (50 supply) funds ten seconds of work on the same site. Stage 2 grants the existing dug-in protection and 320 integrity. Hasty protection remains during an interrupted upgrade. No terrain excavation is simulated. |
| Work interruption | Pressure can pause the actor; accepted new orders release it. The site keeps paid materials and earned progress. Resume uses an eligible worker; repeated current commands preserve the same action/worker rather than charging or rerouting again. Cancel/salvage cannot refund free digging or duplicate paid refunds. |
| Persistence | Campaign version 3 adds per-member throwable stock, with version-1/2 and nested retry migration, including older engineer records from the field-unit definitions. Explicit empty and zero stock stay empty, casualties stay lost, and actual released inventory carries between operations. Actor tasks, projectiles, smoke, requests and tactical works remain transient. |

## Controls and feedback

G frag, V smoke, D dig, U engineer upgrade, B nearby backup and H Hold fire are available with selected capable infantry. RESERVE and AUTO FRAG are explicit strip toggles. Escape/right-click cancel the pending targeting gesture; S/Move/Retreat replace accepted preparation according to existing order rules. An already released grenade is a world object.

The strip shows stock and relevant capabilities. Throw previews use the executor's known-body trajectory and allied-risk checks; work previews use the same ground/access rules as commitment. Rejected commands explain the reason without spending stock or supply. Selection text reports real work/cover/backup state; detailed action ownership stays in diagnostics. The strip fits above both the Field Guide and multi-selection roster.

## Verification

```sh
python3 tools/check.py --group m1
python3 tools/check.py --group tactical
./tools/play.sh --audio-driver Dummy --script tests/m1_native_review.gd
```

Use Godot 4.5.1. The eight M1 suites cover cooperation, throwables, support, work, optics, campaign persistence, real command input and a staged Harbor interaction. The broader tactical gate retains existing geometry, mission, command, combat, economy and save assertions.

**Prior verified evidence at recovered commit `6149686`:** 71 passing suite results, including all 466 M1 checks and 1,439 M0 checks. The full serial run passed 70/71; after correcting its sole ordinary engineer-confirmation failure, the field-work UI and M1 command suites passed their focused rerun. Four native captures passed, and all 17 recorded native source hashes and 90 functional source hashes matched that recovered state. Full runs and the prior snapshot are in [validation](../validation.md#m1-infantry-defense--2026-10-31). This evidence does not validate later publication-review edits; their current results must be recorded before closing task 10.

The Harbor fixture uses authored ground near `(312,652)`, staged existing force types and normal command APIs/ticks. Hold fire isolates grenade damage from incidental shooting. It demonstrates concurrent work/throws, smoke, actual backup delivery/return and one paid upgrade. It is not a mission victory, human playtest or balance/performance benchmark. Coordination and defensive grenade handover also have separate deterministic regression fixtures.

## Bounds and remaining work

Throwables cap active projectiles/preparations at 64 and smoke at 32. Defensive reviews inspect at most two due sections per tick under shared decision/line admission. Support caps 32 requests, 64 registered reserves and 12 provider candidates; requests, leases, service and returns have explicit deadlines. Field positions cap 64 active jobs and 96 sites and use bounded local approach/work searches. These code limits do not establish a wall-clock or FPS result; M0's documented synchronous navigation hitch risk remains.

M1 art uses the existing procedural soldiers with placeholder throw/dig poses, simple payload meshes, pooled smoke and staged prepared-position meshes. Bouncing, room/interior throws, grenade replenishment, expanded urban actions, engineer request dispatch, broad initiative profiles and new domain assignments remain later work. Human command clarity, tuning, long-session play and supported-hardware performance acceptance remain open.
