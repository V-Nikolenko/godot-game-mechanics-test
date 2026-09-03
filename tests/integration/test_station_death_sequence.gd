## Integration tests for the space station's death sequence (EPIC sub-item 5).
##
## Like the rest of the space-station family these are NOT characterization tests — the death
## sequence is new code, so they assert intended behaviour.
##
## Three things about the harness, all learned the hard way by earlier station tests:
##
##  - The station is parented to a container `Node2D` owned by `add_child_autofree`, never to the
##    test script directly. `ExplosionEffect.explode()` parents its CPUParticles2D to the
##    station's PARENT and lets them self-free ~0.5 s later, so a station added straight to the
##    script leaves `GUT WARNING: Test script has N unfreed children`. A container is also how the
##    station is really parented in play (under `WaveManager.enemy_container`).
##  - Timings are shortened by writing the NODE's copied field (`station.death_duration`), never
##    `station.config`. `space_station.gd` load()s the .tres and ResourceLoader caches it, so the
##    config is one process-wide object shared with every later test in the run.
##  - `died` cannot be reached without going through `armor_broken`: the core refuses all damage
##    while a turret lives, so every test here kills the four turrets first.
extends GutTest

const STATION_SCENE := preload("res://assault/scenes/enemies/space_station/space_station.tscn")

var _container: Node2D
var _station: SpaceStation


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)

	_station = STATION_SCENE.instantiate() as SpaceStation
	_container.add_child(_station)
	await get_tree().process_frame


## Kills all four turrets, leaving the core damageable. Filters by type before casting: from the
## first turret kill onward `$Turrets` also contains CPUParticles2D, and a raw get_children()
## would hand back a particle node whose `is_alive()` call reds the test as an Unexpected Error.
func _break_armor() -> void:
	for t in _station.turrets():
		t.hurt_box.received_damage.emit(9999)
	await get_tree().process_frame


func _kill_core() -> void:
	await _break_armor()
	_station.hurt_box.received_damage.emit(9999)
	await get_tree().process_frame


func _sequence() -> StationDeathSequence:
	return _station.get_node("DeathSequence") as StationDeathSequence


## Direct CPUParticles2D children of the container. Direct-only and type-filtered on purpose:
## a recursive search would also find the permanent HitEffect particles every BaseEnemy carries
## (base_enemy.gd:29-30 + hit_effect.gd:21,34) and the turret explosions under $Turrets.
func _container_particles() -> Array:
	var out: Array = []
	for child in _container.get_children():
		if child is CPUParticles2D:
			out.append(child)
	return out


# ── 1-3. The wreck's lifetime ─────────────────────────────────────────────────

func test_the_wreck_stays_in_the_tree_after_hp_reaches_zero() -> void:
	await _kill_core()
	await get_tree().process_frame

	assert_true(is_instance_valid(_station),
		"the wreck must survive the frame its HP hit 0 — BaseEnemy would have freed it already")
	assert_eq(_station.get_parent(), _container,
		"the wreck must stay parented, which is what holds station_assault open")
	assert_true(_station.is_dying(), "the station should report that it is dying")


func test_died_and_was_killed_fire_at_the_moment_hp_reaches_zero() -> void:
	var died_count := [0]
	_station.died.connect(func() -> void: died_count[0] += 1)

	await _kill_core()

	assert_eq(died_count[0], 1, "died must fire exactly once, on the frame HP hit 0")
	assert_true(_station.was_killed,
		"was_killed must be true immediately — ScoreTracker reads it on tree_exited to tell a " +
		"kill from an escape, and a late write would score the boss as an escape at 0.75x combo")


func test_further_damage_during_the_death_sequence_does_not_re_emit_died() -> void:
	_station.death_duration = 0.3
	var died_count := [0]
	_station.died.connect(func() -> void: died_count[0] += 1)

	await _kill_core()

	## Health.set_health() emits amount_changed unconditionally, so each of these re-enters
	## _on_health_changed with current == 0.
	for i in 3:
		if is_instance_valid(_station):
			_station.hurt_box.received_damage.emit(50)
	await get_tree().process_frame

	assert_eq(died_count[0], 1, "the _dying latch must stop a 0 -> 0 re-emit re-running death")


# ── 4. The corpse is harmless ─────────────────────────────────────────────────

func test_the_corpse_cannot_ram_the_player() -> void:
	_station.death_duration = 0.3

	var hitbox: HitBox = null
	for child in _station.get_children():
		if child is HitBox:
			hitbox = child
			break
	assert_not_null(hitbox, "the station should have BaseEnemy's contact HitBox")
	assert_eq(hitbox.collision_layer, 256, "alive, the hull sits on the contact layer")

	await _kill_core()
	## set_deferred, so the change lands on the next idle frame.
	await get_tree().process_frame

	assert_eq(hitbox.collision_layer, 0,
		"a dead 256 px hull must not still ram the player — the player's HurtBox monitors 256")
	assert_false(_station.hurt_box.monitoring,
		"the corpse should stop monitoring for incoming physics damage")


# ── 5-6. The timer, and the boundary that proves the path is additive ─────────

func test_the_wreck_is_freed_after_death_sequence_duration() -> void:
	_station.death_duration = 0.15
	await _kill_core()
	assert_true(is_instance_valid(_station), "still present immediately after death")

	await get_tree().create_timer(0.35).timeout
	assert_false(is_instance_valid(_station), "the wreck must be gone once the timer elapses")


