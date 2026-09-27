## INTENT tests: the Swarm Drone's solo ram cycle, run in both the Open Space and the Assault
## harness (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.7.1 and §4 row t8b; task plan
## docs/plans/cmuj4y8rh0070p52xk6vzfvbe/3-plan.md, whose test table these cases follow).
##
## Two drive styles:
## - **Hand-ticked** (most cases): `set_physics_process(false)` and `_tick()`, which integrates the
##   position exactly from `velocity` (move_and_slide's delta drift — see test_enemy_dual_mode.gd).
##   No physics frame runs inside such a case, so no area overlap is ever reported: every burst is a
##   miss. The harness player is a `CharacterBody2D` whose `velocity` a case sets as a pure
##   prediction input — nothing integrates it.
## - **Real physics** (`wait_physics_frames`): the contact, CLOSE_IN and blast cases, against a real
##   player `HurtBox` → `Health` (tests/helpers/contact_fixture.gd).
##
## Dual-mode cases take a string label and build the harness in the body (the leak trap in
## test_enemy_dual_mode.gd's `test_orbit_behaviour_matches_the_constraint` doc).
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const Fixture := preload("res://tests/helpers/contact_fixture.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")
## Shared, read-only: never written (CLAUDE.md config rule).
const CONFIG: SwarmDroneConfig = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone_config.tres")

const DT := 1.0 / 60.0
const SEED := 4242
const MID := Vector2(640.0, 360.0)

const P := SwarmDroneBrain.Phase


