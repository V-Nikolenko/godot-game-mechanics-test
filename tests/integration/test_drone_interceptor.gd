## Characterization tests for `DroneInterceptor`, kept as the **acceptance test** for its port onto
## the Phase 1 brain/mover architecture
## (`docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §2.11, P-8; task cmug33ldz00djm52wqu66uc4z,
## "t14-port-interceptor"). The phase logic (ENTER/ORBIT/DASH) now lives in the sibling
## `DroneInterceptorBrain` (`drone_interceptor_brain.gd`), driven by `EnemyMover`; every assertion
## below still reads only PUBLIC, observable state (velocity, position, rotation, health,
## `is_queued_for_deletion()`), never a private field, and no expected value changed from the
## pre-port pin — only the setup needed to reach that state changed (task acceptance criteria).
##
## ── Harness notes ─────────────────────────────────────────────────────────────────────────────
##
## 1. `DroneInterceptor` moves through `move_and_slide()` (inside `EnemyMover.step()`), unlike
##    `EnemyPathMover` (`test_enemy_path_mover.gd`), which writes `global_position` directly.
##    `CharacterBody2D.move_and_slide()` reads `get_physics_process_delta_time()` internally
##    instead of taking a delta argument, and that value is NOT reliably `1/60` when the method is
##    invoked by hand outside a real physics substep (confirmed empirically here and independently
##    in `test_enemy_dual_mode.gd`'s own harness notes). A single `_physics_process(delta)` call is
##    unaffected — `velocity` is assigned directly by `EnemyMover.step()` *before*
##    `move_and_slide()` ever runs, so it reads back exactly as set — but a MULTI-TICK loop that
##    trusts `move_and_slide()`'s own position update lets that per-call error compound in
##    `global_position`, which then feeds back into any later tick's distance-based velocity (the
##    orbit correction reads distance to the player). So: single-tick cases below call
##    `drone._physics_process(delta)` directly and read `velocity`/`rotation` — safe, since nothing
##    downstream depends on `global_position`'s exact value within that one call. Multi-tick ORBIT
##    simulations instead use `_tick()` (below), which re-derives `global_position` by hand
##    (`before + velocity * delta`) after each `_physics_process()` call, bypassing whatever
##    `move_and_slide()` actually displaced it by — the same technique `test_enemy_dual_mode.gd`
##    uses for the fixture brain. The dash-onset window case is the one exception that loops the
##    full `_physics_process()` many times without `_tick()`: it only ever compares
##    `velocity.length()` against `dash_speed`, and the dash timer counts down using the exact
##    `delta` this file passes in, never `move_and_slide()`'s internal one, so its timing is exact
##    regardless of any position drift alongside it.
## 2. Every drone has its own engine-driven `_physics_process` turned OFF right after spawn
##    (`set_physics_process(false)`) and is ticked only by calling `_physics_process(delta)`
##    directly — same technique `test_enemy_dual_mode.gd` uses for the fixture — so elapsed time is
##    exact regardless of how many real engine frames the test happens to run for.
## 3. `DroneInterceptorBrain._begin_dash()` and `._check_dash_end()` are called directly on the
##    brain in a few cases, the same idiom `test_ram_ship.gd` uses for `_on_received_damage()`: it
##    isolates the dash-DIRECTION formula and the off-screen-cull formula from the random
##    dash-TIMING mechanism (covered separately, seed-robustly, in its own case) and from
##    `move_and_slide()` (note 1), without ever asserting on anything private — only the resulting
##    `velocity` / `global_position` / `is_queued_for_deletion()` is read.
## 4. Several cases spawn the player far outside the `orbit_radius` (100000 px away) so the ENTER
##    phase never transitions to ORBIT during the test window — this keeps the bearing to the
##    player effectively constant while the drone closes a little distance, which is what makes the
##    facing-convergence case's target angle stay put without needing a stationary orbit.
## 5. `DroneInterceptorConfig`'s shipped tuning (`drone_interceptor_config.tres`) is read through
##    the preloaded resource rather than hardcoded, so a tuning change does not silently desync the
##    pinned numbers from the values the game actually ships (same technique `test_ram_ship.gd`
##    uses for `RamShipConfig`).
## 6. **Randomness moved from the global RNG to `brain.rng` (plan review F10).** A seed-robust case
##    now spawns its drone through `_spawn_drone(pos, seed)`, which sets the brain's `rng_seed`
##    export *before* the drone enters the tree — `EnemyBrain._ready()` seeds `rng` from it — rather
##    than calling the global `seed()`, which no longer has any effect on the brain's draws.
## 7. **One player per test function, spawned before any seed loop.** `TargetInfo.player(tree)`
##    (which the brain now uses in place of the old `_get_player()`) resolves the *first* node in
##    group `"player"` — so a loop that spawned a fresh player on every seed iteration (as the
##    pre-port version did, safely, only because it passed that iteration's `player` reference
##    straight into `_phase_orbit(delta, player)` by hand) would silently keep resolving iteration
##    1's player forever. Every seed-loop case below spawns its player once, outside the loop, and
##    reuses it for every seed's drone.
## 8. **Every seed-loop case frees its drone before the next seed's spawns.** Every drone below
##    spawns at the SAME point, `(orbit_radius, 0)`. That was harmless pre-port, because the private
##    phase methods were called directly and never touched `move_and_slide()`. Post-port, a
##    multi-tick case drives the real `_physics_process()` (note 1), and a leftover drone from the
##    previous seed — still sitting at that exact point, since `add_child_autofree` only frees at
##    test teardown — is a real `CharacterBody2D` on the same default collision layer: without
##    freeing it first, the *current* seed's drone collides with it, and `move_and_slide()`
##    corrupts `velocity` in response (confirmed empirically: `test_orbit_correction_speed_is_clamped`
##    saw velocities well under the 60 px/s floor `Steering.orbit`'s own `clampf()` guarantees,
##    before this fix). `_spawn_drone()`'s throwaway `Node2D` container makes this a one-line
##    `drone.get_parent().free()` — an immediate free, not `queue_free()`, so the collider is gone
##    before the next iteration's `move_and_slide()` call, and safe to call early: GUT's
##    `add_child_autofree()` checks `is_instance_valid()` at teardown.
extends GutTest

