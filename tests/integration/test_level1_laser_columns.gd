## Level 1's laser columns as data (Enemy rework phase 8, t17; epic plan §2.16).
##
## `Level1Director.laser_column_schedule()` is the one place the column times and x positions live, and
## `_build_schedules()` binds every `_spawn_laser_columns` event to it. This file pins that the two agree, by
## reading the bound arguments back off a director built off-tree (no `_ready()`, no tree, no scene), so the
## measurement helper (`tests/helpers/level1_column_replay.gd`) and the level-1 placement task can trust the data.
extends GutTest

const DIRECTOR_SCRIPT: GDScript = preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")

## The numbers as the level shipped them before the schedule became data (plan §2.16): typed here on purpose, so
## editing the schedule without meaning to fails this row.
const SHIPPED_TIMES := {
	&"deep_space": [6.0, 14.0, 22.0],
	&"planet_approach": [10.0, 25.0, 38.0, 55.0, 78.0, 98.0],
	&"cloud_descent": [8.0, 18.0, 34.0],
}


func _bound_columns(director: Node) -> Dictionary:
	var out: Dictionary = {}
	var schedules: Dictionary = director._build_schedules()
	for section_name: StringName in schedules:
		var rows: Array = []
		for event: Dictionary in schedules[section_name]:
			var callable: Callable = event["callable"]
			if callable.get_method() != &"_spawn_laser_columns":
				continue
			var bound: Array = callable.get_bound_arguments()
			assert(bound.size() == 1)
			rows.append({"time": event["time"], "columns": bound[0]})
		out[section_name] = rows
	return out


func test_schedule_equals_the_bound_arguments_of_the_directors_spawn_callables() -> void:
	var director: Node = DIRECTOR_SCRIPT.new()
	var bound := _bound_columns(director)
	var data: Dictionary = DIRECTOR_SCRIPT.laser_column_schedule()
	director.free()

	assert_eq(bound.keys().size(), data.keys().size(), "same sections")
	for section_name: StringName in data:
		var want: Array = data[section_name]
		var got: Array = bound.get(section_name, [])
		assert_eq(got.size(), want.size(), "%s: one callable per row" % section_name)
		for i in mini(got.size(), want.size()):
			assert_eq(got[i]["time"], want[i]["time"], "%s row %d time" % [section_name, i])
			assert_eq(Array(got[i]["columns"]), Array(want[i]["columns"]), "%s row %d columns" % [section_name, i])


func test_schedule_keeps_the_shipped_times_and_column_counts() -> void:
	var data: Dictionary = DIRECTOR_SCRIPT.laser_column_schedule()
	var total_columns := 0
	for section_name: StringName in SHIPPED_TIMES:
		var times: Array = []
		for row: Dictionary in data[section_name]:
			times.append(row["time"])
			total_columns += (row["columns"] as Array).size()
		assert_eq(times, SHIPPED_TIMES[section_name], "%s times" % section_name)
	assert_eq(total_columns, 3 + 2 + 3 + 3 + 2 + 5 + 3 + 3 + 2 + 2 + 3 + 3, "34 columns in all")


func test_the_non_column_events_are_still_scheduled() -> void:
	var director: Node = DIRECTOR_SCRIPT.new()
	var schedules: Dictionary = director._build_schedules()
	director.free()
	var others := {}
	for section_name: StringName in schedules:
		var n := 0
		for event: Dictionary in schedules[section_name]:
			if (event["callable"] as Callable).get_method() != &"_spawn_laser_columns":
				n += 1
		others[section_name] = n
	assert_eq(others, {&"deep_space": 2, &"planet_approach": 3, &"cloud_descent": 1}, "drones and challenges kept")


# ── LaserRay.registers_hazard (plan §2.16 step 3) ────────────────────────────────────────────────────────────────
#
# Level 1's columns and its LaserWallWave kill AI enemies (measured, DECISIONS.md "Phase 8, built in t17"), so they opt
# in to being a `&"laser_wall"` hazard from warn start to the end of active. Driven by calling the phase steps directly
# (warn_duration 0 and no active_duration timer are created), so no SceneTreeTimer is left behind and no wall time passes.

const LASER_SCENE: PackedScene = preload("res://assault/scenes/hazards/laser_ray/laser_ray.tscn")
const WALL_SCENE: PackedScene = preload("res://assault/scenes/hazards/laser_ray/laser_wall.tscn")
## The ray's lit strip: 56 px wide, 12 tiles of 128 px; the registered radius is half the width plus the 24 px pad.
const BEAM_WIDTH := 56.0
const BEAM_LENGTH := 12.0 * 128.0
const PAD := 24.0


func _ray(registers: bool, at: Vector2 = Vector2(300.0, -380.0), rot: float = 0.0) -> LaserRay:
	var ray := LASER_SCENE.instantiate() as LaserRay
	ray.auto_start = false
	ray.warn_duration = 0.0
	ray.active_duration = 0.0
	ray.registers_hazard = registers
	add_child_autofree(ray)
	ray.global_position = at
	ray.global_rotation = rot
	return ray


