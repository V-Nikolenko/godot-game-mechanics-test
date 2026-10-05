## The Gatling Interceptor (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.6, §2.2, §2.8; task plan
## docs/plans/cmulwkar600c1qj2xnqykqsvo/3-plan.md). INTENT tests, t10-gatling-windows: scene wiring and
## pool sizing (the AI need, the legacy rail floor, and the rail starvation named as deliberate), the
## rail fallback read from config fields, the pressure-window rhythm and cadence in both harnesses, the
## side-on strafe, the side rule (first window, alternation, the Assault wall exception), the budget
## rule for SWING_IN and the deferred DISENGAGE.
##
## Harness rules (same as test_fighter.gd): the harness is built inside the body, Gatlings are
## hand-ticked with `_tick()`, and the shipped config is read from the preloaded `.tres` and never
## written (a case that needs other values writes the Gatling's PRIVATE `config`, and says so). Every
## Gatling is seeded, so a run is reproducible.
##
## Hand-ticked rounds never fly, so they never expire and the pool would starve after three streams:
## `_simulate()` records every new round and puts it straight back in `StreamPool`.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor.tscn")
## Shared, read-only: never written (CLAUDE.md config rule).
const CONFIG: GatlingInterceptorConfig = \
		preload("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor_config.tres")

const DT := 1.0 / 60.0
const MID := Vector2(640.0, 360.0)
const SEED := 1
## The epic §4 side-on bound: the line to the player within 90° ± 35° of `h`, i.e. the bearing |φ|.
const SIDE_ON_MIN_DEG := 55.0
const SIDE_ON_MAX_DEG := 125.0

const P := GatlingInterceptorBrain.Phase