const DRONE_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn")
const DRONE_CONFIG: DroneInterceptorConfig = \
		preload("res://assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres")

const DT := 1.0 / 60.0

## Several arbitrary seeds, not one, per the review's seed-robustness requirement (F10): the dash
## onset window must hold regardless of which values the random draws happen to produce. None is
## 0 — that value means "randomize" on `EnemyBrain.rng_seed`, not "seed with 0" (note 6).
const _SEEDS := [1, 2, 3, 4, 5, 42, 100]


func _spawn_drone(pos: Vector2, rng_seed: int = 0) -> DroneInterceptor:
	var container := Node2D.new()
	add_child_autofree(container)
	var drone := DRONE_SCENE.instantiate() as DroneInterceptor
	assert_not_null(drone, "sanity: drone_interceptor.tscn's root is not a DroneInterceptor")
	drone.global_position = pos
	if rng_seed != 0:
		_brain(drone).rng_seed = rng_seed
	container.add_child(drone)
	drone.set_physics_process(false)
	return drone


func _brain(drone: DroneInterceptor) -> DroneInterceptorBrain:
	return drone.get_node("Brain") as DroneInterceptorBrain


func _spawn_player(pos: Vector2, vel: Vector2 = Vector2.ZERO) -> CharacterBody2D:
	var p := CharacterBody2D.new()
	p.add_to_group("player")
	p.global_position = pos
	p.velocity = vel
	add_child_autofree(p)
	return p


func _spawn_arena_camera(pos: Vector2) -> ArenaCamera:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	cam.global_position = pos
	cam.make_current()
	return cam


## Runs one manual physics tick, then replaces whatever `move_and_slide()` actually displaced the
## actor by with an exact `delta * velocity` integration (harness note 1).
func _tick(drone: BaseEnemy, delta: float) -> void:
	var before := drone.global_position
	drone._physics_process(delta)
	drone.global_position = before + drone.velocity * delta


## Drives the full tick (via `_tick()`, note 1) for up to `steps` calls. Stops early the moment the
## dash begins (detected publicly, via `velocity` crossing the midpoint between
## `orbit_correct_speed` and `dash_speed`), since nothing here has a notion of "stop ticking me".
## Returns every nonzero orbit-correction speed sampled, in call order.
func _run_orbit_and_collect_speeds(drone: DroneInterceptor, steps: int) -> Array[float]:
	var dash_threshold: float = (DRONE_CONFIG.orbit_correct_speed + DRONE_CONFIG.dash_speed) * 0.5
	var speeds: Array[float] = []
	for _i in steps:
		_tick(drone, DT)
		var vlen := drone.velocity.length()
		if vlen > dash_threshold:
			break
		if vlen > 0.01:
			speeds.append(vlen)
	return speeds


