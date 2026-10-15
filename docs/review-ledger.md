# Implementation and review ledger

## Recursive checkpoint — playable MVP

- Trigger: “AAA quality”, “best UI”, “real tactics”, and “keep improving” need testable interpretations.
- Concrete meaning: one complete mission with selection, group commands, differentiated units, terrain rules, reinforcements, victory/defeat, and restart; visible command acknowledgement and measured runtime behavior.
- Artifact/test: simulation regressions, viewport input events, a normal-API scripted playthrough, rendered snapshots, and a repeatable benchmark.
- Kill result: unwinnable mission, hidden-target cheating, broken command controls, overlapping models, unreadable combat, or sustained frame-budget misses.
- Scale trigger: the slice passes those gates; increase content only after that evidence exists.
- Decision: use a bounded local single-player slice with procedural original models and explicit production-quality limitations. Keep this interpretation; defer campaign, multiplayer, and production asset creation.

## Passes

| Pass / expert practice | Evidence and decision |
|---|---|
| RTS gameplay engineer — separate simulation from view and test state transitions | Fixed 30 Hz simulation; headless combat, visibility, capture, queue, and terminal-state tests; end-to-end player policy uses ordinary commands and purchases |
| Engine engineer — use existing navigation primitives | Godot AStarGrid2D with domain/footprint-specific grids; no external navigation dependency |
| UX designer — inspect task completion, feedback, and recovery | Box/click selection, conventional right-click and A-click, groups, queues, pause, minimap orders, state/health, cost explanations, briefing, and restart; automated viewport events cover core controls |
| Technical artist — inspect renders, not just source | Corrected ground-face culling, initial camera crop, range overlay stacking, and mismatched visual/collision bounds |
| Performance engineer — measure before optimizing | Cached terrain visibility, cached minimap texture, batched rigid unit geometry by material, MultiMesh vegetation; earlier 1440×900-scale measurement improved from 23.618 to 13.035 ms p95 after rendering changes; not a controlled 1080p comparison |
| Navigation specialist — test swept footprints rather than centers | Conservative radii validated against mesh vertices, safe deployments and formation slots, continuous segment clearance against units/static geometry, shared tree locations and pier bounds |
| VFX artist — stage effects over time and bound cost | 640 pooled billboard particles; flashes precede smoke; dust/wakes identify motion; synthetic audio and mute; rendered timing/visibility inspected |

## Recursive checkpoint — no clipping

- Trigger: “models don’t clip” includes far more than a passable center point.
- Concrete meaning: every rendered unit fits its horizontal envelope; ground/sea motion keeps that envelope out of solids and other bodies; air bands clear tall props and one another.
- Artifact/test: `tests/test_clearance.gd` checks mesh vertices, dense movement, deployment, redirection, and naval passage; rendered views check presentation.
- Kill result: any negative separation margin, static-boundary violation, or geometry extending outside its envelope. A stalled but non-overlapping army also fails the playable-MVP goal.
- Scale trigger: representative stress checks and the full mission both pass; retain the conservative implementation and document limits.
- Decision: use clearance-aware routing and avoidance now; defer a larger-scale navigation replacement until profiling or deadlock evidence requires it.

## Primary implementation references

