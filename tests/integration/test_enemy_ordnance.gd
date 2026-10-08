## Enemy ordnance (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.3, task t6): the gravity bomb,
## the mine and the pursuit bomb. Intent tests, driven by a fixture dropper that does what the
## Bomber's brain will do in t9/t10: acquire/instantiate, set the config-derived exports, `launch()`.
##
## Every case runs through real physics: a player stand-in carries a real layer-128 area, so the
## ordnance's proximity trigger, and a player `HitBox` standing in for a bullet or rocket, go through
## the same overlap queries the game uses. The blast is counted as the `ContactBlast` nodes that
## enter the container.
##
## Config values come from the shipped `BomberConfig` (bomber_config.tres), read only, never a typed number.
extends GutTest

const CFG: BomberConfig = preload("res://assault/scenes/enemies/bomber/bomber_config.tres")

const KINDS: Array[EnemyOrdnance.Kind] = [
	EnemyOrdnance.Kind.GRAVITY_BOMB, EnemyOrdnance.Kind.MINE, EnemyOrdnance.Kind.PURSUIT_BOMB]

var _cfg: BomberConfig = CFG  # shared resource: read, never write
var _container: Node2D
var _blasts: Array[ContactBlast] = []
## radius and damage of each blast, read as it enters the tree (it frees itself after a few frames)
var _blast_info: Array[Dictionary] = []
var _expired: Dictionary = {}


func before_each() -> void:
	_blasts = []
	_blast_info = []
	_expired = {}
	_container = Node2D.new()
	add_child_autofree(_container)
	_container.child_entered_tree.connect(_on_container_child)


func _on_container_child(node: Node) -> void:
	if node is ContactBlast:
		_blasts.append(node)
		_blast_info.append({
			"radius": ((node.get_child(0) as CollisionShape2D).shape as CircleShape2D).radius,
			"damage": (node as ContactBlast).damage,
			"layer": (node as ContactBlast).collision_layer,
		})


# ---------------------------------------------------------------------------------------------
# Fixture dropper
# ---------------------------------------------------------------------------------------------

func _seconds(s: float) -> void:
	await wait_physics_frames(roundi(s * Engine.physics_ticks_per_second))


## Config-derived exports and the launch, per kind - the dropper's whole job.
func _configure_and_launch(o: EnemyOrdnance, dir: Vector2, target: Vector2) -> void:
	match o.kind:
		EnemyOrdnance.Kind.GRAVITY_BOMB:
			o.trigger_radius = _cfg.trigger_radius
			o.arm_delay = _cfg.gravity_bomb_arm_delay
			o.warning_time = _cfg.gravity_bomb_fuse
			o.blast_radius = _cfg.gravity_blast_radius
			o.blast_damage = _cfg.gravity_blast_damage
			o.launch(dir, _cfg.gravity_bomb_speed, target)
		EnemyOrdnance.Kind.MINE:
			o.trigger_radius = _cfg.trigger_radius
			o.arm_delay = _cfg.mine_arm_delay
			o.warning_time = _cfg.mine_warning
			o.mine_life = _cfg.mine_life
			o.blast_radius = _cfg.mine_blast_radius
			o.blast_damage = _cfg.mine_blast_damage
			o.launch(dir, _cfg.mine_eject_speed, target)
		EnemyOrdnance.Kind.PURSUIT_BOMB:
			o.trigger_radius = _cfg.pursuit_trigger_radius
			o.steer_window = _cfg.pursuit_steer_window
			o.turn_rate = _cfg.pursuit_turn_rate
			o.steer_lead = _cfg.pursuit_lead
			o.final_speed = _cfg.pursuit_final_speed
			o.blast_radius = _cfg.pursuit_blast_radius
			o.blast_damage = _cfg.pursuit_blast_damage
			o.launch(dir, _cfg.pursuit_launch_speed, target)


