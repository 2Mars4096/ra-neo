import json
path = 'resources/maps/black_sea_harbor.json'
bp = json.load(open(path))
keep = {s['name']: s for s in bp['streets']}
cls = {'Peninsula spine': 'avenue', 'Bayhead ring': 'arterial', 'Freight arterial': 'arterial',
       'Quay service road': 'port', 'Cargo east connector': 'port', 'Farm north access': 'track'}
streets = []
for name, c in cls.items():
    s = dict(keep[name]); s.pop('plots', None); s.pop('spacing', None); s.pop('offset', None); s['class'] = c; streets.append(s)
def st(name, width, c, purpose, pts):
    streets.append({'name': name, 'width': width, 'class': c, 'purpose': purpose, 'points': pts})
# Historic centre: rounded hill ring, radials, waterfront boulevard and embankment.
st('Primorsky boulevard', 12, 'boulevard', 'old town waterfront boulevard', [[214,343],[300,341],[340,342],[406,340]])
st('Inlet embankment', 10, 'boulevard', 'old town inlet embankment', [[406,340],[408,415],[410,492],[418,530],[432,556],[450,575],[452,607.5]])
st('Hill ring north', 12, 'avenue', 'old town hill ring street', [[297.1,398],[386,398],[408,415]])
st('Hill ring south', 12, 'avenue', 'old town hill ring street', [[410,492],[396,510],[290,510]])
st('West sea street', 10, 'street', 'old town western sea street', [[214,343],[212,410],[224,490],[218,560],[240,590],[270,600]])
st('Cathedral radial', 10, 'street', 'old town radial to boulevard', [[325,398],[325,354.4]])
st('Admiralty radial', 10, 'street', 'old town radial to boulevard', [[362,398],[362,341.3]])
st('Lazarev street', 10, 'street', 'old town cross street', [[297.1,398],[212.4,398]])
st('Greek street', 10, 'street', 'old town cross street', [[290,455],[218.75,455]])
st('Market street', 10, 'street', 'old town cross street', [[290,510],[222.3,510]])
st('Dock street', 10, 'street', 'old town cross street', [[288.8,553],[430.4,553]])
st('South radial', 10, 'street', 'old town radial to ring road', [[340,510],[340,604.4]])
st('Embankment radial', 10, 'street', 'old town radial to ring road', [[385,510],[385,607.2]])
# Hillside private sector: contour lanes, steep connector, ravine road.
st('Upper contour lane', 7, 'lane', 'hillside private lane', [[274.5,636],[320,642],[365,638],[410,646],[440,642]])
st('Middle contour lane', 7, 'lane', 'hillside private lane', [[322,694],[362,690],[412,694],[446,690]])
st('Lower contour lane', 7, 'lane', 'hillside private lane', [[332,728],[358,725],[400,730],[452,725]])
st('Hillside steps', 7, 'lane', 'hillside connector to ring road', [[360,605.6],[358,638.6],[362,690],[358,725]])
st('Ravine road', 8, 'garage', 'ravine garage cooperative road', [[440,608.8],[440,642],[446,690],[452,725]])
st('East upper lane', 7, 'lane', 'hillside private lane', [[440,642],[480,648],[520,640],[556,646]])
st('East lower lane', 7, 'lane', 'hillside private lane', [[446,690],[490,684],[530,692],[560,688]])
st('East hillside lane', 7, 'lane', 'hillside connector to ring road', [[520,599.6],[520,640]])
# Port estate grid.
st('Port road north', 12, 'street', 'port service grid', [[560,407],[711,410],[809.2,400]])
st('Port road south', 12, 'street', 'port service grid', [[560,468],[701.7,470],[810,466]])
st('Port west road', 12, 'street', 'port service grid', [[565,353],[560,407],[560,468],[560,595]])
st('Dock cross road', 12, 'street', 'port service grid', [[632,353],[632,582.1]])
st('Shipyard lane', 10, 'street', 'ship repair yard access', [[560,440],[512,440]])
# Eastern bayhead microdistrict superblock arterials.
st('Bayhead north lane', 12, 'avenue', 'microdistrict superblock street', [[920.8,262],[1010,262]])
st('Bayhead avenue', 14, 'arterial', 'microdistrict superblock arterial', [[925.7,335],[1010,337]])
st('Garage lane', 10, 'garage', 'microdistrict garage edge', [[880,525],[1010,540]])
st('Microdistrict east road', 12, 'avenue', 'microdistrict superblock street', [[1010,262],[1010,337],[1010,540]])
# Farm belt village and vineyard track.
st('Farm lane', 9, 'lane', 'linear village lane', [[565,686],[620,690],[690,680],[745,665],[800,676],[860,688],[895,698]])
st('Vineyard track', 6, 'track', 'vineyard service track', [[820,540],[820,680]])
# North side settlement, ferry and battery track.
st('North shore road', 12, 'street', 'north side settlement road', [[630,165],[700,172],[770,182],[840,200],[922.2,235.6]])
st('North upper lane', 7, 'lane', 'north side private lane', [[690,128],[750,118],[820,126],[880,132],[936.2,145]])
st('Ferry lane', 7, 'lane', 'north side connector', [[700,172],[700,126.3],[700,92]])
st('Chapel lane', 7, 'lane', 'north side connector', [[800,189.7],[800,123.7],[800,98]])
st('North hill lane', 7, 'lane', 'north side private lane', [[700,92],[750,95],[800,98],[860,102],[905,106]])
st('Ferry landing lane', 8, 'street', 'ferry landing access', [[760,183.8],[760,203]])
st('Battery track', 6, 'track', 'track to coastal battery ruin', [[247,160],[330,145],[450,130],[530,131],[640,132],[690,128]])
st('Dacha upper lane', 6, 'lane', 'dacha cooperative lane', [[300,72],[400,70],[500,68]])
st('Dacha middle lane', 6, 'lane', 'dacha cooperative lane', [[300,104],[400,101],[500,99]])
st('Dacha west lane', 6, 'lane', 'dacha cooperative lane', [[300,72],[300,104],[300,146.8]])
st('Dacha centre lane', 6, 'lane', 'dacha cooperative lane', [[400,70],[400,101],[400,136.2]])
st('Dacha east lane', 6, 'lane', 'dacha cooperative lane', [[500,68],[500,99],[500,130.6]])
st('Barracks road', 10, 'street', 'reserve compound access', [[944,110],[1012,110]])
bp['streets'] = streets
bp['city_districts'] = [
 {'id': 'ravine', 'name': 'Ravine garage cooperative', 'morphology': 'garages', 'polygon': [[427,614],[458,612],[464,745],[430,745]]},
 {'id': 'hillside', 'name': 'Southern hillside private sector', 'morphology': 'private', 'polygon': [[276,612],[560,598],[562,748],[320,748],[320,648],[276,642]]},
 {'id': 'centre', 'name': 'Historic centre', 'morphology': 'perimeter', 'polygon': [[198,322],[300,318],[432,322],[432,400],[440,520],[470,558],[458,612],[270,606],[200,598],[190,410]]},
 {'id': 'green', 'name': 'West insertion green', 'morphology': 'green', 'polygon': [[198,598],[276,610],[276,642],[320,648],[320,768],[198,768]]},
 {'id': 'port', 'name': 'Freight harbor estate', 'morphology': 'port', 'polygon': [[495,330],[700,326],[800,312],[862,290],[870,300],[813,342],[813,546],[700,576],[560,602],[490,565],[485,460],[500,390]]},
 {'id': 'micro', 'name': 'Eastern bayhead microdistrict', 'morphology': 'superblock', 'polygon': [[813,342],[870,300],[880,242],[1024,242],[1024,548],[950,548],[880,529],[813,548]]},
 {'id': 'village', 'name': 'Vineyard village and farm belt', 'morphology': 'village', 'polygon': [[562,602],[700,578],[880,533],[1024,556],[1024,768],[562,768]]},
 {'id': 'reserve', 'name': 'Northeast barracks reserve', 'morphology': 'compound', 'polygon': [[912,20],[1024,20],[1024,242],[925,242]]},
 {'id': 'north', 'name': 'North side settlement', 'morphology': 'north', 'polygon': [[600,60],[912,60],[925,242],[872,250],[830,225],[730,205],[590,190]]},
 {'id': 'dacha', 'name': 'Headland dacha cooperative', 'morphology': 'dacha', 'polygon': [[288,58],[512,56],[512,134],[450,132],[330,146],[288,150]]},
 {'id': 'headland', 'name': 'Battery headland', 'morphology': 'open', 'polygon': [[185,0],[912,0],[912,60],[600,60],[590,190],[300,175],[160,190],[205,100]]},
]
bp['open_spaces'] = [
 {'name': 'Cathedral square', 'kind': 'square', 'polygon': [[316,438],[376,438],[378,481],[316,481]]},
 {'name': 'Cathedral close', 'kind': 'cathedral_close', 'polygon': [[330,404],[366,404],[366,438],[330,438]]},
 {'name': 'Hill garden west', 'kind': 'hill_park', 'polygon': [[302,404],[330,404],[330,438],[316,438],[316,484],[302,504]]},
 {'name': 'Hill garden south', 'kind': 'hill_park', 'polygon': [[316,481],[378,481],[380,486],[364,486],[364,504],[316,504]]},
 {'name': 'Harbor approach plaza', 'kind': 'square', 'polygon': [[326,347],[358,347],[356,362],[330,362]]},
 {'name': 'Seafront garden', 'kind': 'seafront', 'polygon': [[214,331],[288,327],[288,334],[214,337]]},
 {'name': 'Ravine allotments', 'kind': 'ravine', 'polygon': [[426,650],[436,650],[438,720],[428,720]]},
 {'name': 'Ravine east slope', 'kind': 'ravine', 'polygon': [[452,700],[462,700],[464,742],[456,742]]},
 {'name': 'Cemetery', 'kind': 'cemetery', 'polygon': [[212,648],[262,648],[262,728],[214,728]]},
 {'name': 'Quarry scrub', 'kind': 'scrub', 'polygon': [[214,736],[300,736],[300,764],[214,764]]},
 {'name': 'Tank farm', 'kind': 'tank_farm', 'polygon': [[768,476],[800,476],[800,536],[768,536]]},
 {'name': 'Container yard', 'kind': 'stockyard', 'polygon': [[640,478],[690,478],[690,566],[640,566]]},
 {'name': 'Parade ground', 'kind': 'parade', 'polygon': [[976,118],[1016,118],[1016,160],[976,160]]},
 {'name': 'Vineyard north A', 'kind': 'vineyard', 'polygon': [[664,592],[736,582],[736,640],[664,646]]},
 {'name': 'Vineyard north B', 'kind': 'vineyard', 'polygon': [[752,572],[781,566],[781,640],[752,640]]},
 {'name': 'Vineyard north C', 'kind': 'vineyard', 'polygon': [[826,574],[878,562],[878,634],[826,634]]},
 {'name': 'Vineyard south A', 'kind': 'vineyard', 'polygon': [[575,736],[690,736],[690,762],[575,762]]},
 {'name': 'Vineyard south B', 'kind': 'vineyard', 'polygon': [[705,736],[835,736],[835,762],[705,762]]},
 {'name': 'Ploughed field', 'kind': 'field', 'polygon': [[600,612],[660,612],[660,640],[600,640]]},
 {'name': 'Coop yard', 'kind': 'field', 'polygon': [[905,700],[960,700],[960,740],[905,740]]},
 {'name': 'Headland pines', 'kind': 'headland', 'polygon': [[250,30],[520,30],[520,52],[284,54],[284,150],[262,150],[250,145]]},
 {'name': 'Battery point', 'kind': 'headland', 'polygon': [[200,105],[255,105],[262,170],[205,172]]},
 {'name': 'North pines', 'kind': 'headland', 'polygon': [[610,30],[905,30],[905,62],[610,62]]},
]
L = []
def lm(design, pos, yaw, size, district, **kw):
    d = {'design': design, 'position': pos, 'rotation_degrees': yaw, 'source_size': size, 'district': district}; d.update(kw); L.append(d)
