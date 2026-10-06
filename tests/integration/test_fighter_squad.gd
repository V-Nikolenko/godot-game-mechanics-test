## Fighter squads (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.5, §4; task plan
## docs/plans/cmulwkar300bxqj2xgtk6jyu3/3-plan.md). INTENT tests.
##
## Every squad here comes out of a real `WaveManager` (one wave at `trigger_time` 0, stagger 0, so
## `_spawn_with_delay()` never awaits a `SceneTreeTimer` — the tests/README leak trap) into the
## `enemy_ai_harness.gd` worlds, and its fighters are hand-ticked in lock-step at 60 Hz against a
## holding player. Rounds are recorded and put straight back in their pools (hand-ticked bullets never
## fly). The shipped config is never written; a case that needs other values writes a fighter's
## PRIVATE `config`, and says so. Every fighter is seeded, so each run is reproducible.
##
## Fighter–fighter physics collision is excepted between the spawned fighters (`_spawn()`): the
## physics space is never stepped in a GUT run, so `move_and_slide()` would collide each fighter with
## its mates' stale spawn positions, which makes a squad run non-deterministic. These cases measure
## the brains; the bodies colliding in game is a separate question (DECISIONS, t9).
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
## Shared, read-only: never written (CLAUDE.md config rule).
const CONFIG: FighterConfig = preload("res://assault/scenes/enemies/fighter/fighter_config.tres")

const DT := 1.0 / 60.0
## `player_fighter.tscn`'s hurtbox radius (5 × 2.7), as test_fighter.gd.
const PLAYER_HURTBOX_RADIUS := 13.5
const SEED := 100
## A private budget long enough that the Assault budget never ends a case that is about something else.
const LONG_ENGAGE := 600.0

const P := FighterBrain.Phase
const K := FighterBrain.PassKind
const R := SquadController.Role

## The kind each role's pass takes (epic §2.5 table).
const KIND_FOR := {R.LEAD: K.FRONTAL, R.FLANK_LEFT: K.FLANK_LEFT, R.FLANK_RIGHT: K.FLANK_RIGHT, R.REAR: K.REAR}

## The player positions and formation offsets (design units) the single-layout cases use.
const PLAYERS := [Vector2(640, 560), Vector2(480, 520), Vector2(820, 600)]
const OFFSETS := [Vector2(0, -230), Vector2(-110, -260), Vector2(120, -200)]
## The separation sweep's grid: every player position against every formation offset — the
## task's measured set, not a hand-picked subset (review B3).
const SWEEP_PLAYERS := [Vector2(640, 560), Vector2(480, 520), Vector2(820, 600), Vector2(640, 600),
	Vector2(400, 480), Vector2(900, 640), Vector2(640, 380)]
const SWEEP_OFFSETS := [Vector2(0, -230), Vector2(-110, -260), Vector2(120, -200), Vector2(0, -250),
	Vector2(-160, -220), Vector2(170, -240)]


# ── World ────────────────────────────────────────────────────────────────────────────────────────

func _world(mode: String, player_pos: Vector2) -> Dictionary:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = player_pos
	var cam: Camera2D
	if mode == "open_space":
		cam = Camera2D.new()
		cam.global_position = Vector2(640, 360)
		h.root.add_child(cam)
	else:
		cam = h.root.get_node("ArenaCamera") as Camera2D
	cam.make_current()
	var wm := WaveManager.new()
	wm.enemy_container = h.root
	h.root.add_child(wm)
	return {"h": h, "wm": wm, "mode": mode}


## Spawns formations of fighters through the real `WaveManager` (one entry per formation, so one
## board each) and returns the new fighters in spawn order, seeded, with physics off (hand-ticked) and
## with physics collision excepted between them. `configure` receives each fighter's PRIVATE config.
func _spawn(w: Dictionary, formations: Array, at: Vector2, configure: Callable = Callable()) -> Array[Fighter]:
	var b := WaveBuilder.new()
	var entries: Array = []
	for formation in formations:
		entries.append(b.fighter().at(at.x, at.y).formation(formation))
	var waves: Array[WaveResource] = [b.wave(0.0, entries)]
	(w.wm as WaveManager).load_section(waves)
	(w.wm as WaveManager)._process(0.0)
	var out: Array[Fighter] = []
	for c in (w.h.root as Node).get_children():
		if c is Fighter:
			c.set_physics_process(false)
			_brain(c).rng.seed = SEED + out.size()
			_brain(c).start_engaged = true  # pre-t12: predates the hub idle
			if configure.is_valid():
				configure.call(c.config)
			out.append(c)
	for a in out:
		for c in out:
			if a != c:
				a.add_collision_exception_with(c)
	return out


## Frees a world now: `TargetInfo.player()` reads the first player in the tree, so a case that builds
## several worlds must drop each before the next.
func _drop(w: Dictionary) -> void:
	var root: Node = w.h.root
	root.get_parent().remove_child(root)
	root.free()