## An unpooled drop: the dropper frees the ordnance on `expired`, the one-owner rule's other half.
func _drop(kind: EnemyOrdnance.Kind, at: Vector2, dir: Vector2, target: Vector2) -> EnemyOrdnance:
	var o: EnemyOrdnance = EnemyOrdnanceScenes.scene_for(kind).instantiate()
	_container.add_child(o)
	o.global_position = at
	_expired[o] = 0
	o.expired.connect(func() -> void: _expired[o] += 1)
	o.expired.connect(o.queue_free)
	_configure_and_launch(o, dir, target)
	return o


## A player stand-in: a CharacterBody2D in group `player` (so `TargetInfo.player()` finds it, with a
## velocity) carrying a layer-128 area like a real player HurtBox.
func _player(at: Vector2, velocity := Vector2.ZERO) -> CharacterBody2D:
	var p := CharacterBody2D.new()
	p.add_to_group(&"player")
	p.collision_layer = 0
	p.collision_mask = 0
	p.position = at
	p.velocity = velocity
	var hurt := Area2D.new()
	hurt.collision_layer = CollisionLayers.PLAYER_HURTBOX
	hurt.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	hurt.add_child(shape)
	p.add_child(hurt)
	_container.add_child(p)
	return p


## A player projectile stand-in: a real `HitBox` on the bullet layer (64) or rocket layer (32).
func _shot(at: Vector2, layer := CollisionLayers.PLAYER_HITBOX, dmg := 50) -> HitBox:
	var hb := HitBox.new()
	hb.collision_layer = layer
	hb.collision_mask = 0
	hb.damage = dmg
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	hb.add_child(shape)
	_container.add_child(hb)
	hb.global_position = at
	return hb


func _live_blasts() -> int:
	return _blasts.size()


# ---------------------------------------------------------------------------------------------
# Detonation: exactly one blast, with the configured radius and damage
# ---------------------------------------------------------------------------------------------

func _expected_blast(kind: EnemyOrdnance.Kind) -> Array:
	match kind:
		EnemyOrdnance.Kind.GRAVITY_BOMB:
			return [_cfg.gravity_blast_radius, _cfg.gravity_blast_damage]
		EnemyOrdnance.Kind.MINE:
			return [_cfg.mine_blast_radius, _cfg.mine_blast_damage]
		_:
			return [_cfg.pursuit_blast_radius, _cfg.pursuit_blast_damage]


func test_each_kind_blasts_exactly_once_with_its_configured_radius_and_damage() -> void:
	for kind in KINDS:
		_blasts = []
		_blast_info = []
		_player(Vector2(0, 20))
		var o := _drop(kind, Vector2.ZERO, Vector2.DOWN, Vector2(0, 20))
		await _seconds(2.5)
		assert_eq(_blasts.size(), 1, "kind %d: exactly one blast" % kind)
		if _blast_info.size() == 1:
			var info := _blast_info[0]
			assert_almost_eq(info["radius"] as float, _expected_blast(kind)[0] as float, 0.001, "kind %d radius" % kind)
			assert_eq(info["damage"], _expected_blast(kind)[1] as int, "kind %d damage" % kind)
			assert_eq(info["layer"], CollisionLayers.ENEMY_HITBOX, "the player's hurtbox sees it")
		assert_eq(_expired[o], 1, "kind %d: expired once" % kind)
		for n in get_tree().get_nodes_in_group(&"player"):
			n.remove_from_group(&"player")
			n.queue_free()
		await wait_physics_frames(1)


func test_a_blast_is_not_repeated_after_the_ordnance_is_gone() -> void:
	_player(Vector2(0, 20))
	_drop(EnemyOrdnance.Kind.MINE, Vector2.ZERO, Vector2.DOWN, Vector2.ZERO)
	await _seconds(2.5)
	assert_eq(_blasts.size(), 1)
	await _seconds(1.0)
	assert_eq(_blasts.size(), 1, "nothing detonates a second time")


