## Minefields as structures (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.10, task t8): `Minefield`
## (`assault/scenes/hazards/minefield/`). INTENT tests.
##
## Pattern geometry, the ready-order boundary of an AUTHORED field, "every placed mine is ALL, placed, registered
## and alive after 60 s" in a field that holds `mine.tscn` mines (authored `mine_life` 8.0), drifting mines staying on
## their leash, the beacon, the field freeing itself, and - in BOTH modes on the 8x clock - a player stub and an
## avoidance-0 fixture being set off and damaged while an avoidance-0.8 fixture is not. Assault drift is hand-ticked.
##
## Hand-ticked rows disable the field's processing (its mines inherit that) and tick the field and its mines at a
## fixed 1/60 s. `fixture_enemy.tscn`'s `HurtBox` has no shape and the fixture joins no group, so the real-physics
## rows add a 14 px shape and group `enemies` at runtime (the shared scene is not edited). Each real-physics scenario
## runs once per mode and its numbers are shared by the rows that read them.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const FIELD: PackedScene = preload("res://assault/scenes/hazards/minefield/minefield.tscn")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const STUB_RADIUS := 12.0
const FIXTURE_HURT_RADIUS := 14.0
const CROSS_SPEED := 240.0
const ASSAULT_DRIFT := 60.0

const _SPEEDUP := 8
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false

var _container: Node2D
## Scenario results shared by the rows that read them (plain data, never nodes).
var _crossings: Dictionary = {}
var _sixty: Dictionary = {}


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)


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


func _game_step() -> float:
	return 1.0 / float(_saved_ticks if _clock_scaled else Engine.physics_ticks_per_second)


func _seconds(s: float) -> void:
	await wait_physics_frames(roundi(s / _game_step()))


# ---------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------

## A field from the scene with [param setup] applied before it enters the tree. [param hand_ticked] disables its
## processing (and so its mines'), for ticking by hand.
func _field(props: Dictionary = {}, parent: Node = null, hand_ticked: bool = false, at: Vector2 = Vector2.ZERO) -> Minefield:
	var f := FIELD.instantiate() as Minefield
	for key: String in props:
		f.set(key, props[key])
	if hand_ticked:
		f.process_mode = Node.PROCESS_MODE_DISABLED
	f.position = at
	(parent if parent != null else _container).add_child(f)
	return f


func _mine_positions(f: Minefield) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in f.mines():
		out.append(m.position)
	return out


func _registered(m: Node) -> bool:
	if not is_instance_valid(m):
		return false
	for info: HazardInfo in Hazards.around((m as Node2D).global_position, 1.0):
		if info.source == m:
			return true
	return false


func _world(mode: String) -> RefCounted:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	return harness


func _player(at: Vector2, parent: Node) -> CharacterBody2D:
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
	parent.add_child(p)
	p.global_position = at
	return p


## `fixture_enemy.tscn` made visible to a mine (a 14 px shape on its `HurtBox`, group `enemies`, both before
## `add_child`) and flying at [param velocity] with the given avoidance. Health 100.
func _enemy(at: Vector2, parent: Node, avoidance: float, velocity: Vector2) -> BaseEnemy:
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
	var mover := e.get_node("EnemyMover") as EnemyMover
	mover.hazard_avoidance = avoidance
	mover.hazard_margin = 24.0
	e.position = at
	parent.add_child(e)
	(e.get_node("Brain")).desired_velocity = velocity
	return e


class _Ticker extends Node:
	var fn: Callable

	func _physics_process(_delta: float) -> void:
		fn.call()


func _tick_each_frame(parent: Node, fn: Callable) -> Node:
	var t := _Ticker.new()
	t.fn = fn
	parent.add_child(t)
	return t


func _health(e: BaseEnemy) -> int:
	return (e.get_node("Health") as Health).current_health


# ---------------------------------------------------------------------------------------------
# Pattern geometry
# ---------------------------------------------------------------------------------------------

