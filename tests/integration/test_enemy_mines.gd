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
