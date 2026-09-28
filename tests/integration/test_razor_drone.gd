## The Razor Drone's behaviour spec (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.8.2, §4 row t10;
## task plan docs/plans/cmuj4y8rr007gp52xxs8dec5s/3-plan.md, rev 2 + amendments A1-A5).
##
## These are INTENT tests: they replace the Phase 1 port's 1:1 pins (DECISIONS, Phase 2: "Drone Interceptor
## 1:1 pins are retired"). The mover now has acceleration, braking and a turn cap, and the corridor is
## on (`constraint_mode = AUTO`), so every old "instant velocity" number was re-derived, not copied.
##
## Harness rules (same as test_swarm_drone.gd):
## - Dual-mode cases take a string label from `use_parameters`, and build the harness inside the body
##   (the default-argument leak trap in test_enemy_dual_mode.gd).
## - Drones are hand-ticked with `_tick()`, which calls `_physics_process` and then re-integrates the
##   position exactly (`move_and_slide()` reads its own delta when driven by hand). Hand ticks have no
##   physics step, so every dash MISSES unless a case emits the contact itself, or uses the one
##   real-physics world.
## - Every case seeds `rng_seed` or uses `force_next_choice()`, so no branch depends on a seed's luck.
## - The shipped config is read from the preloaded `.tres` and never written; a case that needs other
##   values writes the drone's PRIVATE copy (`drone.config`) before it enters the tree.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const Fixture := preload("res://tests/helpers/contact_fixture.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/razor_drone/razor_drone.tscn")
## Shared, read-only: never written (CLAUDE.md config rule).
const CONFIG: RazorDroneConfig = preload("res://assault/scenes/enemies/razor_drone/razor_drone_config.tres")

const DT := 1.0 / 60.0
const SEED := 4242
const SEEDS := [1, 2, 3, 4, 5, 42, 100]
const MID := Vector2(640.0, 360.0)
## `player_fighter.tscn`'s hurtbox radius (5 × 2.7), for the feint's clearance (task review B3).
const PLAYER_HURTBOX_RADIUS := 13.5

const P := RazorDroneBrain.Phase
const L := StateLight.State


