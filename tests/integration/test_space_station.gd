## Integration test for the space-station mini-boss entity (EPIC sub-item 1).
##
## Unlike most of this suite these are NOT characterization tests — the entity is new, so they
## assert intended behaviour rather than pinning existing quirks.
##
## The rule under test: the station core refuses all damage while any turret is alive, and
## becomes damageable the moment the last one dies. The core stays *hittable* throughout — it
## emits `armor_deflected` and flashes — because two shipped systems drive damage straight into
## `HurtBox.received_damage` without any physics (`plasma_nova_module.gd:39-41` and
## `beam_behavior.gd:99-102`), and a "disable the hurtbox" implementation would leak both.
##
## Lives in integration/ rather than unit/ because it instances a real scene
## (`tests/README.md`: unit/ is "no scene loading").
##
## COVERAGE GAP, now partly closed: most of the tests below drive damage by emitting
## `HurtBox.received_damage` directly, so on their own they do NOT prove the collision layers are
## right — a core whose HurtBox has a `collision_layer` no bullet could ever hit passes all nine of
## them. The two tests at the bottom of this file close that for the bullet path: they instance a
## real `bullet.tscn` and step physics, so the layer/mask chain has to work for them to pass. The
## rocket (32) and asteroid (1024) mask bits and the incoming mining-laser ray are still verified
## only by reading the scene. See `ENEMY.md` -> "Collision layers".
extends GutTest

const STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")
const STATION_CONFIG := preload("res://assault/scenes/enemies/space_station/space_station_config.tres")

var _station: SpaceStation

## Stands in for `WaveManager.enemy_container`. Not cosmetic since sub-item 4a: the station now
## carries a `BulletPool`, and `bullet_pool.gd:47` resolves its container as
## `get_parent().get_parent()`. Parenting the station straight to this script would resolve that
## to GUT's own parent of the test script. It also keeps `ExplosionEffect`'s particles, which
## parent to `actor.get_parent()`, inside something `add_child_autofree` owns.
var _container: Node2D


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_station = STATION_SCENE.instantiate() as SpaceStation
	_container.add_child(_station)


## Emit on the core's own HurtBox — the same entry point the AoE module and the mining laser use.
func _hit_core(damage: int) -> void:
	_station.hurt_box.received_damage.emit(damage)


func _turrets() -> Array:
	return _station.get_node("Turrets").get_children()


func _kill_turret(index: int) -> void:
	var t := _turrets()[index] as StationTurret
	t.hurt_box.received_damage.emit(t.health.max_health)


# ── Armour rule ───────────────────────────────────────────────────────────────

func test_station_starts_armored_with_four_live_turrets() -> void:
	assert_eq(_station.live_turret_count(), 4, "station should start with 4 live turrets")
	assert_true(_station.is_armored(), "station should start armoured")


## The backlog's done-condition: destroy turrets one at a time and prove the core is
## invulnerable until the last one dies.
func test_core_ignores_damage_while_any_turret_lives() -> void:
	var full: int = _station.health.max_health
	for i in 3:
		_kill_turret(i)
		assert_eq(_station.live_turret_count(), 3 - i,
			"live turret count after killing turret %d" % i)
		assert_true(_station.is_armored(), "still armoured with %d turrets left" % (3 - i))
		_hit_core(50)
		assert_eq(_station.health.current_health, full,
			"core must not lose health with %d turrets alive" % (3 - i))


func test_core_becomes_damageable_after_last_turret_dies() -> void:
	var full: int = _station.health.max_health
	for i in 4:
		_kill_turret(i)
	assert_eq(_station.live_turret_count(), 0, "all turrets dead")
	assert_false(_station.is_armored(), "core must be unarmoured once the last turret dies")
	_hit_core(50)
	assert_eq(_station.health.current_health, full - 50, "core now takes damage")


