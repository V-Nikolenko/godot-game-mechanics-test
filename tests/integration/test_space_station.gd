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
## KNOWN COVERAGE GAP: damage is driven by emitting `HurtBox.received_damage` directly, so these
## tests do NOT prove the collision layers are right. A core whose HurtBox has the wrong
## `collision_layer` — one no bullet could ever hit — passes every test in this file. Those
## values are verified by reading the scene, and provably only once the station is in a live
## level (sub-item 2).
extends GutTest

const STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")
const STATION_CONFIG := preload("res://assault/scenes/enemies/space_station/space_station_config.tres")

var _station: SpaceStation


func before_each() -> void:
	_station = STATION_SCENE.instantiate() as SpaceStation
	add_child_autofree(_station)


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
## (`health_component.gd:40-42`), so a dead turret hit again re-enters its death handler.
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
