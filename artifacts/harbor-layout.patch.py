p='artifacts/harbor-layout.author.py'
s=open(p).read()
marker = "bp['schema_version'] = 2\n"
assert marker in s
s = s.replace(marker, marker + '''bp['proposal']['assumptions'] = [
 "One world unit is one gameplay distance unit, not a survey scale; building footprints are RTS-compressed to about 0.6x real, storey 2.7 u.",
 "Land forces cross around the closed south-inlet head and the eastern main-bay head; there are no underwater roads or invisible bridges.",
 "All normal play uses field operations with one supply pool and engineer support; old scenarios remain hidden fixtures.",
 "Navigation cells are 4 units and fog cells are 8 units; primary corridors are 16-20 units wide, town streets 10-12, private lanes and tracks 6-8.",
 "Rotations use Godot Y yaw: local x,z points rotate clockwise by rotation_degrees (world = centre + (x cos a - z sin a, x sin a + z cos a), a = -yaw). Street face is local -z.",
 "Collision: architecture entries are independent of blocks; each carries collision [first,count] into blocks. A rotated footprint is covered by <=6 axis-aligned rects with <=1 u excess; where a street is too oblique for that, the building yaw is snapped toward the axis (a slightly stepped frontage, as on real slopes).",
 "Morphology note: each district is one period's rule set. Historic centre = rounded ring street around the cathedral hill with radials, waterfront boulevard and inlet embankment; perimeter blocks with corner buildings, continuous 0.8 u (side street) or 3.2 u (tree-lined main street) building lines and open courtyards. Hillside = contour lanes, walled private plots 11-21 x 13-30 with the house on a front corner, outbuildings and gardens behind, garages in the ravine. Microdistrict = superblocks between arterials with slab rows on the block axis, 18-22 u yards, a school or kindergarten, shops on the arterial and garages on the edge. Port = grid estate with transit sheds parallel to the quay, siding between shed and quay road, crane rails on the apron, workshops and a tank farm behind. Farm belt = linear village on one lane with barns behind and vineyard blocks edged by poplars. North side = private houses, three panel_5 near the ferry landing, a dacha cooperative grid and the battery ruin on the headland.",
 "Squares, parks, the cemetery, vineyards, fields, the tank farm, stockyard and parade ground are deliberate open space, not missing scatter. Damage is clustered within ~60 u of objectives and the freight front only.",
]
''')
open(p,'w').write(s)
print('ok')
