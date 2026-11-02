# 18-2-1-3: Nearby reserve backup

**Parent:** [18-2-1: M1 infantry defense](18-2-1-m1-infantry-defense.md)
**Status:** completed
**Goal:** Dispatch one authorized existing infantry reserve to useful nearby support and return it without overriding a newer assignment.

## Scope and baseline

This delivery continues completed section 2 at `e180a118` on `codex/m1-section-3`. The initial implementation reuses section 3 code from `39af9e3`, preserving sections 1–2's corrected covering-fire, order-priority, throw-ownership and living-body smoke behavior. The reviewed integration corrects order/rollback ownership, support-credit and smoke-observation defects, and passes the current affected gate. This checkpoint is prepared for commit and publication.

Section 3 provides `Simulation.set_reserve(ids, enabled)` and `Simulation.request_backup(ids)`, bounded provider matching, exclusive service leases, normal routed movement, useful-support checks and assignment-safe return. Requests use troops already on the battlefield and authorize no purchase or free replenishment. Contextual Reserve/Backup controls remain section 5. Hasty positions are section 4; wider engineer, medical, logistics, reconnaissance, vehicle, air and naval request adapters remain outside this checkpoint.

## Implementation components

| Component | Implementation | Acceptance |
|---|---|---|
| 1. Delegation and requests | Explicit reserve authorization, copied requester observations with observed body points, deduplicated requests and bounded retry/history. | No undelegated or occupied section is borrowed; requests create no units or supply and cannot refresh hidden enemy coordinates. |
| 2. Matching and exclusive leases | Choose a capable nearby provider and atomically claim both provider and request under its existing assignment. | Competing calls cannot share one provider; readiness uses the actual useful weapon, loaded stock, fire permission and current actor duties. |
| 3. Movement and useful support | Find a physically useful support point, route through the ordinary executor and measure sustained real readiness/observation and current target/weapon use. | A label or arrival behind a wall is insufficient; smoke, elevation, weapon range, reloads, casualties and pressure affect delivery. |
| 4. Communication and failures | Keep accepted exclusive work through radio loss until acknowledgement or the known lease deadline; bound unavailable routes and losses. | No duplicate dispatch, silent renewal or stale reconnection; pending planning is distinct from failed geometry and no-progress timeouts. |
| 5. Return and order integration | Return to the saved held position only while the provider still owns its original assignment; integrate existing orders and engineer work. | Accepted replacements revoke obsolete support, rejected provisional commands preserve it, queued/replacement placement pauses accrue no false service/stall time, absolute deadlines remain active, and delayed cleanup cannot restore superseded intent. |

## Tasks

- [x] 1. Recover section 3 code and tests onto the completed section 2 branch.
- [x] 2. Review reserve delegation, request observations, provider eligibility, resource conservation and exclusive claims.
- [x] 3. Review normal movement, actual support weapon/range, smoke and physical exposure, and sustained service completion.
- [x] 4. Review radio loss, acknowledgement, expiry, losses, bounded failure and cleanup.
- [x] 5. Review return ownership and accepted/provisional replacement commands, including existing engineer work.
- [x] 6. Run the affected functional gate, record current source hashes and any reproduced defects, then prepare the checkpoint for commit and push.

## Behavior contract

- Reserve authorization is explicit. A connected infantry section may be marked for future reserve service, but unfinished orders, garrisons, engineering, throw preparation, active combat or insufficient ready personnel prevent dispatch. Casualty duties remain part of member-readiness validation.
- A request records the sender's assignment/version, fixed origin and copied observation, including any exposed body point recorded when the observation was made. The original reported squad position is retained; requests never query a hidden unit to reconstruct that point. Repeated calls for the same active request reuse that request. Unknown frontage supplies a point to cover; it does not invent a live enemy.
- Matching reserves one provider and one request through the shared action/claim system. Movement is temporary work under the existing provider assignment. No unit is spawned and no supply is charged.
- Readiness and usefulness select the actual appropriate weapon. Infantry or unknown frontage requires usable rifle stock and range, including for a specialist; armor can require its launcher. Live reloads, Hold fire and incompatible actor duties remain authoritative.
- Useful delivery requires real member readiness and a clear optical lane through terrain, elevation and smoke. A member currently engaging a different target or using a different weapon cannot be credited merely for carrying a suitable alternative. Sustained service is measured at the provider's actual position; loss of usefulness resets progress.
- Accepted work survives later radio loss with its existing exclusive lease. A remote cancellation waits for acknowledgement or expiry; nearby local communication can acknowledge it. Reconnection cannot renew obsolete work or create a duplicate service.
- Completion or acknowledged cancellation starts a bounded physical return to the saved reserve position. Restore hold only for the same assignment and request ownership. Accepted new orders, including a queued command becoming the active head, cancel support so the ordinary order executor can complete the new command. Unresolved queued or replacement placement preserves the accepted assignment until success or rejection is known; its pause earns no useful-service time or route-stall time. Absolute lease and return deadlines still expire. Cancellation or expiry also clears obsolete movement/action state from a parked rollback snapshot.
- Existing engineer construction/clearing/recovery work remains authoritative. Explicit replacement work revokes reserve service; internally continuing already accepted work must retain future reserve authorization.