## Distinguishes "armoured" from "unhittable". A disabled-hurtbox implementation would pass the
## test above but fail this one — and would silently leak the two direct-emit damage paths.
func test_armored_core_emits_armor_deflected_and_keeps_full_health() -> void:
	watch_signals(_station)
	var full: int = _station.health.max_health
	_hit_core(50)
	assert_signal_emitted_with_parameters(_station, "armor_deflected", [50])
	assert_eq(_station.health.current_health, full, "deflected damage must not reduce health")


func test_turret_damage_does_not_leak_into_core_health() -> void:
	var full: int = _station.health.max_health
	var t := _turrets()[0] as StationTurret
	t.hurt_box.received_damage.emit(10)
	assert_eq(_station.health.current_health, full, "turret damage must not touch core health")
	assert_eq(t.health.current_health, t.health.max_health - 10, "turret took the damage")


# ── Boundaries ────────────────────────────────────────────────────────────────

## `Health.set_health()` emits `amount_changed` on EVERY call including 0 -> 0
## (`health_component.gd:51-53`), so a dead turret hit again re-enters its death handler.
## Without the `_alive` guard this would re-emit `destroyed` and, under the old counter design,
## un-armour the core early.
func test_destroyed_turret_ignores_further_damage() -> void:
	var t := _turrets()[0] as StationTurret
	watch_signals(t)
	_kill_turret(0)
	for _i in 3:
		t.hurt_box.received_damage.emit(999)
	assert_signal_emit_count(t, "destroyed", 1, "destroyed must fire exactly once")
	assert_eq(_station.live_turret_count(), 3, "live count must not double-decrement")
	assert_true(_station.is_armored(), "three turrets are still alive")


func test_station_with_no_live_turrets_is_immediately_damageable() -> void:
	for i in 4:
		_kill_turret(i)
	assert_eq(_station.live_turret_count(), 0, "degenerate case: no live turrets")
	assert_false(_station.is_armored(), "a station with no live turrets is not armoured")


# ── Config-driven stats (CLAUDE.md: the .tres wins over the scene's Health node) ──

func test_config_max_health_wins_over_scene_health_node() -> void:
	assert_eq(_station.health.max_health, STATION_CONFIG.max_health,
		"core max_health must come from the .tres, not the scene")
	assert_eq(_station.health.current_health, STATION_CONFIG.max_health,
		"core starts at full config health")


func test_config_turret_health_is_applied_to_every_turret() -> void:
	for t in _turrets():
		var turret := t as StationTurret
		assert_eq(turret.health.max_health, STATION_CONFIG.turret_health,
			"turret max_health must come from the station's .tres")
		assert_eq(turret.health.current_health, STATION_CONFIG.turret_health,
			"turret starts at full config health")


# ── Premise: real bullets, real physics ───────────────────────────────────────
#
# Everything above drives damage by emitting `HurtBox.received_damage` directly, which is the
# documented coverage gap in this file's header: it proves nothing about collision layers, and
# nothing about what happens when a shot has to cross the armoured core to reach a turret.
#
# These two instance a real `bullet.tscn` and let the physics server find the hurtboxes. They
# exist because the whole "keep the core hurtbox hull-sized" decision
# (`docs/plans/should-the-station-s-core-hurtbox-be-narrowed-to-88-x-240-a-/3-plan.md`,
# `ENEMY.md` → "Core hurtbox: why it spans the whole hull") rests on one load-bearing fact:
#
#   **a player bullet is not consumed by the first hurtbox it overlaps.**
#
# That used to be true only by accident of three unrelated settings. It is now a stated rule with
# its own gate — `tests/integration/test_player_bullet_lifetime.gd` and `bullet.gd`'s header —
# which is what closed `two-consecutive-reviews-asserted-that-a-player-bullet-dies-o`.
#
# Whether the default gun *should* keep piercing is still open, as
# `code-health-backlog` → `decide-whether-the-player-s-default-gun-should-stop-on-its-f`. If it is
# ever changed without also changing the station, every shot aimed at a turret is absorbed by the
# core one to two physics frames early, deflects for 0 and dies — **the turrets become unkillable
# and so does the boss.** A geometry test cannot see that; this one goes red at the point of the
# change, and `test_a_bullet_is_not_consumed_by_a_hurtbox_it_overlaps` does the same one level down.

