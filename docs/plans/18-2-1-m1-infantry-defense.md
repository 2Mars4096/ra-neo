# 18-2-1: M1 infantry defense

**Parent:** [18-2-infantry-fire-and-movement](18-2-infantry-fire-and-movement.md)
**Status:** in-progress
**Goal:** Deliver coordinated infantry defense with finite grenades, optical smoke, nearby backup and staged field positions through compact controls.

## Delivery boundary

M0 is complete at `5850504`. M1 is divided into the six sections below. The current delivery completes **section 2** on `codex/m1-section-2`, based on completed section 1 at `d10682e`. Section 1 reused `0f5eb25`, then corrected actual covering fire and explicit/urgent target priority; its plan was published first at `14caa85`. Section 2 recovers the grenade/smoke code from `26480fb` and corrects stale cleanup and exposed-member smoke visibility, with current functional and native evidence. The reviewed checkpoint is prepared for commit and publication. Later sections exist on the separate staged implementation branch; their code and completion claims are outside this branch.

This slice crosses plans 18-2/3/4/5/9/10/11/12. Their broader urban, domain and sustainment catalogues remain open. Status below describes this branch. Each section remains a separate buildable checkpoint with affected checks and tracking updates; the current delivery stops before section 3.

## Implementation sequence

| Section | Scope | Dependency and acceptance | Status |
|---|---|---|---|
| **[M1.1 — Coordinated cover and movement](18-2-1-1-coordinated-cover-and-movement.md)** | A ready member covers a moving partner, holds a useful firing position and hands over after reload, suppression or casualty; task ownership excludes conflicting actions. | M0 readiness, observations and order authority. Check real ammunition/rays, partner replacement, survival moves and player overrides. | Complete — 17/17 affected suites pass |
| **[M1.2 — Fragmentation and smoke](18-2-1-2-grenades-and-smoke.md)** | Finite carried payloads, interruptible preparation, one release charge, swept flight, physical blast and height-aware optical smoke. | M1.1 covering and actor claims. Check cancellation, allies, alternative throwers, actual impact and air/ground visibility. | Complete — 22/22 suites; three native captures |
| **M1.3 — Nearby reserve backup** | Explicitly delegate an existing section, lease one capable responder, deliver useful support and return to its unchanged assignment. | M1.1 readiness and M1.2 optical rays. Check actual support weapons, exclusive leases, radio loss, retasking and deadlines. | Pending |
| **M1.4 — Hasty positions and upgrades** | One infantry member digs shallow cover; an engineer can reinforce the same site with one paid upgrade. Retain interrupted progress. | M1.1 actor ownership and M1.3 order cancellation. Check cover stages, geometry, work authority and no duplicate charges/refunds. | Pending |
| **M1.5 — Controls and feedback** | Contextual commands, target previews, Hold fire, Reserve/Auto Frag toggles and concise action status. | M1.1–M1.4 APIs. Check real input, rejected orders, partial radio acknowledgements, cancellation and layout. | Pending |
| **M1.6 — Persistence and integration** | Preserve individual equipment through outcomes/retry, migrate old saves, and combine the mechanics in Harbor. | M1.1–M1.5. Check empty inventories/casualties, migration, integrated encounter, affected regression gate and native rendering. | Pending |

## Tasks

- [x] 1. Reuse the existing coordinated cover/movement and actor-ownership implementation from `0f5eb25`.
  - [x] Complete the [section 1 review](18-2-1-1-coordinated-cover-and-movement.md), record current evidence and publish `codex/m1-section-1`.
- [x] 2. Recover and verify finite fragmentation grenades and optical smoke; prepare the checkpoint for publication.
  - [x] Recover the section 2 implementation onto `d10682e` while retaining section 1 corrections.
  - [x] Complete the [section 2 review](18-2-1-2-grenades-and-smoke.md), record current evidence and prepare `codex/m1-section-2` for commit and push.
- [ ] 3. Recover, verify and publish existing-reserve backup and assignment-safe return.
- [ ] 4. Recover, verify and publish hasty positions, engineer upgrades and work-order integration.
- [ ] 5. Recover, verify and publish compact controls, previews and action feedback.
- [ ] 6. Recover persistence, run integration/native review, update evidence and publish completion.

