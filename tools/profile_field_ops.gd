extends SceneTree
# CPU diagnostic runner. Run only in a frozen copy with tools/phase_probe.gd.
# phase_probe.gd is a generated timing helper; see artifacts/lag-investigation.md.
# No native benchmark, screenshot, or production output is invoked.
var probe
var results:Array=[]
func _init()->void:
 call_deferred("run")
func stats(values:Array)->Dictionary:
 var ordered:=values.duplicate()
 ordered.sort()
 var total:float=0
 for v in values:total+=v
 return {"calls":values.size(),"total_ms":total,"mean_ms":total/maxi(1,values.size()),"p95_ms":ordered[mini(ordered.size()-1,int(ordered.size()*0.95))] if not ordered.is_empty() else 0,"max_ms":ordered.back() if not ordered.is_empty() else 0}
func phases()->Dictionary:
 var out:Dictionary={}
 for key in probe.samples:out[key]=stats(probe.samples[key])
 return out
func prepare(preset:int):
 var sim=load("res://scripts/simulation.gd").new(true,preset)
 if preset==3:
  sim.time=45.0
  for i in 22:sim.spawn("rifle",0,Vector2(8+(i%5)*4,38+(i/5)*4))
  sim.issue(sim.living(0).map(func(u):return u.id),Vector2(46,22),"attack_move")
 else:
  sim.issue(sim.living(0).filter(func(u):return u.kind in ["rifle","tank","atgm"]).map(func(u):return u.id),Vector2(72,45),"attack_move")
 return sim
func run()->void:
 if DisplayServer.get_name()!="headless":
  printerr("Refusing non-headless execution");quit(2);return
 if not FileAccess.file_exists("res://tools/phase_probe.gd"):
  printerr("Requires a prepared frozen diagnostic copy; see artifacts/lag-investigation.md");quit(2);return
 probe=load("res://tools/phase_probe.gd")
 for preset in [5,3]:
  var begin:=Time.get_ticks_usec()
  var sim=prepare(preset)
  var startup:float=(Time.get_ticks_usec()-begin)/1000.0
  for i in 60:sim.tick(1.0/30.0);sim.events.clear()
  probe.samples.clear()
  var ticks:Array=[]
  var memory_before:=Performance.get_monitor(Performance.MEMORY_STATIC)
  for i in 600:
   begin=Time.get_ticks_usec()
   sim.tick(1.0/30.0)
   ticks.append((Time.get_ticks_usec()-begin)/1000.0)
   sim.events.clear()
  results.append({"preset":preset,"scenario":sim.scenario.name,"mode":sim.scenario.get("mode","tactical"),"startup_ms":startup,"ticks":stats(ticks),"phases_inclusive":phases(),"groups":sim.units.size(),"end_time":sim.time,"result":sim.result,"state_sha256":var_to_str([sim.units,sim.combat_rng.state,sim.classic,sim.credits]).sha256_text(),"nav_grids":sim.terrain.navigation.size(),"visibility_cache":sim.visibility_cache.size(),"static_memory_delta_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)-memory_before})
 # Actual scene scripts under dummy rendering: animation/HUD CPU, not GPU timings.
 var sim_class=load("res://scripts/simulation.gd")
 sim_class.scenario_selection=3
 var battle=load("res://scripts/battle.gd").new()
 battle.sim=prepare(3)
 root.add_child(battle)
 battle.set_process(false);battle.set_physics_process(false)
 battle.show_help=false;battle.paused=false
 Engine.max_fps=0
 for i in 10:
  battle._process(1.0/60.0)
  await process_frame
 probe.samples.clear()
 for i in 120:
  if i%2==0:battle.sim.tick(1.0/30.0)
  battle._process(1.0/60.0)
  await process_frame
 results.append({"presentation_headless_frames":120,"phases_inclusive":phases(),"draw_calls_dummy_renderer":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
 var output:="/private/tmp/field-ops-profile.json"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
 var file:=FileAccess.open(output,FileAccess.WRITE)
 file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"results":results},"  "))
 battle.queue_free()
 await process_frame
 print("FIELD OPS CPU DIAGNOSTIC: completed; ",output)
 quit()