func _harness(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = MID
	return h


func _spawn(h: RefCounted, pos: Vector2, configure: Callable = Callable(), rng_seed: int = SEED) -> GatlingInterceptor:
	var g := SCENE.instantiate() as GatlingInterceptor
	g.global_position = pos
	(g.get_node("Brain") as GatlingInterceptorBrain).rng_seed = rng_seed
	if configure.is_valid():
		configure.call(g.config)
	h.root.add_child(g)
	g.set_physics_process(false)
	return g


func _brain(g: GatlingInterceptor) -> GatlingInterceptorBrain:
	return g.get_node("Brain") as GatlingInterceptorBrain


func _tick(g: BaseEnemy) -> void:
	var before := g.global_position
	g._physics_process(DT)
	g.global_position = before + g.velocity * DT


func _bullets_under(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is EnemyBullet and (c as EnemyBullet).visible:
			n += 1
	return n


## How long a round of `round_scene` lives at `speed`: its own `ProjectileLifetime.max_distance` / speed.
func _life(round_scene: PackedScene, speed: float) -> float:
	var bullet := round_scene.instantiate() as EnemyBullet
	var life := (bullet.get_node("ProjectileLifetime") as ProjectileLifetime).max_distance / speed
	bullet.free()
	return life


## The bearing of `x` from the player, measured from `h` (UP for a holding player in both harnesses).
func _bearing_deg(x: Vector2, p: Vector2) -> float:
	return rad_to_deg(Vector2.UP.angle_to(x - p))


## Hand-ticks `g` for up to `seconds`, moving the player by its own velocity first, and logs every tick:
## `phase0` is the phase the tick started in (a stream's last round is fired on the tick it ends),
## `phase` the one after it. Every new round is logged and put back in its pool. `each.call(rec)`
## returning true stops the run.
func _simulate(h: RefCounted, g: GatlingInterceptor, seconds: float, each: Callable = Callable()) -> Dictionary:
	var brain := _brain(g)
	var light := g.get_node("StateLight") as StateLight
	var pool := g.get_node("StreamPool") as BulletPool
	var out := {"ticks": [], "shots": [], "freed": false}
	var t := 0.0
	for i in int(round(seconds / DT)):
		h.player.global_position += h.player.velocity * DT
		var phase0 := brain.phase
		_tick(g)
		t += DT
		if g.is_queued_for_deletion():
			out.freed = true
			break
		var rec := {"i": i, "t": t, "phase0": phase0, "phase": brain.phase, "x": g.global_position,
			"v": g.velocity, "p": h.player.global_position, "light": light.get_state(), "side": brain.side,
			"flank": brain.flank_point, "seek": brain.seek_target, "rounds": brain.stream_rounds,
			"windows": brain.windows_done, "budget_left": brain.budget.remaining()}
		for bullet in pool._active.duplicate():
			out.shots.append({"t": t, "i": i, "phase0": phase0, "dir": (bullet as EnemyBullet)._direction,
				"from": (bullet as Node2D).global_position, "p": h.player.global_position,
				"pv": h.player.velocity})
			pool._recycle(bullet)
		out.ticks.append(rec)
		if each.is_valid() and each.call(rec):
			break
	return out


## The phases entered, in order (consecutive duplicates collapsed).
func _sequence(run: Dictionary) -> Array:
	var seq: Array = []
	for r in run.ticks:
		if seq.is_empty() or seq[-1] != r.phase:
			seq.append(r.phase)
	return seq


## Each maximal stretch of one phase: {phase, t0, t1, ticks, entry (record), shots}.
func _stretches(run: Dictionary, phase: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cur: Dictionary = {}
	for r in run.ticks:
		if r.phase == phase:
			if cur.is_empty():
				cur = {"t0": r.t, "t1": r.t, "ticks": 0, "entry": r, "recs": []}
			cur.t1 = r.t
			cur.ticks += 1
			cur.recs.append(r)
		elif not cur.is_empty():
			out.append(cur)
			cur = {}
	if not cur.is_empty():
		out.append(cur)
	return out


## Streams: each run of rounds fired in STREAM ticks, split where a non-STREAM tick intervenes.
func _streams(run: Dictionary) -> Array[Array]:
	var out: Array[Array] = []
	var cur: Array = []
	var last_stream_tick := -10
	var shots_by_tick := {}
	for s in run.shots:
		if not shots_by_tick.has(s.i):
			shots_by_tick[s.i] = []
		shots_by_tick[s.i].append(s)
	for r in run.ticks:
		if r.phase0 != P.STREAM:
			continue
		if r.i != last_stream_tick + 1 and not cur.is_empty():
			out.append(cur)
			cur = []
		last_stream_tick = r.i
		for s in shots_by_tick.get(r.i, []):
			cur.append(s)
	if not cur.is_empty():
		out.append(cur)
	return out


func _windows(run: Dictionary) -> Array[Dictionary]:
	return _stretches(run, P.SWING_IN)


# ── Scene and pool ───────────────────────────────────────────────────────────────────────────────

func test_the_scene_has_the_ai_stack_and_one_brain_driven_controller() -> void:
	var g := SCENE.instantiate() as GatlingInterceptor
	add_child_autofree(g)
	assert_true(g.get_node_or_null("Brain") is GatlingInterceptorBrain)
	var mover := g.get_node_or_null("EnemyMover") as EnemyMover
	assert_not_null(mover)
	assert_eq(mover.constraint_mode, EnemyMover.ConstraintMode.AUTO)
	assert_true(g.get_node_or_null("StateLight") is StateLight)
	assert_null(g.get_node_or_null("AIStateMachine"))
	var controllers: Array[AttackController] = []
	for c in g.get_children():
		if c is AttackController:
			controllers.append(c)
	assert_eq(controllers.size(), 1, "one controller")
	assert_true(controllers[0].driven_by_brain)
	assert_false(controllers[0].enabled)
	assert_eq(controllers[0].bullet_pool, g.get_node("StreamPool"))


func test_every_bullet_pool_is_a_direct_child_of_the_root_and_holds_the_gatling_stream() -> void:
	var g := SCENE.instantiate() as GatlingInterceptor
	add_child_autofree(g)
	var pools := 0
	for n in g.find_children("*", "BulletPool", true, false):
		pools += 1
		assert_eq(n.get_parent(), g, "%s must be a direct child of the root" % n.name)
	assert_eq(pools, 1)
	assert_eq((g.get_node("StreamPool") as BulletPool).bullet_scene, EnemyRounds.GATLING_STREAM)


## The AI need: the longest stream, alive for its whole range, at most one stream per window period.
func test_the_stream_pool_covers_the_ai_stream() -> void:
	var g := SCENE.instantiate() as GatlingInterceptor
	add_child_autofree(g)
	var brain := _brain(g)
	var need := EnemyRounds.pool_size_for(CONFIG.stream_rounds_max, _life((g.get_node("StreamPool") as BulletPool).bullet_scene, CONFIG.round_speed), brain.min_window_period())
	assert_eq(need, 36, "12 rounds × ceil(5.83 s / 2.28 s)")
	assert_gte((g.get_node("StreamPool") as BulletPool).pool_size, need)


## The legacy rail pool was 20, so the rail stream never has fewer rounds than it used to. The true
## rail need (a constant 0.09 s stream of 6.36 s rounds) is 71, and the pool is DELIBERATELY smaller:
## a rail Gatling fires ~36 rounds and stalls until they expire, the legacy starvation shape (it stalled
## at 20). A true 11 shots/s hose would make the station's LEFT/RIGHT reinforcements harder — a balance
## change this phase does not own (epic §2.2). Ph15 takes the rails away.
func test_the_rail_keeps_the_legacy_starvation_shape_deliberately() -> void:
	var g := SCENE.instantiate() as GatlingInterceptor
	add_child_autofree(g)
	var pool := g.get_node("StreamPool") as BulletPool
	var size := pool.pool_size
	assert_gte(size, 20, "never below the legacy rail pool")
	var rail_need := EnemyRounds.pool_size_for(1, _life(pool.bullet_scene, CONFIG.rail_stream_speed), CONFIG.rail_stream_interval)
	assert_eq(rail_need, 71)
	assert_lt(size, rail_need, "deliberate: the rail stream starves, as it always has")


func test_config_pins_the_turn_against_the_acceleration() -> void:
	assert_lte(CONFIG.turn_rate * CONFIG.max_speed, CONFIG.acceleration)


func test_the_config_reaches_the_mover_the_hull_and_the_contact_box() -> void:
	var h := _harness("open_space")
	var g := _spawn(h, MID + Vector2(0, -600))
	var mover := g.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.max_speed, CONFIG.max_speed)
	assert_eq(mover.acceleration, CONFIG.acceleration)
	assert_eq(mover.braking, CONFIG.braking)
	assert_eq(mover.max_turn_rate, CONFIG.turn_rate)
	assert_eq(g.health.max_health, CONFIG.max_health)
	assert_eq(g.contact_hit_box.damage, CONFIG.collision_damage)
	assert_eq(_brain(g).config, g.config, "the brain reads the instance's private config")


func test_the_stream_pattern_is_built_per_instance_with_the_brain_rng() -> void:
	var h := _harness("open_space")
	var a := _spawn(h, MID + Vector2(0, -600))
	var b := _spawn(h, MID + Vector2(0, 600))
	var pa := (a.get_node("Attack") as AttackController).pattern as GatlingAttackPattern
	var pb := (b.get_node("Attack") as AttackController).pattern as GatlingAttackPattern
	assert_not_null(pa)
	assert_ne(pa, pb, "one pattern per Gatling")
	assert_eq(pa.rng, _brain(a).rng)
	assert_true(pa.aim_at_player)
	assert_eq(pa.bullet_speed, CONFIG.round_speed)
	assert_eq(pa.bullet_damage, CONFIG.round_damage)
	assert_eq(pa.spread_angle, CONFIG.stream_spread)
	assert_eq(pa.accuracy, CONFIG.accuracy)
	assert_false(pa.aim_point.is_finite(), "no shared aim point for a solo Gatling (t11's hook)")


# ── Rail fallback (epic §2.8) ────────────────────────────────────────────────────────────────────

func test_suspend_installs_the_legacy_rail_stream_from_config() -> void:
	var h := _harness("open_space")
	var g := _spawn(h, MID + Vector2(0, -400))
	_brain(g).enter_phase(P.STREAM)
	g.suspend_ai()
	var a := g.get_node("Attack") as AttackController
	var p := a.pattern as GatlingAttackPattern
	assert_false(a.driven_by_brain)
	assert_true(a.enabled)
	assert_eq(p.fire_interval, CONFIG.rail_stream_interval)
	assert_eq(p.bullet_speed, CONFIG.rail_stream_speed)
	assert_eq(p.bullet_damage, CONFIG.rail_damage)
	assert_eq(p.spread_angle, CONFIG.rail_spread)
	assert_true(p.aim_at_player)
	assert_eq(p.accuracy, 0.0)
	assert_null(p.rng, "the legacy global randf")
	assert_eq((g.get_node("StateLight") as StateLight).get_state(), StateLight.State.OFF)


func test_a_rail_gatling_fires_at_the_rail_interval() -> void:
	var h := _harness("open_space")
	var g := _spawn(h, MID + Vector2(0, -400))
	g.suspend_ai()
	var a := g.get_node("Attack") as AttackController
	for _i in 3:
		a.tick(CONFIG.rail_stream_interval + 0.001)
	assert_eq(_bullets_under(h.root), 3, "one Gatling Stream round per rail_stream_interval")


# ── The pressure window (dual) ───────────────────────────────────────────────────────────────────

## A long budget so the Assault run reaches a second window (the private config, not the .tres).
func _long_budget(c: GatlingInterceptorConfig) -> void:
	c.engage_seconds = 60.0


func _natural_run(mode: String, seconds: float = 16.0) -> Dictionary:
	var h := _harness(mode)
	var g := _spawn(h, MID + Vector2(-300, -560), _long_budget)
	return _simulate(h, g, seconds)


func test_a_window_runs_the_whole_phase_sequence(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var run := _natural_run(mode)
	var seq := _sequence(run)
	var expected := [P.APPROACH, P.SWING_IN, P.SPIN_UP, P.STREAM, P.COOLDOWN, P.REPOSITION, P.SWING_IN]
	assert_gte(seq.size(), expected.size(), "%s: %s" % [mode, seq])
	assert_eq(seq.slice(0, expected.size()), expected, mode)


func test_the_light_tells_the_window(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var run := _natural_run(mode)
	var bad := 0
	for r in run.ticks:
		var want := StateLight.State.OFF
		if r.phase == P.SWING_IN or r.phase == P.SPIN_UP:
			want = StateLight.State.CHARGING
		elif r.phase == P.STREAM:
			want = StateLight.State.ARMED
		if r.light != want:
			bad += 1
	assert_eq(bad, 0, "%s: CHARGING through SWING_IN and SPIN_UP, ARMED in STREAM, OFF otherwise" % mode)


func test_spin_up_stream_and_cooldown_cadence(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var run := _natural_run(mode)
	for s in _stretches(run, P.SPIN_UP):
		assert_almost_eq(s.ticks * DT, CONFIG.spin_up_seconds, DT + 0.001, "%s: SPIN_UP length" % mode)
	for s in _stretches(run, P.COOLDOWN):
		if s.t1 < run.ticks[-1].t:
			assert_almost_eq(s.ticks * DT, CONFIG.cooldown_seconds, DT + 0.001, "%s: COOLDOWN length" % mode)
	var silent := 0
	for shot in run.shots:
		if shot.phase0 != P.STREAM:
			silent += 1
	assert_eq(silent, 0, "%s: no round outside STREAM (0 in SPIN_UP and COOLDOWN)" % mode)
	var streams := _streams(run)
	assert_gte(streams.size(), 2, "%s: at least two windows" % mode)
	var stream_stretches := _stretches(run, P.STREAM)
	for k in streams.size():
		var shots: Array = streams[k]
		if k < streams.size() - 1 or run.ticks[-1].phase != P.STREAM:
			assert_between(shots.size(), CONFIG.stream_rounds_min, CONFIG.stream_rounds_max, "%s: N" % mode)
			assert_eq(shots.size(), stream_stretches[k].entry.rounds, "%s: N equals stream_rounds" % mode)
		for j in range(1, shots.size()):
			assert_almost_eq(shots[j].t - shots[j - 1].t, CONFIG.stream_interval, DT + 0.001,
				"%s: round gap" % mode)


## Staged straight into STREAM for seeds 1..40: the draw covers both ends of [8, 12] and nothing outside.
func test_a_seed_sweep_sees_8_and_12_rounds_and_nothing_else() -> void:
	var h := _harness("open_space")
	var seen := {}
	for s in range(1, 41):
		var g := _spawn(h, MID + Vector2(CONFIG.preferred_range, 0), Callable(), s)
		var brain := _brain(g)
		brain.enter_phase(P.STREAM)
		var run := _simulate(h, g, 2.0, func(r: Dictionary) -> bool: return r.phase != P.STREAM)
		var n: int = run.shots.size()
		assert_eq(n, brain.stream_rounds, "seed %d fires exactly its N" % s)
		seen[n] = true
		g.free()
	for n in seen:
		assert_between(n as int, CONFIG.stream_rounds_min, CONFIG.stream_rounds_max)
	assert_true(seen.has(CONFIG.stream_rounds_min), "N = 8 occurs: %s" % [seen.keys()])
	assert_true(seen.has(CONFIG.stream_rounds_max), "N = 12 occurs: %s" % [seen.keys()])


func test_every_stream_is_fired_side_on(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var run := _natural_run(mode, 20.0)
	var streamed := 0
	for r in run.ticks:
		if r.phase0 != P.STREAM:
			continue
		streamed += 1
		var phi := absf(_bearing_deg(r.x, r.p))
		assert_between(phi, SIDE_ON_MIN_DEG, SIDE_ON_MAX_DEG, "%s t=%.2f: bearing %.1f°" % [mode, r.t, phi])
	assert_gt(streamed, 0)
	assert_gte(_streams(run).size(), 2, "%s: at least two windows checked" % mode)


func test_the_stream_leads_a_moving_player() -> void:
	var h := _harness("open_space")
	h.player.velocity = Vector2(150, 0)
	var g := _spawn(h, MID + Vector2(0, -380))
	_brain(g).enter_phase(P.STREAM)
	var run := _simulate(h, g, 1.5, func(r: Dictionary) -> bool: return r.phase != P.STREAM)
	assert_gt(run.shots.size(), 0)
	var lead := 0.0
	for s in run.shots:
		var to_player: Vector2 = (s.p - s.from).normalized()
		# Positive: the round points to the player's velocity side of the line to the player.
		lead += signf(to_player.cross(s.dir)) * signf(to_player.cross(s.pv)) * absf(to_player.angle_to(s.dir))
	assert_gt(lead / run.shots.size(), 0.0, "the mean round direction leads the player's current position")


# ── Sides (epic §2.6, review B3) ─────────────────────────────────────────────────────────────────

func _corridor_centre_x() -> float:
	return AssaultCorridorConstraint.new().inner_rect().get_center().x


func _sides_of_windows(run: Dictionary) -> Array:
	var sides: Array = []
	for w in _windows(run):
		sides.append(w.entry.side)
	return sides


## The first window comes from the open half: the player sits 150 px left of centre (review N7: not a
## tie), and the first SWING_IN's flank point is in the right half.
func test_assault_first_window_is_on_the_half_opposite_the_player() -> void:
	var h := _harness("assault")
	h.player.global_position = Vector2(_corridor_centre_x() - 150.0, MID.y)
	var g := _spawn(h, Vector2(_corridor_centre_x() - 300.0, MID.y - 560.0))
	var run := _simulate(h, g, 6.0, func(r: Dictionary) -> bool: return r.phase == P.SWING_IN)
	var swing := _windows(run)
	assert_eq(swing.size(), 1, "reached the first SWING_IN")
	assert_gt(swing[0].entry.flank.x, _corridor_centre_x(), "the first flank point is in the right half")
	assert_eq(swing[0].entry.side, 1.0)


func test_assault_later_windows_alternate_sides() -> void:
	var h := _harness("assault")
	h.player.global_position = Vector2(_corridor_centre_x() - 150.0, MID.y)
	var g := _spawn(h, Vector2(_corridor_centre_x() - 300.0, MID.y - 560.0), _long_budget)
	var run := _simulate(h, g, 20.0)
	var sides := _sides_of_windows(run)
	assert_gte(sides.size(), 3, "three windows: %s" % [sides])
	for k in range(1, sides.size()):
		assert_eq(sides[k], -sides[k - 1], "window %d flips: %s" % [k, sides])


func _wall_run(min_flank_range: float) -> Array:
	var h := _harness("assault")
	var rect := AssaultCorridorConstraint.new().inner_rect()
	h.player.global_position = Vector2(rect.end.x - 100.0, MID.y)
	var g := _spawn(h, Vector2(rect.end.x - 300.0, MID.y - 560.0), func(c: GatlingInterceptorConfig) -> void:
		c.engage_seconds = 60.0
		c.min_flank_range = min_flank_range)
	var run := _simulate(h, g, 20.0)
	var out: Array = []
	for w in _windows(run):
		out.append({"side": w.entry.side, "fx": w.entry.flank.x, "px": w.entry.p.x})
	return out


## A player hugging the right wall: the flipped flank point would sit within `min_flank_range` of it,
## so every window stays on the open (left) side.
func test_assault_a_player_hugging_a_wall_keeps_every_window_on_the_open_side() -> void:
	var windows := _wall_run(CONFIG.min_flank_range)
	assert_gte(windows.size(), 3, "%s" % [windows])
	for w in windows:
		assert_eq(w.side, -1.0, "%s" % [windows])
		assert_lt(w.fx, w.px, "the flank point is left of the player")


## Boundary: the same run with the exception off flips — so the case above can fail.
func test_assault_without_the_wall_exception_the_same_run_flips() -> void:
	var windows := _wall_run(0.0)
	assert_gte(windows.size(), 2, "%s" % [windows])
	var flipped := false
	for w in windows:
		if w.side == 1.0:
			flipped = true
	assert_true(flipped, "with min_flank_range 0 a later window takes the wall side: %s" % [windows])


func test_open_space_windows_alternate_sides() -> void:
	var run := _natural_run("open_space", 20.0)
	var sides := _sides_of_windows(run)
	assert_gte(sides.size(), 3, "%s" % [sides])
	for k in range(1, sides.size()):
		assert_eq(sides[k], -sides[k - 1], "window %d flips: %s" % [k, sides])


## The swing round to the other flank never cuts across the player.
func test_open_space_swings_never_come_inside_min_flank_range() -> void:
	var run := _natural_run("open_space", 20.0)
	var past_first := false
	var closest := INF
	for r in run.ticks:
		if r.phase == P.SWING_IN:
			past_first = true
		if past_first:
			closest = minf(closest, r.x.distance_to(r.p))
	assert_true(past_first)
	assert_gte(closest, CONFIG.min_flank_range, "closest %.1f px" % closest)



## Review A2: a player near the corridor top. Going round ahead, the clamped ring waypoints would sit
## ~65 px above the player and the swing would fly straight over it, so the swing goes round behind.
func _corridor_top_closest(fallback: bool) -> float:
	var h := _harness("assault")
	var rect := AssaultCorridorConstraint.new().inner_rect()
	h.player.global_position = Vector2(rect.get_center().x, rect.position.y + 130.0)
	var g := _spawn(h, h.player.global_position + Vector2(-300, 200), _long_budget)
	_brain(g).route_fallback = fallback
	var run := _simulate(h, g, 20.0)
	assert_gte(_windows(run).size(), 3, "fallback=%s: three windows" % fallback)
	var past_first := false
	var closest := INF
	for r in run.ticks:
		if r.phase == P.SWING_IN:
			past_first = true
		if past_first:
			closest = minf(closest, r.x.distance_to(r.p))
	return closest


func test_assault_swings_round_behind_a_player_near_the_corridor_top() -> void:
	var closest := _corridor_top_closest(true)
	assert_gte(closest, CONFIG.min_flank_range, "closest %.1f px" % closest)


## Boundary: with the fallback off the same run cuts over the player — so the case above can fail.
func test_assault_without_the_route_fallback_the_swing_cuts_over_the_player() -> void:
	var closest := _corridor_top_closest(false)
	assert_lt(closest, CONFIG.min_flank_range, "closest %.1f px" % closest)


# ── Budget (epic §2.6, review B4) ────────────────────────────────────────────────────────────────

## Assault, player at the corridor centre (the first side is +1, the tie rule): a spawn within
## `swing_in_reach` of the first flank point, so APPROACH hands over on its first tick.
func _staged_near_flank(h: RefCounted, engage: float, offset: Vector2 = Vector2(0, -100)) -> GatlingInterceptor:
	var f := MID + Vector2(CONFIG.preferred_range, -GatlingInterceptorBrain.ASSAULT_FLANK_AHEAD)
	return _spawn(h, f + offset, func(c: GatlingInterceptorConfig) -> void: c.engage_seconds = engage)


## No false telegraph: APPROACH reaches its hand-over with less than `swing_in_max` of budget left, so it
## holds in REPOSITION instead of starting a window; the light never turns yellow and it leaves when the
## budget runs out.
func test_with_less_budget_than_swing_in_max_no_window_starts() -> void:
	var h := _harness("assault")
	var g := _staged_near_flank(h, CONFIG.swing_in_max - 0.1)
	var run := _simulate(h, g, 4.0)
	assert_eq(run.ticks[0].phase, P.REPOSITION, "the hand-over holds in REPOSITION")
	for r in run.ticks:
		assert_ne(r.phase, P.SWING_IN)
		assert_ne(r.light, StateLight.State.CHARGING)
	assert_eq(run.shots.size(), 0)
	assert_true(P.DISENGAGE in _sequence(run), "%s" % [_sequence(run)])


## The other side of the same boundary: one tick more than `swing_in_max` left starts the window.
func test_with_just_enough_budget_the_window_starts() -> void:
	var h := _harness("assault")
	var g := _staged_near_flank(h, CONFIG.swing_in_max + 2.0 * DT)
	var run := _simulate(h, g, 0.1)
	assert_eq(run.ticks[0].phase, P.SWING_IN)
	assert_eq(run.ticks[0].light, StateLight.State.CHARGING)


## Budget expiry mid-stream: the stream still fires all its rounds, then DISENGAGE (never COOLDOWN). The
## acceptance bound is the epic's 2.08 s (spin-up + `sync_wait_max` + the longest stream); a solo Gatling
## never waits, so it also meets the tighter solo bound — a SPIN_UP that wrongly held for
## `sync_wait_max` would pass 2.08 and fail this.
##
## Staged in two runs: the first, with a long budget, measures when the stream starts from this spawn;
## the second sets the budget to expire 0.3 s into it.
func test_budget_expiry_during_a_stream_defers_disengage_to_its_end() -> void:
	var offset := Vector2(0, -280)
	var probe_h := _harness("assault")
	var probe := _staged_near_flank(probe_h, 60.0, offset)
	var probe_run := _simulate(probe_h, probe, 4.0, func(r: Dictionary) -> bool: return r.phase == P.STREAM)
	var stream_at: float = probe_run.ticks[-1].t
	# Out of the tree (TargetInfo reads the first player in it); add_child_autofree still frees it.
	probe_h.root.get_parent().remove_child(probe_h.root)
	var engage := stream_at + 0.3
	assert_gte(engage, CONFIG.swing_in_max, "sanity: the window can start with this budget")

	var h := _harness("assault")
	var g := _staged_near_flank(h, engage, offset)
	var brain := _brain(g)
	# A lambda captures locals by value: the expiry is recorded in a shared Dictionary.
	var expiry := {"at": -1.0, "in": -1}
	var run := _simulate(h, g, 6.0, func(r: Dictionary) -> bool:
		if expiry.at < 0.0 and r.budget_left <= 0.0:
			expiry.at = r.t
			expiry.in = r.phase0
		return r.phase == P.DISENGAGE)
	var expired_at: float = expiry.at
	var expired_in: int = expiry.in
	assert_eq(expired_in, P.STREAM, "the budget expired mid-stream")
	var last: Dictionary = run.ticks[-1]
	assert_eq(last.phase, P.DISENGAGE)
	assert_eq(last.phase0, P.STREAM, "DISENGAGE starts on the tick the stream ends, never COOLDOWN")
	assert_eq(_streams(run)[-1].size(), brain.stream_rounds, "the stream fired all its rounds")
	var bound := CONFIG.spin_up_seconds + CONFIG.sync_wait_max + CONFIG.stream_rounds_max * CONFIG.stream_interval
	assert_almost_eq(bound, 2.08, 0.001)
	assert_lte(last.t - expired_at, bound, "DISENGAGE within 2.08 s of expiry")
	var solo := CONFIG.spin_up_seconds + (CONFIG.stream_rounds_max - 1) * CONFIG.stream_interval + 2.0 * DT
	assert_lte(last.t - expired_at, solo, "and within the solo bound")


func test_budget_expiry_in_reposition_disengages_on_the_same_tick() -> void:
	var h := _harness("assault")
	var g := _spawn(h, MID + Vector2(-380, -60), func(c: GatlingInterceptorConfig) -> void:
		c.engage_seconds = 0.5)
	var brain := _brain(g)
	brain.enter_phase(P.REPOSITION)
	var run := _simulate(h, g, 1.0, func(r: Dictionary) -> bool: return r.phase == P.DISENGAGE)
	var last: Dictionary = run.ticks[-1]
	assert_eq(last.phase, P.DISENGAGE)
	assert_eq(last.phase0, P.REPOSITION)
	assert_lte(last.budget_left, 0.0)
	assert_gt(run.ticks[-2].budget_left, 0.0, "the tick before, the budget had not expired")


func test_assault_disengage_frees_the_gatling_outside_the_world_rect() -> void:
	var h := _harness("assault")
	var g := _spawn(h, MID + Vector2(200, 0))
	_brain(g).enter_phase(P.DISENGAGE)
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var run := _simulate(h, g, 25.0)
	assert_true(run.freed, "the Gatling leaves and frees itself")
	assert_false(rect.has_point(g.global_position), "and it was outside the world rect when freed")


func test_open_space_never_disengages() -> void:
	var h := _harness("open_space")
	var g := _spawn(h, MID + Vector2(700, 0), func(c: GatlingInterceptorConfig) -> void: c.engage_seconds = 0.1)
	var run := _simulate(h, g, 3.0)
	assert_false(P.DISENGAGE in _sequence(run))
	assert_false(g.is_queued_for_deletion())


func test_assault_stays_in_the_corridor_until_disengage() -> void:
	var h := _harness("assault")
	var g := _spawn(h, MID + Vector2(-300, -560))
	var soft := AssaultCorridorConstraint.new()
	var band := soft.inner_rect().grow(soft.soft_band)
	var run := _simulate(h, g, 12.0)
	var entered := false
	for r in run.ticks:
		if r.phase == P.DISENGAGE:
			break
		entered = entered or soft.inner_rect().has_point(r.x)
		if not entered:
			continue
		assert_true(band.has_point(r.x), "t=%.2f %s at %s" % [r.t, r.phase, r.x])


func test_phase_changed_carries_the_phase_entered() -> void:
	var h := _harness("open_space")
	var g := _spawn(h, MID + Vector2(900, 0))
	watch_signals(_brain(g))
	_brain(g).enter_phase(P.COOLDOWN)
	assert_signal_emitted_with_parameters(_brain(g), "phase_changed", [P.COOLDOWN])