const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

## Lower-right turret, at station-local (76, 76) with a 26 px radius, so its rim spans
## y ∈ [50, 102] on the x = 76 lane.
const _LANE_TURRET_INDEX: int = 3

## `Bullet` needs nothing set up: `speed` is exported at 900, `rotation` defaults to 0 (straight
## up), and `_ready()` pushes its own `damage` into the child HitBox. It is parented to the
## container rather than to the station so no hull transform — including the phase-2 rotation —
## moves it, and so `add_child_autofree(_container)` still owns it at teardown. That matters:
## this bullet never frees itself, which is the very premise under test.
func _fire_bullet_at(spawn: Vector2) -> Bullet:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	_container.add_child(bullet)
	bullet.global_position = spawn
	return bullet


## THE premise test. A bullet fired up the x = 76 lane crosses the core's rect (bottom edge at
## y = +120, ~6 frames at 900 px/s = 15 px/frame), is deflected by the armour for 0, keeps
## flying, and hits the turret at y = +102 (~7 frames) for its full 50.
##
## The 12-frame budget is deliberate and bounded on both sides: fewer than 8 and the bullet has
## not reached the turret; 17 or more and it reaches the *upper* turret at y = -50 and takes a
## second 50 off a different one, so "exactly one hit of 50" stops being what is asserted.
func test_a_real_bullet_in_a_turret_lane_damages_the_turret_through_the_armored_core() -> void:
	watch_signals(_station)
	var turret := _turrets()[_LANE_TURRET_INDEX] as StationTurret
	var full_core: int = _station.health.max_health
	var full_turret: int = turret.health.max_health

	var bullet := _fire_bullet_at(Vector2(76.0, 200.0))
	await wait_physics_frames(12)

	assert_true(
		is_instance_valid(bullet),
		"the bullet must survive the core overlap — if it does not, the station's turrets are "
		+ "unreachable behind their own armour and the boss cannot be killed"
	)
	assert_eq(
		turret.health.current_health,
		full_turret - 50,
		"the turret behind the armoured core must take the bullet's full 50"
	)
	assert_eq(
		_station.health.current_health,
		full_core,
		"the armoured core must not lose health to a bullet that physically hit it"
	)
	assert_signal_emitted(
		_station,
		"armor_deflected",
		"the core is hittable while armoured — the bullet must reach its HurtBox through the "
		+ "collision layers, not only through a direct received_damage emit"
	)


## The other half, and the one that closes the layer-mask half of the coverage gap: once the
## armour is gone a real bullet on the centre lane damages the core itself. Every direct-emit
## test above passes happily on a core whose `collision_layer` no bullet could ever see.
##
## Killing the turrets starts the laser phase, which rotates the hull ~6.7° over these 12 frames
## and fires its first volley. Both are harmless here — a 240x240 box tilted by 6.7° still spans
## the x = 0 lane — but it is why this test asserts on health and not on the hull's transform.
func test_a_real_bullet_damages_the_core_once_the_armor_is_broken() -> void:
	var full_core: int = _station.health.max_health
	for i in 4:
		_kill_turret(i)
	assert_false(_station.is_armored(), "precondition: the armour is gone")

	var bullet := _fire_bullet_at(Vector2(0.0, 200.0))
	await wait_physics_frames(12)

	assert_true(is_instance_valid(bullet), "the bullet is not consumed by the core hurtbox")
	assert_eq(
		_station.health.current_health,
		full_core - 50,
		"an unarmoured core must take damage from a real bullet found through the collision "
		+ "layers, not just from a direct received_damage emit"
	)
