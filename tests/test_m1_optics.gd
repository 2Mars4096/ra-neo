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

func per_body_smoke_acquisition()->void:
	var sim=Sim.new(false,0)
	sim.scenario.autonomy=true
	var observer:Dictionary=sim.spawn("rifle",0,Vector2(20,60))
	var target:Dictionary=sim.spawn("rifle",1,Vector2(30,60))
	target.members[0].pos=Vector2(30,59);target.members[1].pos=Vector2(30,60)
	var exposed:Dictionary=target.members[2]
	exposed.pos=Vector2(30,65)
	sim.throwables.smoke.append({"id":1,"pos":Vector3(25,0,60),"radius":1.0,"height":4.0,"born":0.0,"expires":18.0,"team":1})
	sim.Throwables._smoke_changed(sim)
	check(not sim.smoke_clear(observer.pos,target.pos) and sim.smoke_clear(observer.pos,exposed.pos),"a cloud hides the squad anchor while a living member remains exposed beside it")
	sim.update_visibility()
	check(target.seen_by[0] and sim.contact_known(observer,target),"the exposed living member permits current acquisition despite the smoke-hidden anchor")
	check(sim.can_fire(observer,target),"current observation and actual per-member weapon rays agree on the exposed soldier")
	var health:float=exposed.hp
	exposed.hp=0.0
	sim.update_visibility()
	check(not target.seen_by[0],"a dead exposed body cannot reveal the living members behind smoke")
	exposed.hp=health;exposed.pos=Vector2(30,61)
	sim.update_visibility()
	check(not target.seen_by[0],"a section stays hidden when every living member is screened")
	target.pos=Vector2(30,54)
	check(sim.smoke_clear(observer.pos,target.pos),"an empty squad anchor can be outside the screened body rays")
	sim.update_visibility()
	check(not target.seen_by[0],"a clear empty anchor cannot reveal screened living members")
	target.pos=Vector2(30,60);exposed.pos=Vector2(200,65)
	sim.update_visibility()
	check(not target.seen_by[0],"a clear member beyond the observer's sight range cannot reveal screened teammates")
	exposed.pos=Vector2(30,65)
	var wall:=Rect2(24,61.2,2,6)
	sim.terrain.dynamic_blocks.append(wall)
	sim.update_visibility()
	check(not target.seen_by[0],"a member's smoke-free ray still requires physical wall clearance")
	sim.terrain.dynamic_blocks.erase(wall)
	sim.scenario.jam_radius=100.0;sim.objectives[0].owner=1
	check(sim.comms_blocked(observer),"local observation fixture has no shared radio link")
	check(sim.contact_known(observer,target),"jammed local observation uses the exposed member rather than the screened anchor")
	sim.scenario.jam_radius=0.0
	sim.update_visibility()
	var mover:Dictionary=observer.members[0]
	check(sim.Coordination.begin_bound(observer,mover,sim,target,{"pos":Vector2(22,62),"screened":false}),"an actual clear firing lane to the exposed member can support a teammate")
	mover.cover_phase="SEEKING"
	var coverer:Dictionary=sim.Infantry.member_by_id(observer,str(mover.get("covered_by",observer.members[1].member_id)))
	for peer in observer.members:
		if peer!=coverer:peer.cooldown=100.0
	for _tick in range(60):
		sim.time+=1.0/30.0
		coverer.cooldown-=1.0/30.0
		sim.Coordination.review(observer,sim)
		sim.infantry_combat(observer,1.0/30.0,[target])
		if float(coverer.last_shot)>=0.0:break
	check(float(coverer.last_shot)>=0.0 and coverer.rounds==5 and coverer.aim_member==exposed.index,"the credited coverer spends a rifle round at the actual exposed member")
	check(sim.events.any(func(event):return event.get("type","")=="shot" and event.get("kind","")=="rifle" and event.get("from",Vector2.INF)==coverer.pos),"per-body smoke acquisition reaches the authoritative firing executor")

func smoke_releases_local_cover()->void:
	var sim=Sim.new(false,0)
	sim.scenario.autonomy=true
	var u:Dictionary=sim.spawn("rifle",0,Vector2(20,60))
	var target:Dictionary=sim.spawn("rifle",1,Vector2(30,60))
	var spotter:Dictionary=sim.spawn("rifle",0,Vector2(30,70))
	sim.update_visibility()
	var mover:Dictionary=u.members[0]
	check(sim.Coordination.begin_bound(u,mover,sim,target,{"pos":Vector2(22,62),"screened":false}),"local covering role starts before smoke deployment")
	mover.cover_phase="SEEKING";mover.cover_goal=Vector2(22,62);mover.cover_path=[mover.cover_goal]
	var partner:Dictionary=sim.Infantry.member_by_id(u,str(mover.get("covered_by",u.members[1].member_id)))
	sim.throwables.smoke.append({"id":1,"pos":Vector3(25,0,60),"radius":2.0,"height":4.0,"born":0.0,"expires":18.0,"team":1})
	sim.Throwables._smoke_changed(sim);sim.update_visibility()
	check(sim.contact_known(u,target) and sim.relief_sight_clear(spotter,target),"another observer retains the enemy contact around the cloud")
	check(not sim.can_fire(u,target),"shared knowledge does not bypass a local smoke-blocked firing lane")
	sim.Coordination.review(u,sim)
	check(not mover.has("covered_by") and not partner.has("cover_for"),"smoke releases both sides of the unusable covering role")
	check(sim.actions.active(u,"member:%s:support"%partner.member_id).is_empty(),"smoke releases the covering action channel")
	check(mover.cover_phase=="SEEKING" and mover.cover_path==[Vector2(22,62)],"loss of optical support preserves the mover's already validated shelter route")

func spread_visibility_parity()->void:
	for wide in [false,true]:
		var sim=Sim.new(false,0)
		var observer:Dictionary=sim.spawn("rifle",0,Vector2(20,60))
		var target:Dictionary=sim.spawn("rifle",1,Vector2(30,60))
		target.pos=Vector2(45,60) if wide else Vector2(40,63)
		for member in target.members:member.pos=target.pos
		target.members[2].pos=Vector2(37,65)
		var reach:float=float(sim.definitions.rifle.sight)*float(sim.weather.sight_scale)
		check(observer.pos.distance_to(target.pos)>reach and observer.pos.distance_to(target.members[2].pos)<reach,"spread fixture has an out-of-sight anchor and an in-range body: "+str(wide))
		check((sim.section_offset(target)>sim.SPREAD_NARROW)==wide and (not wide or observer.pos.distance_to(target.pos)>reach+sim.SPREAD_NARROW+sim.SPREAD_SLACK),"fixture exercises the intended narrow/wide spatial path: "+str(wide))
		sim.throwables.smoke.append({"id":1,"pos":Vector3(25,0,60),"radius":1.0,"height":4.0,"born":0.0,"expires":18.0,"team":1})
		sim.Throwables._smoke_changed(sim)
		sim.use_spatial_targeting=false;sim.update_visibility()
		var exhaustive:bool=target.seen_by[0]
		check(exhaustive,"exhaustive observation admits the actually visible member within sight: "+str(wide))
		sim.use_spatial_targeting=true;sim.update_visibility()
		check(target.seen_by[0]==exhaustive and target.seen_by[0],"indexed observation preserves exposed members beyond the anchor search radius: "+str(wide))

func _init()->void:
	aircraft_target("rifle")
	aircraft_target("tank")
	aircraft_fog_cache()
	per_body_smoke_acquisition()
	smoke_releases_local_cover()
	spread_visibility_parity()
	print("M1 OPTICS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
