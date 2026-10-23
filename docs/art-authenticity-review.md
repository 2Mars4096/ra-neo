# Authenticity study: details that carry meaning

2026-10-14. User clarification: preserve quality; do **not** make the game coarse. Study why convincing worlds survive limited resolution. Findings below are visual interpretations of inspected publisher/developer images, not claims about undocumented rendering internals.

## Inspected references

- [RA2 publisher screenshots](https://store.steampowered.com/app/2229850/): first naval assault image (`ss_e46d63df85e3c001e8488d48dba44a0d9e0869b0`). Service ramps, vents, ribs, concrete pads, perimeter walls, wheel tracks, craters and a varied shore establish purpose and contact. Bright faction accents coexist with readable shaded machinery. It is stylized, yet objects describe their function.
- [AoE II DE official gallery](https://www.ageofempires.com/news/visual-look-at-aoe2de/): Barbarossa waterfront screenshot. Roof overhangs, masonry faces, narrow streets, connected enclosures and waterfront foundations give construction logic. Repeated houses form a settlement instead of isolated display pieces. Open squares are framed and usable; trees form masses.
- [Songs of Syx publisher screenshots](https://store.steampowered.com/app/1162750/Songs_of_Syx/): first night-city image (`ss_f2d8c5d47a23f8d54560d144fdad30677c602817`). Thick room boundaries, door connections, furniture/storage arrangements, planted paths and pools distinguish functions. Repetition works because it builds coherent rooms and streets; varied rooms interrupt it. Local lights reinforce occupation, though this is no argument to add hundreds of runtime lights to For Every Dawn.
- [AoE DE developer explanation](https://www.ageofempires.com/news/age-empires-definitive-edition-3d-2d-game/): explicitly describes 3D source models rendered into 2D images and separate rendered zoom levels. This is about AoE DE, not proof of every named game's pipeline. The relevant lesson is to judge assets at intended gameplay scale, not assume real-time polygon or texture count establishes quality.

The browser's Google search encountered a verification page; direct publisher pages remained accessible. No verification bypass, asset extraction into runtime, or licensing assumption.

## Decisions for For Every Dawn

| Detail | Why it matters | For Every Dawn action / acceptance |
|---|---|---|
| Roof eaves, openings, foundations | Explains construction and thickness | Existing geometry retained; inspect readable dark recesses and roof/wall separation at zoom44 and70 |
| Door–path–street connection | Makes a building belong to the town | Reduce selected main-street setbacks, preserve driving clearance; further continuous frontage remains needed |
| Quay face, coping, supported bollards | Explains why freight roads meet water | Author a bounded waterfront edge with shared blockers; do not scatter fenders on bare sand |
| Stock beside loading doors | Shows function, not random clutter | Two fitted warehouse pipe racks; keep loading access visibly clear |
| Gardens, yards, squares and service lanes | Gives empty land a reason | Current district tint is insufficient; compose boundaries and use before further map expansion |
| Tire wear, drainage staining, chipped corners | Shows cause and use | Prefer localized wear at contact/use points; avoid uniform dirt/noise on every face |
| Material-specific large features | Identifies material at normal zoom | Roof tile courses, plaster loss exposing brick, metal seams/rubber tracks; do not rely on microscopic noise |
| Consistent silhouette/light/value | Keeps the scene coherent and units readable | Preserve miniature presentation and material quality; no blanket pixelation or resolution downgrade |

## Current assessment

The authored map adds route/economy decisions and differentiated parcels, but the reference target remains incomplete. Density must come from connected buildings, boundaries and activity areas, not uniform scattering. Roadside paving/grates already exist (a review's claim that none exist is incorrect); their visual weight and continuity remain too weak. Tank/boat surfaces and foliage still need authored shape/material detail. Further enlargement is lower priority than completing one coherent street and riverfront composition.
