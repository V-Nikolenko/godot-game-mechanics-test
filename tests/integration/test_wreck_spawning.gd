## INTENT tests for wrecks left by destroyed ships (plan §2.9, docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md):
## a mover-driven enemy that dies sometimes leaves a `Wreck` in the level's `HazardContainer` — never in the enemy
## container (which holds an `ENEMIES_CLEARED` section open), never in group `enemies`, drawing its roll from the
## brain's seeded rng and only when there is a container to put the wreck in. The alive cap (Assault 4, Open Space 8)
## retires the oldest wreck, also when several ships die in one frame.
##
## Dual-mode rows run in both harnesses (`use_parameters`). The kill is `health.decrease(...)` outside a physics flush,
## with the enemy's own tick switched off; ONE row (`test_a_real_bullet_kill_leaves_exactly_one_wreck`) runs real physics
## on the 8× clock, because a real kill happens inside the bullet's `area_entered` flush, where adding a body
## synchronously is an engine error (GUT fails the test on one). The level-1 exit guard lives in
## `test_level1_fighter_exit.gd`.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SWARM_SCENE: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

const _MODES := ["open_space", "assault"]
const _CAP := {"open_space": 8, "assault": 4}
const _SPEEDUP: int = 8

## [config path, wreck_chance, wreck_size] — plan §2.9.
const _CONFIGS := [
	["res://assault/scenes/enemies/swarm_drone/swarm_drone_config.tres", 0.0, 0],
	["res://assault/scenes/enemies/razor_drone/razor_drone_config.tres", 0.0, 0],
	["res://assault/scenes/enemies/fighter/fighter_config.tres", 0.2, 0],
	["res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor_config.tres", 0.2, 0],
	["res://assault/scenes/enemies/sniper/sniper_config.tres", 0.3, 0],
	["res://assault/scenes/enemies/support_ship/support_ship_config.tres", 0.3, 0],
	["res://assault/scenes/enemies/missile_corvette/missile_corvette_config.tres", 0.5, 1],
	["res://assault/scenes/enemies/ram_corvette/ram_corvette_config.tres", 0.5, 1],
	["res://assault/scenes/enemies/bomber/bomber_config.tres", 0.6, 2],
]

var _clock_scaled: bool = false
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8

var _h
var _hazards: Node2D
var _enemies: Node2D


func after_each() -> void:
	_restore_clock()


func _scale_clock() -> void:
	if _clock_scaled:
		return
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	_clock_scaled = true
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP


func _restore_clock() -> void:
	if not _clock_scaled:
		return
	_clock_scaled = false
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


## A harness plus a `HazardContainer` (group `hazard_container`) and a separate enemy container.
func _build(mode: String, with_hazard_container: bool = true) -> void:
	_h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(_h.root)
	_enemies = Node2D.new()
	_enemies.name = "EnemyContainer"
	_h.root.add_child(_enemies)
	_hazards = null
	if with_hazard_container:
		_hazards = Node2D.new()
		_hazards.name = "HazardContainer"
		_hazards.add_to_group(Hazards.CONTAINER_GROUP)
		_h.root.add_child(_hazards)


func _drone(at: Vector2, chance: float, seed_value: int = 11, size: int = 0) -> SwarmDrone:
	var d := SWARM_SCENE.instantiate() as SwarmDrone
	d.config.wreck_chance = chance
	d.config.wreck_size = size
	(d.get_node("Brain") as EnemyBrain).rng_seed = seed_value
	d.global_position = at
	_enemies.add_child(d)
	d.set_physics_process(false)
	return d


func _kill(d: BaseEnemy) -> void:
	d.health.decrease(d.health.current_health)


## Lets the deferred `spawn_into` attaches run.
func _flush() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _wrecks() -> Array[Wreck]:
	var out: Array[Wreck] = []
	if _hazards == null:
		return out
	for c in _hazards.get_children():
		if c is Wreck:
			out.append(c)
	return out


func _alive_wrecks() -> Array[Wreck]:
	var out: Array[Wreck] = []
	for w in _wrecks():
		if not w.is_retiring():
			out.append(w)
	return out


func test_the_shipped_configs_carry_the_plan_chances_and_sizes() -> void:
	for row in _CONFIGS:
		var cfg := load(row[0]) as ShipConfig
		assert_not_null(cfg, row[0])
		assert_almost_eq(cfg.wreck_chance, float(row[1]), 0.0001, "%s wreck_chance" % row[0])
		assert_eq(cfg.wreck_size, int(row[2]), "%s wreck_size" % row[0])


