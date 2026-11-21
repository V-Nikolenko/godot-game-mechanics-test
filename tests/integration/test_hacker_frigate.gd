## The Hacker Frigate's shell and movement (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.10; Phase 9 t8, task plan
## docs/plans/cmw5k4yk400aiqs2xujalkqzf/3-plan.md). Intent tests, both harnesses unless a row says otherwise.
##
## Hand-ticked at 1/60 (`_tick`: `_physics_process(dt)`, then the position integrated from the velocity, the corvette tests' shape); the test
## moves the harness player itself. `_spawn()` writes `engage_seconds = 1000` and then the row's own config fields onto the instance's private
## config before `add_child` (the budget is live in the Assault harness and would end every long row at 9 s); only the Assault-life rows put
## the shipped 9.0 back. It also writes `first_pulse_delay = 1000` (t9): these are movement rows, so the Hijack Pulse stays off in them; the
## Assault-life rows put the shipped 2.0 back, and `test_hijack_pulse.gd` covers the arc through TELEGRAPH and PULSE. Every behaviour row has a
## control that switches the behaviour off and fails the same bound.
##
## Assault placement (every Assault row but the life rows): the player at (640, 620), centred 100 px above the view's bottom edge, facing UP,
## the hull started on its 520 ring at the bearing the row names (0° = straight above). The ring fits inside the clamp rect up to ≈ 93° from
## straight up, and every row keeps the hull inside that sector.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const PH9: GDScript = preload("res://tests/helpers/ph9_exit_keys.gd")
const PROBE: GDScript = preload("res://tests/helpers/specialist_exit_probe.gd")
const SINGLE_WRITER: GDScript = preload("res://tests/integration/test_enemy_mover_single_writer.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/hacker_frigate/hacker_frigate.tscn")
const SHIPPED: HackerFrigateConfig = preload("res://assault/scenes/enemies/hacker_frigate/hacker_frigate_config.tres")  # read only
const Phase := HackerFrigateBrain.Phase

const DT := 1.0 / 60.0
const MODES := ["open_space", "assault"]
const ASSAULT_PLAYER := Vector2(640.0, 620.0)
const VIEW_BAND := -60.0
## The cone rows' bounds (plan §2.10): nose 2.2 s at 720 px, 1.9 s at 520 px; route 1.8 s; far-way time 0.5 s.
const NOSE_BOUND_OS := 2.2
const NOSE_BOUND_ASSAULT := 1.9
const ROUTE_BOUND := 1.8
const FAR_WAY_BOUND := 0.5
const RESNAP_AFTER := 3.5
const SNAP_DEG := 10.0
## The cone cases: [forced orbit direction, far way?].
const CASES := {"cw_far": [1, true], "ccw_far": [-1, true], "cw_near": [1, false]}

var _exit: Dictionary = {}
var _probe_s: float = 0.0
var _roots: Array[Node] = []


func after_each() -> void:
	_roots.clear()


func before_all() -> void:
	var t0 := Time.get_ticks_usec()
	_exit = PH9.hacker_exit(self)
	_probe_s = float(Time.get_ticks_usec() - t0) / 1e6


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

## A fresh harness world. Any earlier world of this test is taken out of the tree first: its player would still be in group `player`
## (and its camera an arena), and `TargetInfo.player()` reads the first one it finds. It is still freed with the test.
func _world(mode: String):
	for old in _roots:
		if is_instance_valid(old) and old.is_inside_tree():
			old.get_parent().remove_child(old)
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	_roots.append(h.root)
	h.player.global_position = ASSAULT_PLAYER if h.is_assault else Vector2.ZERO
	return h


func _spawn(h, pos: Vector2, props: Dictionary = {}, seed: int = 1, engaged: bool = true) -> HackerFrigate:
	var hacker := SCENE.instantiate() as HackerFrigate
	var brain := hacker.get_node("Brain") as HackerFrigateBrain
	brain.start_engaged = engaged
	brain.rng_seed = seed
	hacker.config.engage_seconds = 1000.0
	hacker.config.first_pulse_delay = 1000.0  # movement rows: the pulse (t9) stays off unless a row puts it back
	for key in props:
		hacker.config.set(key, props[key])
	hacker.global_position = pos
	h.root.add_child(hacker)
	hacker.set_physics_process(false)  # hand-ticked
	return hacker


func _tick(hacker: HackerFrigate, delta: float = DT) -> void:
	var before := hacker.global_position
	hacker._physics_process(delta)
	hacker.global_position = before + hacker.velocity * delta


## One tick of the hull, then the player moves on its own velocity.
func _step(hacker: HackerFrigate, player: CharacterBody2D) -> void:
	_tick(hacker)
	player.global_position += player.velocity * DT


func _brain(hacker: HackerFrigate) -> HackerFrigateBrain:
	return hacker.get_node("Brain") as HackerFrigateBrain


## The point on a ring of `radius` round `centre`, `deg` degrees clockwise (on screen) from straight above.
func _on_ring(centre: Vector2, radius: float, deg: float) -> Vector2:
	return centre + Vector2.RIGHT.rotated(-PI / 2.0 + deg_to_rad(deg)) * radius


## Degrees of the hull's bearing from the player, measured from straight above (clockwise positive).
func _from_up_deg(hacker: Node2D, player: Node2D) -> float:
	return rad_to_deg(wrapf((hacker.global_position - player.global_position).angle() + PI / 2.0, -PI, PI))


## The sign of the hull's angular motion round the player (+1 = the bearing angle grows), from the velocity relative to the player's.
func _angular_sign(hacker: CharacterBody2D, player: CharacterBody2D) -> float:
	var b := (hacker.global_position - player.global_position).normalized()
	var rel := hacker.velocity - player.velocity
	return signf(b.cross(rel))


