# 18-11: Command interface and feedback

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Make expanded tactical behavior easy to command, predict and interrupt with a compact battlefield interface.

## Baseline and evidence

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

**Grenade/smoke:** select a capable section, choose the payload, point at a valid area and confirm. Preview remaining charges, uncertain throw/impact area, obstruction and known allied risk. One eligible soldier reserves the action; the rest preserve useful roles. Escape cancels preparation, while a released projectile remains in the world. A request for another unit's smoke is shown as support, not as a grenade magically appearing in this section.

**Backup:** select Request support or let a delegated unit raise its own need. Show the responding unit and brief status. Clicking the indicator focuses that responder; cancelling releases its temporary task. Buying a new unit remains a separate purchase interaction unless an explicit automated spending allowance exists.

**Digging:** choose a point/short defensive line, preview eligibility and intended facing, and commit. Show progressive completion, assigned workers and pause reason. A basic infantry position and an engineer upgrade have distinct cost/capability labels. No extra click is required for each shovel stroke or individual soldier assignment.

**Escort/observe:** choose the friendly asset or area once. Subsequent positioning is automatic within the assignment boundary. An explicit move can be temporary only when the UI clearly shows that it retains the assignment; ordinary replacement orders keep their existing replacement semantics.

**Resupply/repair:** offer a contextual service-and-return command. Show the chosen provider and original assignment marker. The unit returns only if that assignment remains valid. A destroyed or unreachable provider produces a clear alternative/pending state.

## Tasks

- [ ] 1. Document current command semantics and protect them with focused input/replacement tests.
- [ ] 2. Add the minimal initiative/engagement permission view with [18-1](18-1-action-framework-and-readiness.md); show scope in hover text and selection overlays.
- [ ] 3. Add a capability-filtered context strip for the M1 grenade, smoke, backup and digging slice; use concise labels and recognizable icons.
- [ ] 4. Make previews and commit validation share current geometry, inventory, knowledge and authorization checks. A stale preview may fail clearly without consuming resources.
- [ ] 5. Add activity, support lifecycle and optional service-return cues using existing notice merging.
- [ ] 6. Show mixed-selection eligibility: how many units can act, which one is assigned, and what stays pending. Do not duplicate throws or paid work accidentally.
- [ ] 7. Preserve queued orders, control groups, pause, minimap commands and keyboard access; define conflict behavior for targeting modes.
- [ ] 8. Inspect native visuals and run the usability/latency scenarios below before enabling the new controls broadly.

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