func test_a_ring_of_nine_lays_nine_mines_on_a_200_px_circle() -> void:
	var f := _field({"pattern": Minefield.Pattern.RING, "count": 9, "radius": 200.0}, null, true, Vector2(500, 300))
	assert_eq(f.mines().size(), 9)
	for p in _mine_positions(f):
		assert_almost_eq(p.length(), 200.0, 0.5, "every mine on the circle")
	var seen: Array[float] = []
	for p in _mine_positions(f):
		seen.append(snappedf(rad_to_deg(p.angle()), 1.0))
	seen.sort()
	assert_eq(seen.size(), 9)
	assert_almost_eq(rad_to_deg(_mine_positions(f)[1].angle()) - rad_to_deg(_mine_positions(f)[0].angle()), 40.0, 0.5,
			"evenly spread: 360 / 9 degrees apart")
	assert_eq(f.mines()[0].global_position, Vector2(500, 300) + _mine_positions(f)[0], "positions are local to the field")


func test_a_grid_keeps_its_spacing() -> void:
	var f := _field({"pattern": Minefield.Pattern.GRID, "count": 9, "spacing": 110.0}, null, true)
	var points := _mine_positions(f)
	assert_eq(points.size(), 9)
	var xs := {}
	var ys := {}
	var nearest := INF
	for i in points.size():
		xs[snappedf(points[i].x, 0.01)] = true
		ys[snappedf(points[i].y, 0.01)] = true
		for j in range(i + 1, points.size()):
			nearest = minf(nearest, points[i].distance_to(points[j]))
	assert_eq(xs.size(), 3, "3 columns")
	assert_eq(ys.size(), 3, "3 rows")
	assert_almost_eq(nearest, 110.0, 0.01, "neighbours are exactly `spacing` apart")
	var centre := Vector2.ZERO
	for p in points:
		centre += p
	assert_almost_eq((centre / 9.0).length(), 0.0, 0.01, "centred on the field")
	var g := _field({"pattern": Minefield.Pattern.GRID, "count": 10, "spacing": 50.0}, null, true)
	assert_eq(g.mines().size(), 10, "count is honoured when it is not a square (4 x 3 cells, 10 filled)")


func test_scatter_is_seed_stable() -> void:
	var make := func(seed_value: int) -> Array[Vector2]:
		var f := _field({"pattern": Minefield.Pattern.SCATTER, "count": 7, "radius": 300.0, "rng_seed": seed_value}, null, true)
		return _mine_positions(f)
	var a: Array[Vector2] = make.call(5)
	var b: Array[Vector2] = make.call(5)
	var c: Array[Vector2] = make.call(6)
	assert_eq(a.size(), 7)
	assert_eq(a, b, "the same seed gives the same points")
	assert_ne(a, c, "a different seed gives different ones")
	for p in a:
		assert_lte(p.length(), 300.0 + 0.01, "inside the disc")
	var unseeded := func() -> Array[Vector2]:
		var f := _field({"pattern": Minefield.Pattern.SCATTER, "count": 4}, null, true)
		return _mine_positions(f)
	assert_eq(unseeded.call(), unseeded.call(), "seed 0 is a fixed seed, so even an unseeded field is the same every time")


func test_weights_choose_the_variant_with_the_fields_rng() -> void:
	var only_emp := _field({"w_proximity": 0.0, "w_emp": 1.0}, null, true)
	for m in only_emp.mines():
		assert_eq(m.variant, EnemyMine.Variant.EMP, "a flat weight of 0 elsewhere leaves only EMP")
	var none := _field({"w_proximity": 0.0}, null, true)
	for m in none.mines():
		assert_eq(m.variant, EnemyMine.Variant.PROXIMITY, "all weights 0 falls back to PROXIMITY")
	var mixed := func() -> Array:
		var f := _field({"count": 12, "rng_seed": 9, "w_proximity": 1.0, "w_chain": 1.0, "w_pulse": 1.0}, null, true)
		return f.mines().map(func(m: EnemyMine) -> int: return m.variant)
	var first: Array = mixed.call()
	assert_eq(first, mixed.call(), "the same seed draws the same variants")
	assert_true(first.has(EnemyMine.Variant.PROXIMITY) and first.has(EnemyMine.Variant.CHAIN) and first.has(EnemyMine.Variant.PULSE),
			"all three weighted variants appear in 12 draws")
	assert_false(first.has(EnemyMine.Variant.EMP), "a variant with weight 0 never does")


