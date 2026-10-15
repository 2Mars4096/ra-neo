# Harbor City Design Rules

Design contract for plan 14. Fictional, Sevastopol-inspired: broad public urban
history only (limestone centre rebuilt after 1944, hillside private houses,
Soviet microdistricts, port and ship repair, vineyards). No real military data.

## Why the first harbor build looked artificial

- Buildings were placed at fixed spacing along every street, with types cycled
  from one 11-item list, so chapel/cafe/warehouse/farmstead sat side by side.
- Every lot had the same setback, size band and street-parallel orientation;
  five parallel lanes formed a ladder; no district had its own street pattern.
- No blocks, yards, walls, open spaces, landmarks, or decor tied to land use.

## What makes real towns read as authentic

1. **Era-specific morphology.** Each district is the product of one period and
   rule set: perimeter blocks (19th c./postwar), private-sector plots, Soviet
   superblocks, port/industrial estates, villages and fields.
2. **Streets → blocks → plots → buildings.** Buildings belong to plots cut from
   blocks; plot width varies (lognormal), corners get larger buildings.
3. **Setback and enclosure differ by district.** 0 m continuous street wall in
   the centre; 0–5 m behind walls in private sector; 12–40 m set back in open
   green superblocks; fenced yards in industry.
4. **Function follows location.** Shops on main streets/corners only; church on
   the hilltop/square; school inside the superblock; market near a transport
   node; cranes on quays; barns at field edges. Landmarks are rare.
5. **Topography drives geometry.** Ring + radial streets around a central hill;
   lanes follow contours; ravines (balka) stay green with garages/allotments.
6. **Back-of-house clutter.** Yards, sheds, walls, gates, laundry lines,
   garages, heat pipes, parked cars, rail sidings, stock piles.
7. **Unevenness and wear.** Height bands, roof forms, colour shifts, vacant
   lots, a building site, damage clustered near fighting (not random).

## Scale

1 world unit ≈ 1 m vertically (storey 2.7 u). Footprints are RTS-compressed
≈0.6× real. Map 1024×768 u ≈ 1.7×1.3 km real. All dimensions below are world
units: frontage W × depth D.

## District plan (keep current water, arterials, objectives, insertions)

| District (current bounds) | Morphology | Main types | Decor |
|---|---|---|---|
| Old peninsula town [222,345,190,215] | Historic centre: ring street around central hill, 4–6 radials, perimeter blocks 40–70 u with inner courtyards; waterfront boulevard and landing; hilltop square with cathedral (OLD TOWN objective) | classic_row, classic_corner, stalin_block, civic_hall, cathedral, colonnade_landing, market_hall | plane trees on boulevards, double lamps, monument, fountain, kiosks, trolley poles, courtyard trees/sheds/laundry, parked cars on side streets |
| Southern hillside [310,575,220,140] | Private sector: winding contour lanes 6–8 u, irregular plots 12–22 × 18–30, walled; ravine with garage cooperative and allotments | stone_house, outbuilding, garage_row, dacha_hut | stone walls+gates, grape pergolas, fruit trees, greenhouses, sheds |
| Freight harbor [555,342,290,180] | Port estate: quay apron with crane rails and sidings, transit sheds parallel to quay, workshops behind, tank farm, fenced perimeter with gate | transit_shed, workshop_hall, port_admin, gatehouse, slipway | portal cranes, rail sidings, boxcars, containers, fuel tanks, concrete fence, pipe/stock piles |
| Eastern bayhead [875,340,135,230] | Soviet microdistrict: superblocks bounded by arterials; slabs on two dominant axes forming open yards; school/kindergarten central; shops on arterial; garages at edge | panel_5, panel_9, point_tower (≤1), school, kindergarten, shop_pavilion, garage_row | playgrounds, heat pipes, parking bays, dumpsters, laundry lines, acacias, bus stops |
| Farm belt [550,600,330,130] | Linear village on farm lane; vineyard blocks of trellis rows; poplar windbreaks on field edges; cooperative yard | farmstead, stone_house, barn_long, coop_shed | vineyard rows, poplars, water tower, haystacks, tractors, irrigation ditches |
| North headland [660,50,250,110] | North-side settlement: private houses + 2–4 panel_5 near a ferry landing; old coastal battery ruin on the point | stone_house, panel_5, fort_ruin, shop_pavilion | pines, walls, small boats, pier |
| West insertion green [220,640,150,90] | Edge of town: petrol station on the spine, quarry/scrub, cemetery with cypresses | petrol_station, outbuilding | cypresses, fences, signs |
| Northeast reserve [915,60,100,140] | Enemy staging: fenced barracks compound, vehicle sheds, open parade ground | barracks, workshop_hall, gatehouse | concrete fence, checkpoint, antennas |

