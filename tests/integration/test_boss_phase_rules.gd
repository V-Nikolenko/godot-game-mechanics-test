## INTENT gate for IDEAS §25 (boss phase rules), Phase 11 t1 (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.1): every phase of a boss ladder
## after the first changes at least two of movement, attacks, vulnerable areas, arena control, reinforcements and visuals.
##
## It sweeps every `.tscn` under `assault/` and `open_space/` whose `SceneState` has a node scripted with `BossPhaseDriver`, instantiates each
## in a scratch tree (the driver's `validate(hull)` reads the live `ModularHull`) and asserts `validate()` returns nothing. The shipped boss
## scene since t5 is `space_fortress.tscn`: the sweep must find it (a broken sweep that finds nothing fails), and the synthetic boundary below proves
## the check can reject.
extends GutTest

const DRIVER_SCRIPT := "res://global/boss/boss_phase_driver.gd"
const ROOTS := ["res://assault", "res://open_space"]
const FORTRESS_SCENE := "res://assault/scenes/enemies/space_fortress/space_fortress.tscn"
const HOST_SCENE: PackedScene = preload("res://tests/helpers/fixture_modular_host.tscn")


func _scenes_under(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scenes_under(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			out.append(dir_path.path_join(file))


## True when [param state] has a node whose script is the driver's.
func _has_driver(state: SceneState) -> bool:
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"script":
				var script := state.get_node_property_value(i, p) as Script
				if script != null and script.resource_path == DRIVER_SCRIPT:
					return true
	return false


func _boss_scenes() -> Array[String]:
	var all: Array[String] = []
	for root in ROOTS:
		_scenes_under(root, all)
	all.sort()
	var found: Array[String] = []
	for path in all:
		# A text pre-filter: loading every scene under `assault/` costs ~1.9 s of the gate; only a scene that names the driver script is loaded.
		if not FileAccess.get_file_as_string(path).contains(DRIVER_SCRIPT):
			continue
		var scene := load(path) as PackedScene
		if scene != null and _has_driver(scene.get_state()):
			found.append(path)
	return found


func _drivers_of(node: Node, out: Array[BossPhaseDriver]) -> void:
	if node is BossPhaseDriver:
		out.append(node)
	for child in node.get_children():
		_drivers_of(child, out)


func _hull_of(node: Node) -> ModularHull:
	for child in node.get_children():
		if child is ModularHull:
			return child
	return null


func test_every_shipped_boss_ladder_changes_at_least_two_aspects_per_phase() -> void:
	var scenes := _boss_scenes()
	gut.p("boss scenes holding a BossPhaseDriver: %d" % scenes.size())
	assert_has(scenes, FORTRESS_SCENE, "the sweep finds the Space Fortress (Phase 11 t5)")
	for path in scenes:
		var inst := (load(path) as PackedScene).instantiate()
		add_child_autofree(inst)
		var drivers: Array[BossPhaseDriver] = []
		_drivers_of(inst, drivers)
		assert_gt(drivers.size(), 0, "%s: a driver is in the instantiated tree" % path)
		for d in drivers:
			var hull := _hull_of(d.get_parent())
			assert_not_null(hull, "%s: the driver's host has a ModularHull to validate against" % path)
			assert_eq(d.validate(hull), PackedStringArray(), "%s: the ladder validates" % path)


func test_a_scene_with_a_driver_is_found_by_the_sweep() -> void:
	var state := _scene_with_driver().get_state()
	assert_true(_has_driver(state), "a scene state holding a PhaseDriver node is recognised")
	assert_false(_has_driver(HOST_SCENE.get_state()), "and one without is not")


func _scene_with_driver() -> PackedScene:
	var host := HOST_SCENE.instantiate()
	var d := BossPhaseDriver.new()
	d.name = "PhaseDriver"
	host.add_child(d)
	d.owner = host
	var scene := PackedScene.new()
	assert_eq(scene.pack(host), OK)
	host.free()
	return scene


func test_a_synthetic_ladder_with_a_one_change_phase_fails_validate() -> void:
	var host := HOST_SCENE.instantiate()
	add_child_autofree(host)
	var start := BossPhase.new()
	start.phase_id = &"start"
	start.trigger = BossPhase.Trigger.START
	var weak := BossPhase.new()
	weak.phase_id = &"weak"
	weak.trigger = BossPhase.Trigger.PARTS_DESTROYED
	weak.count = 1
	weak.changes = BossPhase.Change.ATTACKS
	var d := BossPhaseDriver.new()
	d.phases = [start, weak] as Array[BossPhase]
	autofree(d)
	var errors := d.validate(host.get_node("ModularHull") as ModularHull)
	assert_eq(errors.size(), 1, "exactly the one-change phase is rejected: %s" % ["; ".join(errors)])
	weak.changes = BossPhase.Change.ATTACKS | BossPhase.Change.VISUALS
	assert_eq(d.validate(host.get_node("ModularHull") as ModularHull).size(), 0, "two changes pass")
