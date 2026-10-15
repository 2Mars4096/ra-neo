# Navigation/gameplay worker report — 2026-10-14

> Follow-up: the classic mission blocker below is now resolved; see [classic regression follow-up](classic-regression-followup.md) for the proven cause, integrated fix and final validation. This earlier report is retained as historical evidence.

## Result and ownership

Four production files changed: `scripts/simulation.gd`, `scripts/tactical_director.gd`, `scripts/cover_behavior.gd`, `scripts/classic.gd`. Expanded `tests/test_regroup_recovery.gd` and `tests/test_tactical_flexibility.gd`; added `tests/test_riverside_navigation.gd`. Preserved interrupted individual recovery, scenario dimensions, fog/minimap/camera changes. No final terrain algorithm change; a temporary exclusion-cell padding experiment was removed. No art, effects, scenario JSON, central tracking docs, or check.py edits. No delegation or native benchmarks.

This report is the worker's tracking artifact. The manager can incorporate it into central docs after integration.

## Concrete fixes

- Completed autonomous attack advances can clear a blocked ally's approach with a seven-unit local maneuver, constrained within eight units of their retained objective and a twenty-second cooldown. Explicit move/hold/retreat remain excluded. This addresses the stationary section sealing the Canal Watch corridor exit.
- A blocked attack-move whose assigned destination is occupied by an idle friendly can resolve a clear arrival within six units of that destination. Original intent/order position remains unchanged. This uses cached weighted AStar and existing swept-body checks; it does not apply to explicit move/retreat or rewrite direct-attack target identity.
- Simultaneous autonomous withdrawals reserve distinct reachable rally slots. A withdrawal with no positional progress for four seconds now exits at the bounded tactical review cadence, restoring firing and retaining its original objective, instead of remaining fire-disabled until the long deadline.
- Stationary SUPPORT preserves valid shelter. Wall-cover validation and selection consider all observed effective threats within the existing 25-unit perception neighborhood. Unobserved enemies cannot reserve shelter; hostile future cover destinations are not friendly reservations. Physical collision remains authoritative.
- Classic construction-site search uses scenario bounds. Previously neither Riverside base could find infrastructure within the old 96×72 search region. Enemy default staging also follows map height.
- Real Riverside testing exposed loaded harvesters stuck over 150 seconds on the first terrain-legal unloading side. Economy trip creation now evaluates eight body-aware unloading routes and retains the shortest reachable one. Existing active orders are not periodically reissued.

## Final checks actually run

All commands use Godot 4.5.1 headless. Exact commands and exit statuses are in [navigation-owned-checks.json](navigation-owned-checks.json). General form:

```sh
./tools/play.sh --headless --log-file /tmp/ra-owned-TEST.log --script tests/TEST.gd
```

| Test | Final outcome |
| --- | --- |
| test_regroup_recovery | PASS, 216,925 checks |
| test_riverside_navigation | PASS, 1,873 checks |
| test_tactical_flexibility | PASS, 52 checks |
| test_gap_navigation | PASS, 2,746 checks |
| test_actor_spatial | PASS, 1,447 checks |
| test_road_routing | PASS, 9 checks |
| test_cover_behavior | PASS |
| test_scenarios | PASS; three legacy victories at 111.8, 98.7, 168.8 simulated seconds |
| test_classic | PASS |
| test_classic_input | PASS |
| test_camera_zoom | PASS, 11 checks |
| test_scenario_dimensions | PASS, 37 checks; real sixth scenario present |
| test_tactics | PASS, 15 checks |
| test_simulation | PASS, 41 checks |
| classic_playthrough | FAIL: DEFEAT at 340.5 simulated seconds |

Per-test logs are `artifacts/navigation-owned-TEST.log`; passing runs were inspected for script errors and assertion failures, not only exit status. The platform certificate-store diagnostic persists on headless macOS runs.

## Stronger acceptance evidence

[Regroup evidence](regroup-recovery.json): the original single `[1,2,3,4]` attack-move plus scout order is retained. All three infantry sections reunite by 60 seconds; sections 1 and 3 have completed their orders then, while section 2 still has a 3.9-second block. By 90 seconds all three infantry orders are complete and blocked time is below one second. Command-group identity and original objectives remain unchanged. The village is friendly. Every tick checks friendly ground-body separation and soldier continuous swept terrain clearance. This is not a claim that the tank or every possible crowd layout completes.

[Riverside evidence](riverside-navigation.json): actual scenario index 5 / `riverside_town`, extent 144×108, shore 128; HQs at (10,97)/(114,9); four authored deposits. Real refinery and barracks construction, paid infantry deployment for both teams, and additional player harvester production succeed. Over 180 simulated seconds, original harvesters complete 3 and 20 moving loaded delivery trips; the newly produced harvester completes one. Refinery sites (6,86)/(116,26) deliberately separate collection/unloading zones so payouts alone cannot pass the trip check. The previously failing western dock layout is retained in the regression.

The economy fixture suppresses strategic attack waves and AI purchases to isolate production and hauling; tactical autonomy stays enabled. It is not a whole-match victory test. A separate real-map harvester traverses (18,97)→(114,20) under one explicit move with continuous terrain-clear movement. Town-spanning paths pass for radii 0.8, 1.9 and 2.65. Authored road-edge routes pass; the base-road node (14,97) is within the HQ clearance apron, so that route starts at a nearby reachable legal point. This does not claim every road centerline is directly traversable by every unit.

Real-map fog revelation/image extent, minimap far-region conversion, and zoom bounds pass headlessly. Existing input/zoom suites also pass. No native visual acceptance is claimed.

## Unresolved criteria and limits

- **Full classic mission policy acceptance remains open.** Final `classic_playthrough.gd` loses at 340.5s. An isolated reconstructed copy with this run's gameplay changes removed also loses at 338.3s; [reconstruction log](navigation-reconstructed-baseline-classic.log). Cover-only, director-only and arrival-only ablations also lose. This supports a pre-existing interrupted-state mission problem, but the reconstruction is not an untouched version-control baseline (the workspace has no Git repository). Do not report the old documented classic victory as revalidated.
- Riverside full combat/annihilation balance, native fog/minimap/zoom readability and render acceptance remain untested here. Manager controls native benchmarking and performance acceptance. No FPS/speedup claim.
- Congestion recovery is bounded local behavior, not a proof of arbitrary crowd deadlock freedom. Explicit commands still retain their restrictions, and deliberately sealed base exits can remain blocked.
- Nearby collection and unloading gameplay radii can overlap at some legal refinery sites, permitting stationary cargo cycling; the strengthened trip regression avoids relying on that behavior. Economic-radius/balance redesign is outside this fix.
- Temporary whole-cell dynamic-obstacle padding was rejected: it did not resolve the corridor or congested dock case and changed unrelated path behavior. Existing cached weighted AStar is retained.

Scenario JSON SHA-256 at validation: `7df5c71246fb8450dd95782c4b467cd6e9f95dfc10b8ebb742628e4c43fd8a82`. Concurrent manager changes after validation require corresponding integration checks.
