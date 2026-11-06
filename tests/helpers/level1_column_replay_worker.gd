## Manually-run measurement: how many AI enemies die in level 1's laser columns (Enemy rework phase 8, t17; epic plan
## docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.16). NOT a GUT test (no `test_` prefix, so GUT never runs it, and
## GUT time is precious); `scripts/measure-level1-columns.sh` runs it headless:
##
##     godot --headless --path . -s tests/helpers/level1_column_replay.gd [-- <section> …]
##
## It replays each of level 1's three column sections (`deep_space`, `planet_approach`, `cloud_descent`; or the ones named
## after `--`) through a real `WaveManager` in the Assault harness (a real `ArenaCamera`, so the corridor and the world
## rect are live; a stationary, hurtbox-less player stub at the lower centre of the view; every brain seeded from its
## spawn index before its `_ready()`), at an 8x clock with the physics step kept at 1/60 game-second. The column schedule is
## `Level1Director.laser_column_schedule()`, lit by the director's own `_spawn_laser_columns()` (so a change to how it
## builds a `LaserRay`, e.g. the `registers_hazard` opt-in, is what gets measured), at the section-relative times the real
## `_process` uses. `deep_space` also lights `level_1.tscn`'s static 12-ray `LaserWallWave` at t = 0, as the level does.
##
## For every AI enemy (a `BaseEnemy` with a `Brain`) it counts, per section, per source (`columns` / `wall_wave`: the ray's
## owner) and per kind (the enemy scene's file name):
##   spawned  - entered the container;
##   exposed  - at least once, with its origin inside the lit (lethal) hit rect of a ray;
##   killed   - `died` fired with its origin inside a lit ray's hit rect (nothing shoots in this world, so a 9999-damage
##              ray is the only thing that can kill one there; a hull rule that refuses the hit shows as exposed > killed).
## Output: one `RESULT <section> <source> <kind> spawned=N exposed=N killed=N` line per kind that was exposed, a
## `TOTAL <section> spawned=N exposed=N killed=N` line per section, and a final `DONE`. Exit code 0.
##
## The worker half of the helper: `level1_column_replay.gd` (a SceneTree script) adds this node once the autoloads exist. No `class_name`.
extends Node

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const DIRECTOR_SCRIPT: GDScript = preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")
const WALL_SCENE: PackedScene = preload("res://assault/scenes/hazards/laser_ray/laser_wall.tscn")

const SPEEDUP := 8
const SEED_BASE := 8101
const SECTIONS: Array[StringName] = [&"deep_space", &"planet_approach", &"cloud_descent"]
## Where level_1.tscn puts its LaserWallWave.
const WALL_POSITION := Vector2(0.0, -380.0)
## Run this long past the last column's active phase and the last spawn timer so nothing unfired is left behind.
const TAIL := 2.0
## A ray's hit rect is grown by this (px) before the "origin inside it" test: the origin of a ship is its centre.
const REACH_PAD := 0.0

var _rays: Array[LaserRay] = []
var _container: Node2D = null
var _spawned := 0
## Per kind: spawned / exposed / killed, keyed `"<source>|<kind>"` for the latter two.
var _spawn_counts: Dictionary = {}
var _exposed: Dictionary = {}
var _killed: Dictionary = {}
var _exposed_ids: Dictionary = {}
var _killed_ids: Dictionary = {}
var _live: Array[BaseEnemy] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var wanted: Array[StringName] = []
	for arg in OS.get_cmdline_user_args():
		wanted.append(StringName(arg))
	if wanted.is_empty():
		wanted = SECTIONS
	var saved_scale := Engine.time_scale
	var saved_ticks := Engine.physics_ticks_per_second
	var saved_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = saved_ticks * SPEEDUP
	Engine.max_physics_steps_per_frame = saved_steps * SPEEDUP
	Engine.time_scale = saved_scale * SPEEDUP

	var director: Node = DIRECTOR_SCRIPT.new()
	var sections: Array = director._build_sections()
	var schedule: Dictionary = DIRECTOR_SCRIPT.laser_column_schedule()
	for section_name in wanted:
		var section: LevelSection = null
		for s in sections:
			if (s as LevelSection).section_name == section_name:
				section = s
		if section == null:
			printerr("unknown section %s" % section_name)
			continue
		await _replay(section, schedule.get(section_name, []), section_name == &"deep_space")
	director.free()

	Engine.time_scale = saved_scale
	Engine.physics_ticks_per_second = saved_ticks
	Engine.max_physics_steps_per_frame = saved_steps
	print("DONE")
	get_tree().quit(0)