## Building families (`design` ids)

All built by `scripts/city_buildings.gd` dispatch. Local frame: centred, x along
frontage, street face at −z (ParcelKit convention). Every solid vertex stays in
[−W/2,W/2]×[−D/2,D/2]; height ≤ `CityBuildings.height_cap()` (floors×2.7 + 4,
or the per-family cap for domes and tall halls, e.g. cathedral 24).

| design | W range | D range | floors | notes | owner |
|---|---|---|---|---|---|
| classic_row | 10–24 | 9–12 | 2–4 | limestone/ochre, cornice, pilasters, shopfront or arcade variant | urban |
| classic_corner | 14–22 | 14–22 | 3–4 | L-plan, chamfered corner, optional turret; corner at −x,−z | urban |
| stalin_block | 36–56 | 11–14 | 4–5 | rusticated base, pitched roof, central arch to courtyard | urban |
| civic_hall | 28–40 | 18–24 | 2–3 | portico/colonnade, steps, pediment | urban |
| cathedral | 18–24 | 26–34 | — | central dome, drum, bell tower at −z | urban |
| colonnade_landing | 20–26 | 8–10 | 1 | colonnade arch + steps toward +z (water side) | urban |
| market_hall | 26–34 | 16–20 | 1 | clerestory hall + side stalls | urban |
| panel_5 | 36–48 | 9–10 | 5 | flat roof, 3–6 entrance canopies at −z, balconies at +z | urban |
| panel_9 | 48–64 | 10–11 | 9 | flat roof, lift machine rooms | urban |
| point_tower | 15–18 | 15–18 | 12–14 | landmark only | urban |
| school | 36–44 | 24–30 | 3 | П/H plan, sports ground is decor | urban |
| kindergarten | 22–28 | 16–20 | 2 | two wings, verandas | urban |
| shop_pavilion | 16–28 | 10–14 | 1–2 | glazed front, flat roof, signage | urban |
| stone_house | 7–11 | 6–9 | 1–2 | hipped tile roof, porch | works |
| outbuilding | 3–6 | 3–5 | 1 | summer kitchen / shed | works |
| dacha_hut | 4–6 | 4–5 | 1 | attic gable, veranda | works |
| garage_row | 3.2×n (n 6–24) | 6–7 | 1 | flat roof, individual doors at −z | works |
| transit_shed | 50–80 | 18–24 | 1 (9–11 u tall) | gable/sawtooth roof, rolling doors both long sides | works |
| workshop_hall | 28–50 | 16–22 | 1 (8–10 u) | gable, clerestory, high door at −z | works |
| port_admin | 22–30 | 11–13 | 3–4 | flat roof, sign | works |
| gatehouse | 5–7 | 4–5 | 1 | barrier arm is decor | works |
| slipway | 30–44 | 10–14 | — | ramp toward +z water, hull on cradle | works |
| barn_long | 24–36 | 10–12 | 1 | low gable | works |
| coop_shed | 30–44 | 14–18 | 1 | sheet-metal agricultural shed | works |
| petrol_station | 16–20 | 10–14 | 1 | canopy + kiosk + pumps | works |
| barracks | 36–48 | 11–13 | 3 | plain render, pitched roof | works |
| fort_ruin | 26–34 | 26–34 | — | low curved masonry battery, gun pits | works |
| farmstead / terrace / villa / cafe / chapel / warehouse / flat_block | existing | | | kept for fallback | existing |

