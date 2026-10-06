## Gatling convergence fire (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.6.1, §4 row
## test_gatling_convergence.gd; task t11-gatling-convergence). INTENT tests: a squad of two Gatlings charges
## together, crosses its streams at the player's likely next position from one side, and the far side stays open.
##
## Harness rules (same as test_gatling_interceptor.gd): the harness is built inside the body, Gatlings are
## hand-ticked LEAD first then FLANK, every one is seeded, and the shipped config is read from the preloaded
## `.tres` and never written (a case that needs other values writes the Gatling's PRIVATE `config`).
##
## Each Gatling's pattern is swapped for a recording subclass, so the aim point a round was ACTUALLY fired with
## is read at fire time (a last round is fired on the tick the stream ends and the point is cleared).
## Hand-ticked rounds never fly, so `_run()` puts every new round straight back in its pool.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor.tscn")
## Shared, read-only: never written (CLAUDE.md config rule).
const CONFIG: GatlingInterceptorConfig = \
		preload("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor_config.tres")

const DT := 1.0 / 60.0
const MID := Vector2(640.0, 360.0)
## The LEAD sits on its flank point (right of the player, `h` = UP); the FLANK is the second closest, near
## where its own offset flank point lands, so both swing in at once.
const LEAD_POS := Vector2(1015.0, 330.0)
const FLANK_POS := Vector2(960.0, 140.0)
## Epic §4: every aim line passes within this of the shared point (px), before the per-round jitter.
const AIM_TOLERANCE_PX := 48.0

const P := GatlingInterceptorBrain.Phase


## Records the aim point each round is fired with, and where from.
class RecordingPattern extends GatlingAttackPattern:
	var log: Array = []
	var frame: int = 0
	var board: SquadController

	func fire(ship: Node2D, pool: BulletPool) -> void:
		log.append({"frame": frame, "aim": aim_point, "from": ship.global_position,
				"point": board.convergence_point if board != null else Vector2.INF})
		super.fire(ship, pool)


