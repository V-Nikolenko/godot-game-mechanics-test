## Integration tests for the shared boss death sequence (`BossDeathSequence`, `global/boss/`), on its first host, the Space Fortress
## (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.4 and §2.11; re-pointed from the retired space station in Phase 11 t11).
##
## Intent tests, not characterization: they assert what the death spectacle is for.
##
## Three things about the harness:
##
##  - The fortress is parented to a container `Node2D` owned by `add_child_autofree`, never to the test script directly.
##    `ExplosionEffect.explode()` parents its CPUParticles2D to the host's PARENT and lets them self-free ~0.5 s later, so a host added
##    straight to the script leaves `GUT WARNING: Test script has N unfreed children`. A container is also how the boss is really parented
##    in play (under `WaveManager.enemy_container`).
##  - The fortress's own physics is off (no brain, no mover), so nothing but the death sequence writes the dying hull's `rotation`.
##  - Timings are shortened by writing the NODE's copied field (`fortress.death_duration`), its tunable surface. `fortress.config` is a
##    private per-instance copy (`ShipConfig.privatise()`), but the object a test `preload()`s is one process-wide resource and is never
##    written.
##
## The death is the core part's death (`part(&"core").destroy()`): the hull is armour and refuses every hit.
extends GutTest

const FORTRESS_SCENE := preload("res://assault/scenes/enemies/space_fortress/space_fortress.tscn")
const SHIPPED: SpaceFortressConfig = preload("res://assault/scenes/enemies/space_fortress/space_fortress_config.tres")  # read only

var _container: Node2D
var _fortress: SpaceFortress


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_fortress = _spawn(Vector2(640.0, 360.0))
	await get_tree().process_frame


func _spawn(at: Vector2) -> SpaceFortress:
	var f := FORTRESS_SCENE.instantiate() as SpaceFortress
	f.global_position = at
	_container.add_child(f)
	f.set_physics_process(false)
	return f


func _kill_core() -> void:
	_fortress.part(&"core").destroy()
	await get_tree().process_frame


func _sequence() -> BossDeathSequence:
	return _fortress.get_node("DeathSequence") as BossDeathSequence


## Direct CPUParticles2D children of the container. Direct-only and type-filtered on purpose: a recursive search would also find the
## permanent HitEffect particles every BaseEnemy carries.
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

	assert_true(is_instance_valid(_fortress),
		"the wreck must survive the frame its HP hit 0 — BaseEnemy would have freed it already")
	assert_eq(_fortress.get_parent(), _container,
		"the wreck must stay parented, which is what holds station_assault open")
	assert_true(_fortress.is_dying(), "the fortress should report that it is dying")


func test_died_and_was_killed_fire_at_the_moment_hp_reaches_zero() -> void:
	var died_count := [0]
	_fortress.died.connect(func() -> void: died_count[0] += 1)

	await _kill_core()

	assert_eq(died_count[0], 1, "died must fire exactly once, on the frame HP hit 0")
	assert_true(_fortress.was_killed,
		"was_killed must be true immediately — ScoreTracker reads it on tree_exited to tell a " +
		"kill from an escape, and a late write would score the boss as an escape at 0.75x combo")


func test_further_damage_during_the_death_sequence_does_not_re_emit_died() -> void:
	_fortress.death_duration = 0.3
	var died_count := [0]
	_fortress.died.connect(func() -> void: died_count[0] += 1)

	await _kill_core()

	## The armoured hull refuses `received_damage` while dying, so a damage emit would never reach the death handler. `Health.set_health()`
	## emits `amount_changed` unconditionally, so each of these re-enters `_on_health_changed` with current == 0: the `_dying` latch is what
	## is under test.
	for i in 3:
		if is_instance_valid(_fortress):
			_fortress.health.set_health(0)
	await get_tree().process_frame

	assert_eq(died_count[0], 1, "the _dying latch must stop a 0 -> 0 re-emit re-running death")


# ── 4. The corpse is harmless ─────────────────────────────────────────────────