func _v3() -> VFormation:
	return WaveBuilder.new().v_formation(3, 40.0, 12.0, 0.0)


func _w5() -> WFormation:
	return WaveBuilder.new().w_formation(5, 60.0, 40.0, 0.0)


func _long_budget(c: FighterConfig) -> void:
	c.engage_seconds = LONG_ENGAGE


func _brain(f: Node) -> FighterBrain:
	return f.get_node("Brain") as FighterBrain


func _alive(f: Variant) -> bool:
	return is_instance_valid(f) and not f.is_queued_for_deletion()


func _tick(f: Fighter) -> void:
	var before := f.global_position
	f._physics_process(DT)
	f.global_position = before + f.velocity * DT


func _hull(f: Fighter) -> float:
	var body := f.get_node("CollisionShape2D") as CollisionShape2D
	return (body.shape as CircleShape2D).radius * absf(body.scale.x)


## Rounds `f` fired since the last call, put straight back in their pools.
func _take_shots(f: Fighter) -> int:
	var shots := 0
	for pool_name in ["AimedPool", "ForwardPool"]:
		var pool := f.get_node(pool_name) as BulletPool
		for bullet in pool._active.duplicate():
			shots += 1
			pool._recycle(bullet)
	return shots


## Ticks every live fighter in lock-step for up to `seconds` and logs a frame per tick: the window
## after the frame, and per fighter (by spawn index) its phase, role, latched pass, hold state, window
## flag, position, seek target, light and the rounds it fired this frame. `each.call(frame)` returning
## true stops the run.
func _run(w: Dictionary, fighters: Array[Fighter], seconds: float, each: Callable = Callable()) -> Array[Dictionary]:
	var squad: SquadController = fighters[0].squad
	var player: Node2D = w.h.player
	var frames: Array[Dictionary] = []
	var t := 0.0
	for _i in int(round(seconds / DT)):
		for f in fighters:
			if _alive(f):
				_tick(f)
		t += DT
		var frame := {"t": t, "window": squad.attack_window_open, "p": player.global_position, "f": []}
		for f in fighters:
			if not _alive(f):
				frame.f.append(null)
				continue
			var brain := _brain(f)
			frame.f.append({"phase": brain.phase, "role": squad.role_of(f), "pass_role": brain.pass_role,
				"kind": brain.pass_kind, "bearing": brain.pass_bearing, "dir": brain.pass_dir,
				"lane": brain.pass_lane, "hold": brain.is_holding(), "settled": brain.is_settled(),
				"answered": brain._answered_window, "slack": brain.run_budget_slack(), "x": f.global_position,
				"seek": brain.seek_target, "light": (f.get_node("StateLight") as StateLight).get_state(),
				"shots": _take_shots(f)})
		frames.append(frame)
		if each.is_valid() and each.call(frame):
			break
	return frames


## Frame indices on which fighter `k` entered `phase` (it was elsewhere, or absent, the frame before).
func _entries(frames: Array[Dictionary], k: int, phase: int) -> Array[int]:
	var out: Array[int] = []
	var was := -1
	for i in frames.size():
		var rec: Variant = frames[i].f[k]
		var now: int = rec.phase if rec != null else -1
		if now == phase and was != phase:
			out.append(i)
		was = now
	return out


func _index_of_role(fighters: Array[Fighter], role: int) -> int:
	var squad: SquadController = fighters[0].squad
	for k in fighters.size():
		if _alive(fighters[k]) and squad.role_of(fighters[k]) == role:
			return k
	return -1


## Stops a run once the fighter at `k` has entered RUN_IN a second time.
func _until_second_run(k: int) -> Callable:
	var state := {"runs": 0, "was": false}
	return func(frame: Dictionary) -> bool:
		var rec: Variant = frame.f[k]
		var run: bool = rec != null and rec.phase == P.RUN_IN
		if run and not state.was:
			state.runs += 1
		state.was = run
		return state.runs >= 2


# ── Roles and the pincer ─────────────────────────────────────────────────────────────────────────

func test_a_v3_is_one_squad_of_the_lead_and_both_flanks(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0])
	assert_eq(fighters.size(), 3)
	var squad: SquadController = fighters[0].squad
	assert_not_null(squad)
	var roles := []
	for f in fighters:
		assert_same(f.squad, squad, "one board for the formation")
		roles.append(squad.role_of(f))
	roles.sort()
	assert_eq(roles, [R.LEAD, R.FLANK_LEFT, R.FLANK_RIGHT])