func test_the_gravity_bomb_warns_for_its_fuse_before_it_blasts() -> void:
	_player(Vector2(0, 30))
	var o := _drop(EnemyOrdnance.Kind.GRAVITY_BOMB, Vector2.ZERO, Vector2.DOWN, Vector2(0, 600))
	# Armed at gravity_bomb_arm_delay; the player is already inside, so the warning starts then.
	await _seconds(_cfg.gravity_bomb_arm_delay + _cfg.gravity_bomb_fuse * 0.6)
	assert_true(o.is_warning(), "mid-fuse the bomb is blinking its warning")
	assert_eq(_blasts.size(), 0, "no blast before the fuse runs out")
	await _seconds(_cfg.gravity_bomb_fuse * 0.4 + 0.3)
	assert_eq(_blasts.size(), 1)


func test_a_gravity_bomb_with_nobody_near_detonates_at_the_end_of_its_drop() -> void:
	var drop := 100.0
	var o := _drop(EnemyOrdnance.Kind.GRAVITY_BOMB, Vector2.ZERO, Vector2.DOWN, Vector2(0, drop))
	var travel_time: float = (drop + o.max_travel_margin) / _cfg.gravity_bomb_speed
	await _seconds(travel_time * 0.8)
	assert_eq(_blasts.size(), 0, "still falling")
	await _seconds(travel_time * 0.4)
	assert_eq(_blasts.size(), 1, "it detonates when it has travelled to its aim point plus the margin")
	assert_eq(_expired[o], 1)


func test_a_player_outside_the_trigger_radius_never_sets_a_mine_off() -> void:
	_player(Vector2(0, 400))
	_drop(EnemyOrdnance.Kind.MINE, Vector2.ZERO, Vector2.DOWN, Vector2.ZERO)
	await _seconds(2.0)
	assert_eq(_blasts.size(), 0)


## Review round 2 B1(b): arming counts from release, and the trigger is a poll of the overlaps, so a
## player who is already inside the radius when the mine arms still sets it off.
func test_a_player_already_inside_when_the_mine_arms_still_sets_it_off() -> void:
	_player(Vector2(0, 30))
	var o := _drop(EnemyOrdnance.Kind.MINE, Vector2.ZERO, Vector2.DOWN, Vector2.ZERO)
	await _seconds(_cfg.mine_arm_delay * 0.6)
	assert_false(o.is_armed(), "not armed before its delay")
	assert_false(o.is_warning())
	await _seconds(_cfg.mine_arm_delay * 0.4 + 0.2)
	assert_true(o.is_armed())
	assert_true(o.is_warning(), "armed with a player inside: the warning starts")
	assert_eq(_blasts.size(), 0)
	await _seconds(_cfg.mine_warning + 0.3)
	assert_eq(_blasts.size(), 1)


func test_a_player_entering_after_the_mine_is_armed_sets_it_off() -> void:
	var p := _player(Vector2(0, 500))
	_drop(EnemyOrdnance.Kind.MINE, Vector2.ZERO, Vector2.DOWN, Vector2.ZERO)
	await _seconds(_cfg.mine_arm_delay + 0.3)
	assert_eq(_blasts.size(), 0)
	p.position = Vector2(0, 20)
	await _seconds(_cfg.mine_warning + 0.4)
	assert_eq(_blasts.size(), 1)


# ---------------------------------------------------------------------------------------------
# Defuse: any player hit pops it, no blast
# ---------------------------------------------------------------------------------------------

