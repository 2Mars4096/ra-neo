# 18-11: Command interface and feedback

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** in-progress
**Goal:** Make expanded tactical behavior easy to command, predict and interrupt with a compact battlefield interface.

## Baseline and evidence

M0 protects existing replacement, queued, provisional, Hold and internal-approach ownership. The HUD adds reloading/ready counts and pressure/fire-policy reasons; the local diagnostic report adds bounded own-team action traces, strength and planner counters. [18-1-1](18-1-1-m0-foundation.md) tracks verification. [M1.5](18-2-1-5-controls-and-feedback.md) now exposes G/V throws, D/U work, B backup, H Hold fire and explicit Reserve/Auto Frag toggles. Broader initiative profiles and later domain controls remain future work.

[Battle](../../scripts/battle.gd) handles contextual right-click, queued commands, selection, targeting and tactical pause. [HUD](../../scripts/hud.gd) already shows selected-unit state/reasons, movement routes, engineer placement and purchase queues. [NoticeFeed](../../scripts/notice_feed.gd) limits and merges notifications. Extend these surfaces rather than adding a separate panel for every soldier action.

## Command model

| Surface | Proposed behavior | Control boundary |
|---|---|---|
| Existing Move / Attack-move / Hold / Retreat | Retain familiar semantics and shortcuts | A new valid order cancels obsolete temporary plans promptly |
| Initiative control | Direct, Standard and Cautious, with one short hover explanation each | Changes local deviation and survival/readiness policy, not hidden damage/accuracy bonuses |
| Context command strip | Show only relevant actions: throw, dig, observe, escort, support, resupply/repair and return | Unsupported actions remain absent; temporarily unavailable ones explain the specific reason |
| Ground/object drag | Choose a facing, work line, observation area or defensive sector when the action needs one | Preview must use the same physical rules as the committed action |
| Selected-unit activity | Small action icon, current reason and progress only when useful | Detailed decision trace is a developer view, not routine player text |
| Support request indicator | Needed, accepted, en route, delivering or unavailable | No modal acknowledgement for ordinary automatic requests |

Direct initiative permits weapon readiness, legal stance/aim changes and execution details while keeping the explicit path/position intent. Standard permits short role-appropriate repositioning and delegated cooperation. Cautious increases willingness to retain shelter or seek authorized readiness support within a visible leash. All modes preserve explicit Hold semantics; a player can deliberately retain a dangerous position. Final names and thresholds require playtesting.

Hold fire is a separate authoritative engagement permission, so observing or waiting does not reveal a unit unexpectedly. It blocks autonomous damaging/revealing weapon and payload releases, including automatic smoke. An explicit attack/throw grants one visibly scoped action permission and then restores the standing policy; emergency target priority does not silently override it. The UI distinguishes engagement permission from initiative and Hold position. Any self-defense exception must be explicit; avoid multiplying doctrine sliders in the first slice.

## Key interaction flows

**Grenade/smoke:** select a capable section, choose the payload, point at a valid area and confirm. Preview remaining charges, throw/impact area, obstruction and known allied risk. One eligible soldier reserves the action; the rest preserve useful roles. Escape/right-click cancels the pending targeting gesture. Accepted Hold/Move/Retreat cancels unreleased preparation; a released projectile remains in the world. A request for another unit's smoke remains later support scope.

**Backup:** select Request support or let a delegated unit raise its own need. Show the responding unit and brief status. Clicking the indicator focuses that responder; cancelling releases its temporary task. Buying a new unit remains a separate purchase interaction unless an explicit automated spending allowance exists.

**Digging:** choose a point/short defensive line, preview eligibility and intended facing, and commit. Show progressive completion, assigned workers and pause reason. A basic infantry position and an engineer upgrade have distinct cost/capability labels. No extra click is required for each shovel stroke or individual soldier assignment.

**Escort/observe:** choose the friendly asset or area once. Subsequent positioning is automatic within the assignment boundary. An explicit move can be temporary only when the UI clearly shows that it retains the assignment; ordinary replacement orders keep their existing replacement semantics.

**Resupply/repair:** offer a contextual service-and-return command. Show the chosen provider and original assignment marker. The unit returns only if that assignment remains valid. A destroyed or unreachable provider produces a clear alternative/pending state.

## Tasks

- [x] 1. Document current command semantics and protect them with focused input/replacement tests.
- [ ] 2. Complete the initiative/engagement permission view with [18-1](18-1-action-framework-and-readiness.md). M1 exposes Hold fire with scope in hover text; initiative profiles remain later work.
- [x] 3. Add the M1 capability-filtered strip with concise action labels, hotkeys, stock and policy states.
- [x] 4. Share executor validation and structured preview data for M1; stale/rejected commitment preserves resources and explains failure.
- [ ] 5. Complete broader activity/service-return cues. M1 reports retained work, remaining time, covering and current backup state; later services remain open.
- [x] 6. Make M1 mixed-selection commands truthful: one throw/worker, no duplicate spending, partial radio receipts and reversible connected-section toggles.
- [x] 7. Preserve existing orders, groups, pause and minimap commands; targeted modes remain exclusive and cancellation consumes the gesture.
- [ ] 8. Complete native/human usability and measured latency acceptance. M1.5 has a reproducible native review; no hardware latency or human-playtest claim is implied.

## Feedback and presentation contract

Every accepted command has an immediate visual acknowledgement, followed by preparing/performing/completed or a specific failure. Expensive planning may remain pending after acknowledgement. Display player intent and current activity separately: for example, Defend crossroads and Reloading, or Protect convoy and Responding to aircraft.

Use the existing faction/readability system for routes; autonomous temporary movement remains distinguishable from the player destination. Hover/selection reveals support links, facing sectors and intended positions; the whole army should not display permanent rings, cards and floating paragraphs. Include text or shape distinctions where color alone would be ambiguous.

Placeholder assets need stable identifiers and state examples: throw preparation/release, low digging loop, request acknowledgement, repair activity, observation and withdrawal. The authoritative action is not timed by a cosmetic animation clip. Audio/animation can reinforce an event but may not hide whether it completed or failed.

## Acceptance scenarios

- A player can issue smoke, a backup request and a short work line through one targeting gesture after choosing the action; repeated confirmation dialogs are absent.
- Mixed selection consumes one requested payload, not one per selected unit, unless the player explicitly requests a volley.
- A new move/hold cancels preparation and removes stale route/role cues; released effects and already completed work remain visible.
- Under jamming, acknowledgement reports the actual reception state and does not imply a remote order succeeded.
- Tactical pause, minimap and keyboard interactions do not accidentally execute a world action through an open UI surface.
- In a busy scene, urgent events remain distinguishable while duplicate support/reload notices do not flood the feed.

## Decisions

- Keep the normal interface compact and context-dependent. Deep behavior configuration starts in data/developer tooling, with only meaningful player choices exposed.
- The development plan's 100 ms command-feedback target is a proposed verification target; measure it separately from path completion and action execution through [18-12](18-12-performance-and-validation.md).
- Do not require final art to test the flow, but validate actual rendered readability and input rather than declaring success from screenshots alone.

## Notes

Dependencies: action/capability contract, support lifecycle and the enabled domain actions. This plan does not redesign the regional atlas or add a full tactical world-save interface. Minimal UI and feedback are part of each vertical slice, not a final cosmetic stage.
