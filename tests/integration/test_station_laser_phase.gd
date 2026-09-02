## Integration test for the space-station laser phase (EPIC sub-item 3).
##
## NOT characterization: `StationLaserPhase`, `SpaceStation.armor_broken` and the five
## `SpaceStationConfig` laser fields are all new code, so these assert intended behaviour.
## Plan: `docs/plans/station-laser-phase/3-plan.md`.
##
## The two backlog done-conditions are tests 1/2 (the phase starts only after the LAST turret
## dies) and tests 4/5 (a beam damages only during its active window, never during the warning).
##
## ── Two harness rules this file must obey ────────────────────────────────────────────────────
##
## 1. **Never write to `station.config`.** `space_station.gd:24` `load()`s the `.tres` and
##    `ResourceLoader` caches, so every SpaceStation in the process shares ONE
##    `SpaceStationConfig` — the same object `preload()` hands this file. Mutating it to shorten
##    the timings would permanently rewrite the shipped values for every later test in the run,
##    including `test_config_laser_values_win_over_script_defaults` below. Tests shorten timings
##    by writing the **phase node's own copied fields** instead (`StationLaserPhase` copies them
##    in `_ready()`), which touches no shared state.
##
## 2. **Test timings are `warn 0.2 / active 0.3 / interval 2.5`.** The interval must stay LONGER
##    than a full beam lifetime (~1.9 s at these durations: warn + 0.56 s charge + 0.3 s active +
##    0.84 s dissolve), or volley 2 spawns while volley 1 is still dissolving and the child-count
##    assertions become false rather than merely flaky.
##
## Lives in integration/ because it instances real scenes (`tests/README.md`: unit/ does no
## scene loading).
extends GutTest

const STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")
const STATION_CONFIG := preload("res://assault/scenes/enemies/space_station/space_station_config.tres")

var _station: SpaceStation
## Stands in for `WaveManager.enemy_container`, which is what actually parents the station in a
## level. Not cosmetic: `ExplosionEffect.explode()` parents its `CPUParticles2D` to
## `actor.get_parent()` and lets it self-free on `finished` (~1 s later), so a station added
## straight to the test script leaves particles behind as unfreed children of the script when the
## test that kills the core returns. Routing through a container that `add_child_autofree` owns
## takes them with it.
var _container: Node2D


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_station = _spawn_station()


func _spawn_station() -> SpaceStation:
	var station := STATION_SCENE.instantiate() as SpaceStation
	_container.add_child(station)
	return station


func _turrets() -> Array:
	return _station.get_node("Turrets").get_children()


func _kill_turret(index: int) -> void:
	var t := _turrets()[index] as StationTurret
	t.hurt_box.received_damage.emit(t.health.max_health)


func _kill_all_turrets() -> void:
	for i in _turrets().size():
		_kill_turret(i)


# ── Step 2: the armor_broken trigger ──────────────────────────────────────────

## Test 1's negative half, at the signal level: three of four turrets dead is still armoured.
func test_armor_broken_does_not_fire_while_any_turret_lives() -> void:
	watch_signals(_station)
	for i in 3:
		_kill_turret(i)
	assert_eq(_station.live_turret_count(), 1, "one turret should still be alive")
	assert_true(_station.is_armored(), "station should still be armoured")
	assert_signal_emit_count(_station, "armor_broken", 0,
		"armor_broken must not fire until the LAST turret dies")


func test_armor_broken_fires_when_the_last_turret_dies() -> void:
	watch_signals(_station)
	_kill_all_turrets()
	assert_eq(_station.live_turret_count(), 0, "all turrets should be dead")
	assert_false(_station.is_armored(), "station should no longer be armoured")
	assert_signal_emit_count(_station, "armor_broken", 1, "armor_broken fires on the last death")


## Test 3 — the boundary case for the `_armor_broken` guard.
##
## Re-emitting `received_damage` on a dead turret would prove nothing: `station_turret.gd:45-47`
## returns early when `not _alive`, so the damage never reaches `Health` and `destroyed` never
## re-fires. Driving `destroyed` directly is what re-enters the station's subscription, and it
## DOES double-fire without the guard.
func test_armor_broken_emits_exactly_once() -> void:
	watch_signals(_station)
	_kill_all_turrets()
	for i in 3:
		var t := _turrets()[i] as StationTurret
		t.destroyed.emit(t)
	assert_signal_emit_count(_station, "armor_broken", 1,
		"armor_broken must be idempotent against re-entry through destroyed")


