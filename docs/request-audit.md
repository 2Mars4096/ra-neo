# Request review — 2026-10-14

The game remains a playable prototype. Passing regression suites does not establish AAA quality, tactical realism, human enjoyment, or thousands-unit capacity.

| Request | Observed state | Still unfinished |
|---|---|---|
| Soldiers visibly seek shelter | New individual routes, separate reserved slots, staggered movement, arrival/settle and selected-squad route feedback in Canal Watch and Frontier | Migration to original three maps; peeking, crawling, vaulting and interiors; larger navigation regions |
| Different soldier states | Independent health, aim, shots, reloads, suppression, crouch/prone/rise and travel-driven legs | Production skeletal animation and broader visual review |
| Smart combined arms | Land-group support/flank/withdraw/regroup; explicit orders constrain initiative | Stronger role assignment, flight/naval decision models, human assessment of tactical quality |
| Realistic weapon relationships | Eligibility, accuracy and damage separated; rifle/armor immunity and fragile UAV rules | Fictional numbers need balance testing; no physical ballistics or comprehensive directional cover |
| Communications disruption | Jammer blocks new commands/uploads; local behavior continues | Detailed communication propagation and alternate EW interactions |
| Vanilla RTS | Base building, finite harvesting, power, queues, enemy economy, annihilation victory | Air/naval production, defenses, research, repair/sell and fuller economic balance |
| Distinct scenarios | Five modes including canal village and skirmish | Full town dimensions, richer topography, broader mission variety |
| Terrain/weather | Terrain speed, cover/sight blockers, rainy showcase/skirmish, wet ground, wind-driven smoke | Elevation, richer terrain interaction, wider weather variety |
| Art, materials and decor | Painted-miniature direction, procedural mesh/material and facade variations, weather/VFX | Bespoke production assets, richer vegetation, coherent prop library; present art remains visibly procedural |
| No clipping/shaking | Swept clearance, spacing, steadier hull motion, automated geometry checks | Universal guarantee is not established; continued crowded-route and animation review |
| Thousands of troops | Spatial queries and indexed lookup; synthetic query benchmark | Full 250/500/1,000/2,000-entity battles, large maps, navigation/render scaling; 16.7 ms target unmet |

## Unit-role review

These are game-design interpretations, not real-world operating procedures. The [Army urban combined-arms overview](https://www.army.mil/article/287773/combined_arms_in_urban_operations_insights_into_atp_3_06_11) supports complementary infantry/armor roles. The [Army aviation teaming account](https://www.army.mil/article/122498/guard_soldiers_fly_manned_unmanned_aircraft_train_together) illustrates reconnaissance and information sharing between unmanned and manned aircraft. Neither validates our numerical values or small-UAV model.

- Rifle section: independently find shelter, settle, acquire and fire; preserve separation and player intent. Implemented in this pass.
- Anti-armor team: same personal shelter/readiness system; weapon eligibility differentiates its targets. Specialized deployment animation remains open.
- Tank: existing deliberate hull movement, independent turret, support and withdrawal. More capable protected-route selection remains open.
- AA vehicle: existing air-capable weapon relationships; deliberate air-threat prioritization and escort assignment remain open.
- UAV: existing observation, shared contacts and communication loss; reconnaissance routes, endurance and autonomous recovery remain open.
- Helicopter: existing flight presentation and weapon eligibility; flight-specific maneuver decisions remain open.
- Corvette: existing naval navigation and weapons; coordinated naval maneuvers remain open.
- Harvester: existing finite collection/delivery; convoy protection and threat-aware rerouting remain open.

Read-only AA/naval reference retrieval was attempted but returned timeout/403; no detailed doctrine claims are based on those pages.
