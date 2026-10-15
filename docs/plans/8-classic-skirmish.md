# 8: Classic RTS skirmish

**Status:** completed
**Goal:** Add the user's requested harvest/build/produce/destroy loop alongside the tactical missions.

## Tasks
- [x] 1. Finite deposits, harvesters, refinery delivery and replacement harvesting vehicles.
- [x] 2. HQ, power, barracks and vehicle factory; placement, construction and dynamic obstacles.
- [x] 3. Producer queues, prerequisites, low-power slowdown, rally points and cancellation refunds.
- [x] 4. Enemy economy/construction and base-destruction victory/defeat.
- [x] 5. Full-match, failure and viewport regression; native review and documentation. Launch through the standard game entry/Skirmish menu.

## Decisions
- User's vanilla RTS request explicitly expands the earlier showcase scope to a separate fifth mode.
- Existing tactical scenarios remain available. Classic starts with HQ, two infantry sections and one harvester per side.
- This first skirmish supports infantry, armor, AA and UAV production. Airfield/naval production, defenses, research and multiplayer are later increments.
- Starting base locations and deposit locations are scenario information. Live targets still require observation.

## Notes
- Early fixed enemy build sites could be occupied or unreachable; search legal nearby sites instead.
- Reserve enemy money for infrastructure before repeated combat production.
- End-to-end policy must scout the enemy HQ rather than indefinitely attacking only visible outer facilities.

- Production exits are bounded to the facility neighborhood. Actor-aware deployment waits when blocked.
- Construction cannot occupy finite deposits or individual soldiers. Refinery site selection considers haul distance.
- End-to-end policies exposed real income/defense tradeoffs: several lost their bases after leaving the economy exposed. The revised policy protects the approach, builds production and scouts before assaulting.
- Added actual viewport-button tests for placement, paid queues, cancellation and rally points; navigation regression covers the observed harvester grid-boundary jam.

- Latest normal-command classic victory: 554 simulated seconds, 23 kills, 15 losses, three own structures surviving. Economic/AI balance remains provisional.
