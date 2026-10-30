extends RefCounted
# Local, user-requested diagnostics. No network, account identifiers or machine IDs.
const BUILD_PATH := "res://resources/build_info.json"

static func build_info() -> Dictionary:
	if FileAccess.file_exists(BUILD_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(BUILD_PATH))
		if parsed is Dictionary:
			return parsed
	return {"version":"development", "commit":"unknown", "channel":"development"}

static func label() -> String:
	var build := build_info()
	var revision := str(build.get("commit", "unknown")).left(8)
	return "%s · %s%s" % [build.get("version", "development"), revision, " (modified)" if build.get("dirty", false) else ""]

static func snapshot(sim, reason: String = "player-report") -> Dictionary:
	var report := {
		"schema":1, "reason":reason, "created_at_utc":Time.get_datetime_string_from_system(true),
		"build":build_info(), "engine":Engine.get_version_info().string,
		"os":OS.get_name(), "renderer":RenderingServer.get_current_rendering_method(),
		"graphics_adapter":RenderingServer.get_video_adapter_name(),
		"notice":"Local diagnostic snapshot. No automatic upload. Not a saved game or performance benchmark."
	}
	if sim == null:
		return report
	var objectives: Array = []
	for objective in sim.objectives:
		objectives.append({"name":objective.name, "owner":objective.owner,
			"progress":objective.progress, "contested":objective.get("contested", false),
			"enemy_present":objective.get("enemy_present", false)})
	var army_counts := [{}, {}]
	var own_commands: Array = []
	for unit in sim.units:
		if not sim.alive(unit):continue
		var counts: Dictionary = army_counts[int(unit.team)]
		counts[unit.kind] = int(counts.get(unit.kind, 0)) + 1
		if unit.team != 0 or own_commands.size() >= 48:continue
		var orders: Array = []
		for order in unit.orders.slice(0, 4):
			var destination: Vector2 = order.get("pos", unit.pos)
			orders.append({"mode":order.get("mode", ""), "destination":[destination.x, destination.y], "target_id":order.get("target", -1)})
		own_commands.append({"id":unit.id, "kind":unit.kind, "position":[unit.pos.x, unit.pos.y],
			"health":unit.hp, "state":unit.state, "reason":unit.get("reason", ""),
			"blocked_seconds":unit.get("blocked_time", 0.0), "route_points":unit.path.size(), "orders":orders,
			"order_version":unit.get("order_version",0), "assignment":unit.get("assignment",{}).get("id",0),
			"action_reason":unit.get("action_reason","ready"), "strength":sim.Infantry.strength(unit,sim.time)})
	report["mission"] = {"id":sim.scenario.get("id", ""), "seconds":sim.time, "result":sim.result,
		"supply":sim.credits, "hold_seconds":sim.score_hold, "kills":sim.kills, "losses":sim.losses,
		"objectives":objectives, "army_counts":army_counts, "own_commands":own_commands}
	report["tactics"]={"tick":sim.action_tick,"planning":sim.terrain.planning.snapshot(),
		"path_calls":sim.terrain.path_calls,"astar_searches":sim.terrain.astar_calls,
		"events":sim.actions.event_log.filter(func(event):return int(event.team)==0).slice(-64)}
	return report

static func write_report(sim, reason: String = "player-report", directory: String = "user://reports") -> Dictionary:
	var text := JSON.stringify(snapshot(sim, reason), "  ") + "\n"
	var absolute := ProjectSettings.globalize_path(directory)
	var error := DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK:
		return {"ok":false, "path":"", "text":text, "error":"Could not create report folder (%s)" % error}
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	var path := directory.path_join("for-every-dawn-%s-%d.json" % [stamp, Time.get_ticks_msec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok":false, "path":"", "text":text, "error":"Could not write report (%s)" % FileAccess.get_open_error()}
	file.store_string(text)
	file.flush()
	error = file.get_error()
	file.close()
	return {"ok":error == OK, "path":ProjectSettings.globalize_path(path), "text":text,
		"error":"" if error == OK else "Report write failed (%s)" % error}