func _harness(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	return h


## Instantiated, seeded, optionally reconfigured (on its PRIVATE config copy, before the tree), then
## parented under the harness and switched to hand-ticking.
func _spawn(h: RefCounted, pos: Vector2, configure: Callable = Callable(), rng_seed: int = SEED) -> SwarmDrone:
	var drone := SCENE.instantiate() as SwarmDrone
	drone.global_position = pos
	(drone.get_node("Brain") as SwarmDroneBrain).rng_seed = rng_seed
	if configure.is_valid():
		configure.call(drone.config)
	h.root.add_child(drone)
	drone.set_physics_process(false)
	return drone


func _brain(drone: SwarmDrone) -> SwarmDroneBrain:
	return drone.get_node("Brain") as SwarmDroneBrain


func _light(drone: SwarmDrone) -> StateLight:
	return drone.get_node("StateLight") as StateLight


func _tick(drone: BaseEnemy) -> void:
	var before := drone.global_position
	drone._physics_process(DT)
	drone.global_position = before + drone.velocity * DT


## Every phase the brain enters, in order.
func _phase_log(drone: SwarmDrone) -> Array[int]:
	var log: Array[int] = []
	_brain(drone).phase_changed.connect(func(p: int) -> void: log.append(p))
	return log


## Ticks until `phase` is entered or `max_ticks` run out. Returns the ticks used, or -1.
func _tick_until(drone: SwarmDrone, phase: int, max_ticks: int) -> int:
	for i in max_ticks:
		_tick(drone)
		if _brain(drone).phase == phase:
			return i + 1
	return -1


# ── Config ───────────────────────────────────────────────────────────────────────────────────────

func test_config_pins_the_steady_state_turn() -> void:
	assert_true(CONFIG.overshoot_turn_rate * CONFIG.max_speed <= CONFIG.acceleration,
		"the mover can follow the overshoot curve at steady state (rate × max_speed ≤ acceleration)")


## Review round 2 (B5): the steady-state pin ignores the time spent shedding burst speed. With
## braking 500 the overshoot turned only ~44°.
func test_config_pins_the_turn_including_the_braking_phase() -> void:
	var shed := (CONFIG.burst_speed - CONFIG.max_speed) / CONFIG.braking
	var turn := CONFIG.overshoot_turn_rate * (CONFIG.overshoot_seconds - shed)
	assert_gte(turn, deg_to_rad(60.0), "the overshoot can turn at least 60° after shedding the burst speed")


## Every value differs from what the scene authors, so a drone that copies nothing fails.
func test_config_flows_through_to_every_node() -> void:
	var h := _harness("open_space")
	var drone := _spawn(h, Vector2(0, -300), func(c: SwarmDroneConfig) -> void:
		c.max_health = 55
		c.collision_damage = 41
		c.blast_radius = 70.0
		c.blast_damage = 9
		c.braking = 777.0
		c.second_passes = 2
		c.engage_seconds = 2.0)
	_tick(drone)
	assert_eq(drone.health.max_health, 55)
	assert_eq(drone.health.current_health, 55)
	assert_eq(drone.contact_hit_box.damage, 41)
	assert_eq(drone.contact_profile.mode, ContactProfile.Mode.EXPLOSIVE)
	assert_eq(drone.contact_profile.blast_radius, 70.0)
	assert_eq(drone.contact_profile.blast_damage, 9)
	assert_eq((drone.get_node("EnemyMover") as EnemyMover).braking, 777.0)
	assert_eq(_brain(drone).braking, 777.0)
	assert_eq(_brain(drone).passes_left, 2)
	assert_eq(_brain(drone).budget.seconds, 2.0)


func test_budget_seconds_come_from_the_config() -> void:
	var h := _harness("assault")
	h.player.global_position = MID
	var drone := _spawn(h, MID + Vector2(0, -250), func(c: SwarmDroneConfig) -> void: c.engage_seconds = 2.0)
	var ticks := _tick_until(drone, P.DISENGAGE, 400)
	assert_between(ticks, 120, 121, "DISENGAGE exactly when 2.0 s of budget run out, not at the default 5.5 s")


# ── APPROACH / CLOSE_IN ──────────────────────────────────────────────────────────────────────────

func test_approach_corkscrews(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drone := _spawn(h, MID + Vector2(0, -700))
	var max_lateral := 0.0
	var reached := false
	for _i in 600:
		_tick(drone)
		if _brain(drone).phase != P.APPROACH:
			reached = _brain(drone).phase == P.CLOSE_IN
			break
		max_lateral = maxf(max_lateral, absf(drone.global_position.x - MID.x))
	assert_gt(max_lateral, 15.0, "%s: the approach swings off the straight line (a seek gives 0)" % mode)
	assert_true(reached, "%s: APPROACH hands over to CLOSE_IN" % mode)


func test_corkscrew_phase_comes_from_the_rng() -> void:
	var h := _harness("open_space")
	var a := _brain(_spawn(h, Vector2(0, -900), Callable(), 11)).cork_phase
	var b := _brain(_spawn(h, Vector2(100, -900), Callable(), 22)).cork_phase
	var c := _brain(_spawn(h, Vector2(200, -900), Callable(), 11)).cork_phase
	assert_ne(a, b, "different seeds, different phases")
	assert_eq(a, c, "control: the same seed gives the same phase, so the phase comes from rng")


func test_close_in_settles_on_the_ring(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drone := _spawn(h, MID + Vector2(350, 0))
	var min_dist := INF
	var close_in_ticks := 0
	var entered := false
	for _i in 400:
		_tick(drone)
		var phase := _brain(drone).phase
		if phase == P.CLOSE_IN:
			close_in_ticks += 1
			min_dist = minf(min_dist, drone.global_position.distance_to(MID))
		elif phase == P.WINDUP:
			entered = true
			break
	assert_true(entered, "%s: reaches WINDUP" % mode)
	assert_lt(close_in_ticks, int(SwarmDroneBrain.CLOSE_IN_MAX_SECONDS / DT),
		"%s: settled on the ring rather than timing out" % mode)
	assert_almost_eq(drone.global_position.distance_to(MID), SwarmDroneBrain.CLOSE_IN_RADIUS,
		SwarmDroneBrain.CLOSE_IN_TOLERANCE, "%s: winds up on the ring" % mode)
	assert_gte(min_dist, 150.0, "%s: never cuts inside the ring" % mode)


# ── WINDUP: the clamped prediction ───────────────────────────────────────────────────────────────

## Enters WINDUP from rest `distance` px left of a player moving perpendicular to the line of
## sight, runs it out, and returns [lead_time, aim, player position] as they stood at BURST entry.
func _windup_against(mode: String, distance: float) -> Array:
	var h := _harness(mode)
	h.player.global_position = MID
	h.player.velocity = Vector2(0, 150)
	var drone := _spawn(h, MID + Vector2(-distance, 0))
	var brain := _brain(drone)
	var at_burst: Array = []
	brain.phase_changed.connect(func(p: int) -> void:
		if p == P.BURST and at_burst.is_empty():
			at_burst.append_array([brain.lead_time, brain.aim]))
	brain.enter_phase(P.WINDUP)
	_tick_until(drone, P.BURST, 60)
	return at_burst


func test_a_far_target_clamps_the_lead_to_0_8(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var r := _windup_against(mode, 600.0)
	assert_eq(r.size(), 2, "%s: burst started" % mode)
	assert_almost_eq(float(r[0]), 0.8, 0.0001, "%s: 600/480 = 1.25 s clamps to 0.8" % mode)
	assert_almost_eq(r[1], MID + Vector2(0, 150) * 0.8, Vector2(0.01, 0.01),
		"%s: aim is the 0.8 s prediction (60 px past the 0.4 s one)" % mode)


func test_a_near_target_clamps_the_lead_to_0_4(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var r := _windup_against(mode, 60.0)
	assert_eq(r.size(), 2, "%s: burst started" % mode)
	assert_almost_eq(float(r[0]), 0.4, 0.0001, "%s: 60/480 = 0.125 s clamps to 0.4" % mode)
	assert_almost_eq(r[1], MID + Vector2(0, 150) * 0.4, Vector2(0.01, 0.01), "%s" % mode)


func test_a_mid_target_uses_distance_over_burst_speed(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var r := _windup_against(mode, 288.0)
	assert_eq(r.size(), 2, "%s: burst started" % mode)
	assert_almost_eq(float(r[0]), 0.6, 0.01, "%s: 288/480 = 0.6 s, inside the window" % mode)
	assert_almost_eq(r[1], MID + Vector2(0, 150) * float(r[0]), Vector2(0.01, 0.01), "%s" % mode)


## Epic §4 "a burst toward a stationary player uses facing" (reading recorded in DECISIONS): the
## prediction degenerates to the player's position, the burst goes straight at it, and the wind-up
## has swung the nose onto that line before the burst starts — from the natural ~90° entry.
func test_a_burst_at_a_stationary_player_goes_where_the_drone_faces(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drone := _spawn(h, MID + Vector2(300, 0))
	var brain := _brain(drone)
	var facing_at_burst := [Vector2.ZERO]
	brain.phase_changed.connect(func(p: int) -> void:
		if p == P.BURST:
			facing_at_burst[0] = brain._facing())
	assert_gt(_tick_until(drone, P.BURST, 400), 0, "%s: bursts" % mode)
	_tick(drone)
	var to_player := (MID - drone.global_position).normalized()
	var burst_dir := drone.velocity.normalized()
	assert_almost_eq(brain.aim, MID, Vector2(0.01, 0.01), "%s: stationary → aim is the player" % mode)
	assert_almost_eq(absf(to_player.angle_to(burst_dir)), 0.0, 0.01, "%s: bursts straight at the player" % mode)
	assert_almost_eq(absf(facing_at_burst[0].angle_to(burst_dir)), 0.0, 0.05,
		"%s: the nose points along the burst when it starts" % mode)


func test_the_windup_swings_the_nose_round_from_180_degrees(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drone := _spawn(h, MID + Vector2(250, 0))
	var brain := _brain(drone)
	# Nose pointing straight away from the player: dir (1, 0) → rotation = 0 − sprite_forward_angle.
	drone.rotation = Vector2.RIGHT.angle() - drone.sprite_forward_angle
	assert_almost_eq(brain._facing().angle_to(Vector2.RIGHT), 0.0, 0.0001, "sanity: facing away")
	var facing_at_burst := [Vector2.ZERO]
	brain.phase_changed.connect(func(p: int) -> void:
		if p == P.BURST:
			facing_at_burst[0] = brain._facing())
	brain.enter_phase(P.WINDUP)
	_tick_until(drone, P.BURST, 60)
	assert_almost_eq(absf(facing_at_burst[0].angle_to(Vector2.LEFT)), 0.0, 0.05,
		"%s: a 180° swing completes inside the 0.4 s wind-up" % mode)


# ── Lights, arming, hold ─────────────────────────────────────────────────────────────────────────

func test_windup_holds_yellow_then_burst_is_red_and_armed(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drone := _spawn(h, MID + Vector2(-250, 0))
	var brain := _brain(drone)
	drone.velocity = Vector2(0, 220)  # entering WINDUP at full speed, across the line of sight
	var speed_at_burst := [-1.0]
	brain.phase_changed.connect(func(p: int) -> void:
		if p == P.BURST:
			speed_at_burst[0] = drone.velocity.length())
	brain.enter_phase(P.WINDUP)
	while brain.phase == P.WINDUP:
		assert_eq(_light(drone).get_state(), StateLight.State.CHARGING, "%s: yellow while winding up" % mode)
		assert_false(drone.contact_profile.is_armed(), "%s: not armed while winding up" % mode)
		_tick(drone)
	assert_eq(brain.phase, P.BURST)
	assert_lte(speed_at_burst[0], 5.0, "%s: the hold has stopped the drone by the end of the wind-up" % mode)
	while brain.phase == P.BURST:
		assert_eq(_light(drone).get_state(), StateLight.State.ARMED, "%s: red while bursting" % mode)
		assert_true(drone.contact_profile.is_armed(), "%s: armed while bursting" % mode)
		_tick(drone)
	assert_eq(brain.phase, P.OVERSHOOT)
	assert_eq(_light(drone).get_state(), StateLight.State.OFF, "%s: light off on the overshoot" % mode)
	assert_false(drone.contact_profile.is_armed(), "%s: disarmed on the overshoot" % mode)


# ── OVERSHOOT: the curve, and exactly one second pass ────────────────────────────────────────────

## Burst along +x from O; the burst covers 27 ticks × 8 px = 216 px, so a player at O + (216, 200)
## is exactly 90° off the velocity heading when OVERSHOOT starts.
func test_the_overshoot_curves_toward_the_player() -> void:
	var h := _harness("open_space")
	var origin := Vector2(0, 0)
	var burst_ticks := int(round(CONFIG.burst_seconds / DT))
	h.player.global_position = origin + Vector2(burst_ticks * CONFIG.burst_speed * DT, 200)
	var drone := _spawn(h, origin)
	var brain := _brain(drone)
	brain.aim = origin + Vector2(200, 0)
	brain.enter_phase(P.BURST)
	var burst_heading := Vector2.RIGHT
	var cap := CONFIG.overshoot_turn_rate * DT + 0.001
	var overshoot_ticks := 0
	while brain.phase != P.WINDUP and brain.phase != P.REJOIN and overshoot_ticks < 200:
		var v0 := drone.velocity
		var bearing: Vector2 = h.player.global_position - drone.global_position
		_tick(drone)
		if brain.phase != P.OVERSHOOT:
			continue
		overshoot_ticks += 1
		var change := v0.angle_to(drone.velocity)
		assert_lte(absf(change), cap, "per-tick heading change within overshoot_turn_rate·dt")
		assert_gte(change * v0.angle_to(bearing), -0.000001, "turns toward the player's bearing, never away")
		assert_gte(drone.velocity.length(), 0.5 * CONFIG.max_speed, "never slows below half max_speed")
	assert_gt(overshoot_ticks, 40, "sanity: the overshoot ran")
	assert_gte(absf(burst_heading.angle_to(drone.velocity)), deg_to_rad(60.0),
		"the overshoot turned at least 60° by its end (a straight line turns 0)")


func test_the_overshoot_keeps_moving_inside_the_corridor() -> void:
	var h := _harness("assault")
	var origin := Vector2(500, 360)
	h.player.global_position = origin + Vector2(216, 200)
	var drone := _spawn(h, origin)
	var brain := _brain(drone)
	var log := _phase_log(drone)
	brain.aim = origin + Vector2(200, 0)
	brain.enter_phase(P.BURST)
	for _i in 200:
		_tick(drone)
		if brain.phase == P.OVERSHOOT:
			assert_gte(drone.velocity.length(), 0.5 * CONFIG.max_speed, "never stops mid-corridor")
		if brain.phase == P.WINDUP:
			break
	assert_eq(log.slice(0, 3), [P.BURST, P.OVERSHOOT, P.WINDUP] as Array[int], "BURST → OVERSHOOT → WINDUP")


## Hand-ticked, so every burst misses (no physics step, no overlap).
func test_a_miss_gets_exactly_one_more_pass(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID + Vector2(0, 250)
	var drone := _spawn(h, MID)
	var brain := _brain(drone)
	var log := _phase_log(drone)
	var bursts_at_rejoin := [-1]
	brain.phase_changed.connect(func(p: int) -> void:
		if p == P.REJOIN and bursts_at_rejoin[0] < 0:
			bursts_at_rejoin[0] = brain.burst_count)
	brain.enter_phase(P.WINDUP)
	_tick_until(drone, P.REJOIN, 400)
	assert_eq(log.slice(0, 7),
		[P.WINDUP, P.BURST, P.OVERSHOOT, P.WINDUP, P.BURST, P.OVERSHOOT, P.REJOIN] as Array[int],
		"%s: one attack, exactly one second pass, then rejoin" % mode)
	assert_eq(bursts_at_rejoin[0], 2, "%s: two bursts before REJOIN" % mode)


# ── Real physics: contact, CLOSE_IN, blast ───────────────────────────────────────────────────────

func _physics_world() -> Node2D:
	var c := Node2D.new()
	c.position = Vector2(120, 80)
	add_child_autofree(c)
	return c


func _real_player(container: Node2D, pos: Vector2) -> Health:
	var player := Fixture.build_player(pos)
	player.add_to_group(&"player")
	container.add_child(player)
	return player.get_node("Health") as Health


func _real_drone(container: Node2D, pos: Vector2, hold_still: bool) -> SwarmDrone:
	var drone := SCENE.instantiate() as SwarmDrone
	drone.position = pos
	_brain(drone).rng_seed = SEED
	container.add_child(drone)
	if hold_still:
		drone.set_physics_process(false)
	return drone


func test_contact_while_armed_detonates_and_dies_as_a_kill() -> void:
	var world := _physics_world()
	var health := _real_player(world, Vector2(300, 200))
	var drone := _real_drone(world, Vector2(300, 200), true)
	var detonations := [0]
	var killed := [false]
	drone.contact_profile.detonated.connect(func(_at: Vector2) -> void: detonations[0] += 1)
	drone.died.connect(func() -> void: killed[0] = drone.was_killed)
	await wait_physics_frames(3)
	_brain(drone).enter_phase(P.BURST)
	await wait_physics_frames(5)
	assert_eq(detonations[0], 1, "one detonation on contact")
	assert_true(killed[0], "died as a kill (was_killed), not an escape")
	assert_false(is_instance_valid(drone), "freed")
	assert_lt(health.current_health, Fixture.PLAYER_MAX_HEALTH, "the player was hurt")


## The brain runs for real: from 150 px it is in CLOSE_IN, and it is pushed onto the player's
## hurtbox every frame. Unarmed, touching deals nothing — a brain that armed outside BURST fails.
func test_touching_a_drone_in_close_in_deals_no_damage() -> void:
	var world := _physics_world()
	var player_pos := Vector2(300, 200)
	var health := _real_player(world, player_pos)
	var drone := _real_drone(world, player_pos + Vector2(150, 0), false)
	await wait_physics_frames(2)
	assert_eq(_brain(drone).phase, P.CLOSE_IN, "sanity: in CLOSE_IN")
	for _i in 10:
		drone.position = player_pos
		await wait_physics_frames(1)
		assert_eq(_brain(drone).phase, P.CLOSE_IN, "still in CLOSE_IN")
	assert_eq(health.current_health, Fixture.PLAYER_MAX_HEALTH, "touching an unarmed drone deals 0")
	assert_false(drone.contact_profile.is_armed())


## 40 px apart: contact box r13 + player r12 = 25 < 40 (no touch); blast r48 + 12 = 60 > 40 (hit).
func _shoot_drone_at_40px(armed: bool) -> int:
	var world := _physics_world()
	var player_pos := Vector2(300, 200)
	var health := _real_player(world, player_pos)
	var drone := _real_drone(world, player_pos + Vector2(40, 0), true)
	await wait_physics_frames(3)
	_brain(drone).enter_phase(P.BURST if armed else P.CLOSE_IN)
	await wait_physics_frames(2)
	drone.health.decrease(CONFIG.max_health)  # shot down
	await wait_physics_frames(5)
	return Fixture.PLAYER_MAX_HEALTH - health.current_health


func test_an_armed_drone_shot_within_blast_radius_hurts_the_player_by_blast_damage() -> void:
	var lost: int = await _shoot_drone_at_40px(true)
	assert_eq(lost, CONFIG.blast_damage, "only the blast reaches: exactly blast_damage")


func test_an_unarmed_drone_shot_within_blast_radius_deals_nothing() -> void:
	var lost: int = await _shoot_drone_at_40px(false)
	assert_eq(lost, 0, "no blast when shot unarmed")


# ── Assault exit ─────────────────────────────────────────────────────────────────────────────────

func test_the_assault_exit_starts_exactly_at_engage_seconds() -> void:
	var h := _harness("assault")
	h.player.global_position = MID
	var drone := _spawn(h, MID + Vector2(0, -260))
	var brain := _brain(drone)
	var ticks := 0
	var speed_at_expiry := -1.0
	for _i in 800:
		var v := drone.velocity.length()
		_tick(drone)
		ticks += 1
		if brain.phase == P.DISENGAGE:
			speed_at_expiry = v
			break
	assert_between(ticks, int(CONFIG.engage_seconds / DT), int(CONFIG.engage_seconds / DT) + 1,
		"DISENGAGE on the tick the budget expires — never before engage_seconds")
	assert_gte(brain.burst_count, 1, "sanity: it attacked during its engagement")
	assert_lte(speed_at_expiry, CONFIG.max_speed + 1.0, "no burst straddles the expiry")


## With only 2.0 s of budget, a drone that needs ~1.3 s of CLOSE_IN never has the 1.29 s an attack
## needs, so it never winds up; the open-space control (budget inactive) does.
func test_no_attack_starts_that_the_budget_cannot_finish() -> void:
	var h := _harness("assault")
	h.player.global_position = MID
	var drone := _spawn(h, MID + Vector2(350, 0), func(c: SwarmDroneConfig) -> void: c.engage_seconds = 2.0)
	var log := _phase_log(drone)
	_tick_until(drone, P.DISENGAGE, 300)
	assert_true(log.has(P.DISENGAGE), "disengaged")
	assert_false(log.has(P.WINDUP), "never wound up with too little budget left")


## The control for the case above: the same drone and geometry with no arena (budget inactive).
func test_the_same_drone_without_a_budget_does_wind_up() -> void:
	var control_h := _harness("open_space")
	control_h.player.global_position = MID
	var control := _spawn(control_h, MID + Vector2(350, 0), func(c: SwarmDroneConfig) -> void: c.engage_seconds = 2.0)
	assert_gt(_tick_until(control, P.WINDUP, 300), 0, "control: the same drone without a budget winds up")


func test_the_assault_exit_frees_only_outside_the_world_rect() -> void:
	var h := _harness("assault")
	h.player.global_position = MID + Vector2(0, 250)
	var drone := _spawn(h, MID)
	var brain := _brain(drone)
	var limit := int((CONFIG.engage_seconds + 3.4) / DT)
	var freed_at := -1
	for i in limit:
		_tick(drone)
		if drone.is_queued_for_deletion():
			freed_at = i
			break
	assert_eq(brain.phase, P.DISENGAGE, "left through DISENGAGE")
	assert_gt(freed_at, 0, "freed within engage_seconds + 3.4 s")
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := drone.global_position
	assert_true(pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y,
		"freed only once strictly outside the projectile world rect (at %s, rect %s)" % [pos, rect])
	assert_true(drone.get_node("EnemyMover").constraint_released(), "the corridor was released")


func test_open_space_never_disengages() -> void:
	var h := _harness("open_space")
	h.player.global_position = MID
	var drone := _spawn(h, MID + Vector2(0, -260))
	var log := _phase_log(drone)
	for _i in 720:
		_tick(drone)
	assert_false(log.has(P.DISENGAGE), "no exit without an arena")
	assert_eq(_brain(drone).budget.remaining(), INF)
	assert_gte(_brain(drone).burst_count, 2, "sanity: it kept attacking")


func test_a_below_screen_spawn_enters_the_corridor() -> void:
	var h := _harness("assault")
	h.player.global_position = MID
	var visible := AssaultCorridorConstraint.new()._visible_rect()
	var drone := _spawn(h, Vector2(640, 1300))
	assert_false(visible.has_point(drone.global_position), "sanity: spawned outside the visible rect")
	var entered := false
	for _i in 600:
		_tick(drone)
		if visible.has_point(drone.global_position):
			entered = true
			break
	assert_true(entered, "a below-screen spawn flies into the corridor")


## Same setup in both harnesses: a burst straight at a player 130 px above the bottom edge. Open
## Space flies past the edge; the corridor holds the Assault drone back.
func _max_y_of_a_burst_toward_the_bottom_edge(mode: String) -> float:
	var h := _harness(mode)
	h.player.global_position = Vector2(640, 1080)
	var drone := _spawn(h, Vector2(640, 950))
	var brain := _brain(drone)
	brain.enter_phase(P.WINDUP)
	var max_y := drone.global_position.y
	for _i in 100:
		_tick(drone)
		max_y = maxf(max_y, drone.global_position.y)
	# Detach this world so the next run cannot see its player or its ArenaCamera (autofree still frees it).
	h.root.get_parent().remove_child(h.root)
	return max_y


func test_the_corridor_filters_a_burst_toward_an_edge() -> void:
	var bottom := AssaultCorridorConstraint.new()._visible_rect().end.y
	var open_max := _max_y_of_a_burst_toward_the_bottom_edge("open_space")
	var assault_max := _max_y_of_a_burst_toward_the_bottom_edge("assault")
	assert_gt(open_max, bottom, "sanity: unconstrained, the burst crosses the bottom edge")
	assert_lt(assault_max, open_max, "the corridor holds the Assault drone back")


# ── Rails ────────────────────────────────────────────────────────────────────────────────────────

func test_a_rail_suspension_arms_the_profile_and_leaves_the_squad() -> void:
	var world := _physics_world()
	var cam := Camera2D.new()
	world.add_child(cam)
	cam.make_current()
	var squad := SquadController.new()
	var mate := Node2D.new()
	mate.position = Vector2(5000, 5000)
	world.add_child(mate)
	squad.join(mate)
	var drone := SCENE.instantiate() as SwarmDrone
	drone.position = Vector2(300, 200)
	drone.squad = squad
	world.add_child(drone)
	assert_true(squad.members().has(drone), "sanity: joined")
	var rail := EnemyPathMover.new()
	drone.add_child(rail)
	assert_true(drone.is_ai_suspended(), "the rail suspended the brain")
	assert_true(drone.contact_profile.is_armed(), "a rail drone hurts on contact, like the Kamikaze")
	assert_eq(_light(drone).get_state(), StateLight.State.ARMED, "and shows it")
	assert_false(squad.members().has(drone), "it left its squad")


# ── Squad calls (roles themselves are t8c) ───────────────────────────────────────────────────────

func _squad_drone(h: RefCounted, squad: SquadController) -> SwarmDrone:
	var drone := SCENE.instantiate() as SwarmDrone
	drone.global_position = MID
	_brain(drone).rng_seed = SEED
	drone.squad = squad
	h.root.add_child(drone)
	drone.set_physics_process(false)
	return drone


func test_a_sole_squad_member_claims_releases_and_keeps_its_lead() -> void:
	var h := _harness("open_space")
	h.player.global_position = MID + Vector2(0, 250)
	var squad := SquadController.new()
	var drone := _squad_drone(h, squad)
	var brain := _brain(drone)
	var probe := Node.new()
	autofree(probe)
	assert_eq(squad.role_of(drone), SquadController.Role.LEAD, "joined as LEAD")

	brain.enter_phase(P.WINDUP)
	var claimed := brain._claimed_side
	assert_gte(claimed, 0, "claimed a side on WINDUP entry")
	assert_ne(squad.claim_side(probe, claimed), claimed, "the side is latched to the drone")
	squad.release_side(probe)

	_tick_until(drone, P.OVERSHOOT, 60)
	assert_eq(squad.claim_side(probe, claimed), claimed, "released on OVERSHOOT")
	squad.release_side(probe)

	_tick_until(drone, P.REJOIN, 400)
	assert_eq(squad.role_of(drone), SquadController.Role.LEAD,
		"a sole member keeps LEAD (release_lead would pin it to REAR)")


func test_a_lead_with_a_mate_hands_the_lead_on_at_rejoin() -> void:
	var h := _harness("open_space")
	h.player.global_position = MID + Vector2(0, 250)
	var squad := SquadController.new()
	var mate := Node2D.new()
	mate.global_position = Vector2(5000, 5000)
	h.root.add_child(mate)
	squad.join(mate)
	var drone := _squad_drone(h, squad)
	assert_eq(squad.role_of(drone), SquadController.Role.LEAD, "sanity: the drone leads before its attack")
	_brain(drone).enter_phase(P.WINDUP)
	_tick_until(drone, P.REJOIN, 400)
	assert_ne(squad.role_of(drone), SquadController.Role.LEAD, "the finishing lead handed the token on")
	assert_eq(squad.role_of(mate), SquadController.Role.LEAD, "to its mate")
