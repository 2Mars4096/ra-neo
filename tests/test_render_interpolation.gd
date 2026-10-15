extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	battle.set_process(false);battle.set_physics_process(false)
	var u=battle.sim.units[0]
	var original:Vector2=u.pos
	battle.render_history[u.id]={"pos":u.pos-Vector2(1,0),"members":u.members.map(func(m):return m.pos-Vector2(1,0))}
	battle.paused=false;battle.show_help=false
	battle.sync_units(0.016)
	var shown:Vector3=battle.nodes[u.id].position
	assert(shown.x>=original.x-1.001 and shown.x<=original.x+0.001)
	assert(u.pos==original,"presentation cannot change authoritative position")
	battle.paused=true;battle.sync_units(0.016)
	assert(is_equal_approx(battle.nodes[u.id].position.x,original.x),"pause snaps to authoritative state")
	battle.camera_size=72
	battle.sync_units(0.016)
	var fine:Array=battle.nodes[u.id].get_meta("fine_shadow_meshes",[])
	assert(not fine.is_empty(),"articulated fine shadow parts are indexed")
	for mesh in fine:assert(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert(battle.contact_shadow_count>0 and battle.contact_shadows.visible,"far infantry retain grounded contact shadows")
	battle.camera_size=32
	battle.sync_units(0.016)
	for mesh in fine:assert(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"close zoom restores detailed shadows")
	assert(not battle.contact_shadows.visible,"close zoom restores real shadows without duplicated contact overlay")
	assert(u.pos==original,"shadow detail cannot change simulation")
	print("RENDER INTERPOLATION: PASS")
	quit()