## The first pass of each member: its role's kind, from its role's side, at its role's lane (epic
## §2.4.1 worked check, measured against the holding player). In the corridor a flank's bearing may
## flip to the other side when its run would be too short (t8b's corridor rule), so there a flank is
## only asserted to come in laterally.
func test_the_pincer_and_the_frontal_pass(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0])
	var lead := _index_of_role(fighters, R.LEAD)
	var frames := _run(w, fighters, 16.0, _until_second_run(lead))
	var h := Vector2.UP  # the harness player holds, facing the default UP (and UP is the corridor's h)
	var right := h.rotated(PI / 2.0)
	var lanes := {K.FRONTAL: CONFIG.pass_offset, K.FLANK_LEFT: CONFIG.pass_offset,
		K.FLANK_RIGHT: CONFIG.pass_offset + CONFIG.flank_lane_gap}
	var eps := Vector2(1e-3, 1e-3)
	for k in fighters.size():
		var entries := _entries(frames, k, P.RUN_IN)
		assert_false(entries.is_empty(), "member %d ran" % k)
		if entries.is_empty():
			continue
		var first: Dictionary = frames[entries[0]].f[k]
		assert_eq(first.kind, KIND_FOR[first.pass_role], "member %d: the kind of its role" % k)
		match first.kind:
			K.FLANK_LEFT, K.FLANK_RIGHT:
				var from_role: Vector2 = -right if first.kind == K.FLANK_LEFT else right
				if mode == "open_space":
					assert_almost_eq(first.bearing, from_role, eps, "a flank comes from its role's side")
				else:
					assert_almost_eq(absf((first.bearing as Vector2).dot(right)), 1.0, 1e-3, "a flank comes in laterally")
			_:
				assert_almost_eq(first.bearing, h, eps, "the LEAD comes head-on")
		var closest := INF
		for i in range(entries[0], frames.size()):
			var rec: Variant = frames[i].f[k]
			if rec == null or rec.phase != P.RUN_IN:
				break
			closest = minf(closest, (rec.x as Vector2).distance_to(frames[i].p))
		assert_almost_eq(closest, lanes[first.kind], 40.0, "member %d (kind %d): closest approach = its lane" % [k, first.kind])


# ── The window ───────────────────────────────────────────────────────────────────────────────────

func test_the_window_opens_on_the_lead_run_in_and_closes_on_its_extend(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0])
	var lead := _index_of_role(fighters, R.LEAD)
	var frames := _run(w, fighters, 9.0)
	var run_in := _entries(frames, lead, P.RUN_IN)
	var extend := _entries(frames, lead, P.EXTEND)
	assert_false(run_in.is_empty(), "the LEAD ran")
	assert_false(extend.is_empty(), "and extended")
	if run_in.is_empty() or extend.is_empty():
		return
	var first_open := -1
	for i in frames.size():
		if frames[i].window:
			first_open = i
			break
	assert_eq(first_open, run_in[0], "the window opens on the LEAD's RUN_IN entry")
	assert_false(frames[run_in[0] - 1].window, "and was closed before it")
	for i in range(run_in[0], extend[0]):
		assert_true(frames[i].window, "open through the run (frame %d)" % i)
	assert_false(frames[extend[0]].window, "closed on the LEAD's EXTEND entry")


## The LEAD starts its run (and opens the window) only once both flanks are settled at their S, or it
## has held `lead_wait_max`, or — Assault — its run would no longer fit the engagement budget.
func test_the_lead_does_not_open_before_its_flanks_settle(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0])
	var lead := _index_of_role(fighters, R.LEAD)
	var frames := _run(w, fighters, 9.0)
	var run_in := _entries(frames, lead, P.RUN_IN)
	assert_false(run_in.is_empty())
	if run_in.is_empty():
		return
	var i0: int = run_in[0]
	var held := 0
	for i in range(i0 - 1, -1, -1):
		if not frames[i].f[lead].hold:
			break
		held += 1
	var waited_out := held * DT >= CONFIG.lead_wait_max - DT
	var out_of_time: bool = frames[i0 - 1].f[lead].slack <= FighterBrain.EXTEND_MIN_SECONDS + DT
	for k in fighters.size():
		var role: int = frames[i0].f[k].role
		if role != R.FLANK_LEFT and role != R.FLANK_RIGHT:
			continue
		var settled: bool = frames[i0 - 1].f[k].settled or frames[i0].f[k].settled
		assert_true(settled or waited_out or out_of_time, "flank %d settled before the LEAD went (held %.2f s)" % [k, held * DT])


