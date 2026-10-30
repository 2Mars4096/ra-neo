extends SceneTree
const Info = preload("res://scripts/release_info.gd")
const Sim = preload("res://scripts/simulation.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _init() -> void:
	var sim = Sim.new(true, Sim.default_selection())
	var state := var_to_str([sim.units, sim.credits, sim.time, sim.result, sim.combat_rng.state])
	var report := Info.snapshot(sim, "test")
	check(report.mission.id == "black_sea_harbor", "report identifies the active Harbor")
	# A source checkout has no generated release metadata. Do not label it as
	# an exported playtest build merely to satisfy a historical fixture.
	if FileAccess.file_exists(Info.BUILD_PATH):
		var metadata=JSON.parse_string(FileAccess.get_file_as_string(Info.BUILD_PATH))
		check(metadata is Dictionary and report.build==metadata,"generated build metadata is preserved")
	else:
		check(report.build.version=="development" and report.build.commit=="unknown" and report.build.channel=="development","source checkout reports its honest development fallback")
	check(not Info.label().is_empty(), "version label is available")
	check(report.mission.objectives.size() == 3, "all objectives included")
	check(not report.mission.own_commands.is_empty(), "own commands help reproduce stuck orders")
	check(report.mission.own_commands.size() <= 48, "report size bounded")
	check(report.tactics.tick==sim.action_tick and report.tactics.events.size()<=64,"tactical diagnostics are current and bounded")
	check(report.tactics.planning.has("limits") and report.tactics.has("astar_searches"),"planning admission and actual search counts are separate")
	check(report.mission.own_commands.all(func(command):return command.has("order_version") and command.has("assignment") and command.has("strength")),"command ownership and casualty strength accompany action reasons")
	check(report.tactics.events.all(func(event):return int(event.team)==0),"action trace contains only own-team events")
	check(not report.has("environment") and not report.has("machine_id"), "no environment or persistent machine identifier")
	check(state == var_to_str([sim.units, sim.credits, sim.time, sim.result, sim.combat_rng.state]), "report never changes the match")
	var saved := Info.write_report(sim, "test", "res://artifacts/report-test")
	check(saved.ok and FileAccess.file_exists(saved.path), "report written to a portable writable path")
	if saved.ok:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(saved.path))
		check(parsed is Dictionary and parsed.mission.id == "black_sea_harbor", "report round trips as JSON")
		DirAccess.remove_absolute(saved.path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://artifacts/report-test"))
	var refused := Info.write_report(sim, "test", "res://project.godot/not-a-directory")
	check(not refused.ok and not refused.text.is_empty() and not refused.error.is_empty(), "filesystem failure preserves copyable diagnostic text")
	print("RELEASE INFO: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
