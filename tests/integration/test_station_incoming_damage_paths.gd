## Closes the last of `test_space_station.gd`'s documented collision-layer coverage gap.
##
## NOT characterization except where a test says `CHARACTERIZED` in so many words — the station is
## new code, so these assert intent.
##
## `test_space_station.gd` drives most of its damage by emitting `HurtBox.received_damage`
## directly, which proves nothing about the layers; its last two tests closed that for the
## **bullet** (64) path with a real `bullet.tscn` and real physics. Three incoming damage paths
## were still verified only by reading the scene, and each has its own way of failing silently:
##
## | Path | Bit under test | What a wrong value costs |
## |---|---|---|
## | player rockets | `HurtBox.collision_mask & 32` | homing and warhead missiles fly through the boss |
## | asteroid contact | `HurtBox.collision_mask & 1024` | the hull is immune to the debris the level throws at it |
## | player mining laser | `SpaceStation.collision_layer == 0` | the hull blocks the beam AND shields everything behind it |
##
## The mask bits come from `base_enemy.gd:25` (`97 | 1024`, code) and `space_station.tscn:75-76`
## (the same value, authored). The laser row is the odd one out: `BeamBehavior` finds its targets
## by group and geometry, not by layer, so what is under test there is the *root body's* layer —
## `beam_behavior.gd` rays bodies with `_RAY_BLOCK_MASK = 1 | 1024`, and a station on the default
## layer 1 truncates the beam at its own hull edge and is then skipped as the blocker.
##
## Lives in integration/ because it instances real scenes and steps the physics server
## (`tests/README.md`: unit/ is "no scene loading").
extends GutTest

const STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const WARHEAD_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
const ASTEROID_SCENE: PackedScene = preload("res://assault/scenes/hazards/big_asteroid/big_asteroid.tscn")
const LASER_MODE: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/mining_laser.tres")

## Damage each source deals, duplicated here on purpose rather than read back off the instance:
## the point is to fail if one of them changes, so it must not track it.
const HOMING_DAMAGE: int = 100
const WARHEAD_DAMAGE: int = 50
const ASTEROID_CONTACT_DAMAGE: int = 40

## Lower-right turret, station-local (76, 76), 26 px radius — the same lane
## `test_space_station.gd` fires its bullet up.
const _LANE_TURRET_INDEX: int = 3

var _station: SpaceStation

## Stands in for `WaveManager.enemy_container`, for the same reason `test_space_station.gd` has
## one: `bullet_pool.gd:47` resolves its container as `get_parent().get_parent()`.
var _container: Node2D


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_station = STATION_SCENE.instantiate() as SpaceStation
	_container.add_child(_station)


func _turrets() -> Array:
	return _station.get_node("Turrets").get_children()


func _break_armor() -> void:
	for t in _turrets():
		var turret := t as StationTurret
		turret.hurt_box.received_damage.emit(turret.health.max_health)
	assert_false(_station.is_armored(), "precondition: the armour is gone")


## Parented to the container rather than to the station, so no hull transform — including the
## phase-2 rotation — moves the projectile under it, and so `add_child_autofree(_container)` still
## owns whatever survives the test.
func _spawn(scene: PackedScene, at: Vector2) -> Node2D:
	var n := scene.instantiate() as Node2D
	_container.add_child(n)
	n.global_position = at
	return n


# ── Rockets: HurtBox.collision_mask & 32 ──────────────────────────────────────
#
# `ENEMY.md` -> "Collision layers" warns that copying the gunship scene's raw `collision_mask = 65`
# would drop bit 6 and let both player missiles pass through the boss. Nothing checked it. These do:
# a real missile, real physics, no `received_damage` emit anywhere.
#
# Both missile scenes put their `HitBox` on layer 32 with `damage_type = 1` (ROCKET) —
# `homing_missile.tscn:57-63`, `warhead_missile.tscn:59-64` — so each is covered on its own rather
# than one standing in for the other.

## Rocket damage reaches the core once the armour is gone. Homing missiles fly forward when
## `locked_target` is null (`homing_missile.gd:27-30`), so nothing else has to be set up.
##
## 16 frames at 500 px/s = 133 px. The capsule's 9 px nose reaches the core's bottom edge
## (y = +120) at frame ~9, so the budget is comfortably past contact and the missile is freed on
## contact, which is what keeps it from ever reaching the far side.
func test_a_real_homing_missile_damages_the_unarmored_core_through_the_collision_layers() -> void:
	_break_armor()
	var full: int = _station.health.current_health

	var missile := _spawn(HOMING_SCENE, Vector2(0.0, 200.0))
	await wait_physics_frames(16)

	assert_eq(
		_station.health.current_health,
		full - HOMING_DAMAGE,
		"a homing missile must be found through HurtBox.collision_mask bit 32 — without it the "
		+ "missile flies through the boss and the player's rockets are cosmetic"
	)
	assert_false(is_instance_valid(missile), "the missile detonates on the hurtbox it hits")


