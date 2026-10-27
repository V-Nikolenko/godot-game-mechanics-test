## The Mine Layer shell (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.11, task t10): scene structure, the
## per-variant pools, `drop_mine()`, the rail fallback, the Assault DISENGAGE exit. INTENT tests.
##
## Hand-stepped with a fixed delta (the layer is `set_physics_process(false)` / `set_process(false)`), never a `Timer`.
## The one real-physics row (a mine outlives its layer and still goes off) runs on the 8x clock, the
## test_enemy_mines.gd pattern. Numbers come from the scenes (`EnemyMineScenes.export_of`) or the config, never typed
## copies.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const LAYER_SCENE: PackedScene = preload("res://assault/scenes/enemies/mine_layer/mine_layer.tscn")
const SHIPPED: MineLayerConfig = preload("res://assault/scenes/enemies/mine_layer/mine_layer_config.tres")  # read only

const DT := 1.0 / 60.0
const MODES := ["open_space", "assault"]
## The variants the shipped config builds a pool for, and the pool node each lives in.
const POOLS := {
	EnemyMine.Variant.PROXIMITY: "ProximityPool",
	EnemyMine.Variant.CHAIN: "ChainPool",
	EnemyMine.Variant.PULSE: "PulsePool",
	EnemyMine.Variant.HOMING: "HomingPool",
}
const STUB_RADIUS := 12.0

const _SPEEDUP := 8
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


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


func _world(mode: String):
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	return harness


func _spawn(harness, pos: Vector2) -> MineLayer:
	var layer := LAYER_SCENE.instantiate() as MineLayer
	layer.global_position = pos
	harness.root.add_child(layer)
	layer.set_physics_process(false)  # hand-ticked
	layer.set_process(false)          # the rail clock is hand-stepped too
	return layer


func _tick(layer: MineLayer, delta: float) -> void:
	var before := layer.global_position
	layer._physics_process(delta)
	layer.global_position = before + layer.velocity * delta


func _mines_in(root: Node) -> Array[EnemyMine]:
	var found: Array[EnemyMine] = []
	for child in root.get_children():
		if child is EnemyMine:
			found.append(child)
	return found


## A player stand-in: a body in group `player` with a real layer-128 `HurtBox`, recording damage in `meta damage`.
func _player_stub(at: Vector2, parent: Node) -> CharacterBody2D:
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


# ── Structure ────────────────────────────────────────────────────────────────────────────────────

func test_a_pool_per_weighted_variant_is_a_persistent_root_child_sized_by_pool_size_for() -> void:
	var harness = _world("open_space")
	var layer := _spawn(harness, Vector2(300.0, 100.0))
	for variant: int in POOLS:
		var pool := layer.get_node_or_null(POOLS[variant]) as BulletPool
		assert_not_null(pool, "%s is a direct child of the root" % POOLS[variant])
		if pool == null:
			continue
		assert_true(pool.persist_after_owner_death, "%s: persist_after_owner_death" % POOLS[variant])
		assert_eq(pool.pool_size, EnemyMineScenes.pool_size_for(variant, layer.config), "%s: sized by pool_size_for" % POOLS[variant])
		assert_eq(pool.bullet_scene, EnemyMineScenes.scene_for(variant), "%s: holds its own variant" % POOLS[variant])
	# The weight-0 variants build no pool, and the sizing rule says so.
	for variant in [EnemyMine.Variant.DRIFTING, EnemyMine.Variant.EMP]:
		assert_eq(EnemyMineScenes.pool_size_for(variant, layer.config), 0, "weight 0 -> size 0")
		assert_null(layer._pool_for(variant), "and no pool node")


