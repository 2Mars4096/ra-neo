# 17: Distinct battles and persistent regional operations

**Status:** completed
**Goal:** Give separate battlefields distinct tactical problems, shared elevation rules and lightweight persistent consequences.

## Tasks

- [x] 1. Implement rail logistics, pass interdiction and shore/sea-control objectives.
- [x] 2. Preserve campaign ownership, surviving forces, casualties and supply between operations.
- [x] 3. Add shared elevation, slope-aware mobility, terrain visibility and grounded presentation.
- [x] 4. Add Windbreak Fields for open agricultural maneuver.
- [x] 5. Extend editor validation, mission feedback and native regression coverage.
- [x] 6. Inspect native visuals, update evidence and deliver on `codex/regional-operations`.

## Decisions

- The user explicitly accepts recommendations 1, 3, 4 and 5, and excludes any requirement for adjacent or continuous battlefield geometry.
- Regional consequences are operational abstractions. One tactical simulation loads at a time; there is no simulated travel between maps.
- Capture facilities affect supply, reinforcement access and enemy reserves. Terrain affects sight and mobility without arbitrary damage bonuses.
- Save deployment checkpoints and operation outcomes. A running battle is not serialized; restarting returns to its deployment checkpoint.
- Use the pinned Godot 4.5.1 engine for functional and native rendered checks. Human balance and hardware performance acceptance remain open.

## Evidence and limits

The regional integration gate passed 14 suites and a focused follow-up passed nine suites, including the real scene/save lifecycle. Final focused counts: regional physics 2,301; operation rules 50; elevation 58; campaign persistence 66; campaign UI/startup 47; atlas UI 89; all zero failures. Authoring/editor checks passed 17 and nine tests respectively; seven real-browser editor workflows passed without page errors. Both map compilers reproduce their checked-in outputs.

Native GL Compatibility captures were inspected for the atlas, full mission briefing, Windbreak Fields, South Inlet and the elevated lookout. Native review found and corrected mesh winding, road-ramp clipping and false stair shading. See [validation](../validation.md) for commands and coverage, and [regional operations](../regional-map.md) for play/editor behavior.

Campaign travel and infrastructure effects are abstractions. Tactical positions, destruction and orders do not persist; closing during a battle restores its deployment checkpoint. Heights and grade limits are authored gameplay values. Human balance, complete AI playthroughs, detailed foot/suspension animation and sustained hardware performance are not established by these checks.