## Each flank answers a window once; `_answered_window` resets on reading it closed. The window is
## driven by hand (the LEAD is never ticked, so it opens nothing), and the flanks' PRIVATE
## `flank_wait_max` and budget are raised so only the window can start them.
func test_each_flank_answers_a_window_once_and_resets_on_reading_it_closed(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0], func(c: FighterConfig) -> void:
		c.flank_wait_max = 600.0
		c.engage_seconds = LONG_ENGAGE)
	var squad: SquadController = fighters[0].squad
	var lead := _index_of_role(fighters, R.LEAD)
	var flanks: Array[Fighter] = []
	for k in fighters.size():
		if k != lead:
			flanks.append(fighters[k])
	var tick_flanks := func(seconds: float, stop: Callable) -> bool:
		for _i in int(round(seconds / DT)):
			for f in flanks:
				_tick(f)
			if stop.call():
				return true
		return false
	var all_settled := func() -> bool:
		return flanks.all(func(f: Fighter) -> bool: return _brain(f).is_settled())
	var never := func() -> bool: return false
	assert_true(tick_flanks.call(12.0, all_settled), "both flanks reach and settle at S")
	for f in flanks:
		assert_eq(_brain(f).phase, P.REPOSITION, "holding, not running, with no window")
	# Window 1: each settled flank answers it.
	squad.attack_window_open = true
	tick_flanks.call(2.0 * DT, never)
	for f in flanks:
		assert_true(_brain(f)._answered_window, "answered window 1")
	var ran := func() -> bool:
		return flanks.all(func(f: Fighter) -> bool: return _brain(f).phase == P.RUN_IN)
	assert_true(tick_flanks.call(2.0, ran), "both flanks start their run (within their stagger)")
	# Back at S with the SAME window still open: no second answer.
	assert_true(tick_flanks.call(20.0, all_settled), "both flanks come back and settle")
	tick_flanks.call(1.0, never)
	for f in flanks:
		assert_true(_brain(f).is_holding(), "window 1 is not answered twice")
	# Closing it resets the flag on the first tick that reads it.
	squad.attack_window_open = false
	tick_flanks.call(DT, never)
	for f in flanks:
		assert_false(_brain(f)._answered_window, "reset on reading the window closed")
	# Window 2 is answered.
	squad.attack_window_open = true
	assert_true(tick_flanks.call(2.0, ran), "window 2 is answered")


func test_a_flank_whose_lead_never_opens_goes_after_flank_wait_max(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0], _long_budget)
	var lead := _index_of_role(fighters, R.LEAD)
	var flanks: Array[Fighter] = []
	for k in fighters.size():
		if k != lead:
			flanks.append(fighters[k])
	var settled_at := {}
	var ran_at := {}
	var t := 0.0
	for _i in int(round(14.0 / DT)):
		for f in flanks:
			_tick(f)
		t += DT
		for f in flanks:
			var brain := _brain(f)
			if brain.is_settled() and not settled_at.has(f):
				settled_at[f] = t
			if brain.phase == P.RUN_IN and not ran_at.has(f):
				ran_at[f] = t
	for f in flanks:
		assert_true(settled_at.has(f) and ran_at.has(f), "a flank settled and then ran")
		if settled_at.has(f) and ran_at.has(f):
			var waited: float = ran_at[f] - settled_at[f]
			assert_between(waited, CONFIG.flank_wait_max - DT, CONFIG.flank_wait_max + CONFIG.flank_stagger * 2.0 + 3.0 * DT,
					"it goes after flank_wait_max (plus at most its crossing stagger)")


## Round-2 review N6: a flank kept off its S — here pinned 50 px off it every tick, as two holders
## pushing apart or a mate crossing its station again and again would keep it — never settles, so
## neither a window nor `flank_wait_max` can start it, and Open Space has no budget to end the hold. It
## still goes once it has been unsettled `UNSETTLED_WAIT_FACTOR` × `flank_wait_max`, and not before.
func test_a_flank_kept_off_its_station_still_goes() -> void:
	var w := _world("open_space", PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0])
	var lead := _index_of_role(fighters, R.LEAD)
	var flank: Fighter = fighters[(lead + 1) % fighters.size()]
	var brain := _brain(flank)
	var off := Vector2(50.0, 0.0)
	assert_lt(off.length(), FighterBrain.HOLD_DRIFT_PX, "sanity: inside the drift limit, so it keeps holding")
	var pinned_at := -1.0
	var ran_at := -1.0
	var t := 0.0
	for _i in int(round(16.0 / DT)):
		_tick(flank)  # the LEAD is never ticked: no window ever opens
		t += DT
		if brain.phase == P.RUN_IN:
			ran_at = t
			break
		if brain.is_holding():
			if pinned_at < 0.0:
				pinned_at = t
			flank.global_position = brain.pass_start + off
			flank.velocity = Vector2.ZERO
	assert_gt(pinned_at, 0.0, "the flank reached its station and held")
	assert_gt(ran_at, 0.0, "a flank kept off its station still runs")
	if pinned_at > 0.0 and ran_at > 0.0:
		var bound := FighterBrain.UNSETTLED_WAIT_FACTOR * CONFIG.flank_wait_max
		assert_between(ran_at - pinned_at, bound - 2.0 * DT, bound + CONFIG.flank_stagger + 3.0 * DT,
				"after UNSETTLED_WAIT_FACTOR x flank_wait_max unsettled")


# ── Separation, and every attack from the rendezvous ─────────────────────────────────────────────