func test_the_body_hurtbox_and_contact_box_are_one_circle_of_radius_40() -> void:
	var harness = _world("open_space")
	var layer := _spawn(harness, Vector2(300.0, 100.0))
	var body := (layer.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	assert_eq(body.radius, 40.0)
	assert_eq(((layer.get_node("HurtBox/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius, 40.0)
	assert_eq(((layer.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius, 40.0)
	assert_eq((layer.get_node("Dispenser") as Marker2D).position, Vector2(0.0, -38.0), "the stern, art nose-down")
	assert_not_null(layer.get_node_or_null("StateLight"))


func test_the_config_has_no_trigger_warning_or_blast_fields() -> void:
	var names: Array[String] = []
	for p in SHIPPED.get_property_list():
		names.append(String(p.name))
	for banned in ["trigger_radius", "warning_time", "mine_warning", "blast_radius", "blast_damage", "mine_blast_radius", "mine_blast_damage"]:
		assert_false(names.has(banned), "%s belongs to the variant scene" % banned)
	assert_eq(SHIPPED.hazard_avoidance, 0.8)
	assert_eq(SHIPPED.hazard_margin, 24.0)


func test_the_layer_joins_group_enemies_after_ready() -> void:
	var harness = _world("open_space")
	var layer := _spawn(harness, Vector2(300.0, 100.0))
	assert_true(layer.is_in_group("enemies"), "BaseEnemy does not join it; MineLayer._ready() does")


# ── drop_mine ────────────────────────────────────────────────────────────────────────────────────

func test_drop_mine_sets_the_life_by_mode_and_the_arm_and_eject_in_both(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var layer := _spawn(harness, Vector2(300.0, 100.0))
	var mine := layer.drop_mine(EnemyMine.Variant.PROXIMITY, layer.dispenser.global_position + Vector2(0.0, -120.0))
	assert_not_null(mine)
	assert_eq(mine.arm_delay, 0.5, "%s: arm 0.5" % mode)
	assert_eq(mine.eject_time, 0.3, "%s: eject 0.3" % mode)
	var lifetime := mine.get_node("ProjectileLifetime") as ProjectileLifetime
	if mode == "assault":
		assert_eq(mine.mine_life, 9.0, "assault: life 9.0")
	else:
		assert_eq(mine.mine_life, 0.0, "open space: never fizzles")
		assert_eq(lifetime.max_time, 240.0, "open space: with a 240 s backstop")
	assert_eq(mine.arm_delay, SHIPPED.mine_arm_delay)
	assert_eq(mine.eject_time, SHIPPED.mine_eject_time)


func test_per_variant_numbers_survive_the_drop(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var layer := _spawn(harness, Vector2(300.0, 100.0))
	for variant: int in POOLS:
		var mine := layer.drop_mine(variant, layer.dispenser.global_position + Vector2(0.0, -100.0))
		assert_not_null(mine, "%s: a mine came out" % POOLS[variant])
		if mine == null:
			continue
		assert_eq(mine.variant, variant)
		for prop: StringName in [&"trigger_radius", &"warning_time", &"blast_radius", &"blast_damage"]:
			var authored: Variant = EnemyMineScenes.export_of(variant, prop, null)
			if authored == null:
				authored = _script_default(prop)
			assert_eq(mine.get(prop), authored, "%s: %s is the scene's, %s" % [POOLS[variant], prop, mode])
	var pulse := layer.drop_mine(EnemyMine.Variant.PULSE, layer.dispenser.global_position)
	assert_eq(pulse.blast_damage, 8, "PULSE keeps its blast of 8")


func _script_default(prop: StringName) -> Variant:
	var probe := EnemyMine.new()
	var v: Variant = probe.get(prop)
	probe.free()
	return v


func test_the_eject_stops_on_the_rest_point_within_4_px() -> void:
	var harness = _world("open_space")
	harness.player.global_position = Vector2(5000.0, 5000.0)
	var layer := _spawn(harness, Vector2(600.0, 300.0))
	var rest := Vector2(520.0, 140.0)
	var mine := layer.drop_mine(EnemyMine.Variant.PROXIMITY, rest)
	for i in int((layer.config.mine_eject_time + 0.5) / DT):
		mine._physics_process(DT)
	assert_lt(mine.global_position.distance_to(rest), 4.0, "stopped at %s" % mine.global_position)


func test_an_exhausted_chain_pool_falls_back_to_a_proximity_mine() -> void:
	var harness = _world("open_space")
	harness.player.global_position = Vector2(5000.0, 5000.0)
	var layer := _spawn(harness, Vector2(600.0, 300.0))
	var size := (layer.get_node("ChainPool") as BulletPool).pool_size
	for i in size:
		var chain := layer.drop_mine(EnemyMine.Variant.CHAIN, layer.dispenser.global_position)
		assert_eq(chain.variant, EnemyMine.Variant.CHAIN, "chain %d" % i)
	var extra := layer.drop_mine(EnemyMine.Variant.CHAIN, layer.dispenser.global_position)
	assert_not_null(extra, "an exhausted pool still lays something")
	assert_eq(extra.variant, EnemyMine.Variant.PROXIMITY, "a proximity mine")
	assert_eq(extra.blast_damage, int(EnemyMineScenes.export_of(EnemyMine.Variant.PROXIMITY, &"blast_damage", 30)),
		"with the proximity scene's numbers")


func test_drop_mine_is_null_when_nothing_can_be_acquired() -> void:
	var harness = _world("open_space")
	harness.player.global_position = Vector2(5000.0, 5000.0)
	var layer := _spawn(harness, Vector2(600.0, 300.0))
	var size := (layer.get_node("ProximityPool") as BulletPool).pool_size
	for i in size:
		assert_not_null(layer.drop_mine(EnemyMine.Variant.PROXIMITY, layer.dispenser.global_position))
	assert_null(layer.drop_mine(EnemyMine.Variant.PROXIMITY, layer.dispenser.global_position), "nothing left")


## Real physics (8x): a mine laid before the layer dies still arms and goes off after it, on a player standing on it.
func test_a_mine_laid_before_the_layer_died_still_triggers_after_it(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var harness = _world(mode)
	var layer := _spawn(harness, Vector2(300.0, 100.0))
	var rest := Vector2(300.0, 400.0)
	var mine := layer.drop_mine(EnemyMine.Variant.PROXIMITY, rest)
	var stub := _player_stub(rest, harness.root)
	layer.free()
	assert_true(is_instance_valid(mine), "%s: the mine outlived its layer" % mode)
	await wait_physics_frames(roundi(1.6 / (1.0 / float(_saved_ticks))))
	assert_gt(int(stub.get_meta(&"damage")), 0, "%s: and still went off" % mode)
	assert_false(is_instance_valid(mine), "%s: and freed itself after its blast (the handed-over owner)" % mode)


# ── The rail fallback ────────────────────────────────────────────────────────────────────────────

func _railed(harness, pos: Vector2) -> MineLayer:
	var layer := _spawn(harness, pos)
	var rail := EnemyPathMover.new()
	var movement := StraightMovement.new()
	movement.speed = 100.0 / ArenaCamera.WORLD_SCALE
	rail.movement = movement
	rail.exit_mode = EnemyPathMover.ExitMode.FREE_ON_DURATION
	rail.exit_time = 60.0
	layer.add_child(rail)
	rail.set_physics_process(false)
	return layer


func test_a_rail_layer_drops_a_proximity_mine_every_interval_on_a_real_path_mover() -> void:
	var harness = _world("open_space")
	var layer := _railed(harness, Vector2(300.0, 100.0))
	assert_true(layer.is_ai_suspended(), "sanity: the rail took the layer over")
	var interval := SHIPPED.rail_mine_interval
	var drop_times: Array[float] = []
	var seen := 0
	for i in int((interval * 3.0 + 0.3) / DT):
		layer._process(DT)
		var now := _mines_in(harness.root).size()
		if now > seen:
			drop_times.append((i + 1) * DT)
			seen = now
	assert_eq(drop_times.size(), 3, "three mines in three intervals and a bit")
	for n in drop_times.size():
		assert_almost_eq(drop_times[n], interval * (n + 1), DT * 1.01, "mine %d drops on the interval, +-1 tick" % n)
	var mine := _mines_in(harness.root)[0]
	assert_eq(mine.variant, EnemyMine.Variant.PROXIMITY)
	assert_eq(mine.mine_life, SHIPPED.assault_mine_life, "with the Assault life")
	assert_almost_eq(mine.global_position.distance_to(layer.dispenser.global_position), 0.0, 0.01, "at the dispenser, speed 0")


func test_an_unsuspended_layer_drops_nothing_from_the_rail_clock() -> void:
	var harness = _world("open_space")
	var layer := _spawn(harness, Vector2(300.0, 100.0))
	for i in int(SHIPPED.rail_mine_interval * 3.0 / DT):
		layer._process(DT)
	assert_eq(_mines_in(harness.root).size(), 0, "the clock is a rail fallback only")


# ── The brain shell ──────────────────────────────────────────────────────────────────────────────

func test_the_phase_enum_is_declared_in_full_and_append_only() -> void:
	var P := MineLayerBrain.Phase
	assert_eq([P.APPROACH, P.LAY, P.BREAK_OFF, P.REPOSITION, P.DISENGAGE, P.IDLE, P.NOTICING, P.RETURNING],
			[0, 1, 2, 3, 4, 5, 6, 7])


func test_accepts_tow_is_false_in_lay_only() -> void:
	var harness = _world("open_space")
	var layer := _spawn(harness, Vector2(300.0, 100.0))
	var brain := layer.get_node("Brain") as MineLayerBrain
	assert_true(brain.accepts_tow(), "APPROACH")
	brain.enter_phase(MineLayerBrain.Phase.LAY)
	assert_false(brain.accepts_tow(), "LAY refuses a tow")
	brain.enter_phase(MineLayerBrain.Phase.BREAK_OFF)
	assert_true(brain.accepts_tow(), "BREAK_OFF")
	brain.enter_phase(MineLayerBrain.Phase.REPOSITION)
	assert_true(brain.accepts_tow(), "REPOSITION")
	brain.enter_phase(MineLayerBrain.Phase.DISENGAGE)
	assert_true(brain.accepts_tow(), "DISENGAGE")


func test_disengage_releases_the_corridor_and_raises_the_speed_cap() -> void:
	var harness = _world("assault")
	var layer := _spawn(harness, Vector2(640.0, 200.0))
	var mover := layer.get_node("EnemyMover") as EnemyMover
	var brain := layer.get_node("Brain") as MineLayerBrain
	assert_true(mover.constraint is AssaultCorridorConstraint, "sanity: the corridor holds it")
	assert_false(mover.constraint_released())
	brain.enter_phase(MineLayerBrain.Phase.DISENGAGE)
	assert_true(mover.constraint_released(), "the corridor is released")
	assert_eq(mover.max_speed, SHIPPED.exit_speed, "at exit_speed")


## A layer put into DISENGAGE heading out of the view keeps going and leaves the view rect: the corridor does not hold
## it at the band. Control: the same layer with its constraint left on is turned back at the band.
func test_a_disengaging_layer_heading_out_of_the_view_leaves_it() -> void:
	var harness = _world("assault")
	var view := EnemyWorld.view_rect(get_tree())
	var layer := _spawn(harness, Vector2(view.end.x - 60.0, view.get_center().y))
	layer.velocity = Vector2(SHIPPED.max_speed, 0.0)
	var brain := layer.get_node("Brain") as MineLayerBrain
	brain.enter_phase(MineLayerBrain.Phase.DISENGAGE)
	var left_view_at := -1
	var freed := false
	for i in 1500:
		_tick(layer, DT)
		if left_view_at < 0 and not view.has_point(layer.global_position):
			left_view_at = i
		if layer.is_queued_for_deletion():
			freed = true
			break
	assert_gt(left_view_at, -1, "it left the view rect")
	assert_true(freed, "and went on to leave the world rect, so it is not held at the band (at %s)" % layer.global_position)
	assert_gt(layer.global_position.x, view.end.x, "through the right edge")

	var held := _spawn(harness, Vector2(view.end.x - 60.0, view.get_center().y))
	held.velocity = Vector2(SHIPPED.max_speed, 0.0)
	var held_brain := held.get_node("Brain") as MineLayerBrain
	held_brain.enter_phase(MineLayerBrain.Phase.APPROACH)  # constraint still on, approaching a player in the view
	var furthest := held.global_position.x
	for i in 300:
		_tick(held, DT)
		furthest = maxf(furthest, held.global_position.x)
	assert_lt(furthest, view.end.x + 200.0, "control: a layer still under the corridor is not let far out")


func test_disengage_with_no_planned_pass_exits_along_the_velocity_else_the_facing() -> void:
	var harness = _world("assault")
	var layer := _spawn(harness, Vector2(640.0, 360.0))
	var brain := layer.get_node("Brain") as MineLayerBrain
	layer.velocity = Vector2(0.0, -200.0)
	brain.enter_phase(MineLayerBrain.Phase.DISENGAGE)
	_tick(layer, DT)
	assert_lt(layer.velocity.y, 0.0, "along the velocity direction (up)")
	assert_almost_eq(layer.velocity.x, 0.0, 1.0)

	var resting := _spawn(harness, Vector2(240.0, 360.0))  # apart: two overlapping bodies push each other
	resting.velocity = Vector2.ZERO
	resting.rotation = 0.0
	var rbrain := resting.get_node("Brain") as MineLayerBrain
	rbrain.enter_phase(MineLayerBrain.Phase.DISENGAGE)
	_tick(resting, DT)
	var facing := Vector2.RIGHT.rotated(resting.rotation + EnemyMover.sprite_forward_angle_of(resting))
	assert_gt(resting.velocity.normalized().dot(facing), 0.9, "else the facing")


# ── Passes (task t11; plan §2.12; task plan docs/plans/cmvkb0hdc00uiqs2xhvb2awai/3-plan.md) ─────────
#
# Hand-ticked with `_pass_step()`: the stub player moves by its velocity, the layer ticks, then every mine its brain laid
# that is still live or fading ticks once (the rows tick each mine themselves, so ejects and fizzles run). Every row whose
# outcome depends on a draw seeds the brain with SEED. The two 60 s scenarios yield a frame every YIELD_EVERY ticks so the
# pools' deferred `_recycle()` runs; every laid mine has its own physics switched off from the `mine_dropped` handler, so
# those frames add no wall-time-dependent mine ticks and a seeded run is reproducible.

## Chosen before the first run; never changed to turn a row green.
const SEED := 4242
const YIELD_EVERY := 60
## A mine's eject is over this many ticks after its drop (`mine_eject_time` 0.3 s = 18 ticks, + 2).
const LAND_TICKS := 20
const ANGLE_BOUND_DEG := 40.0
const PATH_BOUND := 40.0
const OS_PLAYER := Vector2(640.0, 360.0)

## Scenario results shared by several rows, computed once per file (plain data only: every world is freed after its row).
var _cache := {}


func _brain(layer: MineLayer) -> MineLayerBrain:
	return layer.get_node("Brain") as MineLayerBrain


## A layer for the pass rows: seeded before `add_child` (`EnemyBrain._ready()` reads `rng_seed`), engaged from the start,
## hand-ticked. Every mine its brain lays is recorded in `meta drops` as `{mine, tick, phase, k, landed}` (`k` = its index
## in the pass, -1 for a tail drop; `landed` = where it was LAND_TICKS after the drop) and has its own physics switched off.
func _pass_layer(harness, pos: Vector2, velocity: Vector2 = Vector2.ZERO) -> MineLayer:
	var layer := LAYER_SCENE.instantiate() as MineLayer
	var brain := layer.get_node("Brain") as MineLayerBrain
	brain.rng_seed = SEED
	brain.start_engaged = true
	layer.global_position = pos
	harness.root.add_child(layer)
	layer.set_physics_process(false)
	layer.set_process(false)
	layer.velocity = velocity
	var drops: Array = []
	var active := {}
	layer.set_meta(&"drops", drops)
	layer.set_meta(&"active", active)
	layer.set_meta(&"tick", 0)
	layer.set_meta(&"land_i", 0)
	brain.mine_dropped.connect(func(mine: EnemyMine) -> void:
		mine.set_physics_process(false)
		active[mine] = true
		var in_lay := brain.phase == MineLayerBrain.Phase.LAY
		drops.append({"mine": mine, "tick": int(layer.get_meta(&"tick")), "phase": brain.phase,
				"k": brain.drops_this_pass - 1 if in_lay else -1}))
	return layer


## One hand-tick. Returns the layer position the brain saw on this tick.
func _pass_step(layer: MineLayer, player: CharacterBody2D, move_player: bool = true) -> Vector2:
	if move_player:
		player.global_position += player.velocity * DT
	var now := int(layer.get_meta(&"tick")) + 1
	layer.set_meta(&"tick", now)
	var seen := layer.global_position
	_tick(layer, DT)
	var active: Dictionary = layer.get_meta(&"active")
	for mine in active.keys():
		if not is_instance_valid(mine) or not (mine.is_live() or mine.is_fizzling()):
			active.erase(mine)
		else:
			mine._physics_process(DT)
	var drops: Array = layer.get_meta(&"drops")
	var i := int(layer.get_meta(&"land_i"))
	while i < drops.size() and now - int(drops[i].tick) >= LAND_TICKS:
		var m: Variant = drops[i].mine
		drops[i].landed = (m as EnemyMine).global_position if is_instance_valid(m) else Vector2.INF
		i += 1
	layer.set_meta(&"land_i", i)
	return seen


## Steps until `done.call()` is true (checked after each step), the layer is freed, or `max_ticks`. Returns the ticks run.
func _run_until(layer: MineLayer, player: CharacterBody2D, max_ticks: int, done: Callable) -> int:
	for i in max_ticks:
		_pass_step(layer, player)
		if layer.is_queued_for_deletion() or done.call():
			return i + 1
	return max_ticks


func _pass_drops(layer: MineLayer) -> Array:
	return (layer.get_meta(&"drops") as Array).filter(func(d: Dictionary) -> bool: return int(d.k) >= 0)


func _dist_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


func _angle_deg(a: Vector2, b: Vector2) -> float:
	return rad_to_deg(absf(a.angle_to(b)))


## Seconds to ticks, rounded.
func _ticks(seconds: float) -> int:
	return roundi(seconds / DT)


func _stall_guard(brain: MineLayerBrain) -> float:
	var pts := brain.path_points()
	var length := 0.0
	for i in pts.size() - 1:
		length += pts[i].distance_to(pts[i + 1])
	return length * MineLayerBrain.STALL_FACTOR / brain.config.lay_speed + MineLayerBrain.STALL_SLACK


## A layer that has made its first plan: a standing stub in Open Space (a fence plan), the player at (640, 360) in
## Assault. Returns [harness, layer].
func _first_plan(mode: String, arc_chance: float) -> Array:
	var harness = _world(mode)
	var at := OS_PLAYER + Vector2(600.0, 0.0) if mode == "open_space" else Vector2(240.0, 300.0)
	var layer := _pass_layer(harness, at)
	layer.config.arc_chance = arc_chance
	_pass_step(layer, harness.player)
	return [harness, layer]


# ── Geometry ─────────────────────────────────────────────────────────────────────────────────────

func test_zigzag_rest_points_alternate_35_on_122_chords(mode: String = use_parameters(MODES)) -> void:
	var setup := _first_plan(mode, 0.0)
	var brain := _brain(setup[1])
	var cfg := brain.config
	var pts := brain.planned_rest_points
	assert_eq(brain.pass_shape, MineLayerBrain.Shape.ZIGZAG, "%s: forced ZIGZAG" % mode)
	assert_eq(pts.size(), cfg.mines_per_pass)
	var chord := Vector2(cfg.mine_step, 2.0 * cfg.zigzag_amplitude).length()
	assert_almost_eq(chord, 122.1, 0.05, "sanity: the plan's chord")
	var c := brain.pass_centre
	for k in pts.size():
		var y := (pts[k] - c).dot(brain.pass_normal)
		assert_almost_eq(absf(y), cfg.zigzag_amplitude, 1.0, "%s: mine %d is %.2f off the axis" % [mode, k, y])
		if k == 0:
			continue
		var prev_y := (pts[k - 1] - c).dot(brain.pass_normal)
		assert_lt(y * prev_y, 0.0, "%s: mine %d alternates side" % [mode, k])
		assert_almost_eq(pts[k].distance_to(pts[k - 1]), chord, 2.0, "%s: chord %d" % [mode, k])
		assert_almost_eq((pts[k] - pts[k - 1]).dot(brain.pass_axis), cfg.mine_step, 1.0, "%s: axis step %d" % [mode, k])


func test_arc_rest_points_follow_the_formula_on_the_players_side(mode: String = use_parameters(MODES)) -> void:
	var setup := _first_plan(mode, 1.0)
	var harness = setup[0]
	var brain := _brain(setup[1])
	var cfg := brain.config
	var pts := brain.planned_rest_points
	assert_eq(brain.pass_shape, MineLayerBrain.Shape.ARC, "%s: forced ARC" % mode)
	var c := brain.pass_centre
	var u := brain.pass_axis
	var p: Vector2 = harness.player.global_position
	var own_normal := u.orthogonal() if u.orthogonal().dot(p - c) > 0.0 else -u.orthogonal()
	assert_gt(brain.pass_normal.dot(p - c), 0.0, "%s: the plan's normal points at the player" % mode)
	var n := cfg.mines_per_pass
	for k in n:
		var t := float(k) / float(n - 1)
		var want := c + u * ((k - (n - 1) * 0.5) * cfg.mine_step) + own_normal * (4.0 * cfg.arc_depth * t * (1.0 - t))
		assert_lt(pts[k].distance_to(want), 2.0, "%s: mine %d at %s, formula %s" % [mode, k, pts[k], want])
		assert_gt((pts[k] - c).dot(own_normal), -0.5, "%s: mine %d bows toward the player" % [mode, k])
		if k > 0:
			var gap := pts[k].distance_to(pts[k - 1])
			assert_between(gap, 98.0, 125.0, "%s: spacing %d" % [mode, k])


# ── Natural passes (shared) ──────────────────────────────────────────────────────────────────────

## One natural pass per mode, from a layer at rest: Open Space against a standing stub 600 px away (bearing 0), Assault
## against the player at (640, 360) (run until the layer is freed). Per tick: what the brain saw and what it decided.
func _natural_pass(mode: String) -> Dictionary:
	var key := "natural_" + mode
	if _cache.has(key):
		return _cache[key]
	var harness = _world(mode)
	var layer := _pass_layer(harness, OS_PLAYER + Vector2(600.0, 0.0) if mode == "open_space" else Vector2(240.0, 300.0))
	var brain := _brain(layer)
	var out := {"seen": [], "phase": [], "run_in": [], "frozen": [], "r": [], "s": [], "u": [], "vel": [],
			"released": [], "budget_left": [], "lay_start": -1, "lay_end": -1, "lays": 0, "freed": false,
			"rest": [], "path": PackedVector2Array(), "axis": Vector2.ZERO, "view": EnemyWorld.view_rect(get_tree()),
			"stall": 0.0, "drops": [], "player": harness.player.global_position}
	var last_phase: int = brain.phase
	var budget_ticks := _ticks(40.0)
	for i in budget_ticks:
		var seen := _pass_step(layer, harness.player)
		if layer.is_queued_for_deletion():
			out.freed = true
			break
		out.seen.append(seen)
		out.phase.append(brain.phase)
		out.run_in.append(brain.run_in_active)
		out.frozen.append(brain.plan_frozen)
		out.r.append(brain.pass_run_in_point)  # the R this tick planned (and, once frozen, kept)
		out.s.append(brain.pass_start)
		out.u.append(brain.pass_axis)
		out.vel.append(layer.velocity)
		out.released.append((layer.get_node("EnemyMover") as EnemyMover).constraint_released())
		out.budget_left.append(brain.budget.remaining())
		if brain.phase == MineLayerBrain.Phase.LAY and last_phase != MineLayerBrain.Phase.LAY:
			out.lays += 1
			out.lay_start = i
			out.rest = brain.planned_rest_points.duplicate()
			out.path = brain.path_points()
			out.axis = brain.pass_axis
			out.stall = _stall_guard(brain)
		if last_phase == MineLayerBrain.Phase.LAY and brain.phase != MineLayerBrain.Phase.LAY:
			out.lay_end = i
		last_phase = brain.phase
		if mode == "open_space" and out.lay_end >= 0 and i >= out.lay_end + LAND_TICKS + 1:
			break
	for d in layer.get_meta(&"drops"):
		out.drops.append({"tick": d.tick - 1, "k": d.k, "landed": d.get("landed", Vector2.INF), "variant": (d.mine as EnemyMine).variant})
	gut.p("natural %s pass: LAY %.2f -> %.2f s, %s after %.2f s" % [mode, (out.lay_start + 1) * DT, (out.lay_end + 1) * DT,
			"freed" if out.freed else "run ended", out.seen.size() * DT])
	_cache[key] = out
	return out


func test_every_mine_lands_within_4_px_of_its_planned_point(mode: String = use_parameters(MODES)) -> void:
	var run := _natural_pass(mode)
	assert_gt(run.lay_start, 0, "%s: LAY was reached" % mode)
	var pass_drops: Array = run.drops.filter(func(d: Dictionary) -> bool: return int(d.k) >= 0)
	assert_eq(pass_drops.size(), 6, "%s: exactly six drops, nothing to skip with no earlier pass" % mode)
	for d in pass_drops:
		var planned: Vector2 = run.rest[int(d.k)]
		assert_lt((d.landed as Vector2).distance_to(planned), 4.0,
				"%s: mine %d landed at %s, planned %s" % [mode, d.k, d.landed, planned])


func test_assault_mines_lie_inside_the_view_on_a_horizontal_axis() -> void:
	var run := _natural_pass("assault")
	var axis: Vector2 = run.axis
	assert_lt(absf(axis.y), 0.01, "a horizontal axis (%s)" % axis)
	var inner: Rect2 = (run.view as Rect2).grow(-64.0)
	for p: Vector2 in run.rest:
		assert_true(inner.has_point(p), "rest point %s inside view_rect().grow(-64)" % p)
	for d in run.drops:
		if int(d.k) >= 0:
			assert_true(inner.has_point(d.landed), "laid mine %s inside view_rect().grow(-64)" % d.landed)


## Boundary: a player on the view's top edge pulls C above the clamp box, which holds it on the box's top edge; the pass
## is still laid, inside the view.
func test_an_assault_player_on_the_top_edge_clamps_the_centre_and_still_gets_a_pass() -> void:
	var harness = _world("assault")
	var view := EnemyWorld.view_rect(get_tree())
	harness.player.global_position = Vector2(view.get_center().x, view.position.y)
	var layer := _pass_layer(harness, Vector2(240.0, 400.0))
	var brain := _brain(layer)
	_pass_step(layer, harness.player)
	var cfg := brain.config
	var box := view.grow(-(cfg.view_margin + maxf(cfg.zigzag_amplitude, cfg.arc_depth)))
	assert_almost_eq(brain.pass_centre.y, box.position.y, 0.001, "C held on the clamp box's top edge")
	assert_lt(brain.pass_normal.y, 0.0, "the normal still points at the player, above the line")
	var ticks := _run_until(layer, harness.player, _ticks(20.0),
			func() -> bool: return brain.phase == MineLayerBrain.Phase.DISENGAGE)
	assert_lt(ticks, _ticks(20.0), "the pass finished")
	_run_until(layer, harness.player, LAND_TICKS + 1, func() -> bool: return false)
	var laid := _pass_drops(layer)
	assert_eq(laid.size(), 6, "all six laid")
	for d in laid:
		assert_true(view.grow(-64.0).has_point(d.get("landed", Vector2.INF)), "inside the view: %s" % d.get("landed"))


# ── Where the line goes (Open Space) ─────────────────────────────────────────────────────────────

func test_a_standing_player_gets_a_fence_plan_frozen_from_a_latched_frame(bearing: float = use_parameters([0.0, 90.0, 180.0])) -> void:
	var harness = _world("open_space")
	var dir := Vector2.RIGHT.rotated(deg_to_rad(bearing))
	var layer := _pass_layer(harness, OS_PLAYER + dir * 600.0)
	var brain := _brain(layer)
	_pass_step(layer, harness.player)
	assert_eq(brain.pass_form, &"fence", "%.0f deg: a fence plan" % bearing)
	var f0 := brain.frame_f
	var r0 := brain.pass_run_in_point
	var frozen_at := 1 if brain.plan_frozen else -1
	var f_drift := 0.0
	var r_drift := 0.0
	for i in range(1, _ticks(2.5)):
		if brain.plan_frozen:
			break
		_pass_step(layer, harness.player)
		f_drift = maxf(f_drift, brain.frame_f.distance_to(f0))
		r_drift = maxf(r_drift, brain.pass_run_in_point.distance_to(r0))
		if brain.plan_frozen:
			frozen_at = i + 1
	assert_gt(frozen_at, 0, "%.0f deg: frozen within 2.5 s" % bearing)
	assert_eq(brain.fence_fallbacks, 0, "%.0f deg: no fence fallback" % bearing)
	assert_lt(f_drift, 0.001, "%.0f deg: frame_f latched (drift %.5f)" % [bearing, f_drift])
	assert_lt(r_drift, 1.0, "%.0f deg: the run-in point stays put (drift %.2f px)" % [bearing, r_drift])
	var want := OS_PLAYER + dir * brain.config.fence_distance
	assert_lt(brain.pass_centre.distance_to(want), 2.0, "%.0f deg: C %s is 320 px from the stub toward the layer (%s)" % [bearing, brain.pass_centre, want])
	gut.p("standing %.0f deg: frozen on tick %d" % [bearing, frozen_at])


## A 100 px/s stub with the layer at rest 600 px from it at `bearing` (0 = straight ahead). Runs until the plan
## freezes (at most `max_seconds`), then on through the pass when `through` is set.
func _lead_run(bearing: float, max_seconds: float, through: bool) -> Dictionary:
	var harness = _world("open_space")
	harness.player.velocity = Vector2(100.0, 0.0)
	var layer := _pass_layer(harness, OS_PLAYER + Vector2.RIGHT.rotated(deg_to_rad(bearing)) * 600.0)
	var brain := _brain(layer)
	var frozen_at := _run_until(layer, harness.player, _ticks(max_seconds), func() -> bool: return brain.plan_frozen)
	var out := {"frozen": brain.plan_frozen, "frozen_at": frozen_at, "form": brain.pass_form, "centre": brain.pass_centre,
			"fence_fallbacks": brain.fence_fallbacks, "ahead_at_arm": []}
	if not through:
		return out
	var arm_ticks := _ticks(brain.config.mine_arm_delay)
	var lay_seen := false
	for i in _ticks(15.0):
		_pass_step(layer, harness.player)
		lay_seen = lay_seen or brain.phase == MineLayerBrain.Phase.LAY
		for d in _pass_drops(layer):
			if int(d.k) in [2, 3] and int(layer.get_meta(&"tick")) - int(d.tick) == arm_ticks:
				out.ahead_at_arm.append((out.centre - harness.player.global_position).dot(Vector2.RIGHT))
				assert_true((d.mine as EnemyMine).is_armed(), "mine %d is armed now" % d.k)
		if lay_seen and brain.phase != MineLayerBrain.Phase.LAY and out.ahead_at_arm.size() >= 2:
			break
	return out


func test_a_moving_player_gets_a_lead_plan_on_its_track() -> void:
	var run := _lead_run(0.0, 2.5, true)
	assert_true(run.frozen, "frozen within 2.5 s (tick %d)" % run.frozen_at)
	assert_eq(run.form, &"lead", "a lead plan")
	assert_eq(run.fence_fallbacks, 0, "no fence fallback (the control for the fallback row)")
	assert_lt(absf((run.centre as Vector2).y - OS_PLAYER.y), 2.0, "C %s on the stub's track line" % run.centre)
	assert_eq(run.ahead_at_arm.size(), 2, "mines 2 and 3 both armed")
	for ahead: float in run.ahead_at_arm:
		assert_gt(ahead, 80.0, "C is %.1f px ahead of the live stub when the middle mine arms" % ahead)
	gut.p("lead ahead: frozen on tick %d, C ahead at arm %s" % [run.frozen_at, run.ahead_at_arm])


func test_an_abeam_moving_player_also_gets_a_lead_plan() -> void:
	var run := _lead_run(90.0, 5.0, false)
	assert_true(run.frozen, "frozen within 5.0 s (tick %d)" % run.frozen_at)
	assert_eq(run.form, &"lead", "a lead plan")
	assert_eq(run.fence_fallbacks, 0)
	gut.p("lead abeam: frozen on tick %d" % run.frozen_at)


## A layer (not ticked) beside a 100 px/s stub, for the pure planner rows.
func _pure_lead_layer(harness, ahead: float = 600.0) -> MineLayer:
	harness.player.velocity = Vector2(100.0, 0.0)
	return _pass_layer(harness, OS_PLAYER + Vector2(ahead, 0.0))


func test_the_arrival_scan_finds_the_earliest_feasible_time() -> void:
	var harness = _world("open_space")
	var brain := _brain(_pure_lead_layer(harness))
	var v := Vector2(100.0, 0.0)
	brain.plan_pass(OS_PLAYER, v, [])
	assert_eq(brain.pass_form, &"lead")
	var t := brain.arrival_time
	assert_gt(t, 0.1, "the scan had to search (T %.4f)" % t)
	assert_lt(brain.flight_time(brain.lead_run_in_point(OS_PLAYER, v, t)), t + 0.001, "R(T) is reachable by T")
	var early := t - 0.004
	assert_gt(brain.flight_time(brain.lead_run_in_point(OS_PLAYER, v, early)), early, "but not 0.004 s earlier")


func test_lost_feasibility_freezes_the_last_lead_plan() -> void:
	var harness = _world("open_space")
	var layer := _pure_lead_layer(harness)
	var brain := _brain(layer)
	var v := Vector2(100.0, 0.0)
	brain.plan_pass(OS_PLAYER, v, [])
	assert_eq(brain.pass_form, &"lead")
	assert_false(brain.plan_frozen, "sanity: 600 px out, not yet within commit distance")
	var centre := brain.pass_centre
	layer.global_position = OS_PLAYER - Vector2(1500.0, 0.0)
	brain.plan_pass(OS_PLAYER, v, [])
	assert_true(brain.plan_frozen, "the guard froze the plan")
	assert_eq(brain.pass_centre, centre, "as it stood")
	assert_eq(brain.pass_form, &"lead", "still a lead plan")
	assert_eq(brain.fence_fallbacks, 0, "not a fence fallback")


func test_a_reversing_player_does_not_move_a_frozen_line() -> void:
	var harness = _world("open_space")
	harness.player.velocity = Vector2(100.0, 0.0)
	var layer := _pass_layer(harness, OS_PLAYER + Vector2(600.0, 0.0))
	var brain := _brain(layer)
	_run_until(layer, harness.player, _ticks(6.0), func() -> bool: return brain.plan_frozen)
	assert_true(brain.plan_frozen)
	var frozen_rest := brain.planned_rest_points.duplicate()
	_run_until(layer, harness.player, _ticks(10.0), func() -> bool: return brain.phase == MineLayerBrain.Phase.LAY)
	assert_eq(brain.phase, MineLayerBrain.Phase.LAY, "LAY reached")
	harness.player.velocity = -harness.player.velocity
	_run_until(layer, harness.player, _ticks(10.0), func() -> bool: return brain.phase != MineLayerBrain.Phase.LAY)
	_run_until(layer, harness.player, LAND_TICKS + 1, func() -> bool: return false)
	for k in frozen_rest.size():
		assert_lt(brain.planned_rest_points[k].distance_to(frozen_rest[k]), 0.001, "rest point %d unchanged" % k)
	var laid := _pass_drops(layer)
	assert_eq(laid.size(), 6)
	for d in laid:
		assert_lt((d.landed as Vector2).distance_to(frozen_rest[int(d.k)]), 4.0, "mine %d laid where planned" % d.k)


func test_a_player_too_fast_to_lead_gets_a_frozen_fence_on_the_first_tick() -> void:
	var harness = _world("open_space")
	harness.player.velocity = Vector2(220.0, 0.0)
	var layer := _pass_layer(harness, OS_PLAYER - Vector2(600.0, 0.0))
	var brain := _brain(layer)
	harness.player.global_position += harness.player.velocity * DT
	var p1: Vector2 = harness.player.global_position
	var l1 := layer.global_position
	_pass_step(layer, harness.player, false)
	assert_true(brain.plan_frozen, "frozen on the first planning tick")
	assert_eq(brain.pass_form, &"fence", "a fence plan")
	assert_eq(brain.fence_fallbacks, 1, "one fence fallback")
	var want := p1 + (l1 - p1).normalized() * brain.config.fence_distance
	assert_lt(brain.pass_centre.distance_to(want), 2.0, "C %s 320 px from the stub toward the layer (%s)" % [brain.pass_centre, want])
	var ticks := _run_until(layer, harness.player, _ticks(15.0), func() -> bool: return brain.phase == MineLayerBrain.Phase.LAY)
	assert_eq(brain.phase, MineLayerBrain.Phase.LAY, "LAY reached (%.2f s)" % (ticks * DT))
	assert_eq(brain.fence_fallbacks, 1, "and only the one")


# ── The run-in and LAY ───────────────────────────────────────────────────────────────────────────

func test_the_run_in_starts_within_60_px_and_lay_starts_on_the_crossing() -> void:
	var run := _natural_pass("open_space")
	var lookahead := SHIPPED.path_lookahead
	var handover := -1
	for i in run.seen.size():
		if run.run_in[i]:
			handover = i
			break
		if run.frozen[i]:
			assert_gt((run.seen[i] as Vector2).distance_to(run.r[i]), lookahead, "tick %d: no handover while still > 60 px out" % i)
	assert_gt(handover, 0, "the run-in started")
	assert_lt((run.seen[handover] as Vector2).distance_to(run.r[handover]), lookahead + 0.001, "on the first tick within 60 px of R")
	var lay: int = run.lay_start
	assert_gt(lay, handover, "LAY after the handover")
	for i in range(handover, lay):
		assert_lt((run.seen[i] - run.s[i]).dot(run.u[i]), 0.0, "tick %d: not yet across S" % i)
	assert_gte((run.seen[lay] - run.s[lay]).dot(run.u[lay]), 0.0, "LAY starts on the tick the centre crosses S")
	for d in run.drops:
		assert_gte(int(d.tick), lay, "no drop before LAY")


## A frozen plan and an arrival: "aligned" (on the axis 100 px before R, moving along u at 240), "perpendicular" (300 px
## from R along the normal, moving at R at 240), and "earlier pass" (aligned, with a live ZIGZAG line of real PROXIMITY
## mines centred 380 px away, rotated toward the E end so it crosses the new line near its mine 5).
func test_lay_flies_sideways_and_on_the_path(arrival: String = use_parameters(["aligned", "perpendicular", "earlier pass"])) -> void:
	var harness = _world("open_space")
	var layer := _pass_layer(harness, OS_PLAYER + Vector2(600.0, 0.0))
	var brain := _brain(layer)
	_pass_step(layer, harness.player)
	brain.freeze_plan()
	var u := brain.pass_axis
	var r := brain.pass_run_in_point
	if arrival == "perpendicular":
		layer.global_position = r + brain.pass_normal * 300.0
		layer.velocity = -brain.pass_normal * 240.0
	else:
		layer.global_position = r - u * 100.0
		layer.velocity = u * 240.0
	if arrival == "earlier pass":
		var older := _older_line(harness, brain)
		for m in older:
			assert_true(m.is_live(), "older mine live")
			var seen := Hazards.around(m.global_position, 0.0).any(func(h: HazardInfo) -> bool: return h.source == m)
			assert_true(seen, "and registered")
	var path := brain.path_points()
	var worst_angle := 0.0
	var worst_off := 0.0
	var lay_ticks := 0
	for i in _ticks(20.0):
		_pass_step(layer, harness.player)
		if brain.phase == MineLayerBrain.Phase.LAY:
			lay_ticks += 1
			worst_angle = maxf(worst_angle, _angle_deg(layer.velocity, u))
			worst_off = maxf(worst_off, _dist_to_polyline(layer.global_position, path))
		elif lay_ticks > 0:
			break
	assert_gt(lay_ticks, 0, "%s: LAY reached" % arrival)
	assert_lt(worst_angle, ANGLE_BOUND_DEG, "%s: LAY velocity within 40 deg of the axis (worst %.1f)" % [arrival, worst_angle])
	assert_lt(worst_off, PATH_BOUND, "%s: centre within 40 px of the polyline (worst %.1f)" % [arrival, worst_off])
	gut.p("LAY %s: worst angle %.1f deg, worst offset %.1f px, %d ticks" % [arrival, worst_angle, worst_off, lay_ticks])


## Six PLAYER-hostility PROXIMITY mines launched by hand at speed 0 (registered at once), on a ZIGZAG line centred
## `min_pass_separation` from `brain`'s centre on the fence circle, rotated toward its E end.
func _older_line(harness, brain: MineLayerBrain) -> Array[EnemyMine]:
	var cfg := brain.config
	var p: Vector2 = harness.player.global_position
	var f := (brain.pass_centre - p).normalized()
	var phi := 2.0 * asin(cfg.min_pass_separation / (2.0 * cfg.fence_distance))
	if (p + f.rotated(phi) * cfg.fence_distance - brain.pass_centre).dot(brain.pass_axis) < 0.0:
		phi = -phi
	var c := p + f.rotated(phi) * cfg.fence_distance
	var u := brain.pass_axis.rotated(phi)
	var n := (p - c).normalized()
	var out: Array[EnemyMine] = []
	for k in cfg.mines_per_pass:
		var m := EnemyOrdnanceScenes.MINE.instantiate() as EnemyMine
		m.mine_life = 0.0
		harness.root.add_child(m)
		m.set_physics_process(false)
		var at := c + u * ((k - (cfg.mines_per_pass - 1) * 0.5) * cfg.mine_step) + n * (cfg.zigzag_amplitude * (1.0 if k % 2 == 0 else -1.0))
		m.global_position = at
		m.launch(Vector2.ZERO, 0.0, at)
		out.append(m)
	return out


# ── Open Space: gradual, hazard-aware ────────────────────────────────────────────────────────────

## 60 s against a "standing" stub or a "circling" one (120 px/s on a 700 px circle round (640, 360)). Computed once per
## file; yields a frame every YIELD_EVERY ticks so the pools' deferred recycles run.
func _scenario(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var harness = _world("open_space")
	var player: CharacterBody2D = harness.player
	var circle_r := 700.0
	var omega := 120.0 / circle_r
	var angle := 0.0
	var layer: MineLayer
	if name == "circling":
		player.global_position = OS_PLAYER + Vector2(circle_r, 0.0)
		player.velocity = Vector2(0.0, 120.0)
		layer = _pass_layer(harness, OS_PLAYER)
	else:
		layer = _pass_layer(harness, OS_PLAYER + Vector2(600.0, 0.0))
	var brain := _brain(layer)
	var cfg := brain.config
	var reach := 80.0 + 60.0 + cfg.hazard_margin + 0.6 * cfg.max_speed
	var out := {"lays": [], "freezes": [], "drops_per_pass": [], "max_live": 0, "min_clear": INF, "reach_seen": false,
			"approaches": []}
	var last_phase: int = -1
	var was_frozen := false
	var approach_start := 0.0
	var lay_start := -1.0
	for i in _ticks(60.0):
		if name == "circling":
			angle += omega * DT
			player.global_position = OS_PLAYER + Vector2(cos(angle), sin(angle)) * circle_r
			player.velocity = Vector2(-sin(angle), cos(angle)) * 120.0
		_pass_step(layer, player, false)
		var now := (i + 1) * DT
		var ph: int = brain.phase
		if ph == MineLayerBrain.Phase.APPROACH and last_phase != MineLayerBrain.Phase.APPROACH:
			approach_start = now
			was_frozen = false
		if ph == MineLayerBrain.Phase.APPROACH and brain.plan_frozen and not was_frozen:
			was_frozen = true
			out.freezes.append({"t": now, "after": now - approach_start, "centre": brain.pass_centre, "form": brain.pass_form,
					"spread_fallback": brain.pass_spread_fallback, "earlier": brain.live_pass_centres()})
		if ph == MineLayerBrain.Phase.LAY and last_phase != MineLayerBrain.Phase.LAY:
			lay_start = now
		if last_phase == MineLayerBrain.Phase.LAY and ph != MineLayerBrain.Phase.LAY:
			out.lays.append([lay_start, now])
			out.drops_per_pass.append(brain.drops_this_pass)
		out.max_live = maxi(out.max_live, brain.live_mine_count())
		if ph in [MineLayerBrain.Phase.APPROACH, MineLayerBrain.Phase.REPOSITION, MineLayerBrain.Phase.DISENGAGE]:
			var pos := layer.global_position
			for d in layer.get_meta(&"drops"):
				var m: Variant = d.mine
				if int(d.k) < 0 or not is_instance_valid(m) or not (m as EnemyMine).is_live():
					continue
				var gap := pos.distance_to((m as EnemyMine).global_position)
				out.min_clear = minf(out.min_clear, gap)
				out.reach_seen = out.reach_seen or gap < reach
		last_phase = ph
		if (i + 1) % YIELD_EVERY == 0:
			await get_tree().process_frame
	out.passes = brain.passes_started
	out.fence_fallbacks = brain.fence_fallbacks
	out.spread_fallbacks = brain.spread_fallbacks
	out.abandoned = brain.abandoned_passes
	out.tail_drops = brain.tail_drops
	gut.p("scenario %s: %d passes, fence %d, spread %d, abandoned %d, tail %d, max live %d, min clear %.1f" % [name,
			out.passes, out.fence_fallbacks, out.spread_fallbacks, out.abandoned, out.tail_drops, out.max_live, out.min_clear])
	for fz in out.freezes:
		gut.p("  freeze at %.2f s (%.2f s into APPROACH): %s, spread fallback %s, %d earlier" % [fz.t, fz.after, fz.form,
				fz.spread_fallback, (fz.earlier as Array).size()])
	_cache[name] = out
	return out


func test_open_space_passes_are_gradual(scenario: String = use_parameters(["standing", "circling"])) -> void:
	var run: Dictionary = await _scenario(scenario)
	var cfg := SHIPPED
	assert_gte(run.passes, 3, "%s: at least three passes in 60 s (anti-inert)" % scenario)
	var lays: Array = run.lays
	for i in range(1, lays.size()):
		var gap: float = lays[i][0] - lays[i - 1][1]
		assert_gte(gap, cfg.break_seconds + cfg.pass_period_min - 0.001, "%s: %.2f s from LAY %d's end to the next" % [scenario, gap, i - 1])
	for n: int in run.drops_per_pass:
		assert_lte(n, cfg.mines_per_pass, "%s: at most six mines a pass" % scenario)
	for fz in run.freezes:
		if fz.spread_fallback:
			continue
		for e: Vector2 in fz.earlier:
			assert_gte((fz.centre as Vector2).distance_to(e), cfg.min_pass_separation,
					"%s: the plan frozen at %.2f s is 380 px from an earlier live pass" % [scenario, fz.t])
	assert_lte(run.max_live, cfg.max_live_mines, "%s: never more than 18 live" % scenario)
	if scenario == "standing":
		assert_eq(run.fence_fallbacks, 0, "standing: no fence fallback")
		assert_eq(run.abandoned, 0, "standing: no pass abandoned")


func test_the_layer_keeps_clear_of_older_lines_while_approaching_and_repositioning() -> void:
	var run: Dictionary = await _scenario("standing")
	assert_gt(run.min_clear, 100.0, "closest approach to a live mine of another pass: %.1f px" % run.min_clear)
	assert_true(run.reach_seen, "and the avoidance stage had something in reach at least once")


# ── The spread (pure plan_pass) ──────────────────────────────────────────────────────────────────

func test_the_fence_spread_takes_the_first_legal_rotation_and_turns_the_frame() -> void:
	var harness = _world("open_space")
	var brain := _brain(_pass_layer(harness, OS_PLAYER + Vector2(600.0, 0.0)))
	var cfg := brain.config
	var f := Vector2.RIGHT
	var theta := 2.0 * asin((cfg.min_pass_separation + 10.0) / (2.0 * cfg.fence_distance))
	var earlier: Array[Vector2] = []
	for a in [0.0, theta, -theta]:
		earlier.append(OS_PLAYER + f.rotated(a) * cfg.fence_distance)
	brain.plan_pass(OS_PLAYER, Vector2.ZERO, earlier)
	var want := OS_PLAYER + f.rotated(2.0 * theta) * cfg.fence_distance
	assert_almost_eq(rad_to_deg(2.0 * theta), 150.2, 0.05, "sanity: +2 theta is 150.2 deg")
	assert_lt(brain.pass_centre.distance_to(want), 1.0, "C at +150.2 deg (%s, want %s)" % [brain.pass_centre, want])
	for e in earlier:
		assert_gte(brain.pass_centre.distance_to(e), cfg.min_pass_separation, "clear of %s" % e)
	assert_almost_eq(brain.frame_f.angle_to(f.rotated(2.0 * theta)), 0.0, 0.01, "frame_f rotated with it")
	assert_eq(brain.spread_fallbacks, 0)
	assert_gt((-brain.pass_axis).dot(brain.get_parent().global_position - OS_PLAYER), 0.0,
			"the axis sign is re-applied to the rotated frame: S on the layer's side")


func test_the_fence_spread_with_no_legal_candidate_counts_a_fallback() -> void:
	var harness = _world("open_space")
	var brain := _brain(_pass_layer(harness, OS_PLAYER + Vector2(600.0, 0.0)))
	var cfg := brain.config
	var theta := 2.0 * asin((cfg.min_pass_separation + 10.0) / (2.0 * cfg.fence_distance))
	var earlier: Array[Vector2] = []
	for a in [0.0, theta, -theta, 2.0 * theta, -2.0 * theta]:
		earlier.append(OS_PLAYER + Vector2.RIGHT.rotated(a) * cfg.fence_distance)
	brain.plan_pass(OS_PLAYER, Vector2.ZERO, earlier)
	assert_lt(brain.pass_centre.distance_to(OS_PLAYER + Vector2.RIGHT * cfg.fence_distance), 0.01, "the first candidate")
	assert_eq(brain.spread_fallbacks, 1, "one spread fallback")
	assert_true(brain.pass_spread_fallback)


func test_the_lead_spread_shifts_along_the_heading() -> void:
	var harness = _world("open_space")
	var v := Vector2(100.0, 0.0)
	var first := _brain(_pure_lead_layer(harness))
	first.plan_pass(OS_PLAYER, v, [])
	var c0 := first.pass_centre
	var second := _brain(_pure_lead_layer(harness))
	var earlier: Array[Vector2] = [c0]
	second.plan_pass(OS_PLAYER, v, earlier)
	var c1 := second.pass_centre
	assert_eq(second.pass_form, &"lead")
	assert_gte((c1 - c0).dot(Vector2.RIGHT), 300.0, "shifted further along f (%s -> %s)" % [c0, c1])
	assert_lt(absf(c1.y - OS_PLAYER.y), 2.0, "still on the track line")
	assert_gte(c1.distance_to(c0), SHIPPED.min_pass_separation, "and clear of the earlier centre")
	assert_eq(second.spread_fallbacks, 0)


# ── The live cap, Assault, the tail drop ─────────────────────────────────────────────────────────

func test_the_live_cap_retires_the_oldest(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	harness.player.global_position = Vector2(5000.0, 5000.0)
	var layer := _pass_layer(harness, Vector2(640.0, 300.0))
	var brain := _brain(layer)
	var cap := SHIPPED.max_live_mines if mode == "open_space" else SHIPPED.assault_max_live_mines
	var mines: Array[EnemyMine] = []
	for i in cap:
		mines.append(brain.lay_mine(EnemyMine.Variant.PROXIMITY, layer.global_position + Vector2(0.0, -30.0)))
	assert_eq(brain.live_mine_count(), cap, "%s: %d live" % [mode, cap])
	var extra := brain.lay_mine(EnemyMine.Variant.PROXIMITY, layer.global_position + Vector2(0.0, -30.0))
	assert_eq(brain.live_mine_count(), cap, "%s: still %d after one more" % [mode, cap])
	assert_true(mines[0].is_fizzling(), "%s: the oldest is retired" % mode)
	assert_true(extra.is_live(), "%s: the new one is live" % mode)
	assert_false(mines[1].is_fizzling(), "%s: only the oldest" % mode)


func test_assault_lays_one_pass_then_leaves_sideways() -> void:
	var run := _natural_pass("assault")
	assert_eq(run.lays, 1, "one LAY")
	assert_true(run.freed, "and the layer left the world before the run ended")
	var laid: Array = run.drops.filter(func(d: Dictionary) -> bool: return int(d.k) >= 0)
	assert_eq(laid.size(), 6, "six mines")
	var end: int = run.lay_end
	assert_eq(run.phase[end], MineLayerBrain.Phase.DISENGAGE, "DISENGAGE right after LAY")
	assert_true(run.released[end], "with the corridor released")
	var settle := _ticks(0.25)
	var checked := 0
	for i in range(end + settle, run.phase.size()):
		assert_gt((run.vel[i] as Vector2).normalized().dot(run.axis), 0.9, "tick %d: leaving along the line's axis" % i)
		checked += 1
	assert_gt(checked, 0)


func test_an_assault_budget_expiring_mid_lay_lets_the_pass_finish() -> void:
	var natural := _natural_pass("assault")
	var harness = _world("assault")
	var layer := _pass_layer(harness, Vector2(240.0, 300.0))
	var brain := _brain(layer)
	layer.config.engage_seconds = (natural.lay_start + 1) * DT + 1.0
	var lay_start := -1
	var lay_end := -1
	var expired_in_lay := false
	for i in _ticks(20.0):
		_pass_step(layer, harness.player)
		if layer.is_queued_for_deletion():
			break
		if brain.phase == MineLayerBrain.Phase.LAY:
			if lay_start < 0:
				lay_start = i
			expired_in_lay = expired_in_lay or brain.budget.remaining() <= 0.0
		elif lay_start >= 0 and lay_end < 0:
			lay_end = i
			assert_eq(brain.phase, MineLayerBrain.Phase.DISENGAGE, "DISENGAGE after the LAY")
			assert_true((layer.get_node("EnemyMover") as EnemyMover).constraint_released(), "with the corridor released")
	assert_eq(lay_start, natural.lay_start, "the same seeded run up to LAY")
	assert_true(expired_in_lay, "the budget expired during the LAY")
	assert_gt(lay_end, lay_start)
	assert_lte((lay_end - lay_start) * DT, natural.stall + DT, "the LAY lasted no longer than its stall guard")
	assert_eq(_pass_drops(layer).size(), 6, "all six dropped")


## A stub kept 200 px from the Dispenser along `side` (`stern` or `front`), re-placed before every tick.
func _tail_run(side: String, seconds: float) -> Array:
	var harness = _world("open_space")
	var layer := _pass_layer(harness, OS_PLAYER + Vector2(600.0, 0.0))
	var brain := _brain(layer)
	var times: Array[int] = []
	var seen := 0
	for i in _ticks(seconds):
		var nose := Vector2.RIGHT.rotated(layer.rotation + EnemyMover.sprite_forward_angle_of(layer))
		var dispenser := layer.dispenser.global_position
		var at := dispenser - nose * 200.0 if side == "stern" else layer.global_position + nose * 200.0
		harness.player.global_position = at
		_pass_step(layer, harness.player, false)
		var drops: Array = layer.get_meta(&"drops")
		while seen < drops.size():
			times.append(i + 1)
			var mine := drops[seen].mine as EnemyMine
			assert_lt(mine.global_position.distance_to(dispenser), 0.5, "laid at the Dispenser, no eject (%s)" % mine.global_position)
			seen += 1
	return [times, brain]


func test_a_chasing_player_gets_a_tail_mine() -> void:
	var cooldown := _ticks(SHIPPED.tail_drop_cooldown)
	var behind := _tail_run("stern", SHIPPED.tail_drop_cooldown + 3.0 * DT)
	var times: Array[int] = behind[0]
	assert_gt(times.size(), 0, "a tail mine")
	assert_eq(times[0], 1, "within one tick")
	assert_eq(times.filter(func(t: int) -> bool: return t <= 1 + cooldown - 1).size(), 1, "still one at 2.5 s - 1 tick")
	assert_eq(times.filter(func(t: int) -> bool: return t <= 1 + cooldown + 1).size(), 2, "two by 2.5 s + 1 tick")
	assert_eq((behind[1] as MineLayerBrain).tail_drops, 2)
	var ahead := _tail_run("front", 2.6)
	assert_eq((ahead[0] as Array).size(), 0, "control: a player in front gets none")


func test_lay_never_tail_drops() -> void:
	var harness = _world("open_space")
	var layer := _pass_layer(harness, OS_PLAYER + Vector2(600.0, 0.0))
	var brain := _brain(layer)
	_pass_step(layer, harness.player)
	brain.freeze_plan()
	layer.global_position = brain.pass_run_in_point - brain.pass_axis * 100.0
	layer.velocity = brain.pass_axis * 240.0
	_run_until(layer, harness.player, _ticks(10.0), func() -> bool: return brain.phase == MineLayerBrain.Phase.LAY)
	assert_eq(brain.phase, MineLayerBrain.Phase.LAY)
	var tails := brain.tail_drops
	for i in _ticks(10.0):
		var nose := Vector2.RIGHT.rotated(layer.rotation + EnemyMover.sprite_forward_angle_of(layer))
		harness.player.global_position = layer.dispenser.global_position - nose * 200.0
		_pass_step(layer, harness.player, false)
		if brain.phase != MineLayerBrain.Phase.LAY:
			break
	assert_eq(brain.tail_drops, tails, "no tail drop during LAY")
	var drops: Array = layer.get_meta(&"drops")
	assert_eq(drops.size(), _pass_drops(layer).size(), "only pass mines")