lm('cathedral', [348,421], 180, [22,30], 'centre')
lm('colonnade_landing', [300,328.5], 180, [22,9], 'centre', street='Primorsky boulevard')
lm('civic_hall', [346,494], 180, [32,18], 'centre', floors=3, street='Hill ring south')
lm('market_hall', [318,582], 180, [30,18], 'centre', street='Bayhead ring')
lm('point_tower', [948,312], 0, [16,16], 'micro', floors=13)
lm('fort_ruin', [228,140], 0, [30,30], 'headland')
lm('petrol_station', [291,623.5], 90, [18,12], 'green', street='Peninsula spine')
lm('slipway', [828,318], 180, [36,12], 'port')
lm('slipway', [503,500], -90, [36,12], 'port')
lm('port_admin', [718,528], 90, [26,12], 'port', floors=4, street='Freight arterial')
lm('gatehouse', [713,549], 90, [6,4.5], 'port', street='Freight arterial')
lm('barracks', [984,70], 90, [40,12], 'reserve')
lm('barracks', [1004,70], 90, [40,12], 'reserve')
lm('barracks', [994,175], 0, [40,12], 'reserve')
lm('workshop_hall', [994,204], 0, [36,16], 'reserve')
lm('gatehouse', [968,98], 180, [6,4.5], 'reserve', street='Barracks road')
lm('panel_5', [735,150], 0, [40,9.5], 'north')
lm('panel_5', [777,140], 0, [36,9.5], 'north')
lm('panel_5', [775,165], 0, [36,9.5], 'north')
lm('shop_pavilion', [735,195], 0, [18,11], 'north', street='North shore road')
lm('coop_shed', [880,712], 0, [36,16], 'village')
lm('barn_long', [884,740], 0, [30,11], 'village')
bp['landmarks'] = L
bp['crane_rails'] = [{'points': [[572,340.5],[640,339],[698,336]], 'spacing': 30}, {'points': [[732,334],[798,322]], 'spacing': 28}]
bp['port_fence'] = [[[566,586],[628,575]], [[636,573],[696,563]], [[704,561],[756,548]], [[764,546],[806,535]]]
bp['compound_fence'] = [[[970,40],[1018,40]], [[1018,40],[1018,214]], [[970,214],[1018,214]], [[970,40],[970,104]], [[970,116],[970,214]]]
bp['decor'] = [
 {'id': 'fountain.round', 'position': [364,447], 'context': 'cathedral square fountain'},
 {'id': 'monument.statue', 'position': [328,474], 'context': 'cathedral square monument'},
 {'id': 'monument.column', 'position': [314,360], 'context': 'harbor approach memorial column'},
 {'id': 'kiosk.market_stall', 'position': [296,566], 'context': 'market stalls beside market hall'},
 {'id': 'kiosk.market_stall', 'position': [342,566], 'context': 'market stalls beside market hall'},
 {'id': 'water_tower.farm', 'position': [915,712], 'context': 'cooperative water tower'},
 {'id': 'antenna.panel_mast', 'position': [1010,117], 'context': 'reserve signals mast', 'road_margin': 0.3},
 {'id': 'antenna.tripod', 'position': [978,104], 'context': 'reserve signals antenna'},
 {'id': 'checkpoint_gate.boom', 'position': [962,101.5], 'rotation_degrees': 0, 'context': 'compound checkpoint barrier raised beside the gate'},
 {'id': 'small_boat.rowing', 'position': [575,325], 'rotation_degrees': 90, 'domain': 'sea', 'context': 'civilian boats moored beside freight quay'},
 {'id': 'small_boat.rowing', 'position': [600,323], 'rotation_degrees': 90, 'domain': 'sea', 'context': 'civilian boats moored beside freight quay'},
 {'id': 'small_boat.outboard', 'position': [752,216], 'rotation_degrees': 90, 'domain': 'sea', 'context': 'boats at north side ferry landing'},
 {'id': 'small_boat.rowing', 'position': [768,218], 'rotation_degrees': 90, 'domain': 'sea', 'context': 'boats at north side ferry landing'},
 {'id': 'barge.flat_deck', 'position': [765,298], 'rotation_degrees': 90, 'domain': 'sea', 'context': 'moored freight lighter outside navigable centerline'},
 {'id': 'bus_stop.glazed_shelter', 'position': [748,190], 'context': 'ferry landing bus stop'},
]
bp['quay_walls'] = [[[300,320],[430,325]], [[560,335],[700,330]]]
bp['damage_front'] = [[640,365],[680,372],[750,372],[790,360],[700,400],[705,440]]
bp['layout_validation'] = {'primary_road_min_width': 16, 'building_road_clearance': 0.5, 'collision_excess_max': 1.0, 'collision_rects_max': 6,
  'setback_limits': {'perimeter': [0.3, 5.5], 'private': [0.3, 8.0], 'north': [0.3, 8.0], 'village': [0.3, 9.5], 'garages': [0.5, 4.5], 'port': [2.0, 9.0], 'superblock': [3.0, 12.0], 'green': [0.3, 6.0], 'compound': [0.3, 8.0], 'dacha': [0.3, 6.0],
                     'garage_row': [0.5, 4.5], 'gatehouse': [0.3, 5.0], 'shop_pavilion': [3.0, 12.0]},
  'boat_support_point': [340,316], 'sea_route_points': [[80,640],[100,400],[170,270],[340,265],[670,260]],
  'land_route_points': [[280,680],[270,600],[430,610],[560,595],[700,570],[880,525],[930,400],[920,250],[940,120]]}
