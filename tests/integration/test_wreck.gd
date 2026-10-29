## INTENT tests for the wreck family (plan §2.8, docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md; build choices in
## docs/plans/cmvg30aax007rqs2x14trnuf9/3-plan.md): wrecks and derelict structures are real cover — solid, opaque to
## sight lines and to shots of both sides — a drifting wreck hurts what it runs into while a still one is harmless, and
## every wreck and debris fragment leaves on its own.
##
## Collision rows (a shot, a sight line, a body touching a wreck) use real physics on the 8× clock (step kept at 1/60
## game-second, `test_level1_drone_exit.gd`'s `_scale_clock()`), restored in `after_each`. Lifetime and fragment rows
## hand-tick `_physics_process(D)` with the node's own tick switched off. Every node is added with
## `add_child_autofree`, so the static `Hazards` registry is empty after each test.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SMALL: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_small.tscn")
const MEDIUM: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_medium.tscn")
const LARGE: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_large.tscn")
const SATELLITE: PackedScene = preload("res://assault/scenes/hazards/wreck/structure_satellite.tscn")
const CARGO: PackedScene = preload("res://assault/scenes/hazards/wreck/structure_cargo_platform.tscn")
const MODULE: PackedScene = preload("res://assault/scenes/hazards/wreck/structure_station_module.tscn")
const EXPLOSIVE: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_explosive.tscn")
const RAM_SCENE: PackedScene = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn")
const DEBRIS: PackedScene = preload("res://assault/scenes/hazards/wreck/debris_drift.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const ROUND_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/rounds/pulse_round.tscn")
const ASTEROID_SCENE: PackedScene = preload("res://assault/scenes/hazards/small_asteroid/small_asteroid.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const SWARM_SCENE: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")
const SNIPER_SCENE: PackedScene = preload("res://assault/scenes/enemies/sniper/sniper.tscn")
const SNIPER_SHOT: PackedScene = preload("res://assault/scenes/projectiles/bullets/sniper_bullet.tscn")

const _MODES := ["open_space", "assault"]
const _ALL_WRECKS := [SMALL, MEDIUM, LARGE, SATELLITE, CARGO, MODULE]
const _SHIP_SCENES := [
	"res://open_space/scenes/entities/player/player_ship.tscn",
	"res://assault/scenes/player/player_fighter.tscn",
	"res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn",
	"res://assault/scenes/enemies/razor_drone/razor_drone.tscn",
	"res://assault/scenes/enemies/fighter/fighter.tscn",
	"res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor.tscn",
	"res://assault/scenes/enemies/bomber/bomber.tscn",
	"res://assault/scenes/enemies/sniper/sniper.tscn",
	"res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn",
	"res://assault/scenes/enemies/missile_corvette/missile_corvette.tscn",
	"res://assault/scenes/enemies/support_ship/support_ship.tscn",
	"res://assault/scenes/enemies/mine_layer/mine_layer.tscn",
	"res://assault/scenes/enemies/defense_turret/defense_turret.tscn",
	"res://assault/scenes/enemies/power_source/power_source.tscn",
]
const D := 1.0 / 60.0
const P := Vector2(640.0, 360.0)
const _SPEEDUP: int = 8

var _clock_scaled: bool = false
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8


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


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await _frames(int(ceil(s * 60.0)))


func _container() -> Node2D:
	var c := Node2D.new()
	add_child_autofree(c)
	return c


## A harness whose fake player has left the group, so a real player scene can be the only one.
func _world(mode: String):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.remove_from_group(&"player")
	return h


func _wreck(parent: Node, at: Vector2, scene: PackedScene = MEDIUM) -> Wreck:
	var w := scene.instantiate() as Wreck
	parent.add_child(w)
	w.global_position = at
	return w


func _debris(parent: Node, at: Vector2) -> DebrisFragment:
	var f := DEBRIS.instantiate() as DebrisFragment
	parent.add_child(f)
	f.global_position = at
	return f


