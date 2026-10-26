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