# ── Step 4: the laser phase ───────────────────────────────────────────────────

func _phase() -> StationLaserPhase:
	return _station.get_node("LaserPhase") as StationLaserPhase


## Shorten the timings on the PHASE NODE, never on `station.config` — see the header. Must be
## called before the phase starts, i.e. before the last turret dies.
##
## `interval 2.5` is chosen to stay LONGER than a full beam lifetime at these durations
## (~1.9 s), preserving the shipped `interval > lifetime` relation the child-count assertions
## depend on.
func _use_fast_timings(rotation_speed: float = 0.0) -> void:
	var p := _phase()
	p.warn_duration = 0.2
	p.active_duration = 0.3
	p.volley_interval = 2.5
	p.rotation_speed = rotation_speed
	p.beam_count = 2


## Test 1 — the backlog's first done-condition.
func test_phase_does_not_start_while_any_turret_lives() -> void:
	_use_fast_timings(0.5)
	for i in 3:
		_kill_turret(i)
	await wait_physics_frames(30)
	assert_false(_phase().is_active(), "phase must not start while a turret still lives")
	assert_eq(_phase().live_beams().size(), 0, "no beams may spawn while the station is armoured")
	assert_almost_eq(_station.rotation, 0.0, 0.0001, "the station must not rotate while armoured")


## Test 2 — the other half of the done-condition.
func test_phase_starts_when_last_turret_dies() -> void:
	_use_fast_timings()
	_kill_all_turrets()
	assert_true(_phase().is_active(), "phase must start when the last turret dies")
	await wait_physics_frames(2)
	assert_eq(_phase().live_beams().size(), _phase().beam_count,
		"the first volley spawns exactly beam_count beams, no more")


## Test 4 — the backlog's second done-condition, negative half.
##
## A real physics assertion, not a direct emit: a stub HurtBox on the player layer is placed in
## the beam's path and must receive NOTHING while the beam is still telegraphing.
func test_beam_is_not_lethal_during_the_warning_window() -> void:
	_use_fast_timings()
	var probe := _add_player_probe()
	_kill_all_turrets()
	await wait_physics_frames(2)
	var beam := _phase().live_beams()[0]
	## Sample at half the warning window, comfortably away from the boundary.
	await wait_seconds(0.1)
	assert_false(beam.is_lethal_now(), "the beam must not be lethal during its warning window")
	assert_eq(probe.hits, 0, "a warning beam must deal no damage at all")


## Test 5 — the positive half. Catches a beam that telegraphs and then never arms, which test 4
## alone would happily pass.
func test_beam_damages_the_player_during_the_active_window() -> void:
	_use_fast_timings()
	var probe := _add_player_probe()
	_kill_all_turrets()
	## warn (0.2) + the ~0.56 s laser_increase charge-up, plus margin.
	await wait_seconds(1.0)
	assert_gt(probe.hits, 0, "the beam must damage the player once it is armed")
	assert_eq(probe.last_damage, 9999, "the laser is a one-hit kill")


## A stand-in for the player: a real `HurtBox` on layer 128 (player_hurtbox), placed in the beam's
## path so the beam has to find it through actual physics. `test_space_station.gd` drives damage
## by emitting `received_damage` directly and documents that as a coverage gap — this closes it
## for the laser, which is the one thing here whose whole correctness is a collision mask.
class PlayerProbe:
	extends HurtBox

	var hits: int = 0
	var last_damage: int = 0

	func _init() -> void:
		received_damage.connect(_count)

	func _count(damage: int) -> void:
		hits += 1
		last_damage = damage


## Default offset (0, 400) sits inside volley 0's first beam, which emits at local (0, 140) and
## extends 1536 px along +Y.
func _add_player_probe(offset: Vector2 = Vector2(0.0, 400.0)) -> PlayerProbe:
	var probe := PlayerProbe.new()
	probe.collision_layer = 128
	probe.collision_mask = 0
	## The beam's HitZone is what monitors; the probe only has to be visible to it.
	probe.monitoring = false
	probe.monitorable = true
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32.0, 32.0)
	var shape := CollisionShape2D.new()
	shape.shape = rect
	probe.add_child(shape)
	probe.position = offset
	add_child_autofree(probe)
	return probe