func test_a_player_bullet_defuses_every_kind_with_no_blast() -> void:
	for kind in KINDS:
		_blasts = []
		_blast_info = []
		_player(Vector2(0, 20))
		var at := Vector2(300.0 + 400.0 * kind, 0.0)
		var o := _drop(kind, at, Vector2.DOWN, at + Vector2(0, 300))
		# The player is inside the trigger radius only for the mine and the pursuit bomb at the
		# start; the shot lands on whichever kind it is, within its first 0.2 s.
		await wait_physics_frames(3)
		var shot := _shot(o.global_position)
		await _seconds(2.5)
		shot.queue_free()
		assert_eq(_blasts.size(), 0, "kind %d: a shot ordnance never blasts" % kind)
		assert_eq(_expired[o], 1, "kind %d: expired exactly once" % kind)
		assert_false(is_instance_valid(o) and not o.is_queued_for_deletion(), "kind %d freed" % kind)
		for n in get_tree().get_nodes_in_group(&"player"):
			n.remove_from_group(&"player")
			n.queue_free()
		await wait_physics_frames(1)


func test_a_rocket_defuses_too() -> void:
	var o := _drop(EnemyOrdnance.Kind.MINE, Vector2.ZERO, Vector2.DOWN, Vector2.ZERO)
	await wait_physics_frames(3)
	_shot(o.global_position, CollisionLayers.PLAYER_ROCKETS, 100)
	await _seconds(1.0)
	assert_eq(_blasts.size(), 0)
	assert_eq(_expired[o], 1)


func test_a_shot_after_the_warning_started_still_defuses() -> void:
	_player(Vector2(0, 30))
	var o := _drop(EnemyOrdnance.Kind.MINE, Vector2.ZERO, Vector2.DOWN, Vector2.ZERO)
	await _seconds(_cfg.mine_arm_delay + _cfg.mine_warning * 0.5)
	assert_true(o.is_warning())
	_shot(o.global_position)
	await _seconds(1.0)
	assert_eq(_blasts.size(), 0, "defusing wins even mid-warning")
	assert_eq(_expired[o], 1)


# ---------------------------------------------------------------------------------------------
# Mine: stays put, fizzles
# ---------------------------------------------------------------------------------------------

func test_a_mine_is_stationary_after_its_ejection() -> void:
	var o := _drop(EnemyOrdnance.Kind.MINE, Vector2.ZERO, Vector2.DOWN, Vector2.ZERO)
	await _seconds(o.eject_time + 0.1)
	var rest := o.global_position
	assert_gt(rest.y, 1.0, "it was ejected along its launch direction")
	await _seconds(2.0)
	assert_lt(o.global_position.distance_to(rest), 1.0, "drift under 1 px over 2 s")


func test_a_mine_fizzles_at_the_end_of_its_life_with_no_blast() -> void:
	var o := _drop(EnemyOrdnance.Kind.MINE, Vector2.ZERO, Vector2.DOWN, Vector2.ZERO)
	o.mine_life = 1.0
	await _seconds(o.mine_life * 0.8)
	assert_eq(_expired[o], 0, "still live")
	await _seconds(0.2 + o.fizzle_time + 0.2)
	assert_eq(_expired[o], 1, "fizzled and expired once")
	assert_eq(_blasts.size(), 0, "a fizzle is not a blast")


# ---------------------------------------------------------------------------------------------
# Gravity bomb keeps its heading
# ---------------------------------------------------------------------------------------------

func test_a_gravity_bomb_keeps_its_launch_direction_and_speed() -> void:
	var dir := Vector2(1, 2).normalized()
	var o := _drop(EnemyOrdnance.Kind.GRAVITY_BOMB, Vector2.ZERO, dir, Vector2(500, 1000))
	_player(Vector2(-900, 0))
	await _seconds(1.0)
	assert_almost_eq(o.heading().dot(dir), 1.0, 0.0001)
	var expected: Vector2 = dir * _cfg.gravity_bomb_speed * 1.0
	assert_lt(o.global_position.distance_to(expected), _cfg.gravity_bomb_speed * 0.1,
			"about one second of flight at gravity_bomb_speed")


# ---------------------------------------------------------------------------------------------
# Pursuit bomb: steers for a window, then freezes
# ---------------------------------------------------------------------------------------------