## Over a full attack cycle — every window up to and including the first one each REAR flies a dry
## pass on — no two squad members come within 2 × hull radius, on every layout of the measured grid
## (V3 and W5). In Open Space that is from the LEAD opening its first window to its first RUN_IN at or
## after its third, once every REAR has finished a dry pass (round-2 review B1: the REARs fly on the
## second window, so a measurement that stops at the LEAD's second RUN_IN never sees one); the run
## asserts it got there (round-2 N3). In Assault it is to the last fighter leaving: the shipped budget
## flies one pass, and a REAR never dry-passes there (an Assault fighter leaves after `passes`, so its
## REARs are promoted, not sent on a dry pass). A fighter on its DISENGAGE exit has left the board but
## still counts (round-2 N4): the give-way yields to an exiting ex-member, so the check measures it. Before the
## first window the formation is still fanning out of its 80 px spawn slots, which is the spawn
## layout's business (t16), not the squad's (DECISIONS, t9).
##
## The same runs also assert (review B2) that every squad member's RUN_IN starts from its hold at S —
## no deadline or breach pass that answers no window — and, in Assault, that a LEAD or FLANK that
## fires nothing is one that never started a run: the budget rule (`run_budget_slack()`) held it at
## S rather than send it out mid-run. Nobody touches the player outside its own exit (the straight
## DISENGAGE exit is t8b's, out of scope).
func test_members_never_come_within_two_hull_radii(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var worst := INF
	var worst_player := INF
	var silent_held := 0
	var runs := 0
	for form_name in ["v3", "w5"]:
		for player in SWEEP_PLAYERS:
			for at in SWEEP_OFFSETS:
				var res := _cycle(mode, form_name, player, at)
				runs += 1
				var where := "%s %s P%s at%s" % [mode, form_name, player, at]
				assert_true(res.window_seen, "%s: the LEAD opened a window" % where)
				if mode == "open_space":
					assert_gte(res.lead_runs, 3, "%s: the cycle reached the LEAD's third run" % where)
					assert_eq(res.rears_done, res.rears, "%s: every REAR flew its dry pass inside the cycle" % where)
				assert_gte(res.sep, 2.0 * res.hull, "%s: members stay apart over the cycle (%s)" % [where, res.sep_note])
				assert_gt(res.near, res.hull + PLAYER_HURTBOX_RADIUS, "%s: nobody touches the player" % where)
				assert_eq(res.breaches, [], "%s: every squad run starts from a hold at S" % where)
				assert_eq(res.silent_runners, [], "%s: an attacker that ran fired" % where)
				silent_held += res.silent_held
				worst = minf(worst, res.sep)
				worst_player = minf(worst_player, res.near)
	gut.p("%s: %d layouts; worst separation over the cycle %.1f px, worst distance to the player %.1f px; %d attackers held to the end by the budget" \
			% [mode, runs, worst, worst_player, silent_held])


func _cycle(mode: String, form_name: String, player_pos: Vector2, at: Vector2) -> Dictionary:
	var w := _world(mode, player_pos)
	var fighters := _spawn(w, [_v3() if form_name == "v3" else _w5()], at)
	var squad: SquadController = fighters[0].squad
	var player: Node2D = w.h.player
	var hull := _hull(fighters[0])
	var lead: Fighter = fighters[_index_of_role(fighters, R.LEAD)]
	var res := {"hull": hull, "sep": INF, "sep_note": "", "near": INF, "breaches": [], "silent_runners": [],
		"silent_held": 0, "window_seen": false, "lead_runs": 0, "rears": 0, "rears_done": 0}
	var shots := {}
	var ran := {}
	var was_hold := {}
	var was_phase := {}
	var attackers: Array[Fighter] = []
	var lead_runs := 0
	var rears_done := {}
	var all_dry := false
	for f in fighters:
		if squad.role_of(f) == R.REAR:
			res.rears += 1
		shots[f] = 0
		ran[f] = false
		was_hold[f] = false
		was_phase[f] = -1
	var t := 0.0
	for _i in int(round(50.0 / DT)):
		for f in fighters:
			if _alive(f):
				_tick(f)
		t += DT
		var live: Array[Fighter] = []
		for f in fighters:
			if not _alive(f):
				continue
			live.append(f)
			var brain := _brain(f)
			shots[f] += _take_shots(f)
			if brain.phase == P.RUN_IN and was_phase[f] != P.RUN_IN:
				ran[f] = true
				if not was_hold[f]:
					res.breaches.append("%.2f %s" % [t, R.keys()[squad.role_of(f)]])
				if f == lead:
					lead_runs += 1
					all_dry = all_dry or rears_done.size() >= res.rears
			if brain.pass_role == R.REAR and was_phase[f] == P.TURN and brain.phase != P.TURN:
				rears_done[f] = true  # the dry pass is over
			if brain.phase != P.DISENGAGE:
				res.near = minf(res.near, f.global_position.distance_to(player.global_position))
			was_hold[f] = brain.is_holding()
			was_phase[f] = brain.phase
		if squad.attack_window_open and not res.window_seen:
			res.window_seen = true
			for f in live:
				if squad.role_of(f) != R.REAR:
					attackers.append(f)
		if res.window_seen:
			for a in live.size():
				for b in range(a + 1, live.size()):
					var d := live[a].global_position.distance_to(live[b].global_position)
					if d < res.sep:
						res.sep = d
						res.sep_note = "%.2f s, %s/%s" % [t, P.keys()[_brain(live[a]).phase], P.keys()[_brain(live[b]).phase]]
		if mode == "open_space" and lead_runs >= 3 and all_dry:
			break
		if live.is_empty():
			break
	if mode == "assault":
		for f in attackers:
			if shots[f] == 0:
				if ran[f]:
					res.silent_runners.append(f.name)
				else:
					res.silent_held += 1
	res.lead_runs = lead_runs
	res.rears_done = rears_done.size()
	_drop(w)
	return res


# ── Reassignment and the side-change rule ────────────────────────────────────────────────────────

func test_killing_the_lead_reassigns_in_the_same_call(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0])
	var squad: SquadController = fighters[0].squad
	var lead := fighters[_index_of_role(fighters, R.LEAD)]
	var hint := squad.target_position_hint
	var rest := fighters.filter(func(f: Fighter) -> bool: return f != lead)
	rest.sort_custom(func(a: Fighter, b: Fighter) -> bool:
		return a.global_position.distance_squared_to(hint) < b.global_position.distance_squared_to(hint))
	squad.attack_window_open = true
	lead.free()
	assert_eq(squad.role_of(rest[0]), R.LEAD, "the closest remaining member leads, before any tick")
	assert_false(squad.attack_window_open, "the dead LEAD's window is closed")
	assert_eq(squad.member_count(), 2)


