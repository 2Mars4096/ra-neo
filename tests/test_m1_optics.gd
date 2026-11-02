extends SceneTree

# Smoke uses actual world-height optical rays even on a flat map. Aircraft
# targeting must agree with that geometry for both sections and single bodies.
const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func aircraft_target(kind:String)->void:
	var sim=Sim.new(false,0)
	var aircraft:Dictionary=sim.spawn("helo",0,Vector2(20,60))
	var target:Dictionary=sim.spawn(kind,1,Vector2(36,60))
	var altitude:float=sim.unit_altitude(aircraft)
	check(not sim.terrain.has_elevation(),"fixture uses the flat optical path: "+kind)
	check(sim.weapon_reaches(aircraft.kind,aircraft.pos,target),"aircraft reaches the unobscured target: "+kind)
	sim.throwables.smoke.append({"id":1,"pos":Vector3(24,0,60),"radius":2.0,"height":4.0,"born":0.0,"expires":18.0,"team":1,"visible":true})
	check(sim.smoke_clear(aircraft.pos,target.pos,altitude,1.6),"cruise-altitude ray passes above the low cloud: "+kind)
	check(not sim.smoke_clear(aircraft.pos,target.pos,3.0,1.6),"low ray crosses the same physical cloud: "+kind)
	check(sim.weapon_reaches(aircraft.kind,aircraft.pos,target,sim.SOLDIER_CHECKS,altitude),"height-aware aircraft acquisition sees above smoke: "+kind)
	check(sim.weapon_reaches(aircraft.kind,aircraft.pos,target),"default aircraft height also sees above smoke: "+kind)
	aircraft["altitude"]=3.0
	check(not sim.weapon_reaches(aircraft.kind,aircraft.pos,target,sim.SOLDIER_CHECKS,sim.unit_altitude(aircraft)),"actual low flight height cannot inherit cruise visibility: "+kind)

	# A supplied altitude can also be higher than the definition (skyline climb).
	# This taller cloud intersects the nominal cruise ray but not the real ray.
	var raised=Sim.new(false,0)
	var high:Dictionary=raised.spawn("helo",0,Vector2(20,60))
	var close:Dictionary=raised.spawn(kind,1,Vector2(30,60))
	high["altitude"]=14.0
	raised.throwables.smoke.append({"id":1,"pos":Vector3(22,0,60),"radius":0.75,"height":10.0,"born":0.0,"expires":18.0,"team":1,"visible":true})
	check(raised.smoke_clear(high.pos,close.pos,raised.unit_altitude(high),1.6) and not raised.smoke_clear(high.pos,close.pos,float(raised.definitions.helo.altitude),1.6),"climbing above a tall cloud differs from nominal cruise: "+kind)
	check(raised.weapon_reaches(high.kind,high.pos,close,raised.SOLDIER_CHECKS,raised.unit_altitude(high)),"acquisition preserves explicit higher aircraft altitude: "+kind)

func aircraft_fog_cache()->void:
	var sim=Sim.new(false,0)
	var aircraft:Dictionary=sim.spawn("helo",0,Vector2(20,60))
	var tile:Vector2i=sim.terrain.cell(Vector2(36,60))
	var point:Vector2=sim.terrain.center(tile)
	var source:Vector2=sim.terrain.center(sim.terrain.cell(aircraft.pos))
	sim.throwables.smoke.append({"id":1,"pos":Vector3(24,0,60),"radius":2.0,"height":4.0,"born":0.0,"expires":18.0,"team":1,"visible":true})
	sim.Throwables._smoke_changed(sim)
	check(not sim.terrain.has_elevation(),"fog cache fixture has flat terrain and a finite-height cloud")
	check(sim.relief_fog_clear(aircraft,source,point),"cruise-height fog ray clears the cloud")
	sim.update_visibility()
	check(sim.visible_cells.has(tile),"cruise-height observer reveals the cell across smoke")
	# Change only altitude: no movement to a new cell or smoke revision may
	# invalidate the cache on this path. Fog must agree with the current ray.
	aircraft["altitude"]=3.0
	check(not sim.relief_fog_clear(aircraft,source,point),"lowered observer's actual fog ray crosses smoke")
	sim.update_visibility()
	check(not sim.visible_cells.has(tile),"descending in the same flat-map cell cannot reuse clear high-altitude fog")
	check(sim.explored.has(tile),"loss of current sight retains previously explored terrain")
	aircraft["altitude"]=9.0
	sim.update_visibility()
	check(sim.visible_cells.has(tile),"ascending in the same cell restores sight above the cloud")
	# Same-cell observers also share the per-update deduplication key. A low
	# aircraft visited first must not prevent its higher teammate contributing.
	aircraft["altitude"]=3.0
	var high:Dictionary=sim.spawn("helo",0,Vector2(12,52))
	high.pos=aircraft.pos+Vector2(0.25,0.25)
	high["altitude"]=9.0
	check(sim.terrain.cell(high.pos)==sim.terrain.cell(aircraft.pos),"different-height observers share the same fog cell")
	sim.update_visibility()
	check(sim.visible_cells.has(tile),"higher same-kind observer contributes even when the low observer is processed first")
	high.hp=0.0
	sim.update_visibility()
	check(not sim.visible_cells.has(tile),"loss of the high observer leaves only the low observer's smoke-blocked sight")

func _init()->void:
	aircraft_target("rifle")
	aircraft_target("tank")
	aircraft_fog_cache()
	print("M1 OPTICS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