## Behavior contract

This table specifies the complete M1 target. Section 1 provides cooperation and shared actor ownership; section 2 adds payloads, optical smoke and their integration with covering fire. Backup dispatch, field positions, contextual controls and campaign inventory persistence remain later sections on this branch.

| Area | M1 behavior |
|---|---|
| Cooperation | A coverer must be alive, available, loaded, settled, permitted to fire and able to reach the observed threat with its real weapon ray. Actual combat uses that threat and its appropriate weapon ahead of incidental targets. A conflicting explicit attack or urgent threat preempts support and releases its claim. The coverer holds its actual firing position and cannot voluntarily top off while a teammate depends on it. Reload, casualty, suppression, smoke or forced hull avoidance invalidate the role. An exposed mover finishes its validated short shelter move if support is lost. An observed threat the section cannot engage can justify a validated local screened shelter move, explicitly labeled unsupported; it cannot justify an exposed flank or override Move/Hold/Retreat. |
| Inventory | New capable infantry start with one frag and one smoke each. A selected group requests one throw, choosing one eligible member. Reservation does not spend stock; release spends once. Lost holders do not donate or regenerate equipment. There is no grenade refill service in M1. |
| Manual throws | A throw request chooses an available member with a safe arc, starts preparation and replaces that section's current command with a hold at its position. A blocked nearest member does not hide another member's valid throw. New commands cancel uncommitted work. Hold fire permits only the explicitly requested throw. Released objects survive retasking, casualty and cancellation. G/V targeting controls belong to section 5. |
| Defensive frag | AUTO FRAG is off by default. A settled, free-fire section may use carried frag stock against at least two currently observed, exposed infantry when a useful covering partner is available. Reviews are bounded and releases separated; opportunity, current partner, command, arc and allied exposure are rechecked before release. Smoke remains manual. |
| Flight and blast | Fictional 18-unit range, a deterministic arc, bounded swept collision and stop-on-contact behavior. Blast uses actual impact, per-body exposure, walls, height, garrison protection and existing wounds/suppression. Both factions reject known allied risk before release; allies entering later can be hit. |
| Optical smoke | One fixed cylinder of radius 4.5, height 4 and lifetime 18 seconds. It blocks either team's optical ray and invalidates visibility caches on deployment/expiry. Acquisition and jammed local knowledge use exposed living member bodies, with indexed/exhaustive parity for wide sections. A sufficiently elevated ray can clear the cloud. Presentation follows the authoritative volume; particles do not decide visibility. |
| Backup | RESERVE explicitly delegates a connected idle/held infantry section. B requests existing local assistance without spending or spawning. One provider owns the lease, moves normally, provides four seconds of useful readiness/observation or fire support, then returns to its unchanged held assignment. Copied infantry contacts and unknown frontage require usable rifle stock/range rather than an operator's launcher. New accepted orders, including digging/upgrades, revoke reserve delegation and stale return work. |
| Communication | Accepted support retains its exclusive lease through radio loss, preventing a duplicate dispatch. Lease expiry, provider loss, changed assignments, blocked routes and missing readiness produce bounded failure/return behavior. Remembered contacts are copied facts, not live hidden targets. |
| Hasty position | D accepts nearby clear, sufficiently level soil. One rifle/AT/engineer member approaches and works for 18 seconds; the other members remain available. No supply charge. The unfinished marker gives no protection; completion grants ordinary cover with 120 integrity. |
| Reinforcement | U with an engineer selects a completed shallow position. The existing trench price (50 supply) funds ten seconds of work on the same site. Stage 2 grants the existing dug-in protection and 320 integrity. Hasty protection remains during an interrupted upgrade. No terrain excavation is simulated. |
| Work interruption | Pressure can pause the actor; accepted new orders release it. The site keeps paid materials and earned progress. Resume uses an eligible worker; repeated current commands preserve the same action/worker rather than charging or rerouting again. Cancel/salvage cannot refund free digging or duplicate paid refunds. |
| Persistence | Campaign version 3 adds per-member throwable stock, with version-1/2 and nested retry migration, including older engineer records from the field-unit definitions. Explicit empty and zero stock stay empty, casualties stay lost, and actual released inventory carries between operations. Actor tasks, projectiles, smoke, requests and tactical works remain transient. |