func test_the_corpse_cannot_ram_the_player() -> void:
	_fortress.death_duration = 0.3

	var hitbox := _fortress.contact_hit_box
	assert_not_null(hitbox, "the fortress should have BaseEnemy's contact HitBox")
	assert_eq(hitbox.collision_layer, 256, "alive, the hull sits on the contact layer")

	await _kill_core()
	## set_deferred, so the change lands on the next idle frame.
	await get_tree().process_frame

	assert_eq(hitbox.collision_layer, 0,
		"a dead 352 px hull must not still ram the player — the player's HurtBox monitors 256")
	assert_false(_fortress.hurt_box.monitoring,
		"the corpse should stop monitoring for incoming physics damage")


# ── 5-6. The timer, and the boundary that proves the path is additive ─────────

func test_the_wreck_is_freed_after_death_sequence_duration() -> void:
	_fortress.death_duration = 0.15
	await _kill_core()
	assert_true(is_instance_valid(_fortress), "still present immediately after death")

	await get_tree().create_timer(0.35).timeout
	assert_false(is_instance_valid(_fortress), "the wreck must be gone once the timer elapses")


## BOUNDARY. The node's script default is 0.0, so this is also what a fortress with no config does: the timed path must be strictly
## additive over BaseEnemy's one-frame death.
func test_death_sequence_duration_zero_keeps_the_base_enemy_behaviour() -> void:
	_fortress.death_duration = 0.0
	await _kill_core()

	assert_false(is_instance_valid(_fortress),
		"at duration 0 the fortress must be freed in the same frame, exactly as every other enemy")


# ── 8-9. The blast chain ──────────────────────────────────────────────────────

## If this fails, the ExplosionEffect is parented to the sequence node instead of the host and every blast is landing inside the rotating
## hull. DO NOT weaken this test to make it pass.
func test_the_blast_chain_rolls_across_the_hull_rather_than_detonating_at_its_centre() -> void:
	var seq := _sequence()
	seq.death_spin = 0.0
	_fortress.death_duration = 0.4

	await _kill_core()
	await get_tree().create_timer(0.25).timeout

	var particles := _container_particles()
	assert_gt(particles.size(), 0,
		"blasts must land in the CONTAINER, so they survive the wreck and hold the section open")

	var found_offset := false
	for p in particles:
		var d: float = (p.global_position - _fortress.global_position).length()
		if absf(d - seq.blast_spread_radius) < 1.0:
			found_offset = true
			break
	assert_true(found_offset,
		"at least one blast must sit ~%.0f px off centre — a centre-only burst is the old death"
			% seq.blast_spread_radius)


func test_blast_offsets_are_deterministic() -> void:
	var seq := _sequence()

	## A second, independent fortress: two runs must agree.
	var other_fortress := _spawn(Vector2(640.0, 1200.0))
	await get_tree().process_frame
	var other := other_fortress.get_node("DeathSequence") as BossDeathSequence

	for i in 8:
		assert_eq(seq.blast_offset(i), other.blast_offset(i),
			"blast %d must be identical across fortresses — no randf() anywhere in the chain" % i)
		assert_eq(seq.blast_offset(i), seq.blast_offset(i),
			"blast %d must be stable across repeated calls" % i)

	## And it is genuinely a chain, not the same point eight times.
	assert_ne(seq.blast_offset(0), seq.blast_offset(1),
		"consecutive blasts must land in different places")

	other_fortress.free()


func test_every_blast_lands_on_the_hull() -> void:
	var seq := _sequence()
	var hull := _fortress.hull_radius()
	assert_almost_eq(hull, 176.0, 0.001, "sanity: the ring hull's radius")
	for i in SHIPPED.death_blast_count:
		assert_lt(seq.blast_offset(i).length(), hull,
			"blast %d must land ON the %.0f px hull, not beside it" % [i, hull * 2.0])


# ── 10. The wreck degrades ────────────────────────────────────────────────────

