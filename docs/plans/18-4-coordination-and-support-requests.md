# 18-4: Coordination and support requests

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** in-progress
**Goal:** Let units request and deliver useful assistance while preserving assignments, limited resources, communication and player authority.

## Baseline and evidence

[TacticalDirector](../../scripts/tactical_director.gd) already coordinates some support/flank choices among units sharing `command_group`; [Simulation.record_order](../../scripts/simulation.gd) replaces that group when a new nonqueued command is issued. [FieldOps](../../scripts/field_ops.gd) has purchases, construction, support posts, enemy waves and mortar/FPV mechanisms. The active M1.3 increment adds a bounded infantry-reserve request adapter around these existing executors. A call for backup must dispatch an eligible unit or obtain a real service; it does not create troops or supply.

## Active increment — M1.3

[Nearby reserve backup](18-2-1-3-nearby-reserve-backup.md) completes the first bounded request adapter on `codex/m1-section-3` over completed section 2 (`e180a118`). The recovered `39af9e3` candidate supplies explicit infantry reserve delegation, copied request observations, one exclusive provider lease, ordinary movement, useful-support checks and return under the unchanged assignment. Review has corrected queued/provisional order ownership, paused service/stall accounting, stale rollback cleanup, capability-only service credit and loss of observed body geometry through smoke. [Current evidence](../evidence/m1-03-checks.json) passes 29/29 affected suites, including 125 support-request and 62 lifecycle checks, with zero assertion/script failures. Identical tests reproduce seven support and 24 lifecycle failures on the integrated pre-fix baseline, then pass after correction. The checkpoint is prepared for commit and publication.

This increment addresses the nearby-backup, unavailability and cancellation/return portions of COOP-01/02/15/16. The broader catalogue and remaining tasks below stay open beyond this infantry adapter. Requests authorize no spawning, purchase or automatic engineer/medical/logistics service. M1.5 supplies contextual controls, and M1.6 verifies physical reserve service/return alongside covering, smoke and staged work in Harbor.

## Action catalogue

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

## Request and assignment contract

Each request carries a stable ID, sender, needed effect/capability, observed location or entity reference, confidence/time, urgency, service boundary, expiry, original assignment version and authorized resource category. A provider responds with capability, availability, route estimate and opportunity cost. Reserve one provider or the explicitly required small set; cap provider participation and avoid recursive requests for the same unmet need.

Lifecycle: requested, offered, accepted, en route, delivering, completed; alternative outcomes are unavailable, cancelled and expired. Acknowledgement names the selected provider and whether arrival is estimated or blocked. No provider is a valid answer. Duplicate requests merge by sender/need/location/time; retries back off and cannot flood the UI or path queue.

Completion is effect-specific. Backup must reach a useful supporting position and accept its temporary role; reconnaissance must produce a relevant observation update; a repair request completes when the agreed capability is restored. Merely arriving near a point is insufficient. Timeouts release claims and clearly report partial completion.

Use a persistent assignment ID separate from one movement command. Snapshot the provider's assignment version when it accepts; after completion resume only if that version still matches. A newer player order revokes the temporary task. Casualties, incompatible domains, invalid targets or lost routes invalidate claims.

Accepted tasks carry a request generation, provider token and locally known lease expiry. Radio loss alone leaves the provider uncertain but committed until that lease ends; the dispatcher does not immediately assign the same exclusive work again. Cancellation/release requires acknowledgement or expiry before reassignment. A disconnected provider stops exclusive work at its agreed expiry and cannot resume a stale generation after reconnecting. Paid service commits validate the current token once. Internal provider movement retains the parent assignment version through the 18-1 child-action contract.

## Authority and communication

Automatic assistance is permitted only within an assigned force/reserve/support zone and its initiative policy. A request does not pull every nearby unit away from a defense. Protect minimum coverage, existing explicit duties and resource reservations. Expensive work, off-map purchases or major movement beyond the delegated boundary remain player-directed unless a spending/task allowance was explicitly granted.

Communication uses the information contract in [18-9](18-9-information-and-electronic-warfare.md). Nearby local cooperation may continue under radio loss; remote request delivery waits or fails visibly. Existing accepted orders survive disconnection. Provider knowledge consists of communicated observations, not the sender's hidden enemy object reference. A remembered point can be investigated without tracking an unseen live target.

Fire/smoke requests also carry engagement permission. A support request or urgent target does not override a provider's Hold fire. An explicit accepted fire order may grant one scoped release; permission is rechecked at commitment.

## Tasks

- [x] 1. Reuse persistent assignment IDs from [18-1](18-1-action-framework-and-readiness.md) and add the initial infantry request/claim record through M1.3.
- [x] 2. Implement the nearby-infantry COOP-01/02/15/16 adapter with one existing reserve responder and no automatic spending.
- [x] 3. Implement useful-arrival tests, duplicate merging, expiries, cancellations and assignment-version-safe return for the initial reserve adapter.
- [ ] 4. Add small role reservations for covering and protection; inspect real firing readiness before a movement relies on support.
- [ ] 5. Adapt existing engineer, aid, repair, supply and recon providers to the same lifecycle; do not require every expansion mechanic.
- [ ] 6. Add delegated zones/priorities and minimal UI acknowledgement with [18-11](18-11-command-interface-and-feedback.md).
- [ ] 7. Add smoke/fire-support and relief adapters after their authoritative effects exist.
- [ ] 8. Validate competing requests, losses, jamming, new orders, unavailable routes and resource conflicts under [18-12](18-12-performance-and-validation.md).
  - [x] Complete the infantry-reserve gate in [M1.3](18-2-1-3-nearby-reserve-backup.md); broader provider and paid-service scenarios remain pending.

## Acceptance scenarios

- Two threatened sections request one reserve. It accepts one task, the other receives a bounded pending/unavailable result, and no unit is duplicated.
- An escort ignores an unrelated low-priority call while its protected unit is threatened; a player reassignment is honored immediately after receipt.
- A reserve arriving behind an obstructing wall does not report useful covering support; it repositions within budget or reports failure.
- A responder is killed, jammed or blocked en route. A jammed provider remains uncertain but committed until acknowledgement or its known lease expires; reassignment and reconnection cannot duplicate a service, drain a second guard or restart stale work.
- A player retasks the responder during assistance. Completion never restores its obsolete order.
- A request needing paid construction cannot spend supply without a valid allowance; resource reservation/refund executes once.

## Decisions

- Select providers from a bounded local/group index. Prefer an appropriate available provider over the closest incapable unit.
- Calling backup and buying reinforcements are distinct game actions. The initial feature uses troops already on the battlefield.
- Initial fire support uses providers already modeled; a dedicated player mortar/artillery unit is separately gated roster scope.
- Unit cooperation should be visible through movement, role icons and concise acknowledgements. Repeated requests merge into one state display.

## Notes

Dependencies are the minimal action, observation and UI contracts, plus whichever provider is enabled. The broader broker is intended to serve infantry, vehicles, air and sea; the initial infantry-reserve adapter is complete, while the wider domain adapters remain open. Domain-specific movement and effects remain owned by their existing executors. Placeholder art is a small request/accepted/arrived icon and a selection-only assignment link.
