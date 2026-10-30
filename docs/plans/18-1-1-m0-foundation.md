# 18-1-1: M0 tactical foundation

**Parent:** [18-1-action-framework-and-readiness](18-1-action-framework-and-readiness.md)
**Status:** complete
**Goal:** Make the existing roster prepare, select targets and obey current orders reliably, with legitimate observations and bounded planning.

## Scope and baseline

Implemented on `codex/unit-tactics-implementation`, continuing recovery checkpoint `e36b211` over planning baseline `caf1b4c` and regional operations `f5916e8`. The user authorized implementation starting with M0. M1 throwables, optical smoke, backup requests and infantry digging remain subsequent work.

## Tasks

- [x] 1. Introduce assignment/order versions and a bounded action registry with atomic claims, deadlines, interruption reasons and failure backoff.
- [x] 2. Adapt existing reload, aim, cover and maneuver executors without transferring projectile or inventory ownership into diagnostics.
- [x] 3. Prepare empty weapons in quiet intervals; allow a low rifle magazine to top off only with another capable loaded member watching. Preserve rounds when interrupted.
- [x] 4. Evaluate the explicit target first, retain useful ordinary targets and preempt with an eligible observed urgent air threat. Reacquire aim on a real target/weapon change.
- [x] 5. Separate assigned, effective, recoverable, available and ready strength; identify equipment by member identity and provide an interruptible handover interface.
- [x] 6. Record copied local/shared contacts with source, timestamp, deterministic confidence decay, expiry and bounded storage.
- [x] 7. Add shared planning admission, continuation for large placement searches, version checks and event-triggered review. Budget denial stays pending.
- [x] 8. Preserve campaign magazine/equipment/loss history with version-1 migration and version-2 validation.
- [x] 9. Expose selected-section readiness and bounded local diagnostic traces.
- [x] 10. Finish the combined tactical regression gate, native readiness review and documented performance boundary.

## Implemented contracts

| Area | Current behavior |
|---|---|
| Commands | An accepted replacement changes `order_version`; queued orders activate their own assignment when reached. Internal give-way/reposition routes retain their parent's assignment. Provisional placement has no new attack permission or movement until accepted. |
| Actions | `TacticalActions` owns identities, channels and claims. Existing executors own movement, magazines, missiles, purchases and released effects. Cancellation releases claims; it cannot refund a committed effect. |
| Readiness | In autonomous scenarios, rifle reload takes 1.8 seconds and launcher reload 3 seconds. A rifle with at most 2 of 6 rounds can top off after a 3-second lull if a loaded capable partner remains. All-empty sections can reload. These are existing/provisional game timings, not measured realism. |
| Strength | Assigned strength survives losses and saves. Healing remains limited to survivors. Launcher availability follows its recorded holder, rather than array position zero. Handover requires a valid nearby giver/receiver, time and unchanged order ownership; it is an internal interface only. |
| Pressure | Useful local cover/aid can continue. Withdrawal avoids routes closing on known threats and can finish after committed, quiet disengagement. A handled loss episode does not repeat solely on renewed visibility; new fire/hits/losses/heavy suppression re-arm it. Failed withdrawals never acknowledge safety. |
| Permissions | Hold position keeps its movement boundary. Separate `set_fire_policy` supports Hold fire internally; an accepted explicit attack has scoped permission. No new fire-policy button is exposed in M0. |
| Knowledge | Only actual sensor observations write contact facts. A lost contact keeps its last observed position, ages out after 30 seconds, and cannot refresh from hidden motion or death. Jamming retains local observations without uploading them. Memory does not grant firing permission. |
| Planning | Per-tick admission covers route, cover, regroup, decision and formation bundles. Large formation, firing-position and invalid-ground searches retain cursors. Current order, geometry, contact and destination legality are checked before use. |
| Persistence | Operational saves carry original strength, member IDs, partial magazines and equipment ownership. Reload timers, routes, action claims and tactical contact memory do not persist between battlefields. |

## Validation

The dedicated gate is `python3 tools/check.py --group m0`; the broader integration gate is `--group tactical`, both using Godot 4.5.1. They cover real command replacement, provisional/rejected orders, released missile/FPV effects, paused paid work, contact isolation, campaign migration and route continuation in addition to the small action fixtures.

`tests/m0_native_review.gd` renders staged empty-magazine, replacement-move and completed-reload states through the actual scene/HUD. It preserves ordinary fog and uses isolated preferences; scripted review does not access the player's campaign.

The final combined gate passes **58/58 suites**, including all **10 M0 suites / 1,439 checks**. Native review completes **3 captures / 0 failures**. The unchanged regroup-recovery suite passes **128,621 checks**. [Validation](../validation.md#m0-tactical-foundation--2026-10-30) records outputs, source hashes, native captures and the isolated busy-combat CPU sample. Initial regression failures and their fixes are recorded in [bugs](../bugs.md); mission, collision and reunion thresholds were not relaxed to obtain a pass.

## Performance boundary

Admission limits bound how many finite search bundles start in one authoritative tick. They do not make Godot's synchronous A* time-bounded or move it onto a worker. Terrain counts path calls and actual A* starts separately. Setup/direct tool calls remain synchronous. The valid 900-tick busy-combat CPU sample measures **29.816 ms p95 / 354.828 ms maximum**, so expensive synchronous work remains a concrete follow-up. No new rendered-FPS, input-latency, hardware-capacity or full-battle balance claim follows from these checks.

## Next increment

M1 can build on the reservation, permission, contact and ownership contracts. Coordinated section roles, grenades/smoke, actual backup dispatch, infantry hasty positions, dedicated initiative controls and automatic specialist transfer remain outside M0.
