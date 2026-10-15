# 1: Tactical RTS vertical slice

**Status:** completed
**Goal:** Deliver one playable Godot skirmish that demonstrates responsive squad control, useful terrain, combined-arms decisions, and measurable runtime performance.

## Scope

One compact battlefield with open ground, a covered route, a ridge or sight blocker, and a chokepoint. Start with infantry squads, an armored vehicle, and a reconnaissance drone against a small defending force. Capture or secure a marked objective with a clear victory/defeat state and restart.

The common command foundation now also supports gunships, corvettes, and anti-air vehicles in this mission. Production art, base economy, multiplayer, and a campaign are later milestones.

## Tasks

- [x] 1. Inspect installed Godot tooling, choose and pin an engine version and renderer, record baseline hardware, and create a runnable project with verified launch instructions.
- [x] 2. Build the camera and graybox terrain, including traversability and visibility blockers.
- [x] 3. Implement click/box selection, control groups, contextual move/attack, attack-move, stop, queued orders, and visible order feedback.
- [x] 4. Add squad formation movement, obstacle navigation, arrival behavior, and clear unreachable-order handling.
- [x] 5. Add data-driven infantry, armor, and reconnaissance drone definitions; implement basic weapons, damage, cover, and readable suppression feedback.
- [x] 6. Implement team visibility and fog of war; verify the drone reveals targets and the opponent cannot target hidden units through unavailable information.
- [x] 7. Add simple defending behavior, objective logic, win/loss, and restart for a short complete scenario.
- [x] 8. Add reproducible performance scenarios and capture frame times, simulation costs, entity counts, and command feedback latency.
- [x] 9. Exercise terrain routes and controls through scripted playthrough and viewport input tests; record findings, defects, and baseline results before expanding scope.

## Acceptance checks

- A fresh checkout can open and run using documented, verified steps.
- Mixed group orders have visible acknowledgements; units do not silently drop queued orders or remain permanently stuck at the chokepoint.
- Infantry and armor respect impassable terrain; drone movement follows its own domain rules.
- Cover and visibility change combat outcomes in reproducible scenarios, and fog prevents unauthorized targeting.
- The scenario can be won, lost, and restarted without restarting the editor.
- Capture video/screenshots of command interactions plus profiler results with hardware and scenario details. Evaluate against the provisional targets in the roadmap and record shortfalls honestly.

## Decisions

- Godot 4.5.1 implementation now exists. Automated playthrough, rendered review, clearance regression, and performance measurement are complete; human playtesting remains a next step.
- Implemented desktop mouse-and-keyboard, 3D elevated camera, and local single-player first.
- Use original assets or clearly identified licensed placeholders.
- Create child plans only when a task needs additional breakdown.

## Risks to investigate

Formation/navigation cost, visual clutter, readability of terrain effects, and the balance between tactical depth and input burden. Establish repeatable measurements before choosing optimizations.

## Active refinement

- [1-1: Visual effects and model clearance](1-1-effects-and-clearance.md).

- [1-2: Authentic equipment](1-2-authentic-equipment.md).