- [Godot 4.5 AStarGrid2D](https://docs.godotengine.org/en/4.5/classes/class_astargrid2d.html): built-in grid pathfinding and diagonal restrictions.
- [Godot 4.5 MultiMesh optimization](https://docs.godotengine.org/en/4.5/tutorials/performance/using_multimesh.html): instancing repeated geometry.

These support engine choices; they do not establish a universal industry standard for RTS architecture or prove that this game's UX is optimal. Human playtesting and broader hardware validation remain necessary for those judgments.

## Equipment review — user steering

The user rejected the blockout appearance. The art criterion changed from “distinct placeholders” to military-inspired silhouettes and equipment that hold up at gameplay zoom. Added shaped armor, running gear, weapon/optics detail, tandem cockpit, tail/rotors, naval hull/deck equipment, and soldier anatomy/kit. Rechecked mesh footprints after replacement. The equipment study is a close-up reference; battle screenshots assess actual readability.

Reference photographs were consulted for shape and equipment cues; no photographs or third-party models were imported: [Army Abrams imagery](https://www.army.mil/article/222100/2_8_cav_tests_abrams_upgrades_demonstrates_increased_lethality), [Army Apache overview](https://www.army.mil/article/137579/AH_64E_APACHE_ATTACK_HELICOPTER/), and [DVIDS Abrams range photo](https://www.dvidshub.net/image/7260745/1-63-dragons-qualify-fort-riley-m1-abrams-range).

The more detailed art increased render work. A first true-1080p stress run measured 19.433 ms frame p95, exceeding the 16.7 ms target. The next change merged equipment paint into vertex colors and narrowed movement-neighbor scans; remeasurement is required before claiming the target is met.

## Final closeout

Close-up inspection exposed lost hull surfaces in mixed indexed/unindexed batching. Normalizing source topology fixed equipment and roofs; seven new triangle-preservation checks prevent recurrence. All 94,801 clearance/geometry checks pass, as do simulation, input, effects, and the 65-second normal-command mission. Corrected rendered frame p95 is 14.130 ms at actual 1080p on Apple M4 Pro (377 final-frame draw calls). Synthetic input p95 is 101.229 ms across ten samples with concurrent headless tests, narrowly missing the 100 ms provisional target; keep this as follow-up evidence. See [validation](validation.md).

Stop this implementation pass at the playable MVP. Further claims about authenticity, fun, optimal UX, larger-battle performance, or production quality require human review and broader measurements; do not equate passing regressions with those judgments.

## Tactical decisions increment

Design criterion: preserving a damaged unit should trade immediate firepower and supply for later strength. Added retreat, paid safe-zone recovery, suppression consequences, and observed-contact enemy responses. Verified costs, interruption, hidden-contact restrictions, group destinations, and actual arrival. The UI exposes the retreat command and recovery costs. All tests pass, but the baseline policy still wins in 75.1 seconds: keep the broader match-design work open rather than interpreting this as proof of tactical depth.

## State-driven actors and landscapes

The user's feedback expanded the pass from animation polish to individual entity behavior. Chosen boundary: squad-level intent and safe coarse routing, with individual soldier movement, health, target/cooldown/aim, reactions, and casualty outcomes. Stable formation slots avoid exchange deadlocks; distinct cadence and real casualties replace synchronized visual copies. Animated envelope tests caught foot dipping under whole-body hit lean; moving the lean to the torso fixed it. Three fictional terrain presets remain winnable. Broad references and state coverage are recorded in [unit-state design](unit-state-design.md). Human review still needs to judge whether the individual motion feels convincing, particularly starts/stops and close-quarters behavior.

Final measured cost after individual entities: 16.384 ms frame p95 and 8.016 ms simulation p95 at 1080p on Apple M4 Pro, with 95 living friendly entities at the last sample. The provisional frame budget is only narrowly met. Preserve batching per articulated joint and profile further before increasing force scale.

## Combat relationships and communication review — 2026-10-13

- Systems-design criterion: distinguish avoiding a hit from surviving it. Implement separate seeded hit chance and damage, zero-effect armor pairings, slant range, and a fragile small UAV. Tests exercise all matrix entries and 1,000 shot trials.
- Gameplay-programming criterion: unit role follows surviving equipment. Squad engagement checks use individual weapon/range; remove dictionary copying from that hot loop.
- UX criterion: interrupted control must have a reason and a remedy. Brief the EXCHANGE emitter, mark its area, show LINK LOST, preserve last orders, and restore radio on capture. No silent deferred replay of rejected orders.
- Navigation criterion: new combat outcomes must not create permanent congestion in the baseline missions. Add throttled dynamic detours and retain swept geometry checks. The unchanged three-scenario policy now completes.
- Fidelity boundary: matrix probabilities, damage, and interference radius are chosen gameplay abstractions. No claim of physical penetration, real jamming range, or universally fatal drone bullet contacts. Automated correctness and screenshot review do not establish enjoyable balance.

## 2026-10-14 — Riverside team cross-review

- Codex map review: accepted road/parcel/car clearance corrections, paved freight connection, western covered-route adjustment and contested field move;96 checks passed before frontage follow-up.
- Codex navigation review: accepted connectivity-tested firing candidate repair and disclosed-base approach; integrated classic victory371.9s without weakening policy or assertions.
- Codex independent VFX/navigation review: no remaining integration blocker in inspected images/code; noted flat orange fireball, repeated trail puffs and bright impact core. Source: artifacts/riverside-cross-review-codex.md.
- Claude independent map-art review: accepted important frontage, empty-block and missing-quay findings. Main sent frontage/quay repairs; remaining composition gap is explicitly open. Rejected categorical claim that paving/gutters do not exist: they are implemented but too visually weak. Source: artifacts/riverside-cross-review-claude.md.
- Lead native VFX review: found screen-covering white sheets, verified projection sign fix, then verified final CPU billboard revision with native captures and1352changed-pixel size regression. No unverified renderer-incompatibility cause accepted.
- Both configured Codex and Claude profiles completed real reviews. This is bounded acceptance of fixes, not reference-parity approval.

## 2026-10-14 — Asset library final review

- Codex and Claude independently inspected native gallery/source; reports: `artifacts/assets-cross-review-codex.md` and `assets-cross-review-claude.md`.
- Implemented supported findings: context/entry/discharge checks; explicit conservative overhead collision policy; measured render dimensions, larger inspection, rotation and fixed-scale comparison; transparent shelter glass; irregular rip-rap; continuous cloth and monotonic lean-to roof; nonperiodic damage shapes; neutral palette and safety colors; sloped/light-concrete irrigation banks.
- Lead rerendered all100 entries with per-model previews/source hashes. Corrected preview-floor shadow acne on flat damage dressing; the preview floor receives shadows but no longer casts them. Asset suites, palette invariance, placement and gallery callbacks pass.
- Final integrated50-suite result:49 pass, one original60s arrival checkpoint fails at67.10s. All90s completion/clearance/command invariants pass. Navigation worker review remains `revise`; asset workers accepted for bounded library delivery, not reference-quality approval or gameplay integration of every asset.