## Test 6 — THE regression test for the self-destruct trap.
##
## It MUST force a diagonal volley. At `emitter_radius = 140` an axis-aligned beam starts 20 px
## clear of the 240x240 core hurtbox and never touches it, so on volley 0 this test passes with
## the fix reverted — it is vacuous. Volley index 2 emits at local (-99, 99) and (99, -99), both
## comfortably inside the +/-120 square, and that is where the boss kills itself.
##
## Real physics throughout: no direct `received_damage` emits.
##
## IF THE EMITTER EVER MOVES OUTSIDE THE HULL ON ALL ANGLES, the health half of this test goes
## vacuous again and only the collision-mask assertion below still bites. Replace it rather than
## deleting it.
func test_beam_does_not_damage_the_station_that_fires_it() -> void:
	var p := _phase()
	p.warn_duration = 0.2
	p.active_duration = 1.0
	p.volley_interval = 0.0
	p.rotation_speed = 0.0
	p.beam_count = 2
	## Diagonal volley — set before the phase starts.
	p._volley_index = 2

	_kill_all_turrets()
	assert_false(_station.is_armored(), "the core must be un-armoured, or this proves nothing")

	var beam := p.live_beams()[0]
	assert_eq(beam.get_node("HitZone").collision_mask, 128,
		"the station's beams must hit the player layer only")
	assert_eq(beam.get_node("HitZone").collision_mask & 512, 0,
		"layer 512 is the station's own core HurtBox — the beam must not see it")

	## warn 0.2 + ~0.56 charge, then well over 0.5 s of fully lethal beam.
	await wait_seconds(1.4)
	assert_true(is_instance_valid(_station), "the station must not have killed itself")
	assert_eq(_station.health.current_health, _station.health.max_health,
		"the station must take zero damage from its own beam")


## Test 7 — rotation is a property of the phase, not of existing.
func test_station_rotates_only_during_the_laser_phase() -> void:
	var p := _phase()
	p.warn_duration = 0.2
	p.active_duration = 0.3
	p.volley_interval = 0.0
	## Deliberately not the shipped 0.5: a hardcoded speed would still pass at 0.5.
	p.rotation_speed = 2.0
	p.beam_count = 2

	await wait_physics_frames(20)
	assert_almost_eq(_station.rotation, 0.0, 0.0001,
		"an armoured station must not rotate at all")

	_kill_all_turrets()
	var r0: float = _station.rotation
	var f0: int = Engine.get_physics_frames()
	await wait_physics_frames(20)
	var frames: int = Engine.get_physics_frames() - f0
	var expected: float = p.rotation_speed * float(frames) / float(Engine.physics_ticks_per_second)
	## Tolerance is three physics frames' worth: whether _physics_process ran on the first and
	## last frame of the window is not worth pinning, but the RATE is.
	var tol: float = p.rotation_speed * 3.0 / float(Engine.physics_ticks_per_second)
	assert_almost_eq(_station.rotation - r0, expected, tol,
		"rotation must advance at laser_rotation_speed, not at some hardcoded rate")


## Drives volleys by hand rather than waiting out four 2.5 s intervals — the determinism claim is
## about the angle list, and 20 s of wall clock buys nothing.
func _volley_angle_sequence(station: SpaceStation) -> Array[float]:
	var p := station.get_node("LaserPhase") as StationLaserPhase
	p.warn_duration = 0.2
	p.active_duration = 0.3
	## 0 disables the repeat timer, so nothing fires except what this function asks for.
	p.volley_interval = 0.0
	## Isolate the angle list from the sweep.
	p.rotation_speed = 0.0
	p.beam_count = 2
	for t in station.get_node("Turrets").get_children():
		var turret := t as StationTurret
		turret.hurt_box.received_damage.emit(turret.health.max_health)

	var out: Array[float] = []
	for k in 4:
		for beam in p.live_beams():
			p.remove_child(beam)
			beam.queue_free()
		p._volley_index = k
		p._fire_volley()
		for beam in p.live_beams():
			out.append(beam.rotation)
	return out