func _view_inner(h) -> Rect2:
	return EnemyWorld.view_rect(h.root.get_tree()).grow(VIEW_BAND)


# ── Structure ────────────────────────────────────────────────────────────────────────────────────

func test_the_scene_shares_one_40_px_circle_and_collides_for_15() -> void:
	var h = _world("open_space")
	var hacker := _spawn(h, Vector2(0.0, -720.0))
	var body := hacker.get_node("CollisionShape2D") as CollisionShape2D
	assert_true(body.shape is CircleShape2D)
	assert_eq((body.shape as CircleShape2D).radius, 40.0)
	assert_same((hacker.get_node("HurtBox/CollisionShape2D") as CollisionShape2D).shape, body.shape)
	assert_same((hacker.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D).shape, body.shape)
	assert_eq(hacker.contact_profile.mode, ContactProfile.Mode.COLLISION)
	assert_eq(hacker.contact_hit_box.damage, 15)
	assert_eq(hacker.health.max_health, 120)
	assert_eq(hacker.score_value, 90)
	assert_eq(hacker.sprite_forward_angle, PI / 2.0, "nose-down hull art")
	assert_eq(hacker.body_radius(), 40.0)
	assert_not_null(hacker.dish(), "the antenna part t9 unfolds")
	assert_not_null(hacker.state_light(), "the light on the dish")
	assert_eq(hacker.state_light().get_parent(), hacker.dish())
	assert_true(hacker.is_in_group(&"enemies"))
	assert_true(hacker.is_ai_driven())


func test_the_config_is_applied_to_the_mover_and_the_brain() -> void:
	var h = _world("open_space")
	var hacker := _spawn(h, Vector2(0.0, -720.0))
	var mover := hacker.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.max_speed, 230.0)
	assert_eq(mover.acceleration, 700.0, "the Support Ship's: the cone escape needs it")
	assert_eq(mover.max_turn_rate, 1.4)
	assert_eq(mover.hazard_avoidance, 0.7)
	assert_eq(mover.hazard_margin, 80.0)
	assert_eq(mover.hazard_resistance, 0.4)
	assert_same(_brain(hacker).config, hacker.config)


## Plan §2.10 / §2.19 starting values, read off the shipped `.tres`.
func test_the_shipped_numbers() -> void:
	var c := SHIPPED
	assert_eq([c.preferred_range, c.assault_preferred_range, c.range_drift, c.min_range], [720.0, 520.0, 90.0, 420.0])
	assert_eq([c.orbit_speed_cw, c.orbit_speed_ccw, c.cone_escape_speed, c.reversal_min, c.reversal_max], [0.18, 0.3, 0.3, 3.0, 6.0])
	assert_eq([c.nose_cone_deg, c.route_cone_deg, c.route_min_speed], [30.0, 25.0, 80.0])
	assert_eq([c.break_speed, c.break_lateral_weight, c.break_burst_seconds, c.break_exit_margin, c.break_max_seconds, c.break_rearm_seconds],
			[360.0, 0.25, 0.8, 120.0, 3.0, 1.0])
	assert_eq([c.view_margin, c.engage_seconds, c.exit_speed], [60.0, 9.0, 300.0])
	assert_eq([c.perceive_radius, c.lose_radius, c.notice_time, c.idle_radius, c.idle_speed], [760.0, 1600.0, 0.35, 160.0, 0.45])
	assert_eq([c.wreck_chance, c.wreck_size], [0.4, 1])
	assert_lt(c.orbit_speed_ccw * c.preferred_range, c.max_speed, "the fast arc (216 px/s) stays under max_speed")
	assert_gt(c.lose_radius, c.preferred_range + c.range_drift + c.min_range + c.break_exit_margin - c.min_range,
			"its own fight never reads as losing the player")
	assert_gt(c.lose_radius, c.perceive_radius, "AnchorIdle's hysteresis margin")


func test_the_phase_enum_is_append_only() -> void:
	assert_eq([Phase.HOLD_ARC, Phase.TELEGRAPH, Phase.PULSE, Phase.BREAK_OFF, Phase.DISENGAGE, Phase.IDLE, Phase.NOTICING, Phase.RETURNING],
			[0, 1, 2, 3, 4, 5, 6, 7])


func test_the_wave_builder_spawns_it() -> void:
	assert_eq(WaveBuilder.HACKER_FRIGATE, "res://assault/scenes/enemies/hacker_frigate/hacker_frigate.tscn")
	var b := WaveBuilder.new()
	assert_eq(b.hacker_frigate()._scene, WaveBuilder.HACKER_FRIGATE)
	assert_true(ResourceLoader.exists(WaveBuilder.HACKER_FRIGATE))


# ── Holds range ──────────────────────────────────────────────────────────────────────────────────

## Ticks until the hull's distance to the player first lies in `band`, then whether it stayed there to the end; -1 if never.
func _range_run(h, hacker: HackerFrigate, seconds: float, band: Vector2) -> Dictionary:
	var first := -1
	var left_after := false
	var worst := Vector2(INF, -INF)
	for i in int(round(seconds / DT)):
		_step(hacker, h.player)
		var d := hacker.global_position.distance_to(h.player.global_position)
		var inside := d >= band.x and d <= band.y
		if first < 0 and inside:
			first = i
		if first >= 0:
			worst = Vector2(minf(worst.x, d), maxf(worst.y, d))
			if not inside:
				left_after = true
	return {"first": first, "left_after": left_after, "worst": worst}


