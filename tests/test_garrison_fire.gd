extends SceneTree
# Garrisons fire from the windows (black_sea_harbor, L-shaped block): riflemen
# keep shooting at enemy infantry in range on every face, not just the doorway
# side; rifles ignore tanks (rifle vs tank effectiveness 0); a garrisoned
# Javelin team launches at a tank from the building; the soldiers' states show
# the fight.
const Sim=preload("res://scripts/simulation.gd")
const Garrison=preload("res://scripts/garrison.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

const SIDES:=[Vector2.RIGHT,Vector2.UP,Vector2.LEFT,Vector2.DOWN]
const GAP:=9.0  # enemy distance from the wall: inside rifle range from a window

# Open ground `GAP` off the building's face in `dir`, with a clear line from the window line.
func side_spot(sim,building:Dictionary,dir:Vector2)->Vector2:
	var b:Rect2=building.bounds
	var c:Vector2=b.get_center()
	var edge:=Vector2(b.end.x if dir.x>0 else (b.position.x if dir.x<0 else c.x),b.end.y if dir.y>0 else (b.position.y if dir.y<0 else c.y))
	var p:Vector2=edge+dir*GAP
	if not sim.terrain.traversable(p,"land",2.65) or sim.terrain.is_water(p):return Vector2(-1,-1)
	if not sim.terrain.line_clear(edge+dir*0.7,p):return Vector2(-1,-1)
	return p

# An L-shaped (multi-part) block with a doorway and open ground on at least three faces.
func pick_building(sim)->Dictionary:
	for b in Garrison.index(sim).buildings:
		if b.rects.size()<2 or int(b.capacity)<2 or b.bounds.size.x<12 or b.bounds.size.y<12 or b.bounds.size.x>40 or b.bounds.size.y>40:continue
		var open:=SIDES.filter(func(dir):return side_spot(sim,b,dir).x>=0)
		if open.size()<3:continue
		if Garrison.entry_point(sim,b.id,b.bounds.get_center()).x<0:continue
		return b
	return {}

# Walk a fresh section in through the doorway (the real order path).
func garrison(sim,kind:String,building:Dictionary)->Dictionary:
	var door:=Garrison.entry_point(sim,building.id,building.bounds.get_center())
	var outward:Vector2=(door-building.bounds.get_center()).normalized()
	var squad:Dictionary=sim.spawn(kind,0,door+outward*5.0)
	if squad.is_empty() or Garrison.order(sim,[squad.id],building.id)!=1:return {}
	for i in 900:
		sim.tick(1.0/30)
		if Garrison.inside(squad):return squad
	return {}

func enemy(sim,kind:String,p:Vector2)->Dictionary:
	var e:Dictionary=sim.spawn(kind,1,p)
	if not e.is_empty():e.hold_command=true
	return e

func remove(sim,u:Dictionary)->void:
	for m in u.members:m.hp=0.0;m.wound=Sim.Infantry.KIA
	u.hp=0.0

# Runs `seconds`, counting the section's shots (a soldier's last_shot advancing)
# and which targets its soldiers picked.
func watch(sim,squad:Dictionary,seconds:float)->Dictionary:
	var last:={}
	for m in squad.members:last[m.index]=float(m.get("last_shot",-100.0))
	var result:={"shots":0,"targets":{},"states":{},"first":-1.0}
	for i in int(seconds*30.0):
		sim.tick(1.0/30)
		for m in squad.members:
			if m.hp<=0:continue
			if float(m.get("last_shot",-100.0))>float(last[m.index]):
				result.shots+=1;last[m.index]=m.last_shot
				if result.first<0:result.first=sim.time
			if int(m.target)>=0:result.targets[int(m.target)]=true
			result.states[str(m.state)]=true
	return result

func living(u:Dictionary)->int:
	return u.members.filter(func(m):return m.hp>0).size()

func rifle_case(index:int)->void:
	var sim=Sim.new(false,index)
	var building:=pick_building(sim)
	check(not building.is_empty(),"L-shaped block with open faces found")
	if building.is_empty():return
	var squad:=garrison(sim,"rifle",building)
	check(not squad.is_empty(),"rifle section garrisons the block")
	if squad.is_empty():return
	var door:Vector2=squad.garrison_door
	print("building %d bounds %s rects %d door %s" % [building.id,building.bounds,building.rects.size(),door])
	var off_door:=0
	var inflicted:=0.0
	for dir in SIDES:
		var p:=side_spot(sim,building,dir)
		if p.x<0:continue
		var e:Dictionary=enemy(sim,"rifle",p)
		if e.is_empty():continue
		var facing_door:bool=(door-building.bounds.get_center()).dot(dir)>0 and absf((door-building.bounds.get_center()).normalized().dot(dir))>0.7
		var hp0:float=e.hp
		var seen:=watch(sim,squad,10.0)
		var n:=living(squad)
		print("side %s%s: shots %d by %d soldiers, first at +%.1fs, enemy hp %.0f -> %.0f, states %s" % [dir,"(door)" if facing_door else "",seen.shots,n,seen.first-sim.time+10.0 if seen.first>0 else -1.0,hp0,e.hp,seen.states.keys()])
		check(seen.targets.has(e.id),"side %s: garrison targets the enemy section" % dir)
		# More shots than soldiers: they keep firing, not one round each.
		check(seen.shots>n,"side %s: windows keep firing (%d shots, %d soldiers)" % [dir,seen.shots,n])
		inflicted+=hp0-e.hp
		check(seen.states.has("CYCLING") or seen.states.has("ACQUIRING"),"side %s: soldiers show the fight (%s)" % [dir,seen.states.keys()])
		if not facing_door:off_door+=1
		remove(sim,e)
		for i in 30:sim.tick(1.0/30)
	# Hits on prone soldiers are ~12% a shot: judge casualties over all faces.
	check(inflicted>0.0,"enemy infantry takes casualties from the windows (%.0f hp)" % inflicted)
	check(off_door>=1,"an enemy off the doorway face was tested (%d)" % off_door)
	# Tanks: rifles do not waste fire on armour (rifle vs tank effectiveness is 0).
	check(not sim.effective_weapon("rifle","tank"),"rifle vs tank is ineffective")
	var spot:Vector2=Vector2(-1,-1)
	for dir in SIDES:
		spot=side_spot(sim,building,dir)
		if spot.x>=0:break
	var tank:Dictionary=enemy(sim,"tank",spot)
	check(not tank.is_empty(),"enemy tank placed")
	if tank.is_empty():return
	# Its gun stays silent: this case is about what the rifles pick, and HE
	# through the walls would end the garrison before the infantry arrive.
	tank.cooldown=1e9
	var tank_only:=watch(sim,squad,4.0)
	check(not tank_only.targets.has(tank.id) and tank_only.shots==0,"rifles hold fire at a lone tank (%d shots)" % tank_only.shots)
	# Infantry beside the tank (the reported street): rifles pick the soldiers.
	var rider:Dictionary=enemy(sim,"rifle",spot+(spot-building.bounds.get_center()).normalized().orthogonal()*4.0)
	if rider.is_empty():rider=enemy(sim,"rifle",spot)
	check(not rider.is_empty(),"enemy infantry placed beside the tank")
	if rider.is_empty():return
	var mixed:=watch(sim,squad,8.0)
	print("tank + infantry: shots %d, targets %s (tank %d, infantry %d)" % [mixed.shots,mixed.targets.keys(),tank.id,rider.id])
	check(not mixed.targets.has(tank.id),"rifles never target the tank")
	check(mixed.targets.has(rider.id) and mixed.shots>living(squad),"rifles fire at the infantry beside the tank (%d shots)" % mixed.shots)

func javelin_case(index:int)->void:
	var sim=Sim.new(false,index)
	var building:=pick_building(sim)
	if building.is_empty():check(false,"javelin fixture building");return
	var squad:=garrison(sim,"atgm",building)
	check(not squad.is_empty(),"Javelin section garrisons the block")
	if squad.is_empty():return
	var spot:Vector2=Vector2(-1,-1)
	for dir in SIDES:
		spot=side_spot(sim,building,dir)
		if spot.x>=0:break
	var tank:Dictionary=enemy(sim,"tank",spot+(spot-building.bounds.get_center()).normalized()*4.0)
	check(not tank.is_empty(),"enemy tank placed for the Javelin")
	if tank.is_empty():return
	# Gun silent, as in the rifle case: the question is whether the team keeps
	# engaging after its first missile (lock, launch, reload, lock again).
	tank.cooldown=1e9
	var missiles0:int=sim.missiles_left(squad)
	var launches:Array=[]
	var hp0:float=tank.hp
	for i in 24*30:
		sim.tick(1.0/30)
		for m in sim.missiles:
			if int(m.shooter)==int(squad.id) and not launches.has(float(m.launched)):launches.append(float(m.launched))
		if not sim.alive(tank):break
	print("javelin: missiles %d -> %d, launches at %s, tank hp %.0f -> %.0f, gunner %s" % [missiles0,sim.missiles_left(squad),launches,hp0,tank.hp,squad.members[0].state])
	check(not launches.is_empty(),"garrisoned Javelin launches at the tank")
	check(launches.size()>=2 or not sim.alive(tank),"the Javelin keeps engaging after its first missile (%d launches)" % launches.size())
	check(sim.missiles_left(squad)==missiles0-launches.size(),"missiles are spent on the tank")

func _init()->void:
	var index:=harbor_index()
	rifle_case(index)
	javelin_case(index)
	print("GARRISON FIRE: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)