## Verified integration corrections

- Accepting a queued head could leave backup ownership active and prevent ordinary command completion; a rejected queued head could lose the still-valid support route. Head activation and rejected-order restoration now preserve the correct owner; regressions follow the replacement order through actual ordinary completion.
- Unresolved replacement placement could accrue false stall/service time. Cancelling or expiring the old task could also leave parked movement/action state that a later rejection resurrected. Queued and replacement placement pauses and snapshot cleanup now follow actual ownership, while absolute lease and return deadlines remain active.
- A merely capable member could receive support credit while the combat executor selected a different target or weapon. Useful service now checks what the ready member is actually doing.
- Smoke requests retained an observed squad's screened anchor but lost its exposed living-body geometry. Observations now store the copied body point at observation time; request/placement/usefulness reuse that immutable fact without a live hidden lookup.

The final lifecycle and support tests reproduce these defects on the integrated baseline tree, then pass on the corrected source; the exact controls are recorded below.

## Bounds and verification

Current limits are 32 request records, 64 registered reserves, 12 match candidates and six candidate supporting positions. Initial timings are an eight-second request window, 25-second accepted lease, 20-second return deadline, four seconds of useful service, four-second retry delay and 15-second terminal history. These are provisional simulation values and finite code bounds, not performance or balance acceptance.

Use Godot 4.5.1. `python3 tools/check.py --group m1` selects coordination, throwables, smoke optics, support requests and support lifecycle at this checkpoint. The affected gate should also exercise accepted/provisional orders, planning admission, ordinary movement/combat, engineer work, garrisons and copied knowledge.

The [current functional report](../evidence/m1-03-checks.json) records **29/29 selected suites passing in 203 seconds** on Godot 4.5.1, with no assertion or script failures. The **467 M1 checks** comprise 79 coordination, 145 throwable, 56 optics, 125 support-request and 62 support-lifecycle checks, all with zero failures. The report retains the exact selection, outputs and current source hashes.

The identical final tests were also run against integrated baseline tree `ba5456bc00ecf1970485cdd1e91f9834f70f0bb8`, consisting of `e180a118` plus the recovered `39af9e3` scripts/tests before the corrections:

| Regression suite | Baseline result | Corrected result |
|---|---|---|
| Support lifecycle | 62 checks, 24 expected failures | 62 checks, 0 failures |
| Support requests | 125 checks, 7 expected failures | 125 checks, 0 failures |

The lifecycle control ran in an isolated export; the support control ran on the matching integrated working tree before correction. Both compare the same final tests against the recorded pre-fix production files, not a full historical `39af9e3` checkout. Sections 1–2's evidence remains historical to their own checkpoints. Section 3 adds no render/UI assets and claims no new native capture, frame-rate or human-balance acceptance; contextual input remains section 5.

## Decisions

- Preserve the completed section 2 baseline and import no section 4–6 implementation modules.
- Use existing infantry, shared action ownership and ordinary movement; no new roster or purchased reinforcement service.
- Treat copied observations and real local optical lanes separately from live hidden target state.
- Keep support and return bounded, while preserving newer player commands and already accepted engineering work.

## Notes

The broader [coordination and support plan](18-4-coordination-and-support-requests.md) remains open. This checkpoint does not implement general escort, recon, engineer, medical, supply, transport or cross-domain dispatch, delegated spending, tactical-world save/load or contextual input. Requests and leases remain tactical state.
