# 10: Riverside battlefield and combat presentation

**Status:** in-progress
**Goal:** Build an authored larger classic RTS battlefield with readable combat effects and validated navigation.

## Design decisions
- 144×108 is a bounded first expansion (2.25× area), not a claim of town-scale thousands-unit readiness.
- Southwest and northeast headquarters have separate starting resource fields and clear space to build. Two farther fields create expansion/raiding decisions.
- The town centre offers a comparatively direct approach, with buildings screening approaches and intersections exposing crossings.
- A western off-road route follows managed shelter belts, crosses north of the southwest neighbourhood, and rejoins the northern road. It keeps soil/weather movement costs; it is not another full-speed asphalt road.
- An eastern freight route has wider vehicle access, loading/service context, and a contested resource field. The river bounds its eastern side.
- Roads and walkable lanes are laid out first. Parcels face those routes, and props occupy intentional service/parking/utility locations with matching bounds.
- Twenty parcels reuse eleven building families across districts. Reuse is deliberate; twenty unique production assets are not claimed.
- Four worker tracks: navigation, VFX, category/variant library, independent map review. Lead owns layout and final integration.

## Tasks
- [x] Author road hierarchy, district functions, base/resource positions and parcel metadata.
- [x] Adapt world/water/weather geometry to scenario dimensions.
- [x] Add grounded roadside industry/street/waterfront props with shared footprints.
- [ ] Validate full-map route alternatives, clear starting economies, production and enemy playthrough.
- [x] Integrate distinct firing, impacts and staged explosions without changing damage rules.
- [x] Review element categories and variants; separate implemented assets from planned ones.
- [ ] Run native captures, behavior checks and isolated performance tests; fix valid cross-review comments.

## Acceptance
The starting economy works; roads do not cut through solids; infantry and vehicles can use the intended approaches; both bases can be attacked; camera, fog and minimap cover the full map. Effects remain bounded, visually distinct and cosmetic. Native screenshots, not just geometry tests, must be inspected. Performance and remaining limitations must be reported.

## Route decisions from validation
- Shift the northern freight parcel and high-street car to preserve full tank clearance. Link the southern freight road through (108,98), avoiding a cable reel while keeping a continuous paved route.
- Place the western expansion at (42,34): initial nominal access is about22 versus24 seconds, replacing a strongly player-favored12.5 versus31.7-second placement. These are path timings, not whole-match balance proof.
- Western route is deliberately slower and partly covered; central streets are faster but expose crossings; freight is paved and passes expansion/industrial traffic. No uniform scaling of the original layout.
- Use compacted earth and gravel around town/industrial frontages; retain underlying off-road/weather costs. Two pipe racks fit actual warehouse docks inside existing blocked parcels; library fenders/sandbags remain unplaced when safe contextual placement is absent.