# ---------------------------------------------------------------------------------------------
# AUTHORED fields and the ready-order boundary
# ---------------------------------------------------------------------------------------------

func _authored(positions: Array) -> Minefield:
	var f := FIELD.instantiate() as Minefield
	f.pattern = Minefield.Pattern.AUTHORED
	var mines_node := f.get_node("Mines")
	for p: Vector2 in positions:
		var m := EnemyMineScenes.scene_for(EnemyMine.Variant.PROXIMITY).instantiate() as EnemyMine
		assert_false(m.placed, "authored placed = false")
		assert_eq(m.hostility, EnemyMine.Hostility.PLAYER, "authored PLAYER")
		m.position = p
		mines_node.add_child(m)
	f.position = Vector2(100, 50)
	f.process_mode = Node.PROCESS_MODE_DISABLED
	_container.add_child(f)
	return f


func test_authored_children_end_placed_and_all_after_one_frame() -> void:
	var spots := [Vector2(-60, 0), Vector2(40, 90), Vector2(10, -70)]
	var f := _authored(spots)
	await wait_process_frames(1)
	assert_eq(_mine_positions(f), spots as Array[Vector2], "the editor positions are kept")
	assert_eq(f.mines().size(), 3)
	for m in f.mines():
		assert_true(m.placed, "placed by the field's _ready()")
		assert_eq(m.hostility, EnemyMine.Hostility.ALL)
		assert_true(m.expired.is_connected(m.queue_free), "self-owned through the mine's deferred setup")
		assert_true(_registered(m), "registered on its own launch")
		assert_eq((m.get_node("ProximityArea") as Area2D).collision_mask,
				CollisionLayers.PLAYER_HURTBOX | CollisionLayers.ENEMY_HURTBOX, "the ALL mask, applied in launch()")
		assert_eq(m.mine_life, 0.0, "mine.tscn's authored 8.0 never reaches a placed mine")


func test_a_player_hostility_field_leaves_its_mines_player_only() -> void:
	var f := _field({"hostility": EnemyMine.Hostility.PLAYER}, null, true)
	await wait_process_frames(1)
	for m in f.mines():
		assert_eq(m.hostility, EnemyMine.Hostility.PLAYER)
		assert_eq((m.get_node("ProximityArea") as Area2D).collision_mask, CollisionLayers.PLAYER_HURTBOX)
		assert_true(m.placed)


func test_a_child_that_is_not_a_mine_is_an_error_and_is_ignored() -> void:
	var f := FIELD.instantiate() as Minefield
	f.pattern = Minefield.Pattern.AUTHORED
	var stray := Node2D.new()
	stray.name = "NotAMine"
	f.get_node("Mines").add_child(stray)
	var mine := EnemyMineScenes.scene_for(EnemyMine.Variant.PROXIMITY).instantiate() as EnemyMine
	f.get_node("Mines").add_child(mine)
	f.process_mode = Node.PROCESS_MODE_DISABLED
	_container.add_child(f)
	assert_push_error("not an EnemyMine")
	await wait_process_frames(1)
	assert_eq(f.mines().size(), 1, "only the real mine counts")
	assert_true(mine.placed)
	assert_true(is_instance_valid(stray), "the stray child is left alone, not freed")


# ---------------------------------------------------------------------------------------------
# Placed mines: hostility, placed, registered, never fizzling, drifting on a leash (hand-ticked, 60 s, shared)
# ---------------------------------------------------------------------------------------------