## IDEAS §17: a W5 loses a FLANK and the closest REAR takes an attacking place in the same call. The
## board recomputes every role by distance (review N4), so the assertion is the recompute: the three
## members closest to the hint are LEAD + both FLANKs, the closest ex-REAR is among them, and one
## REAR is left.
func test_a_w5_flank_killed_promotes_the_closest_rear_in_the_same_call(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_w5()], OFFSETS[0])
	var squad: SquadController = fighters[0].squad
	assert_eq(squad.rear_count(), 2, "a W5 is LEAD + two flanks + two REARs")
	var hint := squad.target_position_hint
	var by_distance := func(a: Fighter, b: Fighter) -> bool:
		return a.global_position.distance_squared_to(hint) < b.global_position.distance_squared_to(hint)
	var rears := fighters.filter(func(f: Fighter) -> bool: return squad.role_of(f) == R.REAR)
	rears.sort_custom(by_distance)
	var flank := fighters[_index_of_role(fighters, R.FLANK_LEFT)]
	flank.free()
	var rest := fighters.filter(func(f: Variant) -> bool: return _alive(f))
	rest.sort_custom(by_distance)
	var front := []
	for f in rest.slice(0, 3):
		front.append(squad.role_of(f))
	front.sort()
	assert_eq(front, [R.LEAD, R.FLANK_LEFT, R.FLANK_RIGHT], "the three closest attack, recomputed before any tick")
	assert_true(rest.slice(0, 3).has(rears[0]), "the closest REAR is among them")
	assert_eq(squad.role_of(rest[3]), R.REAR, "the farthest waits on")
	assert_eq(squad.rear_count(), 1)


## The side-change rule (epic §2.5): a role change mid-run leaves the latched pass alone until the
## pass ends, and the new role's kind is taken on the next RUN_IN, never before.
func test_a_role_change_mid_run_keeps_the_latched_pass_until_reposition(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0], _long_budget)
	var squad: SquadController = fighters[0].squad
	var lead_k := _index_of_role(fighters, R.LEAD)
	# Run until a flank is mid-RUN_IN and the closest member to the player but the LEAD, so the
	# LEAD's death makes it the new LEAD.
	var flank_k := [-1]
	_run(w, fighters, 12.0, func(frame: Dictionary) -> bool:
		for k in frame.f.size():
			var rec: Variant = frame.f[k]
			if k == lead_k or rec == null or rec.phase != P.RUN_IN:
				continue
			var d: float = (rec.x as Vector2).distance_to(frame.p)
			var closest := true
			for j in frame.f.size():
				if j != k and j != lead_k and frame.f[j] != null and (frame.f[j].x as Vector2).distance_to(frame.p) <= d:
					closest = false
			if closest and d < 2.0 * CONFIG.pass_offset + CONFIG.flank_lane_gap:
				flank_k[0] = k
				return true
		return false)
	assert_ne(flank_k[0], -1, "a flank is on its run")
	if flank_k[0] == -1:
		return
	var runner := fighters[flank_k[0]]
	var brain := _brain(runner)
	var latched := [brain.pass_kind, brain.pass_bearing, brain.pass_dir, brain.pass_lane, brain.pass_role]
	fighters[lead_k].free()
	assert_ne(squad.role_of(runner), latched[4], "sanity: the runner's role changed mid-run")
	var ended := false
	var next_kind := -1
	var t := 0.0
	while t < 16.0:
		for f in fighters:
			if _alive(f):
				_tick(f)
		t += DT
		if not ended:
			if brain.phase == P.RUN_IN or brain.phase == P.EXTEND:
				assert_eq([brain.pass_kind, brain.pass_bearing, brain.pass_dir, brain.pass_lane, brain.pass_role], latched,
						"the latched pass holds through the run (t %.2f)" % t)
			else:
				ended = true
		elif brain.phase == P.RUN_IN:
			next_kind = brain.pass_kind
			assert_eq(brain.pass_role, squad.role_of(runner), "the next pass is latched with the current role")
			break
	assert_true(ended, "the pass ended")
	assert_eq(next_kind, KIND_FOR[squad.role_of(runner)], "the next run is the new role's kind")


