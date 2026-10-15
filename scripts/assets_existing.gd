class_name ExistingEnvironmentAssets
extends RefCounted
const Props=preload("res://scripts/roadside_props.gd")
const Kit=preload("res://scripts/parcel_kit.gd")
static var cache:Array=[]
static func specs()->Array:
	if not cache.is_empty():return cache.duplicate(true)
	for kind in Kit.INTACT+Kit.RUINS:
		var width:=10.0 if kind=="warehouse" else 8.0
		cache.append({"kind":kind,"variant":"parcel","category":"architecture","label":str(kind).replace("_"," ").capitalize(),"footprint":[-width/2,-4,width,8],"height":10.5,"placement":["street_frontage","solid_parcel"],"collision":"solid","cover":false,"entrance":[0,-4],"description":"Existing authored building family shown in an 8×8 parcel; north entrance orientation. Whole parcel remains solid."})
	for kind in ["sedan","service","lamp","pallets","drums","reel","cabinet","bench","bin","bollard","quay_bay"]:
		var f:Rect2=Props.local_footprint(kind)
		cache.append({"kind":kind,"variant":"existing","category":"waterfront" if kind in ["bollard","quay_bay"] else ("industry" if kind in ["pallets","drums","reel","cabinet"] else "town_life"),"label":str(kind).replace("_"," ").capitalize(),"footprint":[f.position.x,f.position.y,f.size.x,f.size.y],"height":4.0 if kind=="lamp" else 2.5,"placement":["shared_roadside_footprint"],"collision":"solid","cover":false,"description":"Existing roadside model; placement must reserve its full footprint."})
	return cache.duplicate(true)
static func build(art,parent:Node3D,kind:String,variant:String)->Node3D:
	if not specs().any(func(s):return s.kind==kind and s.variant==variant):return null
	var model:=Node3D.new();parent.add_child(model)
	var rect:=Rect2(-5,-4,10,8) if kind=="warehouse" else Rect2(-4,-4,8,8)
	if kind in Kit.INTACT:
		preload("res://scripts/architectural_block.gd").build(art,model,rect,0,{"design":kind,"facing":"north"})
	elif kind in Kit.RUINS:
		preload("res://scripts/ruined_building.gd").build(art,model,rect,0,{"design":kind,"facing":"north"})
	elif kind=="lamp":Props._lamp(art,model)
	elif kind=="quay_bay":Props._quay_bay(art,model,12.0,Color("929183"))
	elif kind in ["sedan","service"]:Props._car(art,model,kind=="service",Color("656c58"))
	else:Props._furniture(art,model,kind,Color("6b6e57"))
	art.bake_model(model)
	return model
