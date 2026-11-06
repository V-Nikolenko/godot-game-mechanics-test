## The mine family (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.1-§2.3, task t2): `EnemyMine`, the
## shared spec file every mine task (§2.2-§2.8) adds to. INTENT tests.
##
## t2 covers what every mine shares: the Bomber's mine IS the PROXIMITY variant, a mine is a hazard only
## while it is a live, launched mine (a pooled idle mine sits in the tree, so registration is
## launch-scoped), `mine_life` 0 never fizzles, a `placed` mine owns and launches itself, hostility
## ALL lets enemy hulls set a mine off and hurts both sides, `retire()` fizzles, the warning rule, and
## the measured avoidance footprint.
##
## Numbers come from the scenes (`EnemyMineScenes.export_of`) or the live mine, never typed copies.
## Hand-ticked rows disable the mine's processing and call `_physics_process` on it and its
## `ProjectileLifetime` at a fixed 1/60 s. Real-physics rows run on the 8x clock (the
## test_enemy_ordnance.gd pattern); every scenario several rows share is run once.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const MINE_SCRIPT: GDScript = preload("res://assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd")
const DUMB_ROCKET: PackedScene = preload("res://assault/scenes/projectiles/enemy_rockets/dumb_rocket.tscn")
const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
## The top of the Ph4 mine band: a player crossing at this speed is still inside the effect when it fires.
const CROSSING_SPEED := 440.0
## Hull radius of every stand-in that sets a mine off (the player stub and the fixture enemy's hurtbox).
const STUB_RADIUS := 12.0
const FIXTURE_HURT_RADIUS := 14.0

var _container: Node2D
var _blasts: Array[Node] = []

const _SPEEDUP := 8
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_each() -> void:
	_blasts = []
	_container = Node2D.new()
	add_child_autofree(_container)
	_container.child_entered_tree.connect(_on_container_child)


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


## One physics step in game seconds: unchanged by `_scale_clock()`.
func _game_step() -> float:
	return 1.0 / float(_saved_ticks if _clock_scaled else Engine.physics_ticks_per_second)


func _seconds(s: float) -> void:
	await wait_physics_frames(roundi(s / _game_step()))


func _on_container_child(node: Node) -> void:
	if node is ContactBlast:
		_blasts.append(node)


# ---------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------

## A bare PROXIMITY mine (`mine.tscn`), not yet in the tree.
func _mine() -> EnemyMine:
	return EnemyMineScenes.scene_for(EnemyMine.Variant.PROXIMITY).instantiate() as EnemyMine


## An unpooled, launched mine at [param at]; freed on `expired` (the one-owner rule's other half).
func _launched(at: Vector2, parent: Node = null, setup: Callable = Callable()) -> EnemyMine:
	var m := _mine()
	if setup.is_valid():
		setup.call(m)
	(parent if parent != null else _container).add_child(m)
	m.global_position = at
	m.expired.connect(m.queue_free)
	m.launch(Vector2.ZERO, 0.0, at)
	return m


## A mine in the tree with its processing off, for hand-ticking.
func _hand_ticked(setup: Callable = Callable()) -> EnemyMine:
	var m := _mine()
	m.process_mode = Node.PROCESS_MODE_DISABLED
	if setup.is_valid():
		setup.call(m)
	_container.add_child(m)
	return m


func _tick(m: EnemyMine, ticks: int) -> void:
	var lt := m.get_node("ProjectileLifetime") as ProjectileLifetime
	for i in ticks:
		if not is_instance_valid(m):
			return
		m._physics_process(DT)
		if is_instance_valid(lt):
			lt._physics_process(DT)


## Ticks until [param done] answers true (at most [param max_ticks]); returns the tick it did, -1 if never.
func _tick_until(m: EnemyMine, done: Callable, max_ticks: int) -> int:
	for i in max_ticks:
		_tick(m, 1)
		if done.call():
			return i + 1
	return -1


## True while [param m]'s own info is in the registry.
func _registered(m: Node) -> bool:
	if not is_instance_valid(m):
		return false
	for info: HazardInfo in Hazards.around((m as Node2D).global_position, 1.0):
		if info.source == m:
			return true
	return false


## A player stand-in: a body in group `player` with a real layer-128 `HurtBox` named `HurtBox` (so both
## `ContactBlast` and `Hazards.pulse_damage` reach it), which records every damage it takes in `meta damage`.
func _player(at: Vector2, parent: Node = null) -> CharacterBody2D:
	var p := CharacterBody2D.new()
	p.add_to_group(&"player")
	p.collision_layer = 0
	p.collision_mask = 0
	var hurt := HurtBox.new()
	hurt.name = "HurtBox"
	hurt.collision_layer = CollisionLayers.PLAYER_HURTBOX
	hurt.collision_mask = CollisionLayers.ENEMY_HITBOX
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = STUB_RADIUS
	shape.shape = circle
	hurt.add_child(shape)
	p.add_child(hurt)
	p.set_meta(&"damage", 0)
	hurt.received_damage.connect(func(d: int) -> void: p.set_meta(&"damage", int(p.get_meta(&"damage")) + d))
	(parent if parent != null else _container).add_child(p)
	p.global_position = at
	return p


## `fixture_enemy.tscn` made visible to a mine: a 14 px shape on its `HurtBox` (the scene ships none) and
## group `enemies` (neither `BaseEnemy` nor the fixture joins it), both before `add_child`. Health 100, so a
## 30-damage blast lowers it without killing it.
func _visible_enemy(at: Vector2, parent: Node = null) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = FIXTURE_HURT_RADIUS
	shape.shape = circle
	e.get_node("HurtBox").add_child(shape)
	e.add_to_group(&"enemies")
	var health := e.get_node("Health") as Health
	health.max_health = 100
	health.current_health = 100
	e.position = at
	(parent if parent != null else _container).add_child(e)
	return e


## A pooled mine's owner: container -> ship -> `BulletPool` (the pool resolves its container as its
## grandparent), prewarmed with [param size] `mine.tscn` instances.
func _pool(size: int) -> BulletPool:
	var ship := Node2D.new()
	var pool := BulletPool.new()
	pool.bullet_scene = EnemyMineScenes.scene_for(EnemyMine.Variant.PROXIMITY)
	pool.pool_size = size
	pool.persist_after_owner_death = true
	ship.add_child(pool)
	_container.add_child(ship)
	return pool


## Calls [param fn] on every physics tick while the returned node lives; it is a child of [param parent], so it is freed
## with the scene (a lambda left connected to a tree signal would outlive the nodes it captured).
func _tick_each_frame(parent: Node, fn: Callable) -> Node:
	var t := _Ticker.new()
	t.fn = fn
	parent.add_child(t)
	return t


class _Ticker extends Node:
	var fn: Callable

	func _physics_process(_delta: float) -> void:
		fn.call()


# ---------------------------------------------------------------------------------------------
# PROXIMITY is the Bomber's mine
# ---------------------------------------------------------------------------------------------

func test_proximity_is_the_bombers_mine_scene() -> void:
	assert_eq(EnemyMineScenes.scene_for(EnemyMine.Variant.PROXIMITY), EnemyOrdnanceScenes.MINE,
			"PROXIMITY is enemy_ordnance/mine.tscn itself, not a copy")
	var m := _mine()
	assert_true(m is EnemyMine, "mine.tscn's script is EnemyMine")
	assert_eq(m.kind, EnemyOrdnance.Kind.MINE)
	assert_eq(m.variant, EnemyMine.Variant.PROXIMITY)
	m.free()
	assert_almost_eq(float(EnemyMineScenes.export_of(EnemyMine.Variant.PROXIMITY, &"warning_time", 1.0)), 0.25, 1e-6,
			"mine.tscn authors warning_time 0.25 (was 0.5), so the scene itself passes the warning rule")


func test_pool_size_for() -> void:
	var cfg := {"max_live_mines": 18, "w_proximity": 0.5, "w_chain": 0.2, "w_pulse": 0.15, "w_homing": 0.15,
			"w_drifting": 0.0, "w_emp": 0.0}
	var obj := _Cfg.new(cfg)
	assert_eq(EnemyMineScenes.pool_size_for(EnemyMine.Variant.PROXIMITY, obj), 20, "PROXIMITY: cap + 2")
	assert_eq(EnemyMineScenes.pool_size_for(EnemyMine.Variant.CHAIN, obj), 6, "ceil(18 * 0.2 / 1.0) + 2 = 6")
	assert_eq(EnemyMineScenes.pool_size_for(EnemyMine.Variant.HOMING, obj), 5, "ceil(18 * 0.15) + 2 = 3 + 2")
	assert_eq(EnemyMineScenes.pool_size_for(EnemyMine.Variant.DRIFTING, obj), 0, "weight 0: no pool")
	assert_eq(EnemyMineScenes.pool_size_for(EnemyMine.Variant.EMP, _Cfg.new({"max_live_mines": 8})), 0,
			"a config without the weight: no pool")


## A duck-typed config stand-in: answers `in` and property reads for the keys it was built with.
class _Cfg extends RefCounted:
	var _d: Dictionary

	func _init(d: Dictionary) -> void:
		_d = d

	func _get(property: StringName) -> Variant:
		return _d.get(String(property))

	func _get_property_list() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for k: String in _d:
			out.append({"name": k, "type": typeof(_d[k])})
		return out


# ---------------------------------------------------------------------------------------------
# Registration is launch-scoped
# ---------------------------------------------------------------------------------------------

