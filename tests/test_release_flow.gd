extends SceneTree
# Controlled end-state fixtures, deliberately separate from harbor_playthrough:
# verify result UI -> real click/confirmation -> actual SceneTree reload.
# These state assignments exercise controller lifecycle, not earned victory.
const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func _init()->void:
	Sim.scenario_selection=Sim.default_selection()
	call_deferred("run")

func settle():
	await process_frame
	await process_frame
	var battle=current_scene
	if battle!=null:
		battle.set_process(false)
		battle.set_physics_process(false)
	return battle

func fresh(battle,label:String)->void:
	check(battle!=null,label+": current scene exists after reload")
	if battle==null:return
	var sim=battle.sim
	check(sim.scenario.id=="black_sea_harbor" and sim.result=="",label+": fresh public Harbor, no terminal result")
	check(sim.time==0 and sim.credits==3200 and sim.field_ops.income_rate==6,label+": timer and authored economy reset")
	check(sim.living(0).size()==sim.scenario.player_force.size(),label+": authored starting force restored")
	check(sim.objectives.all(func(o):return o.owner==1 and o.progress==0),label+": all objectives reset")
	check(sim.FieldOps.queue(sim).is_empty() and battle.selected.is_empty(),label+": purchase queue and selection reset")
	check(battle.show_help and not battle.menu_open(),label+": deployment briefing restored")

func run()->void:
	root.size=Vector2i(1280,720)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle=await settle()
	fresh(battle,"initial")
	for outcome in ["VICTORY","DEFEAT"]:
		battle.show_help=false
		battle.paused=true
		var sim=battle.sim
		if outcome=="VICTORY":
			for unit in sim.units:
				if unit.team==1:unit.hp=0
			for objective in sim.objectives:
				objective.owner=0
				objective.progress=sim.capture_time
			sim.score_hold=float(sim.scenario.hold)
			sim.time=100.0
			sim.counterattack_at=0.0
			sim.counterattack_sent=true
			sim.update_objectives(0.0)
		else:
			for unit in sim.units:
				if unit.team==0:unit.hp=0
			sim.tick(1.0/30.0)
		check(sim.result==outcome,outcome+": rules produce the controlled terminal fixture")
		var seconds:float=sim.time
		sim.tick(1.0)
		check(sim.time==seconds,outcome+": terminal simulation remains frozen")
		battle.hud.queue_redraw()
		await process_frame
		await process_frame
		var redeploy:Array=battle.hud.hits.filter(func(hit):return hit.id=="restart")
		check(redeploy.size()==1 and battle.hud.modal,outcome+": result overlay has one redeploy action")
		if redeploy.size()!=1:break
		var before:int=battle.get_instance_id()
		var click:=InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.pressed=true
		click.position=redeploy[0].rect.get_center()
		battle._input(click)
		battle=await settle()
		check(battle!=null and battle.get_instance_id()!=before,outcome+": real redeploy click replaced the scene")
		fresh(battle,outcome+" redeploy")
	# An active match must pass through the confirmation button's connected
	# signal, rather than only opening/canceling a modal.
	if battle!=null:
		battle.show_help=false
		battle.paused=false
		battle.sim.tick(1.0/30.0)
		battle.ui_action("restart",Vector2.ZERO)
		check(battle.menu_open() and battle.menu.mode=="restart","live restart opens confirmation")
		var buttons:Array=battle.menu.find_children("*","Button",true,false).filter(func(button):return button.text=="Restart battle")
		check(buttons.size()==1,"actual confirmation button is present")
		if buttons.size()==1:
			var before:int=battle.get_instance_id()
			buttons[0].pressed.emit()
			battle=await settle()
			check(battle!=null and battle.get_instance_id()!=before,"confirmed live restart replaced the scene")
			fresh(battle,"confirmed restart")
	print("RELEASE FLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