## A real player for [param mode], frozen (no input, no own movement), shield emptied, every hit recorded.
func _player(parent: Node, mode: String, at: Vector2, received: Array[int]) -> PlayerBase:
	var player: PlayerBase = (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate()
	parent.add_child(player)
	player.global_position = at
	player.set_physics_process(false)
	player.set_process(false)
	player.shield_component.set_all_zero()
	(player.get_node("HurtBox") as HurtBox).received_damage.connect(func(n: int) -> void: received.append(n))
	return player


func _body_radius(body: Node2D) -> float:
	var cs := body.get_node("Collision" if body.has_node("Collision") else "CollisionShape2D") as CollisionShape2D
	return (cs.shape as CircleShape2D).radius * cs.global_scale.x


## The body circle's centre: the Assault fighter's sits 1 px below its origin.
func _body_centre(body: Node2D) -> Vector2:
	return (body.get_node("Collision" if body.has_node("Collision") else "CollisionShape2D") as Node2D).global_position


func _hp(node: Node) -> int:
	return (node.get_node("Health") as Health).current_health


func _gone(node: Variant) -> bool:
	return not is_instance_valid(node) or (node as Node).is_queued_for_deletion()


# --- sight lines --------------------------------------------------------------------------------

func test_a_wreck_blocks_line_of_sight_and_debris_does_not() -> void:
	_scale_clock()
	var c := _container()
	_wreck(c, Vector2(400, 300))
	var debris := _debris(c, Vector2(800, 300))
	debris.speed = 0.0
	await _frames(3)
	var space := c.get_world_2d().direct_space_state
	assert_false(LineOfSight.clear(space, Vector2(400, 150), Vector2(400, 450)), "a wreck stands on the line")
	assert_true(LineOfSight.clear(space, Vector2(500, 150), Vector2(500, 450)), "control: a line beside it is clear")
	assert_true(LineOfSight.clear(space, Vector2(800, 150), Vector2(800, 450)), "debris is not a sight-line blocker")


# --- shots of both sides ------------------------------------------------------------------------

func test_a_player_bullet_stops_on_a_wreck_and_damages_it() -> void:
	_scale_clock()
	var c := _container()
	var w := _wreck(c, Vector2(400, 300))
	var hp0 := _hp(w)
	var b: Node2D = BULLET_SCENE.instantiate()
	c.add_child(b)
	b.global_position = Vector2(400, 420)
	b.expired.connect(b.queue_free)
	await _frames(30)
	assert_true(_gone(b), "the bullet ended on the wreck")
	assert_lt(_hp(w), hp0, "and the wreck took its damage")
	assert_false(is_instance_valid(b) and (b as Node2D).global_position.y < 300.0, "it never crossed the wreck")


func test_an_enemy_rocket_stops_on_a_wreck() -> void:
	_scale_clock()
	var c := _container()
	var w := _wreck(c, Vector2(400, 300))
	var hp0 := _hp(w)
	var ends: Array = []
	var r := EnemyRocketScenes.scene_for(EnemyRocket.Kind.DUMB).instantiate() as EnemyRocket
	c.add_child(r)
	r.global_position = Vector2(400, 50)
	r.reset()
	r.expired.connect(func() -> void: ends.append(r))
	r.expired.connect(r.queue_free)
	r.launch(Vector2.DOWN, Vector2(400, 700), null)
	await _seconds(1.2)
	assert_eq(ends.size(), 1, "the rocket's flight ended")
	assert_lt(_hp(w), hp0, "on the wreck, which took the impact")


func _round(parent: Node, at: Vector2, dir: Vector2, ends: Array) -> EnemyBullet:
	var b := ROUND_SCENE.instantiate() as EnemyBullet
	parent.add_child(b)
	b.global_position = at
	b.reset()
	b.set_direction(dir)
	b.expired.connect(func() -> void: ends.append(b))
	b.expired.connect(b.queue_free)
	return b


func test_an_enemy_round_stops_on_an_armed_wreck() -> void:
	_scale_clock()
	var c := _container()
	var w := _wreck(c, Vector2(400, 300))
	await _seconds(0.7)
	assert_true(w.is_armed(), "the contact box armed after 0.6 s")
	var ends: Array = []
	var b := _round(c, Vector2(250, 300), Vector2.RIGHT, ends)
	await _seconds(1.0)
	assert_eq(ends.size(), 1, "the round ended on the wreck: cover works from both sides")
	assert_false(is_instance_valid(b), "and was freed")


func test_an_enemy_round_still_passes_an_asteroid() -> void:
	_scale_clock()
	var c := _container()
	var rock: Node2D = ASTEROID_SCENE.instantiate()
	c.add_child(rock)
	rock.global_position = Vector2(400, 300)
	rock.set_physics_process(false)
	await _seconds(0.7)
	var ends: Array = []
	var b := _round(c, Vector2(250, 300), Vector2.RIGHT, ends)
	await _seconds(1.0)
	assert_eq(ends.size(), 0, "an asteroid's contact box does not answer stops_enemy_rounds()")
	assert_true(is_instance_valid(b) and b.global_position.x > 450.0, "the round flew on past the asteroid")


func test_a_wreck_at_zero_hp_is_destroyed_once_and_frees() -> void:
	var c := _container()
	var w := _wreck(c, Vector2(400, 300))
	var n := Hazards.count()
	var destroyed: Array = []
	w.destroyed.connect(func(at: Vector2) -> void: destroyed.append(at))
	var hurt := w.get_node("HurtBox") as HurtBox
	hurt.received_damage.emit(150)
	assert_false(_gone(w), "200 HP: 150 is not enough")
	hurt.received_damage.emit(50)
	hurt.received_damage.emit(50)
	assert_eq(destroyed.size(), 1, "destroyed once")
	assert_true(w.is_queued_for_deletion())
	await get_tree().process_frame
	assert_false(is_instance_valid(w))
	assert_eq(Hazards.count(), n - 1, "and unregistered")


# --- contact: only a moving wreck hurts --------------------------------------------------------

const _OFFSETS := 10


## One concurrent sweep: `_OFFSETS` ship/wreck pairs 140 px apart (inside the Assault world rect, x −444…1724, so no wreck retires early), wreck i starting `gap + i·step/10` px from touching
## (exact touch included) so the first penetrating step lands at every sub-step phase. Returns each ship's hits.
func _sweep(h, make_ship: Callable, speed: float, gap: float) -> Array:
	var hits: Array = []
	var step := speed / 60.0
	for i in _OFFSETS:
		var at := Vector2(100.0 + 140.0 * i, 700.0)
		var counted: Array[int] = []
		var ship: Node2D = make_ship.call(h.root, at, counted)
		var w := MEDIUM.instantiate() as Wreck
		w.drift_velocity = Vector2(0, speed)
		var touch := 25.0 + _body_radius(ship)
		w.global_position = at - Vector2(0, touch + gap + step * float(i) / float(_OFFSETS))
		h.root.add_child(w)
		hits.append(counted)
	var travel := gap + step
	await _seconds(travel / speed + 0.6)
	return hits


func _make_player(mode: String) -> Callable:
	return func(root: Node, at: Vector2, counted: Array[int]) -> Node2D:
		return _player(root, mode, at, counted)


func _make_swarm(root: Node, at: Vector2, counted: Array[int]) -> Node2D:
	var e := SWARM_SCENE.instantiate() as BaseEnemy
	e.global_position = at
	root.add_child(e)
	e.suspend_ai()
	e.set_physics_process(false)
	e.hurt_box.received_damage.connect(func(n: int) -> void: counted.append(n))
	return e


func _assert_each_hurt_once(hits: Array, what: String) -> void:
	for i in hits.size():
		assert_eq(hits[i], [10] as Array[int], "%s, offset %d/%d: hurt exactly once" % [what, i, _OFFSETS])


func test_a_drifting_wreck_hurts_the_player_at_every_sub_step_phase(mode: String = use_parameters(_MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	# Assault forces 60 px/s down; Open Space drifts at the same speed for the same 1 px steps.
	var hits: Array = await _sweep(h, _make_player(mode), 60.0, 45.0)
	_assert_each_hurt_once(hits, "%s player" % h.label)


func test_a_slow_open_space_drift_still_hurts_the_player() -> void:
	_scale_clock()
	var h = _world("open_space")
	var hits: Array = await _sweep(h, _make_player("open_space"), 15.0, 12.0)
	_assert_each_hurt_once(hits, "15 px/s")


func test_a_drifting_wreck_hurts_an_enemy(mode: String = use_parameters(_MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	var hits: Array = await _sweep(h, _make_swarm, 60.0, 45.0)
	_assert_each_hurt_once(hits, "%s swarm drone" % h.label)
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var x := (e as Node2D).global_position.x
		assert_almost_eq(fposmod(x - 100.0, 140.0), 0.0, 0.001, "%s: the drone was held still (x %.2f)" % [h.label, x])


## Pushes [param ship] into a still, armed wreck with its own `move_and_slide()` for 1 s.
func _ram_still_wreck(h, ship: CharacterBody2D) -> Wreck:
	var w := _wreck(h.root, P)
	ship.global_position = P + Vector2(0, -(_body_radius(w) + _body_radius(ship) + 60.0))
	await _seconds(0.7)
	assert_true(w.is_armed())
	for i in 60:
		ship.velocity = Vector2(0, 200)
		ship.move_and_slide()
		await get_tree().physics_frame
	return w


func test_a_still_wreck_touched_by_a_moving_player_does_not_hurt() -> void:
	_scale_clock()
	var h = _world("open_space")
	var received: Array[int] = []
	var player := _player(h.root, "open_space", P, received)
	var w: Wreck = await _ram_still_wreck(h, player)
	var rest := P.y - _body_radius(w) - _body_radius(player)
	assert_eq(received, [] as Array[int], "a still wreck is solid but harmless")
	assert_between(player.global_position.y, rest - 1.0, rest + 0.1, "the player came to rest against the body")


func test_a_still_wreck_does_not_hurt_a_sniper_parked_against_it() -> void:
	_scale_clock()
	var h = _world("open_space")
	var e := SNIPER_SCENE.instantiate() as BaseEnemy
	h.root.add_child(e)
	e.set_physics_process(false)
	var hits: Array[int] = []
	e.hurt_box.received_damage.connect(func(n: int) -> void: hits.append(n))
	await _ram_still_wreck(h, e)
	assert_eq(hits, [] as Array[int], "the sniper (t13 parks it against cover) takes nothing from a still wreck")


## The invariant "a still wreck is harmless" rests on: no ship's hurtbox reaches past its body.
func test_no_ship_hurtbox_is_larger_than_its_body() -> void:
	var c := _container()
	for path in _SHIP_SCENES:
		var ship := (load(path) as PackedScene).instantiate() as Node2D
		c.add_child(ship)
		var body := ship.get_node("Collision" if ship.has_node("Collision") else "CollisionShape2D") as CollisionShape2D
		var hurt_box := ship.get_node("HurtBox") as Area2D
		var hurt: CollisionShape2D = null
		for child in hurt_box.get_children():
			if child is CollisionShape2D:
				hurt = child
		var body_half := body.shape.get_rect().size * body.global_scale.abs() * 0.5
		var hurt_half := hurt.shape.get_rect().size * hurt.global_scale.abs() * 0.5
		assert_lte(hurt_half.x, body_half.x + 0.001, "%s: hurtbox wider than the body" % path)
		assert_lte(hurt_half.y, body_half.y + 0.001, "%s: hurtbox taller than the body" % path)


func test_a_wreck_spawned_on_the_player_does_not_hurt_before_it_arms() -> void:
	_scale_clock()
	var h = _world("open_space")
	var received: Array[int] = []
	_player(h.root, "open_space", P, received)
	var w := MEDIUM.instantiate() as Wreck
	w.spawn_into(h.root, P, 0.0)
	await _seconds(0.55)
	assert_true(is_instance_valid(w) and w.is_inside_tree(), "spawned")
	assert_eq(received, [] as Array[int], "no hurt during the first 0.6 s")
	await _seconds(0.3)
	assert_eq(received, [10] as Array[int], "boundary: once armed the same overlap does hurt")


func test_a_wreck_spawned_on_the_assault_player_drifts_off_it() -> void:
	_scale_clock()
	var h = _world("assault")
	var received: Array[int] = []
	var player := _player(h.root, "assault", P, received)
	var w := MEDIUM.instantiate() as Wreck
	w.spawn_into(h.root, P, 0.0)
	await _seconds(1.5)
	assert_gt(w.global_position.distance_to(player.global_position), _body_radius(w) + _body_radius(player),
		"the yield ignores a ship it was born on: the wreck drifted clear")


# --- lifetime per mode --------------------------------------------------------------------------

func test_assault_drift_is_60_down_whatever_the_inherited_y() -> void:
	var h = _world("assault")
	var w := MEDIUM.instantiate() as Wreck
	w.drift_velocity = Vector2(30, -200)
	h.root.add_child(w)
	w.global_position = P
	w.set_physics_process(false)
	for i in 60:
		w._physics_process(D)
	assert_almost_eq(w.global_position, P + Vector2(30, 60), Vector2(0.01, 0.01), "x inherited, y always 60 px/s down")
	assert_eq(w.velocity, Vector2(30, 60))
	assert_eq(w.hazard_info().velocity, Vector2(30, 60), "the hazard info leads the real drift")


func test_assault_wreck_frees_on_leaving_the_world_rect() -> void:
	_scale_clock()
	var h = _world("assault")
	var w := _wreck(h.root, Vector2(640, 1150))
	var n := Hazards.count()
	await _seconds(1.0)
	assert_false(is_instance_valid(w), "past y 1164 it ended and freed itself")
	assert_eq(Hazards.count(), n - 1)


func test_open_space_wreck_fades_out_and_frees_after_its_lifetime() -> void:
	var h = _world("open_space")
	var w := _wreck(h.root, P)
	w.set_physics_process(false)
	(w.get_node("ProjectileLifetime") as Node).set_physics_process(false)
	var n := Hazards.count()
	for i in 75:
		w._physics_process(0.5)
	assert_false(w.is_retiring(), "37.5 s: still in play")
	w._physics_process(0.5)
	assert_true(w.is_retiring(), "38 s: the 2 s fade starts")
	assert_eq(Hazards.count(), n - 1, "and it is no longer a hazard")
	w._physics_process(1.0)
	assert_almost_eq(w.modulate.a, 0.5, 0.01, "halfway through the fade")
	assert_false(w.is_queued_for_deletion())
	w._physics_process(1.0)
	assert_true(w.is_queued_for_deletion(), "40 s: gone")


func test_open_space_wreck_does_not_drift_by_default_and_a_structure_is_permanent() -> void:
	var h = _world("open_space")
	var s := _wreck(h.root, P, SATELLITE)
	s.set_physics_process(false)
	for i in 120:
		s._physics_process(1.0)
	assert_false(s.is_retiring(), "lifetime 0: a placed structure never leaves")
	assert_eq(s.global_position, P, "and does not drift")


# --- the clamp edge -----------------------------------------------------------------------------

func _overlap_frames(w: Wreck, player: Node2D, seconds: float) -> int:
	var touch := _body_radius(w) + _body_radius(player) - 0.5
	var held := 0
	for i in int(seconds * 60.0):
		await get_tree().physics_frame
		if is_instance_valid(w) and w.global_position.distance_to(_body_centre(player)) < touch:
			held += 1
	return held


func test_a_wreck_never_holds_the_assault_player_at_the_clamp_edge() -> void:
	_scale_clock()
	var h = _world("assault")
	var received: Array[int] = []
	var player := _player(h.root, "assault", Vector2(640, 1100), received)
	var w := MEDIUM.instantiate() as Wreck
	w.global_position = Vector2(640, 1100 - (25.0 + _body_radius(player) + 15.0))
	h.root.add_child(w)
	var held: int = await _overlap_frames(w, player, 1.5)
	assert_lte(held, 2, "the wreck yields to the pinned player (%d frames overlapping)" % held)
	assert_eq(player.global_position, Vector2(640, 1100), "and never moved them")


func test_without_the_yield_the_same_wreck_holds_the_player() -> void:
	_scale_clock()
	var h = _world("assault")
	var received: Array[int] = []
	var player := _player(h.root, "assault", Vector2(640, 1100), received)
	var w := MEDIUM.instantiate() as Wreck
	w.yield_to_ships = false
	w.global_position = Vector2(640, 1100 - (25.0 + _body_radius(player) + 15.0))
	h.root.add_child(w)
	var held: int = await _overlap_frames(w, player, 1.5)
	assert_gt(held, 2, "boundary: the clamp-edge row can fail (%d frames overlapping)" % held)


# --- retire, spawn, registry, groups ------------------------------------------------------------

func test_retire_unregisters_at_once_and_frees_after_the_fade() -> void:
	var c := _container()
	var w := _wreck(c, P)
	w.set_physics_process(false)
	var n := Hazards.count()
	w.retire()
	assert_eq(Hazards.count(), n - 1, "unregistered at once")
	assert_eq(w.collision_layer, 0, "no longer solid")
	assert_eq((w.get_node("HurtBox") as Area2D).collision_layer, 0, "no longer shootable")
	assert_eq((w.get_node("ContactHitBox") as Area2D).collision_layer, 0, "no longer a contact or a round stop")
	w._physics_process(0.25)
	assert_almost_eq(w.modulate.a, 0.5, 0.01, "fading")
	assert_false(w.is_queued_for_deletion(), "never vanishes before the fade ends")
	w._physics_process(0.25)
	assert_true(w.is_queued_for_deletion())
	w.retire()
	assert_eq(Hazards.count(), n - 1, "a second retire changes nothing")


func test_retire_releases_the_cover_claim() -> void:
	var c := _container()
	var w := _wreck(c, P)
	var a := Node.new()
	var b := Node.new()
	add_child_autofree(a)
	add_child_autofree(b)
	assert_true(w.try_claim(a))
	assert_false(w.try_claim(b), "one cover user at a time")
	assert_true(w.hazard_info().is_claimed_by(a), "the claim lives on the HazardInfo")
	w.release(a)
	assert_true(w.try_claim(b))
	w.retire()
	assert_false(w.hazard_info().is_claimed(), "a retired wreck holds no claim")


func test_spawn_into_a_freed_container_leaves_no_orphan() -> void:
	for scene in [MEDIUM, DEBRIS]:
		var c := Node2D.new()
		add_child(c)
		var n := scene.instantiate() as Node2D
		n.spawn_into(c, P, 0.0)
		c.free()
		await get_tree().process_frame
		await get_tree().process_frame
		assert_false(is_instance_valid(n), "%s freed itself" % scene.resource_path)


func test_spawn_into_applies_the_transform_once_parented() -> void:
	var c := _container()
	c.position = Vector2(100, 100)
	var w := MEDIUM.instantiate() as Wreck
	w.spawn_into(c, P, 0.5)
	assert_false(w.is_inside_tree(), "deferred")
	assert_true(w.spawned, "a runtime wreck, for t11's alive cap")
	await get_tree().process_frame
	assert_true(w.is_inside_tree())
	assert_almost_eq(w.global_position, P, Vector2(0.01, 0.01))
	assert_almost_eq(w.rotation, 0.5, 0.0001)
	assert_false(_wreck(c, P).spawned, "a placed wreck is not")


func test_registered_while_alive_and_unregistered_after_free() -> void:
	var c := _container()
	var n := Hazards.count()
	var w := _wreck(c, P)
	var f := _debris(c, P + Vector2(200, 0))
	assert_eq(Hazards.count(), n + 2)
	var kinds := []
	for info in Hazards.around(P, 300.0):
		kinds.append((info as HazardInfo).kind)
	assert_has(kinds, &"wreck")
	assert_has(kinds, &"debris")
	w.queue_free()
	f.queue_free()
	await get_tree().process_frame
	assert_eq(Hazards.count(), n)


func test_every_wreck_scene_is_cover_and_never_an_enemy() -> void:
	var c := _container()
	var radii := {SMALL: 13.0, MEDIUM: 25.0, LARGE: 40.0, SATELLITE: 28.0, CARGO: 55.0, MODULE: 45.0}
	for scene in _ALL_WRECKS:
		var w := _wreck(c, P, scene)
		var path: String = scene.resource_path
		assert_false(w.is_in_group(&"enemies"), "%s: never an enemy" % path)
		assert_true(w.is_in_group(&"wrecks"), path)
		assert_true(w.blocks_line_of_sight(), path)
		assert_true(w.stops_enemy_rounds(), path)
		assert_eq(w.collision_layer, CollisionLayers.ENVIRONMENT, path)
		assert_eq(w.collision_mask, 0, path)
		var info := w.hazard_info()
		assert_eq(info.kind, &"wreck", path)
		assert_almost_eq(info.radius, radii[scene], 0.01, path)
		assert_almost_eq(info.avoid_weight, 0.6, 0.0001, path)
		assert_true(info.line_of_sight_blocker, path)
		assert_eq(info.pull_force, 0.0, path)
		var contact := w.get_node("ContactHitBox") as HitBox
		assert_eq(contact.collision_layer, CollisionLayers.HAZARD_CONTACT, path)
		assert_eq(contact.damage, 10, path)
		assert_false(contact.monitorable, "%s: disarmed at birth" % path)
		assert_true((contact.get_node("CollisionShape2D") as CollisionShape2D).disabled, "%s: shape off at birth (see Wreck._arm_contact)" % path)
		var hurt := w.get_node("HurtBox") as HurtBox
		assert_eq(hurt.collision_layer, CollisionLayers.ENEMY_HURTBOX, path)
		assert_eq(hurt.collision_mask, CollisionLayers.PLAYER_ROCKETS | CollisionLayers.PLAYER_HITBOX, path)
		var structure: bool = scene in [SATELLITE, CARGO, MODULE]
		assert_eq(_hp(w), 800 if structure else 200, path)
		assert_eq(w.lifetime, 0.0 if structure else 40.0, path)
		assert_eq(w.drift_velocity, Vector2.ZERO, path)


func test_wreck_scenes_scene_for() -> void:
	assert_eq(WreckScenes.scene_for(WreckScenes.Size.SMALL, false), SMALL)
	assert_eq(WreckScenes.scene_for(WreckScenes.Size.MEDIUM, false), MEDIUM)
	assert_eq(WreckScenes.scene_for(WreckScenes.Size.LARGE, false), LARGE)
	for size in [WreckScenes.Size.SMALL, WreckScenes.Size.MEDIUM, WreckScenes.Size.LARGE]:
		assert_eq(WreckScenes.scene_for(size, true), EXPLOSIVE, "an explosive wreck has one scene, whatever the size")
	assert_null(WreckScenes.scene_for(7, true))
	assert_null(WreckScenes.scene_for(7, false))


# --- debris fragments ---------------------------------------------------------------------------

func _hand_debris(at: Vector2) -> DebrisFragment:
	var c := _container()
	var f := _debris(c, at)
	f.set_physics_process(false)
	(f.get_node("ProjectileLifetime") as Node).set_physics_process(false)
	return f


func test_debris_scene_numbers() -> void:
	var f := _hand_debris(P)
	assert_false((f as Node) is PhysicsBody2D, "not a body: never solid, never a sight-line blocker")
	assert_false(f.is_in_group(&"enemies"))
	assert_eq(f.lifetime, 30.0)
	assert_eq(f.textures.size(), 6, "debris_1..6")
	var contact := f.get_node("ContactHitBox") as HitBox
	assert_eq(contact.collision_layer, CollisionLayers.HAZARD_CONTACT)
	assert_eq(contact.damage, 8)
	assert_eq(contact.damage_type, HitBox.DamageType.CONTACT)
	var info := f.hazard_info()
	assert_eq(info.kind, &"debris")
	assert_almost_eq(info.avoid_weight, 0.4, 0.0001)
	assert_false(info.line_of_sight_blocker)
	assert_between(f.speed, 20.0, 40.0)


func test_debris_decelerates_to_a_stop_and_spins_without_turning() -> void:
	var f := _hand_debris(P)
	f.speed = 30.0
	f.deceleration = 10.0
	f.spin = 1.0
	f.direction = Vector2.RIGHT
	for i in 60:
		f._physics_process(0.1)
	assert_eq(f.speed, 0.0, "stopped after 3 s")
	assert_almost_eq(f.global_position, P + Vector2(43.5, 0.0), Vector2(0.01, 0.01), "travelled along its direction only")
	assert_almost_eq(f.rotation, 6.0, 0.0001, "spun 1 rad/s")
	assert_eq(f.hazard_info().velocity, Vector2.ZERO)


func test_debris_contact_arms_only_once_clear_of_a_live_source() -> void:
	var f := _hand_debris(P)
	var src := Node2D.new()
	add_child_autofree(src)
	src.global_position = P
	f.source = src
	f.source_clear_radius = 50.0
	f.direction = Vector2.RIGHT
	f.speed = 30.0
	f._physics_process(1.0)
	assert_false(f.is_armed(), "30 px from its source: disarmed")
	f._physics_process(1.0)
	assert_true(f.is_armed(), "60 px: armed")
	var g := _hand_debris(P)
	var src2 := Node2D.new()
	add_child(src2)
	src2.global_position = P
	g.source = src2
	g.source_clear_radius = 50.0
	g.speed = 0.0
	g._physics_process(D)
	assert_false(g.is_armed())
	src2.free()
	g._physics_process(D)
	assert_true(g.is_armed(), "a freed source arms it at once")


func test_debris_frees_after_its_lifetime() -> void:
	_scale_clock()
	var c := _container()
	var f := _debris(c, P)
	f.lifetime = 0.5
	(f.get_node("ProjectileLifetime") as ProjectileLifetime).max_time = 0.5
	await _seconds(0.8)
	assert_false(is_instance_valid(f), "ended and freed itself")


func test_debris_configure_is_deterministic_for_one_seed() -> void:
	var picks := []
	for i in 2:
		var f := DEBRIS.instantiate() as DebrisFragment
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		f.configure(rng)
		picks.append([f.speed, f.direction, (f.get_node("Sprite2D") as Sprite2D).texture])
		f.free()
	assert_eq(picks[0], picks[1])
	assert_between(picks[0][0], 20.0, 40.0)


# --- revision 2 rows ----------------------------------------------------------------------------

func test_one_hit_costs_exactly_its_damage_above_100_hp() -> void:
	var c := _container()
	for pair in [[MEDIUM, 200], [SATELLITE, 800]]:
		var w := _wreck(c, P, pair[0])
		(w.get_node("HurtBox") as HurtBox).received_damage.emit(10)
		assert_eq(_hp(w), pair[1] - 10, "%s: Health is not clamped to its default 100" % pair[0].resource_path)


func test_a_retiring_wreck_takes_no_hits_and_never_blows() -> void:
	_scale_clock()
	var c := _container()
	var w := _wreck(c, P)
	var destroyed: Array = []
	w.destroyed.connect(func(at: Vector2) -> void: destroyed.append(at))
	await _frames(2)
	w.retire()
	await _frames(2)
	var b: Node2D = BULLET_SCENE.instantiate()
	c.add_child(b)
	b.global_position = P + Vector2(0, 60)
	b.expired.connect(b.queue_free)
	await _frames(6)
	assert_eq(_hp(w), 200, "unhittable while fading")
	assert_eq(destroyed, [], "and never destroyed")
	assert_true(is_instance_valid(b) and b.global_position.y < P.y - 25.0, "the bullet flew straight through")


func test_cover_stops_the_player_sniper_shot_and_takes_its_full_damage() -> void:
	_scale_clock()
	var c := _container()
	var w := _wreck(c, P)
	var b: Node2D = SNIPER_SHOT.instantiate()
	b.set(&"unlimited_pierce", true)
	c.add_child(b)
	b.global_position = P + Vector2(0, 150)
	await _frames(20)
	assert_true(_gone(b), "the piercing Sniper Shot ends on a wreck, as on an asteroid")
	assert_eq(_hp(w), 200 - 50, "and the wreck takes its full damage, whichever callback runs first")


func test_open_space_wreck_and_structure_outlive_the_30_s_cap_in_real_physics() -> void:
	_scale_clock()
	var h = _world("open_space")
	var w := _wreck(h.root, P)
	var s := _wreck(h.root, P + Vector2(300, 0), SATELLITE)
	await _frames(2)
	for node in [w, s]:
		var life := node.get_node("ProjectileLifetime") as ProjectileLifetime
		assert_eq(life.max_time, 0.0, "Open Space: the Assault cap is off")
		life._physics_process(31.0)
		assert_false(node.is_retiring(), "31 s of the cap: nothing")
		assert_true(node.is_inside_tree())
	await _frames(1)
	assert_true(is_instance_valid(w) and is_instance_valid(s), "both still in play")


func test_assault_cap_ends_in_a_fade_not_a_vanish() -> void:
	var h = _world("assault")
	var w := _wreck(h.root, P)
	w.set_physics_process(false)
	(w.get_node("ProjectileLifetime") as ProjectileLifetime).expire_now()
	assert_true(w.is_retiring(), "expired -> retire()")
	assert_false(w.is_queued_for_deletion(), "it fades first")


# --- explosive wrecks and reactor fields (plan §2.10) -------------------------------------------

## A hazard container in the tree (group `hazard_container`), as the level scenes have.
func _hazard_container(parent: Node) -> Node2D:
	var c := Node2D.new()
	c.add_to_group(Hazards.CONTAINER_GROUP)
	parent.add_child(c)
	return c


func _explosive(parent: Node, at: Vector2) -> Wreck:
	return _wreck(parent, at, EXPLOSIVE)


func _fields(c: Node) -> Array[HazardField]:
	var out: Array[HazardField] = []
	for n in c.get_children():
		if n is HazardField and not n.is_queued_for_deletion():
			out.append(n)
	return out


func test_the_explosive_scene_numbers() -> void:
	var c := _container()
	var w := _explosive(c, P)
	assert_true(w.explosive)
	assert_eq(_hp(w), 20)
	assert_true(w.is_in_group(&"wrecks"))
	assert_false(w.is_in_group(&"enemies"))
	assert_true(w.blocks_line_of_sight(), "still cover")
	var light := w.get_node("StateLight") as StateLight
	assert_eq(light.get_state(), StateLight.State.CHARGING, "the glow of live ordnance")
	assert_eq(w.fuse, 1.0)
	assert_eq(w.blast_radius, 110.0)
	assert_eq(w.blast_damage, 25)
	var plain := MEDIUM.instantiate() as Wreck
	assert_false(plain.explosive, "an ordinary wreck is inert")
	plain.free()


func test_the_reactor_field_scene_numbers() -> void:
	var f := load("res://assault/scenes/hazards/reactor_field/reactor_field.tscn").instantiate() as HazardField
	add_child_autofree(f)
	var info := f.hazard_info()
	assert_eq(info.kind, &"reactor_field")
	assert_eq(info.radius, 90.0)
	assert_eq(f.damage_radius, 90.0)
	assert_eq(f.stress_damage, 4)
	assert_eq(f.stress_period, 0.5)
	assert_eq(f.duration, 2.0)
	assert_eq(info.avoid_weight, 1.0)
	assert_eq(info.pull_force, 0.0)
	assert_eq(info.tangential_force, 0.0)
	assert_eq(info.movement_penalty, 0.0)


## Shoots the explosive wreck to 0 HP with a player and a swarm drone [param gap] px (centre to centre) from it.
## Returns [player hits, enemy hits].
func _blast_with_gap(mode: String, gap: float) -> Array:
	var h = _world(mode)
	var c := _hazard_container(h.root)
	var player_hits: Array[int] = []
	var enemy_hits: Array[int] = []
	_player(h.root, mode, P + Vector2(gap, 0), player_hits)
	_make_swarm(h.root, P + Vector2(0, gap), enemy_hits)
	var w := _explosive(c, P)
	(w.get_node("HurtBox") as HurtBox).received_damage.emit(20)
	await get_tree().process_frame
	await get_tree().process_frame
	return [player_hits, enemy_hits]


func test_a_wreck_shot_to_zero_hurts_the_player_and_an_enemy_at_110_px(mode: String = use_parameters(_MODES)) -> void:
	var r: Array = await _blast_with_gap(mode, 110.0)
	assert_eq(r[0], [25] as Array[int], "%s: the player's centre is in the blast" % mode)
	assert_eq(r[1], [25] as Array[int], "%s: and so is the enemy's" % mode)


func test_neither_is_hurt_at_111_px(mode: String = use_parameters(_MODES)) -> void:
	var r: Array = await _blast_with_gap(mode, 111.0)
	assert_eq(r[0], [] as Array[int], "%s: just outside, the player is spared" % mode)
	assert_eq(r[1], [] as Array[int], "%s: and so is the enemy" % mode)


func test_the_blast_deflects_off_a_plated_ram() -> void:
	var h = _world("open_space")
	var c := _hazard_container(h.root)
	var ram := RAM_SCENE.instantiate() as RamCorvette
	ram.global_position = P + Vector2(50, 0)
	h.root.add_child(ram)
	ram.set_physics_process(false)
	var hp := ram.health.current_health
	var w := _explosive(c, P)
	(w.get_node("HurtBox") as HurtBox).received_damage.emit(20)
	assert_eq(ram.health.current_health, hp, "the armour deflects the blast")
	await get_tree().process_frame
	await get_tree().process_frame


func test_the_blast_spares_other_wrecks() -> void:
	var h = _world("open_space")
	var c := _hazard_container(h.root)
	var other := _wreck(c, P + Vector2(40, 0), MEDIUM)
	var w := _explosive(c, P)
	(w.get_node("HurtBox") as HurtBox).received_damage.emit(20)
	assert_eq(_hp(other), 200, "wrecks do not chain")
	await get_tree().process_frame
	await get_tree().process_frame


func test_detonating_twice_in_one_frame_hurts_once(mode: String = use_parameters(_MODES)) -> void:
	var h = _world(mode)
	var c := _hazard_container(h.root)
	var received: Array[int] = []
	_player(h.root, mode, P + Vector2(50, 0), received)
	var w := _explosive(c, P)
	var n := [0]
	w.detonated.connect(func(_at: Vector2) -> void: n[0] += 1)
	w._detonate()
	w._detonate()
	(w.get_node("HurtBox") as HurtBox).received_damage.emit(20)
	assert_eq(received, [25] as Array[int], "%s: one blast" % mode)
	assert_eq(n[0], 1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_fields(c).size(), 1, "and one reactor field")


## An armed explosive wreck at P with nothing on it. Returns [wreck, detonation counter, harness, container].
func _touch_setup() -> Array:
	_scale_clock()
	var h = _world("open_space")
	var c := _hazard_container(h.root)
	var w := _explosive(c, P)
	var n := [0]
	w.detonated.connect(func(_at: Vector2) -> void: n[0] += 1)
	await _seconds(0.7)
	assert_true(w.is_armed())
	return [w, n, h, c]


func test_a_touch_detonates_after_the_fuse_and_not_before() -> void:
	var r: Array = await _touch_setup()
	var w: Wreck = r[0]
	var n: Array = r[1]
	var received: Array[int] = []
	_player(r[2].root, "open_space", P, received)
	await _seconds(0.9)
	assert_eq(n[0], 0, "0.9 s into the fuse: not yet")
	assert_true(w.is_fusing())
	await _seconds(0.3)
	assert_eq(n[0], 1, "1.2 s in: it went off")
	assert_true(received.has(25), "and the player standing on it took the blast")


func test_no_touch_no_fuse() -> void:
	var r: Array = await _touch_setup()
	await _seconds(1.2)
	assert_false((r[0] as Wreck).is_fusing())
	assert_eq(r[1][0], 0)


func test_a_wreck_that_retires_does_not_blow_up_on_touch() -> void:
	var r: Array = await _touch_setup()
	(r[0] as Wreck).retire(0.2)
	_player(r[2].root, "open_space", P, [] as Array[int])
	await _seconds(1.2)
	assert_eq(r[1][0], 0)


func test_a_detonation_leaves_one_reactor_field_that_stresses_for_two_seconds_and_frees() -> void:
	var h = _world("open_space")
	var c := _hazard_container(h.root)
	var received: Array[int] = []
	_player(h.root, "open_space", P + Vector2(60, 0), received)
	var w := _explosive(c, P)
	w._detonate()
	await get_tree().process_frame
	await get_tree().process_frame
	var fields := _fields(c)
	assert_eq(fields.size(), 1, "exactly one reactor field")
	var f := fields[0]
	assert_eq(f.kind, &"reactor_field")
	assert_eq(f.global_position, P)
	assert_true(_gone(w))
	received.clear()
	f.set_physics_process(false)
	var ticks := 0
	while is_instance_valid(f) and not f.is_queued_for_deletion() and ticks < 200:
		f._physics_process(D)
		ticks += 1
	assert_between(ticks, 119, 121, "it lives 2.0 s")
	assert_between(received.size(), 3, 4, "a pulse every 0.5 s")
	for amount in received:
		assert_eq(amount, 4)
	await get_tree().process_frame
	assert_false(is_instance_valid(f), "and frees")


func test_no_container_means_no_reactor_field() -> void:
	var h = _world("open_space")
	var w := _explosive(h.root, P)
	w._detonate()
	await get_tree().process_frame
	await get_tree().process_frame
	for n in h.root.get_children():
		assert_false(n is HazardField, "nothing to put it in, so nothing spawned")
	assert_true(_gone(w))


func test_a_real_bullet_kills_an_explosive_wreck_and_leaves_exactly_one_reactor_field() -> void:
	_scale_clock()
	var h = _world("open_space")
	var c := _hazard_container(h.root)
	var w := _explosive(c, Vector2(400, 300))
	var b: Node2D = BULLET_SCENE.instantiate()
	h.root.add_child(b)
	b.global_position = Vector2(400, 420)
	b.expired.connect(b.queue_free)
	await _frames(40)
	assert_true(_gone(w), "the shot killed it")
	assert_eq(_fields(c).size(), 1, "and exactly one reactor field appeared, with no engine error")