func test_a_pooled_idle_mine_is_not_a_hazard_and_a_launched_one_is() -> void:
	var before := Hazards.count()
	var pool := _pool(2)
	await wait_process_frames(1)
	assert_eq(Hazards.count(), before, "two prewarmed mines sit in the tree, unlaunched: no phantom hazards")
	var m := pool.acquire(Vector2(100, 100)) as EnemyMine
	assert_eq(Hazards.count(), before, "acquired but not launched: still nothing")
	m.launch(Vector2.DOWN, 0.0, Vector2(100, 100))
	assert_eq(Hazards.count(), before + 1, "launch() registers")
	assert_true(_registered(m))
	var info := m.hazard_info()
	assert_eq(info.kind, &"mine")
	assert_eq(info.radius, m.trigger_radius + m.hazard_pad, "radius = trigger_radius + hazard_pad")
	assert_eq(m.hazard_pad, 60.0)
	assert_eq(info.avoid_weight, 1.0)
	assert_eq(info.source, m)
	assert_eq(info.position, m.global_position)
	assert_eq(info.velocity, Vector2.ZERO, "a PROXIMITY mine does not move")
	assert_eq(info.pull_force, 0.0)
	assert_eq(info.tangential_force, 0.0)
	assert_eq(info.movement_penalty, 0.0)
	assert_false(info.line_of_sight_blocker, "a mine is no cover")
	# A recycle (reparent into the pool while done) must not re-register it.
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.retire()
	_tick(m, ceili(m.fizzle_time / DT) + 2)
	await wait_process_frames(2)
	assert_eq(Hazards.count(), before, "retired, recycled into the pool: not a hazard")


## `acquire()` reparents BEFORE `reset()`, so a recycled mine enters the container with its last life's state:
## that `_enter_tree()` must not register it, and its second launch must register it exactly once.
func test_a_second_life_registers_once_and_only_on_launch() -> void:
	var before := Hazards.count()
	var pool := _pool(1)
	await wait_process_frames(1)
	var m := pool.acquire(Vector2(100, 100)) as EnemyMine
	m.launch(Vector2.ZERO, 0.0, Vector2(100, 100))
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.retire()
	_tick(m, ceili(m.fizzle_time / DT) + 2)
	await wait_process_frames(2)  # the deferred recycle
	assert_eq(m.get_parent(), pool, "recycled into the pool")
	assert_eq(Hazards.count(), before)
	var again := pool.acquire(Vector2(200, 100)) as EnemyMine
	assert_eq(again, m, "the same mine, second life")
	assert_eq(Hazards.count(), before, "re-acquired, not launched: not a hazard")
	again.launch(Vector2.ZERO, 0.0, Vector2(200, 100))
	assert_eq(Hazards.count(), before + 1, "launched: exactly one registration")
	assert_eq(again.hazard_info().position, Vector2(200, 100))


func test_a_live_mine_moved_to_another_parent_stays_registered() -> void:
	var m := _hand_ticked()
	m.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	var other := Node2D.new()
	_container.add_child(other)
	m.reparent(other)
	assert_true(_registered(m), "_exit_tree unregistered it, _enter_tree put it back")
	assert_eq(Hazards.around(m.global_position, 1.0).filter(func(i: HazardInfo) -> bool: return i.source == m).size(), 1,
			"once")


func test_defuse_fizzle_retire_free_and_opt_out_all_unregister() -> void:
	var defused := _hand_ticked()
	defused.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	assert_true(_registered(defused), "defuse: registered first")
	(defused.get_node("HurtBox") as HurtBox).received_damage.emit(5)
	assert_false(_registered(defused), "a shot mine is not a hazard")

	var fizzled := _hand_ticked(func(m: EnemyMine) -> void: m.mine_life = 1.0)
	fizzled.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	assert_true(_registered(fizzled))
	_tick(fizzled, 61)
	assert_true(fizzled.is_fizzling(), "past mine_life it fades")
	assert_false(_registered(fizzled), "a fading mine is no longer a hazard")
	_tick(fizzled, ceili(fizzled.fizzle_time / DT) + 1)
	assert_false(_registered(fizzled), "nor once it has expired")

	var retired := _hand_ticked()
	retired.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	retired.retire()
	_tick(retired, 1)
	assert_false(_registered(retired), "retire() unregisters")

	var freed := _hand_ticked()
	freed.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	assert_true(_registered(freed))
	var before := Hazards.count()
	freed.queue_free()
	await wait_process_frames(1)
	assert_eq(Hazards.count(), before - 1, "a freed mine leaves the registry (_exit_tree)")

	var opted_out := _hand_ticked(func(m: EnemyMine) -> void: m.registers_hazard = false)
	before = Hazards.count()
	opted_out.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	_tick(opted_out, 30)
	assert_eq(Hazards.count(), before, "registers_hazard = false is never counted")
	assert_false(_registered(opted_out))


# ---------------------------------------------------------------------------------------------
# Lifetime: mine_life 0 never fizzles; placed mines take placed_life, never the authored 8 s
# ---------------------------------------------------------------------------------------------

func test_mine_life_zero_never_fizzles() -> void:
	var m := _hand_ticked(func(m: EnemyMine) -> void: m.mine_life = 0.0)
	(m.get_node("ProjectileLifetime") as ProjectileLifetime).max_time = 0.0  # inert backstop: the mine's own rule
	m.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	_tick(m, 30 * 60)
	assert_false(m.is_fizzling(), "mine_life 0: no fizzle at 30 s")
	assert_true(is_instance_valid(m) and _registered(m), "still a live hazard at 30 s")


## A dropper that gives a pooled mine life 0 by mistake still gets it back: the scene's backstop ends it.
func test_a_non_placed_mine_with_life_zero_still_ends_at_its_backstop() -> void:
	var m := _hand_ticked(func(m: EnemyMine) -> void: m.mine_life = 0.0)
	var backstop := (m.get_node("ProjectileLifetime") as ProjectileLifetime).max_time
	assert_gt(backstop, 0.0, "precondition: the scene authors a backstop")
	var count := [0]
	m.expired.connect(func() -> void: count[0] += 1)
	m.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	var tick := _tick_until(m, func() -> bool: return count[0] > 0, ceili(backstop / DT) + 10)
	assert_almost_eq(tick * DT, backstop, DT + 1e-6, "expired at the backstop +- 1 tick")
	assert_false(_registered(m))


func test_mine_life_8_fizzles_at_8_s() -> void:
	var m := _hand_ticked(func(m: EnemyMine) -> void: m.mine_life = 8.0)
	m.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	var tick := _tick_until(m, m.is_fizzling, 9 * 60)
	assert_almost_eq(tick * DT, 8.0, DT + 1e-6, "the Ph4 value: fizzles at 8.0 s +- 1 tick")


func test_a_placed_bare_mine_never_takes_the_authored_8_s() -> void:
	assert_eq(float(EnemyMineScenes.export_of(EnemyMine.Variant.PROXIMITY, &"mine_life", 0.0)), 8.0,
			"precondition: mine.tscn authors 8 s for the Bomber")
	var m := _hand_ticked(func(m: EnemyMine) -> void: m.placed = true)
	await wait_process_frames(1)  # the deferred _start_if_placed()
	assert_true(_registered(m), "a placed mine launches itself")
	_tick(m, 60 * 60)
	assert_true(is_instance_valid(m), "still live at 60 s")
	assert_false(m.is_fizzling(), "placed_life 0: never fizzles")
	assert_true(_registered(m), "and still a hazard: the 10 s backstop is inert for a placed mine")


func test_a_placed_mine_with_placed_life_fizzles_then_frees_itself() -> void:
	var m := _hand_ticked(func(m: EnemyMine) -> void:
		m.placed = true
		m.placed_life = 5.0)
	var expired := [0]
	m.expired.connect(func() -> void: expired[0] += 1)
	await wait_process_frames(1)
	var tick := _tick_until(m, m.is_fizzling, 6 * 60)
	assert_almost_eq(tick * DT, 5.0, DT + 1e-6, "placed_life 5.0: fizzles at 5.0 s +- 1 tick after launch")
	_tick(m, ceili(m.fizzle_time / DT) + 2)
	assert_eq(expired[0], 1, "one expired")
	await wait_process_frames(1)
	assert_false(is_instance_valid(m), "self-owned: it frees itself")


# ---------------------------------------------------------------------------------------------
# Placed mode and the ready order
# ---------------------------------------------------------------------------------------------

## Assault: the projectile world rect is the corridor + 64 px (y -444...1164). A placed mine authored above it (a
## minefield's outer mines entering from the top) must not expire on it; a dropped mine there does (control).
func test_a_placed_mine_outside_the_assault_world_rect_lives() -> void:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	var outside := Vector2(640, -600)
	var placed := _mine()
	placed.placed = true
	placed.process_mode = Node.PROCESS_MODE_DISABLED
	placed.position = outside
	harness.root.add_child(placed)
	var dropped := _mine()
	dropped.process_mode = Node.PROCESS_MODE_DISABLED
	dropped.position = outside
	harness.root.add_child(dropped)
	var dropped_expired := [0]
	dropped.expired.connect(func() -> void: dropped_expired[0] += 1)
	dropped.launch(Vector2.ZERO, 0.0, outside)
	await wait_process_frames(1)  # the placed mine's deferred setup
	assert_false(EnemyWorld.projectile_world_rect(get_tree()).has_point(outside), "precondition: outside the rect")
	_tick(dropped, 1)
	assert_eq(dropped_expired[0], 1, "control: a dropped mine out there expires on its first tick")
	_tick(placed, 60)
	assert_true(is_instance_valid(placed) and _registered(placed), "a placed mine ignores the world rect")


func test_a_placed_mine_arms_triggers_and_frees_itself_and_a_pooled_one_does_not() -> void:
	_scale_clock()
	var placed := _mine()
	placed.placed = true
	_container.add_child(placed)
	placed.global_position = Vector2.ZERO
	_player(Vector2(0, 30))
	# Control: a pooled mine 3000 px away, set off the same way.
	var pool := _pool(1)
	var pooled := pool.acquire(Vector2(3000, 0)) as EnemyMine
	pooled.launch(Vector2.ZERO, 0.0, Vector2(3000, 0))
	_player(Vector2(3000, 30))
	await _seconds(0.5 * placed.arm_delay)
	assert_true(is_instance_valid(placed) and _registered(placed), "placed: registered from its own launch")
	assert_false(placed.is_armed(), "not armed before arm_delay")
	assert_eq(_blasts.size(), 0)
	await _seconds(0.5 * placed.arm_delay + 0.1)
	assert_true(is_instance_valid(placed) and placed.is_armed(), "armed after arm_delay")
	assert_true(placed.is_warning(), "the player inside the radius sets it off")
	await _seconds(placed.warning_time + 0.3)
	assert_eq(_blasts.size(), 2, "one blast each")
	assert_false(is_instance_valid(placed), "a placed mine frees itself after its blast")
	assert_true(is_instance_valid(pooled), "a pooled mine never frees itself: its pool recycles it")
	assert_false(_registered(pooled), "a detonated mine is not a hazard")