func test_a_ray_registers_nothing_by_default() -> void:
	var before := Hazards.count()
	var ray := _ray(false)
	ray.start()
	assert_eq(Hazards.count(), before, "started")
	ray._begin_increase()
	ray._phase = LaserRay._Phase.IDLE
	assert_eq(Hazards.count(), before, "active")
	assert_null(ray.hazard_info(), "no info")
	ray.dissolve()
	assert_eq(Hazards.count(), before, "dissolving")


func test_an_opted_in_ray_registers_from_warn_start_to_the_end_of_active() -> void:
	var before := Hazards.count()
	var ray := _ray(true)
	assert_eq(Hazards.count(), before, "not before start()")
	ray.start()
	assert_eq(Hazards.count(), before + 1, "registered at warn start")
	ray._begin_increase()
	assert_eq(Hazards.count(), before + 1, "still registered while charging")
	ray._phase = LaserRay._Phase.IDLE
	assert_eq(Hazards.count(), before + 1, "still registered while active")
	ray.dissolve()
	assert_eq(Hazards.count(), before, "gone as the dissolve begins")


func test_the_registered_info_is_the_beams_long_axis() -> void:
	var ray := _ray(true, Vector2(300.0, -380.0))
	ray.start()
	var info := ray.hazard_info()
	assert_not_null(info, "info while registered")
	if info == null:
		return
	assert_eq(info.kind, &"laser_wall")
	assert_almost_eq(info.position, Vector2(300.0, -380.0 + BEAM_LENGTH * 0.5), Vector2(0.01, 0.01), "centre")
	assert_almost_eq(info.segment_half, Vector2(0.0, BEAM_LENGTH * 0.5), Vector2(0.01, 0.01), "half segment, downward")
	assert_almost_eq(info.radius, BEAM_WIDTH * 0.5 + PAD, 0.001, "half width + 24")
	assert_eq(info.avoid_weight, 1.0)
	assert_eq(info.pull_force, 0.0, "a wall has no pull")
	assert_eq(info.exempt_group, &"", "nothing is exempt from a column")
	assert_eq(info.source, ray)


func test_a_rotated_ray_registers_its_rotated_axis() -> void:
	var ray := _ray(true, Vector2(0.0, 0.0), PI * 0.5)
	ray.start()
	var info := ray.hazard_info()
	if info == null:
		fail_test("no info")
		return
	var want := Vector2.DOWN.rotated(PI * 0.5) * BEAM_LENGTH * 0.5
	assert_almost_eq(info.position, want, Vector2(0.01, 0.01), "centre")
	assert_almost_eq(info.segment_half, want, Vector2(0.01, 0.01), "half segment follows the rotation")


func test_a_registered_ray_leaves_the_registry_when_it_is_freed() -> void:
	var before := Hazards.count()
	var ray := _ray(true)
	ray.start()
	assert_eq(Hazards.count(), before + 1)
	ray.free()
	assert_eq(Hazards.count(), before, "freed mid-warning")


func test_a_lit_column_is_found_by_hazards_around() -> void:
	# The point of the registry entry: a lit column is something `Hazards.around()` finds, which is what avoidance reads.
	var ray := _ray(true, Vector2(300.0, -380.0))
	ray.start()
	var beside := Vector2(300.0 + BEAM_WIDTH * 0.5 + 10.0, 100.0)
	var found := Hazards.around(beside, 0.0)
	assert_eq(found.size(), 1, "10 px off the strip's edge is inside the footprint")
	assert_eq(Hazards.around(Vector2(300.0 + 200.0, 100.0), 0.0).size(), 0, "200 px away is clear")


func test_the_directors_columns_opt_in() -> void:
	var level := Node2D.new()
	add_child_autofree(level)
	var spawner := Node.new()
	level.add_child(spawner)
	# `set_script` on a node already in the tree runs no `_ready()`, which would want the level's exports.
	spawner.set_script(DIRECTOR_SCRIPT)
	var before := Hazards.count()
	spawner._spawn_laser_columns([200, 600], 0.0, 0.0)
	var rays: Array[LaserRay] = []
	for child in level.get_children():
		if child is LaserRay:
			rays.append(child)
	assert_eq(rays.size(), 2, "one ray per column")
	assert_eq(Hazards.count(), before + 2, "each column is in the registry while lit")
	for ray in rays:
		assert_true(ray.registers_hazard)
		ray.free()
	assert_eq(Hazards.count(), before)


func test_every_ray_of_the_static_laser_wall_opts_in() -> void:
	var state := WALL_SCENE.get_state()
	var rays := 0
	for i in state.get_node_count():
		if state.get_node_instance(i) == null:
			continue
		rays += 1
		var opted := false
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"registers_hazard":
				opted = bool(state.get_node_property_value(i, p))
		assert_true(opted, "%s registers_hazard" % state.get_node_name(i))
	assert_eq(rays, 12, "the LaserWallWave is 12 rays")