## Same drive as `_run_orbit_and_collect_speeds()`, but tracks the min/max distance from the
## player instead of the raw speed samples.
func _run_orbit_and_measure_distance(drone: DroneInterceptor, player: CharacterBody2D, steps: int) -> Dictionary:
	var dash_threshold: float = (DRONE_CONFIG.orbit_correct_speed + DRONE_CONFIG.dash_speed) * 0.5
	var min_dist := INF
	var max_dist := 0.0
	for _i in steps:
		_tick(drone, DT)
		if drone.velocity.length() > dash_threshold:
			break
		var dist: float = (player.global_position - drone.global_position).length()
		min_dist = minf(min_dist, dist)
		max_dist = maxf(max_dist, dist)
	return {"min": min_dist, "max": max_dist}


# ── 1. No player → zero velocity ───────────────────────────────────────────────

func test_no_player_holds_zero_velocity() -> void:
	var drone := _spawn_drone(Vector2(500.0, 500.0))
	drone._physics_process(DT)
	assert_eq(drone.velocity, Vector2.ZERO)


# ── 2. ENTER: seek the player at approach_speed ────────────────────────────────

func test_enter_phase_moves_toward_the_player_at_approach_speed() -> void:
	_spawn_player(Vector2(400.0, 0.0))
	var drone := _spawn_drone(Vector2(0.0, 0.0))  # 400 px away, well outside orbit_radius (130)

	drone._physics_process(DT)

	assert_almost_eq(drone.velocity.x, DRONE_CONFIG.approach_speed, 0.01)
	assert_almost_eq(drone.velocity.y, 0.0, 0.01)
	assert_almost_eq(drone.velocity.length(), DRONE_CONFIG.approach_speed, 0.01)


# ── 3. ENTER → ORBIT switch, boundary at exactly orbit_radius ─────────────────

## Just outside the radius: ENTER must still be seeking at the full approach_speed after one tick.
## Exactly AT the radius (boundary): after the switch, the correction speed must be bounded by
## orbit_correct_speed, which is strictly less than approach_speed — a public, velocity-only signal
## that the phase changed, without ever reading `phase` itself.
func test_switches_to_orbit_at_or_before_the_radius_boundary() -> void:
	_spawn_player(Vector2(0.0, 0.0))

	var just_outside := _spawn_drone(Vector2(DRONE_CONFIG.orbit_radius + 5.0, 0.0))
	just_outside._physics_process(DT)
	assert_almost_eq(
		just_outside.velocity.length(), DRONE_CONFIG.approach_speed, 0.01,
		"just outside the radius, ENTER must still be seeking at full approach_speed"
	)

	# BOUNDARY: exactly at the radius. Tick 1 flips the phase (no velocity write that frame,
	# since the transition itself early-returns); tick 2 is the first real ORBIT correction.
	var at_radius := _spawn_drone(Vector2(DRONE_CONFIG.orbit_radius, 0.0))
	at_radius._physics_process(DT)
	at_radius._physics_process(DT)
	assert_lte(
		at_radius.velocity.length(), DRONE_CONFIG.orbit_correct_speed + 0.01,
		"exactly at the radius, the SECOND tick must already be an orbit correction, not another ENTER seek"
	)
	assert_gt(
		at_radius.velocity.length(), 0.0,
		"sanity: the orbit correction actually produced motion"
	)


# ── 4. Orbit correction speed clamped to [60, orbit_correct_speed] ────────────

func test_orbit_correction_speed_is_clamped() -> void:
	_spawn_player(Vector2(0.0, 0.0))
	var samples: Array[float] = []
	for s in _SEEDS:
		var drone := _spawn_drone(Vector2(DRONE_CONFIG.orbit_radius, 0.0), s)
		samples.append_array(_run_orbit_and_collect_speeds(drone, 80))
		drone.get_parent().free()  # harness note 8: no stale collider left for the next seed

	assert_gt(samples.size(), 10, "sanity: enough orbit-correction samples to mean something")
	for v in samples:
		# The 0.01 margin on both sides absorbs float32 error from Vector2.normalized() — clampf()
		# itself guarantees the underlying `speed` scalar never leaves [60, orbit_correct_speed].
		assert_between(
			v, 60.0 - 0.01, DRONE_CONFIG.orbit_correct_speed + 0.01,
			"every orbit-correction speed must be clamped to [60, orbit_correct_speed]"
		)
	var min_sample: float = samples.min()
	assert_lt(
		min_sample, DRONE_CONFIG.orbit_correct_speed - 1.0,
		"sanity: the clamp's lower bound must actually be exercised, not pegged at the ceiling forever"
	)