## Test 8 — fails the moment someone reaches for `randf()`, which is the natural reading of the
## backlog's "at varying positions".
func test_volley_angles_are_deterministic() -> void:
	var second := _spawn_station()

	var a := _volley_angle_sequence(_station)
	var b := _volley_angle_sequence(second)

	assert_eq(a.size(), 8, "four volleys of two beams")
	for i in a.size():
		## `Node2D.rotation` is float32-backed, so PI * 1.25 reads back 3.92699074745178 rather
		## than 3.92699081698724 — compare with a tolerance, never with ==.
		assert_almost_eq(a[i], b[i], 0.0001,
			"two fresh stations must fire the identical angle sequence (beam %d)" % i)

	for k in 4:
		var first: float = a[k * 2]
		var opposed: float = a[k * 2 + 1]
		assert_almost_eq(absf(angle_difference(first, opposed)), PI, 0.0001,
			"the two beams of volley %d must be opposed" % k)


## Test 9 — nothing this phase creates may outlive the station. `LevelSection.ENEMIES_CLEARED`
## polls the enemy container's child count, and a beam that is lethal on the frame the boss dies
## would still get one kill out of a corpse.
func test_beams_stop_and_do_not_outlive_the_station() -> void:
	var p := _phase()
	p.warn_duration = 0.2
	p.active_duration = 2.0
	p.volley_interval = 0.0
	p.rotation_speed = 0.0
	p.beam_count = 2

	_kill_all_turrets()
	await wait_seconds(1.0)
	var beams := p.live_beams()
	assert_gt(beams.size(), 0, "there must be a live beam, or this proves nothing")
	var lethal_before: int = 0
	for beam in beams:
		if beam.is_lethal_now():
			lethal_before += 1
	assert_gt(lethal_before, 0, "at least one beam must be lethal before the core dies")

	_station.hurt_box.received_damage.emit(_station.health.max_health)

	assert_false(p.is_active(), "the phase must stop the moment the core dies")
	for beam in p.live_beams():
		assert_false(beam.is_lethal_now(), "no beam may still be lethal after the boss dies")

	await wait_physics_frames(2)
	assert_false(is_instance_valid(_station), "the station must be freed")


## Test 10 — `CLAUDE.md`'s config-driven rule.
##
## Asserted against the PHASE NODE's copied fields, not `station.config`: `station.config` IS the
## object `preload()` returns here, so comparing the two would be an identity check that cannot
## fail. What actually needs pinning is that the copy in `_ready()` happened.
func test_config_laser_values_win_over_script_defaults() -> void:
	var p := _phase()
	assert_almost_eq(p.warn_duration, STATION_CONFIG.laser_warn_duration, 0.0001,
		"warn_duration must come from the .tres")
	assert_almost_eq(p.active_duration, STATION_CONFIG.laser_active_duration, 0.0001,
		"active_duration must come from the .tres")
	assert_almost_eq(p.volley_interval, STATION_CONFIG.laser_volley_interval, 0.0001,
		"volley_interval must come from the .tres")
	assert_almost_eq(p.rotation_speed, STATION_CONFIG.laser_rotation_speed, 0.0001,
		"rotation_speed must come from the .tres")
	assert_eq(p.beam_count, STATION_CONFIG.laser_beam_count, "beam_count must come from the .tres")

	## Without this the block above passes for a phase that never read the config at all.
	var defaults := StationLaserPhase.new()
	var differs: bool = (
		not is_equal_approx(defaults.warn_duration, STATION_CONFIG.laser_warn_duration)
		or not is_equal_approx(defaults.active_duration, STATION_CONFIG.laser_active_duration)
		or not is_equal_approx(defaults.volley_interval, STATION_CONFIG.laser_volley_interval)
		or not is_equal_approx(defaults.rotation_speed, STATION_CONFIG.laser_rotation_speed)
		or defaults.beam_count != STATION_CONFIG.laser_beam_count
	)
	defaults.free()
	assert_true(differs,
		"the .tres must differ from the phase's script defaults on at least one field, or the "
		+ "assertions above pass without the copy ever running")