## The AUTHORED-field shape: a parent whose `_ready()` (which runs after its children's) sets `placed` and
## `hostility` on a child authored `placed = false` / PLAYER. The child's deferred setup must still see them.
func test_a_parent_setting_placed_in_its_own_ready_wins() -> void:
	var parent_script := GDScript.new()
	parent_script.source_code = "extends Node2D\nfunc _ready() -> void:\n" \
			+ "\tvar m = get_child(0)\n\tm.placed = true\n\tm.hostility = %d\n" % EnemyMine.Hostility.ALL
	parent_script.reload()
	var parent := Node2D.new()
	parent.set_script(parent_script)
	var m := _mine()
	assert_false(m.placed)
	assert_eq(m.hostility, EnemyMine.Hostility.PLAYER)
	parent.add_child(m)
	_container.add_child(parent)
	await wait_process_frames(1)
	assert_true(m.expired.is_connected(m.queue_free), "self-owned")
	assert_true(_registered(m), "registered")
	assert_eq((m.get_node("ProximityArea") as Area2D).collision_mask,
			CollisionLayers.PLAYER_HURTBOX | CollisionLayers.ENEMY_HURTBOX, "the ALL mask, applied in launch()")


# ---------------------------------------------------------------------------------------------
# Hostility
# ---------------------------------------------------------------------------------------------

## One scenario, four mines 1500 px apart: a PLAYER mine with an enemy inside its radius, and three ALL mines
## each with one non-ship 512 area inside (another mine, a rocket's shoot-down box, a lone Ram plate whose
## hull is outside). None may be set off.
func test_player_mines_ignore_enemies_and_all_mines_ignore_non_ship_hurtboxes() -> void:
	_scale_clock()
	var player_mine := _launched(Vector2(0, 0))
	var enemy := _visible_enemy(Vector2(40, 0))

	var all_setup := func(m: EnemyMine) -> void: m.hostility = EnemyMine.Hostility.ALL
	var by_mine := _launched(Vector2(1500, 0), null, all_setup)
	var other := _mine()
	_container.add_child(other)
	other.global_position = Vector2(1540, 0)

	var by_rocket := _launched(Vector2(3000, 0), null, all_setup)
	var rocket := DUMB_ROCKET.instantiate()
	_container.add_child(rocket)
	rocket.global_position = Vector2(3040, 0)

	var by_plate := _launched(Vector2(4500, 0), null, all_setup)
	var ram := Node2D.new()
	ram.add_to_group(&"enemies")
	var plates := Node2D.new()
	plates.name = "Plates"
	ram.add_child(plates)
	var plate := ArmorPlate.new()
	plates.add_child(plate)
	_container.add_child(ram)
	ram.global_position = Vector2(4500, 300)  # the "hull" is far outside the radius
	plate.global_position = Vector2(4540, 0)

	await _seconds(player_mine.arm_delay + player_mine.warning_time + 0.5)
	assert_true(_live_and_quiet(player_mine), "a PLAYER mine is not set off by an enemy")
	assert_eq((enemy.get_node("Health") as Health).current_health, 100)
	assert_true(_live_and_quiet(by_mine), "ALL: another mine's hurtbox is not a ship")
	assert_true(_live_and_quiet(by_rocket), "ALL: a rocket's shoot-down box is not a ship")
	assert_true(_live_and_quiet(by_plate), "ALL: a plate's hurtbox alone is not a ship")
	assert_eq(_blasts.size(), 0)


## Still alive (not detonated, not defused by an overlapping box), armed, and not warning.
func _live_and_quiet(m: EnemyMine) -> bool:
	return is_instance_valid(m) and m.is_armed() and not m.is_warning()


func test_an_all_mine_is_set_off_by_an_enemy_and_hurts_both_sides() -> void:
	_scale_clock()
	var m := _launched(Vector2.ZERO, null, func(m: EnemyMine) -> void: m.hostility = EnemyMine.Hostility.ALL)
	var enemy := _visible_enemy(Vector2(30, 0))
	var health := enemy.get_node("Health") as Health
	var damage := m.blast_damage
	assert_lt(30.0, m.blast_radius, "precondition: both stand-ins sit inside the blast radius (centre distance)")
	var warned := false
	for i in roundi((m.arm_delay + 0.3) / _game_step()):
		await wait_physics_frames(1)
		if m.is_warning():
			warned = true
			break
	assert_true(warned, "an enemy hull inside an ALL mine's radius sets it off")
	# Only now does the player arrive, inside the blast radius: it did not set the mine off.
	var p := _player(Vector2(0, -30))
	await _seconds(m.warning_time + 0.2)
	assert_false(is_instance_valid(m), "it detonated")
	assert_eq(_blasts.size(), 0, "an ALL blast is Hazards.pulse_damage, not a ContactBlast")
	assert_eq(health.current_health, 100 - damage, "the enemy took the blast")
	assert_eq(int(p.get_meta(&"damage")), damage, "and so did the player")


## Own accumulated clock only, like the rest of the ordnance family (a timer outlives a freed test tree and leaks).
func test_the_mine_family_uses_no_timer() -> void:
	const DIR := "res://assault/scenes/projectiles/enemy_ordnance/mines/"
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool:
		return f.ends_with(".gd") or f.ends_with(".tscn"))
	assert_gt(files.size(), 0)
	for f: String in files:
		var text := FileAccess.get_file_as_string(DIR + f)
		assert_false(text.contains("create_timer"), f + " has no create_timer")
		assert_false(text.contains("Timer"), f + " mentions no Timer")


func test_retire_is_one_expired_and_no_blast() -> void:
	var m := _hand_ticked()
	var count := [0]
	m.expired.connect(func() -> void: count[0] += 1)
	m.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	m.retire()
	m.retire()
	_tick(m, ceili(m.fizzle_time / DT) + 10)
	assert_eq(count[0], 1, "exactly one expired")
	await wait_process_frames(1)
	assert_eq(_blasts.size(), 0, "no blast")


# ---------------------------------------------------------------------------------------------
# The warning rule (§2.2), from scene exports
# ---------------------------------------------------------------------------------------------

func _default(prop: StringName) -> Variant:
	var v: Variant = MINE_SCRIPT.get_property_default_value(prop)
	return 0.0 if v == null else v


func _export(variant: int, prop: StringName) -> float:
	return float(EnemyMineScenes.export_of(variant, prop, _default(prop)))


## `(trigger_radius + effect_radius) / warning_time >= 440 + own_speed`.
func _warning_rule(trigger: float, blast_radius: float, blast_damage: float, emp_radius: float, warning: float,
		own_speed: float) -> bool:
	var effect := blast_radius if blast_damage > 0.0 else emp_radius
	return (trigger + effect) / warning >= CROSSING_SPEED + own_speed


func _own_speed(variant: int) -> float:
	match variant:
		EnemyMine.Variant.HOMING:
			return _export(variant, &"home_speed")
		EnemyMine.Variant.DRIFTING:
			return _export(variant, &"drift_speed")
	return 0.0


func test_every_mine_scene_passes_the_warning_rule() -> void:
	var built := 0
	for v: int in EnemyMine.Variant.values():
		if EnemyMineScenes.scene_for(v) == null:
			continue
		built += 1
		assert_true(_warning_rule(_export(v, &"trigger_radius"), _export(v, &"blast_radius"),
				_export(v, &"blast_damage"), _export(v, &"emp_radius"), _export(v, &"warning_time"), _own_speed(v)),
				"variant %s: (trigger + effect) / warning >= 440 + own speed" % EnemyMine.Variant.keys()[v])
	assert_gt(built, 0, "at least PROXIMITY is built")


func test_the_warning_rule_can_reject() -> void:
	var p := EnemyMine.Variant.PROXIMITY
	var trigger := _export(p, &"trigger_radius")
	assert_false(_warning_rule(trigger, 48.0, 30.0, 0.0, 0.4, 0.0), "warning 0.4 with blast 48: 320 < 440")
	assert_false(_warning_rule(trigger, _export(p, &"blast_radius"), _export(p, &"blast_damage"), 0.0,
			_export(p, &"warning_time"), 75.0), "a 75 px/s homing mine (round 1): 512 < 515")
	assert_true(_warning_rule(trigger, _export(p, &"blast_radius"), _export(p, &"blast_damage"), 0.0,
			_export(p, &"warning_time"), 60.0), "control: at 60 px/s it passes, 512 >= 500")