func test_it_holds_its_range_against_a_still_player(mode: String = use_parameters(MODES)) -> void:
	var cones := {"nose_cone_deg": 0.0, "route_cone_deg": 0.0}
	# On the ring: Open Space 20 s with the shipped reversals and drift; Assault 6 s from -30° on the 0.18 arc, reversals held.
	var h = _world(mode)
	var props := cones.duplicate()
	if h.is_assault:
		props.merge({"reversal_min": 30.0, "reversal_max": 30.0})
	var start: Vector2 = _on_ring(h.player.global_position, 520.0, -30.0) if h.is_assault else _on_ring(h.player.global_position, 720.0, 0.0)
	var hacker := _spawn(h, start, props)
	var brain := _brain(hacker)
	if h.is_assault:
		brain.force_orbit_direction(1)
	var band := Vector2(brain.held_range() - (SHIPPED.range_drift + 60.0), brain.held_range() + SHIPPED.range_drift + 60.0)
	var seconds := 6.0 if h.is_assault else 20.0
	var on_ring := _range_run(h, hacker, seconds, band)
	assert_eq(on_ring["first"], 0, "%s: in the band from the first tick" % mode)
	assert_false(on_ring["left_after"], "%s: and it never left it (worst %s)" % [mode, on_ring["worst"]])
	# The far start: it closes into the band within 3 s and stays.
	var far_d := 900.0 if h.is_assault else 1100.0
	var h2 = _world(mode)
	var far := _spawn(h2, _on_ring(h2.player.global_position, far_d, 0.0 if h.is_assault else 30.0), props)
	if h2.is_assault:
		_brain(far).force_orbit_direction(1)
	var closing := _range_run(h2, far, seconds, band)
	assert_between(int(closing["first"]), 1, int(3.0 / DT), "%s: in the band within 3 s (tick %d)" % [mode, closing["first"]])
	assert_false(closing["left_after"], "%s: and stays (worst %s)" % [mode, closing["worst"]])
	# Control: a hull that cannot move never gets there.
	var h3 = _world(mode)
	var stuck_props := props.duplicate()
	stuck_props["max_speed"] = 1.0
	var stuck := _spawn(h3, _on_ring(h3.player.global_position, far_d, 0.0 if h.is_assault else 30.0), stuck_props)
	if h3.is_assault:
		_brain(stuck).force_orbit_direction(1)
	var control := _range_run(h3, stuck, seconds, band)
	assert_eq(control["first"], -1, "%s control: max_speed 1 never reaches the band" % mode)


# ── Asymmetric arcs and reversals ────────────────────────────────────────────────────────────────

## The hull's bearing rate (rad/s, signed) over 3 s after a 1 s settle, forced in `dir`, reversals held, cones 0, no drift.
func _arc_rate(mode: String, dir: int, extra: Dictionary = {}) -> float:
	var h = _world(mode)
	var props := {"nose_cone_deg": 0.0, "route_cone_deg": 0.0, "range_drift": 0.0, "reversal_min": 30.0, "reversal_max": 30.0}
	props.merge(extra, true)
	var start_deg := (-40.0 * dir) if h.is_assault else 0.0
	var hacker := _spawn(h, _on_ring(h.player.global_position, 520.0 if h.is_assault else 720.0, start_deg), props)
	_brain(hacker).force_orbit_direction(dir)
	for _i in 60:
		_step(hacker, h.player)
	var total := 0.0
	for _i in 180:
		var before: float = (hacker.global_position - h.player.global_position).angle()
		_step(hacker, h.player)
		total += wrapf((hacker.global_position - h.player.global_position).angle() - before, -PI, PI)
		assert_false(_brain(hacker).view_clamp_bound, "%s: the clamp never binds" % mode)
	assert_eq(_brain(hacker).phase, Phase.HOLD_ARC, "%s: still on the arc" % mode)
	return total / 3.0


func test_the_arc_is_lopsided_018_one_way_and_030_the_other(mode: String = use_parameters(MODES)) -> void:
	var cw := _arc_rate(mode, 1)
	var ccw := _arc_rate(mode, -1)
	gut.p("%s: hull bearing rate %+.4f (cw) / %+.4f (ccw) rad/s" % [mode, cw, ccw])
	assert_almost_eq(cw, 0.18, 0.01, "%s: +1 is the 0.18 rad/s arc, the bearing angle growing (clockwise on screen)" % mode)
	assert_almost_eq(ccw, -0.30, 0.01, "%s: -1 is the 0.30 rad/s arc" % mode)
	# Control: equal speeds give equal rates.
	var even := {"orbit_speed_ccw": SHIPPED.orbit_speed_cw}
	var c_cw := _arc_rate(mode, 1, even)
	var c_ccw := _arc_rate(mode, -1, even)
	assert_lt(absf(absf(c_cw) - absf(c_ccw)), 0.01, "%s control: one speed both ways is not lopsided" % mode)
	assert_gt(absf(absf(cw) - absf(ccw)), 0.1, "%s: the shipped arcs differ" % mode)


## Sign changes of `orbit_dir` in 10 s on the shipped reversal clock, and whether the brain stayed in HOLD_ARC.
func _reversals(mode: String, seed: int, extra: Dictionary = {}) -> Dictionary:
	var h = _world(mode)
	var props := {"nose_cone_deg": 0.0, "route_cone_deg": 0.0, "range_drift": 0.0}
	props.merge(extra, true)
	var hacker := _spawn(h, _on_ring(h.player.global_position, 520.0 if h.is_assault else 720.0, 0.0), props, seed)
	var brain := _brain(hacker)
	_tick(hacker)
	var flips := 0
	var last := brain.orbit_dir
	var left := false
	for _i in 600:
		_step(hacker, h.player)
		if brain.orbit_dir != last:
			flips += 1
			last = brain.orbit_dir
		if brain.phase != Phase.HOLD_ARC:
			left = true
	return {"flips": flips, "left": left}