func _replay(section: LevelSection, columns: Array, with_wall: bool) -> void:
	_rays.clear()
	_live.clear()
	_spawn_counts = {}
	_exposed = {}
	_killed = {}
	_exposed_ids = {}
	_killed_ids = {}
	_spawned = 0

	var harness: RefCounted = HARNESS.assault()
	get_tree().root.add_child(harness.root)
	var cam := harness.root.get_node("ArenaCamera") as Camera2D
	cam.make_current()
	harness.player.global_position = cam.global_position + Vector2(0.0, 250.0)
	_container = Node2D.new()
	_container.name = "EnemyContainer"
	harness.root.add_child(_container)
	_container.child_entered_tree.connect(_on_container_child_entered)
	get_tree().node_added.connect(_on_node_added)

	# The real `_spawn_laser_columns()`: it only needs a parent to add the rays to. `set_script` on a node already in
	# the tree does not run `_ready()` (which would want the level's exports).
	var spawner := Node.new()
	harness.root.add_child(spawner)
	spawner.set_script(DIRECTOR_SCRIPT)

	var wm := WaveManager.new()
	wm.enemy_container = _container
	harness.root.add_child(wm)

	for i in 3:
		await get_tree().process_frame
	if with_wall:
		var wall := WALL_SCENE.instantiate() as Node2D
		wall.position = WALL_POSITION
		harness.root.add_child(wall)
	wm.load_section(section.waves)

	var last_trigger := 0.0
	for w in section.waves:
		last_trigger = maxf(last_trigger, (w as WaveResource).trigger_time)
	var length := section.duration
	if section.end_condition != LevelSection.EndCondition.DURATION:
		length = last_trigger + section.enemies_cleared_timeout
	var last_column := 0.0
	for row in columns:
		last_column = maxf(last_column, float(row["time"]))
	length = maxf(length, last_column + 7.0) + TAIL

	var pending: Array = columns.duplicate()
	var t := 0.0
	while t < length:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var i := 0
		while i < pending.size():
			if t >= float(pending[i]["time"]):
				spawner._spawn_laser_columns(pending[i]["columns"])
				pending.remove_at(i)
			else:
				i += 1
		_poll_exposure()

	wm.set_process(false)
	# Let every already-triggered spawn timer fire (an unfired SceneTreeTimer is reported as a leak at exit).
	var settle := 0.0
	while settle < 2.5:
		await get_tree().physics_frame
		settle += 1.0 / 60.0
	get_tree().node_added.disconnect(_on_node_added)
	_container.child_entered_tree.disconnect(_on_container_child_entered)
	_report(section.section_name)
	harness.root.queue_free()
	await get_tree().process_frame


func _on_node_added(node: Node) -> void:
	if node is LaserRay:
		_rays.append(node)


func _on_container_child_entered(node: Node) -> void:
	if not node is BaseEnemy:
		return
	var brain := node.get_node_or_null("Brain") as EnemyBrain
	if brain == null:
		return
	brain.rng_seed = SEED_BASE + _spawned
	_spawned += 1
	var kind := _kind_of(node)
	_spawn_counts[kind] = int(_spawn_counts.get(kind, 0)) + 1
	_live.append(node)
	node.died.connect(_on_enemy_died.bind(node))


func _kind_of(node: Node) -> String:
	return node.scene_file_path.get_file().get_basename()


## The source label of the lit ray that covers `pos`, or "" when none does.
func _covering_source(pos: Vector2) -> String:
	for ray in _rays:
		if not is_instance_valid(ray) or not ray.is_lethal_now():
			continue
		if ray.danger_rect().grow(REACH_PAD).has_point(pos):
			# `LaserWallWave`'s rays sit under a plain "LaserWall" Node2D; the director's columns under the level root.
			return "wall_wave" if ray.get_parent() != null and ray.get_parent().scene_file_path.ends_with("laser_wall.tscn") else "columns"
	return ""


func _poll_exposure() -> void:
	var i := 0
	while i < _live.size():
		var e := _live[i]
		if not is_instance_valid(e) or not e.is_inside_tree():
			_live.remove_at(i)
			continue
		var source := _covering_source(e.global_position)
		if source != "" and not _exposed_ids.has(_exposure_id(e, source)):
			_exposed_ids[_exposure_id(e, source)] = true
			var key := "%s|%s" % [source, _kind_of(e)]
			_exposed[key] = int(_exposed.get(key, 0)) + 1
		i += 1


func _on_enemy_died(enemy: BaseEnemy) -> void:
	var source := _covering_source(enemy.global_position)
	if source == "":
		return
	var key := "%s|%s" % [source, _kind_of(enemy)]
	# `died` can fire again while a lit ray keeps re-hitting a ship that is already dying: count each ship once.
	if not _killed_ids.has(_exposure_id(enemy, source)):
		_killed_ids[_exposure_id(enemy, source)] = true
		_killed[key] = int(_killed.get(key, 0)) + 1
	if not _exposed_ids.has(_exposure_id(enemy, source)):
		_exposed_ids[_exposure_id(enemy, source)] = true
		_exposed[key] = int(_exposed.get(key, 0)) + 1


func _report(section_name: StringName) -> void:
	var total_exposed := 0
	var total_killed := 0
	var keys: Array = _exposed.keys()
	for k in _killed.keys():
		if not keys.has(k):
			keys.append(k)
	keys.sort()
	for key: String in keys:
		var parts := key.split("|")
		var ex := int(_exposed.get(key, 0))
		var ki := int(_killed.get(key, 0))
		total_exposed += ex
		total_killed += ki
		print("RESULT %s %s %s spawned=%d exposed=%d killed=%d"
			% [section_name, parts[0], parts[1], int(_spawn_counts.get(parts[1], 0)), ex, ki])
	var spawned := 0
	for k in _spawn_counts:
		spawned += int(_spawn_counts[k])
	print("TOTAL %s spawned=%d exposed=%d killed=%d" % [section_name, spawned, total_exposed, total_killed])


## One exposure per enemy per source: an enemy crossing a column and later the wall wave is exposed to both.
func _exposure_id(enemy: Node, source: String) -> String:
	return "%d|%s" % [enemy.get_instance_id(), source]
