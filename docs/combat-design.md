# Combat and communications contract

## Modeling choice

Separate target detection, weapon eligibility, range/line of fire, aim preparation, hit probability, and on-hit damage. A miss causes no HP loss. Near misses from eligible weapons can suppress infantry. Suppression reduces accuracy and fire cadence, not projectile energy.

The numbers in `resources/combat.json` are fictional balance multipliers. HP, ranges, and durations are compressed gameplay values, not physical measurements. The matrix deliberately omits rare component damage: rifles cannot eventually destroy a tank, armored AA vehicle, or corvette by accumulating hull damage. Real equipment is more varied than these seven classes.

## Roles

| Weapon | Infantry | Heavy armor | Light armor | Small UAV | Helicopter | Ship |
|---|---|---|---|---|---|---|
| Rifle | Primary | No hull damage | No hull damage | Low hit chance; one hit disables | Weak, difficult | No hull damage |
| AT launcher | Possible, inefficient | Strong | Strong | Cannot track | Cannot track | Effective abstract damage |
| Tank gun | Direct fire | Effective | Strong | Cannot track | Cannot track | Limited direct fire |
| Gunship weapon | Effective | Strong | Strong | Difficult | Possible | Limited |
| Naval gun | Fire support | Limited | Effective | Difficult | Possible | Effective |
| AA autocannon | Effective | No hull damage | Limited | Best tracking | Strong | Minor abstract damage |
| Recon UAV | Unarmed | Unarmed | Unarmed | Unarmed | Unarmed | Unarmed |

Tank and light-armor facings modify eligible damage: front ×0.7, side ×1, rear ×1.35. They never turn a zero-damage rifle hit into penetration. Infantry cover reduces on-hit damage. The current model has no component hitboxes, armor thickness, ammunition choice, splash damage, or physical interception.

Each rifle actor fires 3.75 base damage. The small UAV has 3 HP, so one successful rifle hit disables it. Rifle tracking starts at 16%, reduced by range and target/shooter movement; AA starts at 72%. These are explicit design choices, not an assertion that every real drone dies to every bullet contact. A moving drone can survive several volleys and still die on the first successful hit. Slant distance includes flight altitude. Randomness is seeded for reproducible tests.

## Communications

IRON DISTRICT's hostile EXCHANGE jams friendly units within 14 world units. The area is pre-briefed and marked on the minimap. Disconnected units keep the orders received before entry and acquire targets locally. Move, attack, stop, and retreat commands cannot reach them; failed commands are not replayed later. They stop uploading reconnaissance. Capturing EXCHANGE shuts the jammer down and restores command delivery. Friendly locations remain visible for usability; this is not a fully simulated radio network.

Individual soldiers retain their personal aim, cooldown, health, and local movement. Lost radio does not imply lost training or lost weapons. Current autonomy does not yet choose cover or plan a withdrawal independently. UAVs continue their received flight plan without uploading contacts; configurable return/land/hover failsafes remain future work.

## Evidence boundary

Broad role inspiration: the [Army mounted armored vehicle overview](https://cpeground.army.mil/Combat-Platforms/Project-Manager-Mounted-Armored-Vehicles/) and [Army counter-small-UAS catalog](https://www.army.mil/article-amp/253075/22_643_counter_small_unmanned_aircraft_systems_c_suas_catalog). Neither supplies or validates this game's numerical matrix. Automated tests establish the implemented relationships; playtesting must still establish balance and clarity.