func test_the_arc_reverses_at_random_3_to_6_s_over_four_seeds(mode: String = use_parameters(MODES)) -> void:
	for seed in [1, 2, 3, 4]:
		var run := _reversals(mode, seed)
		assert_gte(int(run["flips"]), 1, "%s seed %d: at least one reversal in 10 s" % [mode, seed])
		assert_lte(int(run["flips"]), 3, "%s seed %d: no more than 10 / 3 s allows" % [mode, seed])
		assert_false(run["left"], "%s seed %d: never left HOLD_ARC" % [mode, seed])
		var held := _reversals(mode, seed, {"reversal_min": 30.0, "reversal_max": 30.0})
		assert_eq(int(held["flips"]), 0, "%s seed %d control: a 30 s clock never reverses in 10 s" % [mode, seed])


# ── The cones (plan §2.10 cone-row procedure) ────────────────────────────────────────────────────

## One snap-and-measure of a cone row on a running hull. `kind` "nose" or "route", `far` whether the snap puts its motion toward the far
## edge. Returns {exit_t (s or -1), exit_near (bool), far_t (s), inside_at_bound, clamp_bound, out_of_view, motion_sign}.
func _snap_and_measure(h, hacker: HackerFrigate, kind: String, far: bool, cone_deg: float, bound: float, write_cone: bool) -> Dictionary:
	var player: CharacterBody2D = h.player
	var b := (hacker.global_position - player.global_position).angle()
	var s := _angular_sign(hacker, player)
	var axis := b + s * deg_to_rad(SNAP_DEG) * (1.0 if far else -1.0)
	if kind == "nose":
		player.rotation = axis + PI / 2.0  # TargetInfo.facing = UP.rotated(rotation)
	else:
		player.velocity = Vector2.RIGHT.rotated(axis) * 100.0
	if write_cone:
		if kind == "nose":
			hacker.config.nose_cone_deg = cone_deg
		else:
			hacker.config.route_cone_deg = cone_deg
	var far_sign := s if far else -s
	var cone := deg_to_rad(cone_deg)
	var out := {"exit_t": -1.0, "exit_near": false, "far_t": 0.0, "inside_at_bound": false, "clamp_bound": false, "out_of_view": false,
		"motion_sign": s}
	var bound_tick := int(round(bound / DT))
	var limit := maxi(bound_tick, int(round(6.0 / DT)))
	for i in range(1, limit + 1):
		_step(hacker, player)
		var a := wrapf((hacker.global_position - player.global_position).angle() - axis, -PI, PI)
		if h.is_assault:
			out["clamp_bound"] = bool(out["clamp_bound"]) or _brain(hacker).view_clamp_bound
			out["out_of_view"] = bool(out["out_of_view"]) or not _view_inner(h).has_point(hacker.global_position)
		if float(out["exit_t"]) < 0.0 and _angular_sign(hacker, player) == far_sign:
			out["far_t"] = float(out["far_t"]) + DT
		if i == bound_tick:
			out["inside_at_bound"] = absf(a) < cone
		if float(out["exit_t"]) < 0.0 and absf(a) >= cone:
			out["exit_t"] = i * DT
			out["exit_near"] = signf(a) == -far_sign
			if i >= bound_tick:
				break
		if float(out["exit_t"]) >= 0.0 and i >= bound_tick:
			break
	return out


## A fresh hull warmed up into a steady forced-direction orbit (cones 0, reversals held, no drift), then snapped and measured; in the main
## run (`cone_on`) re-snapped 3.5 s after its first exit and measured again.
func _cone_row(mode: String, kind: String, case: String, cone_on: bool) -> Array:
	var h = _world(mode)
	var dir: int = CASES[case][0]
	var far: bool = CASES[case][1]
	var radius := 520.0 if h.is_assault else 720.0
	var start_deg := 0.0
	if h.is_assault and not far:
		start_deg = -45.0 * dir  # it never turns back: start on the side it moves away from
	var start := _on_ring(h.player.global_position, radius, start_deg)
	var away: Vector2 = (h.player.global_position - start).normalized()  # from the hull, through the player
	if kind == "nose":
		h.player.rotation = away.angle() + PI / 2.0
	else:
		h.player.rotation = away.rotated(PI / 2.0).angle() + PI / 2.0  # facing across, so the nose cone never holds it
		h.player.velocity = away * 100.0
	var props := {"nose_cone_deg": 0.0, "route_cone_deg": 0.0, "range_drift": 0.0, "reversal_min": 30.0, "reversal_max": 30.0}
	var hacker := _spawn(h, start, props)
	_brain(hacker).force_orbit_direction(dir)
	for _i in 120:
		_step(hacker, h.player)
	var cone_deg := 30.0 if kind == "nose" else 25.0
	var bound := ROUTE_BOUND if kind == "route" else (NOSE_BOUND_ASSAULT if h.is_assault else NOSE_BOUND_OS)
	var runs: Array = []
	var first := _snap_and_measure(h, hacker, kind, far, cone_deg, bound, cone_on)
	assert_eq(int(first["motion_sign"]), dir, "%s %s %s: the warm-up orbit runs the forced way" % [mode, kind, case])
	runs.append(first)
	if cone_on and float(first["exit_t"]) >= 0.0:
		# Measured to the bound or the exit, whichever is later: run on to 3.5 s after the exit.
		var ticks_after := int(round(RESNAP_AFTER / DT)) - maxi(0, int(round(bound / DT)) - int(round(float(first["exit_t"]) / DT)))
		for _i in maxi(ticks_after, 0):
			_step(hacker, h.player)
		runs.append(_snap_and_measure(h, hacker, kind, far, cone_deg, bound, false))
	return runs


func _assert_main_cone_run(label: String, run: Dictionary, bound: float, assault: bool) -> void:
	assert_between(float(run["exit_t"]), 0.0, bound + 1e-6, "%s: out within %.1f s (%.2f s)" % [label, bound, run["exit_t"]])
	assert_true(run["exit_near"], "%s: through the near edge" % label)
	assert_lte(float(run["far_t"]), FAR_WAY_BOUND + 1e-6, "%s: at most %.1f s moving the far way (%.2f s)" % [label, FAR_WAY_BOUND, run["far_t"]])
	if assault:
		assert_false(run["clamp_bound"], "%s: the view clamp never binds" % label)
		assert_false(run["out_of_view"], "%s: the hull stays inside view_rect().grow(-60)" % label)


