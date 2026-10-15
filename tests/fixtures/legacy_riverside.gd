extends RefCounted
# Frozen former economy fixture, not a selectable/current battlefield mode.
static func create(populate:bool=true):
	var sim=preload("res://scripts/simulation.gd").new(false,4)
	sim.scenario=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/riverside_classic.json"))
	sim.terrain=preload("res://scripts/terrain.gd").new(5)
	sim.terrain.poles.clear();sim.objectives.clear()
	sim.classic={}
	sim.Classic.setup(sim)
	if populate:sim.Classic.populate(sim)
	sim.update_visibility()
	return sim