## The other half of the side-change rule: a new pass kind is only reached through REPOSITION, and no
## REPOSITION seek target's straight segment from the fighter passes within `reposition_min_radius`
## of the player. A hold at S (and the slide aside for a mate) seeks S itself and is not a route.
func test_every_reposition_seek_target_clears_the_reposition_radius(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var checked := 0
	var worst := INF
	for n in PLAYERS.size():
		var w := _world(mode, PLAYERS[n])
		var fighters := _spawn(w, [_w5()], OFFSETS[n], _long_budget)
		var frames := _run(w, fighters, 16.0)
		for i in range(1, frames.size()):
			var p: Vector2 = frames[i].p
			for k in fighters.size():
				var rec: Variant = frames[i].f[k]
				var before: Variant = frames[i - 1].f[k]
				if rec == null or before == null or rec.phase != P.REPOSITION or rec.hold:
					continue
				if (before.x as Vector2).distance_to(p) < CONFIG.reposition_min_radius:
					continue  # t8b's break-away starts inside the radius, by design
				worst = minf(worst, Geometry2D.get_closest_point_to_segment(p, before.x, rec.seek).distance_to(p))
				checked += 1
		_drop(w)
	assert_gt(checked, 0, "sanity: REPOSITION was flown")
	assert_gte(worst, CONFIG.reposition_min_radius - 2.0, "%s: no seek target passes within reposition_min_radius" % mode)


# ── REARs ────────────────────────────────────────────────────────────────────────────────────────

## REARs fire nothing and never light the warning (review B4: never asserted vacuously), with a long
## PRIVATE budget:
## - Open Space: only once each REAR has actually flown a dry pass (it answers every second window, in
##   the slot after it — task plan §3.4);
## - Assault: a fighter leaves after `passes` passes, so a REAR never reaches its dry pass there — it
##   holds through the attackers' windows and is promoted as they leave. The case runs until each REAR
##   has been promoted and has fired as an attacker: the guard is the role, not the fighter.
## A FLANK demoted to REAR mid-pass is the next case.
func test_rears_fire_nothing(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _world(mode, PLAYERS[0])
	var fighters := _spawn(w, [_w5()], OFFSETS[0], _long_budget)
	var squad: SquadController = fighters[0].squad
	var rear_ks: Array[int] = []
	for k in fighters.size():
		if squad.role_of(fighters[k]) == R.REAR:
			rear_ks.append(k)
	assert_eq(rear_ks.size(), 2)
	var state := {"was": {}, "runs": {}, "windows": {}, "window_was": false, "fired_promoted": {}}
	var frames := _run(w, fighters, 60.0, func(frame: Dictionary) -> bool:
		for k in rear_ks:
			var rec: Variant = frame.f[k]
			if rec == null:
				continue
			var run: bool = rec.phase == P.RUN_IN and rec.pass_role == R.REAR
			if run and not state.was.get(k, false):
				state.runs[k] = state.runs.get(k, 0) + 1
			state.was[k] = run
			if frame.window and not state.window_was and rec.role == R.REAR:
				state.windows[k] = state.windows.get(k, 0) + 1
			if rec.role != R.REAR and rec.pass_role != R.REAR and rec.shots > 0:
				state.fired_promoted[k] = true
		state.window_was = frame.window
		if mode == "open_space":
			# Stop once every REAR has finished a dry pass (it has left RUN_IN after one).
			return rear_ks.all(func(k: int) -> bool: return state.runs.get(k, 0) >= 1 and not state.was.get(k, false))
		return rear_ks.all(func(k: int) -> bool: return state.fired_promoted.has(k)))
	for k in rear_ks:
		if mode == "open_space":
			assert_gte(state.runs.get(k, 0), 1, "precondition: REAR %d flew a dry pass" % k)
		else:
			assert_gte(state.windows.get(k, 0), 1, "precondition: REAR %d held through a window as REAR" % k)
			assert_eq(state.runs.get(k, 0), 0, "an Assault REAR is promoted, never sent on a dry pass")
			assert_true(state.fired_promoted.has(k), "precondition: REAR %d was promoted and then fired" % k)
	var rear_shots := 0
	var rear_charging := 0
	var attacker_shots := 0
	for frame in frames:
		for rec in frame.f:
			if rec == null:
				continue
			if rec.pass_role == R.REAR or rec.role == R.REAR:
				rear_shots += rec.shots
				if rec.light == StateLight.State.CHARGING:
					rear_charging += 1
			else:
				attacker_shots += rec.shots
	assert_eq(rear_shots, 0, "REAR passes are dry")
	assert_eq(rear_charging, 0, "and never light the warning")
	assert_gt(attacker_shots, 0, "sanity: the attackers fire")


## Round-2 review N2: a FLANK demoted to REAR mid-run — by a closer member joining, here the board's
## `_reassign(force_rear)` seam (`release_lead()`'s rotation) so the demoted runner is the one chosen —
## fires nothing from that tick on, although its latched pass is still a FLANK's. A control run of the
## same seeded squad with no demotion proves that very pass fires, so the case has teeth: only the
## current-role REAR gate (`_try_open_burst()`) holds it.
func test_a_flank_demoted_to_rear_mid_run_fires_nothing_after(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var fired := []
	for demote in [false, true]:
		var w := _world(mode, PLAYERS[0])
		var fighters := _spawn(w, [_v3()], OFFSETS[0], _long_budget)
		var squad: SquadController = fighters[0].squad
		var runner_k := [-1]
		_run(w, fighters, 12.0, func(frame: Dictionary) -> bool:
			for k in frame.f.size():
				var rec: Variant = frame.f[k]
				if rec != null and rec.phase == P.RUN_IN and (rec.pass_role == R.FLANK_LEFT or rec.pass_role == R.FLANK_RIGHT):
					runner_k[0] = k
					return true
			return false)
		assert_ne(runner_k[0], -1, "a flank started its run")
		if runner_k[0] == -1:
			_drop(w)
			return
		var runner := fighters[runner_k[0]]
		var brain := _brain(runner)
		var latched := brain.pass_role
		if demote:
			squad._reassign(runner)
			assert_eq(squad.role_of(runner), R.REAR, "sanity: demoted to REAR mid-run")
		var shots := 0
		var t := 0.0
		while t < 4.0 and (brain.phase == P.RUN_IN or brain.phase == P.EXTEND):
			for f in fighters:
				if _alive(f):
					_tick(f)
			t += DT
			shots += _take_shots(runner)
			if demote:
				assert_eq(brain.pass_role, latched, "the latched pass is still the flank's")
		fired.append(shots)
		_drop(w)
	assert_gt(fired[0], 0, "control: this very pass fires when the flank keeps its role")
	assert_eq(fired[1], 0, "demoted mid-run, it fires nothing")


# ── Edges ────────────────────────────────────────────────────────────────────────────────────────

func test_a_squad_of_one_flies_the_solo_alternation() -> void:
	var w := _world("open_space", PLAYERS[0])
	var fighters := _spawn(w, [WaveBuilder.new().v_formation(1, 40.0, 12.0, 0.0)], OFFSETS[0])
	assert_eq(fighters.size(), 1)
	var frames := _run(w, fighters, 24.0)
	var kinds := []
	for i in _entries(frames, 0, P.RUN_IN):
		kinds.append(frames[i].f[0].kind)
	assert_gte(kinds.size(), 2, "two passes")
	for i in range(1, kinds.size()):
		assert_true(kinds[i] in [K.FLANK_LEFT, K.FLANK_RIGHT] and kinds[i] != kinds[i - 1], "alternating flanks: %s" % [kinds])


func test_a_disengaging_fighter_leaves_the_board() -> void:
	var w := _world("assault", PLAYERS[0])
	var fighters := _spawn(w, [_v3()], OFFSETS[0])
	var squad: SquadController = fighters[0].squad
	var left := [false]
	_run(w, fighters, 12.0, func(frame: Dictionary) -> bool:
		for k in fighters.size():
			var rec: Variant = frame.f[k]
			if rec != null and rec.phase == P.DISENGAGE:
				assert_false(squad.members().has(fighters[k]), "a disengaging fighter is off the board")
				assert_eq(squad.role_of(fighters[k]), R.NONE)
				left[0] = true
				return true
		return false)
	assert_true(left[0], "sanity: a fighter disengaged")


## The give-way is a squad rule: two formations in one wave are two boards, and a fighter gives way
## only to fighters of its own.
func test_strangers_do_not_give_way() -> void:
	var w := _world("open_space", PLAYERS[0])
	var fighters := _spawn(w, [_v3(), _v3()], OFFSETS[0])
	assert_eq(fighters.size(), 6)
	assert_not_same(fighters[0].squad, fighters[3].squad, "sanity: two boards")
	for f in fighters:
		var mates := _brain(f)._mates()
		assert_eq(mates.size(), 2, "%s: its two squad mates" % f.name)
		for mate in mates:
			assert_same(mate.actor.get(&"squad"), f.squad, "%s gives way only to its own squad" % f.name)