func test_the_defaults_leave_no_wreck() -> void:
	var cfg := ShipConfig.new()
	assert_eq(cfg.wreck_chance, 0.0)
	assert_eq(cfg.wreck_size, 0)


func _kill_run(mode: String, kills: int, chance: float, seed_value: int) -> Array:
	_build(mode)
	var spawned: Array = []
	_hazards.child_entered_tree.connect(func(n: Node) -> void:
		if n is Wreck:
			spawned.append(n.global_position))
	for i in kills:
		var at := Vector2(100.0 + 40.0 * i, 200.0)
		var d := _drone(at, chance, seed_value + i)
		_kill(d)
		await _flush()
	_h.root.queue_free()
	await get_tree().process_frame
	return spawned


func test_the_same_seed_leaves_the_same_wrecks_over_20_kills(mode: String = use_parameters(_MODES)) -> void:
	var first: Array = await _kill_run(mode, 20, 0.5, 40)
	var second: Array = await _kill_run(mode, 20, 0.5, 40)
	assert_gt(first.size(), 0, "sanity: some of 20 kills at 50 %% leave a wreck")
	assert_lt(first.size(), 20, "sanity: and not every one does")
	assert_eq(first, second, "%s: same seeds, same wrecks at the same places" % mode)
	var other: Array = await _kill_run(mode, 20, 0.5, 9000)
	assert_ne(first, other, "%s: different seeds roll differently" % mode)


func test_chance_zero_leaves_none(mode: String = use_parameters(_MODES)) -> void:
	_build(mode)
	for i in 10:
		_kill(_drone(Vector2(100.0 + 40.0 * i, 200.0), 0.0, 5 + i))
	await _flush()
	assert_eq(_wrecks().size(), 0, "%s: chance 0 never leaves a wreck" % mode)


func test_no_container_leaves_no_wreck_and_draws_no_rng(mode: String = use_parameters(_MODES)) -> void:
	_build(mode, false)
	var dying := _drone(Vector2(300.0, 200.0), 1.0, 77)
	var control := _drone(Vector2(500.0, 200.0), 1.0, 77)
	var dying_rng: RandomNumberGenerator = (dying.get_node("Brain") as EnemyBrain).rng
	_kill(dying)
	await _flush()
	var wrecks := get_tree().get_nodes_in_group(&"wrecks")
	assert_eq(wrecks.size(), 0, "%s: no container, no wreck anywhere" % mode)
	var control_brain := control.get_node("Brain") as EnemyBrain
	assert_eq(dying_rng.randf(), control_brain.rng.randf(),
		"%s: the brain's next randf() equals the control's: the roll was never drawn" % mode)


func test_a_roll_draws_exactly_one_value_when_a_container_exists(mode: String = use_parameters(_MODES)) -> void:
	_build(mode)
	var dying := _drone(Vector2(300.0, 200.0), 0.5, 77)
	var control := _drone(Vector2(500.0, 200.0), 0.5, 77)
	var dying_rng: RandomNumberGenerator = (dying.get_node("Brain") as EnemyBrain).rng
	_kill(dying)
	await _flush()
	var control_brain := control.get_node("Brain") as EnemyBrain
	control_brain.rng.randf()
	assert_eq(dying_rng.randf(), control_brain.rng.randf(),
		"%s: one draw per death" % mode)


func test_the_wreck_is_the_hazard_containers_child_never_the_enemies(mode: String = use_parameters(_MODES)) -> void:
	_build(mode)
	var d := _drone(Vector2(300.0, 220.0), 1.0, 3, 1)
	d.velocity = Vector2(80.0, 40.0)
	d.rotation = 0.7
	_kill(d)
	await _flush()
	var wrecks := _wrecks()
	assert_eq(wrecks.size(), 1, "%s: chance 1 leaves one wreck" % mode)
	if wrecks.is_empty():
		return
	var w := wrecks[0]
	assert_eq(w.get_parent(), _hazards, "a child of the hazard container")
	assert_false(w.is_in_group(&"enemies"), "never in group enemies")
	assert_true(w.is_in_group(&"wrecks"))
	for c in _enemies.get_children():
		assert_false(c is Wreck, "never a child of the enemy container")
	assert_lt(w.global_position.distance_to(Vector2(300.0, 220.0)), 3.0, "left where the ship died")
	assert_almost_eq(w.rotation, 0.7, 0.0001, "with its rotation")
	assert_eq(w.drift_velocity, Vector2(20.0, 10.0), "inheriting 25 %% of the ship's velocity")
	assert_eq(w.scene_file_path, "res://assault/scenes/hazards/wreck/wreck_medium.tscn", "of the configured size")


