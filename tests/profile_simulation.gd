# Headless CPU workload matching showcase_launch's 100-member stress setup.
# This is simulation timing, not a rendered frame or input-latency benchmark.
extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
func _init()->void:
 var sim=Sim.new(true,3)
 if "--exhaustive-actors" in OS.get_cmdline_user_args():sim.use_actor_index=false
 for i in 22:sim.spawn("rifle",0,Vector2(8+(i%5)*4,38+(i/5)*4))
 sim.issue(sim.living(0).map(func(u):return u.id),Vector2(46,22),"attack_move")
 sim.time=45.0
 var times:Array=[]
 var total:=Time.get_ticks_usec()
 for i in 600:
  var start:=Time.get_ticks_usec()
  sim.tick(1.0/30.0)
  times.append((Time.get_ticks_usec()-start)/1000.0)
  sim.events.clear()
 var elapsed:float=(Time.get_ticks_usec()-total)/1000.0
 times.sort()
 var report:={"scope":"Headless simulation only; no renderer, setup excluded, all 600 ticks measured", "scenario":"Canal Watch", "initial_weather_time":45,"ticks":600,"dt":1.0/30.0,"actor_index":sim.use_actor_index,"elapsed_ms":elapsed,"p50_ms":times[300],"p95_ms":times[570],"unit_state_sha256":JSON.stringify(sim.units).sha256_text()}
 FileAccess.open("res://artifacts/simulation-profile.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("SIMULATION PROFILE: ",JSON.stringify(report))
 quit()
