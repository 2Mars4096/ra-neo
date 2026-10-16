extends SceneTree
# Goals inside a wreck's margin (black_sea_harbor). A land vehicle can never
# stop within hull radius + wreck radius of a burnt-out hull, so a click on or
# beside a wreck must resolve to a clear spot next to it (on the near side when
# the click is on the wreck itself), whether the wreck was there when the order
# was given or appeared on the way. A group order spreads its slots round the
# wreck, and a direct attack on infantry hugging a wreck still closes and fires.
const Sim=preload("res://scripts/simulation.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const OPEN:=Vector2(300,640)
const MARGIN:=2.45+2.45 # tank hull + tank wreck
const NEAR:=3.0 # "a clear spot within ~3 u" of the wreck's margin
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func scenario_index(id:String)->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id==id:return i
	return -1

func _init()->void:
	var started:=Time.get_ticks_usec()
	single("move_on_wreck",Vector2.ZERO,"move")
	single("attack_move_on_wreck",Vector2.ZERO,"attack_move")
	single("move_far_edge",Vector2(3.0,1.0),"move")
	single("move_near_edge",Vector2(-3.5,0.0),"move")
	appears_later()
	group()
	direct_attack()
	print("WRECK GOAL: %d checks, %d failures (%.0f ms)" % [checks,failures,(Time.get_ticks_usec()-started)/1000.0])
	quit(0 if failures==0 else 1)

func fresh()->Object:
	return Sim.new(false,scenario_index("black_sea_harbor"))

# A real kill: a tank hull knocked out where it stands becomes a wreck.
func wreck(sim,pos:Vector2)->Dictionary:
	var hull:Dictionary=sim.spawn("tank",1,pos)
	hull.pos=pos
	VehicleDamage.ensure_state(sim,hull)
	var damage:float=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	hull.hp-=damage
	check(hull.get("wrecked",false),"wreck placed at %s" % pos)
	return VehicleDamage.wrecks(sim).back()

func tank(sim,pos:Vector2)->Dictionary:
	var u:Dictionary=sim.spawn("tank",0,pos)
	u.pos=pos
	u.facing=Vector2.RIGHT
	return u

# Ticks until every unit has no orders (or the limit); returns seconds taken (-1 = never).
func run(sim,units:Array,limit:float)->float:
	for step in int(limit*30.0):
		sim.tick(1.0/30.0)
		if units.all(func(u):return u.orders.is_empty()):return (step+1)/30.0
	return -1.0

func clear_of(wreck:Dictionary,pos:Vector2)->bool:
	return pos.distance_to(wreck.pos)>=MARGIN-0.05

func single(label:String,offset:Vector2,mode:String)->void:
	var sim=fresh()
	var hulk:=wreck(sim,OPEN)
	var start:=OPEN+Vector2(-24,0)
	var u:=tank(sim,start)
	sim.rebuild_spatial()
	var click:=OPEN+offset
	check(sim.issue([u.id],click,mode)==1,"%s: order accepted" % label)
	var goal:Vector2=u.orders[0].pos if not u.orders.is_empty() else click
	check(clear_of(hulk,goal),"%s: ordered goal resolves clear of the wreck (%.2f u from it)" % [label,goal.distance_to(hulk.pos)])
	var took:=run(sim,[u],40.0)
	var gap:float=u.pos.distance_to(hulk.pos)
	print("  %s: arrive=%.1f s at %s, %.2f u from wreck, %.2f u from click, state %s" % [label,took,u.pos.snapped(Vector2(0.01,0.01)),gap,u.pos.distance_to(click),u.state])
	check(took>=0.0,"%s: tank arrives (state %s, %.2f u from wreck)" % [label,u.state,gap])
	check(clear_of(hulk,u.pos) and gap<=MARGIN+NEAR,"%s: stops beside the wreck, clear of it and within %.0f u of its margin (%.2f u)" % [label,NEAR,gap])
	if offset.x<=0.0:check((u.pos-hulk.pos).dot(start-hulk.pos)>0.0,"%s: stops on the near side" % label)

# The wreck appears at the goal after the order was given.
func appears_later()->void:
	var sim=fresh()
	var start:=OPEN+Vector2(-30,0)
	var u:=tank(sim,start)
	sim.rebuild_spatial()
	check(sim.issue([u.id],OPEN,"move")==1,"appears_later: order accepted")
	for step in 60:sim.tick(1.0/30.0)
	var hulk:=wreck(sim,OPEN)
	var took:=run(sim,[u],40.0)
	var gap:float=u.pos.distance_to(hulk.pos)
	print("  appears_later: arrive=%.1f s at %s, %.2f u from wreck, state %s" % [took,u.pos.snapped(Vector2(0.01,0.01)),gap,u.state])
	check(took>=0.0,"appears_later: tank arrives (state %s, %.2f u from wreck)" % [u.state,gap])
	check(clear_of(hulk,u.pos) and gap<=MARGIN+NEAR,"appears_later: stops clear beside the wreck (%.2f u)" % gap)
	check((u.pos-hulk.pos).dot(start-hulk.pos)>0.0,"appears_later: stops on the near side")

# Four tanks sent together onto the wreck: every slot clear of it, slots apart,
# spread round it rather than stacked on one spot.
func group()->void:
	var sim=fresh()
	var hulk:=wreck(sim,OPEN)
	var tanks:Array=[]
	for i in 4:tanks.append(tank(sim,OPEN+Vector2(-28,(i-1.5)*6.0)))
	sim.rebuild_spatial()
	check(sim.issue(tanks.map(func(t):return t.id),OPEN,"move")==4,"group: all four accept the order")
	var slots:Array=tanks.map(func(t):return t.orders[0].pos if not t.orders.is_empty() else t.pos)
	var apart:=true
	for i in slots.size():
		check(clear_of(hulk,slots[i]),"group: slot %d clear of the wreck (%.2f u)" % [i,slots[i].distance_to(hulk.pos)])
		for j in range(i+1,slots.size()):if slots[i].distance_to(slots[j])<4.0:apart=false
	check(apart,"group: slots spread apart round the wreck")
	var arrived:Array=[-1.0,-1.0,-1.0,-1.0]
	for step in 60*30:
		sim.tick(1.0/30.0)
		for i in 4:if arrived[i]<0.0 and tanks[i].orders.is_empty():arrived[i]=sim.time
		if "trace_group" in OS.get_cmdline_user_args() and step%30==0:print("t=%.0f "%sim.time,tanks.map(func(t):return "%s %s b%.1f p%d"%[(t.pos-hulk.pos).snapped(Vector2(0.1,0.1)),t.state,t.blocked_time,t.path.size()]))
		if arrived.all(func(a):return a>=0.0):break
	var reach:=0.0
	for p in slots:reach=maxf(reach,p.distance_to(hulk.pos))
	print("  group: arrive %s s, slots %s, end %s" % [arrived.map(func(a):return snappedf(a,0.1)),slots.map(func(p):return (p-hulk.pos).snapped(Vector2(0.1,0.1))),tanks.map(func(t):return (t.pos-hulk.pos).snapped(Vector2(0.1,0.1)))])
	check(arrived.all(func(a):return a>=0.0),"group: every tank arrives within 60 s")
	check(tanks.all(func(t):return clear_of(hulk,t.pos)),"group: every tank stops clear of the wreck")
	check(reach<=MARGIN+NEAR+6.0,"group: the slots gather round the wreck (farthest %.2f u)" % reach)

# Enemy riflemen hugging the wreck: a direct attack still closes and fires.
func direct_attack()->void:
	var sim=fresh()
	var hulk:=wreck(sim,OPEN)
	var enemy:Dictionary=sim.spawn("rifle",1,OPEN+Vector2(3.2,0))
	enemy.pos=OPEN+Vector2(3.2,0)
	var u:=tank(sim,OPEN+Vector2(-32,0))
	sim.rebuild_spatial()
	enemy.seen_by[0]=true
	check(sim.issue([u.id],enemy.pos,"attack",false,enemy.id)==1,"direct_attack: order accepted")
	check(not u.orders.is_empty() and u.orders[0].mode=="attack" and int(u.orders[0].target)==enemy.id,"direct_attack: the order keeps its target")
	var fired:=-1.0
	var hp:float=enemy.hp
	for step in 30*30:
		sim.tick(1.0/30.0)
		if u.last_shot>0.0 and u.target==enemy.id and fired<0.0:fired=sim.time
		if not sim.alive(enemy):break
	print("  direct_attack: fired at %.1f s, enemy hp %.0f -> %.0f, tank at %.2f u from wreck" % [fired,hp,enemy.hp,u.pos.distance_to(hulk.pos)])
	check(fired>=0.0,"direct_attack: the tank fires on the riflemen beside the wreck")
	check(enemy.hp<hp,"direct_attack: the riflemen take damage")
