# Riverside waterfront worker report — 2026-10-14

## Bounded implementation

Only `scripts/roadside_props.gd` and `tests/test_roadside_props.gd` changed as production/test sources in this task. Reports/logs are separate worker artifacts. No scenario, terrain, visuals, effects, gameplay, central-doc or check.py edits; no delegation or native processes.

Eight original low masonry bays run along x127.5, within exact plan bounds **x126.9..128.0**, spanning **y16..102**. Two staggered masonry courses support individually jointed coping, top **0.56** world units above ground. Geometry is explicitly dimensioned, without node scaling. Bays are separated by 0.12 expansion joints, except the intentional **five-unit northern loading opening y29.5..34.5**. That opening preserves the tank-deployment sweep beside the northern base.

All 21 existing props retain their plan positions, yaw, colors and footprints. The three existing bollards are raised to the coping top at y=0.56; their full plan footprints fit the supporting bay. No fenders or extra clutter were added. New geometry adds **8 baked meshes and 1,800 triangles**; these are geometry counts, not measured rendering cost.

Quay rectangles enter terrain's existing shared roadside footprint list. Land collision and the existing 2D sight-blocker behavior therefore use the same bounds as the mesh. Sea navigation currently ignores roadside rectangles, so **no mesh or footprint extends beyond shore_x=128**: existing shoreline clearance excludes vessels from the entire solid quay. This does not claim a new sea-collision implementation or height-aware ballistics.

## Checks and evidence

[Exact commands/results and scenario hashes](waterfront-checks.json).

- `test_roadside_props`: **45,874 checks, zero failures**. Checks every rendered Riverside vertex against its footprint; exact bay bounds/height/gaps; bollard support; preserved original placements; no generic scaling; no overlap with other substantial props except intentional bollard support; actual 2.45-radius tank route along x123; preserved road shoulder access; actual 3.3-radius vessel envelopes tangent to the shore; land exclusion; and existing scenario3/4 regressions. [Bounds/mesh evidence](waterfront-bounds.json).
- `test_town_design`: **319 checks, zero failures** after the northern loading opening was added. [Log](waterfront-test_town_design.log).
- `test_riverside_navigation`: **1,880 checks, one failure**: the newly produced harvester does not complete a moving delivery in this layout. [Log](waterfront-test_riverside_navigation.log). Navigation acceptance is therefore incomplete pending gameplay-owner recovery work.

Scenario data remained unchanged before/after the integration runs, hash `46511e0f591fd613a5af230778ea8a5f24d15130ae6b914a9020ec0ce8a2f935`. The previous completed review used an older hash, so these runs checked the current version independently. Later scenario or gameplay changes require corresponding integration checks.

## Rejected layout and remaining integration blocker

The initial continuous edge with expansion joints blocked the northern factory fixture's available tank exit. A no-quay isolated comparison passed. The final five-unit loading opening restores that exit without changing construction/nav rules or weakening the map test; a direct footprint clearance assertion guards the opening.

The current Riverside failure is a later occupied unloading destination: produced harvester 13 carries 120 cargo near **(11.83,76.77)**, retaining destination **(10.95,81.05)** while produced rifle 14 occupies **(11.65,81.40)**. It remains blocked roughly 90 seconds by the end of the fixture. The same scenario with only the new quay omitted passes the complete Riverside suite. The added quay changes route selection/timing and exposes the later dock occupation; it does not physically occupy the western base.

`test_roadside_props.gd -- --haul-probe` is a diagnostic comparison of two otherwise matching economy fixtures, one with the quay and one without. It first observes a western harvester route/position divergence at 40.6 seconds and records the later occupied dock in [probe log](waterfront-haul-probe.log). This diagnostic does not replace the failing mission assertion. The isolated no-quay baseline logs are `waterfront-baseline-test_town_design.log` and `waterfront-baseline-test_riverside_navigation.log`.

The manager has been asked to route bounded occupied-dock recovery to the gameplay owner. This task does not own classic/simulation and has not altered them. No overall integration-success claim is made while the Riverside assertion fails.

## Limits

No native visual review or performance benchmark. The edge has no below-water retaining face, traversable deck, mooring simulation, destructibility or height-aware cover. The northern opening is clear natural bank/access space, not an implemented ramp or dock. Geometry/collision evidence does not establish full-match balance or arbitrary traffic recovery.
