extends SceneTree
# Authored Riverside regression. --no-report leaves report artifacts untouched.
const Sim=preload("res://scripts/simulation.gd")
const Terrain=preload("res://scripts/terrain.gd")
const Classic=preload("res://scripts/classic.gd")
var report:Dictionary={"scenario_index":5,"checks":[],"routes":[],"bases":[],"frontages":[],"limitations":["No native game or performance benchmark launched.","Travel times integrate terrain cost / nominal speed; no combat, acceleration, traffic or squad recovery.","Cover fraction is terrain.cover, not threat-specific protection or LOS.","Build samples are alternative legal sites, not simultaneously placeable facilities."]}
var failures:=0
func xy(p:Vector2)->Array:return [p.x,p.y]
func check(ok:bool,label:String)->void:
	report.checks.append({"pass":ok,"label":label})
	if not ok:failures+=1;print("FAIL: ",label)
func _init()->void:call_deferred("run")
func route(t,points:Array,kind:String,defs:Dictionary,label:String)->Dictionary:
	var radius:float=defs[kind].radius
	var profile:String=t.mobility_profile(kind)
	var length:=0.0;var cost:=0.0;var covered:=0.0;var road:=0.0
	var previous:Vector2=points[0]
	var actual:Array=[xy(previous)]
	for goal in points.slice(1):
		var path:Array=t.path(previous,goal,"land",radius,[],profile)
		if path.is_empty():return {"label":label,"kind":kind,"reachable":false,"failed_from":xy(previous),"failed_to":xy(goal)}
		for point in path:
			if not t.segment_clear(previous,point,"land",radius):return {"label":label,"kind":kind,"reachable":false,"unchecked_segment":true}
			var d:float=previous.distance_to(point)
			length+=d;cost+=t.segment_travel_cost(previous,point,"land",profile)
			var n:=maxi(1,ceili(d/0.5))
			for i in n:
				var p:Vector2=previous.lerp(point,(i+0.5)/n)
				if t.cover(p):covered+=d/n
				if t.on_road(p):road+=d/n
			actual.append(xy(point));previous=point
	return {"label":label,"kind":kind,"reachable":true,"length":length,"nominal_seconds":cost/float(defs[kind].speed),"cover_fraction":covered/maxf(length,0.001),"road_fraction":road/maxf(length,0.001),"path":actual}