## Dual-mode, real physics (8x): a stub crossing the trigger at 220 px/s takes the blast; one that stops at
## `trigger_radius + 30` does not. Both cases share one run, 1500 px apart.
func test_a_crossing_player_takes_the_blast_and_a_stopping_one_does_not(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.root.child_entered_tree.connect(_on_container_child)
	var cross_at := Vector2(300, 200)
	var stop_at := Vector2(300, 600)
	var crossing_mine := _launched(cross_at, harness.root)
	var stopping_mine := _launched(stop_at, harness.root)
	var stop_distance := stopping_mine.trigger_radius + 30.0
	var crosser := _player(cross_at + Vector2(-300, 0), harness.root)
	var stopper := _player(stop_at + Vector2(-300, 0), harness.root)
	var speed := 220.0
	var mover := func() -> void:
		var step := speed * _game_step()
		crosser.global_position.x += step
		var target := stop_at.x - stop_distance
		stopper.global_position.x = minf(target, stopper.global_position.x + step)
	_tick_each_frame(harness.root, mover)
	await _seconds(600.0 / speed)
	assert_gt(int(crosser.get_meta(&"damage")), 0, "%s: a 220 px/s crossing takes the blast" % mode)
	assert_false(is_instance_valid(crossing_mine), "%s: it detonated" % mode)
	assert_eq(int(stopper.get_meta(&"damage")), 0, "%s: stopping at trigger + 30 is safe" % mode)
	assert_true(is_instance_valid(stopping_mine) and not stopping_mine.is_warning(), "%s: not set off" % mode)


# ---------------------------------------------------------------------------------------------
# Avoidance (§2.3, measured)
# ---------------------------------------------------------------------------------------------

## The `test_context_avoidance.gd::_fly()` shape, fed through the registry: seek (500, lateral) from
## (-500, lateral) at 200 px/s with a launched mine at the origin, 60 Hz, `prev_dir` fed back, only the mine's
## own info within the mover's reach. Returns the closest approach of the ship's centre to the mine's.
func _fly_past(mine: EnemyMine, lateral: float, avoidance: float, margin: float = 24.0, speed: float = 200.0) -> float:
	var pos := Vector2(-500.0, lateral)
	var target := Vector2(500.0, lateral)
	var prev := Vector2.ZERO
	var closest := INF
	for step in int(12.0 / DT):
		if pos.distance_to(target) < 6.0:
			break
		var desired := (target - pos).normalized() * speed
		var infos := []
		for info: HazardInfo in Hazards.around(pos, margin + speed * Steering.CONTEXT_LOOKAHEAD):
			if info.source == mine:
				infos.append(info)
		var out := Steering.context_avoid(pos, desired, infos, avoidance, margin, Steering.CONTEXT_LOOKAHEAD,
				prev) if not infos.is_empty() else desired
		prev = out.normalized() if not infos.is_empty() else Vector2.ZERO
		pos += out * DT
		closest = minf(closest, pos.distance_to(mine.global_position))
	return closest


func test_the_footprint_keeps_avoiding_ships_out_of_the_trigger() -> void:
	var mine := _hand_ticked()
	mine.global_position = Vector2.ZERO
	mine.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	for lateral: float in [0.0, 30.0, 60.0]:
		var at_06 := _fly_past(mine, lateral, 0.6)
		assert_gte(at_06, 85.0, "av 0.6, lateral %d: >= 85 px (measured 90/99/109), past the trigger" % lateral)
		assert_gt(at_06, mine.trigger_radius)
		assert_gte(_fly_past(mine, lateral, 0.8), 145.0, "av 0.8, lateral %d: >= 145 px (measured 152/152/156)" % lateral)


func test_without_registration_the_same_runs_fly_straight() -> void:
	var mine := _hand_ticked(func(m: EnemyMine) -> void: m.registers_hazard = false)
	mine.global_position = Vector2.ZERO
	mine.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	for lateral: float in [0.0, 30.0, 60.0]:
		for av: float in [0.6, 0.8]:
			assert_almost_eq(_fly_past(mine, lateral, av), lateral, 1.0, "control: av %s lateral %d" % [av, lateral])


## The real mover, head-on (8x): a fixture enemy with avoidance 0.8 / margin 24 flies (-500, 0) -> (+500, 0) at
## 200 px/s through a launched mine; its control flies through an unregistered one 2000 px below, in the same run.
func test_a_real_mover_flies_round_a_mine_head_on() -> void:
	_scale_clock()
	var no_fizzle := func(m: EnemyMine) -> void: m.mine_life = 0.0
	var mine := _launched(Vector2.ZERO, null, no_fizzle)
	var control_mine := _launched(Vector2(0, 2000), null, func(m: EnemyMine) -> void:
		m.mine_life = 0.0
		m.registers_hazard = false)
	var ships: Array[BaseEnemy] = []
	for start: Vector2 in [Vector2(-500, 0), Vector2(-500, 2000)]:
		var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
		var mover := e.get_node("EnemyMover") as EnemyMover
		mover.hazard_avoidance = 0.8
		mover.hazard_margin = 24.0
		e.position = start
		_container.add_child(e)
		(e.get_node("Brain")).desired_velocity = Vector2(200.0, 0.0)
		ships.append(e)
	var closest := [INF, INF]
	var watch := func() -> void:
		closest[0] = minf(closest[0], ships[0].global_position.distance_to(mine.global_position))
		closest[1] = minf(closest[1], ships[1].global_position.distance_to(control_mine.global_position))
	var ticker := _tick_each_frame(_container, watch)
	await _seconds(6.0)
	ticker.queue_free()
	assert_gt(ships[0].global_position.x, 400.0, "sanity: it got past")
	assert_gte(closest[0], 120.0, "a 0.8 mover keeps >= 120 px from the mine's centre head-on")
	assert_gte(closest[0], closest[1] + 100.0, "and >= the unregistered control (%.1f px) + 100" % closest[1])


# ---------------------------------------------------------------------------------------------
# Drifting and homing mines (§2.4, task t3). Dual-mode, hand-ticked: both variants move by `position` writes in
# `_physics_process` alone, so no physics is needed. Numbers come from the scenes, never typed copies.
# ---------------------------------------------------------------------------------------------

## A hand-ticked [param variant] mine under [param parent] at [param at] (global), not yet launched.
func _variant_mine(variant: int, parent: Node, at: Vector2, setup: Callable = Callable()) -> EnemyMine:
	var m := EnemyMineScenes.scene_for(variant).instantiate() as EnemyMine
	m.process_mode = Node.PROCESS_MODE_DISABLED
	if setup.is_valid():
		setup.call(m)
	parent.add_child(m)
	m.global_position = at
	return m


func _world(mode: String) -> RefCounted:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	return harness


func test_the_drifting_and_homing_scenes_are_built_and_numbered() -> void:
	var d := EnemyMine.Variant.DRIFTING
	var h := EnemyMine.Variant.HOMING
	assert_not_null(EnemyMineScenes.scene_for(d), "drifting_mine.tscn is built")
	assert_not_null(EnemyMineScenes.scene_for(h), "homing_mine.tscn is built")
	assert_eq(int(_export(d, &"variant")), d)
	assert_eq(int(_export(h, &"variant")), h)
	assert_eq(int(_export(d, &"kind")), EnemyOrdnance.Kind.MINE)
	assert_eq(int(_export(h, &"kind")), EnemyOrdnance.Kind.MINE)
	assert_eq(_export(d, &"drift_speed"), 35.0)
	assert_eq(_export(d, &"drift_max_distance"), 1400.0)
	assert_eq(_export(d, &"drift_leash"), 0.0)
	assert_eq(_export(h, &"notice_radius"), 260.0)
	assert_eq(_export(h, &"home_speed"), 60.0)
	assert_eq(_export(h, &"home_turn_rate"), 2.0)
	assert_eq(_export(h, &"home_lose_radius"), 380.0)
	assert_eq(_export(h, &"home_max_distance"), 900.0)


func test_the_warning_rule_covers_drifting_and_homing_with_their_own_speed() -> void:
	for pair: Array in [[EnemyMine.Variant.DRIFTING, 475.0], [EnemyMine.Variant.HOMING, 500.0]]:
		var v: int = pair[0]
		var reach := (_export(v, &"trigger_radius") + _export(v, &"blast_radius")) / _export(v, &"warning_time")
		assert_gte(reach, 440.0 + _own_speed(v), "%s clears 440 + its own speed" % EnemyMine.Variant.keys()[v])
		assert_gte(reach, pair[1] as float, "and the plan's %.0f" % pair[1])
		assert_eq(reach, 512.0, "both authored the shared 80 / 48 / 0.25 numbers")


func test_a_drifting_mine_moves_35_t_along_its_launch_direction(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var start := Vector2(-100, 360)
	var m := _variant_mine(EnemyMine.Variant.DRIFTING, harness.root, start)
	m.launch(Vector2(1, 1).normalized(), 0.0, start)
	_tick(m, 15)
	assert_eq(m.global_position, start, "still ejecting: speed 0, no drift before eject_time (0.3 s)")
	assert_eq(m.hazard_info().velocity, Vector2.ZERO, "its hazard velocity is zero until it drifts")
	_tick(m, 165)
	var t := 180.0 * DT - m.eject_time
	assert_almost_eq(m.global_position.distance_to(start), 35.0 * t, 1.0, "35 px/s for the time after the eject")
	assert_almost_eq((m.global_position - start).normalized().dot(Vector2(1, 1).normalized()), 1.0, 0.001,
			"along the launch direction")
	assert_almost_eq(m.hazard_info().velocity.length(), 35.0, 0.001, "HazardInfo.velocity is kept current")
	assert_almost_eq(m.hazard_info().velocity.normalized().dot(Vector2(1, 1).normalized()), 1.0, 0.001)
	assert_eq(m.hazard_pull_scale(), 0.0, "it does not bend in fields, so its distance cap holds")


func test_a_drifting_mine_fizzles_at_1400_px(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var start := Vector2(-100, 360)  # 1400 px to the right stays inside Assault's x -164...1444 rect
	var m := _variant_mine(EnemyMine.Variant.DRIFTING, harness.root, start)
	var ends := [0]
	m.expired.connect(func() -> void: ends[0] += 1)
	m.launch(Vector2.RIGHT, 0.0, start)
	var fizzled_at := _tick_until(m, func() -> bool: return m.is_fizzling(), 3000)
	assert_gt(fizzled_at, 0, "it fizzles by itself")
	assert_almost_eq(m.global_position.distance_to(start), 1400.0, 1.0, "after 1400 px")
	assert_false(_registered(m), "a fizzling mine is no hazard")
	assert_eq(ends[0], 0, "still fading")
	_tick(m, 30)
	assert_eq(ends[0], 1, "exactly one expired, no blast")
	assert_eq(_blasts.size(), 0)


func test_a_zero_direction_placed_drifter_is_still(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var start := Vector2(300, 300)
	var m := _variant_mine(EnemyMine.Variant.DRIFTING, harness.root, start, func(x: EnemyMine) -> void:
		x.placed = true
		x.drift_direction = Vector2.ZERO)
	await wait_process_frames(1)  # the deferred placed setup
	_tick(m, 600)
	assert_true(is_instance_valid(m) and _registered(m), "live and registered")
	assert_eq(m.global_position, start, "no direction, no motion")
	assert_eq(m.hazard_info().velocity, Vector2.ZERO)


func test_a_drift_leash_keeps_a_placed_drifter_within_121_px_for_60_s(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var start := Vector2(300, 300)
	var m := _variant_mine(EnemyMine.Variant.DRIFTING, harness.root, start, func(x: EnemyMine) -> void:
		x.placed = true
		x.drift_direction = Vector2.RIGHT
		x.drift_leash = 120.0)
	await wait_process_frames(1)
	var far := 0.0
	var reversed := false
	var last_x := start.x
	for i in 3600:
		_tick(m, 1)
		far = maxf(far, m.global_position.distance_to(start))
		if m.global_position.x < last_x - 0.001:
			reversed = true
		last_x = m.global_position.x
	assert_lte(far, 121.0, "never beyond the leash + 1 px")
	assert_gt(far, 100.0, "it did travel the leash")
	assert_true(reversed, "it ping-pongs")
	assert_true(is_instance_valid(m) and not m.is_fizzling() and _registered(m), "and stays live")
	assert_almost_eq(m.global_position.y, start.y, 0.001, "along its direction only")


func test_a_leashed_drifter_follows_its_moving_parent() -> void:
	var field := Node2D.new()
	_container.add_child(field)
	var m := _variant_mine(EnemyMine.Variant.DRIFTING, field, Vector2.ZERO, func(x: EnemyMine) -> void:
		x.placed = true
		x.drift_direction = Vector2.RIGHT
		x.drift_leash = 120.0)
	m.position = Vector2(50, 0)
	await wait_process_frames(1)
	field.position = Vector2(0, 500)
	_tick(m, 60)
	assert_almost_eq(m.global_position.y, 500.0, 0.001, "position writes are local: the field carries the mine")


## The mine under test, a player at [param player_offset] from it, hand-ticked. Launch point (400, 600).
func _homing(harness: RefCounted, player_offset: Vector2, setup: Callable = Callable()) -> EnemyMine:
	var at := Vector2(400, 600)
	var m := _variant_mine(EnemyMine.Variant.HOMING, harness.root, at, setup)
	m.launch(Vector2.DOWN, 0.0, at)
	harness.player.global_position = at + player_offset
	return m


func test_a_homing_mine_does_not_move_before_it_is_armed(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var m := _homing(harness, Vector2(200, 0))
	var start := m.global_position
	_tick(m, int(m.arm_delay / DT) - 2)
	assert_false(m.is_armed())
	assert_eq(m.global_position, start, "armed after arm_delay: no creep before")
	_tick(m, 40)
	assert_true(m.is_armed())
	assert_ne(m.global_position, start, "and then it notices a player 200 px away")


func test_a_homing_mine_notices_at_250_px_and_not_at_270(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var far := _homing(harness, Vector2(270, 0))
	var near := _variant_mine(EnemyMine.Variant.HOMING, harness.root, Vector2(400, 1000))
	near.launch(Vector2.DOWN, 0.0, near.global_position)
	var far_start := far.global_position
	var near_start := near.global_position
	var player_far: Node2D = harness.player
	for i in 120:
		player_far.global_position = far_start + Vector2(270, 0)
		_tick(far, 1)
		# The second mine reads the same single player: put it within 250 px of that one only for its own tick.
		player_far.global_position = near_start + Vector2(250, 0)
		_tick(near, 1)
	assert_eq(far.global_position, far_start, "270 px is just outside notice_radius: no motion")
	assert_gt(near.global_position.x, near_start.x + 10.0, "250 px: it creeps toward the player")


func test_a_homing_mine_creeps_at_60_and_reports_its_velocity(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var m := _homing(harness, Vector2(0, 200))  # straight ahead of its launch heading (DOWN)
	_tick(m, 40)
	assert_true(m.is_armed())
	var before := m.global_position
	_tick(m, 1)
	assert_almost_eq(m.global_position.distance_to(before), 60.0 * DT, 0.001, "home_speed 60 px/s per tick")
	assert_almost_eq(m.hazard_info().velocity.length(), 60.0, 0.001, "HazardInfo.velocity is its creep")
	harness.player.global_position = Vector2(400, 600) + Vector2(0, 2000)
	_tick(m, 1)
	assert_eq(m.hazard_info().velocity, Vector2.ZERO, "and zero when it is not creeping")


func test_a_homing_mine_turns_at_most_home_turn_rate_toward_the_live_player(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var m := _homing(harness, Vector2(250, 0))  # launched heading DOWN, player to the right
	_tick(m, 30)
	var worst := 0.0
	for i in 120:
		var before := m.heading()
		_tick(m, 1)
		worst = maxf(worst, absf(before.angle_to(m.heading())))
	assert_lte(worst, m.home_turn_rate * DT + 0.0005, "never faster than 2.0 rad/s")
	assert_gt(worst, m.home_turn_rate * DT * 0.9, "and it does turn at that rate")
	var to_player: Vector2 = (harness.player.global_position - m.global_position).normalized()
	assert_gt(m.heading().dot(to_player), 0.99, "after a second or two it is heading at the player")
	# The live player: it follows a player that moves.
	harness.player.global_position = m.global_position + Vector2(-200, 0)
	_tick(m, 120)
	assert_lt(m.heading().x, -0.9, "it re-aims at the player's new side")


func test_a_homing_mine_loses_a_retreating_player_past_380_px(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var m := _homing(harness, Vector2(250, 0))
	_tick(m, 30)
	var lost_at := Vector2.INF
	for i in 600:
		harness.player.global_position += Vector2(120.0 * DT, 0)
		var before := m.global_position
		_tick(m, 1)
		var gap := m.global_position.distance_to(harness.player.global_position)
		if lost_at == Vector2.INF and m.global_position == before and i > 5:
			lost_at = m.global_position
			assert_gte(gap, 379.0, "it stops creeping only once the gap passes ~380 px")
			assert_lte(gap, 385.0)
	assert_ne(lost_at, Vector2.INF, "it lost the player")
	assert_eq(m.global_position, lost_at, "and stayed put for the rest of the retreat")
	# It does not re-notice until the player is within 260 px again (hysteresis): 300 px is inside lose, outside notice.
	harness.player.global_position = m.global_position + Vector2(300, 0)
	_tick(m, 60)
	assert_eq(m.global_position, lost_at, "a lost player at 300 px is not re-noticed")
	harness.player.global_position = m.global_position + Vector2(250, 0)
	_tick(m, 60)
	assert_ne(m.global_position, lost_at, "inside notice_radius it creeps again")


func test_a_player_faster_than_60_outruns_a_homing_mine(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var m := _homing(harness, Vector2(250, 0))
	_tick(m, 30)
	for i in 900:
		harness.player.global_position += Vector2(70.0 * DT, 0)
		_tick(m, 1)
	assert_gte(m.global_position.distance_to(harness.player.global_position), 250.0, "a 70 px/s player is never caught")
	assert_false(m.is_warning(), "and never trips it")


func test_a_homing_mine_with_no_player_does_not_move(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var m := _homing(harness, Vector2(100, 0))
	harness.player.remove_from_group(&"player")
	var start := m.global_position
	_tick(m, 120)
	assert_eq(m.global_position, start)


func test_a_homing_mine_never_ends_more_than_900_px_from_launch(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var start := Vector2(640, 500)
	var m := _variant_mine(EnemyMine.Variant.HOMING, harness.root, start)
	m.launch(Vector2.UP, 0.0, start)
	var farthest := 0.0
	var inside := true
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	for i in 1500:  # 25 s: past the 15 s it needs to creep 900 px
		harness.player.global_position = m.global_position + Vector2(0, -200)
		_tick(m, 1)
		if not is_instance_valid(m):
			break
		farthest = maxf(farthest, m.global_position.distance_to(start))
		if harness.is_assault and not rect.has_point(m.global_position):
			inside = false
	assert_true(is_instance_valid(m) and not m.is_fizzling(), "it holds, it does not expire")
	assert_lte(farthest, 900.0 + 0.001, "never beyond home_max_distance")
	assert_gt(farthest, 899.0, "and it did reach the cap")
	assert_true(inside, "Assault: it holds at its own cap before the corridor's projectile rect (y -444)")


# ---------------------------------------------------------------------------------------------
# Chain mines and chain propagation (§2.5, task t4). Dual-mode and hand-ticked: the chain is registry-driven
# (`Hazards.around()`, then centre distance), so only the shot rows need real physics (8x).
# ---------------------------------------------------------------------------------------------

## A hand-ticked scenario: the mines in it, a tick counter, and when (which tick) and how often each one expired.
class _Row extends RefCounted:
	var mines: Array[EnemyMine] = []
	var ticks: int = 0
	var at: Dictionary = {}
	var count: Dictionary = {}

	func watch(m: EnemyMine) -> void:
		m.expired.connect(_on_expired.bind(m))

	func _on_expired(m: EnemyMine) -> void:
		count[m] = int(count.get(m, 0)) + 1
		if not at.has(m):
			at[m] = ticks

	## Seconds between two mines' first `expired` (the tick the second was set off minus the first's).
	func gap(a: EnemyMine, b: EnemyMine) -> float:
		return float(int(at[b]) - int(at[a])) / 60.0


## A launched, hand-ticked [param variant] mine at [param at], part of [param row].
func _row_mine(row: _Row, harness: RefCounted, variant: int, at: Vector2, setup: Callable = Callable()) -> EnemyMine:
	var m := _variant_mine(variant, harness.root, at, setup)
	m.launch(Vector2.ZERO, 0.0, at)
	row.watch(m)
	row.mines.append(m)
	return m


func _tick_row(row: _Row, ticks: int) -> void:
	for i in ticks:
		row.ticks += 1
		for m in row.mines:
			_tick(m, 1)


func test_the_chain_scene_is_built_and_numbered() -> void:
	var c := EnemyMine.Variant.CHAIN
	assert_not_null(EnemyMineScenes.scene_for(c), "chain_mine.tscn is built")
	assert_eq(int(_export(c, &"variant")), c)
	assert_eq(int(_export(c, &"kind")), EnemyOrdnance.Kind.MINE)
	assert_eq(_export(c, &"chain_radius"), 150.0)
	assert_eq(_export(c, &"chain_delay"), 0.2)
	assert_eq(_export(c, &"shot_detonates"), 1.0, "a shot chain mine detonates")
	assert_eq(_export(EnemyMine.Variant.PROXIMITY, &"shot_detonates"), 0.0, "a shot proximity mine still defuses")
	assert_eq(_export(c, &"trigger_radius"), 80.0)
	assert_eq(_export(c, &"warning_time"), 0.25)
	assert_eq(_export(c, &"blast_radius"), 48.0)
	assert_eq(_export(c, &"blast_damage"), 30.0)


## Four chain mines 120 px apart: 0 / 0.2 / 0.4 / 0.6 s. A proximity mine 120 px on is chained at 0.8 s and, not being
## a chain mine, stops it: the one 120 px beyond never goes. Every mine expires exactly once.
func test_a_chain_ripples_at_0_2_s_a_hop_and_a_proximity_mine_ends_it(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var row := _Row.new()
	var chain: Array[EnemyMine] = []
	for i in 4:
		chain.append(_row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100.0 + 120.0 * i, 300)))
	var stopper := _row_mine(row, harness, EnemyMine.Variant.PROXIMITY, Vector2(100.0 + 120.0 * 4, 300))
	var beyond := _row_mine(row, harness, EnemyMine.Variant.PROXIMITY, Vector2(100.0 + 120.0 * 5, 300))
	chain[0].chain_trigger(0.0)
	_tick_row(row, 150)
	for i in 4:
		assert_true(row.at.has(chain[i]), "%s: chain mine %d detonated" % [mode, i])
		assert_almost_eq(row.gap(chain[0], chain[i]), 0.2 * i, DT + 1e-6, "%s: chain mine %d at %.1f s" % [mode, i, 0.2 * i])
	assert_almost_eq(row.gap(chain[0], stopper), 0.8, DT + 1e-6, "%s: the proximity mine 120 px on goes at 0.8 s" % mode)
	assert_false(row.at.has(beyond), "%s: a non-chain mine propagates nothing" % mode)
	assert_true(beyond.is_armed() and not beyond.is_warning(), "%s: the one beyond it is untouched" % mode)
	for m in row.mines:
		if m != beyond:
			assert_eq(int(row.count.get(m, 0)), 1, "%s: expired exactly once" % mode)
	assert_eq(int(row.count.get(beyond, 0)), 0)


func test_chain_radius_149_is_reached_and_151_is_not(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var row := _Row.new()
	var near_a := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100, 200))
	var near_b := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100 + 149, 200))
	var far_a := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100, 700))
	var far_b := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100 + 151, 700))
	near_a.chain_trigger(0.0)
	far_a.chain_trigger(0.0)
	_tick_row(row, 90)
	assert_true(row.at.has(near_b), "%s: 149 px is within chain_radius" % mode)
	assert_false(row.at.has(far_b), "%s: 151 px is not (centre distance, not the 140 px footprint)" % mode)
	assert_true(row.at.has(far_a), "control: the triggered one itself went")


## A chain is physical: no warning, armed or not. A chained mine that already ended is never re-triggered, and a mine
## already chained keeps its first (here the longer) delay.
func test_a_chained_mine_skips_its_warning_and_is_never_triggered_twice(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var row := _Row.new()
	var a := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100, 300))
	var b := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(220, 300))
	assert_false(b.is_armed(), "precondition: not even armed yet (arm_delay %.1f s)" % b.arm_delay)
	b.chain_trigger(1.0)
	b.chain_trigger(0.0)  # already chained: ignored
	a.chain_trigger(0.0)
	_tick_row(row, 30)
	assert_true(row.at.has(a))
	assert_false(row.at.has(b), "%s: b keeps its first delay (1.0 s), not the second call's" % mode)
	assert_false(b.is_warning(), "no warning of its own")
	_tick_row(row, 45)
	assert_almost_eq(row.gap(a, b), 1.0, 3.0 * DT, "%s: and detonates at that delay" % mode)
	# A done mine: ignored, still exactly one `expired`.
	a.chain_trigger(0.0)
	b.chain_trigger(0.0)
	_tick_row(row, 20)
	assert_eq(int(row.count[a]), 1)
	assert_eq(int(row.count[b]), 1)
	# An unlaunched mine is not chained either.
	var idle := _variant_mine(EnemyMine.Variant.CHAIN, harness.root, Vector2(900, 300))
	row.watch(idle)
	idle.chain_trigger(0.0)
	_tick(idle, 30)
	assert_eq(int(row.count.get(idle, 0)), 0, "an idle pooled mine is left alone")


func test_a_recycled_chain_mine_is_not_still_chained() -> void:
	var m := _hand_ticked_variant(EnemyMine.Variant.CHAIN)
	m.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	m.chain_trigger(0.5)
	m.reset()
	m.launch(Vector2.ZERO, 0.0, Vector2.ZERO)
	var ended := [0]
	m.expired.connect(func() -> void: ended[0] += 1)
	_tick(m, 120)
	assert_eq(ended[0], 0, "reset() clears the chain: 2 s later it is still live")
	assert_true(m.is_armed() and not m.is_warning())


func _hand_ticked_variant(variant: int) -> EnemyMine:
	var m := EnemyMineScenes.scene_for(variant).instantiate() as EnemyMine
	m.process_mode = Node.PROCESS_MODE_DISABLED
	_container.add_child(m)
	return m


## A PLAYER chain mine sets off an ALL mine, whose blast is `Hazards.pulse_damage` (hurts enemies) - not the chain
## mine's own `ContactBlast` (the player only).
func test_a_player_chain_mine_sets_off_an_all_mine_and_that_hurts_enemies(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var row := _Row.new()
	var chain := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100, 300))
	var all_mine := _row_mine(row, harness, EnemyMine.Variant.PROXIMITY, Vector2(220, 300),
			func(m: EnemyMine) -> void: m.hostility = EnemyMine.Hostility.ALL)
	var enemy := _visible_enemy(Vector2(220, 330), harness.root)
	var health := enemy.get_node("Health") as Health
	var p := _player(Vector2(220, 270), harness.root)
	assert_eq(chain.hostility, EnemyMine.Hostility.PLAYER)
	chain.chain_trigger(0.0)
	_tick_row(row, 30)
	assert_true(row.at.has(all_mine), "%s: the ALL mine was chained" % mode)
	assert_eq(health.current_health, 100 - all_mine.blast_damage, "%s: pulse_damage reached the enemy" % mode)
	assert_eq(int(p.get_meta(&"damage")), all_mine.blast_damage, "%s: and the player" % mode)


## `link_points()` lists exactly the live mines within `chain_radius` (centre distance), refreshed every 0.5 s of the
## mine's own clock; a mine that is not a chain mine has none.
func test_link_points_list_exactly_the_neighbours_within_chain_radius(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var row := _Row.new()
	var a := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100, 300))
	var b := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(220, 300))
	var _far := _row_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100, 600))
	assert_eq(a.link_points().size(), 0, "nothing is computed before its first refresh")
	_tick_row(row, 31)
	assert_eq(a.link_points(), [b.global_position] as Array[Vector2], "%s: only the mine 120 px away (not the one 300 px away)" % mode)
	# A mine that appears 140 px away is not listed until the next 0.5 s refresh.
	var p := _row_mine(row, harness, EnemyMine.Variant.PROXIMITY, Vector2(100, 440))
	_tick_row(row, 10)
	assert_eq(a.link_points().size(), 1, "%s: still the old set 0.17 s later" % mode)
	_tick_row(row, 60)
	var links := a.link_points()
	assert_eq(links.size(), 2, "%s: refreshed" % mode)
	assert_true(links.has(b.global_position) and links.has(p.global_position))
	assert_eq(p.link_points().size(), 0, "a proximity mine draws no links")
	# A neighbour that fizzled (retire, no blast, so no ripple) drops out at once, and stays out at the next refresh.
	b.retire()
	_tick_row(row, 80)
	assert_eq(a.link_points(), [p.global_position] as Array[Vector2], "%s: the retired neighbour is gone" % mode)