bp['footpaths'] = [[[316,460],[306,460],[299,460]], [[345,481],[345,504]], [[434,645],[436,700],[440,722]], [[700,655],[700,600]]]
bp.pop('courtyards', None)
bp['prop_plan'] = {'centre': 'plane trees and double lamps on boulevards, square furniture, courtyard trees/sheds/laundry/cars',
  'hillside': 'stone yard walls with gates, pergolas, fruit trees, greenhouses and sheds; garages and allotments in the ravine',
  'port': 'portal cranes on quay rails, sidings with boxcars, containers, tank farm, concrete perimeter fence',
  'microdistrict': 'playgrounds, parking bays, heat pipes, dumpsters, acacias, bus stops', 'village': 'trellis rows, poplar windbreaks, haystacks, tractors',
  'waterfront': 'quay walls, bollards and moored civilian boats in water'}
bp['schema_version'] = 2
bp['proposal']['assumptions'] = [
 "One world unit is one gameplay distance unit, not a survey scale; building footprints are RTS-compressed to about 0.6x real, storey 2.7 u.",
 "Land forces cross around the closed south-inlet head and the eastern main-bay head; there are no underwater roads or invisible bridges.",
 "All normal play uses field operations with one supply pool and engineer support; old scenarios remain hidden fixtures.",
 "Navigation cells are 4 units and fog cells are 8 units; primary corridors are 16-20 units wide, town streets 10-12, private lanes and tracks 6-8.",
 "Rotations use Godot Y yaw: local x,z points rotate clockwise by rotation_degrees (world = centre + (x cos a - z sin a, x sin a + z cos a), a = -yaw). Street face is local -z.",
 "Collision: architecture entries are independent of blocks; each carries collision [first,count] into blocks. A rotated footprint is covered by <=6 axis-aligned rects with <=1 u excess; where a street is too oblique for that, the building yaw is snapped toward the axis (a slightly stepped frontage, as on real slopes).",
 "Morphology note: each district is one period's rule set. Historic centre = rounded ring street around the cathedral hill with radials, waterfront boulevard and inlet embankment; perimeter blocks with corner buildings, continuous 0.8 u (side street) or 3.2 u (tree-lined main street) building lines and open courtyards. Hillside = contour lanes, walled private plots 11-21 x 13-30 with the house on a front corner, outbuildings and gardens behind, garages in the ravine. Microdistrict = superblocks between arterials with slab rows on the block axis, 18-22 u yards, a school or kindergarten, shops on the arterial and garages on the edge. Port = grid estate with transit sheds parallel to the quay, siding between shed and quay road, crane rails on the apron, workshops and a tank farm behind. Farm belt = linear village on one lane with barns behind and vineyard blocks edged by poplars. North side = private houses, three panel_5 near the ferry landing, a dacha cooperative grid and the battery ruin on the headland.",
 "Squares, parks, the cemetery, vineyards, fields, the tank farm, stockyard and parade ground are deliberate open space, not missing scatter. Damage is clustered within ~60 u of objectives and the freight front only.",
]
json.dump(bp, open(path, 'w'), indent=1)
print('streets', len(streets))
