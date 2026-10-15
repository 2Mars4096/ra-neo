# Canal Watch: execution design

The target is a readable painted miniature battlefield: ochre fields on the west, a compact plaster-and-brick village in the center, and a cool blue industrial canal on the east. Low shelter belts frame traversable lanes; barns and workshop yards create landmarks. The existing unit roster remains recognizable at the gameplay camera distance.

## Battle storyboard
1. Observe: the UAV reveals village defenders while the mixed land force approaches.
2. Approach: infantry reserve separate nearby cover positions; armor turns and accelerates; supporting weapons cover a repositioning element.
3. Adapt: a blocked or exposed approach prompts a committed lateral maneuver. A damaged/pinned unit withdraws, then regroups toward its retained objective.
4. Capture: securing the village warns of a counterattack; enemy reserves choose their response to the player's established presence.
5. Defend: the force must survive the response and hold both sectors. The canal offers naval support along the eastern approach.

## Authority and commitment
Remote accepted commands replace the current maneuver immediately. Queued commands wait behind the current intent. Stop means hold, permitting local self-defense and posture changes but no autonomous departure. Explicit retreat disables fire and autonomous rerouting of intent. Radio loss rejects remote commands and preserves local initiative, using local perception only. No stale command replay on reconnection.

Tactical maneuvers retain the original objective and have named phases, minimum commitments, deadlines, and cooldowns. Team roles use living, available allies. Supporting waits expire; blocked maneuvers fall back to the original route. Damaged units can recover at staging without losing their mission intent. Decisions do not use unseen enemy positions.

## Boundaries
Flat-ground foot placement is procedural; no uneven-ground skeletal IK or real vehicle drivetrain simulation. Local cover selection uses verified reachable positions and reservations. Original scenarios keep their existing behavior while the showcase validates the new systems. Human play review remains distinct from scripted correctness.

## Weather, terrain and material direction
A passing front links atmosphere to sight and movement: roads stay firm, exposed fields and mud slow when wet, cover remains useful, and the canal separates land from naval routes. Rain and haze must leave selection/command cues readable. Soil dries more slowly than rain clears; the HUD reports the state.

Later user feedback asks for less toy-like surfaces. Retain painted military scale-model color discipline, but use credible roof construction, varied building heights, fine facade detail, beveled equipment and different finishes for glass, rubber, steel and paint. Plaster staining, tiled courses and metal seams add material identity without changing collision footprints. Production textures, bespoke sculpted characters and skeletal rigs remain further work.

## Environmental dressing review
Treat the scene as a functioning place before adding battle damage. The current pass varies domestic/industrial roofs, window construction, chimneys, downpipes and rooftop service vents; ground scarring stays localized. Major geometry shares collision footprints. Tiny surface marks are visual only and confer no cover.

Further dressing candidates are roadside drainage, boundary fences, loading equipment, stored supplies and localized rubble. These are not yet implemented as a full prop library. Future substantial obstacles must enter navigation and sight checks; never fill route gaps with decorative collision surprises. Keep damage concentrated around encounter locations instead of uniformly scattering debris. Terrain relief and richer vegetation remain separate art work.
