# 5: Vehicle stability and scenario identity

**Status:** completed
**Goal:** Remove artificial tank jitter and give each scenario distinct terrain and routes.

## Tasks
- [x] Remove chassis bob on flat ground; bound tracked hull yaw.
- [x] Preserve valid targets and discourage avoidance direction chatter.
- [x] Author agricultural shelter belts and parcels, urban blocks and streets, distinct objective coordinates, and shared visual/collision configuration.
- [x] Validate all three missions and geometry clearance; add target-lock/chassis stability regression.
- [x] Inspect native landscape renders and restart the playable build.

## Decisions
- Preserve separate turret articulation and gun recoil.
- Objective marker positions come from the same scenario data as collision poles.
- Coast retains the original geography. Fields loses harbor props and gains open farmland; Urban uses flat-roof blocks and asphalt streets.
- All maps still share the 96×72 footprint and eastern water boundary. Fully distinct shorelines/elevation remain future work.