# ── 5. Orbit holds the player at roughly the orbit radius (by distance, not angle) ─────────────

## Deliberately asserts by DISTANCE, never by the private `_orbit_angle` (review F10): the port
## moved that draw from the global RNG to `brain.rng`, so an angle-based pin would break on setup
## alone, not on a real behaviour change.
func test_orbit_holds_the_player_within_a_bounded_distance() -> void:
	var player := _spawn_player(Vector2(0.0, 0.0))
	for s in _SEEDS:
		var drone := _spawn_drone(Vector2(DRONE_CONFIG.orbit_radius, 0.0), s)
		var bounds := _run_orbit_and_measure_distance(drone, player, 80)

		assert_lte(
			bounds["max"], DRONE_CONFIG.orbit_radius + DRONE_CONFIG.orbit_correct_speed,
			"seed %d: orbiting must not drift arbitrarily far from the player" % s
		)
		assert_lt(
			bounds["min"], DRONE_CONFIG.orbit_radius,
			"seed %d: sanity, the correction must actually move the drone, not hold it frozen at the radius" % s
		)
		drone.get_parent().free()  # harness note 8: no stale collider left for the next seed


# ── 6. Dash onset: a seed-robust [1.0, 2.0] s window since ORBIT entry ─────────

## Spawning exactly at orbit_radius makes ORBIT entry coincide with the very first tick (see the
## boundary case above), so "elapsed since ORBIT entry" is just "elapsed since the loop started",
## with a one-frame allowance either side to match how the timer is actually sampled (plan §3 step
## 3 / review F10): the dash fires on the first ORBIT tick where the countdown reaches zero, and
## the countdown only starts decrementing on the SECOND tick (the first is spent switching phase).
func test_dash_begins_within_one_to_two_seconds_of_orbit_entry() -> void:
	_spawn_player(Vector2(0.0, 0.0))
	for s in _SEEDS:
		var drone := _spawn_drone(Vector2(DRONE_CONFIG.orbit_radius, 0.0), s)

		# BOUNDARY: 1.0 s minus one frame since ORBIT entry — must NOT have dashed yet.
		for _i in 60:
			drone._physics_process(DT)
		assert_lt(
			drone.velocity.length(), DRONE_CONFIG.dash_speed - 1.0,
			"seed %d: must not dash before 1.0 s (- 1 frame) after ORBIT entry" % s
		)

		# BOUNDARY: 2.0 s plus one frame since ORBIT entry — must have dashed by now.
		for _i in 62:
			drone._physics_process(DT)
		assert_almost_eq(
			drone.velocity.length(), DRONE_CONFIG.dash_speed, 0.5,
			"seed %d: must have dashed by 2.0 s (+ 1 frame) after ORBIT entry" % s
		)
		drone.get_parent().free()  # harness note 8: no stale collider left for the next seed


# ── 7. Dash direction: predicted player position, dash_speed magnitude ────────

func test_dash_direction_uses_the_predicted_player_position() -> void:
	var player := _spawn_player(Vector2(0.0, 0.0), Vector2(100.0, 0.0))
	var drone := _spawn_drone(Vector2(DRONE_CONFIG.orbit_radius, 0.0))

	_brain(drone)._begin_dash()
	drone._physics_process(DT)

	var predicted: Vector2 = player.global_position + player.velocity * DRONE_CONFIG.dash_prediction_time
	var expected_dir: Vector2 = (predicted - Vector2(DRONE_CONFIG.orbit_radius, 0.0)).normalized()
	var expected_vel: Vector2 = expected_dir * DRONE_CONFIG.dash_speed

	assert_almost_eq(drone.velocity.x, expected_vel.x, 0.5)
	assert_almost_eq(drone.velocity.y, expected_vel.y, 0.5)
	assert_almost_eq(drone.velocity.length(), DRONE_CONFIG.dash_speed, 0.5)


## BOUNDARY: no player at dash onset. The documented fallback (`DroneInterceptorBrain._begin_dash`)
## predicts straight down from the drone's own position, not toward anything player-related.
func test_dash_with_no_player_at_onset_goes_straight_down() -> void:
	var drone := _spawn_drone(Vector2(DRONE_CONFIG.orbit_radius, 0.0))

	_brain(drone)._begin_dash()
	drone._physics_process(DT)

	assert_almost_eq(drone.velocity.x, 0.0, 0.5)
	assert_almost_eq(drone.velocity.y, DRONE_CONFIG.dash_speed, 0.5, "DOWN is +Y in Godot's 2D convention")