func test_the_hull_drifts_and_darkens_during_the_sequence() -> void:
	_fortress.death_duration = 0.4
	var rotation_before := _fortress.rotation
	var modulate_before := _fortress.modulate

	await _kill_core()
	await get_tree().create_timer(0.2).timeout

	if not is_instance_valid(_fortress):
		fail_test("the wreck was freed before the sequence could be sampled")
		return

	assert_ne(_fortress.rotation, rotation_before, "the wreck should drift, not stop dead")
	assert_lt(_fortress.modulate.r, modulate_before.r, "the wreck should darken toward burnt grey")


func test_the_spin_decays_rather_than_staying_constant() -> void:
	_fortress.death_duration = 0.6
	await _kill_core()

	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(_fortress):
		fail_test("wreck freed too early to sample the early spin")
		return
	var early_a := _fortress.rotation
	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(_fortress):
		fail_test("wreck freed too early to sample the early spin")
		return
	var early_delta: float = absf(_fortress.rotation - early_a)

	## Sample again near the end of the sequence, where the decay should have bitten.
	await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(_fortress):
		fail_test("wreck freed too early to sample the late spin")
		return
	var late_a := _fortress.rotation
	await get_tree().create_timer(0.1).timeout
	if not is_instance_valid(_fortress):
		fail_test("wreck freed too early to sample the late spin")
		return
	var late_delta: float = absf(_fortress.rotation - late_a)

	assert_lt(late_delta, early_delta,
		"the spin must decay across the sequence, not run at a constant rate to the last frame")


# ── 11. The config copy ───────────────────────────────────────────────────────

func test_the_fortress_copies_its_death_tuning_from_the_config() -> void:
	var cfg: SpaceFortressConfig = _fortress.config
	assert_not_null(cfg, "the fortress ships with a config")
	assert_eq(_fortress.death_duration, cfg.death_sequence_duration,
		"the fortress must copy the shipped duration")
	assert_eq(cfg.death_sequence_duration, 2.4, "the shipped .tres value")
	assert_eq(cfg.death_blast_count, 10, "the shipped .tres value")
	assert_eq(_sequence()._blast_count, 10, "the sequence copied the shipped blast count")


## The NODE defaults must differ from the shipped values, or the copy test above would pass even if the copy were deleted. (The config
## script's own defaults already equal the shipped .tres, so the honest check is on the two nodes that copy it.)
func test_the_node_defaults_differ_from_the_shipped_values() -> void:
	var fresh := FORTRESS_SCENE.instantiate() as SpaceFortress
	var fresh_duration := fresh.death_duration
	fresh.free()
	assert_eq(fresh_duration, 0.0,
		"the fortress's own default is the honest fallback: behave exactly as BaseEnemy")
	assert_ne(fresh_duration, SHIPPED.death_sequence_duration, "the node default must not equal the shipped value")

	var seq := BossDeathSequence.new()
	var fresh_count := seq._blast_count
	seq.free()
	assert_eq(fresh_count, 3, "the sequence's script default, deliberately not the shipped 10")
	assert_ne(fresh_count, SHIPPED.death_blast_count, "the node default must not equal the shipped value")


func test_shortening_the_fortress_duration_does_not_write_back_to_the_config() -> void:
	var before: float = _fortress.config.death_sequence_duration
	_fortress.death_duration = 0.05
	assert_eq(_fortress.config.death_sequence_duration, before,
		"writing the node's copied field must not touch the fortress's config resource at all")


# ── 12. The host contract ─────────────────────────────────────────────────────

func test_a_host_without_death_started_gets_a_warning_and_no_crash() -> void:
	var host := Node2D.new()
	var seq := BossDeathSequence.new()
	host.add_child(seq)
	add_child_autofree(host)
	await get_tree().process_frame
	assert_false(seq.is_running(), "a host lacking the contract leaves the sequence disabled")
	assert_eq(seq._host, null, "no host is stored")
	seq._on_death_started()
	assert_false(seq.is_running(), "a death call on a disabled sequence is a no-op")