## One 60 s run of a 9-mine ring that mixes PROXIMITY (`mine.tscn`, authored `mine_life` 8.0) and DRIFTING mines.
func _sixty_seconds() -> Dictionary:
	if not _sixty.is_empty():
		return _sixty
	var f := _field({"count": 9, "rng_seed": 3, "w_proximity": 1.0, "w_drifting": 1.0}, null, true, Vector2(300, 300))
	await wait_process_frames(1)
	var mines := f.mines()
	var starts := {}
	for m in mines:
		starts[m] = m.global_position
	var proximity_authored_life := float(EnemyMineScenes.export_of(EnemyMine.Variant.PROXIMITY, &"mine_life", 0.0))
	var farthest := {}
	for i in 3600:
		for m in mines:
			m._physics_process(DT)
			farthest[m] = maxf(farthest.get(m, 0.0), m.global_position.distance_to(starts[m]))
		f._physics_process(DT)
	var out := {"proximity_life": proximity_authored_life, "all": true, "placed": true, "alive": true, "registered": true,
			"not_fizzling": true, "life_zero": true, "proximity": 0, "drifting": 0, "drift_moved": true, "drift_leashed": true,
			"drift_far": 0.0, "leash": 0.0, "field_alive": is_instance_valid(f)}
	for m in mines:
		out.all = out.all and m.hostility == EnemyMine.Hostility.ALL
		out.placed = out.placed and m.placed
		out.alive = out.alive and is_instance_valid(m)
		out.registered = out.registered and _registered(m)
		out.not_fizzling = out.not_fizzling and not m.is_fizzling()
		out.life_zero = out.life_zero and m.mine_life == 0.0
		if m.variant == EnemyMine.Variant.PROXIMITY:
			out.proximity += 1
		elif m.variant == EnemyMine.Variant.DRIFTING:
			out.drifting += 1
			out.drift_moved = out.drift_moved and farthest[m] > 20.0
			out.drift_leashed = out.drift_leashed and farthest[m] <= 120.0 + 1.0
			out.drift_far = maxf(out.drift_far, farthest[m])
			out.leash = m.drift_leash
	_sixty = out
	return out


func test_every_placed_mine_is_all_placed_registered_and_alive_after_60_seconds() -> void:
	var r := await _sixty_seconds()
	assert_gt(r.proximity, 0, "the field holds mine.tscn mines (the Bomber's authored 8 s life)")
	assert_eq(r.proximity_life, 8.0, "precondition: mine.tscn authors mine_life 8.0")
	assert_true(r.all, "hostility ALL")
	assert_true(r.placed, "placed")
	assert_true(r.life_zero, "the field never sets placed_life: mine_life stays 0")
	assert_true(r.alive, "no mine freed itself")
	assert_true(r.not_fizzling, "none fizzled")
	assert_true(r.registered, "all still registered as hazards")
	assert_true(r.field_alive, "and so the field is still there")


func test_placed_drifting_mines_move_and_stay_within_121_px() -> void:
	var r := await _sixty_seconds()
	assert_gt(r.drifting, 0, "the field holds drifting mines")
	assert_eq(r.leash, 120.0, "drift_leash 120")
	assert_true(r.drift_moved, "every drifting mine moved")
	assert_true(r.drift_leashed, "and none strayed more than 120 + 1 px (farthest %.2f)" % r.drift_far)


func test_a_placed_drifting_mine_gets_a_random_direction_from_the_fields_rng() -> void:
	var make := func() -> Array:
		var f := _field({"count": 5, "rng_seed": 4, "w_proximity": 0.0, "w_drifting": 1.0}, null, true)
		return f.mines().map(func(m: EnemyMine) -> Vector2: return m.drift_direction)
	var a: Array = make.call()
	assert_eq(a, make.call(), "seeded: the same directions every build")
	var distinct := {}
	for d: Vector2 in a:
		assert_almost_eq(d.length(), 1.0, 0.001, "a unit direction")
		distinct[snappedf(d.x, 0.001)] = true
	assert_gt(distinct.size(), 1, "and not all the same")


# ---------------------------------------------------------------------------------------------
# Beacon and ownership
# ---------------------------------------------------------------------------------------------

func test_the_beacon_goes_dark_with_the_last_mine_and_the_field_frees_itself() -> void:
	var f := _field({"count": 2}, null, true)
	await wait_process_frames(1)
	var beacon := f.get_node("Beacon") as MinefieldBeacon
	assert_not_null(beacon)
	assert_true(beacon.lit, "lit while it holds mines")
	assert_gt(beacon.blink_alpha(), 0.0)
	var mines := f.mines()
	mines[0].queue_free()
	await wait_process_frames(1)
	f._physics_process(DT)
	assert_true(beacon.lit, "one mine left: still lit")
	mines[1].queue_free()
	await wait_process_frames(1)
	f._physics_process(DT)
	assert_false(beacon.lit, "dark with the last mine")
	assert_eq(beacon.blink_alpha(), 0.0)
	assert_true(f.is_dark())
	for i in 58:
		f._physics_process(DT)
	assert_true(is_instance_valid(f), "it lingers for a second")
	for i in 4:
		f._physics_process(DT)
	assert_true(f.is_queued_for_deletion(), "and frees itself one second after the last mine")