func test_it_slides_out_of_the_nose_through_the_near_edge(mode: String = use_parameters(MODES)) -> void:
	var bound := NOSE_BOUND_ASSAULT if mode == "assault" else NOSE_BOUND_OS
	for case in CASES:
		var runs := _cone_row(mode, "nose", case, true)
		assert_eq(runs.size(), 2, "%s %s: exited, then re-snapped" % [mode, case])
		for k in runs.size():
			var run: Dictionary = runs[k]
			gut.p("%s nose %s %s: exit %.3f s (near %s), far-way %.3f s" % [mode, case, "first" if k == 0 else "re-snap", run["exit_t"],
					run["exit_near"], run["far_t"]])
			_assert_main_cone_run("%s nose %s %s" % [mode, case, "first" if k == 0 else "re-snap"], run, bound, mode == "assault")


func test_with_the_nose_cone_off_the_far_way_cases_are_still_inside_at_the_bound(mode: String = use_parameters(MODES)) -> void:
	for case in ["cw_far", "ccw_far"]:
		var run: Dictionary = _cone_row(mode, "nose", case, false)[0]
		gut.p("%s nose control %s: exit %.3f s" % [mode, case, run["exit_t"]])
		assert_true(run["inside_at_bound"], "%s control %s: still inside ± 30° at the bound" % [mode, case])


func test_it_leaves_the_route_cone_of_a_100_px_s_player_through_the_near_edge() -> void:
	for case in CASES:
		var runs := _cone_row("open_space", "route", case, true)
		assert_eq(runs.size(), 2, "route %s: exited, then re-snapped" % case)
		for k in runs.size():
			var run: Dictionary = runs[k]
			gut.p("route %s %s: exit %.3f s (near %s), far-way %.3f s" % [case, "first" if k == 0 else "re-snap", run["exit_t"],
					run["exit_near"], run["far_t"]])
			_assert_main_cone_run("route %s %s" % [case, "first" if k == 0 else "re-snap"], run, ROUTE_BOUND, false)
	for case in ["cw_far", "ccw_far"]:
		var control: Dictionary = _cone_row("open_space", "route", case, false)[0]
		gut.p("route control %s: exit %.3f s" % [case, control["exit_t"]])
		assert_true(control["inside_at_bound"], "route control %s: still inside ± 25° at 1.8 s" % case)


## The documented limit: a player cruising at 360 px/s simply outruns it (max_speed 230).
func test_a_360_px_s_player_outruns_it() -> void:
	var h = _world("open_space")
	var hacker := _spawn(h, Vector2(0.0, -720.0))
	h.player.velocity = Vector2.DOWN * 360.0
	var grew := false
	for _i in int(5.0 / DT):
		_step(hacker, h.player)
		if hacker.global_position.distance_to(h.player.global_position) > _brain(hacker).held_range() + SHIPPED.range_drift:
			grew = true
			break
	assert_true(grew, "the distance passes held_range() + range_drift within 5 s")


## The cone sizes are read every tick: a cone written after the hull is running takes effect on the next tick.
func test_the_cone_sizes_are_read_every_tick() -> void:
	var h = _world("open_space")
	var hacker := _spawn(h, Vector2(0.0, -720.0), {"nose_cone_deg": 0.0, "route_cone_deg": 0.0})
	_step(hacker, h.player)
	assert_false(_brain(hacker).in_cone, "cone 0: never inside")
	hacker.config.nose_cone_deg = 30.0
	_step(hacker, h.player)
	assert_true(_brain(hacker).in_cone, "the player faces UP at it: inside the 30° nose cone")
	assert_eq(_brain(hacker).cone_kind, &"nose")


# ── Break-off ────────────────────────────────────────────────────────────────────────────────────

## A rusher at `speed` px/s re-aimed at the hull every tick from 600 px for `rush_s`, then still for `after_s`.
func _rush(props: Dictionary, speed: float, rush_s: float, after_s: float) -> Dictionary:
	var h = _world("open_space")
	var hacker := _spawn(h, Vector2(0.0, -600.0), props)
	var brain := _brain(hacker)
	var out := {"d_min": INF, "first_inside": -1, "first_break": -1, "radial_first": 0.0, "last_not_arc": -1, "phase_end": -1, "stop": 0,
		"entries": [], "exits": []}
	var prev := Phase.HOLD_ARC
	var ticks := int(round((rush_s + after_s) / DT))
	out["stop"] = int(round(rush_s / DT))
	for i in ticks:
		if i < int(out["stop"]):
			h.player.velocity = (hacker.global_position - h.player.global_position).normalized() * speed
		else:
			h.player.velocity = Vector2.ZERO
		var away: Vector2 = (hacker.global_position - h.player.global_position).normalized()
		_step(hacker, h.player)
		var d := hacker.global_position.distance_to(h.player.global_position)
		out["d_min"] = minf(float(out["d_min"]), d)
		if int(out["first_inside"]) < 0 and d < SHIPPED.min_range:
			out["first_inside"] = i
		if brain.phase == Phase.BREAK_OFF and prev != Phase.BREAK_OFF:
			(out["entries"] as Array).append(i)
			if int(out["first_break"]) < 0:
				out["first_break"] = i
				out["radial_first"] = hacker.velocity.dot(away)
		if brain.phase != Phase.BREAK_OFF and prev == Phase.BREAK_OFF:
			(out["exits"] as Array).append(i)
		if i >= int(out["stop"]) and brain.phase != Phase.HOLD_ARC:
			out["last_not_arc"] = i
		prev = brain.phase
	out["phase_end"] = brain.phase
	return out


