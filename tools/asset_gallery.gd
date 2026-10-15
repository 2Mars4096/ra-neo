extends SceneTree
const Library=preload("res://scripts/asset_library.gd")
const Art=preload("res://scripts/visuals.gd")
var all:Array=[]
var filtered:Array=[]
var page:=0
var category:="all"
var grid:GridContainer
var status:Label
var selector:OptionButton
var next_button:Button
var control:Control
var categories:Array[String]=["all"]
var capturing:=false
var comparison_scale:=false
const PAGE_SIZE:=8
func _init()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,960)
	all=Library.entries()
	for spec in all:
		if str(spec.category) not in categories:categories.append(str(spec.category))
	control=Control.new();root.add_child(control);control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg:=ColorRect.new();bg.color=Color("18201e");control.add_child(bg);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin:=MarginContainer.new();control.add_child(margin);margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,18)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",12);margin.add_child(stack)
	var heading:=Label.new();heading.text="RA / NEO — ENVIRONMENT ASSET LIBRARY";heading.add_theme_font_size_override("font_size",24);stack.add_child(heading)
	var info:=Label.new();info.text="Original runtime models · Fitted previews by default; shared-scale comparison available · Bounds in world units; no automatic collision/cover";stack.add_child(info)
	var row:=HBoxContainer.new();stack.add_child(row)
	selector=OptionButton.new();row.add_child(selector)
	for c in categories:selector.add_item(c.replace("_"," ").capitalize())
	selector.item_selected.connect(func(index):category=categories[index];page=0;refresh())
	for action in [-1,1]:
		var button:=Button.new();button.text="Previous" if action<0 else "Next";row.add_child(button)
		if action==1:next_button=button
		button.pressed.connect(func():page=clampi(page+action,0,maxi(0,ceili(filtered.size()/float(PAGE_SIZE))-1));refresh())
	var scale_toggle:=CheckButton.new();scale_toggle.text="Compare at shared scale";row.add_child(scale_toggle)
	scale_toggle.toggled.connect(func(value):comparison_scale=value;refresh())
	status=Label.new();row.add_child(status)
	grid=GridContainer.new();grid.columns=4;grid.size_flags_vertical=Control.SIZE_EXPAND_FILL;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",12);stack.add_child(grid)
	refresh()
	if "--gallery-self-test" in OS.get_cmdline_user_args():
		await self_test()
		return
	if "--capture-gallery" in OS.get_cmdline_user_args():
		capturing=true
		for c in categories:
			if c=="all":continue
			category=c;page=0;selector.select(categories.find(c));refresh()
			var count:=ceili(filtered.size()/float(PAGE_SIZE))
			for i in count:
				page=i;refresh()
				await process_frame;await process_frame;await RenderingServer.frame_post_draw
				var path:="res://artifacts/asset-gallery-"+c+"-"+str(i+1)+".png"
				var error:=root.get_texture().get_image().save_png(path)
				print("ASSET GALLERY ",c," ",i+1," saved=",error)
				DirAccess.make_dir_recursive_absolute("res://artifacts/asset-previews")
				for column in grid.get_children():
					if not column.has_meta("asset_id"):continue
					var viewport:SubViewport=column.get_child(0).get_child(0)
					viewport.get_texture().get_image().save_png("res://artifacts/asset-previews/"+str(column.get_meta("asset_id"))+".png")
		FileAccess.open("res://artifacts/asset-manifest.json",FileAccess.WRITE).store_string(JSON.stringify(all,"  "))
		var hashes:Dictionary={}
		for spec in all:
			hashes[spec.builder]=FileAccess.get_sha256(spec.builder)
		for path in ["res://scripts/asset_library.gd","res://tools/asset_gallery.gd","res://scripts/environment_palette.gd","res://scripts/unit_models.gd","res://shaders/miniature.gdshader"]:hashes[path]=FileAccess.get_sha256(path)
		FileAccess.open("res://artifacts/asset-capture.json",FileAccess.WRITE).store_string(JSON.stringify({"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"model_count":all.size(),"captured_at":Time.get_datetime_string_from_system(),"source_hashes":hashes,"preview_scale":"camera fitted to measured model bounds; not equal world scale"},"  "))
		print("ASSET GALLERY COMPLETE ",all.size()," entries")
		quit()
func refresh()->void:
	for child in grid.get_children():child.free()
	filtered=all.filter(func(spec):return category=="all" or spec.category==category)
	status.text="  %d assets · Page %d / %d"%[filtered.size(),page+1,maxi(1,ceili(filtered.size()/float(PAGE_SIZE)))]
	for index in range(page*PAGE_SIZE,mini(filtered.size(),page*PAGE_SIZE+PAGE_SIZE)):
		card(filtered[index])
	while grid.get_child_count()%4!=0:
		var spacer:=Control.new();spacer.custom_minimum_size=Vector2(330,244);spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(spacer)
func card(spec:Dictionary,host:VBoxContainer=null)->void:
	var column:=VBoxContainer.new();column.set_meta("asset_id",spec.id);column.custom_minimum_size=Vector2(330,244);column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.size_flags_vertical=Control.SIZE_EXPAND_FILL;
	if host==null:grid.add_child(column)
	else:host.add_child(column)
	var container:=SubViewportContainer.new();container.stretch=true;container.custom_minimum_size=Vector2(320,186);container.size_flags_horizontal=Control.SIZE_EXPAND_FILL;container.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(container)
	var view:=SubViewport.new();view.size=Vector2i(320,186);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ONCE;container.add_child(view)
	container.resized.connect(func():view.render_target_update_mode=SubViewport.UPDATE_ONCE)
	var scene:=Node3D.new();view.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("34403b");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("d0d2c3");env.environment.ambient_light_energy=0.65;scene.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-32,0);light.light_energy=1.05;light.shadow_enabled=true;scene.add_child(light)
	var art=Art.new();var model:=Library.build(art,scene,spec.id)
	var f:Array=spec.footprint;var width:=float(f[2]);var depth:=float(f[3]);var height:=float(spec.height)
	var bounds:AABB=Library.render_bounds(model) if model!=null else AABB(Vector3(-width/2,0,-depth/2),Vector3(width,height,depth))
	spec["render_bounds"]=[bounds.position.x,bounds.position.y,bounds.position.z,bounds.size.x,bounds.size.y,bounds.size.z]
	width=bounds.size.x;depth=bounds.size.z;height=bounds.size.y
	var center:=bounds.position+bounds.size*Vector3(0.5,0.35,0.5)
	var ground:=MeshInstance3D.new();ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;var plane:=PlaneMesh.new();plane.size=Vector2(maxf(width+2,3),maxf(depth+2,3));ground.mesh=plane;ground.position=Vector3(center.x,-0.02,center.z);var material:=StandardMaterial3D.new();material.albedo_color=Color("596154");material.roughness=1;ground.material_override=material;scene.add_child(ground)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.size=24.0 if comparison_scale and host==null else maxf(2.5,maxf(width,maxf(depth,height*1.5))*1.45);camera.position=center+Vector3(16,23,25 if spec.kind in ["drain_outfall","direction_sign","guardrail","bus_stop"] else -25);scene.add_child(camera);camera.look_at(center);camera.current=true
	var label:=Label.new();label.text=spec.label;label.add_theme_font_size_override("font_size",14);column.add_child(label)
	var detail:=Label.new();detail.text="%s · render %.1f × %.1f × %.1f · %s"%[spec.variant,width,depth,height,spec.collision];detail.add_theme_font_size_override("font_size",11);column.add_child(detail)
	if model==null:label.text="MISSING: "+str(spec.id)
	if host==null:
		var inspect_button:=Button.new();inspect_button.text="Inspect";column.add_child(inspect_button)
		inspect_button.pressed.connect(func():inspect_asset(spec))
	else:
		var description:=Label.new();description.text=str(spec.get("description",""))+"\nPlacement envelope: "+str(spec.footprint)+"; height "+str(spec.height)+"\nPlacement: "+str(spec.placement)+" · collision must be installed by the map author";description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(description)

func inspect_asset(spec:Dictionary)->void:
	var panel:=PanelContainer.new();control.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin:=MarginContainer.new();panel.add_child(margin)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,24)
	var stack:=VBoxContainer.new();margin.add_child(stack)
	var back:=Button.new();back.text="Back to catalogue";stack.add_child(back);back.pressed.connect(func():panel.queue_free())
	card(spec,stack)
	var card_column:VBoxContainer=stack.get_child(1)
	var view:SubViewport=card_column.get_child(0).get_child(0)
	var scene:Node3D=view.get_child(0)
	var model:Node3D=null
	for child in scene.get_children():
		if child.has_meta("asset_id"):model=child;break
	var turn:=Button.new();turn.text="Rotate 90°";stack.add_child(turn)
	turn.pressed.connect(func():
		if is_instance_valid(model):
			model.rotation.y+=PI/2
			view.render_target_update_mode=SubViewport.UPDATE_ONCE)


func self_test()->void:
	var failures:Array[String]=[]
	selector.item_selected.emit(categories.find("waterfront"))
	await process_frame
	if filtered.is_empty() or not filtered.all(func(s):return s.category=="waterfront"):failures.append("Category filter")
	next_button.pressed.emit()
	if page!=1 or grid.get_child(0).get_meta("asset_id")!=filtered[PAGE_SIZE].id:failures.append("Next page callback")
	var before:=control.get_child_count()
	grid.get_child(0).get_child(3).pressed.emit()
	if control.get_child_count()!=before+1:failures.append("Inspect opens")
	var panel:Node=control.get_child(control.get_child_count()-1)
	var nodes:Array=[panel];var turn:Button=null;var back:Button=null;var model:Node3D=null
	while not nodes.is_empty():
		var n:Node=nodes.pop_back();nodes.append_array(n.get_children())
		if n is Button:
			if n.text=="Rotate 90°":turn=n
			if n.text=="Back to catalogue":back=n
		if n is Node3D and n.has_meta("asset_id"):model=n
	if turn==null or model==null:failures.append("Inspection controls/model")
	else:
		var angle:float=model.rotation.y;turn.pressed.emit()
		if not is_equal_approx(model.rotation.y,angle+PI/2):failures.append("Rotate callback")
	if back==null:failures.append("Back control")
	else:back.pressed.emit()
	await process_frame
	if control.get_child_count()!=before:failures.append("Back closes inspector")
	print("ASSET GALLERY UI: ",failures.size()," failures ",failures)
	quit(0 if failures.is_empty() else 1)
