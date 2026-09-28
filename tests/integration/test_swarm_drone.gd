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
	var brain := drone.get_node("Brain") as SwarmDroneBrain
	brain.rng_seed = rng_seed
	brain.start_engaged = true  # pre-t8d: every case here predates the hub idle (§ t8d below)
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
	assert_almost_eq(drone.global_position.distance_to(MID), _brain(drone).flank_distance,
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
	_brain(drone).start_engaged = true  # pre-t8d
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
	_brain(drone).start_engaged = true  # pre-t8d
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


# ══ t8c: squad behaviour (epic §2.7.2 / §4 row t8c; task plan docs/plans/cmuj4y8rj0074p52xqmin24gu) ══
#
# Hand-ticked unless stated: every drone is ticked each step, in join order. Budget rule (task plan
# review round 1 B1): in the Assault harness every drone leaves at 5.5 s and cannot wind up after
# ~4.2 s, so the long cases lift `engage_seconds` / `rear_engage_seconds` on each private config.
# "Frozen" adds `windup_seconds = 100`: the lead holds in WINDUP, no window opens, roles never rotate.

const R := SquadController.Role
const LONG_BUDGET := 1000.0


func _budget_rule(c: SwarmDroneConfig) -> void:
	c.engage_seconds = LONG_BUDGET
	c.rear_engage_seconds = LONG_BUDGET


func _frozen(c: SwarmDroneConfig) -> void:
	_budget_rule(c)
	c.windup_seconds = 100.0


## One drone per position, all on one new board, joined in array order. `configure` runs on each
## private config copy before the tree; `seeds` defaults to SEED + index.
func _squad_of(h: RefCounted, positions: Array, configure: Callable = Callable(), seeds: Array = []) -> Array[SwarmDrone]:
	var squad := SquadController.new()
	var out: Array[SwarmDrone] = []
	for i in positions.size():
		var drone := SCENE.instantiate() as SwarmDrone
		drone.global_position = positions[i]
		var brain := drone.get_node("Brain") as SwarmDroneBrain
		brain.rng_seed = int(seeds[i]) if i < seeds.size() else SEED + i
		brain.start_engaged = true  # pre-t8d
		if configure.is_valid():
			configure.call(drone.config)
		drone.squad = squad
		h.root.add_child(drone)
		drone.set_physics_process(false)
		out.append(drone)
	return out


func _tick_all(drones: Array[SwarmDrone]) -> void:
	for d in drones:
		if is_instance_valid(d) and not d.is_queued_for_deletion():
			_tick(d)


func _run(drones: Array[SwarmDrone], ticks: int) -> void:
	for _i in ticks:
		_tick_all(drones)


func _with_role(drones: Array[SwarmDrone], role: int) -> Array[SwarmDrone]:
	var out: Array[SwarmDrone] = []
	for d in drones:
		if is_instance_valid(d) and d.squad.role_of(d) == role:
			out.append(d)
	return out


## Five drones in a row 300 px above `centre`: the middle one is closest, so it leads.
func _row_of_five(centre: Vector2) -> Array:
	return [centre + Vector2(0, -300), centre + Vector2(-40, -300), centre + Vector2(40, -300),
		centre + Vector2(-80, -300), centre + Vector2(80, -300)]


## Where a FLANK's formation slot is right now (the brain's own formula).
func _flank_slot(drone: SwarmDrone, target_pos: Vector2) -> Vector2:
	var brain := _brain(drone)
	var side := 1.0 if drone.squad.role_of(drone) == R.FLANK_RIGHT else -1.0
	var heading := brain._heading_of(TargetInfo.player(get_tree()))
	return target_pos + (Vector2.RIGHT.rotated(side * deg_to_rad(brain.flank_angle_deg)) * brain.flank_distance).rotated(heading.angle())


func _in_tolerance(drone: SwarmDrone, target_pos: Vector2) -> bool:
	var brain := _brain(drone)
	if drone.squad.role_of(drone) == R.REAR:
		return absf(drone.global_position.distance_to(target_pos) - brain.rear_orbit_radius) <= 0.1 * brain.rear_orbit_radius
	return drone.global_position.distance_to(_flank_slot(drone, target_pos)) <= 30.0


# ── Config ───────────────────────────────────────────────────────────────────────────────────────

func test_config_keeps_the_rear_ring_catchable() -> void:
	assert_lte(CONFIG.rear_orbit_speed * CONFIG.rear_orbit_radius, 0.7 * CONFIG.max_speed,
		"the ring's tangential speed leaves the orbit correction headroom under max_speed (task plan D1)")


func test_config_rear_budget_never_exceeds_the_attackers() -> void:
	assert_lte(CONFIG.rear_engage_seconds, CONFIG.engage_seconds,
		"the §2.6 deadline uses engage_seconds, so a REAR may leave earlier, never later")


func test_squad_config_flows_through_to_the_brain() -> void:
	var h := _harness("open_space")
	var drone := _spawn(h, Vector2(0, -300), func(c: SwarmDroneConfig) -> void:
		c.rear_orbit_radius = 301.0
		c.rear_orbit_speed = 0.31
		c.flank_distance = 171.0
		c.flank_angle_deg = 55.0
		c.separation_radius = 41.0
		c.flock_nudge_cap = 0.21
		c.evade_radius = 77.0
		c.rear_engage_seconds = 3.3)
	var brain := _brain(drone)
	assert_eq(brain.rear_orbit_radius, 301.0)
	assert_eq(brain.rear_orbit_speed, 0.31)
	assert_eq(brain.flank_distance, 171.0)
	assert_eq(brain.flank_angle_deg, 55.0)
	assert_eq(brain.separation_radius, 41.0)
	assert_eq(brain.flock_nudge_cap, 0.21)
	assert_eq(brain.evade_radius, 77.0)
	assert_eq(brain.rear_engage_seconds, 3.3)


# ── FORM: the REAR ring ──────────────────────────────────────────────────────────────────────────

func test_rear_holds_the_orbit_radius(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drones := _squad_of(h, _row_of_five(MID), _frozen)
	var rears := _with_role(drones, R.REAR)
	assert_eq(rears.size(), 2, "%s: sanity: a squad of 5 has two REARs" % mode)
	_run(drones, 240)
	var worst := 0.0
	var angle_moved := 0.0
	var last_angle: float = drones[0].squad.rear_ring_angle
	for _i in 180:
		_tick_all(drones)
		for d in rears:
			assert_eq(_brain(d).phase, P.FORM, "%s: the REAR stays in FORM" % mode)
			worst = maxf(worst, absf(d.global_position.distance_to(MID) - CONFIG.rear_orbit_radius))
		angle_moved += absf(angle_difference(last_angle, drones[0].squad.rear_ring_angle))
		last_angle = drones[0].squad.rear_ring_angle
	assert_lte(worst, 0.1 * CONFIG.rear_orbit_radius, "%s: every REAR within ± 10 %% of the ring (worst %.1f px)" % [mode, worst])
	assert_almost_eq(angle_moved, CONFIG.rear_orbit_speed * 3.0, 0.02, "%s: the ring turns at rear_orbit_speed" % mode)
	var a := rears[0].global_position - MID
	var b := rears[1].global_position - MID
	assert_gt(absf(a.angle_to(b)), deg_to_rad(120.0), "%s: two REARs sit on opposite sides of the ring" % mode)


## Review round 1 B3 / round 2 A2: rear 0 (joined first, far away) is still approaching while rear 1
## is in FORM. The ring must still be initialised — a NAN angle would put rear 1 at NAN.
func test_a_rear_finds_the_ring_while_rear_0_is_still_approaching() -> void:
	var h := _harness("open_space")
	h.player.global_position = MID
	var far := MID + Vector2(0, -2000)
	var positions := [far, MID + Vector2(0, -200), MID + Vector2(-60, -200), MID + Vector2(60, -200), MID + Vector2(0, -290)]
	var drones := _squad_of(h, positions, _frozen)
	var squad: SquadController = drones[0].squad
	assert_eq(squad.role_of(drones[0]), R.REAR, "sanity: the far drone is a REAR")
	assert_eq(squad.rear_index(drones[0]), 0, "sanity: and it is rear 0 (joined first)")
	assert_eq(squad.rear_index(drones[4]), 1, "sanity: the near REAR is rear 1")
	var rear1 := drones[4]
	for _i in 240:
		_tick_all(drones)
		assert_true(rear1.velocity.is_finite() and rear1.global_position.is_finite(), "rear 1 stays finite")
	assert_eq(_brain(drones[0]).phase, P.APPROACH, "sanity: rear 0 is still approaching")
	assert_eq(_brain(rear1).phase, P.FORM)
	assert_almost_eq(rear1.global_position.distance_to(MID), CONFIG.rear_orbit_radius, 0.1 * CONFIG.rear_orbit_radius,
		"rear 1 is on the ring")


func test_the_rear_ring_centre_stays_inside_the_corridor() -> void:
	var h := _harness("assault")
	var inner := AssaultCorridorConstraint.new().inner_rect()
	var player_pos := Vector2(inner.get_center().x, inner.position.y + 100.0)
	h.player.global_position = player_pos
	var drones := _squad_of(h, _row_of_five(player_pos + Vector2(0, 600)), _frozen)
	var rears := _with_role(drones, R.REAR)
	var shrunk := inner.grow(-CONFIG.rear_orbit_radius)
	var centre := player_pos.clamp(shrunk.position, shrunk.end)
	assert_ne(centre, player_pos, "sanity: the centre was clamped")
	assert_true(shrunk.has_point(centre), "the ring centre is inside inner_rect() shrunk by the radius")
	_run(drones, 360)
	var worst_centre := 0.0
	var worst_player := 0.0
	for _i in 180:
		_tick_all(drones)
		for d in rears:
			worst_centre = maxf(worst_centre, absf(d.global_position.distance_to(centre) - CONFIG.rear_orbit_radius))
			worst_player = maxf(worst_player, absf(d.global_position.distance_to(player_pos) - CONFIG.rear_orbit_radius))
	assert_lte(worst_centre, 0.1 * CONFIG.rear_orbit_radius, "REARs hold the ring around the clamped centre (worst %.1f)" % worst_centre)
	assert_gt(worst_player, 0.1 * CONFIG.rear_orbit_radius, "boundary: measured from the player itself, they do not")


# ── Who attacks ──────────────────────────────────────────────────────────────────────────────────

## Per-drone phase entries with the step they happened on, and every WINDUP entry's role.
func _record(drones: Array[SwarmDrone], step: Array, log: Dictionary, windup_roles: Array) -> void:
	for d in drones:
		log[d] = []
		var drone := d
		_brain(d).phase_changed.connect(func(p: int) -> void:
			log[drone].append([step[0], p])
			if p == P.WINDUP:
				windup_roles.append(drone.squad.role_of(drone)))


func _first(log: Dictionary, d: SwarmDrone, p: int) -> int:
	for e in log[d]:
		if e[1] == p:
			return e[0]
	return -1


func test_flanks_wind_up_only_after_the_leads_burst(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drones := _squad_of(h, [MID + Vector2(0, -300), MID + Vector2(-60, -310), MID + Vector2(60, -310), MID + Vector2(0, -380)], _budget_rule)
	var lead := _with_role(drones, R.LEAD)[0]
	var flanks := _with_role(drones, R.FLANK_LEFT) + _with_role(drones, R.FLANK_RIGHT)
	assert_eq(flanks.size(), 2, "%s: sanity: two flanks" % mode)
	var step := [0]
	var log := {}
	var windup_roles := []
	_record(drones, step, log, windup_roles)
	for i in 600:
		step[0] = i
		_tick_all(drones)
	var burst := _first(log, lead, P.BURST)
	assert_gt(burst, -1, "%s: the lead burst" % mode)
	for f in flanks:
		var w := _first(log, f, P.WINDUP)
		assert_gt(w, -1, "%s: each flank answers the window" % mode)
		assert_gte(w, burst, "%s: a flank winds up only once the lead has committed" % mode)
	assert_false(windup_roles.has(R.REAR), "%s: no drone ever winds up while it is a REAR" % mode)
	assert_gt(windup_roles.size(), 3, "%s: sanity: several attacks happened" % mode)


func test_two_attackers_never_share_a_side(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drones := _squad_of(h, [MID + Vector2(0, -300), MID + Vector2(-60, -310), MID + Vector2(60, -310), MID + Vector2(0, -380)], _budget_rule)
	var most := 0
	for _i in 600:
		_tick_all(drones)
		var sides := []
		for d in drones:
			var b := _brain(d)
			if (b.phase == P.WINDUP or b.phase == P.BURST) and b._claimed_side >= 0:
				assert_false(sides.has(b._claimed_side), "%s: two attackers claimed the same side" % mode)
				sides.append(b._claimed_side)
		most = maxi(most, sides.size())
	assert_gte(most, 2, "%s: sanity: attackers overlapped, so the check could fail" % mode)


## Review round 2 A1: a lead demoted during its WINDUP must not open a window at its BURST.
func test_a_lead_demoted_during_windup_opens_no_window() -> void:
	var h := _harness("open_space")
	h.player.global_position = MID
	var drones := _squad_of(h, [MID + Vector2(0, -200), MID + Vector2(-60, -210), MID + Vector2(60, -210)], _budget_rule)
	var lead := drones[0]
	var squad: SquadController = lead.squad
	_brain(lead).enter_phase(P.WINDUP)
	var newcomer := SCENE.instantiate() as SwarmDrone
	newcomer.global_position = MID + Vector2(0, 20)
	newcomer.squad = squad
	h.root.add_child(newcomer)
	newcomer.set_physics_process(false)
	assert_eq(squad.role_of(newcomer), R.LEAD, "sanity: the closer newcomer took the lead")
	assert_ne(squad.role_of(lead), R.LEAD, "sanity: the old lead was demoted mid-WINDUP")
	assert_gt(_tick_until(lead, P.BURST, 60), 0, "the demoted drone still finishes its pass")
	assert_false(squad.attack_window_open, "but its burst opens no window for the new lead")


# ── Real physics: no contact damage in FORM ──────────────────────────────────────────────────────

func test_no_contact_damage_while_in_form(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	if mode == "assault":
		var cam := ArenaCamera.new()
		cam.global_position = MID
		world.add_child(cam)
	var health := _real_player(world, MID)
	var squad := SquadController.new()
	var drones: Array[SwarmDrone] = []
	for pos in [MID + Vector2(0, -200), MID + Vector2(-60, -210), MID + Vector2(60, -210), MID + Vector2(0, -290)]:
		var drone := SCENE.instantiate() as SwarmDrone
		drone.position = pos
		_brain(drone).rng_seed = SEED
		_brain(drone).start_engaged = true  # pre-t8d
		_frozen(drone.config)
		drone.squad = squad
		world.add_child(drone)
		drones.append(drone)
	await wait_physics_frames(30)
	var formers := _with_role(drones, R.FLANK_LEFT) + _with_role(drones, R.REAR)
	assert_eq(formers.size(), 2, "%s: sanity: a flank and a rear" % mode)
	for _i in 10:
		for d in formers:
			d.position = MID
		await wait_physics_frames(1)
		for d in formers:
			assert_eq(_brain(d).phase, P.FORM, "%s: still in FORM" % mode)
			assert_false(d.contact_profile.is_armed(), "%s: unarmed in FORM" % mode)
	assert_eq(health.current_health, Fixture.PLAYER_MAX_HEALTH, "%s: touching FORM drones deals 0" % mode)


# ── Reassignment ─────────────────────────────────────────────────────────────────────────────────

func test_the_lead_freed_mid_burst_hands_over_and_the_flank_is_refilled(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drones := _squad_of(h, [MID + Vector2(0, -300), MID + Vector2(-60, -310), MID + Vector2(60, -310), MID + Vector2(0, -380)], _budget_rule)
	var squad: SquadController = drones[0].squad
	var lead := _with_role(drones, R.LEAD)[0]
	var rear := _with_role(drones, R.REAR)[0]
	var step := [0]
	var log := {}
	_record(drones, step, log, [])
	var i := 0
	while _brain(lead).phase != P.BURST and i < 600:
		step[0] = i
		_tick_all(drones)
		i += 1
	assert_eq(_brain(lead).phase, P.BURST, "%s: sanity: the lead is bursting" % mode)
	assert_true(squad.attack_window_open, "%s: sanity: its burst opened the window" % mode)
	drones.erase(lead)
	lead.free()
	var freed_at := i
	assert_false(squad.attack_window_open, "%s: the window died with its lead" % mode)
	var roles := []
	for d in drones:
		roles.append(squad.role_of(d))
	roles.sort()
	assert_eq(roles, [R.LEAD, R.FLANK_LEFT, R.FLANK_RIGHT], "%s: a new lead and both flanks" % mode)
	assert_true(squad.role_of(rear) == R.FLANK_LEFT or squad.role_of(rear) == R.FLANK_RIGHT,
		"%s: the former REAR fills the vacated flank" % mode)
	var promoted := _with_role(drones, R.LEAD)[0]
	var mid_pass := [P.WINDUP, P.BURST, P.OVERSHOOT].has(_brain(promoted).phase)
	for j in 600:
		step[0] = freed_at + j
		_tick_all(drones)
	# The promoted member's entries after the free: if it was mid-pass, it finishes that pass and
	# rejoins before any new WINDUP — it picks up nothing it had not started.
	var after: Array = log[promoted].filter(func(e: Array) -> bool: return e[0] >= freed_at)
	var phases := after.map(func(e: Array) -> int: return e[1])
	if mid_pass:
		var rejoin := phases.find(P.REJOIN)
		assert_gt(rejoin, -1, "%s: the promoted member rejoins after its pass" % mode)
		assert_false(phases.slice(0, rejoin).has(P.WINDUP), "%s: no new pass before it rejoins" % mode)
		assert_eq(phases[rejoin + 1], P.CLOSE_IN, "%s: then closes in as the new lead" % mode)
	# The new lead's burst opens the window again and a flank answers it (epic review N13).
	var lead_burst := -1
	for e in after:
		if e[1] == P.BURST and (not mid_pass or e[0] > after[phases.find(P.CLOSE_IN)][0]):
			lead_burst = e[0]
			break
	assert_gt(lead_burst, -1, "%s: the new lead attacks" % mode)
	var answered := false
	for d in drones:
		if d == promoted:
			continue
		for e in log[d]:
			if e[1] == P.WINDUP and e[0] >= lead_burst:
				answered = true
	assert_true(answered, "%s: a flank answers the new lead's window" % mode)


## Review round 1 B4: a flank that leaves (e.g. detonated on the player) while members have moved
## can move the lead by the distance recompute. The old lead's window must close with it, so the
## flank that already answered it re-arms for the new lead's burst.
func test_a_lead_change_closes_the_window_and_the_new_lead_is_answered() -> void:
	var h := _harness("open_space")
	h.player.global_position = MID
	var drones := _squad_of(h, [MID + Vector2(0, -300), MID + Vector2(-60, -310), MID + Vector2(60, -310), MID + Vector2(0, -380)], _budget_rule)
	var squad: SquadController = drones[0].squad
	var lead := _with_role(drones, R.LEAD)[0]
	var i := 0
	while _brain(lead).phase != P.OVERSHOOT and i < 600:
		_tick_all(drones)
		i += 1
	assert_eq(_brain(lead).phase, P.OVERSHOOT, "sanity: the lead is overshooting")
	assert_true(squad.attack_window_open, "sanity: the window is open")
	var flanks := _with_role(drones, R.FLANK_LEFT) + _with_role(drones, R.FLANK_RIGHT)
	lead.global_position = MID + Vector2(0, 420)  # farther than every mate: the next recompute demotes it
	var gone := flanks[0]
	var stays := flanks[1]
	stays.global_position = MID + Vector2(0, -150)
	drones.erase(gone)
	gone.free()
	assert_eq(squad.role_of(stays), R.LEAD, "sanity: the recompute moved the lead")
	assert_false(squad.attack_window_open, "a change of lead closes the old lead's window")
	var step := [0]
	var log := {}
	_record(drones, step, log, [])
	for j in 600:
		step[0] = j
		_tick_all(drones)
	var burst := -1
	for e in log[stays]:
		if e[1] == P.BURST:
			burst = e[0]
			break
	assert_gt(burst, -1, "the new lead attacks")
	var answered := false
	for d in drones:
		if d != stays:
			for e in log[d]:
				if e[1] == P.WINDUP and e[0] >= burst:
					answered = true
	assert_true(answered, "its window is answered by a flank")


# ── Formation recovery ───────────────────────────────────────────────────────────────────────────

func test_formation_recovers_after_a_150_px_displacement(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var drones := _squad_of(h, _row_of_five(MID), _frozen)
	var formers := _with_role(drones, R.REAR) + _with_role(drones, R.FLANK_LEFT) + _with_role(drones, R.FLANK_RIGHT)
	assert_eq(formers.size(), 4, "%s: sanity" % mode)
	_run(drones, 240)
	for d in formers:
		assert_true(_in_tolerance(d, MID), "%s: sanity: settled before the push" % mode)
	for d in formers:
		var out := (d.global_position - MID).normalized()
		var push := out if d.squad.role_of(d) == R.REAR else out.rotated(PI / 2.0)
		d.global_position += push * 150.0
		assert_false(_in_tolerance(d, MID), "%s: boundary: the push put it out of tolerance" % mode)
	var back := {}
	for i in 180:
		_tick_all(drones)
		for d in formers:
			if not back.has(d) and _in_tolerance(d, MID):
				back[d] = i
	assert_eq(back.size(), 4, "%s: every member was back in tolerance within 3 s (%s)" % [mode, back.values()])
	for d in formers:
		assert_true(_in_tolerance(d, MID), "%s: and is still in tolerance at 3 s" % mode)
		assert_eq(_brain(d).phase, P.FORM, "%s: in FORM" % mode)


# ── Phase offsets (R2.3) ─────────────────────────────────────────────────────────────────────────

func test_phase_offsets_come_from_the_rng(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	var no_flock := func(c: SwarmDroneConfig) -> void: c.flock_nudge_cap = 0.0
	var drones := _squad_of(h, [MID + Vector2(0, -300), MID + Vector2(-60, -300), MID + Vector2(60, -300), MID + Vector2(0, -400)],
		no_flock, [11, 22, 33, 11])
	var b := drones.map(func(d: SwarmDrone) -> SwarmDroneBrain: return _brain(d))
	for i in 3:
		for j in range(i + 1, 3):
			assert_ne(b[i].phase_offset, b[j].phase_offset, "%s: distinct seeds, distinct ring offsets" % mode)
			assert_ne(b[i].cork_phase, b[j].cork_phase, "%s: distinct seeds, distinct corkscrew phases" % mode)
	for x in b:
		assert_lte(absf(x.phase_offset), SwarmDroneBrain.MAX_PHASE_OFFSET, "%s: bounded (D2)" % mode)
	assert_eq(b[0].phase_offset, b[3].phase_offset, "%s: control: the same seed gives the same offset" % mode)
	assert_eq(b[0].cork_phase, b[3].cork_phase, "%s: control: and the same corkscrew phase" % mode)


# ── Rails and the per-role budget ────────────────────────────────────────────────────────────────

func test_a_rail_suspended_member_leaves_and_the_squad_reassigns(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.global_position = MID
	if mode == "assault":
		(h.root.get_node("ArenaCamera") as Camera2D).make_current()
	else:
		var cam := Camera2D.new()
		h.root.add_child(cam)
		cam.make_current()
	var drones := _squad_of(h, [MID + Vector2(0, -300), MID + Vector2(-60, -310), MID + Vector2(60, -310)])
	var squad: SquadController = drones[0].squad
	var lead := _with_role(drones, R.LEAD)[0]
	lead.add_child(EnemyPathMover.new())
	assert_true(lead.is_ai_suspended(), "%s: sanity: the rail took over" % mode)
	assert_false(squad.members().has(lead), "%s: the railed drone left the squad" % mode)
	var roles := []
	for d in drones:
		if d != lead:
			roles.append(squad.role_of(d))
	roles.sort()
	assert_eq(roles, [R.LEAD, R.FLANK_LEFT], "%s: the two left reassign to LEAD + FLANK" % mode)


func _rear_budget_squad(h: RefCounted) -> Array[SwarmDrone]:
	h.player.global_position = MID
	return _squad_of(h, [MID + Vector2(0, -300), MID + Vector2(-60, -310), MID + Vector2(60, -310), MID + Vector2(0, -380)],
		func(c: SwarmDroneConfig) -> void: c.rear_engage_seconds = 2.0)


func test_a_rear_member_honours_rear_engage_seconds() -> void:
	var h := _harness("assault")
	var drones := _rear_budget_squad(h)
	var rear := _with_role(drones, R.REAR)[0]
	var others := drones.filter(func(d: SwarmDrone) -> bool: return d != rear)
	var ticks := 0
	while _brain(rear).phase != P.DISENGAGE and ticks < 400:
		_tick_all(drones)
		ticks += 1
	assert_between(ticks, 120, 121, "the REAR leaves at rear_engage_seconds (2.0 s), not engage_seconds")
	_run(drones, 12)
	for d in others:
		assert_ne(_brain(d).phase, P.DISENGAGE, "attackers keep their full engage_seconds")


func test_rear_engage_seconds_does_nothing_in_open_space() -> void:
	var h := _harness("open_space")
	var drones := _rear_budget_squad(h)
	var log := {}
	_record(drones, [0], log, [])
	_run(drones, 240)
	for d in drones:
		assert_false(log[d].any(func(e: Array) -> bool: return e[1] == P.DISENGAGE), "no exit without an arena")


# ── Nudges ───────────────────────────────────────────────────────────────────────────────────────

func test_the_nudge_is_capped_and_off_outside_formation_phases() -> void:
	var h := _harness("open_space")
	h.player.global_position = MID
	var drones := _squad_of(h, [MID + Vector2(20, 0), MID + Vector2(20, 0)])
	var a := drones[0]
	var b := drones[1]
	var target := TargetInfo.player(get_tree())
	var nudge := _brain(b)._nudge(target)
	assert_gt(nudge.length(), 0.0, "sanity: a coincident mate and the player 20 px away push")
	assert_lte(nudge.length(), CONFIG.flock_nudge_cap * CONFIG.max_speed + 0.001, "capped at flock_nudge_cap × max_speed")
	assert_gt(nudge.dot(b.global_position - MID), 0.0, "and it points away from the player (evade)")
	var mover_a := a.get_node("EnemyMover") as EnemyMover
	var mover_b := b.get_node("EnemyMover") as EnemyMover
	_brain(b).tick(DT)
	assert_eq(_brain(b).phase, P.FORM, "sanity: the mate is in FORM")
	assert_ne(mover_b._nudge, Vector2.ZERO, "control: FORM offers the nudge")
	mover_b.step(DT)
	_brain(a).enter_phase(P.WINDUP)
	_brain(a).tick(DT)
	assert_eq(_brain(a).phase, P.WINDUP)
	assert_eq(mover_a._nudge, Vector2.ZERO, "WINDUP offers no nudge (committed)")
	mover_a.step(DT)
	_brain(b).flock_nudge_cap = 0.0
	assert_eq(_brain(b)._nudge(target), Vector2.ZERO, "cap 0 turns every nudge off")


# ══ t8d: hub idle (epic §2.7.3; task docs/plans/cmuj4y8rm0078p52x5qa7v6fo) ══
#
# Cold-start helpers: unlike `_spawn()` / `_squad_of()` above (which set `start_engaged = true` so
# every t8b/t8c case keeps assuming combat-from-spawn, exactly as it did before this task), these
# leave the brain to decide for itself — Open Space starts IDLE, Assault starts in combat.

const FAR_AWAY := Vector2(100000.0, 100000.0)


func _idle_spawn(h: RefCounted, pos: Vector2, configure: Callable = Callable(), rng_seed: int = SEED) -> SwarmDrone:
	var drone := SCENE.instantiate() as SwarmDrone
	drone.global_position = pos
	(drone.get_node("Brain") as SwarmDroneBrain).rng_seed = rng_seed
	if configure.is_valid():
		configure.call(drone.config)
	h.root.add_child(drone)
	drone.set_physics_process(false)
	return drone


## One squad, one shared `patrol_anchor` set explicitly on every member (as `SectorHub` will), each
## spawned at `anchor + offsets[i]`.
func _idle_squad(h: RefCounted, anchor: Vector2, offsets: Array, configure: Callable = Callable(), seeds: Array = []) -> Array[SwarmDrone]:
	var squad := SquadController.new()
	var out: Array[SwarmDrone] = []
	for i in offsets.size():
		var drone := SCENE.instantiate() as SwarmDrone
		drone.global_position = anchor + offsets[i]
		var brain := drone.get_node("Brain") as SwarmDroneBrain
		brain.rng_seed = int(seeds[i]) if i < seeds.size() else SEED + i
		brain.patrol_anchor = anchor
		if configure.is_valid():
			configure.call(drone.config)
		drone.squad = squad
		h.root.add_child(drone)
		drone.set_physics_process(false)
		out.append(drone)
	return out


func test_open_space_cold_start_begins_idle() -> void:
	var h := _harness("open_space")
	h.player.global_position = FAR_AWAY
	var drone := _idle_spawn(h, Vector2(500, 500))
	_tick(drone)
	assert_eq(_brain(drone).phase, P.IDLE, "Open Space starts on patrol, not in combat")
	assert_not_null(_brain(drone).anchor_idle, "an AnchorIdle was built")


func test_the_assault_harness_starts_in_approach() -> void:
	var h := _harness("assault")
	h.player.global_position = MID
	var drone := _idle_spawn(h, MID + Vector2(0, -700))  # far enough that APPROACH does not hand over on tick 1
	_tick(drone)
	assert_eq(_brain(drone).phase, P.APPROACH, "Assault always starts in combat: the level decided the fight is on")
	assert_null(_brain(drone).anchor_idle, "no AnchorIdle is built in Assault")


func test_patrol_anchor_defaults_to_the_spawn_position() -> void:
	var h := _harness("open_space")
	h.player.global_position = FAR_AWAY
	var pos := Vector2(321.0, -654.0)
	var drone := _idle_spawn(h, pos)
	_tick(drone)
	assert_eq(_brain(drone).patrol_anchor, pos, "unset (Vector2.INF) defaults to where the drone spawned")


func test_idle_stays_within_the_ring_over_20_seconds() -> void:
	var h := _harness("open_space")
	h.player.global_position = FAR_AWAY
	var anchor := Vector2(500.0, -400.0)
	var drones := _idle_squad(h, anchor, [Vector2(20, 0), Vector2(-15, 10), Vector2(0, -25)])
	var worst := 0.0
	for _i in int(20.0 / DT):
		_tick_all(drones)
		for d in drones:
			assert_eq(_brain(d).phase, P.IDLE, "stays on patrol with the player this far away")
			worst = maxf(worst, d.global_position.distance_to(anchor))
	assert_lte(worst, CONFIG.idle_radius + 30.0,
		"every member stayed within idle_radius + 30 of the anchor over 20 s (worst %.1f px)" % worst)


## Array order = squad join order = `_tick_all()`'s per-tick order. The perceiver is ticked LAST,
## so the other two are ticked before it notices in the tick it happens — proving the guarantee is
## really "by the end of the NEXT tick", not "instantly, every time", which array order alone could
## have hidden (if the perceiver had gone first, everyone would (also correctly) leave IDLE the very
## same tick).
func test_one_member_perceiving_wakes_the_whole_squad_by_the_next_tick() -> void:
	var h := _harness("open_space")
	h.player.global_position = FAR_AWAY
	var anchor := Vector2.ZERO
	# Far apart from each other — only proximity to the PLAYER should matter to perception, so this
	# rules out a false pass from the other two coincidentally sitting inside perceive_radius too.
	var drones := _idle_squad(h, anchor, [Vector2(-5000, 0), Vector2(5000, 0), Vector2(0, 0)])
	_tick_all(drones)  # starts every brain; the player is far, so all settle into IDLE
	for d in drones:
		assert_eq(_brain(d).phase, P.IDLE, "sanity: all idle with the player far away")
	var perceiver := drones[2]
	h.player.global_position = perceiver.global_position + Vector2(CONFIG.perceive_radius - 50.0, 0)
	_tick_all(drones)
	assert_ne(_brain(perceiver).phase, P.IDLE, "the perceiver itself leaves IDLE the tick it perceives")
	assert_eq(_brain(drones[0]).phase, P.IDLE, "sanity: not yet — ticked before the perceiver, same tick")
	assert_eq(_brain(drones[1]).phase, P.IDLE, "sanity: not yet — ticked before the perceiver, same tick")
	_tick_all(drones)
	for d in drones:
		assert_ne(_brain(d).phase, P.IDLE, "every member is out of IDLE by the end of the next tick")


func test_hysteresis_holds_for_5_seconds_between_the_radii() -> void:
	var h := _harness("open_space")
	var drone := _idle_spawn(h, Vector2(1000.0, 0.0))
	h.player.global_position = drone.global_position + Vector2(200.0, 0.0)  # inside perceive_radius
	var notice_ticks := int(CONFIG.notice_time / DT) + 2
	for _i in notice_ticks:
		_tick(drone)
	assert_true(_brain(drone).phase != P.IDLE and _brain(drone).phase != P.NOTICING,
		"sanity: reached combat (phase %d)" % _brain(drone).phase)
	var mid := (CONFIG.perceive_radius + CONFIG.lose_radius) / 2.0
	for _i in int(5.0 / DT):
		h.player.global_position = drone.global_position + Vector2(mid, 0.0)
		_tick(drone)
		assert_ne(_brain(drone).phase, P.RETURNING, "never returns while within lose_radius")
		assert_ne(_brain(drone).phase, P.IDLE, "never idles while within lose_radius")


func test_a_member_beyond_lose_radius_does_not_return_while_another_is_engaged() -> void:
	var h := _harness("open_space")
	var anchor := Vector2.ZERO
	var drones := _idle_squad(h, anchor, [Vector2.ZERO, Vector2.ZERO])
	var a := drones[0]
	var b := drones[1]
	h.player.global_position = FAR_AWAY
	_tick_all(drones)
	assert_eq(_brain(a).phase, P.IDLE, "sanity")
	assert_eq(_brain(b).phase, P.IDLE, "sanity")
	h.player.global_position = a.global_position + Vector2(200.0, 0.0)  # inside A's perceive_radius
	b.global_position = a.global_position + Vector2(CONFIG.lose_radius + 300.0, 0.0)  # beyond B's own lose_radius
	for _i in int(1.0 / DT):
		_tick_all(drones)
		assert_ne(_brain(b).phase, P.RETURNING, "B stays engaged while A still is")
		assert_ne(_brain(b).phase, P.IDLE, "B stays engaged while A still is")


func test_all_beyond_lose_radius_return_together_then_idle() -> void:
	var h := _harness("open_space")
	var anchor := Vector2.ZERO
	var drones := _idle_squad(h, anchor, [Vector2(20, 0), Vector2(-20, 0)])
	h.player.global_position = anchor + Vector2(200.0, 0.0)
	for _i in int(CONFIG.notice_time / DT) + 5:
		_tick_all(drones)
	for d in drones:
		assert_ne(_brain(d).phase, P.IDLE, "sanity: both engaged")
	h.player.global_position = FAR_AWAY  # well beyond every member's lose_radius
	# `hold_combat` clears one tick after the last member's `engaged` flag does (§2.7.3's own lag:
	# it is read for THIS tick's update() but written from THIS tick's is_engaged() only at the end
	# of `_tick_anchor_idle`), so members can reach RETURNING on different ticks. What matters is
	# that every one of them passes through it on the way home — not that they all line up on one
	# single tick — so this tracks each member's own visit rather than requiring a simultaneous one.
	var saw_returning := {}
	var settled := false
	for _i in int(15.0 / DT):
		_tick_all(drones)
		for d in drones:
			if _brain(d).phase == P.RETURNING:
				saw_returning[d] = true
		if drones.all(func(d: SwarmDrone) -> bool: return _brain(d).phase == P.IDLE):
			settled = true
			break
	for d in drones:
		assert_true(saw_returning.has(d), "every member passed through RETURNING on the way back")
	assert_true(settled, "all members reach IDLE, back at the anchor")
	for d in drones:
		assert_lte(d.global_position.distance_to(anchor), CONFIG.idle_radius + 30.0, "settled back inside the ring")


## The handover guard (review N10): the mover's own `move_toward` / rotation-rate cap bounds every
## tick regardless of phase, so this only fails if the brain calls `halt()` or `boost()` on the
## NOTICING -> APPROACH transition. Uses `maxf(acceleration, braking)`, not `acceleration` alone —
## the deceleration-to-a-stop that opens NOTICING runs at `braking`, which exceeds `acceleration`.
func test_the_handover_from_noticing_to_combat_never_snaps() -> void:
	var h := _harness("open_space")
	var drone := _idle_spawn(h, Vector2(1000.0, 500.0))
	h.player.global_position = drone.global_position + Vector2(200.0, 0.0)
	_tick(drone)
	assert_eq(_brain(drone).phase, P.NOTICING, "sanity: perceives immediately")
	var v_cap := maxf(CONFIG.acceleration, CONFIG.braking) * DT + 0.5
	var r_cap := CONFIG.max_turn_rate * DT + 0.01
	var left_noticing := false
	for _i in 60:
		var v0 := drone.velocity
		var rot0 := drone.rotation
		_tick(drone)
		assert_lte(drone.velocity.distance_to(v0), v_cap, "no per-tick velocity snap through the handover")
		assert_lte(absf(angle_difference(rot0, drone.rotation)), r_cap, "no per-tick rotation snap through the handover")
		# Stop at the handover itself: once in combat, a normal BURST legitimately snaps velocity
		# via `boost()`, which is not what this guard is about (review N10).
		if _brain(drone).phase != P.NOTICING:
			left_noticing = true
			break
	assert_true(left_noticing, "sanity: leaves NOTICING within the window")