func test_a_300_px_s_rusher_never_gets_closer_than_360_px() -> void:
	var run := _rush({}, 300.0, 4.0, 6.0)
	gut.p("rusher: d_min %.1f px, first inside tick %d, BREAK_OFF tick %d, radial %.1f px/s" % [run["d_min"], run["first_inside"],
			run["first_break"], run["radial_first"]])
	assert_gte(int(run["first_inside"]), 0, "the rusher got inside min_range")
	assert_between(int(run["first_break"]) - int(run["first_inside"]), 0, 1, "BREAK_OFF within one tick of the first reading inside 420")
	assert_gte(float(run["d_min"]), 360.0, "never closer than 360 px")
	assert_almost_eq(float(run["radial_first"]), 360.0 / sqrt(1.25), 2.0, "the first burst opens at ≈ 322 px/s radially")
	var bound := (SHIPPED.min_range + SHIPPED.break_exit_margin - float(run["d_min"])) / (360.0 / sqrt(1.25)) + SHIPPED.break_rearm_seconds
	var resumed := (int(run["last_not_arc"]) + 1 - int(run["stop"])) * DT
	gut.p("rusher: HOLD_ARC for good %.2f s after the stop (bound %.2f s)" % [resumed, bound])
	assert_lte(resumed, bound + 1e-6, "HOLD_ARC resumes within (540 - d_min) / 322 + 1.0 s of the stop")
	assert_eq(int(run["phase_end"]), Phase.HOLD_ARC)
	# Control: no break-off, and the 230 px/s orbit cannot open on a 300 px/s rusher.
	var control := _rush({"min_range": 0.0}, 300.0, 4.0, 0.0)
	assert_eq(int(control["first_break"]), -1, "control: min_range 0 never breaks off")
	assert_lt(float(control["d_min"]), 340.0, "control: the rusher gets below 340 px (%.1f)" % control["d_min"])


func test_a_420_px_s_chase_ends_the_break_off_at_3_s_and_rearms_for_1_s() -> void:
	var run := _rush({}, 420.0, 7.0, 0.0)
	var entries: Array = run["entries"]
	var exits: Array = run["exits"]
	gut.p("chase: entries %s, exits %s" % [entries, exits])
	assert_gte(entries.size(), 2, "a second break-off")
	assert_gte(exits.size(), 1)
	assert_almost_eq((int(exits[0]) - int(entries[0])) * DT, SHIPPED.break_max_seconds, DT + 1e-6, "the first lasts 3.0 s")
	assert_gte((int(entries[1]) - int(exits[0])) * DT, SHIPPED.break_rearm_seconds - 1e-6, "the next waits the 1.0 s rearm")
	# Controls.
	var long := _rush({"break_max_seconds": 100.0}, 420.0, 3.2, 0.0)
	assert_eq((long["exits"] as Array).size(), 0, "control: a 100 s cap is still breaking off after 3.1 s")
	var eager := _rush({"break_rearm_seconds": 0.0}, 420.0, 7.0, 0.0)
	var e_entries: Array = eager["entries"]
	var e_exits: Array = eager["exits"]
	assert_gte(e_entries.size(), 2)
	assert_lt((int(e_entries[1]) - int(e_exits[0])) * DT, SHIPPED.break_rearm_seconds, "control: no rearm breaks off again at once")


func test_the_assault_break_off_stays_on_screen_and_never_boosts() -> void:
	for control in [false, true]:
		var h = _world("assault")
		var inner := _view_inner(h)
		var props := {"view_margin": -2000.0} if control else {}
		var hacker := _spawn(h, Vector2(640.0, 160.0), props)
		var brain := _brain(hacker)
		var mover := hacker.get_node("EnemyMover") as EnemyMover
		h.player.global_position = Vector2(640.0, 500.0)
		var started := -1
		var ended := -1
		var boosted := false
		var left_view := false
		for i in int(3.5 / DT):
			h.player.velocity = (hacker.global_position - h.player.global_position).normalized() * 200.0
			_step(hacker, h.player)
			h.player.global_position = h.player.global_position.clamp(inner.position, inner.end)
			boosted = boosted or mover.is_boosting()
			left_view = left_view or not inner.has_point(hacker.global_position)
			if started < 0 and brain.phase == Phase.BREAK_OFF:
				started = i
			if started >= 0 and ended < 0 and brain.phase != Phase.BREAK_OFF:
				ended = i
		if control:
			assert_true(left_view, "control: with the clamp off the hull leaves view_rect().grow(-60)")
			continue
		assert_eq(started, 0, "BREAK_OFF on the first tick (360 px)")
		assert_false(boosted, "Assault never boosts")
		assert_false(left_view, "the hull stays inside view_rect().grow(-60)")
		assert_between(ended, 1, int(round(3.0 / DT)) + 1, "it ends by 3.0 s (tick %d)" % ended)


# ── Assault life and the measured exit ───────────────────────────────────────────────────────────

func _life(props: Dictionary) -> Dictionary:
	var h = _world("assault")
	h.player.global_position = Vector2(640.0, 360.0)  # the 520 ring pokes out of the view top and bottom: the clamp binds
	var inner := _view_inner(h)
	var all_props := {"engage_seconds": 9.0, "first_pulse_delay": SHIPPED.first_pulse_delay}  # the real life, its pulse included
	all_props.merge(props, true)
	var hacker := _spawn(h, Vector2(1100.0, 140.0), all_props)
	var brain := _brain(hacker)
	var out := {"left_view": false, "disengage_tick": -1, "freed_after": -1.0, "bound_ever": false}
	for i in int(30.0 / DT):
		_step(hacker, h.player)
		if hacker.is_queued_for_deletion():
			out["freed_after"] = (i - int(out["disengage_tick"])) * DT
			break
		if int(out["disengage_tick"]) < 0:
			if brain.phase == Phase.DISENGAGE:
				out["disengage_tick"] = i
			else:
				out["left_view"] = bool(out["left_view"]) or not inner.has_point(hacker.global_position)
				out["bound_ever"] = bool(out["bound_ever"]) or brain.view_clamp_bound
	return out