func _harness(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = MID
	return h


func _spawn(h: RefCounted, pos: Vector2, configure: Callable = Callable(), rng_seed: int = SEED) -> RazorDrone:
	var drone := SCENE.instantiate() as RazorDrone
	drone.global_position = pos
	(drone.get_node("Brain") as RazorDroneBrain).rng_seed = rng_seed
	if configure.is_valid():
		configure.call(drone.config)
	h.root.add_child(drone)
	drone.set_physics_process(false)
	return drone


## A drone already on the orbit ring (it enters ORBIT on its first tick).
func _orbiter(h: RefCounted, rng_seed: int = SEED, bearing: float = 0.0) -> RazorDrone:
	# 1 px inside the ring, so float round-off never leaves it in ENTER.
	return _spawn(h, MID + Vector2.RIGHT.rotated(bearing) * (CONFIG.orbit_radius - 1.0), Callable(), rng_seed)


func _brain(drone: RazorDrone) -> RazorDroneBrain:
	return drone.get_node("Brain") as RazorDroneBrain


func _light(drone: RazorDrone) -> StateLight:
	return drone.get_node("StateLight") as StateLight


func _pool(drone: RazorDrone) -> BulletPool:
	return drone.get_node("BulletPool") as BulletPool


func _tick(drone: BaseEnemy) -> void:
	var before := drone.global_position
	drone._physics_process(DT)
	drone.global_position = before + drone.velocity * DT


func _phase_log(drone: RazorDrone) -> Array[int]:
	var log: Array[int] = []
	_brain(drone).phase_changed.connect(func(p: int) -> void: log.append(p))
	return log


## Ticks until `phase` is entered or `max_ticks` run out. Returns the ticks used, or -1.
func _tick_until(drone: RazorDrone, phase: int, max_ticks: int) -> int:
	for i in max_ticks:
		_tick(drone)
		if _brain(drone).phase == phase:
			return i + 1
	return -1


## Consecutive duplicates removed.
func _runs(states: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for s in states:
		if out.is_empty() or out[-1] != s:
			out.append(s)
	return out


func _contact_radius(drone: RazorDrone) -> float:
	var cs := drone.contact_hit_box.get_node("CollisionShape2D") as CollisionShape2D
	return (cs.shape as CircleShape2D).radius * cs.scale.x


# ── Config ───────────────────────────────────────────────────────────────────────────────────────

func test_config_pins_the_steady_state_turn() -> void:
	assert_true(CONFIG.overshoot_turn_rate * CONFIG.overshoot_speed <= CONFIG.acceleration,
		"the mover can follow the overshoot curve (turn_rate × overshoot_speed ≤ acceleration)")


## Epic review round 2 (B5): the steady-state pin ignores the time spent shedding dash speed.
func test_config_pins_the_turn_including_the_braking_phase() -> void:
	var shed := (CONFIG.dash_speed - CONFIG.overshoot_speed) / CONFIG.braking
	var turn := CONFIG.overshoot_turn_rate * (CONFIG.overshoot_max_seconds - shed)
	assert_gte(turn, deg_to_rad(60.0), "the overshoot can turn at least 60° after shedding the dash speed")


## Task review B3: below orbit_speed × orbit_radius the drone lags inside its ring by a seed-dependent
## amount, and the feint geometry stops being reproducible.
func test_config_keeps_the_orbit_catchable() -> void:
	assert_gte(CONFIG.orbit_correct_speed, CONFIG.orbit_speed * CONFIG.orbit_radius)


## Every value differs from what the scene authors, so a drone that copies nothing fails.
func test_config_flows_through_to_every_node() -> void:
	var h := _harness("open_space")
	var drone := _spawn(h, MID + Vector2(0, -300), func(c: RazorDroneConfig) -> void:
		c.max_health = 55
		c.collision_damage = 41
		c.acceleration = 777.0
		c.braking = 555.0
		c.max_turn_rate = 4.4
		c.pulse_damage = 7
		c.pulse_speed = 333.0
		c.orbit_radius = 111.0
		c.feint_clearance_px = 66.0
		c.engage_seconds = 2.0)
	_tick(drone)
	var mover := drone.get_node("EnemyMover") as EnemyMover
	var pattern := (drone.get_node("AttackController") as AttackController).pattern as AimedAttackPattern
	assert_eq(drone.health.max_health, 55)
	assert_eq(drone.health.current_health, 55)
	assert_eq(drone.contact_hit_box.damage, 41)
	assert_eq(drone.contact_profile.mode, ContactProfile.Mode.RAMMING)
	assert_eq(mover.acceleration, 777.0)
	assert_eq(mover.braking, 555.0)
	assert_eq(mover.max_turn_rate, 4.4)
	assert_eq(_brain(drone).braking, 555.0)
	assert_eq(_brain(drone).orbit_radius, 111.0)
	assert_eq(_brain(drone).feint_clearance_px, 66.0)
	assert_eq(_brain(drone).budget.seconds, 2.0)
	assert_not_null(pattern, "the pulse pattern is built")
	assert_eq(pattern.bullet_damage, 7)
	assert_eq(pattern.bullet_speed, 333.0)
	assert_eq(pattern.accuracy, 0.0)


## Two drones never share one pattern: it is built per instance, not a scene sub-resource.
func test_every_drone_gets_its_own_pulse_pattern() -> void:
	var h := _harness("open_space")
	var a := _spawn(h, MID + Vector2(0, -300))
	var b := _spawn(h, MID + Vector2(0, 300))
	var pa: AttackPatternResource = (a.get_node("AttackController") as AttackController).pattern
	var pb: AttackPatternResource = (b.get_node("AttackController") as AttackController).pattern
	assert_ne(pa, pb)


## The D5 re-pin: the corridor is on, resolved through the real lookup.
func test_the_scene_authors_the_d5_mover(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var drone := _orbiter(h)
	var mover := drone.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.constraint_mode, EnemyMover.ConstraintMode.AUTO)
	if mode == "assault":
		assert_true(mover.constraint is AssaultCorridorConstraint, "Assault resolves the corridor")
	else:
		assert_null(mover.constraint, "Open Space has no constraint")
	var attack := drone.get_node("AttackController") as AttackController
	assert_true(attack.driven_by_brain, "the controller never fires on its own timer")
	assert_false(attack.enabled)
	assert_eq(_brain(drone).attack, attack, "the brain found its AttackController sibling")


# ── ENTER / ORBIT ────────────────────────────────────────────────────────────────────────────────

func test_no_player_requests_zero() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var drone := SCENE.instantiate() as RazorDrone
	drone.global_position = Vector2(500, 500)
	container.add_child(drone)
	drone.set_physics_process(false)
	_tick(drone)
	assert_eq(drone.velocity, Vector2.ZERO)


func test_enter_accelerates_toward_the_player(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var drone := _spawn(h, MID + Vector2(-400, 0))
	_tick(drone)
	assert_almost_eq(drone.velocity.x, CONFIG.acceleration * DT, 0.01, "%s: one tick of acceleration toward the player" % mode)
	assert_almost_eq(drone.velocity.y, 0.0, 0.01)
	for _i in 20:
		_tick(drone)
	assert_almost_eq(drone.velocity.length(), CONFIG.approach_speed, 0.5, "%s: then approach_speed" % mode)
	assert_eq(_brain(drone).phase, P.ENTER)


## From 0.5 s after ORBIT entry until the orbit first ends (task review A2).
func test_orbit_holds_the_radius(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	for s in SEEDS:
		var drone := _orbiter(h, s, float(s))
		var brain := _brain(drone)
		_tick(drone)
		assert_eq(brain.phase, P.ORBIT, "sanity: on the ring")
		var samples := 0
		var ticks := 1
		while brain.phase == P.ORBIT and ticks < 400:
			_tick(drone)
			ticks += 1
			if ticks <= 30 or brain.phase != P.ORBIT:
				continue
			samples += 1
			var dist := drone.global_position.distance_to(MID)
			assert_between(dist, CONFIG.orbit_radius - 15.0, CONFIG.orbit_radius + 15.0,
				"%s seed %d: the orbit holds its radius" % [mode, s])
		assert_gt(samples, 20, "sanity: enough orbit to measure")
		drone.free()


# ── REVERSE ──────────────────────────────────────────────────────────────────────────────────────

func test_the_reversal_passes_through_zero(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var drone := _orbiter(h)
	var brain := _brain(drone)
	brain.force_next_choice(&"reverse")
	for _i in 60:
		_tick(drone)  # settle before the window can end (it is at least 1 s)
	assert_eq(brain.phase, P.ORBIT, "sanity: still orbiting")
	assert_gt(_tick_until(drone, P.REVERSE, 90), 0, "the forced reversal starts")
	var d := brain.orbit_dir
	var s := CONFIG.orbit_speed
	var ramp_step := 2.0 * s / CONFIG.reverse_seconds * DT
	var omegas: Array[float] = [brain.angular_speed]
	var actual: Array[float] = []
	var max_dv := 0.0
	var limit := maxf(CONFIG.acceleration, CONFIG.braking) * DT + 0.001
	for _i in 60:
		var v0 := drone.velocity
		_tick(drone)
		max_dv = maxf(max_dv, (drone.velocity - v0).length())
		if brain.phase == P.REVERSE:
			omegas.append(brain.angular_speed)
		var rel := drone.global_position - MID
		actual.append(rel.cross(drone.velocity) / rel.length_squared())
	assert_almost_eq(omegas[0], d * s, ramp_step + 0.001, "%s: starts at the old sense" % mode)
	var min_abs := INF
	for i in range(1, omegas.size()):
		assert_lte(omegas[i] * d, omegas[i - 1] * d + 0.000001, "monotonic ramp")
		assert_lte(absf(omegas[i] - omegas[i - 1]), ramp_step + 0.000001, "no step bigger than the ramp")
		min_abs = minf(min_abs, absf(omegas[i]))
	assert_lte(min_abs, ramp_step, "%s: the anchor's angular speed passes through zero" % mode)
	assert_almost_eq(brain.angular_speed, -d * s, 0.000001, "ends in the opposite sense")
	assert_eq(brain.orbit_dir, -d, "orbit_dir flipped")
	# The body itself: its angular velocity changes sign, and never by a velocity snap.
	assert_gt(actual[0] * d, 0.0, "%s: the body starts turning in the old sense" % mode)
	assert_lt(actual[-1] * d, 0.0, "%s: and ends in the new one" % mode)
	assert_lte(max_dv, limit, "%s: per-tick |Δv| within the mover's limits (never instant)" % mode)


## Task review N2: a reversal bars the next one until an attack begins.
func test_no_second_reversal_before_an_attack() -> void:
	var h := _harness("open_space")
	var drone := _spawn(h, MID + Vector2(CONFIG.orbit_radius, 0), func(c: RazorDroneConfig) -> void: c.reverse_chance = 1.0)
	var log := _phase_log(drone)
	var brain := _brain(drone)
	for _i in 600:
		_tick(drone)
		if brain.phase == P.WINDUP or brain.phase == P.FEINT_WINDUP:
			break
	assert_eq(log.count(P.REVERSE), 1, "exactly one reversal before the attack")
	assert_true(brain.phase == P.WINDUP or brain.phase == P.FEINT_WINDUP, "the roll after it attacks")


# ── FEINT ────────────────────────────────────────────────────────────────────────────────────────

## Runs a forced fake from a settled orbit. Returns what the cases below assert on.
func _run_fake(h: RefCounted, rng_seed: int = SEED, bearing: float = 0.0) -> Dictionary:
	var drone := _orbiter(h, rng_seed, bearing)
	var brain := _brain(drone)
	brain.force_next_choice(&"fake")
	var log := _phase_log(drone)
	var out := {"drone": drone, "log": log, "lights": [] as Array[int], "armed": false, "min_dist": INF,
		"charging_ticks": 0, "lunge_bearing": 0.0, "end_bearing": 0.0, "lunge_side": 0.0}
	brain.phase_changed.connect(func(p: int) -> void:
		if p == P.FEINT_LUNGE:
			out["lunge_bearing"] = (drone.global_position - MID).angle()
			out["lunge_side"] = brain.lunge_side
		elif p == P.WINDUP:
			out["end_bearing"] = (drone.global_position - MID).angle())
	assert_gt(_tick_until(drone, P.FEINT_WINDUP, 200), 0, "sanity: the fake starts")
	var lights: Array[int] = [_light(drone).get_state()]
	var charging := 1
	while brain.phase != P.WINDUP and lights.size() < 300:
		_tick(drone)
		if brain.phase == P.WINDUP:
			break
		lights.append(_light(drone).get_state())
		if brain.phase == P.FEINT_WINDUP:
			charging += 1
		if drone.contact_profile.is_armed():
			out["armed"] = true
		if brain.phase == P.FEINT_LUNGE or brain.phase == P.FEINT_BRAKE:
			out["min_dist"] = minf(out["min_dist"], drone.global_position.distance_to(MID))
	out["lights"] = lights
	out["charging_ticks"] = charging
	return out


func test_the_fake_never_commits_or_arms(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var r := _run_fake(h)
	var drone: RazorDrone = r["drone"]
	assert_eq(_brain(drone).phase, P.WINDUP, "%s: the fake hands over to a real wind-up" % mode)
	assert_false((r["lights"] as Array).has(L.COMMIT), "%s: a fake never shows white" % mode)
	assert_false(r["armed"], "%s: a fake never arms the contact" % mode)
	assert_eq(_runs(r["lights"]), [L.CHARGING, L.OFF] as Array[int], "%s: yellow, then dark for the lunge and brake" % mode)
	var expected := int(round(CONFIG.windup_seconds * CONFIG.fake_windup_scale / DT))
	assert_between(r["charging_ticks"], expected - 1, expected + 1, "%s: the fake telegraphs for 1.5× the wind-up" % mode)


## A1: the sweep is measured from the lunge's start (the point the feint holds at).
func test_the_fake_passes_beside_and_ends_on_the_far_side(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var r := _run_fake(h)
	var drone: RazorDrone = r["drone"]
	var sweep := angle_difference(r["lunge_bearing"], r["end_bearing"])
	assert_gt(absf(sweep), deg_to_rad(120.0), "%s: ends > 120° round (swept %.1f°)" % [mode, rad_to_deg(sweep)])
	assert_gte(r["min_dist"], _contact_radius(drone) + PLAYER_HURTBOX_RADIUS,
		"%s: the lunge passes beside the player, not through (closest %.1f px)" % [mode, r["min_dist"]])
	var log: Array[int] = r["log"]
	var i := log.find(P.FEINT_WINDUP)
	assert_eq(log.slice(i, i + 4), [P.FEINT_WINDUP, P.FEINT_LUNGE, P.FEINT_BRAKE, P.WINDUP] as Array[int],
		"%s: WINDUP at once, no orbit leg" % mode)
	assert_eq(_brain(drone).orbit_dir, -r["lunge_side"], "the new orbit continues the sweep")
	assert_eq(signf(sweep), _brain(drone).orbit_dir, "%s: the sweep ran in the new orbit's sense" % mode)


func test_the_feint_brake_cap() -> void:
	var h := _harness("open_space")
	var drone := _orbiter(h)
	var brain := _brain(drone)
	var mover := drone.get_node("EnemyMover") as EnemyMover
	brain.force_next_choice(&"fake")
	# A5: a brake that cannot stop — set on the mover only once braking starts, so the hold before it
	# is untouched.
	brain.phase_changed.connect(func(p: int) -> void:
		if p == P.FEINT_BRAKE:
			mover.braking = 1.0)
	assert_gt(_tick_until(drone, P.FEINT_BRAKE, 300), 0, "sanity: reaches the brake")
	var ticks := _tick_until(drone, P.WINDUP, 120)
	var expected := int(round(RazorDroneBrain.FEINT_BRAKE_MAX_SECONDS / DT))
	assert_between(ticks, expected - 1, expected + 1, "a brake that cannot finish hands over at the cap")


# ── REAL DASH ────────────────────────────────────────────────────────────────────────────────────

func test_the_real_dash_is_charging_commit_armed(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var drone := _orbiter(h)
	var brain := _brain(drone)
	brain.force_next_choice(&"real")
	assert_gt(_tick_until(drone, P.WINDUP, 200), 0, "sanity: winds up")
	var lights: Array[int] = [_light(drone).get_state()]
	while brain.phase != P.RETURN and lights.size() < 300:
		_tick(drone)
		lights.append(_light(drone).get_state())
		assert_eq(drone.contact_profile.is_armed(), brain.phase == P.DASH, "%s: armed exactly in DASH" % mode)
	var runs := _runs(lights)
	assert_eq(runs.slice(0, 3), [L.CHARGING, L.COMMIT, L.ARMED] as Array[int], "%s: yellow, white, red" % mode)
	var charging := lights.count(L.CHARGING)
	var commit := lights.count(L.COMMIT)
	assert_between(charging, int(CONFIG.windup_seconds / DT) - 1, int(CONFIG.windup_seconds / DT) + 1, "%s: 0.5 s yellow" % mode)
	assert_between(commit, int(CONFIG.commit_flash_seconds / DT) - 1, int(CONFIG.commit_flash_seconds / DT) + 2, "%s: 0.12 s white" % mode)


func test_dash_direction_is_the_locked_prediction(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.velocity = Vector2(100, 0)
	var drone := _orbiter(h)
	var brain := _brain(drone)
	brain.force_next_choice(&"real")
	var at_dash := [Vector2.ZERO]
	brain.phase_changed.connect(func(p: int) -> void:
		if p == P.DASH:
			at_dash[0] = drone.global_position)
	assert_gt(_tick_until(drone, P.DASH, 300), 0, "sanity: dashes")
	var locked := MID + Vector2(100, 0) * CONFIG.dash_prediction_time
	var expected: Vector2 = (locked - at_dash[0]).normalized()
	assert_almost_eq(drone.velocity.normalized().x, expected.x, 0.001, mode)
	assert_almost_eq(drone.velocity.normalized().y, expected.y, 0.001, mode)
	assert_almost_eq(drone.velocity.length(), CONFIG.dash_speed, 0.01)
	assert_almost_eq(brain.dash_direction.x, expected.x, 0.001)


# ── OVERSHOOT, pulse, survival ───────────────────────────────────────────────────────────────────

## A dash straight through a stationary player from (-130, 0): the curve starts with the player right
## behind the drone.
func _dash_through(h: RefCounted) -> RazorDrone:
	var drone := _spawn(h, MID + Vector2(-CONFIG.orbit_radius, 0))
	_brain(drone).enter_phase(P.DASH)
	return drone


func test_the_overshoot_curves_toward_the_player() -> void:
	var h := _harness("open_space")
	var drone := _dash_through(h)
	var brain := _brain(drone)
	var cap := CONFIG.overshoot_turn_rate * DT + 0.001
	var ticks := 0
	var guard := 0
	while brain.phase != P.RETURN and guard < 300:
		guard += 1
		var v0 := drone.velocity
		var bearing: Vector2 = MID - drone.global_position
		_tick(drone)
		if brain.phase != P.OVERSHOOT:
			continue
		ticks += 1
		var change := v0.angle_to(drone.velocity)
		assert_lte(absf(change), cap, "per-tick heading change within overshoot_turn_rate·dt")
		assert_gte(change * v0.angle_to(bearing), -0.000001, "turns toward the player's bearing, never away")
		assert_gte(drone.velocity.length(), 0.5 * CONFIG.overshoot_speed, "never slows below half overshoot_speed")
	assert_gt(ticks, 30, "sanity: the overshoot ran")
	assert_eq(brain.phase, P.RETURN, "it ends in RETURN")
	assert_gte(absf(Vector2.RIGHT.angle_to(drone.velocity)), deg_to_rad(60.0),
		"the overshoot turned at least 60° (a straight line turns 0)")


func test_the_overshoot_keeps_moving_inside_the_corridor() -> void:
	var h := _harness("assault")
	var drone := _dash_through(h)
	var brain := _brain(drone)
	var log := _phase_log(drone)
	for _i in 300:
		_tick(drone)
		if brain.phase == P.OVERSHOOT:
			assert_gte(drone.velocity.length(), 0.5 * CONFIG.overshoot_speed, "never stops mid-corridor")
		if brain.phase == P.RETURN:
			break
	assert_eq(log.slice(0, 2), [P.OVERSHOOT, P.RETURN] as Array[int], "DASH → OVERSHOOT → RETURN")


func _flying_bullets(h: RefCounted) -> Array[EnemyBullet]:
	var out: Array[EnemyBullet] = []
	for c in h.root.get_children():
		if c is EnemyBullet:
			out.append(c)
	return out


func test_a_miss_fires_exactly_one_pulse(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var drone := _dash_through(h)
	var brain := _brain(drone)
	var pool := _pool(drone)
	var size := pool.get_child_count()
	assert_eq(size, 4, "sanity: a full pool")
	assert_gt(_tick_until(drone, P.OVERSHOOT, 120), 0, "sanity: the dash ends")
	assert_eq(brain.pulses_fired, 1, "%s: one pulse at OVERSHOOT entry" % mode)
	assert_eq(size - pool.get_child_count(), 1, "%s: exactly one bullet left the pool" % mode)
	var bullets := _flying_bullets(h)
	assert_eq(bullets.size(), 1, "the pulse flies in the drone's container (D4)")
	if bullets.size() == 1:
		var bullet := bullets[0]
		assert_eq((bullet.get_node("HitBox") as HitBox).damage, CONFIG.pulse_damage)
		assert_eq(bullet.speed, CONFIG.pulse_speed)
		var dir := Vector2.RIGHT.rotated(bullet.rotation + PI / 2.0)
		var to_player := (MID - bullet.global_position).normalized()
		assert_almost_eq(dir.dot(to_player), 1.0, 0.001, "aimed at the player")
	_tick_until(drone, P.RETURN, 200)
	assert_eq(brain.pulses_fired, 1, "%s: still one pulse after the curve" % mode)
	assert_eq(size - pool.get_child_count(), 1)


func test_a_hit_fires_no_pulse(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var drone := _dash_through(h)
	var brain := _brain(drone)
	_tick(drone)
	assert_eq(brain.phase, P.DASH, "sanity: dashing")
	var area := Area2D.new()
	add_child_autofree(area)
	drone.contact_hit_box.area_entered.emit(area)
	assert_true(brain.dash_hit, "%s: the contact marks the dash as a hit" % mode)
	_tick_until(drone, P.RETURN, 200)
	assert_eq(brain.pulses_fired, 0, "%s: a hit fires no pulse" % mode)
	assert_eq(_pool(drone).get_child_count(), 4, "no bullet left the pool")


func test_contact_outside_the_dash_is_ignored() -> void:
	var h := _harness("open_space")
	var drone := _orbiter(h)
	var brain := _brain(drone)
	for _i in 10:
		_tick(drone)
	assert_eq(brain.phase, P.ORBIT, "sanity: orbiting")
	var made := [0]
	drone.contact_profile.contact_made.connect(func(_a: Area2D) -> void: made[0] += 1)
	var area := Area2D.new()
	add_child_autofree(area)
	drone.contact_hit_box.area_entered.emit(area)
	assert_eq(made[0], 0, "RAMMING is unarmed outside the dash")
	assert_false(brain.dash_hit)
	assert_eq(drone.health.current_health, CONFIG.max_health, "a touch never hurts the drone itself")
	assert_false(drone.is_queued_for_deletion())


func test_the_drone_survives_its_dash(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	for hit in [false, true]:
		var drone := _dash_through(h)
		var brain := _brain(drone)
		_tick(drone)
		if hit:
			var area := Area2D.new()
			add_child_autofree(area)
			drone.contact_hit_box.area_entered.emit(area)
		var ticks := _tick_until(drone, P.ORBIT, 240)
		assert_gt(ticks, 0, "%s hit=%s: back in ORBIT within 4 s" % [mode, hit])
		assert_false(drone.is_queued_for_deletion(), "%s hit=%s: survives" % [mode, hit])
		assert_eq(drone.health.current_health, CONFIG.max_health)
		drone.free()


# ── Real physics: the contact profile against a real player hurtbox ──────────────────────────────

func test_a_real_dash_hurts_a_real_player_and_orbit_contact_does_not() -> void:
	var world := Node2D.new()
	world.position = Vector2(120, 80)
	add_child_autofree(world)
	var player_pos := Vector2(300, 200)
	var player := Fixture.build_player(player_pos)
	player.add_to_group(&"player")
	world.add_child(player)
	var health := player.get_node("Health") as Health
	var drone := SCENE.instantiate() as RazorDrone
	drone.position = player_pos + Vector2(CONFIG.orbit_radius, 0)
	_brain(drone).rng_seed = SEED
	world.add_child(drone)
	await wait_physics_frames(2)
	assert_eq(_brain(drone).phase, P.ORBIT, "sanity: orbiting")
	for _i in 10:
		drone.position = player_pos
		await wait_physics_frames(1)
	assert_eq(health.current_health, Fixture.PLAYER_MAX_HEALTH, "touching an orbiting Razor deals 0")
	drone.set_physics_process(false)
	drone.position = player_pos
	_brain(drone).enter_phase(P.DASH)
	await wait_physics_frames(3)
	assert_eq(health.current_health, Fixture.PLAYER_MAX_HEALTH - CONFIG.collision_damage, "a dash hits for collision_damage")
	assert_true(_brain(drone).dash_hit, "and the brain knows it hit")
	assert_true(is_instance_valid(drone) and not drone.is_queued_for_deletion(), "the drone survives the hit")


# ── Assault: side lane, inner rect, budget ───────────────────────────────────────────────────────

func _dash_lane_angle(mode: String, choice: StringName, rng_seed: int) -> float:
	var h := _harness(mode)
	var drone := _orbiter(h, rng_seed, float(rng_seed))
	_brain(drone).force_next_choice(choice)
	assert_gt(_tick_until(drone, P.DASH, 500), 0, "%s seed %d: dashes" % [mode, rng_seed])
	var angle := RazorDroneBrain.lane_angle_deg(_brain(drone).dash_direction)
	h.root.get_parent().remove_child(h.root)  # detach so the next world cannot see this camera/player
	h.root.queue_free()
	return angle


func test_the_assault_dash_bearing_is_in_the_side_lane() -> void:
	var outside_in_open_space := 0
	for s in SEEDS:
		var angle := _dash_lane_angle("assault", &"real", s)
		assert_between(angle, CONFIG.side_lane_min_deg, CONFIG.side_lane_max_deg, "seed %d: the dash comes from a side lane" % s)
		var open_angle := _dash_lane_angle("open_space", &"real", s)
		if open_angle < CONFIG.side_lane_min_deg or open_angle > CONFIG.side_lane_max_deg:
			outside_in_open_space += 1
	assert_gt(outside_in_open_space, 0, "control: without the corridor the same seeds dash from outside the lane")


## Task review B4: the lunge side is chosen so the far-side dash lands in a lane too.
func test_the_assault_post_feint_dash_is_in_the_side_lane() -> void:
	for s in SEEDS:
		var angle := _dash_lane_angle("assault", &"fake", s)
		assert_between(angle, CONFIG.side_lane_min_deg, CONFIG.side_lane_max_deg, "seed %d: the post-feint dash comes from a side lane" % s)


## The player 50 px inside the corridor's left edge: an unclamped orbit would sit 80 px outside it.
func test_the_orbit_centre_stays_inside_the_shrunk_inner_rect(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var visible := AssaultCorridorConstraint.new()._visible_rect()
	var player_pos := Vector2(visible.position.x + 50.0, 360.0)
	h.player.global_position = player_pos
	var drone := _spawn(h, player_pos + Vector2(CONFIG.orbit_radius, 0))
	var brain := _brain(drone)
	var inner := visible.grow(-CONFIG.orbit_radius)
	for _i in 180:
		_tick(drone)
		if mode == "assault":
			var c := brain.orbit_centre
			assert_true(c.x >= inner.position.x - 0.01 and c.x <= inner.end.x + 0.01
				and c.y >= inner.position.y - 0.01 and c.y <= inner.end.y + 0.01,
				"the orbit centre %s stays inside %s" % [c, inner])
			assert_gt(c.x, player_pos.x, "the clamp is live")
		else:
			assert_eq(brain.orbit_centre, player_pos, "control: Open Space orbits the player itself")


func test_the_assault_budget_exit() -> void:
	var h := _harness("assault")
	var drone := _orbiter(h)
	var brain := _brain(drone)
	var disengage_tick := -1
	var freed_tick := -1
	for i in int((CONFIG.engage_seconds + 6.0) / DT):
		_tick(drone)
		if disengage_tick < 0 and brain.phase == P.DISENGAGE:
			disengage_tick = i + 1
		if drone.is_queued_for_deletion():
			freed_tick = i + 1
			break
	assert_gte(disengage_tick, int(CONFIG.engage_seconds / DT), "never before engage_seconds")
	assert_gt(freed_tick, 0, "freed")
	assert_lte(freed_tick - disengage_tick, int(4.0 / DT), "gone within 4 s of disengaging")
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := drone.global_position
	assert_true(pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y,
		"freed only once strictly outside the projectile world rect (at %s, rect %s)" % [pos, rect])
	assert_true((drone.get_node("EnemyMover") as EnemyMover).constraint_released(), "the corridor was released")


## Task review N4 / N9: expiry waits for the boost; that dash's OVERSHOOT and pulse are skipped.
func test_budget_expiry_waits_for_the_dash_to_end() -> void:
	var h := _harness("assault")
	var drone := _spawn(h, MID + Vector2(-CONFIG.orbit_radius, 0), func(c: RazorDroneConfig) -> void: c.engage_seconds = 0.2)
	var brain := _brain(drone)
	var log := _phase_log(drone)
	_tick(drone)
	brain.enter_phase(P.DASH)
	var dash_ticks := 0
	while brain.phase == P.DASH and dash_ticks < 120:
		_tick(drone)
		dash_ticks += 1
	assert_gt(dash_ticks * DT, 0.2, "sanity: the budget expired while dashing")
	var i := log.find(P.DASH)
	assert_eq(log.slice(i, i + 2), [P.DASH, P.DISENGAGE] as Array[int], "DISENGAGE on the first tick after the boost")
	assert_eq(brain.pulses_fired, 0, "the leaving drone fires no pulse")


func test_open_space_never_disengages() -> void:
	var h := _harness("open_space")
	var drone := _orbiter(h)
	var log := _phase_log(drone)
	for _i in 720:
		_tick(drone)
	assert_false(log.has(P.DISENGAGE), "no exit without an arena")
	assert_eq(_brain(drone).budget.remaining(), INF)
	assert_true(log.has(P.DASH) or log.has(P.FEINT_LUNGE), "sanity: it kept attacking")


# ── Robustness, facing ───────────────────────────────────────────────────────────────────────────

func test_the_player_vanishing_mid_attack_is_safe() -> void:
	var h := _harness("open_space")
	var drone := _orbiter(h)
	var brain := _brain(drone)
	var log := _phase_log(drone)
	brain.force_next_choice(&"real")
	assert_gt(_tick_until(drone, P.WINDUP, 200), 0, "sanity: winds up")
	h.root.remove_child(h.player)
	h.player.free()
	assert_gt(_tick_until(drone, P.RETURN, 300), 0, "the attack still runs to RETURN")
	assert_true(log.has(P.DASH) and log.has(P.OVERSHOOT), "through DASH and OVERSHOOT")
	for _i in 30:
		_tick(drone)
	assert_false(drone.is_queued_for_deletion())


## `max_turn_rate` 6 caps the first tick's lerp (7/s toward a nose-up target 90° away).
func test_the_first_tick_facing_is_capped() -> void:
	var h := _harness("open_space")
	h.player.global_position = Vector2(230, 0)
	var drone := _spawn(h, Vector2(130, 0))
	assert_eq(drone.rotation, 0.0, "sanity")
	_tick(drone)
	var target := Vector2.RIGHT.angle() + PI / 2.0  # nose-up art: sprite_forward_angle = -PI/2
	var expected := minf(lerp_angle(0.0, target, DT * 7.0), CONFIG.max_turn_rate * DT)
	assert_almost_eq(drone.rotation, expected, 0.001)
