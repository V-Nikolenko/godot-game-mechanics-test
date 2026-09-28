## t15 (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.6 "Integration case", review N1): cloud_descent
## is an ENEMIES_CLEARED section, so `LevelDirector._wait_enemies_cleared` starts a
## `enemies_cleared_timeout` clock the moment its LAST wave triggers (`waves_complete`). With rails off,
## nothing culls a drone at the screen edge any more: each one must fight, let its `EngagementBudget`
## expire, and fly out of the world rect by itself (`SwarmDroneBrain` DISENGAGE) before that clock runs
## out, or the level stalls to its forced-free fallback.
##
## `test_engagement_deadline.gd` proves this on paper. This file runs it: the real last wave, through a
## real `WaveManager`, under a real `ArenaCamera` (the corridor constraint and the world rect both come
## from it), against a stationary player stub with no hurtbox — the worst case, since no drone can
## end early by ramming it.
##
## "Left in time" is not enough on its own: today's rail drones were also gone in ~7 s, culled by
## `EnemyPathMover`. So every drone must also leave **in DISENGAGE and with no `EnemyPathMover`** — the
## way only the rails-off AI can — which is what keeps this red on a build that re-adds `.move()`.
##
## Time is game time (summed physics delta), never wall-clock: `WaveManager`'s clock and its delay
## timers run on game time, and a loaded machine stretches wall-clock against it.
extends GutTest

const HARNESS := preload("res://tests/helpers/enemy_ai_harness.gd")
const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")

## Longer than the wave's largest `delay()` (0.8 s), so every WaveManager spawn timer has fired
## before a test returns — an unfired SceneTreeTimer is reported as a leak at process exit.
const _MIN_RUN_SECONDS := 1.0

var _harness: RefCounted
var _container: Node2D
var _wave_manager: WaveManager
var _spawned: int = 0
var _waves_done: bool = false
## One entry per drone that left the tree: { "phase": int, "path_mover": bool }. Held on the test
## object, never on a node, so a late callback during teardown writes into live state.
var _exits: Array[Dictionary] = []
var _recording: bool = false


func before_each() -> void:
	_spawned = 0
	_waves_done = false
	_exits = []
	_recording = true


func after_each() -> void:
	_recording = false


func _cloud_descent() -> LevelSection:
	var d: Node = DIRECTOR_SCRIPT.new()
	autofree(d)
	for s in d._build_sections():
		var section: LevelSection = s
		if section.section_name == &"cloud_descent":
			return section
	return null


func _last_wave(section: LevelSection) -> WaveResource:
	var last: WaveResource = null
	for w in section.waves:
		var wave: WaveResource = w
		if last == null or wave.trigger_time > last.trigger_time:
			last = wave
	return last


## The world: harness (player stub + ArenaCamera), an enemy container and a WaveManager fed `wave`
## re-timed to trigger at once.
func _run(wave: WaveResource) -> void:
	_harness = HARNESS.assault()
	add_child_autofree(_harness.root)
	var cam := _harness.root.get_node("ArenaCamera") as Camera2D
	cam.make_current()
	# Lower centre of the view, stationary. No hurtbox: nothing can detonate on it.
	_harness.player.global_position = cam.global_position + Vector2(0.0, 250.0)

	_container = Node2D.new()
	_container.name = "EnemyContainer"
	_harness.root.add_child(_container)

	_wave_manager = WaveManager.new()
	_wave_manager.enemy_container = _container
	_harness.root.add_child(_wave_manager)
	_wave_manager.enemy_spawned.connect(_on_enemy_spawned)
	_wave_manager.waves_complete.connect(func() -> void: _waves_done = true)

	var retimed := WaveResource.new()
	retimed.trigger_time = 0.0
	retimed.entries = wave.entries
	var waves: Array[WaveResource] = [retimed]
	_wave_manager.load_section(waves)


func _on_enemy_spawned(enemy: Node, _wave_index: int) -> void:
	if not enemy is SwarmDrone:
		return
	_spawned += 1
	enemy.tree_exiting.connect(_on_drone_exiting.bind(enemy))