## Planned controls and feedback — section 5

Section 1 adds automatic local cooperation under existing commands and exposes reasons in diagnostics. Section 2 adds the simulation throw/preview API and defensive policy, with placeholder throw/smoke presentation. The controls below are the later section 5 contract.

G frag, V smoke, D dig, U engineer upgrade, B nearby backup and H Hold fire will be available with selected capable infantry. RESERVE and AUTO FRAG are explicit strip toggles. Escape/right-click cancel the pending targeting gesture; S/Move/Retreat replace accepted preparation according to existing order rules. An already released grenade is a world object.

The strip shows stock and relevant capabilities. Throw previews use the executor's known-body trajectory and allied-risk checks; work previews use the same ground/access rules as commitment. Rejected commands explain the reason without spending stock or supply. Selection text reports real work/cover/backup state; detailed action ownership stays in diagnostics. The strip fits above both the Field Guide and multi-selection roster.

## Verification

Use Godot 4.5.1. `python3 tools/check.py --group m1` selects the M1 suites present at the current checkpoint: `test_infantry_coordination.gd`, `test_throwables.gd` and `test_m1_optics.gd`. `--group tactical` also checks affected existing executors. The complete slice is planned to contain eight M1 suites; its integrated native Harbor review belongs to M1.6.

Current checkpoint results are recorded below as the sections pass. Previous local-candidate results are historical only. A functional pass does not establish human balance, hardware performance or a completed mission.

## Checkpoint evidence

- **Completed M1.1 checkpoint (`d10682e`):** 17/17 affected suites pass, including 79 coordination checks with zero failures. Its [report](../evidence/m1-01-checks.json) records that checkpoint's selection, 83 source hashes and the known ATGM suite shutdown warning.
- **M1.1 regression sensitivity:** the identical 79-check coordination test against unchanged `0f5eb25` produces 10 expected failures without script errors. Its tests exercise actual covering fire, physical shelter arrival, role cleanup and explicit/urgent target preemption. See the [section plan](18-2-1-1-coordinated-cover-and-movement.md) for that checkpoint's correction and verification scope; no native rendering or hardware-performance result was added in section 1.
- **Completed M1.2 checkpoint:** [current evidence](../evidence/m1-02-checks.json) records 22/22 selected suites passing in 173 seconds, without script or assertion failures. Its 280 M1 assertions comprise 79 coordination, 145 throwable and 56 optics checks. Identical-test controls reproduce two stale-cleanup failures before correction and eleven optics failures on `26480fb`; both current suites pass.
- **Section 2 presentation:** [native review](../evidence/m1-02-native-review.json) completed three captures, zero failures, in Godot 4.5.1 OpenGL/llvmpipe; preparation, airborne frag and seven-puff smoke were visually inspected. The fixture uses the simulation API. Contextual controls, campaign inventory persistence, frame-rate and human/balance acceptance remain separate work.

## Bounds and remaining work

Section 1 reviews existing section members and uses the existing bounded cover search. Section 2 caps projectiles/preparations at 64 each, smoke volumes at 32 and defensive reviews at two due sections per tick. Planned later-section limits are 32 support requests, 64 registered reserves, 12 provider candidates, 64 field-work jobs and 96 sites. Requests, leases, service and returns must have deadlines. These limits do not establish CPU/FPS acceptance; M0's synchronous navigation hitch remains an open issue.

Sections 1–2 use the existing procedural soldiers, a placeholder throw pose, simple payload meshes and pooled smoke. Dig poses and staged position meshes belong to later sections. Room/interior throws, bouncing, grenade replenishment, generalized engineer dispatch, broader initiative profiles and M2 domain roles remain later work. Human command clarity, tuning, long-session play and supported-hardware performance acceptance remain open.