func test_the_cap_retires_the_oldest(mode: String = use_parameters(_MODES)) -> void:
	_build(mode)
	var cap: int = _CAP[mode]
	for i in cap + 2:
		_kill(_drone(Vector2(100.0 + 60.0 * i, 200.0), 1.0, 1 + i))
		await _flush()
	var alive := _alive_wrecks()
	assert_eq(alive.size(), cap, "%s: at most %d alive wrecks" % [mode, cap])
	var retiring := _wrecks().filter(func(w: Wreck) -> bool: return w.is_retiring())
	assert_eq(retiring.size(), 2, "the two oldest are fading, not deleted on screen")
	for w in retiring:
		assert_lt(w.global_position.x, 100.0 + 60.0 * 2, "and they are the first two spawned")


func test_the_cap_holds_when_several_die_in_the_same_frame(mode: String = use_parameters(_MODES)) -> void:
	_build(mode)
	var cap: int = _CAP[mode]
	for i in cap + 3:
		_kill(_drone(Vector2(100.0 + 60.0 * i, 200.0), 1.0, 1 + i))
	await _flush()
	assert_eq(_wrecks().size(), cap + 3, "sanity: every death left one")
	assert_eq(_alive_wrecks().size(), cap, "%s: the cap holds with %d deaths in one frame" % [mode, cap + 3])
	for w in _wrecks():
		if w.is_retiring():
			assert_lt(w.global_position.x, 100.0 + 60.0 * 3, "the retired ones are the oldest")
	# Two deaths in one frame on top of a nearly full container.
	var n := _wrecks().size()
	_kill(_drone(Vector2(900.0, 300.0), 1.0, 500))
	_kill(_drone(Vector2(960.0, 300.0), 1.0, 501))
	await _flush()
	assert_eq(_wrecks().size(), n + 2)
	assert_eq(_alive_wrecks().size(), cap, "%s: still at the cap after two more in one frame" % mode)


func test_a_retired_wreck_fades_and_frees(mode: String = use_parameters(_MODES)) -> void:
	_build(mode)
	var cap: int = _CAP[mode]
	for i in cap + 1:
		_kill(_drone(Vector2(100.0 + 60.0 * i, 200.0), 1.0, 1 + i))
	await _flush()
	var before := _wrecks().size()
	assert_eq(before, cap + 1)
	for i in 40:
		await get_tree().physics_frame
	assert_eq(_wrecks().size(), cap, "%s: the retired wreck is gone after its fade" % mode)


func test_an_enemies_cleared_container_empties_while_wrecks_remain(mode: String = use_parameters(_MODES)) -> void:
	_build(mode)
	var drones: Array[SwarmDrone] = []
	for i in 3:
		drones.append(_drone(Vector2(200.0 + 80.0 * i, 200.0), 1.0, 20 + i))
	for d in drones:
		_kill(d)
	await _flush()
	for c in _enemies.get_children():
		assert_false(c is BaseEnemy or c is Wreck, "%s: no ship or wreck is left in the enemy container" % mode)
	assert_eq(_alive_wrecks().size(), 3, "while the wrecks are still there")


func test_a_real_bullet_kill_leaves_exactly_one_wreck() -> void:
	_scale_clock()
	_build("open_space")
	var d := _drone(Vector2(640.0, 360.0), 1.0, 31)
	d.health.max_health = 1
	d.health.current_health = 1
	var b: Node2D = BULLET_SCENE.instantiate()
	_h.root.add_child(b)
	b.global_position = Vector2(640.0, 420.0)
	b.expired.connect(b.queue_free)
	var frames := 0
	while is_instance_valid(d) and frames < 120:
		await get_tree().physics_frame
		frames += 1
	assert_false(is_instance_valid(d) and not d.is_queued_for_deletion(), "sanity: the bullet killed the drone")
	assert_true(d == null or not is_instance_valid(d) or d.was_killed)
	for i in 3:
		await get_tree().physics_frame
	assert_eq(_wrecks().size(), 1, "exactly one wreck appears within 3 physics frames of the kill")
	for c in _enemies.get_children():
		assert_false(c is Wreck, "never in the enemy container")