func run()->void:
	if "--frontage-followup" in OS.get_cmdline_user_args():
		frontage_followup()
		return
	if "--riverside" in OS.get_cmdline_user_args():
		run_riverside_suite()
		return
	var source:=FileAccess.get_file_as_string("res://resources/scenarios.json")
	report["scenario_sha256"]=source.sha256_text()
	var configs:Array=JSON.parse_string(source)
	check(configs.size()>5,"authored sixth scenario exists")
	if configs.size()<6:quit(1);return
	report["source_hashes_at_start"]={}
	for filename in ["scripts/terrain.gd","scripts/classic.gd","scripts/simulation.gd","scripts/roadside_props.gd","scripts/hud.gd"]:
		report.source_hashes_at_start[filename]=FileAccess.get_file_as_string("res://"+filename).sha256_text()
	var t=Terrain.new(5);t.poles.clear() # Frozen classic fixture had no capture poles.
	var sim=preload("res://tests/fixtures/legacy_riverside.gd").create(true)
	report["scenario"]=sim.scenario;report["scope"]="Frozen former Riverside classic layout";report["engine"]=Engine.get_version_info().string
	check(t.world_size==Vector2(144,108),"authored dimensions 144x108")
	var visited:Dictionary={t.roads.nodes.keys()[0]:true}
	for sweep in t.roads.nodes.size():
		for edge in t.roads.segments:
			if visited.has(edge.from):visited[edge.to]=true
			if visited.has(edge.to):visited[edge.from]=true
	check(visited.size()==t.roads.nodes.size(),"named road graph connected")
	var road_hits:Array=[];var road_samples:=0
	for edge in t.roads.segments:
		var normal:Vector2=(edge.b-edge.a).normalized().orthogonal()
		var n:=maxi(1,ceili(edge.a.distance_to(edge.b)/0.25))
		for i in n+1:
			for offset in [-0.5,-0.25,0.0,0.25,0.5]:
				var p:Vector2=edge.a.lerp(edge.b,float(i)/n)+normal*edge.width*offset
				road_samples+=1
				if t.blocked(p) or t.is_water(p):road_hits.append({"edge":[edge.from,edge.to],"point":xy(p)})
	report["road_samples"]=road_samples;report["road_blocker_hits"]=road_hits
	check(road_hits.is_empty(),"road width samples avoid static blockers and water")
	for team in 2:
		var hq:Dictionary=Classic.structures(sim,team,"hq")[0]
		var legal:Array=[]
		for x in range(4,125,2):
			for y in range(4,105,2):
				if Classic.can_build(sim,"refinery",team,Vector2(x,y)):legal.append([x,y])
		var site:=Classic.find_site(sim,"refinery",team)
		check(not legal.is_empty(),"base %s has legal refinery sites"%team)
		check(site.x>=0,"base %s automatic refinery site exists"%team)
		var harvester:Dictionary=sim.living(team).filter(func(u):return u.kind=="harvester")[0]
		var field:Vector2=sim.classic.fields[team].pos
		var access=route(sim.terrain,[harvester.pos,field+Vector2(0,3)],"harvester",sim.definitions,"starting deposit %s"%team)
		check(access.reachable,"base %s harvester reaches collection radius"%team)
		report.bases.append({"team":team,"hq":xy(hq.pos),"legal_refinery_samples":legal,"automatic_refinery":xy(site),"starting_deposit_route":access})
	for i in range(1,configs[5].footpaths[0].size()):
		var a:Array=configs[5].footpaths[0][i-1];var b:Array=configs[5].footpaths[0][i]
		check(t.segment_clear(Vector2(a[0],a[1]),Vector2(b[0],b[1]),"land",2.65),"authored footpath segment %s clears rifle group envelope"%i)
	var north:Vector2=t.roads.nodes.industry_n
	var west:Array=[Vector2(24,97)]
	for waypoint in configs[5].footpaths[0]:west.append(Vector2(waypoint[0],waypoint[1]))
	west.append(north);west.append(Vector2(114,17))
	var routes:Dictionary={"unconstrained":[Vector2(24,97),Vector2(114,17)],"town":[Vector2(24,97),Vector2(48,76),Vector2(72,54),north,Vector2(114,17)],"western_farm":west,"eastern_freight":[Vector2(24,97),Vector2(72,97),t.roads.nodes.freight_south_turn,Vector2(108,54),north,Vector2(114,17)]}
	for wet in [0.0,1.0]:
		t.wetness=wet
		for kind in ["rifle","tank","harvester"]:
			for label in routes:
				var result:=route(t,routes[label],kind,sim.definitions,label)
				result["wetness"]=wet;report.routes.append(result)
				check(result.reachable,"%s %s wet=%s connected"%[label,kind,wet])
				if label=="western_farm" and result.reachable:
					check(result.path.all(func(p):return p[1]<20 or p[1]>82 or p[0]<=18),"western flank does not double back through town %s wet=%s"%[kind,wet])
	for field in sim.classic.fields:
		for team in 2:
			var start:=Vector2(24,97) if team==0 else Vector2(114,17)
			var result:=route(t,[start,field.pos+Vector2(0,3)],"harvester",sim.definitions,"field %s team %s"%[field.pos,team])
			result["wetness"]=t.wetness;report.routes.append(result)
			check(result.reachable,"resource access "+result.label)
	for i in t.blocks.size():
		var rect:Rect2=t.blocks[i];var a:Dictionary=configs[5].architecture[i]
		var direction:Vector2={"north":Vector2.UP,"south":Vector2.DOWN,"east":Vector2.RIGHT,"west":Vector2.LEFT}[a.facing]
		var face:Vector2=rect.get_center()+direction*rect.size*0.5
		var road_distance:=-1.0;var hit:=-1
		for step in range(1,61):
			var p:Vector2=face+direction*(step*0.5)
			if t.on_road(p):road_distance=step*0.5;break
			if t.blocked(p):hit=step;break
		report.frontages.append({"parcel":i,"design":a.design,"facing":a.facing,"face":xy(face),"road_distance_along_facing":road_distance,"blocked_after":hit*0.5 if hit>=0 else -1})
	# Bounded frontage correction: preserve full parcel sizes and test the shared road corridor.
	var frontage_rects:Dictionary={0:Rect2(34,42.5,7,7),2:Rect2(56,42.5,9,7),8:Rect2(56,58.5,9,7),9:Rect2(76.5,58.5,7,7)}
	for index in frontage_rects:
		var rect:Rect2=t.blocks[index]
		check(rect==frontage_rects[index],"approved high-street frontage rectangle %s"%index)
		var setback:float=51.0-rect.end.y if index in [0,2] else rect.position.y-57.0
		check(setback>=1.5 and setback<=2.0,"frontage kerb clearance 1.5 to 2m parcel %s"%index)
		for prop in t.roadside_blocks:
			check(not rect.grow(0.12).intersects(prop),"frontage avoids nearby prop with clearance parcel %s"%index)
		for other in t.blocks:
			if other==rect:continue
			check(not rect.grow(0.12).intersects(other),"frontage avoids adjacent parcel %s"%index)
		for field in sim.classic.fields:
			check(not t.circle_rect(field.pos,3.3,rect),"frontage avoids resource marker footprint parcel %s"%index)
	check(t.blocks[4]==Rect2(87,38,9,9),"villa shift abandoned to retain resource-marker clearance")
	for radius in [2.45,2.65]:
		for offset in [0.0,0.5,1.0]:
			check(t.segment_clear(Vector2(34,54+offset),Vector2(105,54+offset),"land",radius),"continuous high-street tank/squad corridor radius %s offset %s"%[radius,offset])
	report["frontage_correction"]={"rectangles":{"0":[34,42.5,7,7],"2":[56,42.5,9,7],"8":[56,58.5,9,7],"9":[76.5,58.5,7,7]},"kerb_setback":1.5,"villa_retained":[87,38,9,9],"villa_reason":"Target setback overlaps unchanged visible resource marker and rocks at (93,51).","south_cafe_side_shift":"0.5m west leaves 0.3m parcel-to-sedan-footprint gap; no props moved.","visual_acceptance":"No updated native render; parcel bounds checked headlessly."}
	# Geometry-only full-base packing: grant funds and complete each building without simulating time.
	report["base_packing"] = []
	for team in 2:
		var fixture=preload("res://tests/fixtures/legacy_riverside.gd").create(true)
		fixture.credits=5000;fixture.classic.enemy_credits=5000
		var sites:Array=[Vector2(14,86),Vector2(4,104),Vector2(30,100),Vector2(30,78)] if team==0 else [Vector2(114,26),Vector2(98,6),Vector2(96,16),Vector2(122,26)]
		var kinds:Array=["refinery","power","barracks","factory"]
		var results:Array=[]
		for i in kinds.size():
			var ok:bool=Classic.build(fixture,kinds[i],team,sites[i])
			check(ok,"base %s sequential geometry placement %s"%[team,kinds[i]])
			var exit_point:=Vector2(-1,-1)
			if ok:
				var building:Dictionary=Classic.structures(fixture,team,kinds[i],false)[0]
				building.build_left=0;building.hp=building.max_hp
				exit_point=Classic.production_exit(fixture,building,"tank" if kinds[i]=="factory" else "harvester")
			check(exit_point.x>=0,"base %s facility exit %s"%[team,kinds[i]])
			results.append({"kind":kinds[i],"position":xy(sites[i]),"placed":ok,"exit":xy(exit_point)})
		report.base_packing.append({"team":team,"placements":results,"geometry_only_extra_funds":true})
	check(t.segment_clear(t.roads.nodes.industry_n,Vector2(108,54),"land",2.45),"authored freight centerline clears tank radius")
	check(sim.classic.fields[2].pos==Vector2(42,34) and sim.classic.fields[2].remaining==6000,"contested west deposit at (42,34), capacity preserved")
	check(t.roads.nodes.industry_n==Vector2(108,16) and t.roads.nodes.quay_n==Vector2(123,16),"newer north-road y16 preserved")
	check(t.blocks[11]==Rect2(112,63,8,8),"newer plot11 footprint preserved")
	for wet in [0.0,1.0]:
		for kind in ["rifle","tank","harvester"]:
			var samples:Array=report.routes.filter(func(r):return r.get("wetness",-1)==wet and r.kind==kind)
			var town:Dictionary=samples.filter(func(r):return r.label=="town")[0]
			var farm:Dictionary=samples.filter(func(r):return r.label=="western_farm")[0]
			var freight:Dictionary=samples.filter(func(r):return r.label=="eastern_freight")[0]
			if town.reachable and farm.reachable and freight.reachable:
				check(town.nominal_seconds<farm.nominal_seconds and town.nominal_seconds<freight.nominal_seconds,"town quickest intended route %s wet=%s"%[kind,wet])
				check(farm.cover_fraction>0.12,"western route has meaningful sampled cover %s wet=%s"%[kind,wet])
				check(freight.road_fraction>0.95,"freight route stays paved %s wet=%s"%[kind,wet])
	var contested:Array=report.routes.filter(func(r):return r.label.begins_with("field (42.0, 34.0)"))
	if contested.size()==2 and contested.all(func(r):return r.reachable):
		check(absf(contested[0].nominal_seconds-contested[1].nominal_seconds)<5.0,"western contested field approach difference below five nominal wet seconds")
	var hud_source:=FileAccess.get_file_as_string("res://scripts/hud.gd")
	report["integration_observations"]={"guide_still_has_five_entry_loop":hud_source.contains("for i in 5:"),"note":"Static selector observation is outside map acceptance; actual menu interaction is not tested here."}
	report["source_hashes"]={}
	for filename in ["scripts/terrain.gd","scripts/classic.gd","scripts/simulation.gd","scripts/roadside_props.gd","scripts/hud.gd"]:
		report.source_hashes[filename]=FileAccess.get_file_as_string("res://"+filename).sha256_text()
	check(report.source_hashes_at_start==report.source_hashes,"production source stable during map checks")
	report["command"]="./tools/play.sh --headless --log-file /tmp/ra-town-design.log --script tests/test_town_design.gd"
	report["native_inspection"]={"artifact":"artifacts/town-inspection-overview.png","visually_read":true,"fog_disabled":true,"new_native_run":false,"observations":"District silhouettes are discernible, but street-facing parcels remain separated from road edges by grass; overview crops base extremities and cannot establish build room or route access."}
	report["implemented_changes"]=[
		"Parcel 5 x99->97 and sedan (86,58)->(86,59.5) clear the freight/high-street overlaps.",
		"Width-5 south_cross->freight_south_turn (108,98); split yard->freight at that junction so named connectivity matches geometry. y98 avoids the reel near (103,94).",
		"Western woods [6,66,12,16] and [6,30,12,18]; authored footpath includes (12,84),(12,76),(12,36), continue via (12,28),(17,27),(17,4.5),(48,4.5),(48,14) around the north end of the existing woods; remove the obsolete (30,32)/(30,14) dogleg. Path is visual guidance, not a movement speed bonus or AI route mandate.",
		"6000-resource expansion moved (64,86)->(42,34) to reduce unequal approach times. Both 8000-resource starting deposits and eastern contest (93,51) retained.",
		"Preserved industry_n/quay_n y16, plot11 [112,63,8,8], newer northwest woods, districts and all other scenario content."
	]
	report["test_changes"]=["Replace hypothetical candidate override with actual authored map routes and assertions; compare parsed numeric coordinates as Vector2/Rect2, not JSON float arrays against integer arrays.","Follow authored western footpath and current road nodes instead of obsolete (10,84)/(108,14) waypoints.","Move geometry-fixture factory from (7,76), now a deliberate tree row, to (30,78); do not relax construction clearance.","Record five-entry menu as separate integration observation; source-string guard does not test map design or actual UI interaction.","Riverside suite is adapted in memory only to redirect its output to this owned report; all its assertions and simulation loops remain unchanged."]
	report.limitations.append("Road sweep samples cross-sections every 0.25 units at five lateral offsets; not an analytic capsule/corner proof.")
	report.limitations.append("No combat playthrough, tactical LOS comparison, air art clearance, menu click test or native performance acceptance. See riverside_navigation if present for actual moving deliveries and navigation.")
	report.limitations.append("Shared workspace changes concurrently. Source hashes identify inputs; screenshot reviewed earlier predates implemented corrections.")
	report["failures"]=failures
	if "--no-report" in OS.get_cmdline_user_args():
		print("FRONTAGE CORRECTION: ",JSON.stringify(report.frontage_correction))
		print("SCENARIO SHA256: ",report.scenario_sha256)
	else:
		FileAccess.open("res://artifacts/town-design-review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("TOWN DESIGN: ",report.checks.size()," checks; ",failures," failures")
	quit(0 if failures==0 else 1)

# Execute the existing owner's suite without writing its separately owned artifact.
# Adapt only SceneTree plumbing and report destination; retain assertions verbatim.
func run_riverside_suite()->void:
	var source:=FileAccess.get_file_as_string("res://tests/test_riverside_navigation.gd")
	var suite_hash:=source.sha256_text()
	var simulation_hash:=FileAccess.get_file_as_string("res://scripts/simulation.gd").sha256_text()
	var lines:=source.split("\n")
	for i in lines.size():
		if lines[i].contains('FileAccess.open("res://artifacts/riverside-navigation.json"'):
			var line:String=lines[i]
			var payload:=line.substr(line.find("{"),line.rfind("}")-line.find("{")+1)
			lines[i]='\tget_tree().set_meta("town_riverside_result",'+payload+')'
	source="\n".join(lines)
	source=source.replace("extends SceneTree", "extends Node\nvar root:Window:\n\tget:return get_tree().root")
	source=source.replace("quit(0 if failures==0 else 1)","finish_review(0 if failures==0 else 1)")
	source+='\nfunc finish_review(code:int)->void:\n\tvar report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/town-design-review.json"))\n\treport["riverside_navigation"]=get_tree().get_meta("town_riverside_result")\n\treport["riverside_navigation"]["scenario_sha256"]=FileAccess.get_file_as_string("res://resources/scenarios.json").sha256_text()\n\treport["riverside_navigation"]["simulation_sha256_at_start"]="'+simulation_hash+'"\n\treport["riverside_navigation"]["suite_sha256"]="'+suite_hash+'"\n\treport["riverside_navigation"]["command"]="./tools/play.sh --headless --log-file /tmp/ra-riverside-design.log --script tests/test_town_design.gd -- --riverside"\n\tFileAccess.open("res://artifacts/town-design-review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))\n\tget_tree().quit(code)\n'
	if "--no-report" in OS.get_cmdline_user_args():
		source=source.substr(0,source.find("\nfunc finish_review(code:int)->void:"))
		source+='\nfunc finish_review(code:int)->void:\n\tprint("RIVERSIDE RESULT: ",JSON.stringify(get_tree().get_meta("town_riverside_result")))\n\tprint("SCENARIO SHA256: ",FileAccess.get_file_as_string("res://resources/scenarios.json").sha256_text())\n\tget_tree().quit(code)\n'
	var script:=GDScript.new()
	script.source_code=source
	var error:=script.reload()
	if error!=OK:printerr("Riverside suite adapter failed: ",error);quit(1);return
	root.add_child(script.new())

# Focused attribution only: never writes artifacts or changes production data.
func restore_pre_frontage(t)->void:
	for item in [[0,34,40,7,7],[2,56,40,9,7],[8,56,62,9,7],[9,77,62,7,7]]:
		t.blocks[item[0]]=Rect2(item[1],item[2],item[3],item[4])
	t.navigation.clear()
	t.navigation_weights.clear()
func frontage_followup()->void:
	var before=Terrain.new(5);restore_pre_frontage(before)
	var after=Terrain.new(5)
	for radius in [2.45,2.65]:
		print("NORTH OFFSET BASELINE radius=",radius," old=",before.segment_clear(Vector2(34,52.5),Vector2(105,52.5),"land",radius)," new=",after.segment_clear(Vector2(34,52.5),Vector2(105,52.5),"land",radius))
		for offset in [0.0,0.5,1.0]:
			check(before.segment_clear(Vector2(34,54+offset),Vector2(105,54+offset),"land",radius),"baseline centre/south passing corridor")
			check(after.segment_clear(Vector2(34,54+offset),Vector2(105,54+offset),"land",radius),"corrected centre/south passing corridor")
	for original in [true,false]:
		var fixture=preload("res://tests/fixtures/legacy_riverside.gd").create(true)
		if original:restore_pre_frontage(fixture.terrain)
		fixture.classic.enemy_credits=5000
		var sites:Array=[Vector2(114,26),Vector2(98,6),Vector2(96,16),Vector2(122,26)]
		var kinds:Array=["refinery","power","barracks","factory"]
		for i in kinds.size():
			check(Classic.build(fixture,kinds[i],1,sites[i]),"attribution fixture construction")
			var building:Dictionary=Classic.structures(fixture,1,kinds[i],false)[0]
			building.build_left=0;building.hp=building.max_hp
		var factory:Dictionary=Classic.structures(fixture,1,"factory")[0]
		print("FACTORY EXIT original_frontages=",original," exit=",Classic.production_exit(fixture,factory,"tank"))
	# Reproduce only the failed economic fixture on pre-frontage terrain.
	# Same seed, placements, tick count and purchases as the already-run Riverside suite.
	var sim=preload("res://tests/fixtures/legacy_riverside.gd").create(true);restore_pre_frontage(sim.terrain)
	for team in 2:check(Classic.build(sim,"refinery",team,Vector2(6,86) if team==0 else Vector2(116,26)),"baseline economy refinery")
	sim.classic.ai_clock=100000;sim.classic.attack_clock=100000
	var originals:Array=sim.units.filter(func(u):return u.kind=="harvester").map(func(u):return u.id)
	var previous:Dictionary={};var deliveries:Dictionary={}
	for frame in 1800:
		sim.tick(0.1);sim.events.clear()
		for u in sim.units:
			if u.kind!="harvester":continue
			if previous.get(u.id,0.0)>100 and u.get("cargo",0.0)==0:deliveries[u.id]=deliveries.get(u.id,0)+1
			previous[u.id]=u.get("cargo",0.0)
		if frame==150:
			for team in 2:check(Classic.build(sim,"barracks",team,Classic.find_site(sim,"barracks",team)),"baseline barracks")
		if frame==400:
			for team in 2:check(Classic.enqueue(sim,"rifle",team),"baseline infantry queue")
		if frame==250:check(Classic.enqueue(sim,"harvester",0),"baseline harvester queue")
	print("BASELINE ECONOMY deliveries=",deliveries)
	for u in sim.units:
		if u.kind=="harvester" and u.id not in originals:print("BASELINE NEW HARVESTER pos=",u.pos," cargo=",u.get("cargo",0)," blocked=",u.blocked_time," deliveries=",deliveries.get(u.id,0))
	print("FRONTAGE FOLLOWUP: ",report.checks.size()," checks; ",failures," failures")
	quit(0 if failures==0 else 1)
