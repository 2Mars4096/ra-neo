extends SceneTree
# Headless presentation CPU on the historical synthetic extra-force/time-jumped
# setup of profile_harbor_combat.gd; sustained combat is NOT asserted. Per engine
# process frame it brackets the idle step: from a
# node processed first (lowest priority) to RenderingServer.frame_pre_draw, i.e.
# every _process (battle sync/animation/fog/effects), HUD _draw callbacks and the
# transform-notification flush. The 30 Hz simulation tick runs before that window
# and is excluded. The dummy renderer draws nothing: this is not a GPU number.
# Works on builds without the opt-in battle.frame_profile laps (prints them if present).
# Optional user args: --seconds=N (default 12), --no-effects, --no-hud.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
class FrameStart extends Node:
	var stamp:=0
	func _process(_dt:float)->void:stamp=Time.get_ticks_usec()
class FrameEnd extends Node:
	var tree
	func _process(_dt:float)->void:tree.frame_end.call_deferred()
var battle
var start_node:=FrameStart.new()
var end_node:=FrameEnd.new()
var worst:Array[float]=[]
var second:=-1
var started:=0
var seconds:=12.0
var costs:Array[float]=[]
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	print("SCOPE: synthetic transit presentation CPU; combat not asserted. Dummy-renderer samples are not rendered/GPU frame times.")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):seconds=float(arg.trim_prefix("--seconds="))
	Sim.scenario_selection=harbor_index()
	Engine.max_fps=0
	call_deferred("run")
func run()->void:
	root.size=Vector2i(1920,1080)
	start_node.process_priority=-100000
	root.add_child(start_node)
	battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	var sim=battle.sim
	for i in 6:sim.spawn("rifle",0,Vector2(300+i*5,640))
	for i in 2:sim.spawn("tank",0,Vector2(310+i*8,650))
	for wave in 2:
		sim.time=float(sim.field_ops.get("waves",{}).get("next",sim.scenario.enemy_waves.first))+0.1
		FieldOps.enemy_offensive(sim)
	battle.camera_focus=Vector3(330,0,630);battle.camera_size=56.0;battle.camera_zoom_target=56.0;battle.update_camera()
	battle.paused=false;battle.show_help=false;battle.effects.muted=true
	battle.selected=sim.living(0).map(func(u):return u.id).slice(0,8)
	if "profiling_frames" in battle:battle.profiling_frames=true
	if "--no-effects" in OS.get_cmdline_user_args():battle.effects.set_process(false)
	if "--no-hud" in OS.get_cmdline_user_args():battle.hud.visible=false
	end_node.tree=self
	end_node.process_priority=100000
	root.add_child(end_node)
	started=Time.get_ticks_msec()
func frame_end()->void:
	if started==0 or start_node.stamp==0:return
	var elapsed:=Time.get_ticks_msec()-started
	if elapsed<=1500:
		if "frame_profile" in battle:battle.frame_profile.clear()
		return
	costs.append((Time.get_ticks_usec()-start_node.stamp)/1000.0)
	if elapsed/1000!=second:
		second=elapsed/1000
		worst.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
	if elapsed>seconds*1000.0:
		started=0
		report()
		quit()
func stats(values:Array[float])->String:
	if values.is_empty():return "n=0"
	var s:=values.duplicate();s.sort()
	var total:=0.0
	for v in s:total+=v
	return "n=%d mean=%.3fms p50=%.3fms p95=%.3fms p99=%.3fms max=%.2fms" % [s.size(),total/s.size(),s[s.size()/2],s[int(s.size()*0.95)],s[int(s.size()*0.99)],s.back()]
func report()->void:
	print("HARBOR FRAMES idle-step CPU: ",stats(costs))
	print("HARBOR FRAMES engine worst idle frame per second (TIME_PROCESS): ",stats(worst))
	if "frame_profile" in battle:
		for key in battle.frame_profile:print("FRAME PHASE %-12s per_frame=%.3fms" % [key,battle.frame_profile[key]/maxi(1,costs.size())])
	var count:=[0,0]
	for n in root.find_children("*","",true,false):
		count[0]+=1
		if n is VisualInstance3D:count[1]+=1
	print("HARBOR FRAMES nodes=%d visual_instances=%d visible_units=%d sim_time=%.1f" % [count[0],count[1],battle.sim.units.filter(func(u):return battle.sim.alive(u) and u.visible).size(),battle.sim.time])
