# Three-person recovery owner report — 2026-10-14

**Status: incomplete; one original acceptance assertion remains failing.**

## Saved-state inspection and ownership

- Read `docs/todo.md`, the navigation-recovery plan, changelog, architecture, bugs, and `artifacts/three-member-integrated-checks.log` before editing the assigned scripts.
- The integrated log has 11 regroup failures. The CURRENT saved files already included an interrupted endpoint-connection fallback in `infantry.gd` and a living-member, floor-half cover concurrency limit. Running those saved files produced **152,429 checks, 2 failures**; all isolated wall-return cases already passed. This is the actual session baseline, not an attribution of the previous worker's improvements to this session.
- Final runtime edits are only in `scripts/cover_behavior.gd`. `scripts/infantry.gd` and `scripts/tactical_director.gd` are byte-identical to their session-start copies. Preserve the existing triangle and bounded return-route fallback.
- Also changed `tests/test_regroup_recovery.gd` and this report. No assets, resource definitions, other code, or shared tracking documents were edited. Test JSON now goes to `/private/tmp/ra-regroup-owner-evidence.json` so running this owned test does not overwrite the main owner's `artifacts/regroup-recovery.json`.

## Retained change and evidence

Cover selection now excludes an observed contact from shelter triggers when the section can already fire at it and that contact's living weapons cannot reach the section. The range predicate uses each living actor's actual weapon, effectiveness, altitude difference, and range. It does not require an unobstructed incoming line: a protective wall must not invalidate the threat envelope. Suppression and other threatening contacts retain their existing behavior.

The isolated regression establishes a valid outgoing AT shot against observed rifles outside rifle range and verifies that it does not start a shelter trip. Additional assertions cover a nearby live rifle, a dead forward rifle, and a mixed AT/rifle team's surviving weapon ranges. Three rifle members and triangle offsets are checked explicitly.

No original assertions or deadlines were removed or relaxed. Collision functions, body radii, the 10-unit leash, route-length limits, explicit Move/Hold/Retreat handling, and the 60/90/20-second fixtures are unchanged. All wall-return, continuous displacement, swept terrain, actor separation, original-intent, and command-group assertions pass in the final run.

## Final checks actually performed

Required command (stdout captured separately in `/private/tmp/ra-regroup-owner-final.txt`):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/ra-regroup-owner.log --script tests/test_regroup_recovery.gd
```

| Suite | Outcome |
|---|---|
| `test_regroup_recovery.gd` | **Exit 1; 152,441 checks, 1 failure** |
| `test_cover_behavior.gd` | Exit 0; 0 failures; shelter arrival verified |
| `test_tactical_flexibility.gd` | Exit 0; 52 checks, 0 failures |
| `test_gap_navigation.gd` | Exit 0; 2,446 checks, 0 failures |
| `test_actor_spatial.gd` | Exit 0; 1,447 checks, 0 failures |
| `test_individuals.gd` | Exit 0; 1,007 checks, 0 failures |
| `test_stances.gd` | Exit 0; 0 failures |

Adjacent suites used the same executable with `--headless --path . --log-file /private/tmp/ra-owner-TEST.log --script tests/TEST.gd`; captured output is `/private/tmp/ra-owner-TEST.txt`. Their runs used the retained runtime code. A later rejected director experiment was restored byte-for-byte before the final required run. All runs report Godot 4.5.1. The known macOS certificate-store diagnostic appears on both passing and failing runs; no script parse/runtime errors were observed.

## Exact unresolved acceptance criterion

Failure: **`first section completes its village order without reissue`**, evaluated at 60 simulated seconds.

At 60 seconds, section 1 is at `(39.93672, 9.21694)` with the original attack-move to `(39, 22)` still pending. It has 160 HP, no target or maneuver, zero blocked time, and maximum live-member gap 1.99285. Thus the remaining failure is arrival timing, not a separated/dead section or an assertion about collision.

| Section | Maximum live-member gap at 60 s | Regroups completed | First order completion |
|---|---:|---:|---:|
| 1 | 1.99285 | 4 | 67.100 s |
| 2 | 0.98112 | 3 | 67.167 s |
| 3 | 1.67778 | 1 | 59.933 s |

All three original orders are empty at 90 seconds, all residual-congestion checks pass, original intent and command groups are preserved, and the village is player-owned. These are simulated gameplay timestamps, not performance measurements. They do **not** satisfy the unchanged first-section 60-second criterion.

Diagnostic traces of this runtime variant show section 1 engaging enemy 7 beside the villa through roughly 52 seconds, then taking the north-side route; section 2 also waits in SUPPORT near the corridor at 58–61 seconds. Their precise contribution to the seven-second arrival overrun has not been resolved into a safe, verified fix. No engine/permission blocker prevented testing; this is an unresolved behavior regression.

## Rejected experiments, all removed

- Repeated-shelter suppression until anchor progress did not resolve the remaining deadline and could freeze useful cover behavior.
- Broadly ignoring all out-of-range contacts changed early movement and exposed later traffic deadlocks; the retained rule only preserves an already valid outgoing firing position.
- Firing-section clearway maneuvers, route refresh, blocked-unit yielding, alternate flank fallbacks, and changing nearby-partner support waits changed combat/traffic outcomes and introduced additional failures or casualties. They are not retained.
- Restoring a two-of-three shelter-moving allowance also failed acceptance; the saved living-member floor-half rule is retained.

No full 42-suite rerun, windowed render, timed benchmark, or performance/visual acceptance was performed. The earlier 41/42 integrated result is historical evidence, not a fresh final-tree result.
