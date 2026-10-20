# 14-1: Soldiers reach physical cover

**Parent:** [14: Harbor city realism](14-harbor-city-realism.md)
**Status:** completed
**Goal:** Make shelter destinations reachable beside the actual wall or field work, and keep the shelter state consistent with physical protection.

## Tasks

- [x] 1. Reproduce the reported gaps with real simulation ticks and staged native captures on the unchanged branch baseline.
- [x] 2. Match sandbag face positions to the standing body and terrain clearance; remove the duplicate circular obstacle around rectangular field works.
- [x] 3. Recover from blocked approaches and destroyed shelter, including partial squad occupation, without displacing valid occupants.
- [x] 4. Share common building wall profiles between render builders and map collision emission; retain authored layout and explicit complex-shape fallbacks.
- [x] 5. Run focused collision, cover, garrison, destruction and navigation regressions; inspect identical before/after native views.
- [x] 6. Update the existing review branch and [draft PR #1](https://github.com/2Mars4096/ra-neo/pull/1) with the tested changes and remaining limits.

## Confirmed causes

- Sandbag work slots were 0.85 units outside their rectangle. A standing soldier needs 0.8 body radius plus 0.12 terrain clearance, so those slots could never pass the movement test.
- Slot reservation, actor clearance and avoidance also treated field works as circular actors. A terrain-valid flank waypoint was inside that extra circle; a soldier stayed `SEEKING` for more than 28 seconds.
- The idle branch skipped occupied soldiers before checking geometry or failed movement. Destroying a naturally occupied trench left all soldiers `SHELTERED` on unprotected ground.
- Work slots were 1.4 units apart, less than the 1.55-unit separation required by standing bodies. After partial trench destruction, a returning soldier could not fit between two settled occupants. Slots now use 1.65-unit spacing.
- Slot spacing alone did not prevent overlapping reservations across adjoining works or neighboring sections. Work occupation now reserves distance against nearby friendly active shelter goals, including generic cover and newly assigned work goals.
- Nearby-work discovery could assign a goal outside the 10-unit soldier leash. Filtering individual destinations and sharing bounded routes prevents repeated assignment of an unreachable goal.
- Harbor building blockers represented entire placement parcels. Common visible walls are inset within those parcels, so a panel-building shelter could be 2.05 units from the actual facade while only 1.05 from the parcel edge.

## Scope and decisions

- Keep soldier body sizes, swept checks, player command precedence and the existing 10-unit local leash.
- Physical field-work rectangles remain authoritative for collision; mobile vehicles and other soldiers retain body avoidance.
- An approach has a finite deadline. Completed, valid shelter can be held indefinitely; missing or unusable shelter must be cleared.
- Preserve building placement envelopes, positions and rotations. Rendered ground walls and compiled collision use shared profiles for the supported simple families. Custom shapes retain an explicit conservative fallback pending their own compound profiles.
- Native images use the actual game renderer and normal soldier simulation in controlled fixtures. Software-rendered captures are placement evidence, not hardware-performance certification.

## Verification

- Negative controls: the expanded `test_cover_contact.gd` produces 20 expected failures across 99 checks on unchanged baseline code and passes all 99 after the fixes. Restoring only the pre-reservation cover source produces exactly two failures: adjoining-work and neighboring-section goal separation. The intermediate version eventually recovers through the earlier timeout fix, but still assigns incompatible goals during the approach. The contiguous-work fixture seeds fixed structures before spawning soldiers; it does not claim the construction UI places contiguous segments. Wall/vehicle/body collision controls remain intact.
- `test_city_collision.gd`: 24,373 checks pass, including actual rendered ground-face agreement, supported rotated buildings, low-obstacle cover/LOS semantics and collapse ownership. `test_harbor_layout.gd`: 55,118 checks pass. Compiler output is reproducible.
- Native captures use identical initial positions, cameras, threat bearings and 24 seconds of normal simulation. The three sandbag soldiers improve from 3.02–4.49 units outside the footprint with no cover goal to 0.95 units, crouched and sheltered. The two soldiers using the panel facade improve from 2.05 to 1.3544 units from the visible wall. These are center-to-surface measurements; the third panel-fixture soldier selects a neighboring house and is excluded from that facade measurement.
- Final integration on Godot `4.5.1.stable.official.f62fdbde1`: **24 selected suites pass, zero failures**. Coverage includes engineer works, building collision and Harbor layout/gameplay, field geometry/operations/outcomes, regroup recovery, actor indexing, roadside props, cover behavior/contact, legacy Showcase, clearance, garrisons/fire, destruction/bombardment, contact drill, per-body cover, wave strength, enemy defences and large terrain. The prior seven mission-fix suites are included. `python3 tools/build_harbor_map.py --check` is reproducible and `git diff --check` passes. The separate cover-cost timing failures below remain open.

## Performance review

The initial unchanged cover-cost benchmark exposed a new hotspot after the more precise geometry: the `(500,680)` contact fixture rose from 19.9 to 89.5 ms. Profiling found many internal strip-edge candidates and excessive false positives in 32-unit obstacle buckets. The final patch uses conservative 2-unit buckets for narrow queries, validates static indexes once per sampled sight line, and rejects solid interiors before coastline tests. Wide query order, exact predicates, search limits and timing thresholds remain unchanged. All 48 sampled simulation-state hashes match the fixed-geometry code before this optimization, including positions, goals, orders, paths, HP, combat RNG and outcomes.

Final serial comparison, unchanged `tests/test_cover_search_cost.gd`, Godot 4.5.1, required navigation warm-up, no overlapping Godot processes:

| Case | Original baseline | Final fixes |
| --- | ---: | ---: |
| Warm 40-unit order: worst cover work per tick | 11.7 ms | 15.1 ms |
| Contact `(420,560)` | 28.6 ms | 26.5 ms |
| Contact `(500,680)` | 17.3 ms | 29.1 ms |
| Contact `(440,575)` | 15.8 ms | 16.0 ms |
| Maximum across warm cases | 28.6 ms | 29.1 ms |
| Cold soldier-grid initialization case, informational | 282.2 ms | 322.7 ms |
| Total benchmark process wall time | 16.82 s | 21.24 s |

**Performance acceptance remains open.** The baseline has one failing timing assertion; the final fixes have two. Both preserve all functional response assertions. At `(500,680)`, 23 of 24 sections start for cover within 1.2 seconds after the fix, versus 22 within 1.0 second before. That location remains slower than its own baseline and exceeds the unchanged 25 ms limit, despite reducing the initial 89.5 ms regression to 29.1 ms. The close overall peak does not erase the per-location or total-runtime cost. These are controlled simulation-work measurements on this host, not rendered frame rates or hardware certification.