## Real physics (8x): shooting a chain mine detonates it and every neighbour in the ripple; shooting a proximity mine
## still defuses it (no blast, one `expired`).
func test_shooting_a_chain_mine_detonates_the_group_and_a_proximity_mine_still_defuses(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var harness = _world(mode)
	harness.root.child_entered_tree.connect(_on_container_child)
	var row := _Row.new()
	var chain: Array[EnemyMine] = []
	for i in 3:
		chain.append(_live_mine(row, harness, EnemyMine.Variant.CHAIN, Vector2(100.0 + 120.0 * i, 300)))
	var proximity := _live_mine(row, harness, EnemyMine.Variant.PROXIMITY, Vector2(100, 800))
	await wait_physics_frames(3)
	var shot := _ordnance_shot(chain[0].global_position, harness.root)
	await _seconds(1.0)
	assert_eq(_blasts.size(), 3, "%s: the shot mine and both neighbours blast" % mode)
	for m in chain:
		assert_eq(int(row.count.get(m, 0)), 1, "%s: expired exactly once" % mode)
	assert_eq(int(row.count.get(proximity, 0)), 0, "control: the proximity mine was not touched")
	shot.queue_free()
	var shot2 := _ordnance_shot(proximity.global_position, harness.root)
	await _seconds(0.5)
	assert_eq(_blasts.size(), 3, "%s: shooting a proximity mine defuses it: no blast" % mode)
	assert_eq(int(row.count.get(proximity, 0)), 1, "%s: expired once" % mode)
	shot2.queue_free()


## A launched mine with its own processing on (real physics), part of [param row].
func _live_mine(row: _Row, harness: RefCounted, variant: int, at: Vector2) -> EnemyMine:
	var m := EnemyMineScenes.scene_for(variant).instantiate() as EnemyMine
	harness.root.add_child(m)
	m.global_position = at
	m.launch(Vector2.ZERO, 0.0, at)
	row.watch(m)
	row.mines.append(m)
	return m


func _ordnance_shot(at: Vector2, parent: Node) -> HitBox:
	var hb := HitBox.new()
	hb.collision_layer = CollisionLayers.PLAYER_HITBOX
	hb.collision_mask = 0
	hb.damage = 50
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	hb.add_child(shape)
	parent.add_child(hb)
	hb.global_position = at
	return hb


# ---------------------------------------------------------------------------------------------
# The pulse mine (plan §2.7): a small blast, a violet ring, and the player's boost weakened
# ---------------------------------------------------------------------------------------------

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")


## The REAL player of [param mode] (`player_ship.tscn` / `player_fighter.tscn`) at [param at] in [param parent], its own
## physics off so it stays where it is put. Records every hit its `HurtBox` takes in `meta damage`.
func _real_player(mode: String, at: Vector2, parent: Node) -> PlayerBase:
	var p := (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate() as PlayerBase
	parent.add_child(p)
	p.set_physics_process(false)
	p.global_position = at
	p.set_meta(&"damage", 0)
	var hurt := p.get_node("HurtBox") as HurtBox
	hurt.received_damage.connect(func(d: int) -> void: p.set_meta(&"damage", int(p.get_meta(&"damage")) + d))
	return p


func test_the_pulse_scene_is_built_and_numbered() -> void:
	var v := EnemyMine.Variant.PULSE
	assert_not_null(EnemyMineScenes.scene_for(v), "PULSE has a scene")
	assert_eq(int(_export(v, &"variant")), v)
	assert_eq(_export(v, &"pulse_radius"), 170.0)
	assert_eq(_export(v, &"disrupt_strength"), 0.6)
	assert_eq(_export(v, &"disrupt_seconds"), 2.5)
	assert_eq(_export(v, &"blast_damage"), 8.0, "a small blast, not the shared 30")
	assert_eq(_export(v, &"blast_radius"), 48.0)
	assert_eq(_export(v, &"trigger_radius"), 80.0)
	assert_eq(_export(v, &"warning_time"), 0.25)
	assert_true(_warning_rule(_export(v, &"trigger_radius"), _export(v, &"blast_radius"), _export(v, &"blast_damage"),
			_export(v, &"emp_radius"), _export(v, &"warning_time"), 0.0),
			"the warning inequality uses blast_radius (8 damage > 0): 512 >= 440")
	assert_almost_eq((_export(v, &"trigger_radius") + _export(v, &"blast_radius")) / _export(v, &"warning_time"), 512.0, 0.001)


## Hand-ticked: a chained PULSE mine at the origin, two real players of the mode at 150 / 170 / 180 px. `_disrupt_players`
## is centre distance, `<=` radius.
func test_a_pulse_detonation_disrupts_inside_170_px_and_not_at_180(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var at := Vector2(400, 300)
	var near := _real_player(mode, at + Vector2(150, 0), harness.root)
	var edge := _real_player(mode, at + Vector2(0, 170), harness.root)
	var far := _real_player(mode, at + Vector2(-180, 0), harness.root)
	var m := _row_mine(_Row.new(), harness, EnemyMine.Variant.PULSE, at)
	assert_eq(near.boost_efficiency(), 1.0, "%s: nothing is disrupted before the blast" % mode)
	m.chain_trigger(0.0)
	_tick(m, 3)
	assert_almost_eq(near.boost_efficiency(), 0.4, 0.0001, "%s: 150 px: efficiency 0.4" % mode)
	assert_almost_eq(edge.boost_efficiency(), 0.4, 0.0001, "%s: exactly 170 px is inside" % mode)
	assert_eq(far.boost_efficiency(), 1.0, "%s: 180 px is untouched" % mode)


func test_a_pulse_disruption_lasts_2_5_s_and_only_a_pulse_mine_applies_it(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var at := Vector2(400, 300)
	var p := _real_player(mode, at + Vector2(40, 0), harness.root)
	var control := _row_mine(_Row.new(), harness, EnemyMine.Variant.PROXIMITY, at + Vector2(0, 600))
	control.global_position = at
	control.chain_trigger(0.0)
	_tick(control, 3)
	assert_eq(p.boost_efficiency(), 1.0, "%s: a proximity blast disrupts nothing" % mode)
	var m := _row_mine(_Row.new(), harness, EnemyMine.Variant.PULSE, at)
	m.chain_trigger(0.0)
	_tick(m, 3)
	for i in 149:
		p._step_disruption(DT)
	assert_almost_eq(p.boost_efficiency(), 0.4, 0.0001, "%s: still disrupted just before 2.5 s" % mode)
	for i in 3:
		p._step_disruption(DT)
	assert_eq(p.boost_efficiency(), 1.0, "%s: over at 2.5 s" % mode)


## An ALL pulse mine blasts through `Hazards.pulse_damage`: 8 on the real player's hurtbox, not 30, and it disrupts.
func test_an_all_pulse_mine_deals_8_and_disrupts(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var at := Vector2(400, 300)
	var p := _real_player(mode, at + Vector2(20, 0), harness.root)
	var m := _row_mine(_Row.new(), harness, EnemyMine.Variant.PULSE, at,
			func(mm: EnemyMine) -> void: mm.hostility = EnemyMine.Hostility.ALL)
	m.chain_trigger(0.0)
	_tick(m, 3)
	assert_eq(int(p.get_meta(&"damage")), 8, "%s: 8 damage, not 30" % mode)
	assert_almost_eq(p.boost_efficiency(), 0.4, 0.0001, "%s: and the boost is weakened" % mode)


func test_a_pulse_mine_without_the_player_hook_or_in_range_reaches_nobody() -> void:
	var m := _hand_ticked_variant(EnemyMine.Variant.PULSE)
	var bare := CharacterBody2D.new()
	bare.add_to_group(&"player")
	_container.add_child(bare)
	assert_eq(m._disrupt_players(170.0, 0.6, 2.5), 0, "a player stand-in without apply_boost_disruption is skipped")


## Real physics (8x), the real player of each mode standing on a live PULSE mine: it arms, shows the violet effect ring
## during the warning only, blasts for 8 through the real `ContactBlast` (not 30), weakens the boost to 0.4, and leaves a
## self-freeing `PulseRing` in the container.
func test_a_real_pulse_mine_warns_with_a_ring_blasts_for_8_and_disrupts(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var harness = _world(mode)
	harness.root.child_entered_tree.connect(_on_container_child)
	var at := Vector2(300, 300)
	var m := EnemyMineScenes.scene_for(EnemyMine.Variant.PULSE).instantiate() as EnemyMine
	harness.root.add_child(m)
	m.global_position = at
	m.expired.connect(m.queue_free)
	m.launch(Vector2.ZERO, 0.0, at)
	var p := _real_player(mode, at + Vector2(10, 0), harness.root)
	var seen := {"mine": m, "ring_before": false, "ring_warning": 0.0}
	var watch := func() -> void:
		# Holds the mine in a dictionary: a lambda capturing the mine itself errors once it is freed.
		var mine: EnemyMine = seen["mine"] if is_instance_valid(seen["mine"]) else null
		if mine == null:
			return
		if mine.is_warning():
			seen["ring_warning"] = maxf(seen["ring_warning"], mine.effect_ring_radius())
		elif mine.effect_ring_radius() > 0.0:
			seen["ring_before"] = true
	_tick_each_frame(harness.root, watch)
	await _seconds(1.5)
	assert_false(is_instance_valid(m), "%s: the mine detonated" % mode)
	assert_false(seen["ring_before"], "%s: no effect ring outside the warning" % mode)
	assert_eq(seen["ring_warning"], 170.0, "%s: the violet effect ring shows during the warning" % mode)
	assert_eq(int(p.get_meta(&"damage")), 8, "%s: the blast deals 8, not 30" % mode)
	assert_almost_eq(p.boost_efficiency(), 0.4, 0.0001, "%s: the real blast weakened the boost (its physics is off, so it holds)" % mode)
	assert_eq(_blasts.size(), 1, "%s: one small blast" % mode)


## The ring: spawned at the mine's point in its parent on detonation, expanding to 170 px over 0.3 s, then gone.
func test_a_detonation_leaves_a_self_freeing_violet_ring(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var harness = _world(mode)
	var at := Vector2(500, 300)
	var m := _row_mine(_Row.new(), harness, EnemyMine.Variant.PULSE, at)
	m.chain_trigger(0.0)
	_tick(m, 3)
	var rings: Array[PulseRing] = []
	for c in harness.root.get_children():
		if c is PulseRing:
			rings.append(c)
	assert_eq(rings.size(), 1, "%s: exactly one ring" % mode)
	var ring := rings[0]
	assert_eq(ring.global_position, at, "%s: at the mine" % mode)
	assert_eq(ring.max_radius, 170.0)
	assert_eq(ring.default_color.b > ring.default_color.g, true, "%s: violet" % mode)
	await _seconds(PulseRing.DURATION + 0.2)
	assert_false(is_instance_valid(ring), "%s: it frees itself on its own clock" % mode)


# ---------------------------------------------------------------------------------------------
# The EMP mine (plan §2.8): no damage, an EMP through the one hook, a blue-white crackle ring
# ---------------------------------------------------------------------------------------------


func test_the_emp_scene_is_built_and_numbered_and_passes_the_warning_rule_on_emp_radius() -> void:
	var v := EnemyMine.Variant.EMP
	assert_not_null(EnemyMineScenes.scene_for(v), "EMP has a scene")
	assert_eq(int(_export(v, &"variant")), v)
	assert_eq(_export(v, &"emp_radius"), 190.0)
	assert_eq(_export(v, &"emp_seconds"), 2.0)
	assert_eq(_export(v, &"blast_damage"), 0.0, "no hull damage")
	assert_eq(_export(v, &"trigger_radius"), 80.0)
	assert_eq(_export(v, &"warning_time"), 0.25)
	assert_true(_warning_rule(_export(v, &"trigger_radius"), _export(v, &"blast_radius"), _export(v, &"blast_damage"),
			_export(v, &"emp_radius"), _export(v, &"warning_time"), 0.0),
			"blast_damage 0, so emp_radius is the effect radius: (80 + 190) / 0.25 = 1080 >= 440")
	assert_almost_eq((_export(v, &"trigger_radius") + _export(v, &"emp_radius")) / _export(v, &"warning_time"), 1080.0, 0.001)
	# Boundary: the rule really reads emp_radius for this scene (a blast_radius-only read gives 512, also passing, so
	# prove it with a synthetic zero-effect EMP that fails).
	assert_false(_warning_rule(80.0, 48.0, 0.0, 0.0, 0.25, 0.0), "an EMP with no radius would give 320 < 440")


## Hand-ticked: a chained EMP mine, real players of the mode at 150 / 190 / 191 px. Centre distance, `<=` radius; no
## Health damage on anyone, no blast.
func test_an_emp_detonation_reaches_inside_190_px_and_deals_no_damage(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	harness.root.child_entered_tree.connect(_on_container_child)
	var at := Vector2(400, 300)
	var near := _real_player(mode, at + Vector2(150, 0), harness.root)
	var edge := _real_player(mode, at + Vector2(0, 190), harness.root)
	var far := _real_player(mode, at + Vector2(-191, 0), harness.root)
	var m := _row_mine(_Row.new(), harness, EnemyMine.Variant.EMP, at)
	assert_false(near.is_emp_disrupted(), "%s: nothing is disrupted before the blast" % mode)
	m.chain_trigger(0.0)
	_tick(m, 3)
	assert_true(near.is_emp_disrupted(), "%s: 150 px: disrupted" % mode)
	assert_true(edge.is_emp_disrupted(), "%s: exactly 190 px is inside" % mode)
	assert_false(far.is_emp_disrupted(), "%s: 191 px is untouched" % mode)
	assert_eq(near.boost_efficiency(), 0.0, "%s: the stand-in effect is a full disruption" % mode)
	for p in [near, edge, far]:
		assert_eq(int(p.get_meta(&"damage")), 0, "%s: no Health damage" % mode)
	assert_eq(_blasts.size(), 0, "%s: no ContactBlast" % mode)


func test_an_emp_lasts_2_s_and_a_hostility_all_emp_mine_still_deals_no_damage(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var at := Vector2(400, 300)
	var p := _real_player(mode, at + Vector2(20, 0), harness.root)
	var m := _row_mine(_Row.new(), harness, EnemyMine.Variant.EMP, at,
			func(mm: EnemyMine) -> void: mm.hostility = EnemyMine.Hostility.ALL)
	m.chain_trigger(0.0)
	_tick(m, 3)
	assert_eq(int(p.get_meta(&"damage")), 0, "%s: no pulse_damage either" % mode)
	for i in 119:
		p._step_disruption(DT)
	assert_true(p.is_emp_disrupted(), "%s: still disrupted just before 2.0 s" % mode)
	for i in 3:
		p._step_disruption(DT)
	assert_false(p.is_emp_disrupted(), "%s: over at 2.0 s" % mode)


## A PROXIMITY or PULSE detonation never calls the EMP hook (control).
func test_only_an_emp_mine_applies_an_emp(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var at := Vector2(400, 300)
	var p := _real_player(mode, at + Vector2(20, 0), harness.root)
	for v: int in [EnemyMine.Variant.PROXIMITY, EnemyMine.Variant.PULSE]:
		var m := _row_mine(_Row.new(), harness, v, at)
		m.chain_trigger(0.0)
		_tick(m, 3)
	assert_false(p.is_emp_disrupted(), "%s: neither a proximity nor a pulse blast is an EMP" % mode)


## Real physics (8x): the real player standing on a live EMP mine. It arms, shows the blue-white effect ring during the
## warning only, detonates, disrupts the player and deals no Health damage and spawns no blast.
func test_a_real_emp_mine_warns_with_a_ring_and_disrupts_without_damage(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var harness = _world(mode)
	harness.root.child_entered_tree.connect(_on_container_child)
	var at := Vector2(300, 300)
	var m := EnemyMineScenes.scene_for(EnemyMine.Variant.EMP).instantiate() as EnemyMine
	harness.root.add_child(m)
	m.global_position = at
	m.expired.connect(m.queue_free)
	m.launch(Vector2.ZERO, 0.0, at)
	var p := _real_player(mode, at + Vector2(10, 0), harness.root)
	var seen := {"mine": m, "ring_before": false, "ring_warning": 0.0}
	var watch := func() -> void:
		var mine: EnemyMine = seen["mine"] if is_instance_valid(seen["mine"]) else null
		if mine == null:
			return
		if mine.is_warning():
			seen["ring_warning"] = maxf(seen["ring_warning"], mine.effect_ring_radius())
		elif mine.effect_ring_radius() > 0.0:
			seen["ring_before"] = true
	_tick_each_frame(harness.root, watch)
	await _seconds(1.5)
	assert_false(is_instance_valid(m), "%s: the mine detonated" % mode)
	assert_false(seen["ring_before"], "%s: no effect ring outside the warning" % mode)
	assert_eq(seen["ring_warning"], 190.0, "%s: the effect ring shows emp_radius during the warning" % mode)
	assert_true(p.is_emp_disrupted(), "%s: the real mine reached the real player" % mode)
	assert_eq(int(p.get_meta(&"damage")), 0, "%s: and dealt no Health damage" % mode)
	assert_eq(_blasts.size(), 0, "%s: no blast" % mode)


## The crackle ring: spawned at the mine's point in its parent, 190 px, blue-white, gone after 0.35 s on its own clock.
func test_an_emp_detonation_leaves_a_self_freeing_blue_white_ring(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var harness = _world(mode)
	var at := Vector2(500, 300)
	var m := _row_mine(_Row.new(), harness, EnemyMine.Variant.EMP, at)
	m.chain_trigger(0.0)
	_tick(m, 3)
	var rings: Array[EmpRing] = []
	for c in harness.root.get_children():
		if c is EmpRing:
			rings.append(c)
	assert_eq(rings.size(), 1, "%s: exactly one ring" % mode)
	var ring := rings[0]
	assert_eq(ring.global_position, at, "%s: at the mine" % mode)
	assert_eq(ring.max_radius, 190.0)
	assert_true(ring.default_color.b > ring.default_color.r and ring.default_color.g > ring.default_color.r,
			"%s: blue-white" % mode)
	assert_eq(EmpRing.DURATION, 0.35)
	await _seconds(EmpRing.DURATION + 0.2)
	assert_false(is_instance_valid(ring), "%s: it frees itself on its own clock" % mode)


# ---------------------------------------------------------------------------------------------
# Art (t9): every variant wears its own top-down sprite; the state lights are drawn on top
# ---------------------------------------------------------------------------------------------

const _MINE_ART_DIR := "res://assault/assets/sprites/projectiles/mines/"
const _MINE_ART := {
	EnemyMine.Variant.PROXIMITY: "mine_proximity.png",
	EnemyMine.Variant.DRIFTING: "mine_drifting.png",
	EnemyMine.Variant.HOMING: "mine_homing.png",
	EnemyMine.Variant.CHAIN: "mine_chain.png",
	EnemyMine.Variant.PULSE: "mine_pulse.png",
	EnemyMine.Variant.EMP: "mine_emp.png",
}


## Every variant scene has its own `Sprite` (`Sprite2D`) at its centre with an opaque pixel under the middle, a transparent
## corner (no painted-in card) and a body that is no longer the `body_color` circle; no two variants share a texture
## (one silhouette per variant). The Bomber's mine is the PROXIMITY one.
func test_every_variant_scene_wears_its_own_opaque_sprite_at_its_centre(variant: int = use_parameters(_MINE_ART.keys())) -> void:
	var mine: EnemyMine = EnemyMineScenes.scene_for(variant).instantiate()
	add_child_autofree(mine)
	mine.process_mode = Node.PROCESS_MODE_DISABLED
	var sprite := mine.get_node_or_null("Sprite") as Sprite2D
	assert_not_null(sprite, "variant %d: a Sprite2D named Sprite" % variant)
	if sprite == null:
		return
	assert_eq(sprite.position, Vector2.ZERO, "variant %d: at the mine's centre" % variant)
	assert_true(sprite.show_behind_parent, "variant %d: the state lights are drawn on top of the sprite" % variant)
	assert_not_null(sprite.texture, "variant %d: it has a texture" % variant)
	assert_eq(sprite.texture.resource_path, _MINE_ART_DIR + _MINE_ART[variant], "variant %d: its own art" % variant)
	var img := sprite.texture.get_image()
	assert_eq(img.get_size(), Vector2i(24, 24), "variant %d: 24 x 24" % variant)
	assert_gt(img.get_pixel(12, 12).a, 0.99, "variant %d: opaque at the centre" % variant)
	assert_eq(img.get_pixel(0, 0).a, 0.0, "variant %d: transparent corner" % variant)
	assert_eq(img.get_pixel(23, 23).a, 0.0, "variant %d: transparent corner" % variant)
	assert_eq(EnemyMineScenes.export_of(variant, &"body_color", null), null, "variant %d: body_color is gone from the scene" % variant)


func test_no_two_variants_share_a_texture() -> void:
	var paths := {}
	var masks: Array = []
	for variant: int in _MINE_ART:
		var path: String = _MINE_ART_DIR + _MINE_ART[variant]
		assert_false(paths.has(path), "%s is used once" % path)
		paths[path] = true
		var img := (load(path) as Texture2D).get_image()
		# A silhouette per variant: no two sprites have the same alpha mask.
		var mask := PackedByteArray()
		for y in img.get_height():
			for x in img.get_width():
				mask.append(1 if img.get_pixel(x, y).a > 0.5 else 0)
		for other: PackedByteArray in masks:
			assert_ne(mask, other, "%s has its own silhouette" % path)
		masks.append(mask)


## The homing mine's `Eye` sprite is hidden until the mine is noticing, sits toward the player, and is hidden again when it
## stops; every other variant has none.
func test_the_homing_eye_shows_only_while_noticing() -> void:
	var mine: EnemyMine = EnemyMineScenes.scene_for(EnemyMine.Variant.HOMING).instantiate()
	add_child_autofree(mine)
	mine.process_mode = Node.PROCESS_MODE_DISABLED
	var eye := mine.get_node("Eye") as Sprite2D
	assert_eq(eye.texture.resource_path, _MINE_ART_DIR + "mine_homing_eye.png")
	assert_false(eye.visible, "hidden while idle")
	mine._noticing = true
	mine._update_eye()
	assert_true(eye.visible, "shown while noticing")
	mine._noticing = false
	mine._update_eye()
	assert_false(eye.visible, "hidden again")
	for variant: int in _MINE_ART:
		if variant == EnemyMine.Variant.HOMING:
			continue
		var other: EnemyMine = EnemyMineScenes.scene_for(variant).instantiate()
		add_child_autofree(other)
		other.process_mode = Node.PROCESS_MODE_DISABLED
		assert_null(other.get_node_or_null("Eye"), "variant %d has no eye" % variant)
