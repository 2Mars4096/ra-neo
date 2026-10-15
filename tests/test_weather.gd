extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Weather=preload("res://scripts/weather.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:
	check(Weather.sample(0).rain==0,"clear opening")
	check(Weather.sample(60).rain==1 and Weather.sample(60).sight_scale==0.8,"rain visibility band")
	check(Weather.sample(150).rain==0 and Weather.sample(150).wetness>0,"soil stays wet after front")
	check(Weather.sample(240).wetness==0,"soil dries")
	check(Weather.sample(60,false).sight_scale==1,"legacy scenarios unchanged")
	var sim=Sim.new(false,3)
	var scout=sim.spawn("drone",0,Vector2(30,60))
	var target=sim.spawn("drone",1,Vector2(30,60)+Vector2(float(sim.definitions.drone.sight)*0.9,0))
	sim.update_visibility()
	check(target.seen_by[0],"clear sight reaches contact")
	var clear_cells:int=sim.visible_cells.size()
	sim.weather=Weather.sample(60)
	sim.update_visibility()
	check(not target.seen_by[0] and sim.visible_cells.size()<clear_cells,"rain reduces contacts and fog using same state")
	var road:=Vector2(42,48)
	var mud:=Vector2(12,30)
	var dry:float=sim.terrain.ground_speed(mud)
	sim.terrain.wetness=1
	check(sim.terrain.ground_speed(mud)<dry,"wet mud slows units")
	check(sim.terrain.ground_speed(road)==1,"firm route keeps full speed")
	print("WEATHER TESTS: ",failures," failures")
	quit(0 if failures==0 else 1)