func _harness(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = MID
	return h


func _spawn(h: RefCounted, pos: Vector2, board: SquadController, configure: Callable = Callable(), rng_seed: int = 1) -> GatlingInterceptor:
	var g := SCENE.instantiate() as GatlingInterceptor
	g.global_position = pos
	g.squad = board
	(g.get_node("Brain") as GatlingInterceptorBrain).rng_seed = rng_seed
	(g.get_node("Brain") as GatlingInterceptorBrain).start_engaged = true  # pre-t12: predates the hub idle
	if configure.is_valid():
		configure.call(g.config)
	h.root.add_child(g)
	g.set_physics_process(false)
	var old := (g.get_node("Attack") as AttackController).pattern as GatlingAttackPattern
	var rec := RecordingPattern.new()
	rec.fire_interval = old.fire_interval
	rec.bullet_damage = old.bullet_damage
	rec.bullet_speed = old.bullet_speed
	rec.spread_angle = old.spread_angle
	rec.aim_at_player = old.aim_at_player
	rec.accuracy = old.accuracy
	rec.rng = old.rng
	rec.board = board
	(g.get_node("Attack") as AttackController).pattern = rec
	return g


## Turns the nose toward `point` before the first tick, so a short swing is not spent turning round (a Gatling
## starts at rest and heads where its nose points).
func _face(g: GatlingInterceptor, point: Vector2) -> void:
	g.rotation = (point - g.global_position).angle() - EnemyMover.sprite_forward_angle_of(g)


func _brain(g: GatlingInterceptor) -> GatlingInterceptorBrain:
	return g.get_node("Brain") as GatlingInterceptorBrain


func _log(g: GatlingInterceptor) -> Array:
	return ((g.get_node("Attack") as AttackController).pattern as RecordingPattern).log


func _rounds(min_n: int, max_n: int) -> Callable:
	return func(c: GatlingInterceptorConfig) -> void:
		c.stream_rounds_min = min_n
		c.stream_rounds_max = max_n


## A real two-Gatling squad: LEAD closest to the player, then the FLANK. `lead_cfg` / `flank_cfg` write the
## private configs.
func _pair(h: RefCounted, flank_pos: Vector2 = FLANK_POS, lead_cfg: Callable = Callable(), flank_cfg: Callable = Callable()) -> Dictionary:
	var board := SquadController.new()
	var lead := _spawn(h, LEAD_POS, board, lead_cfg, 1)
	var flank := _spawn(h, flank_pos, board, flank_cfg, 2)
	_face(lead, Vector2(1020.0, 330.0))
	_face(flank, Vector2(900.0, 80.0) if flank_pos == FLANK_POS else MID + Vector2(300.0, -300.0))
	return {"board": board, "lead": lead, "flank": flank}


func _tick(g: BaseEnemy) -> void:
	var before := g.global_position
	g._physics_process(DT)
	g.global_position = before + g.velocity * DT


## Hand-ticks the live Gatlings (LEAD first) for up to `seconds`, one frame record per tick:
## {i, t, window, point, stages, g: [{phase0, phase, light, x, side, flank, rounds}, ...]}. `each.call(frame)`
## returning true stops the run. A freed Gatling's entry is {}.
func _run(h: RefCounted, pair: Dictionary, seconds: float, each: Callable = Callable()) -> Array:
	var board: SquadController = pair.board
	var gs: Array = [pair.lead, pair.flank]
	var frames: Array = []
	for i in int(round(seconds / DT)):
		h.player.global_position += h.player.velocity * DT
		var entries: Array = []
		for g in gs:
			if not is_instance_valid(g):
				entries.append({})
				continue
			var brain := _brain(g)
			var phase0 := brain.phase
			((g.get_node("Attack") as AttackController).pattern as RecordingPattern).frame = i
			_tick(g)
			var pool := g.get_node("StreamPool") as BulletPool
			for bullet in pool._active.duplicate():
				pool._recycle(bullet)
			entries.append({"phase0": phase0, "phase": brain.phase,
					"light": (g.get_node("StateLight") as StateLight).get_state(), "x": g.global_position,
					"side": brain.side, "flank": brain.flank_point, "rounds": brain.stream_rounds})
		var frame := {"i": i, "t": (i + 1) * DT, "window": board.attack_window_open,
				"point": board.convergence_point, "stages": board.convergence_stage.size(), "g": entries}
		frames.append(frame)
		if each.is_valid() and each.call(frame):
			break
	return frames


## The first frame index at which Gatling `k` is in `phase` after its tick; -1 if never.
func _first(frames: Array, k: int, phase: int) -> int:
	for f in frames:
		if not f.g[k].is_empty() and f.g[k].phase == phase:
			return f.i
	return -1


func _first_light(frames: Array, k: int, light: int) -> int:
	for f in frames:
		if not f.g[k].is_empty() and f.g[k].light == light:
			return f.i
	return -1


## [first, last] frame index of Gatling `k`'s first STREAM stretch; [-1, -1] if none.
func _stream_span(frames: Array, k: int) -> Array:
	var a := -1
	var b := -1
	for f in frames:
		var e: Dictionary = f.g[k]
		if e.is_empty():
			continue
		if e.phase == P.STREAM:
			if a < 0:
				a = f.i
			b = f.i
		elif a >= 0:
			break
	return [a, b]


## Distance from `point` to the infinite line through `from` and `aim`.
func _line_distance(from: Vector2, aim: Vector2, point: Vector2) -> float:
	var dir := (aim - from).normalized()
	return absf(dir.cross(point - from))


func _bearing_deg(x: Vector2, p: Vector2) -> float:
	return rad_to_deg(Vector2.UP.angle_to(x - p))


## The first window is over: closed, the LEAD flipped into REPOSITION, the FLANK in (or entering) its own.
func _first_window_over(f: Dictionary) -> bool:
	return not f.window and f.i > 30 and f.g[0].phase == P.REPOSITION \
			and (f.g[1].phase == P.COOLDOWN or f.g[1].phase == P.REPOSITION)


func _both_in_stream(f: Dictionary) -> bool:
	return not f.g[0].is_empty() and not f.g[1].is_empty() and f.g[0].phase == P.STREAM and f.g[1].phase == P.STREAM


# ── The pair forms ───────────────────────────────────────────────────────────────────────────────

func test_the_closest_member_leads_and_the_other_flanks(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var pair := _pair(h)
	var board: SquadController = pair.board
	assert_eq(board.role_of(pair.lead), SquadController.Role.LEAD, mode)
	var role := board.role_of(pair.flank)
	assert_true(role == SquadController.Role.FLANK_LEFT or role == SquadController.Role.FLANK_RIGHT, mode)


func test_both_lights_go_charging_within_one_tick(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var pair := _pair(h)
	var frames := _run(h, pair, 2.0, func(f: Dictionary) -> bool: return _both_in_stream(f))
	var a := _first_light(frames, 0, StateLight.State.CHARGING)
	var b := _first_light(frames, 1, StateLight.State.CHARGING)
	assert_gte(a, 0, "%s: the LEAD charges" % mode)
	assert_gte(b, 0, "%s: the FLANK charges" % mode)
	assert_lte(absi(a - b), 1, "%s: lights %d vs %d" % [mode, a, b])


func test_both_swing_in_on_the_same_side_and_keep_the_other_open(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var pair := _pair(h)
	var frames := _run(h, pair, 3.0, func(f: Dictionary) -> bool: return _both_in_stream(f))
	var f: Dictionary = frames[-1]
	assert_true(_both_in_stream(f), "%s: both stream" % mode)
	assert_eq(f.g[0].side, f.g[1].side, "%s: one side" % mode)
	var lead_flank: Vector2 = f.g[0].flank
	var flank_flank: Vector2 = f.g[1].flank
	# Half-plane about the player along `h` = UP: the sign of x − P.x.
	assert_eq(signf(lead_flank.x - MID.x), signf(flank_flank.x - MID.x), "%s: flank points in one half-plane" % mode)
	assert_eq(signf(f.g[0].x.x - MID.x), signf(f.g[1].x.x - MID.x), "%s: the hulls too" % mode)
	var sep := absf(_bearing_deg(lead_flank, MID) - _bearing_deg(flank_flank, MID))
	assert_gte(sep, 30.0, "%s: flank points %.1f° apart" % [mode, sep])


## Review N3: from the second window on the LEAD has FLIPPED its side in REPOSITION but has not crossed yet.
## The FLANK takes the LEAD's intended side — not the half-plane its hull is in.
func test_a_second_window_takes_the_leads_intended_side_not_its_position(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var pair := _pair(h)
	var board: SquadController = pair.board
	var lead: GatlingInterceptor = pair.lead
	var flank: GatlingInterceptor = pair.flank
	var frames := _run(h, pair, 12.0, _first_window_over)
	assert_eq(frames[-1].g[0].phase, P.REPOSITION, "%s: the first window ended" % mode)
	assert_false(board.attack_window_open)
	assert_eq(_brain(lead).side, -1.0, "%s: the LEAD flipped to the left" % mode)
	assert_gt(lead.global_position.x, MID.x, "%s: ... and its hull is still on the right" % mode)
	if _brain(flank).phase == P.COOLDOWN:
		_brain(flank).enter_phase(P.REPOSITION)
	_brain(lead).enter_phase(P.SWING_IN)
	assert_true(board.attack_window_open, "the LEAD opens the second window")
	_tick(lead)
	_tick(flank)
	assert_eq(_brain(flank).phase, P.SWING_IN, "%s: the FLANK answers" % mode)
	assert_eq(_brain(flank).side, -1.0, "%s: the LEAD's intended side" % mode)
	assert_lt(_brain(flank).flank_point.x, MID.x, "%s: its flank point is on the left" % mode)
	assert_lt(_brain(lead).flank_point.x, MID.x)


# ── Rendezvous and fire ──────────────────────────────────────────────────────────────────────────

func test_the_streams_overlap_and_every_round_has_an_aim_point(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var pair := _pair(h)
	var frames := _run(h, pair, 6.0, func(f: Dictionary) -> bool: return not f.window and f.i > 30)
	var lead_span := _stream_span(frames, 0)
	var flank_span := _stream_span(frames, 1)
	assert_gte(lead_span[0], 0, "%s: the LEAD streams" % mode)
	assert_gte(flank_span[0], 0, "%s: the FLANK streams" % mode)
	assert_lte(absi(lead_span[0] - flank_span[0]), 1, "%s: starts %s vs %s" % [mode, lead_span, flank_span])
	var overlap := float(mini(lead_span[1], flank_span[1]) - maxi(lead_span[0], flank_span[0]) + 1) * DT
	assert_gte(overlap, 0.6, "%s: overlap %.2f s" % [mode, overlap])
	for k in 2:
		var g: GatlingInterceptor = [pair.lead, pair.flank][k]
		var log := _log(g)
		assert_eq(log.size(), _brain(g).stream_rounds, "%s #%d fires exactly N" % [mode, k])
		for shot in log:
			assert_true((shot.aim as Vector2).is_finite(), "%s #%d: every round has an aim point" % [mode, k])
			assert_true((shot.point as Vector2).is_finite(), "%s #%d: ... and the board has the point" % [mode, k])
			var d := _line_distance(shot.from, shot.aim, shot.point)
			assert_lte(d, AIM_TOLERANCE_PX, "%s #%d: aim line %.1f px from the point" % [mode, k, d])


## The point is refreshed, never frozen: a moving player's point leads it by `d / round_speed`, clamped.
func test_the_point_tracks_a_moving_player(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	h.player.velocity = Vector2(0.0, -120.0)
	var pair := _pair(h)
	var frames := _run(h, pair, 3.0, func(f: Dictionary) -> bool: return _both_in_stream(f))
	var points := {}
	for f in frames:
		if (f.point as Vector2).is_finite():
			var p: Vector2 = h.player.global_position - h.player.velocity * DT * (frames.size() - 1 - f.i)
			var lead_time := ((f.point as Vector2) - p).length() / 120.0
			assert_between(lead_time, 0.39, 0.81, "%s: the point leads by %.2f s" % [mode, lead_time])
			points[(f.point as Vector2).snappedf(0.01)] = true
	assert_gt(points.size(), 5, "%s: the point moves with the player (%d values)" % [mode, points.size()])


func test_the_window_closes_on_the_later_cooldown_not_the_leads(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	# The LEAD streams 8 rounds, the FLANK 12: the LEAD's COOLDOWN comes first.
	var pair := _pair(h, FLANK_POS, _rounds(8, 8), _rounds(12, 12))
	var frames := _run(h, pair, 6.0)
	var lead_cd := _first(frames, 0, P.COOLDOWN)
	var flank_cd := _first(frames, 1, P.COOLDOWN)
	assert_gt(flank_cd - lead_cd, 3, "%s: the FLANK finishes later (%d vs %d)" % [mode, lead_cd, flank_cd])
	assert_true(frames[lead_cd + 2].window, "%s: still open after the LEAD's COOLDOWN" % mode)
	assert_true(frames[flank_cd - 1].window, "%s: still open just before the FLANK's" % mode)
	assert_false(frames[flank_cd + 2].window, "%s: closed by the FLANK's COOLDOWN" % mode)
	assert_false((frames[flank_cd + 2].point as Vector2).is_finite(), "%s: the point is cleared" % mode)
	assert_eq(frames[flank_cd + 2].stages, 0, "%s: the stages are cleared" % mode)
	# The LEAD kept refreshing the point while it waited.
	assert_true((frames[flank_cd - 1].point as Vector2).is_finite())


func test_the_wait_for_a_late_partner_is_bounded(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	# 540 px from the player (inside the 570 px join range) and ~830 px from its flank point: its SWING_IN
	# runs the full 1.5 s.
	var pair := _pair(h, MID + Vector2(0.0, 540.0))
	var frames := _run(h, pair, 5.0, func(f: Dictionary) -> bool: return not f.window and f.i > 30)
	var lead_spin := _first(frames, 0, P.SPIN_UP)
	var lead_stream := _first(frames, 0, P.STREAM)
	var flank_spin := _first(frames, 1, P.SPIN_UP)
	var flank_stream := _first(frames, 1, P.STREAM)
	assert_gt(flank_spin - lead_spin, int(0.9 / DT), "%s: the FLANK really is late (%d vs %d)" % [mode, flank_spin, lead_spin])
	var waited := float(lead_stream - lead_spin) * DT
	var cap := CONFIG.spin_up_seconds + CONFIG.sync_wait_max
	assert_lte(waited, cap + 2.0 * DT, "%s: the LEAD waited %.2f s" % [mode, waited])
	assert_gte(waited, cap - 2.0 * DT, "%s: ... all of the allowance" % mode)
	assert_gt(flank_stream, lead_stream, "%s: the LEAD streamed first" % mode)
	var flank_log := _log(pair.flank)
	assert_eq(flank_log.size(), _brain(pair.flank).stream_rounds, "%s: the late FLANK still fires all N" % mode)
	for shot in flank_log:
		assert_true((shot.aim as Vector2).is_finite(), "%s: ... with the shared point" % mode)


func test_a_far_flank_skips_the_window(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var pair := _pair(h, MID + Vector2(0.0, 700.0))
	var board: SquadController = pair.board
	var frames := _run(h, pair, 1.0)
	assert_true(frames[3].window, "%s: the LEAD's window is open" % mode)
	assert_false(board.convergence_stage.has(pair.flank), "%s: the far FLANK is not a participant" % mode)
	for f in frames:
		assert_eq(f.g[1].phase, P.APPROACH, "%s: it keeps its own rhythm" % mode)
		assert_eq(f.g[1].light, StateLight.State.OFF)
	assert_eq(_log(pair.flank).size(), 0)


## Review N3: a FLANK in the middle of its own window never aborts it for another's.
func test_a_flank_in_its_own_window_skips_the_open_one() -> void:
	var h := _harness("open_space")
	var pair := _pair(h)
	var board: SquadController = pair.board
	_brain(pair.flank).enter_phase(P.SWING_IN)
	_run(h, pair, 0.1)
	assert_true(board.attack_window_open)
	assert_false(board.convergence_stage.has(pair.flank), "mid-SWING_IN it skips")
	assert_false(_brain(pair.flank)._conv_flank)


func test_the_lead_opens_no_second_window_while_one_is_open() -> void:
	var h := _harness("open_space")
	var pair := _pair(h)
	var board: SquadController = pair.board
	var lead: GatlingInterceptor = pair.lead
	# A window somebody else left open: the LEAD has no key, and may not open another.
	board.attack_window_open = true
	_brain(lead).enter_phase(P.REPOSITION)
	var frames := _run(h, {"board": board, "lead": lead, "flank": pair.flank}, 7.0)
	for f in frames:
		assert_ne(f.g[0].phase, P.SWING_IN, "t=%.2f: the LEAD holds in REPOSITION" % f.t)
	assert_eq(_brain(lead).phase, P.REPOSITION)
	board.attack_window_open = false
	var after := _run(h, {"board": board, "lead": lead, "flank": pair.flank}, 0.5)
	assert_gte(_first(after, 0, P.SWING_IN), 0, "the moment it closes the LEAD goes")


# ── Failure paths ────────────────────────────────────────────────────────────────────────────────

## The LEAD dies mid-window: the board clears; the FLANK, mid-stream, finishes ALL its rounds at its own
## predicted point.
func test_the_lead_dying_clears_the_board_and_the_flank_finishes_its_stream(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var pair := _pair(h, FLANK_POS, _rounds(12, 12), _rounds(12, 12))
	var board: SquadController = pair.board
	var flank: GatlingInterceptor = pair.flank
	var frames := _run(h, pair, 4.0, func(f: Dictionary) -> bool: return _both_in_stream(f) and _log(flank).size() >= 3)
	assert_true(_both_in_stream(frames[-1]), "%s: both streaming" % mode)
	var before := _log(flank).size()
	assert_true((_log(flank)[-1].aim as Vector2).is_finite(), "%s: converging so far" % mode)
	(pair.lead as GatlingInterceptor).free()
	assert_false(board.attack_window_open, "%s: the window is gone" % mode)
	assert_false(board.convergence_point.is_finite(), "%s: the point is gone" % mode)
	assert_true(board.convergence_stage.is_empty(), "%s: the stages are gone" % mode)
	var rest := _run(h, pair, 3.0, func(f: Dictionary) -> bool: return f.g[1].phase != P.STREAM)
	assert_ne(rest[-1].g[1].phase, P.STREAM, "%s: the stream ended" % mode)
	var log := _log(flank)
	assert_eq(log.size(), 12, "%s: the FLANK fired all N" % mode)
	for k in range(before, log.size()):
		assert_false((log[k].aim as Vector2).is_finite(), "%s: round %d at its own predicted point" % [mode, k])


func test_a_flank_dying_does_not_hold_the_window_open() -> void:
	var h := _harness("open_space")
	var pair := _pair(h)
	var board: SquadController = pair.board
	var frames := _run(h, pair, 3.0, func(f: Dictionary) -> bool: return _both_in_stream(f))
	assert_true(_both_in_stream(frames[-1]))
	(pair.flank as GatlingInterceptor).free()
	assert_false(board.convergence_stage.has(pair.flank))
	var rest := _run(h, pair, 3.0, func(f: Dictionary) -> bool: return not f.window)
	assert_false(rest[-1].window, "the LEAD closes the window on its own COOLDOWN")


func test_a_budget_expiry_leaves_the_squad_and_clears_nothing_it_does_not_own() -> void:
	var h := _harness("assault")
	var pair := _pair(h)
	var board: SquadController = pair.board
	var flank: GatlingInterceptor = pair.flank
	_run(h, pair, 0.1)
	assert_true(board.convergence_stage.has(flank))
	_brain(flank).enter_phase(P.DISENGAGE)
	assert_false(board.convergence_stage.has(flank), "a leaving participant is erased")
	assert_true(board.attack_window_open, "the LEAD's window is untouched")


# ── Solo ─────────────────────────────────────────────────────────────────────────────────────────

func test_a_solo_gatling_never_converges(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var g := _spawn(h, LEAD_POS, null)
	var frames := _run(h, {"board": SquadController.new(), "lead": g, "flank": null}, 10.0)
	var streamed := 0
	for f in frames:
		if f.g[0].phase == P.STREAM:
			streamed += 1
	assert_gt(streamed, 0, "%s: it streamed" % mode)
	for shot in _log(g):
		assert_false((shot.aim as Vector2).is_finite(), "%s: solo rounds never take an aim point" % mode)


func test_a_squad_of_one_never_converges(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var board := SquadController.new()
	var g := _spawn(h, LEAD_POS, board)
	var frames := _run(h, {"board": board, "lead": g, "flank": null}, 10.0)
	for f in frames:
		assert_false(f.window, "%s: no window at t=%.2f" % [mode, f.t])
	assert_gt(_log(g).size(), 0)
	for shot in _log(g):
		assert_false((shot.aim as Vector2).is_finite(), mode)