# ── 8. Contact kill ─────────────────────────────────────────────────────────────

func test_contact_sets_health_to_zero() -> void:
	var drone := _spawn_drone(Vector2.ZERO)
	assert_gt(drone.health.current_health, 0, "sanity: alive before contact")

	var dummy_area := Area2D.new()
	add_child_autofree(dummy_area)
	drone.contact_hit_box.area_entered.emit(dummy_area)

	assert_eq(drone.health.current_health, 0)


# ── 9. Facing converges nose-up toward the target ──────────────────────────────

## The FIRST tick's rotation is fully deterministic — no RNG, no prior movement — so it is pinned
## exactly, matching `lerp_angle(0.0, target_rotation, delta * 7.0)` with the DroneInterceptor's own
## nose-up convention `atan2(dir.x, -dir.y)` (the reverse of BaseEnemy's default nose-down
## convention — see plan §2.10; the port declares `sprite_forward_angle = -PI/2` on the scene root,
## which `EnemyMover`'s single facing rule turns into the exact same `atan2(dir.x, -dir.y)` formula).
func test_facing_first_tick_matches_the_nose_up_lerp_exactly() -> void:
	_spawn_player(Vector2(230.0, 0.0))
	var drone := _spawn_drone(Vector2(130.0, 0.0))
	assert_eq(drone.rotation, 0.0, "sanity: a fresh node starts at rotation 0")

	drone._physics_process(DT)

	var dir := Vector2(1.0, 0.0)  # (230,0) - (130,0), normalized
	var target_rotation: float = atan2(dir.x, -dir.y)
	var expected: float = lerp_angle(0.0, target_rotation, DT * 7.0)
	assert_almost_eq(drone.rotation, expected, 0.0001)


## Over a short window (well under the 1.0 s minimum dash delay) with a player far enough away
## that the drone's own small movements do not meaningfully change the bearing to it, rotation
## must have converged close to the nose-up heading.
func test_facing_converges_toward_the_target_over_time() -> void:
	_spawn_player(Vector2(100000.0, 0.0))
	var drone := _spawn_drone(Vector2.ZERO)

	for _i in 30:  # 0.5 s
		drone._physics_process(DT)

	assert_almost_eq(drone.rotation, PI / 2.0, 0.1, "nose-up toward a player straight ahead")


# ── 10. Dash ends when the drone leaves the legacy cull rect (Assault world) ───

## `cam.global_position ± viewport/2 ± 80`, with the camera pinned at (640, 360) and the project's
## fixed 1280x720 viewport: x in [-80, 1360], y in [-80, 800] (plan §2.11). `_check_dash_end()` is
## called directly on the brain, isolating the cull formula from the dash's own timing/direction,
## which are pinned separately above; it never reads `_dash_start` on this path (`EnemyWorld` finds
## a provider), so no dash needs to have actually begun first.
func test_dash_ends_past_the_legacy_cull_rect_in_an_assault_world() -> void:
	_spawn_arena_camera(Vector2(640.0, 360.0))
	var vp: Vector2 = get_viewport().get_visible_rect().size
	assert_eq(vp, Vector2(1280.0, 720.0), "sanity: the project's fixed 1280x720 viewport")

	var cases := [
		{"pos": Vector2(1360.0, 360.0), "culled": false, "label": "x=1360 (right boundary)"},
		{"pos": Vector2(1360.1, 360.0), "culled": true, "label": "x=1360.1 (just past right)"},
		{"pos": Vector2(-80.0, 360.0), "culled": false, "label": "x=-80 (left boundary)"},
		{"pos": Vector2(-80.1, 360.0), "culled": true, "label": "x=-80.1 (just past left)"},
		{"pos": Vector2(640.0, 800.0), "culled": false, "label": "y=800 (bottom boundary)"},
		{"pos": Vector2(640.0, 800.1), "culled": true, "label": "y=800.1 (just past bottom)"},
		{"pos": Vector2(640.0, -80.0), "culled": false, "label": "y=-80 (top boundary)"},
		{"pos": Vector2(640.0, -80.1), "culled": true, "label": "y=-80.1 (just past top)"},
	]
	for c in cases:
		var drone := _spawn_drone(c["pos"])
		_brain(drone)._check_dash_end()
		assert_eq(drone.is_queued_for_deletion(), c["culled"], c["label"])