Shared per-instance fields: `design`, `source_size:[W,D]`, `floors`, `variant`
(0–3 façade/roof variant), `palette` (0–3), `damage` (0 intact, 1 damaged,
2 ruined shell), `seed`, `rotation_degrees`, `position`, `district`.
`damage` is a parameter, not a family. Palette uses few materials and vertex
colour so chunk batching works.

## Layout compiler rules (tools/build_harbor_map.py)

- Blueprint holds districts as polygons with `morphology`. Streets are authored
  per district: centre ring+radials, contour lanes (bent polylines), superblock
  arterials, port grid, farm lane. Primary arterials/route checks stay.
- Blocks = land polygons between streets; plots cut along block edges with
  seeded lognormal widths (deterministic seed per block). No global spacing.
- Per morphology: perimeter (setback 0–0.5, continuous wall, corner buildings,
  courtyard interior kept open + courtyard decor), private (front 0–4, house
  at a front corner, walls on plot lines, garden + outbuilding at rear),
  superblock (slabs aligned to block axis or its perpendicular, ≥16 u spacing,
  yards between, central school/kindergarten), port (sheds parallel to quay,
  crane rail + siding between shed and quay edge), village (houses on lane,
  barns behind, fields beyond).
- Collision: never one large AABB for a rotated building. Emit per-building
  oriented footprints decomposed into ≤6 axis-aligned rects whose union covers
  the footprint with ≤1 u excess. `architecture[]` entries are independent of
  `blocks[]` and carry `collision:[first,count]`.
- Damage: 0 by default; damaged/ruined clustered within ~60 u of objectives
  and the freight front (10–20% there), never uniformly random.
- Must keep: all water polygons, objectives, insertion points, land/sea route
  points reachable, ≥16 u primary road width.

## Decor ids (resources/assets_city.json, builder scripts/assets_city.gd)

Footprint = collision rect [x,z,w,d] in local frame. Collision `flat` means no
blocker. Trees: collision trunk only; canopy is visual.

