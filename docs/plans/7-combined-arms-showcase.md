# 7: A believable combined-arms showcase

**Status:** in-progress
**Goal:** Deliver the reviewed integrated showcase with broad autonomous coordination, individual behavior, convincing motion, and a canal-village mission.

## Tasks
- [x] 1. Visual target sheet and battle storyboard at gameplay scale.
- [x] 2. Objective/command authority, committed decisions, explanations, and communication-loss rules.
- [x] 3. Independent cover movement, vehicle steering, coordinated maneuvers, animation, and focused encounter checks.
- [x] 4. Distinct canal-village showcase and capture-triggered counterattack.
- [ ] 5. Native review, mission/override/communications/congestion regression, profiling, and human play review.

## Contract
Broad autonomy is confirmed: choose flanks, disengage, and regroup. New received orders replace the active plan; hold and retreat constrain initiative. Retain the existing roster and painted military miniature direction. New autonomy and mission behavior are introduced in one showcase before extending existing scenarios. No campaign, multiplayer, or new unit classes.

## Acceptance
Demonstrate scouting, coordinated approach, personal reactions, withdrawal/regroup, capture, and defense through normal commands. Check failure recovery, stable decisions, no clipping in reviewed cases, and frame p95 against 16.7 ms. Human enjoyment/clarity review requires actual player feedback and will not be labeled passed by automation.

## Progress and admitted additions
- Implemented CANAL WATCH as the fourth selectable scenario; original three keep their existing tactical rules.
- Broad autonomy is implemented for land command groups, with local soldier cover/spacing, support waits, flanks, withdrawal and regroup deadlines. Air/naval assets retain their existing command behavior.
- Added weather/environment effects at the user's request: a deterministic passing rain front, wet soil, reliable roads, reduced sight, drifting smoke, bounded rain and haze. Terrain remains planar; no elevation or water-flow simulation.
- Responded to further art feedback with varied roof forms/heights, facade details, beveled equipment, distinct surface finishes, roof/plaster/sheet-metal textures and cultivated field treatment. These remain original procedural assets, not a production-art replacement.
- Automated mission, movement, command, communications and legacy regressions pass. Native visuals have been inspected; human enjoyment/clarity review and the 16.7 ms performance acceptance remain open.

- Additional user steering: connect shelter seeking and firing preparation to behavior. Implemented crouched aim, pinned prone when clear, rising, independent reload and articulated knee/ankle poses. Dedicated stance tests and a rendered stance study accompany these changes; interiors/crawling/vaulting and destructible barricades remain outside this increment.

- User-added classic economy is tracked separately in [8](8-classic-skirmish.md); it does not replace the reviewed showcase.
- Environmental dressing review records installed facade/roof service detail and localized damage separately from the future prop library in showcase-design.md.

- Player feedback found cover movement insufficiently visible. [7-1](7-1-visible-cover.md) replaces close slot adjustment with actual bounded individual shelter routes and visible feedback; this correction does not establish full infantry tactical AI.