func test_a_pursuit_bomb_hits_a_player_who_holds_still() -> void:
	_player(Vector2(0, 500))
	var o := _drop(EnemyOrdnance.Kind.PURSUIT_BOMB, Vector2.ZERO, Vector2.DOWN, Vector2(0, 500))
	await _seconds(5.0)
	assert_eq(_blasts.size(), 1)
	assert_eq(_expired[o], 1)


func test_a_pursuit_bomb_turns_no_faster_than_its_rate_then_freezes_its_heading() -> void:
	var p := _player(Vector2(0, 500))
	var o := _drop(EnemyOrdnance.Kind.PURSUIT_BOMB, Vector2.ZERO, Vector2.RIGHT, Vector2(0, 500))
	var dt := 1.0 / Engine.physics_ticks_per_second
	var prev := o.heading()
	var worst_step := 0.0
	var window_frames := roundi(_cfg.pursuit_steer_window / dt)
	for i in window_frames:
		await get_tree().physics_frame
		worst_step = maxf(worst_step, absf(prev.angle_to(o.heading())))
		prev = o.heading()
	assert_lte(worst_step, _cfg.pursuit_turn_rate * dt + 0.001, "never turns faster than pursuit_turn_rate")
	assert_gt(absf(Vector2.RIGHT.angle_to(o.heading())), 0.5, "it did steer toward the player below it")
	await wait_physics_frames(3)
	var frozen := o.heading()
	# Now the target moves somewhere else entirely: the heading must not follow.
	p.position = Vector2(-600, 100)
	p.velocity = Vector2(-300, 0)
	await _seconds(0.8)
	assert_almost_eq(o.heading().dot(frozen), 1.0, 0.0001, "heading frozen after the steer window")


func test_a_player_who_turns_at_full_rate_after_the_window_escapes_a_pursuit_bomb() -> void:
	var p := _player(Vector2(0, 500))
	var o := _drop(EnemyOrdnance.Kind.PURSUIT_BOMB, Vector2.ZERO, Vector2.DOWN, Vector2(0, 500))
	var closest := INF
	var dt := 1.0 / Engine.physics_ticks_per_second
	var window_frames := roundi((_cfg.pursuit_steer_window + 0.1) / dt)
	await wait_physics_frames(window_frames)
	# Heading is frozen: step sideways at a sustained 300 px/s.
	p.velocity = Vector2(300, 0)
	for i in roundi(4.0 / dt):
		await get_tree().physics_frame
		p.position += p.velocity * dt
		if is_instance_valid(o) and not o.is_queued_for_deletion():
			closest = minf(closest, o.global_position.distance_to(p.position))
	assert_gt(closest, _cfg.pursuit_trigger_radius, "closest approach stays outside the trigger radius")
	assert_eq(_blasts.size(), 0, "no blast on the escaped bomb")


# ---------------------------------------------------------------------------------------------
# Lifetime backstop, reset, pool, structure
# ---------------------------------------------------------------------------------------------

func test_the_lifetime_backstop_expires_ordnance_without_a_blast() -> void:
	var o := _drop(EnemyOrdnance.Kind.GRAVITY_BOMB, Vector2.ZERO, Vector2.DOWN, Vector2(0, 5000))
	(o.get_node("ProjectileLifetime") as ProjectileLifetime).max_time = 0.5
	await _seconds(0.9)
	assert_eq(_expired[o], 1, "the backstop expired it exactly once")
	assert_eq(_blasts.size(), 0, "a timed-out bomb does not blast")


