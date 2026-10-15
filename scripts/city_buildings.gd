class_name CityBuildings
extends RefCounted

# Dispatcher for parametric harbor-city building families (docs/harbor-city-design.md).
# Builders: scripts/city_buildings_urban.gd and scripts/city_buildings_works.gd,
# each exposing build(art,parent:Node3D,spec:Dictionary)->void. Local frame is
# centred, x along frontage, street face at -z; solids stay inside source_size.
const DESIGNS:={
	"classic_row":{"builder":"urban","w":[10,24],"d":[9,12],"floors":[2,4]},
	"classic_corner":{"builder":"urban","w":[14,22],"d":[14,22],"floors":[3,4]},
	"stalin_block":{"builder":"urban","w":[36,56],"d":[11,14],"floors":[4,5]},
	"civic_hall":{"builder":"urban","w":[28,40],"d":[18,24],"floors":[2,3]},
	"cathedral":{"builder":"urban","w":[18,24],"d":[26,34],"floors":[1,1]},
	"colonnade_landing":{"builder":"urban","w":[20,26],"d":[8,10],"floors":[1,1]},
	"market_hall":{"builder":"urban","w":[26,34],"d":[16,20],"floors":[1,1]},
	"panel_5":{"builder":"urban","w":[36,48],"d":[9,10],"floors":[5,5]},
	"panel_9":{"builder":"urban","w":[48,64],"d":[10,11],"floors":[9,9]},
	"point_tower":{"builder":"urban","w":[15,18],"d":[15,18],"floors":[12,14]},
	"school":{"builder":"urban","w":[36,44],"d":[24,30],"floors":[3,3]},
	"kindergarten":{"builder":"urban","w":[22,28],"d":[16,20],"floors":[2,2]},
	"shop_pavilion":{"builder":"urban","w":[16,28],"d":[10,14],"floors":[1,2]},
	"stone_house":{"builder":"works","w":[7,11],"d":[6,9],"floors":[1,2]},
	"outbuilding":{"builder":"works","w":[3,6],"d":[3,5],"floors":[1,1]},
	"dacha_hut":{"builder":"works","w":[4,6],"d":[4,5],"floors":[1,1]},
	"garage_row":{"builder":"works","w":[19.2,76.8],"d":[6,7],"floors":[1,1]},
	"transit_shed":{"builder":"works","w":[50,80],"d":[18,24],"floors":[1,1]},
	"workshop_hall":{"builder":"works","w":[28,50],"d":[16,22],"floors":[1,1]},
	"port_admin":{"builder":"works","w":[22,30],"d":[11,13],"floors":[3,4]},
	"gatehouse":{"builder":"works","w":[5,7],"d":[4,5],"floors":[1,1]},
	"slipway":{"builder":"works","w":[30,44],"d":[10,14],"floors":[1,1]},
	"barn_long":{"builder":"works","w":[24,36],"d":[10,12],"floors":[1,1]},
	"coop_shed":{"builder":"works","w":[30,44],"d":[14,18],"floors":[1,1]},
	"petrol_station":{"builder":"works","w":[16,20],"d":[10,14],"floors":[1,1]},
	"barracks":{"builder":"works","w":[36,48],"d":[11,13],"floors":[3,3]},
	"fort_ruin":{"builder":"works","w":[26,34],"d":[26,34],"floors":[1,1]},
}
const BUILDERS:={"urban":"res://scripts/city_buildings_urban.gd","works":"res://scripts/city_buildings_works.gd"}

# Families whose height is not storey-driven (domes, single tall halls).
const HEIGHT_CAPS:={"cathedral":24.0,"colonnade_landing":8.0,"market_hall":10.0,"transit_shed":12.0,"workshop_hall":12.0,"coop_shed":10.0,"barn_long":9.0,"slipway":9.0}

# Maximum allowed rendered height for a family at a given floor count.
static func height_cap(design:String,floors:int)->float:
	return float(HEIGHT_CAPS.get(design,floors*2.7+4.0))

static func handles(design:String)->bool:
	return DESIGNS.has(design)

# Fill defaults so builders always receive a complete spec.
static func normalized(spec:Dictionary)->Dictionary:
	var result:=spec.duplicate(true)
	var row:Dictionary=DESIGNS[spec.design]
	if not result.has("source_size"):result["source_size"]=[row.w[0],row.d[0]]
	result["floors"]=int(result.get("floors",row.floors[0]))
	result["variant"]=int(result.get("variant",0))
	result["palette"]=int(result.get("palette",0))
	result["damage"]=int(result.get("damage",0))
	result["seed"]=int(result.get("seed",0))
	return result

static func build_spec(art,parent:Node3D,spec:Dictionary)->bool:
	if not handles(str(spec.get("design",""))):return false
	var builder=load(BUILDERS[DESIGNS[spec.design].builder])
	if builder==null:return false
	builder.build(art,parent,normalized(spec))
	return true

# Asset-library adapter: one mid-range sample per family for the gallery.
static func specs()->Array:
	var result:Array=[]
	for design in DESIGNS:
		var row:Dictionary=DESIGNS[design]
		var w:float=(row.w[0]+row.w[1])/2.0;var d:float=(row.d[0]+row.d[1])/2.0
		result.append({"kind":design,"variant":"city","category":"architecture","label":design.replace("_"," ").capitalize(),"footprint":[-w/2,-d/2,w,d],"height":height_cap(design,int(row.floors[1])),"placement":["city_plot"],"collision":"solid","cover":false,"description":"Parametric harbor-city family; see docs/harbor-city-design.md."})
	return result

static func sample(design:String)->Dictionary:
	var row:Dictionary=DESIGNS[design]
	return {"design":design,"source_size":[(row.w[0]+row.w[1])/2.0,(row.d[0]+row.d[1])/2.0],"floors":row.floors[1]}

static func build(art,parent:Node3D,kind:String,_variant:String)->Node3D:
	if not handles(kind):return null
	var model:=Node3D.new();parent.add_child(model)
	build_spec(art,model,sample(kind))
	art.bake_model(model)
	return model
