## The Space Fortress's incoming damage paths through the real collision layers: player rockets, asteroid contact and the player's
## mining laser (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.11; re-pointed from the retired space station in Phase 11 t11).
##
## Intent tests. `test_space_fortress.gd` proves the BULLET (64) path with real bullets; three more paths reach the boss, each with its own
## way of failing silently:
##
## | Path | What is under test | What a wrong value costs |
## |---|---|---|
## | player rockets | `HurtBox.collision_mask & 32` on the hull and the parts | homing and warhead missiles fly through the boss |
## | asteroid contact | `HurtBox.collision_mask & 1024` on the hull and the parts | the boss is immune to the debris the level throws at it |
## | player mining laser | root `collision_layer == 0` and `is_laser_blocking()` false | the hull blocks the beam AND shields every part behind it |
##
## The hull is armour (`deflects_hit()` / `is_armored()` true): a rocket or an asteroid that reaches it is refused (`armor_deflected`) and a
## rocket flies on, so it can reach the battery behind the hull edge. A battery is normally inside its sector's shield bubble, so the rows
## that must reach one first `destroy()` the south generator (its bubbles detach in the same call, `ShieldSector`).
##
## The laser row has TWO guards to pin, unlike the station it replaces: `BeamBehavior` rays bodies on `1 | 1024` and stops at the first one
## unless it answers `is_laser_blocking()` false. The fortress sits on layer 0 AND answers false, so a layer-1 fortress still lets the beam
## through (row b), and the boundary is a plain layer-1 body that does not answer (row c): without it rows a and b would be vacuous.
##
## Real physics at the 8x clock (tests/README.md -> Gate time, rule 1), both harnesses, the fortress's own physics off (no brain, no
## mover), so every shot meets the authored geometry exactly. Frame: local +x right, +y down; the fortress spawns at rotation 0.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const FORTRESS_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_fortress/space_fortress.tscn")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const WARHEAD_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
const ASTEROID_SCENE: PackedScene = preload("res://assault/scenes/hazards/big_asteroid/big_asteroid.tscn")
const LASER_MODE: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/mining_laser.tres")

const MODES := ["open_space", "assault"]
const SPAWN := Vector2(640.0, 360.0)
const HULL_RADIUS := 176.0

## Damage each source deals, duplicated here on purpose rather than read back off the instance: the point is to fail if one of them
## changes, so it must not track it.
const HOMING_DAMAGE: int = 100
const WARHEAD_DAMAGE: int = 50
const ASTEROID_CONTACT_DAMAGE: int = 40

## Ray length in `beam_behavior.gd`. Duplicated deliberately, same reason as the damage values.
const RAY_LENGTH: float = 1200.0
## Distance below the fortress centre the beam is fired from.
const BEAM_STANDOFF: float = 300.0

const _SPEEDUP := 8

var _roots: Array[Node] = []
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_each() -> void:
	_scale_clock()


func after_each() -> void:
	_restore_clock()
	_roots.clear()


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


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

## A fresh harness world; an earlier world of this test leaves the tree first (its player would still be in group `player`).
func _world(mode: String):
	for old in _roots:
		if is_instance_valid(old) and old.is_inside_tree():
			old.get_parent().remove_child(old)
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	_roots.append(h.root)
	h.player.global_position = Vector2(640.0, 1400.0)
	return h


func _spawn_fortress(h) -> SpaceFortress:
	var f := FORTRESS_SCENE.instantiate() as SpaceFortress
	f.global_position = SPAWN
	h.root.add_child(f)
	f.set_physics_process(false)
	return f


## A projectile or hazard parented to the world root, never to the fortress, so no hull transform moves it.
func _spawn(h, scene: PackedScene, local: Vector2) -> Node2D:
	var n := scene.instantiate() as Node2D
	h.root.add_child(n)
	n.global_position = SPAWN + local
	return n


## Counts emissions of a one-int signal carrying exactly [param amount].
func _count_damage(sig: Signal, amount: int) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(d: int) -> void:
		if d == amount:
			n[0] += 1)
	return n


func _count(sig: Signal) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(_a = null) -> void: n[0] += 1)
	return n


func _hp(f: SpaceFortress, id: StringName) -> int:
	return f.part(id).health.current_health


## Every part's current HP, by id.
func _all_hp(f: SpaceFortress) -> Dictionary:
	var out := {}
	for p in f.modular_hull().modules():
		out[p.module_id] = p.health.current_health
	return out


# ── Rockets: HurtBox.collision_mask & 32 ─────────────────────────────────────────────────────────