## The warhead is the second rocket source and carries its own damage value.
##
## 12 frames at 640 px/s = 128 px, contact at frame ~7. It stays on the x = 0 lane throughout,
## which matters: `warhead_missile.tscn:54-56` wires a `VisibleOnScreenNotifier2D` to
## `queue_free`, and a test that let it leave the viewport would look like a missed hit.
func test_a_real_warhead_missile_damages_the_unarmored_core_through_the_collision_layers() -> void:
	_break_armor()
	var full: int = _station.health.current_health

	var missile := _spawn(WARHEAD_SCENE, Vector2(0.0, 200.0))
	await wait_physics_frames(12)

	assert_eq(
		_station.health.current_health,
		full - WARHEAD_DAMAGE,
		"a warhead missile must be found through HurtBox.collision_mask bit 32"
	)
	assert_false(is_instance_valid(missile), "the warhead detonates on the hurtbox it hits")


## The armoured half: the core is *hittable* while armoured, so the missile must reach the HurtBox
## through the layers and be refused there, not fail to arrive.
##
## Fired on the centre lane, which has no turret behind it: the point of this test is the
## deflection itself, not what (if anything) the rocket goes on to hit.
func test_a_real_rocket_is_deflected_by_the_armored_core_rather_than_missing_it() -> void:
	watch_signals(_station)
	var full: int = _station.health.current_health

	var missile := _spawn(HOMING_SCENE, Vector2(0.0, 200.0))
	await wait_physics_frames(16)

	assert_signal_emitted(
		_station,
		"armor_deflected",
		"the armoured core must still register the rocket — a deflect proves the layer chain "
		+ "worked; silence cannot tell a wrong mask from working armour"
	)
	assert_eq(_station.health.current_health, full, "the armoured core loses no health to a rocket")
	assert_true(
		is_instance_valid(missile),
		"a deflected hit must not consume the rocket, exactly like a deflected hit does not "
		+ "consume a bullet (bullet.gd::_hit_is_deflected) — otherwise it can never reach a "
		+ "turret behind the core"
	)


## Fixed by `rockets-cannot-damage-the-space-station-s-turrets-they-deton`
## (`code-health-backlog`): a rocket now survives a **deflected** hit exactly like a bullet does
## (`bullet.gd::_hit_is_deflected`) — `homing_missile.gd` and `warhead_missile.gd` duck-type
## `is_armored()` on the hurtbox's parent before consuming themselves, so a deflection no longer
## detonates the rocket.
##
## The core's HurtBox spans the whole 240x240 hull and the turrets sit *inside* it at (+-76, +-76),
## so a rocket fired up a turret lane reaches the core rect (y = +120) a couple of frames before
## the turret rim (y = +102). It must now be deflected there (0 damage, `armor_deflected` fires)
## and keep flying, then detonate on the live turret behind it for full damage.
func test_a_rocket_up_a_turret_lane_survives_the_armored_core_and_damages_the_turret_behind_it() -> void:
	watch_signals(_station)
	var turret := _turrets()[_LANE_TURRET_INDEX] as StationTurret
	var full_turret: int = turret.health.current_health
	var full_core: int = _station.health.current_health

	var missile := _spawn(HOMING_SCENE, Vector2(76.0, 200.0))
	await wait_physics_frames(16)

	assert_signal_emitted(
		_station,
		"armor_deflected",
		"the rocket must still be deflected by the armoured core it crosses on the way to the "
		+ "turret — a deflect proves it actually reached the core rather than missing it"
	)
	assert_eq(
		_station.health.current_health,
		full_core,
		"the armoured core must not lose health to a rocket that only crossed it"
	)
	assert_eq(
		turret.health.current_health,
		full_turret - HOMING_DAMAGE,
		"the turret behind the armoured core must take the rocket's full damage, exactly as a "
		+ "bullet on this same lane does (test_space_station.gd)"
	)
	assert_false(is_instance_valid(missile), "the missile detonates on the live turret it reaches")


# ── Asteroid contact: HurtBox.collision_mask & 1024 ───────────────────────────
#
# `big_asteroid.tscn:44-49` puts its `ContactHitBox` on layer 1024 with `collision_mask = 0`, so
# the asteroid detects nothing itself — the overlap is found by the station's HurtBox alone, and
# bit 1024 is the only thing that makes it happen. Level 1 throws asteroids across the station's
# lane, so this is a live path, not a hypothetical one.

## Placed at station-local (0, 60): inside the 240x240 core rect, and its 28 px radius stays clear
## of the turrets' x-extent of [50, 102], so exactly one hurtbox is involved.
func test_a_real_asteroid_damages_the_unarmored_core_through_the_collision_layers() -> void:
	_break_armor()
	var full: int = _station.health.current_health

	_spawn(ASTEROID_SCENE, Vector2(0.0, 60.0))
	await wait_physics_frames(4)

	assert_eq(
		_station.health.current_health,
		full - ASTEROID_CONTACT_DAMAGE,
		"asteroid contact must be found through HurtBox.collision_mask bit 1024 — without it "
		+ "the boss is quietly immune to the debris the level flies at it"
	)