func test_a_runtime_spawn_is_deferred_and_lands_at_the_requested_point() -> void:
	var f := FIELD.instantiate() as Minefield
	f.count = 3
	f.process_mode = Node.PROCESS_MODE_DISABLED
	f.spawn_into(_container, Vector2(420, 260))
	assert_null(f.get_parent(), "not added until the message flush")
	await wait_process_frames(1)
	assert_eq(f.get_parent(), _container)
	assert_eq(f.global_position, Vector2(420, 260))
	assert_true(f.spawned)
	assert_eq(f.mines().size(), 3)


func test_spawn_into_a_freed_container_frees_the_field() -> void:
	var gone := Node2D.new()
	add_child(gone)
	var f := FIELD.instantiate() as Minefield
	f.spawn_into(gone, Vector2.ZERO)
	gone.free()
	await wait_process_frames(1)
	var gone_for_good := not is_instance_valid(f)
	if not gone_for_good:
		f.free()
	assert_true(gone_for_good, "no leak: the field frees itself instead of entering a dead container")


# ---------------------------------------------------------------------------------------------
# Assault: the field scrolls itself (hand-ticked)
# ---------------------------------------------------------------------------------------------

func test_in_assault_the_field_moves_60_t_down_and_its_hazards_follow() -> void:
	var harness = _world("assault")
	var f := _field({"count": 4}, harness.root, true, Vector2(640, 100))
	await wait_process_frames(1)
	var mine := f.mines()[0]
	var start := mine.global_position
	for i in 120:
		f._physics_process(DT)
	assert_almost_eq(f.global_position.y, 100.0 + 60.0 * 2.0, 0.01, "60 px/s for 2 s")
	assert_eq(f.global_position.x, 640.0, "straight down")
	assert_almost_eq(mine.global_position.y, start.y + 120.0, 0.01, "its mines are carried")
	var found: HazardInfo = null
	for info: HazardInfo in Hazards.around(mine.global_position, 1.0):
		if info.source == mine:
			found = info
	assert_not_null(found, "still registered")
	assert_almost_eq(found.position.y, start.y + 120.0, 0.01, "HazardInfo.position follows the field")
	assert_almost_eq(found.velocity.y, 60.0, 0.001, "and its velocity is the field's, so the avoidance stage leads it")


func test_in_assault_the_field_frees_once_every_mine_is_below_the_world_rect() -> void:
	var harness = _world("assault")
	var bottom := EnemyWorld.projectile_world_rect(get_tree()).end.y
	var f := _field({"count": 4, "radius": 100.0}, harness.root, true, Vector2(640, bottom - 300))
	await wait_process_frames(1)
	var lowest_offset := 100.0
	var ticks := 0
	while is_instance_valid(f) and not f.is_queued_for_deletion() and ticks < 1200:
		f._physics_process(DT)
		ticks += 1
	var expected := (300.0 + lowest_offset) / 60.0
	assert_true(f.is_queued_for_deletion(), "freed")
	assert_almost_eq(float(ticks) * DT, expected, 2.0 * DT, "exactly when the lowest mine (100 px below the centre) passes the rect")


func test_in_assault_a_field_that_cannot_leave_is_freed_after_40_seconds() -> void:
	var harness = _world("assault")
	var f := _field({"count": 3, "assault_drift_speed": 0.0}, harness.root, true, Vector2(640, 300))
	await wait_process_frames(1)
	for i in 2390:
		f._physics_process(DT)
	assert_false(f.is_queued_for_deletion(), "alive at 39.8 s")
	for i in 20:
		f._physics_process(DT)
	assert_true(f.is_queued_for_deletion(), "gone by 40.1 s")


func test_in_open_space_the_field_is_still() -> void:
	var harness = _world("open_space")
	var f := _field({"count": 4}, harness.root, true, Vector2(640, 100))
	await wait_process_frames(1)
	for i in 600:
		f._physics_process(DT)
	assert_eq(f.global_position, Vector2(640, 100), "no scrolling without an Assault arena")
	assert_false(f.is_queued_for_deletion(), "and no 40 s cleanup")