## BOUNDARY. The script default is 0.0, so this is also what a station with no .tres does: the
## new path must be strictly additive over BaseEnemy's one-frame death.
func test_death_sequence_duration_zero_keeps_the_base_enemy_behaviour() -> void:
	_station.death_duration = 0.0
	await _kill_core()

	assert_false(is_instance_valid(_station),
		"at duration 0 the station must be freed in the same frame, exactly as every other enemy")


# ── 8-9. The blast chain ──────────────────────────────────────────────────────

## Finding K's regression test. If this fails, the ExplosionEffect is parented to the sequence
## node instead of the station and every blast is landing inside the rotating hull.
## DO NOT weaken this test to make it pass.
func test_the_blast_chain_rolls_across_the_hull_rather_than_detonating_at_its_centre() -> void:
	var seq := _sequence()
	seq.death_spin = 0.0
	_station.death_duration = 0.4

	await _kill_core()
	await get_tree().create_timer(0.25).timeout

	var particles := _container_particles()
	assert_gt(particles.size(), 0,
		"blasts must land in the CONTAINER, so they survive the wreck and hold the section open")

	var found_offset := false
	for p in particles:
		var d: float = (p.global_position - _station.global_position).length()
		if absf(d - seq.blast_spread_radius) < 1.0:
			found_offset = true
			break
	assert_true(found_offset,
		"at least one blast must sit ~%.0f px off centre — a centre-only burst is the old death"
			% seq.blast_spread_radius)


func test_blast_offsets_are_deterministic() -> void:
	var seq := _sequence()

	## A second, independent station: two runs must agree.
	var other_station := STATION_SCENE.instantiate() as SpaceStation
	_container.add_child(other_station)
	await get_tree().process_frame
	var other := other_station.get_node("DeathSequence") as StationDeathSequence

	for i in 8:
		assert_eq(seq.blast_offset(i), other.blast_offset(i),
			"blast %d must be identical across stations — no randf() anywhere in the chain" % i)
		assert_eq(seq.blast_offset(i), seq.blast_offset(i),
			"blast %d must be stable across repeated calls" % i)

	## And it is genuinely a chain, not the same point eight times.
	assert_ne(seq.blast_offset(0), seq.blast_offset(1),
		"consecutive blasts must land in different places")

	other_station.free()


func test_every_blast_lands_on_the_hull() -> void:
	var seq := _sequence()
	## The hull is 256x256, so its half-extent is 128 px. A blast outside that is in empty space.
	for i in 8:
		assert_lt(seq.blast_offset(i).length(), 128.0,
			"blast %d must land ON the 256 px hull, not beside it" % i)


# ── 10. The wreck degrades ────────────────────────────────────────────────────

func test_the_hull_drifts_and_darkens_during_the_sequence() -> void:
	_station.death_duration = 0.4
	var rotation_before := _station.rotation
	var modulate_before := _station.modulate

	await _kill_core()
	await get_tree().create_timer(0.2).timeout

	if not is_instance_valid(_station):
		fail_test("the wreck was freed before the sequence could be sampled")
		return

	assert_ne(_station.rotation, rotation_before, "the wreck should drift, not stop dead")
	assert_lt(_station.modulate.r, modulate_before.r, "the wreck should darken toward burnt grey")


func test_the_spin_decays_rather_than_staying_constant() -> void:
	_station.death_duration = 0.6
	await _kill_core()

	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(_station):
		fail_test("wreck freed too early to sample the early spin")
		return
	var early_a := _station.rotation
	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(_station):
		fail_test("wreck freed too early to sample the early spin")
		return
	var early_delta: float = absf(_station.rotation - early_a)

	## Sample again near the end of the sequence, where the decay should have bitten.
	await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(_station):
		fail_test("wreck freed too early to sample the late spin")
		return
	var late_a := _station.rotation
	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(_station):
		fail_test("wreck freed too early to sample the late spin")
		return
	var late_delta: float = absf(_station.rotation - late_a)

	assert_lt(late_delta, early_delta,
		"the spin must decay across the sequence, not run at a constant rate to the last frame")


# ── 11. The config copy ───────────────────────────────────────────────────────

func test_the_station_copies_its_death_duration_from_the_config() -> void:
	var cfg: SpaceStationConfig = _station.config
	assert_not_null(cfg, "the station ships with a config")
	assert_eq(_station.death_duration, cfg.death_sequence_duration,
		"the station must copy the shipped duration")
	assert_eq(cfg.death_sequence_duration, 1.8, "the shipped .tres value")
	assert_eq(cfg.death_blast_count, 7, "the shipped .tres value")


## The script defaults must DIFFER from the shipped .tres, or the config test above would pass
## even if the copy were deleted.
func test_the_script_defaults_differ_from_the_shipped_values() -> void:
	var fresh := SpaceStationConfig.new()
	assert_eq(fresh.death_sequence_duration, 0.0,
		"the script default is the honest fallback: behave exactly as BaseEnemy")
	assert_eq(fresh.death_blast_count, 3, "script default, deliberately not the shipped 7")
	assert_ne(fresh.death_sequence_duration, 1.8, "defaults must not equal the shipped value")


func test_shortening_the_station_duration_does_not_write_back_to_the_shared_config() -> void:
	var before: float = _station.config.death_sequence_duration
	_station.death_duration = 0.05
	assert_eq(_station.config.death_sequence_duration, before,
		"writing the node's copied field must not touch the process-wide shared .tres")