func test_reset_restores_the_authored_exports_and_health() -> void:
	for kind in KINDS:
		var o: EnemyOrdnance = EnemyOrdnanceScenes.scene_for(kind).instantiate()
		_container.add_child(o)
		var damage := o.blast_damage
		var radius := o.blast_radius
		var warning := o.warning_time
		var trigger := o.trigger_radius
		o.blast_damage = 999
		o.blast_radius = 999.0
		o.warning_time = 99.0
		o.trigger_radius = 999.0
		(o.get_node("Health") as Health).set_health(0)
		o.reset()
		assert_eq(o.blast_damage, damage, "kind %d damage" % kind)
		assert_eq(o.blast_radius, radius, "kind %d radius" % kind)
		assert_eq(o.warning_time, warning, "kind %d warning" % kind)
		assert_eq(o.trigger_radius, trigger, "kind %d trigger" % kind)
		assert_eq((o.get_node("Health") as Health).current_health, 1, "kind %d health" % kind)
		o.queue_free()


func test_a_pooled_ordnance_is_reusable_after_a_defuse_and_blasts_once_on_its_next_life() -> void:
	var ship := Node2D.new()
	_container.add_child(ship)
	var pool := BulletPool.new()
	pool.bullet_scene = EnemyOrdnanceScenes.MINE
	pool.pool_size = 1
	pool.persist_after_owner_death = true
	ship.add_child(pool)
	var o := pool.acquire(Vector2(100, 100)) as EnemyOrdnance
	assert_not_null(o)
	_configure_and_launch(o, Vector2.DOWN, Vector2.ZERO)
	await wait_physics_frames(3)
	var shot := _shot(o.global_position)
	await _seconds(0.5)
	shot.queue_free()
	assert_eq(_blasts.size(), 0)
	await wait_physics_frames(2)
	var again := pool.acquire(Vector2(100, 100)) as EnemyOrdnance
	assert_eq(again, o, "the single-slot pool recycled the defused ordnance")
	_configure_and_launch(again, Vector2.DOWN, Vector2.ZERO)
	_player(Vector2(100, 120))
	await _seconds(_cfg.mine_arm_delay + _cfg.mine_warning + 0.5)
	assert_eq(_blasts.size(), 1, "its second life detonates exactly once")


func test_a_pooled_ordnance_outlives_its_ship_and_still_detonates() -> void:
	var ship := Node2D.new()
	_container.add_child(ship)
	var pool := BulletPool.new()
	pool.bullet_scene = EnemyOrdnanceScenes.MINE
	pool.pool_size = 2
	pool.persist_after_owner_death = true
	ship.add_child(pool)
	var o := pool.acquire(Vector2(100, 100)) as EnemyOrdnance
	_configure_and_launch(o, Vector2.DOWN, Vector2.ZERO)
	ship.queue_free()
	await wait_physics_frames(3)
	assert_true(is_instance_valid(o) and not o.is_queued_for_deletion(), "the mine outlives its ship")
	var p := _player(o.global_position + Vector2(0, 10))
	await _seconds(_cfg.mine_arm_delay + _cfg.mine_warning + 0.5)
	assert_eq(_blasts.size(), 1, "and still goes off")
	assert_not_null(p)


func test_ordnance_is_not_an_enemy() -> void:
	for kind in KINDS:
		var o: EnemyOrdnance = EnemyOrdnanceScenes.scene_for(kind).instantiate()
		_container.add_child(o)
		assert_false(o.is_in_group(&"enemies"), "kind %d is not in enemies" % kind)
		assert_false((o as Object) is BaseEnemy)
		o.queue_free()