# ---------------------------------------------------------------------------------------------
# Both modes, real physics (8x): who sets a field off
# ---------------------------------------------------------------------------------------------

## One run per mode. Field "stub" is driven through by a player stub, field "zero" by an avoidance-0 fixture, and field
## "wary" by three avoidance-0.8 / margin-24 fixtures starting 0 / 100 / 200 px apart in lateral, all at 240 px/s.
func _crossing(mode: String) -> Dictionary:
	if _crossings.has(mode):
		return _crossings[mode]
	_scale_clock()
	var harness = _world(mode)
	var assault: bool = mode == "assault"
	# In Assault the field scrolls 60 px/s, so every ship flies with it (240, 60): the same straight line across the
	# field as in Open Space, which is what the lateral offsets describe.
	var velocity := Vector2(CROSS_SPEED, ASSAULT_DRIFT if assault else 0.0)
	var stub_field := _field({}, harness.root, false, Vector2(640, 350))
	var zero_field := _field({}, harness.root, false, Vector2(640, 700))
	var wary_field := _field({}, harness.root, false, Vector2(640, -150))
	var stub := _player(Vector2(140, 350), harness.root)
	var zero := _enemy(Vector2(140, 700), harness.root, 0.0, velocity)
	var wary: Array[BaseEnemy] = []
	for lateral: float in [0.0, 100.0, 200.0]:
		wary.append(_enemy(Vector2(140, -150 + lateral), harness.root, 0.8, velocity))
	var wary_mines := wary_field.mines()
	var closest: Array[float] = [INF, INF, INF]
	var step := _game_step()
	var watch := func() -> void:
		stub.global_position += velocity * step
		for i in 3:
			for m in wary_mines:
				if is_instance_valid(m):
					closest[i] = minf(closest[i], wary[i].global_position.distance_to(m.global_position))
	var ticker := _tick_each_frame(harness.root, watch)
	await _seconds(3.6)
	ticker.queue_free()
	var out := {
		"stub_damage": int(stub.get_meta(&"damage")),
		"stub_mines_left": stub_field.mines().size(),
		"zero_health": _health(zero),
		"zero_mines_left": zero_field.mines().size(),
		"wary_closest": closest,
		"wary_health": wary.map(func(e: BaseEnemy) -> int: return _health(e)),
		"wary_mines_left": wary_field.mines().size(),
		"wary_warning": wary_mines.any(func(m: EnemyMine) -> bool: return is_instance_valid(m) and m.is_warning()),
		"wary_x": wary.map(func(e: BaseEnemy) -> float: return e.global_position.x),
		"count": 9,
	}
	_crossings[mode] = out
	_restore_clock()
	return out


func test_a_player_driven_through_a_field_sets_a_mine_off(mode: String = use_parameters(MODES)) -> void:
	var r := await _crossing(mode)
	assert_gt(r.stub_damage, 0, "%s: the player stub took a blast" % mode)
	assert_lt(r.stub_mines_left, r.count, "%s: and a mine is gone" % mode)


func test_an_avoidance_0_enemy_driven_through_a_field_sets_a_mine_off_and_is_damaged(mode: String = use_parameters(MODES)) -> void:
	var r := await _crossing(mode)
	assert_lt(r.zero_health, 100, "%s: a hostility-ALL mine hurts an enemy" % mode)
	assert_lt(r.zero_mines_left, r.count, "%s: and it was an enemy hull that set it off" % mode)


func test_an_avoidance_0_8_enemy_sets_off_nothing_and_stays_140_px_from_every_mine(mode: String = use_parameters(MODES)) -> void:
	var r := await _crossing(mode)
	for i in 3:
		assert_gte(r.wary_closest[i], 140.0, "%s: lateral %d keeps >= 140 px from every mine centre (%.1f)" % [mode, i * 100, r.wary_closest[i]])
		assert_eq(r.wary_health[i], 100, "%s: lateral %d took no damage" % [mode, i * 100])
	assert_eq(r.wary_mines_left, r.count, "%s: no mine was set off" % mode)
	assert_false(r.wary_warning, "%s: and none is even warning" % mode)