func test_an_assault_life_stays_on_screen_disengages_at_9_s_and_leaves_within_the_measured_exit() -> void:
	var run := _life({})
	gut.p("life: DISENGAGE tick %d, freed %.2f s after (measured worst %.2f s)" % [run["disengage_tick"], run["freed_after"], _exit["seconds"]])
	assert_true(run["bound_ever"], "precondition: the clamp really bound in this placement")
	assert_false(run["left_view"], "the hull stays inside view_rect().grow(-60) for its whole budget")
	assert_between(int(run["disengage_tick"]), int(round(9.0 / DT)) - 2, int(round(9.0 / DT)), "DISENGAGE on the expiry tick")
	assert_gt(float(run["freed_after"]), 0.0, "it left")
	assert_lte(float(run["freed_after"]), float(_exit["seconds"]) + DT, "within the measured exit")
	var control := _life({"view_margin": -2000.0})
	assert_true(control["left_view"], "control: with the clamp off the hull leaves view_rect().grow(-60)")


func test_the_measured_assault_exit_is_printed_and_under_10_s() -> void:
	gut.p("hacker exit: worst %.2f s from %s, %d runs, %d capped (probe %.2f s wall)" % [_exit["seconds"], _exit["start"], _exit["runs"],
			_exit["capped"], _probe_s])
	assert_eq(int(_exit["runs"]), 2166, "every corridor start at max_speed and 10 px/s")
	assert_eq(int(_exit["capped"]), 0, "no run hit the cap")
	assert_gt(float(_exit["seconds"]), 0.0)
	assert_lt(float(_exit["seconds"]), 10.0)


func test_the_exit_key_is_built_once_and_the_hook_changes_nothing() -> void:
	var before: int = PROBE.measured
	assert_eq(PH9.hacker_exit(self), _exit, "the same figure")
	assert_eq(PROBE.measured, before, "a second call is a memo hit")
	var hook_a: Callable = PH9.prepare_probe
	var hook_b: Callable = PH9.prepare_probe
	assert_true(hook_a == hook_b and hook_a.hash() == hook_b.hash(), "the static hook is one Callable on every reference")
	# The stub trick: one corridor start, with and without the hook, is bit-identical (DISENGAGE never reads the player).
	var h = HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = PROBE.MID_VIEW + Vector2(0.0, 300.0)
	var at: Vector2 = PROBE.MID_VIEW + Vector2(-720.0, -720.0)
	var v := Vector2(1.0, 1.0).normalized() * SHIPPED.max_speed
	var plain: float = PROBE.disengage_seconds(h.root, SCENE, Phase.DISENGAGE, at, v, PH9.CAP)
	assert_true(h.player.is_in_group(&"player"), "precondition: without the hook the stub is a player")
	var hooked: float = PROBE.disengage_seconds(h.root, SCENE, Phase.DISENGAGE, at, v, PH9.CAP, PH9.prepare_probe)
	assert_false(h.player.is_in_group(&"player"), "the hook took the stub out of group player")
	assert_eq(hooked, plain, "bit-identical exit")


## No test builds a Ph9 probe call by hand: every `worst_disengage(` naming `HackerFrigateBrain` lives in `ph9_exit_keys.gd`.
func test_no_test_hand_builds_a_ph9_probe_call() -> void:
	var calls := 0
	var flagged: Array = []
	for path: String in _scripts("res://tests"):
		if path == "res://tests/helpers/ph9_exit_keys.gd":
			continue
		var found := _ph9_probe_calls(FileAccess.get_file_as_string(path))
		calls += int(found["calls"])
		for args: String in found["flagged"]:
			flagged.append("%s: %s" % [path, args.strip_edges()])
	assert_gte(calls, 10, "the sweep reads the known calls")
	assert_eq(flagged, [], "no worst_disengage( call outside ph9_exit_keys.gd names the Hacker's brain")
	var synthetic := "var r := SpecialistExitProbe.worst_disengage(self, load(P),\n\tHackerFrigateBrain.Phase.DISENGAGE, s, 20.0, c, hook)"
	assert_eq((_ph9_probe_calls(synthetic)["flagged"] as Array).size(), 1, "boundary: the sweep fires on a hand-built Hacker probe")


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


## `{calls, flagged}`: each line stripped of comments and string contents, joined, then each `worst_disengage(` call's argument text up to
## its matching `)` checked for the Hacker's brain (the `test_laser_tender.gd` sweep's shape).
static func _ph9_probe_calls(source: String) -> Dictionary:
	var lines := PackedStringArray()
	for line in source.split("\n"):
		lines.append(SINGLE_WRITER._code_only(line))
	var code := "\n".join(lines)
	var calls := 0
	var flagged: Array = []
	var at := code.find("worst_disengage(")
	while at >= 0:
		calls += 1
		var open := at + "worst_disengage".length()
		var depth := 0
		var close := code.length()
		for i in range(open, code.length()):
			if code[i] == "(":
				depth += 1
			elif code[i] == ")":
				depth -= 1
				if depth == 0:
					close = i
					break
		var args := code.substr(open, close - open + 1)
		if args.contains("HackerFrigateBrain"):
			flagged.append(args)
		at = code.find("worst_disengage(", close)
	return {"calls": calls, "flagged": flagged}


# ── Hub idle ─────────────────────────────────────────────────────────────────────────────────────