func _on_drone_exiting(drone: Node) -> void:
	if not _recording:
		return
	var has_path_mover := false
	for child in drone.get_children():
		if child is EnemyPathMover:
			has_path_mover = true
	var brain := drone.get_node_or_null("Brain") as SwarmDroneBrain
	_exits.append({"phase": brain.phase if brain else -1, "path_mover": has_path_mover})


func _swarm_drones_alive() -> int:
	var n := 0
	for child in _container.get_children():
		if child is SwarmDrone and not child.is_queued_for_deletion():
			n += 1
	return n


func _expected_drone_count(wave: WaveResource) -> int:
	var n := 0
	for e in wave.entries:
		var entry: SpawnEntryResource = e
		if entry.ship_scene == null or entry.ship_scene.resource_path != WaveBuilder.DRONE:
			continue
		n += entry.formation.compute_slots().size() if entry.formation else 1
	return n


## Advances physics frames until `seconds` of game time have passed, or `stop` returns true (only
## checked after `_MIN_RUN_SECONDS`). Returns the game time elapsed.
func _advance(seconds: float, stop: Callable) -> float:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if elapsed >= _MIN_RUN_SECONDS and stop.call():
			break
	return elapsed


func test_cloud_descents_last_wave_leaves_under_ai_before_the_timeout() -> void:
	var section := _cloud_descent()
	assert_not_null(section, "sanity: level 1 has a cloud_descent section")
	if section == null:
		return
	assert_eq(section.end_condition, LevelSection.EndCondition.ENEMIES_CLEARED, "sanity")
	var wave := _last_wave(section)
	var expected := _expected_drone_count(wave)
	assert_gt(expected, 0, "sanity: cloud_descent's last wave spawns Swarm Drones")

	_run(wave)
	var timeout := section.enemies_cleared_timeout
	var elapsed: float = await _advance(timeout, func() -> bool:
		return _waves_done and _spawned == expected and _swarm_drones_alive() == 0)
	_recording = false

	assert_true(_waves_done, "the wave must have triggered")
	assert_eq(_spawned, expected, "every drone of the wave must have spawned")
	assert_eq(_swarm_drones_alive(), 0,
		"%d Swarm Drone(s) still in the container after %.2f s, timeout %.1f s"
			% [_swarm_drones_alive(), elapsed, timeout])
	assert_lt(elapsed, timeout, "the container must empty BEFORE enemies_cleared_timeout")
	gut.p("cloud_descent last wave cleared in %.2f s of game time (timeout %.1f s)" % [elapsed, timeout])

	assert_eq(_exits.size(), expected, "every drone's exit must have been recorded")
	for i in _exits.size():
		var exit: Dictionary = _exits[i]
		assert_false(exit["path_mover"], "drone %d left on a rail (EnemyPathMover), not under AI" % i)
		assert_eq(int(exit["phase"]), int(SwarmDroneBrain.Phase.DISENGAGE),
			"drone %d left in phase %d, not DISENGAGE" % [i, int(exit["phase"])])


## Boundary: the same wave with `.move()` put back is rejected by the same predicate the main case
## relies on — every drone flies under an `EnemyPathMover`. Duplicated entries: the section's own
## resources are never mutated. ~1 s long; teardown frees the rail drones with recording off.
func test_a_rail_driven_last_wave_is_rejected() -> void:
	var section := _cloud_descent()
	if section == null:
		fail_test("no cloud_descent section")
		return
	var wave := _last_wave(section)
	var railed := WaveResource.new()
	var entries: Array[SpawnEntryResource] = []
	for e in wave.entries:
		var copy := (e as SpawnEntryResource).duplicate() as SpawnEntryResource
		copy.movement = StraightMovement.new()
		entries.append(copy)
	railed.entries = entries

	_run(railed)
	await _advance(_MIN_RUN_SECONDS, func() -> bool: return true)
	_recording = false

	var drones := 0
	for child in _container.get_children():
		if not child is SwarmDrone:
			continue
		drones += 1
		var has_path_mover := false
		for c in child.get_children():
			if c is EnemyPathMover:
				has_path_mover = true
		assert_true(has_path_mover, "a .move() drone must carry an EnemyPathMover, which the main case rejects")
	assert_eq(drones, _expected_drone_count(wave), "sanity: the rail wave spawned")
