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
	check(report.build.version == "0.1.0-playtest", "source build has a version")
	check(not Info.label().is_empty(), "version label is available")
	check(report.mission.objectives.size() == 3, "all objectives included")
	check(not report.mission.own_commands.is_empty(), "own commands help reproduce stuck orders")
	check(report.mission.own_commands.size() <= 48, "report size bounded")
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