func test_scene_structure_and_authored_lifetimes() -> void:
	var expected: Dictionary = {
		EnemyOrdnance.Kind.GRAVITY_BOMB: [16.0, 1800.0],
		EnemyOrdnance.Kind.MINE: [10.0, 0.0],
		EnemyOrdnance.Kind.PURSUIT_BOMB: [10.0, 2400.0],
	}
	for kind in KINDS:
		var o: EnemyOrdnance = EnemyOrdnanceScenes.scene_for(kind).instantiate()
		_container.add_child(o)
		assert_eq(o.kind, kind)
		var hurt := o.get_node("HurtBox") as HurtBox
		assert_eq(hurt.collision_layer, CollisionLayers.ENEMY_HURTBOX, "HurtBox layer 512")
		assert_eq(hurt.collision_mask, CollisionLayers.PLAYER_HITBOX | CollisionLayers.PLAYER_ROCKETS,
				"HurtBox mask 96")
		assert_true(hurt.accepted_damage_types.is_empty(), "accepts every damage type")
		assert_eq((o.get_node("Health") as Health).max_health, 1)
		var prox := o.get_node("ProximityArea") as Area2D
		assert_eq(prox.collision_layer, 0)
		assert_eq(prox.collision_mask, CollisionLayers.PLAYER_HURTBOX)
		var lt := o.get_node("ProjectileLifetime") as ProjectileLifetime
		assert_eq(lt.max_time, (expected[kind] as Array)[0] as float, "kind %d max_time" % kind)
		assert_eq(lt.max_distance, (expected[kind] as Array)[1] as float, "kind %d max_distance" % kind)
		o.queue_free()


func test_the_proximity_radius_is_per_instance() -> void:
	var a: EnemyOrdnance = EnemyOrdnanceScenes.scene_for(EnemyOrdnance.Kind.MINE).instantiate()
	var b: EnemyOrdnance = EnemyOrdnanceScenes.scene_for(EnemyOrdnance.Kind.MINE).instantiate()
	_container.add_child(a)
	_container.add_child(b)
	a.trigger_radius = 30.0
	a.launch(Vector2.DOWN, 100.0, Vector2.ZERO)
	var ra := ((a.get_node("ProximityArea/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius
	var rb := ((b.get_node("ProximityArea/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius
	assert_almost_eq(ra, 30.0, 0.001)
	assert_ne(rb, 30.0, "a sibling instance does not share the shape")
	a.queue_free()
	b.queue_free()


# ---------------------------------------------------------------------------------------------
# Sizing, source sweeps
# ---------------------------------------------------------------------------------------------

func test_pool_size_for_mines_uses_the_run_cadence_and_life() -> void:
	var n := EnemyOrdnanceScenes.pool_size_for(EnemyOrdnance.Kind.MINE, _cfg)
	assert_eq(n, _cfg.max_mines_per_run * int(ceil(_cfg.mine_life / _cfg.min_run_period)))


func test_pool_size_for_bombs_is_four() -> void:
	assert_eq(EnemyOrdnanceScenes.pool_size_for(EnemyOrdnance.Kind.GRAVITY_BOMB, _cfg), 4)
	assert_eq(EnemyOrdnanceScenes.pool_size_for(EnemyOrdnance.Kind.PURSUIT_BOMB, _cfg), 4)


func test_scene_for_maps_each_kind_to_its_constant() -> void:
	assert_eq(EnemyOrdnanceScenes.scene_for(EnemyOrdnance.Kind.GRAVITY_BOMB), EnemyOrdnanceScenes.GRAVITY_BOMB)
	assert_eq(EnemyOrdnanceScenes.scene_for(EnemyOrdnance.Kind.MINE), EnemyOrdnanceScenes.MINE)
	assert_eq(EnemyOrdnanceScenes.scene_for(EnemyOrdnance.Kind.PURSUIT_BOMB), EnemyOrdnanceScenes.PURSUIT_BOMB)


const _ORDNANCE_DIR := "res://assault/scenes/projectiles/enemy_ordnance/"


## Own accumulated clock only: no Timer node and no create_timer anywhere in the ordnance family
## (a timer outlives a freed test tree and leaks - tests/README.md).
func test_the_ordnance_uses_no_timer_node_and_no_create_timer() -> void:
	var files := ["enemy_ordnance.gd", "gravity_bomb.tscn", "mine.tscn", "pursuit_bomb.tscn"]
	for f in files:
		var text := FileAccess.get_file_as_string(_ORDNANCE_DIR + f)
		assert_ne(text, "", f + " readable")
		assert_false(text.contains("create_timer"), f + " has no create_timer")
		assert_false(text.contains("Timer"), f + " mentions no Timer")