## A homing rocket locked on the fortress steers at `homing_point()` (the nearest live vulnerable part: the spread battery, 201 px from
## the launch point, against the sweep battery's 304), crosses the hull edge (y +145.5 on this lane) where the armour refuses it without
## consuming it, and detonates on the battery for its full damage. 40 frames at 500 px/s = 333 px; contact at ~22.
func test_a_homing_rocket_crosses_the_armoured_hull_and_hits_the_battery_it_steers_at(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn_fortress(h)
	f.part(&"shield_south").destroy()
	var refused := _count_damage(f.armor_deflected, HOMING_DAMAGE)
	var battery_before := _hp(f, &"battery_spread")
	assert_eq(f.homing_point(SPAWN + Vector2(99.0, 300.0)), f.part(&"battery_spread").homing_point(),
		"%s: precondition: the rocket's aim point is the spread battery" % mode)

	var missile := _spawn(h, HOMING_SCENE, Vector2(99.0, 300.0))
	missile.set(&"locked_target", f)
	await wait_physics_frames(40)

	assert_gte(refused[0], 1, "%s: the hull refused the rocket through bit 32 (armor_deflected %d)" % [mode, HOMING_DAMAGE])
	assert_eq(_hp(f, &"battery_spread"), battery_before - HOMING_DAMAGE,
		"%s: the battery behind the hull edge takes the rocket's full damage" % mode)
	assert_eq(f.health.current_health, f.health.max_health, "%s: the armoured hull's bar never moves" % mode)
	assert_false(is_instance_valid(missile), "%s: the rocket detonates on the battery, not on the hull" % mode)


## The warhead is the second rocket source and carries its own damage value. Straight up the x 99 lane: 30 frames at 640 px/s = 320 px,
## contact at ~17.
func test_a_warhead_crosses_the_armoured_hull_and_hits_the_battery(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn_fortress(h)
	f.part(&"shield_south").destroy()
	var refused := _count_damage(f.armor_deflected, WARHEAD_DAMAGE)
	var battery_before := _hp(f, &"battery_spread")

	var missile := _spawn(h, WARHEAD_SCENE, Vector2(99.0, 300.0))
	await wait_physics_frames(30)

	assert_gte(refused[0], 1, "%s: the hull refused the warhead through bit 32" % mode)
	assert_eq(_hp(f, &"battery_spread"), battery_before - WARHEAD_DAMAGE, "%s: the battery takes the warhead's damage" % mode)
	assert_eq(f.health.current_health, f.health.max_health, "%s: the armoured hull's bar never moves" % mode)
	assert_false(is_instance_valid(missile), "%s: the warhead detonates on the battery" % mode)


# ── Asteroid contact: HurtBox.collision_mask & 1024 ──────────────────────────────────────────────
#
# `big_asteroid.tscn` puts its `ContactHitBox` on layer 1024 with `collision_mask = 0`, so the asteroid detects nothing itself: the
# overlap is found by the boss's hurtboxes alone, and bit 1024 is the only thing that makes it happen.

## Local (60, -50), radius 28: on the hull and clear of every part (core 78 > 72, north generator 92 > 54, missiles battery 62.6 > 50).
func test_a_real_asteroid_is_refused_by_the_armoured_hull_rather_than_missing_it(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn_fortress(h)
	var refused := _count_damage(f.armor_deflected, ASTEROID_CONTACT_DAMAGE)
	var parts_before := _all_hp(f)

	_spawn(h, ASTEROID_SCENE, Vector2(60.0, -50.0))
	await wait_physics_frames(4)

	assert_gte(refused[0], 1, "%s: the hull registered the asteroid through bit 1024 and refused it" % mode)
	assert_eq(f.health.current_health, f.health.max_health, "%s: the armoured hull loses nothing to asteroid contact" % mode)
	assert_eq(_all_hp(f), parts_before, "%s: and no part was touched" % mode)


## Over the sweep battery (150, 0) with its sector's generator dead: the part's own mask (1120) carries bit 1024. The asteroid also
## overlaps the hull edge (150 + 28 > 176), so a hull refusal may happen too and is not asserted either way.
func test_a_real_asteroid_damages_a_bare_battery_through_the_collision_layers(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn_fortress(h)
	f.part(&"shield_south").destroy()
	var battery_before := _hp(f, &"battery_sweep")

	_spawn(h, ASTEROID_SCENE, Vector2(150.0, 0.0))
	await wait_physics_frames(4)

	assert_eq(_hp(f, &"battery_sweep"), battery_before - ASTEROID_CONTACT_DAMAGE,
		"%s: asteroid contact reaches a bare battery through bit 1024 of the part mask" % mode)
	assert_eq(f.health.current_health, f.health.max_health, "%s: the hull bar never moves" % mode)


# ── Incoming mining laser: the root body's layer and is_laser_blocking() ─────────────────────────

## Drives `BeamBehavior.tick()` from a real `_physics_process`, the only place `direct_space_state` may be queried. It doubles as the
## behaviour's `state` and as the actor itself.
class BeamDriver extends Node2D:
	var actor: Node2D
	var behavior: BeamBehavior
	var mode: WeaponModeResource
	var muzzles: Array[Marker2D] = []
	var frames: int = 0

	func _physics_process(delta: float) -> void:
		if behavior == null:
			return
		behavior.tick(self, mode, muzzles, delta)
		frames += 1


## A beam fired straight up from [param local] (relative to `SPAWN`).
func _fire_beam_up(h, local: Vector2) -> BeamDriver:
	var d := BeamDriver.new()
	d.behavior = BeamBehavior.new()
	d.mode = LASER_MODE
	var muzzle := Marker2D.new()
	d.add_child(muzzle)
	d.muzzles = [muzzle]
	d.actor = d
	h.root.add_child(d)
	d.global_position = SPAWN + local
	return d


## The far endpoint the behaviour last drew to, in world space.
func _beam_endpoint(d: BeamDriver) -> Vector2:
	for child in d.get_children():
		var beam := child as PiercingBeam
		if beam != null:
			var line := beam.get_node("Line2D") as Line2D
			if line.points.size() >= 2:
				return line.points[1]
	return Vector2.INF


func _stop_beam(d: BeamDriver) -> void:
	d.behavior.release(d)
	d.behavior = null


## (a) 60 frames, not 4: the endpoint is drawn on the first tick, but `beam_dps` 12 over a 1/60 s frame is 0.2 a tick and only whole
## points are forwarded, so the first refusal on a locked part lands around frame 30.
func test_the_fortress_does_not_block_the_players_mining_laser(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn_fortress(h)
	var pinged := _count(f.part(&"shield_south").deflected)
	var d := _fire_beam_up(h, Vector2(0.0, BEAM_STANDOFF))
	await wait_physics_frames(60)

	assert_gt(d.frames, 0, "%s: precondition: the beam actually ticked" % mode)
	assert_almost_eq(_beam_endpoint(d).y, SPAWN.y + BEAM_STANDOFF - RAY_LENGTH, 1.0,
		"%s: the beam runs its full length through the fortress — a blocking hull would shield every part behind it" % mode)
	assert_gt(pinged[0], 0, "%s: the locked south generator on the line is burnt (and refuses), not skipped" % mode)
	_stop_beam(d)


func test_the_mining_laser_burns_a_bare_battery_inside_the_hull(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn_fortress(h)
	f.part(&"shield_south").destroy()
	var before := _hp(f, &"battery_spread")
	var d := _fire_beam_up(h, Vector2(99.0, BEAM_STANDOFF))
	await wait_physics_frames(60)

	assert_lt(_hp(f, &"battery_spread"), before, "%s: the beam crosses the hull and burns the battery on its line" % mode)
	assert_eq(f.health.current_health, f.health.max_health, "%s: the hull bar never moves" % mode)
	_stop_beam(d)


## (b) The second guard: even on body layer 1, the fortress answers `is_laser_blocking()` false, so the ray passes it.
func test_a_layer_1_fortress_still_lets_the_beam_through(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn_fortress(h)
	f.collision_layer = 1
	var pinged := _count(f.part(&"shield_south").deflected)
	var d := _fire_beam_up(h, Vector2(0.0, BEAM_STANDOFF))
	await wait_physics_frames(60)

	assert_almost_eq(_beam_endpoint(d).y, SPAWN.y + BEAM_STANDOFF - RAY_LENGTH, 1.0,
		"%s: is_laser_blocking() false keeps a layer-1 fortress from truncating the beam" % mode)
	assert_gt(pinged[0], 0, "%s: and the part on the line is still burnt" % mode)
	_stop_beam(d)


## (c) BOUNDARY, and the reason (a) and (b) are not vacuous: a plain layer-1 body of the hull's size, which does not answer
## `is_laser_blocking()`, stops the beam dead at its near edge.
func test_a_plain_layer_1_hull_sized_body_would_block_the_beam(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HULL_RADIUS
	cs.shape = circle
	body.add_child(cs)
	h.root.add_child(body)
	body.global_position = SPAWN
	assert_eq(body.collision_layer, 1, "precondition: the default body layer")

	var d := _fire_beam_up(h, Vector2(0.0, BEAM_STANDOFF))
	await wait_physics_frames(4)

	assert_almost_eq(_beam_endpoint(d).y, SPAWN.y + HULL_RADIUS, 2.0,
		"%s: a layer-1 body truncates the beam at its near edge, y +176" % mode)
	_stop_beam(d)
