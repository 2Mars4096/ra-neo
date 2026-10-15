extends SceneTree

var failures:Array[String]=[]
var checks:=0

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL: ",label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	battle.set_process(false)
	battle.set_physics_process(false)
	battle.show_help=false
	battle.paused=true
	await process_frame
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=dimensions
		for scenario in [0,4]:
			pass_setup(battle,scenario)
			battle.selected.clear()
			battle.hud.size=Vector2(dimensions)
			battle.hud.queue_redraw()
			await process_frame
			await process_frame
			var hud=battle.hud
			var actions:Array[String]=[]
			for hit in hud.hits:
				actions.append(hit.id)
				check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(hit.rect),"%s fits %s" % [hit.id,dimensions])
				check(hud.action_at(hit.rect.get_center())==(hit.id if hit.enabled else "blocked"),"%s hit target matches drawing" % hit.id)
			for i in hud.hits.size():
				for j in range(i+1,hud.hits.size()):
					check(not hud.hits[i].rect.intersects(hud.hits[j].rect),"%s / %s do not overlap" % [hud.hits[i].id,hud.hits[j].id])
			for required in ["pause","help","restart","attack","stop","retreat","buy:rifle","buy:atgm","buy:tank","buy:drone","buy:helo","buy:boat","buy:aa"]:
				check(required in actions,"action preserved: "+required)
			if scenario==4:
				check("buy:harvester" in actions,"harvester available in classic")
				for kind in battle.sim.Classic.BUILDINGS:check("build:"+kind in actions,"building available: "+kind)
			check(hud.minimap.position.x>dimensions.x-268,"minimap inside right command console")
			check(hud.battlefield_rect().size.x==dimensions.x-268,"camera-safe battlefield excludes sidebar")
			check(hud.action_at(Vector2(dimensions.x-2,300))=="blocked","sidebar frame blocks orders")
			check(hud.action_at(hud.minimap.get_center())=="minimap","minimap accepts pan")
			check(hud.action_at(Vector2(dimensions.x/2,dimensions.y/2))=="","battlefield center remains interactive")
			check(hud.action_at(Vector2(2,100))=="","removed upper dead band")
			check(hud.action_at(Vector2(235,dimensions.y-5))=="","bottom battlefield remains open")
		battle.selected=[battle.sim.living(0).filter(func(unit):return battle.sim.definitions[unit.kind].get("structure",false))[0].id]
		battle.hud.queue_redraw()
		await process_frame
		await process_frame
		var cancellation:Dictionary={}
		for hit in battle.hud.hits:
			if hit.id=="cancel_queue":cancellation=hit
		check(not cancellation.is_empty(),"selected facility retains queue cancellation")
		if not cancellation.is_empty():
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(cancellation.rect),"queue action fits viewport")
			for hit in battle.hud.hits:
				if hit.id!="cancel_queue":check(not hit.rect.intersects(cancellation.rect),"queue cancellation separate from "+hit.id)
		battle.show_help=true
		battle.hud.queue_redraw()
		await process_frame
		await process_frame
		var scenario_count:int=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json")).filter(func(config):return not config.get("hidden",false) or config.id==battle.sim.scenario.id).size()
		check(battle.hud.hits.size()==scenario_count+1,"guide lists playable scenarios and deploy")
		for hit in battle.hud.hits:
			if hit.id.begins_with("scenario:"):check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(hit.rect),"%s selector fits viewport"%hit.id)
		check(battle.hud.action_at(Vector2(3,90))=="blocked","guide modal blocks battlefield")
		battle.show_help=false
	print("HUD LAYOUT: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)

func pass_setup(battle,scenario:int) -> void:
	battle.sim=load("res://scripts/simulation.gd").new(true,scenario)