| id | footprint | h | collision | placement |
|---|---|---|---|---|
| tree.plane_street | [-0.5,-0.5,1,1] | 9 | solid | boulevard, courtyard |
| tree.acacia | [-0.4,-0.4,0.8,0.8] | 7 | solid | yard, street |
| tree.cypress | [-0.4,-0.4,0.8,0.8] | 9 | solid | church, cemetery |
| tree.poplar | [-0.4,-0.4,0.8,0.8] | 14 | solid | windbreak |
| tree.crimean_pine | [-0.5,-0.5,1,1] | 10 | solid | headland, park |
| lamp.boulevard_double | [-0.3,-0.3,0.6,0.6] | 5 | solid | boulevard |
| trolley_pole.span | [-0.25,-0.25,0.5,0.5] | 8 | solid | arterial |
| kiosk.newspaper | [-1.5,-1,3,2] | 2.6 | solid | corner, stop |
| kiosk.market_stall | [-1.5,-1.2,3,2.4] | 2.5 | solid | market |
| monument.column | [-2,-2,4,4] | 12 | solid | square |
| monument.statue | [-2.3,-2.3,4.6,4.6] | 7 | solid | square, park |
| fountain.round | [-3,-3,6,6] | 1.6 | solid | square |
| wall.stone_yard | [-3,-0.3,6,0.6] | 1.8 | solid | private, courtyard |
| wall.stone_gate | [-1.6,-0.3,3.2,0.6] | 2.4 | solid | private |
| fence.chainlink | [-3,-0.1,6,0.2] | 2 | solid | school, sport |
| fence.concrete_panel | [-3,-0.15,6,0.3] | 2.5 | solid | industry |
| fence.picket | [-3,-0.08,6,0.16] | 1.1 | solid | garden |
| playground.frame | [-4,-4,8,8] | 2.5 | solid | superblock yard |
| laundry_line.posts | [-3,-0.2,6,0.4] | 2 | solid | yard |
| heat_pipe.overground | [-6,-0.6,12,1.2] | 1.3 | solid | superblock |
| parking.bay | [-6,-2.5,12,5] | 0 | flat | yard, street |
| car.boxy_sedan | [-0.9,-2,1.8,4] | 1.4 | solid | street, yard |
| car.hatchback | [-0.85,-1.8,1.7,3.6] | 1.4 | solid | street, yard |
| van.minibus | [-1,-2.4,2,4.8] | 2.1 | solid | street, stop |
| dumpster.row | [-2.5,-0.8,5,1.6] | 1.3 | solid | yard |
| portal_crane.rail | [-3.5,-3.5,7,7] | 22 | overhead | quay |
| rail_siding.straight | [-12,-1.5,24,3] | 0.3 | flat | port, industry |
| freight_wagon.boxcar | [-7,-1.5,14,3] | 4 | solid | siding |
| tank.fuel_storage | [-6,-6,12,12] | 9 | solid | tank farm |
| container.stack | [-3,-1.25,6,2.5] | 5.2 | solid | port |
| pergola.grape | [-3,-2,6,4] | 2.4 | solid | private yard |
| greenhouse.film | [-2,-4,4,8] | 2.4 | solid | allotment, yard |
| shed.small | [-1.5,-1.5,3,3] | 2.6 | solid | yard, allotment |
| vineyard.trellis_row | [-10,-0.4,20,0.8] | 1.6 | solid | vineyard |
| water_tower.farm | [-2,-2,4,4] | 12 | solid | farm |
| haystack.round | [-1.5,-1.5,3,3] | 2.5 | solid | field |
| bench.park | [-1,-0.35,2,0.7] | 0.9 | solid | boulevard, yard |
| flowerbed.round | [-2.5,-2.5,5,5] | 0.3 | flat | square, yard |

Repeated decor renders with MultiMesh or chunk-baked meshes, never one duplicated
node per instance.

## Battlefield engineers (what they should be able to do)

Real combat engineers do mobility, counter-mobility, survivability and support.
All tasks cost supply, need an engineer section on site and take time.

| Tier | Task | Function in game |
|---|---|---|
| exists | Sandbag position, observation post, repair point, aid post | cover, sight, vehicle repair, infantry recovery |
| 1 | Concertina wire | infantry blocked/slowed; vehicles crush it |
| 1 | Anti-tank obstacles (hedgehogs / concrete blocks) | blocks vehicles; infantry pass and get light cover |
| 1 | Trench / vehicle berm | infantry dug-in cover; tank hull-down position |
| 1 | Clear obstacle | remove rubble, wreck, wire, barricade from a road |
| 1 | Forward supply point | purchased land units arrive here instead of map edge |
| 1 | Camouflage net | units under it are harder to detect |
| 2 | Breach wall / mousehole | infantry passage through a yard wall or row |
| 2 | Lay / detect mines | hidden AT mines; engineers reveal/clear |
| 2 | Fortify building | sandbagged windows: stronger infantry cover |
| 2 | Landing zone / drone relay | helicopter reinforcement point; drone range/jamming resistance |
| 3 | Gap crossing / quay repair / demolish bridge | open or close crossings; enable sea reinforcement at a quay |

## Off-map logistics (design only — implementation halted)

Supply is the only battlefield currency. The off-map layer decides the rate:
`income = base × production × transport × (1 − interdiction) + held_sector_bonus`.

- **Production** (later macro layer): factories/depots behind the front set a
  ceiling and what may be purchased.
- **Transport**: road convoys, rail, sea convoys through a held port, air
  bridge. Each has throughput and delay; supply arrives in convoy pulses.
- **Interdiction**: enemy strikes on routes reduce throughput temporarily.
- **Front-line**: held sectors (port, rail yard, fuel depot) add throughput;
  a forward supply point shortens reinforcement travel, not income.

Current game keeps the fixed `field_income`; the formula is reserved data for
the macro layer.