func test_a_real_asteroid_is_deflected_by_the_armored_core_rather_than_missing_it() -> void:
	watch_signals(_station)
	var full: int = _station.health.current_health

	_spawn(ASTEROID_SCENE, Vector2(0.0, 60.0))
	await wait_physics_frames(4)

	assert_signal_emitted(_station, "armor_deflected",
		"the armoured core must register the asteroid through the layers")
	assert_eq(_station.health.current_health, full,
		"the armoured core loses no health to asteroid contact")


# ── Incoming mining laser: SpaceStation.collision_layer == 0 ──────────────────
#
# The one path here that is not about the HurtBox mask. `BeamBehavior.tick()` casts a ray against
# *bodies* on `_RAY_BLOCK_MASK = 1 | 1024` (`beam_behavior.gd:8`), truncates the beam at the first
# blocker, skips that blocker as a target (`:90`) and culls every target past the truncation
# (`:94`). `space_station.tscn:62-64` therefore sets the root body to layer 0 **and mask 0** so it
# is not a blocker at all — a fact `ENEMY.md` states and nothing checked.
#
# `test_laser_ray_hit_mask.gd` covers the station's *outgoing* beams. This is the incoming one.

## Drives `BeamBehavior.tick()` from a real `_physics_process`, which is the only place
## `direct_space_state` may be queried. It doubles as the behaviour's `state` (`add_child`,
## `get("actor")`) and as the actor itself (`rotation`, `get_world_2d()`, `get_tree()`).
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


## Ray length in `beam_behavior.gd:6`. Duplicated deliberately, same reason as the damage values.
const RAY_LENGTH: float = 1200.0
## Distance below the station the beam is fired from.
const BEAM_STANDOFF: float = 300.0


func _fire_beam_from_below() -> BeamDriver:
	var d := BeamDriver.new()
	d.behavior = BeamBehavior.new()
	d.mode = LASER_MODE
	var muzzle := Marker2D.new()
	d.add_child(muzzle)
	d.muzzles = [muzzle]
	d.actor = d
	_container.add_child(d)
	d.global_position = Vector2(0.0, BEAM_STANDOFF)
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


## 40 frames, not 4. The endpoint is drawn on the very first tick, but the *damage* is not:
## `beam_dps = 12` over a 1/60 s frame is 0.2, and `_accumulate_and_apply` only forwards whole
## numbers, so the first point of damage — and therefore the first `armor_deflected` — lands
## around frame 30. A shorter budget passes the endpoint assertion and silently drops the one
## that proves the beam found the core at all; that is how this test first ran.
func test_the_station_hull_does_not_block_the_players_mining_laser() -> void:
	watch_signals(_station)
	var d := _fire_beam_from_below()
	await wait_physics_frames(40)

	assert_gt(d.frames, 0, "precondition: the beam actually ticked")
	assert_almost_eq(
		_beam_endpoint(d).y,
		BEAM_STANDOFF - RAY_LENGTH,
		1.0,
		"the beam must run its full length through the station — a hull that blocks it also "
		+ "shields every enemy behind it, and the player sees the laser stop in mid-air"
	)
	assert_signal_emitted(
		_station,
		"armor_deflected",
		"the armoured core must be burnt by the beam, not skipped as its blocker"
	)
	d.behavior.release(d)


## The other half: with the armour gone the beam actually takes the core down. `beam_dps = 12`
## against a 1/60 s frame is 0.2 per tick, and `_accumulate_and_apply` only forwards whole
## numbers, so this needs ~30 frames before the first point of damage lands — hence 40 rather
## than the 4 above.
func test_the_mining_laser_burns_the_unarmored_core() -> void:
	_break_armor()
	var full: int = _station.health.current_health

	var d := _fire_beam_from_below()
	await wait_physics_frames(40)

	assert_lt(
		_station.health.current_health,
		full,
		"an unarmoured core must lose health to the mining laser"
	)
	d.behavior.release(d)


## BOUNDARY, and the reason the two above are not vacuous: put the station on the default body
## layer 1 and the beam stops dead at the hull and burns nothing. This is the failure the layer 0
## line in `space_station.tscn` prevents, applied to a live instance — the same shape as
## `test_enemy_hurtbox_geometry.gd`'s `test_the_88x240_proposal_fails_this_sweep`.
func test_a_station_on_the_default_body_layer_would_block_its_own_fight() -> void:
	watch_signals(_station)
	_station.collision_layer = 1

	var d := _fire_beam_from_below()
	await wait_physics_frames(4)

	var endpoint_y: float = _beam_endpoint(d).y
	assert_gt(
		endpoint_y,
		BEAM_STANDOFF - RAY_LENGTH + 1.0,
		"a layer-1 station truncates the beam at its own hull instead of letting it pass"
	)
	assert_almost_eq(endpoint_y, 120.0, 2.0, "truncated at the hull's near edge, y = +120")
	assert_signal_not_emitted(
		_station,
		"armor_deflected",
		"and it is then skipped as its own blocker, so the beam cannot hurt it either"
	)
