extends SceneTree
const L=preload("res://scripts/asset_library.gd")
var count:=0
var failures:=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:
	var world:=Rect2(0,0,100,100);var p:=Vector2(20,20)
	var drain:="drain_outfall.pipe_headwall"
	check(not L.placement_issues(drain,p,0,world,[],"land").is_empty(),"generic land cannot accept outfall")
	var ctx:={"tags":["ditch_end"],"drainage_zones":[Rect2(18,22,4,5)]}
	check(L.placement_issues(drain,p,0,world,[],"land",true,ctx).is_empty(),"outlet meets receiving ditch")
	check(not L.placement_issues(drain,p,PI,world,[],"land",true,ctx).is_empty(),"reversed discharge rejected")
	var shelter:="bus_stop.glazed_shelter"
	ctx={"tags":[L.find(shelter).placement[0]],"access_zones":[Rect2(18,20.5,4,4)]}
	check(L.placement_issues(shelter,p,0,world,[],"land",true,ctx).is_empty(),"shelter entrance connects to footway")
	check(not L.placement_issues(shelter,p,PI,world,[],"land",true,ctx).is_empty(),"shelter facing away rejected")
	check(not L.placement_issues(shelter,p,0,world,[Rect2(19.5,22,1,1)],"land",true,ctx).is_empty(),"blocked entry path rejected")
	var cable:="overhead_cable.three_phase_span"
	var spec:=L.find(cable)
	check(spec.placement_contract.collision_policy=="whole_footprint_non_traversable_pending_part_integration","pole assembly never silently traversable")
	ctx={"tags":[spec.placement[0]]}
	check(L.placement_issues(cable,p,0,world,[],"land",false,ctx).is_empty(),"self-supported span does not require imaginary external support")
	check(not L.placement_issues(cable,p,0,world,[Rect2(19,19,2,2)],"land",true,ctx).is_empty(),"conservative span envelope reserves corridor")
	print("ASSET PLACEMENT: ",count," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