## A cold Open Space Hacker on its anchor; the player is re-placed every tick `distance` px from the HULL along +x.
func _idle_run(distance: float, seconds: float, hacker: HackerFrigate, h) -> Dictionary:
	var brain := _brain(hacker)
	var out := {"all_idle": true, "worst": 0.0, "noticed": -1, "fought": -1}
	for i in int(round(seconds / DT)):
		h.player.global_position = hacker.global_position + Vector2.RIGHT * distance
		_tick(hacker)
		if brain.phase != Phase.IDLE:
			out["all_idle"] = false
		out["worst"] = maxf(float(out["worst"]), hacker.global_position.distance_to(brain.patrol_anchor))
		if int(out["noticed"]) < 0 and brain.phase == Phase.NOTICING:
			out["noticed"] = i
		if int(out["fought"]) < 0 and brain.phase == Phase.HOLD_ARC:
			out["fought"] = i
	return out


func test_hub_idle_then_notice_at_760_px() -> void:
	var h = _world("open_space")
	var hacker := _spawn(h, Vector2(300.0, -200.0), {}, 3, false)
	var idle := _idle_run(900.0, 4.0, hacker, h)
	assert_true(idle["all_idle"], "IDLE every tick with the player 900 px away")
	assert_lte(float(idle["worst"]), SHIPPED.idle_radius + 40.0, "on its ring (worst %.1f px from the anchor)" % idle["worst"])
	var near := _idle_run(740.0, 1.0, hacker, h)
	assert_eq(int(near["noticed"]), 0, "NOTICING on the first tick inside 760 px")
	assert_between(int(near["fought"]) - int(near["noticed"]), 20, 22, "HOLD_ARC 0.35 s later (%d ticks)" % (int(near["fought"]) - int(near["noticed"])))
	# Control: just outside.
	var h2 = _world("open_space")
	var calm := _spawn(h2, Vector2(300.0, -200.0), {}, 3, false)
	var outside := _idle_run(780.0, 4.0, calm, h2)
	assert_true(outside["all_idle"], "control: 780 px is never noticed")


func test_open_space_cold_start_idles_and_assault_starts_in_combat() -> void:
	var h = _world("open_space")
	h.player.global_position = Vector2(100000.0, 0.0)
	var hacker := _spawn(h, Vector2(300.0, -200.0), {}, 3, false)
	_tick(hacker)
	assert_eq(_brain(hacker).phase, Phase.IDLE)
	assert_not_null(_brain(hacker).anchor_idle)
	assert_eq(_brain(hacker).patrol_anchor, Vector2(300.0, -200.0), "an unset anchor defaults to the spawn position")
	var a = _world("assault")
	var cold := _spawn(a, _on_ring(a.player.global_position, 520.0, 0.0), {}, 3, false)
	_tick(cold)
	assert_eq(_brain(cold).phase, Phase.HOLD_ARC, "Assault always starts in combat")
	assert_null(_brain(cold).anchor_idle)


# ── TELEGRAPH / PULSE tow refusal, suspension ───────────────────────────────────────────────────

## The telegraphed phases refuse a tow and HOLD_ARC accepts one (the pulse itself, its cadence and its gates: `test_hijack_pulse.gd`). With
## the pulse off (`first_pulse_delay` 1000) HOLD_ARC never enters them.
func test_the_attack_phases_refuse_a_tow(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var hacker := _spawn(h, _on_ring(h.player.global_position, 520.0 if h.is_assault else 720.0, 0.0))
	var brain := _brain(hacker)
	var seen: Array[int] = []
	brain.phase_changed.connect(func(p: int) -> void: seen.append(p))
	for p in [Phase.TELEGRAPH, Phase.PULSE]:
		brain.enter_phase(p)
		assert_false(brain.accepts_tow(), "%s: %s refuses a tow" % [mode, p])
		_tick(hacker)
		assert_eq(brain.phase, p, "%s: %s runs on (it is no stub)" % [mode, p])
	brain.enter_phase(Phase.HOLD_ARC)
	assert_true(brain.accepts_tow(), "%s: HOLD_ARC accepts one" % mode)
	seen.clear()
	for _i in int(10.0 / DT):
		_step(hacker, h.player)
	assert_false(seen.has(Phase.TELEGRAPH) or seen.has(Phase.PULSE), "%s: never entered with the pulse off (%s)" % [mode, seen])


## A budget that expires while a TELEGRAPH is up goes straight to DISENGAGE, never through HOLD_ARC (the cancel t9's real telegraph uses).
func test_a_budget_expiring_in_telegraph_goes_straight_to_disengage() -> void:
	var h = _world("assault")
	var hacker := _spawn(h, _on_ring(h.player.global_position, 520.0, 0.0), {"engage_seconds": 0.5})
	var brain := _brain(hacker)
	var seen: Array[int] = []
	brain.phase_changed.connect(func(p: int) -> void: seen.append(p))
	for _i in 120:
		brain.enter_phase(Phase.TELEGRAPH)
		seen.clear()
		_tick(hacker)
		if brain.phase == Phase.DISENGAGE:
			break
	assert_eq(brain.phase, Phase.DISENGAGE)
	assert_eq(seen, [Phase.DISENGAGE] as Array[int], "TELEGRAPH -> DISENGAGE with no HOLD_ARC between")


func test_suspension_turns_the_light_off_and_drops_the_idle() -> void:
	var h = _world("open_space")
	h.player.global_position = Vector2(100000.0, 0.0)
	var hacker := _spawn(h, Vector2(300.0, -200.0), {}, 3, false)
	_tick(hacker)
	var brain := _brain(hacker)
	assert_not_null(brain.anchor_idle, "precondition: idling")
	hacker.state_light().set_state(StateLight.State.ARMED)
	hacker.suspend_ai()
	assert_null(brain.anchor_idle)
	assert_eq(hacker.state_light().get_state(), StateLight.State.OFF)
	assert_false(hacker.is_ai_driven())
