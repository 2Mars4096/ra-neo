# Classic navigation follow-up — 2026-10-14

**Resolved:** the unchanged production `classic_playthrough.gd` wins at **371.9 simulated seconds**, with two friendly structures remaining and all enemy structures destroyed. Twelve headless suites pass. Final Riverside validation passes 1,876 checks on stable, reviewer-corrected scenario data.

## Root cause and evidence

`classic-navigation-attacktrace.log` records seven player tanks attempting the observed enemy HQ at t=180.1s. Every command returns `accepted=0`, selecting the same unreachable firing candidate **(45,11)**. The tanks retain prior staging orders instead of beginning the HQ assault. This is a command destination/connectivity failure, not insufficient combat stats or an actor regroup timeout.

Minimal reproduction in `tests/test_classic_navigation.gd`: enemy HQ (62,9), power (46,6), barracks (46,16), player tank (21.05103,30.94121). The old nearest geometrically valid candidate (45,11) has no terrain path. Initially, both reachable-position and command-acceptance assertions failed.

A test-only subclass (`tests/reachable_attack_probe.gd`) changed only firing-position selection to try distance-sorted valid candidates until a footprint-aware route exists. `tests/classic_reachable_probe.gd` used an otherwise identical canonical mission policy and VICTORY assertion. This produced VICTORY at 371.9s, proving the correction before production integration. The policy/assertion copies were compared exactly after normalizing only preload/output paths.

The simulation owner then integrated the correction in `simulation.gd::attack_position`. This worker did **not** edit that file. The production regression now chooses reachable **(51,15)**, accepts the direct HQ attack and retains its exact target ID. The unchanged production classic mission then reproduced VICTORY at 371.9s; see [full mission log](classic-integrated-playthrough.log).

## Owned production fix

Only `scripts/classic.gd` was edited in this follow-up. `Classic.known_base_approach` replaces the fixed fallback `(18,height−36)`, which stops approximately 26 units from the player HQ. It uses disclosed starting HQ coordinates derived from map bounds and searches 16 terrain-clear, connected observation approaches within ten units of that location, or 65% of the attacker's sight if shorter. It selects the shortest route without reading hidden live enemy positions or assigning a hidden target ID.

The regression exercises the actual AI fallback branch, verifies that moving an unobserved mobile enemy does not change its destination, and moves a rifle section until it observes the previously hidden HQ. Default-map approach **(13.82684,51.76121)** yields contact at **12.1s**. The final real Riverside suite also checks that the expanded-map fallback reaches the disclosed HQ sight neighborhood.

No unit stats, combat effectiveness, production prices, mission policy, victory assertion, or explicit-command rules were changed. Existing move/hold/retreat/replacement authority regressions pass.

## Final checks actually performed

[Exact commands, exit codes and error scans](classic-followup-checks.json). All use `./tools/play.sh --headless --log-file /tmp/... --script tests/NAME.gd` under Godot 4.5.1.

| Test | Result |
| --- | --- |
| classic_playthrough | PASS, VICTORY 371.9s |
| test_classic_navigation | PASS, 8 checks; reachable HQ attack and disclosed-base approach |
| test_riverside_navigation | PASS, 1,876 checks |
| test_classic | PASS |
| test_classic_input | PASS |
| test_tactical_flexibility | PASS, 52 checks |
| test_cover_behavior | PASS |
| test_tactics | PASS, 15 checks |
| test_regroup_recovery | PASS, 216,925 checks |
| test_scenarios | PASS, three legacy mission victories |
| test_simulation | PASS, 41 checks |
| test_combat | PASS |

Logs use `artifacts/classic-followup-NAME.log`, except the full mission log linked above. Headless macOS still emits its certificate-store diagnostic; no script errors/assertion failures were accepted as passing.

## Stable Riverside evidence

Waited for `town-design-review.json` to report completed corrections with zero failures and the same scenario hash as current data. Final independent run verified the scenario hash remained identical before and after execution:

`f01546404624c02e0b990e748e74609b24d0014e7e144e68fbfc214c5025119d`

[Riverside evidence](riverside-navigation.json): both HQs, four authored deposits, real refinery/barracks construction, paid infantry production, additional harvester production, continuous long-route movement, authored road connectivity, expanded fog/minimap/zoom bounds and the new enemy approach check pass. Original harvesters complete 3 and 20 moving loaded deliveries; the produced harvester completes one. Strategic purchases/attack waves are suppressed only in the economy-isolation fixture; tactical autonomy stays enabled. This is not a full Riverside combat victory claim.

[Source hashes](classic-followup-source-hashes.json) identify integration inputs. The canonical `classic_playthrough.gd` remained unchanged, SHA-256 `7c9f2dc802b985c31b537f8b6847df250cbf12c6aefe85d4a0693ec316bd4be8`.

## Remaining limits and ownership

No unresolved blocker remains for the reproduced classic command rejection or the fallback approach defect. Full Riverside combat balance, native visual acceptance, arbitrary-crowd deadlock freedom and runtime performance remain unvalidated. Candidate search uses existing cached weighted AStar; no speedup or frame-time claim.

This worker edited only classic.gd, navigation tests/diagnostic probes and own reports. Simulation correction belongs to the integration owner; map corrections belong to the reviewer. No central docs, check.py, art, effects, battle or HUD edits, no delegation and no native processes/benchmarks were launched.
