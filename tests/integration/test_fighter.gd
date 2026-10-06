## The Fighter (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.4, §2.2, §2.8). INTENT tests.
## t8a-fighter-shell: scene wiring, pool sizing for both the AI and the rail cadences, the rail
## fallback read from config fields, `aim_mode` being rail-only, and the Assault exit.
## t8b-fighter-run (task plan docs/plans/cmulwkar000btqj2x1e58sfd4/3-plan.md): the attack run's pass
## geometry in both harnesses, the TURN, the liveness caps, the Assault corridor rules, and the
## weapons layer (selection by distance, the nose cone, cadence, telegraph, deferred DISENGAGE).
##
## Harness rules (same as test_razor_drone.gd): the harness is built inside the body, fighters are
## hand-ticked with `_tick()`, and the shipped config is read from the preloaded `.tres` and never
## written (a case that needs other values writes the fighter's PRIVATE `config`, and says so).
## Every fighter is seeded, so a run is reproducible.
##
## Hand-ticked bullets never fly, so they never expire and their pool would starve after two
## bursts: `_simulate()` records every new shot and puts it straight back in its pool.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
## Shared, read-only: never written (CLAUDE.md config rule).
const CONFIG: FighterConfig = preload("res://assault/scenes/enemies/fighter/fighter_config.tres")

const DT := 1.0 / 60.0
const MID := Vector2(640.0, 360.0)
## `player_fighter.tscn`'s hurtbox radius (5 × 2.7), as test_razor_drone.gd.
const PLAYER_HURTBOX_RADIUS := 13.5
const SEED := 1

const P := FighterBrain.Phase
const K := FighterBrain.PassKind
const W := FighterBrain.WeaponMode


func _harness(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = MID
	return h


func _spawn(h: RefCounted, pos: Vector2, aim_mode: String = "", configure: Callable = Callable()) -> Fighter:
	var fighter := SCENE.instantiate() as Fighter
	fighter.global_position = pos
	fighter.aim_mode = aim_mode
	(fighter.get_node("Brain") as FighterBrain).rng_seed = SEED
	(fighter.get_node("Brain") as FighterBrain).start_engaged = true  # pre-t12: predates the hub idle
	if configure.is_valid():
		configure.call(fighter.config)
	h.root.add_child(fighter)
	fighter.set_physics_process(false)
	return fighter


func _brain(f: Fighter) -> FighterBrain:
	return f.get_node("Brain") as FighterBrain


func _tick(f: BaseEnemy) -> void:
	var before := f.global_position
	f._physics_process(DT)
	f.global_position = before + f.velocity * DT


func _lifetime(round_scene: PackedScene, speed: float) -> float:
	var bullet := round_scene.instantiate() as EnemyBullet
	var life := (bullet.get_node("ProjectileLifetime") as ProjectileLifetime).max_distance / speed
	bullet.free()
	return life


func _bullets_under(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is EnemyBullet and (c as EnemyBullet).visible:
			n += 1
	return n


func _nose(f: Node2D) -> Vector2:
	return Vector2.RIGHT.rotated(f.rotation + EnemyMover.sprite_forward_angle_of(f))


## Points the nose along `nose_dir` and, with `speed` > 0, moves the fighter along `move_dir` (default
## the same) — a test-only staging write; the single-writer gate covers production scripts.
func _pose(f: Fighter, nose_dir: Vector2, speed: float = 0.0, move_dir: Vector2 = Vector2.ZERO) -> void:
	f.rotation = nose_dir.angle() - EnemyMover.sprite_forward_angle_of(f)
	f.velocity = (move_dir if move_dir != Vector2.ZERO else nose_dir).normalized() * speed


func _hull(f: Fighter) -> float:
	var body := f.get_node("CollisionShape2D") as CollisionShape2D
	return (body.shape as CircleShape2D).radius * absf(body.scale.x)


## Hand-ticks `f` for up to `seconds`, moving the player by its own velocity first, and logs every
## tick (`x0` = the position the brain saw, `x` = after the move). `each.call(rec)` returning true
## stops the run. Every new shot is logged with the pre-tick nose and put back in its pool.
func _simulate(h: RefCounted, f: Fighter, seconds: float, each: Callable = Callable()) -> Dictionary:
	var brain := _brain(f)
	var light := f.get_node("StateLight") as StateLight
	var aimed_pattern := (f.get_node("AimedAttack") as AttackController).pattern as AimedAttackPattern
	var pools := {"aimed": f.get_node("AimedPool") as BulletPool, "forward": f.get_node("ForwardPool") as BulletPool}
	var out := {"ticks": [], "shots": [], "freed": false}
	# The burst's last shot clears `aim_point` on its own tick: shots read the last locked value.
	var locked := Vector2.INF
	var t := 0.0
	for i in int(round(seconds / DT)):
		h.player.global_position += h.player.velocity * DT
		var x0 := f.global_position
		var nose0 := _nose(f)
		_tick(f)
		t += DT
		if f.is_queued_for_deletion():
			out.freed = true
			break
		var rec := {"i": i, "t": t, "phase": brain.phase, "x0": x0, "x": f.global_position, "v": f.velocity,
			"p": h.player.global_position, "anchor": brain.pass_anchor, "kind": brain.pass_kind,
			"lane": brain.pass_lane, "dir": brain.pass_dir, "bearing": brain.pass_bearing,
			"side": brain.pass_side, "start": brain.pass_start, "seek": brain.seek_target,
			"light": light.get_state(), "turn_step": brain._turn_step, "bursting": brain.is_bursting(),
			"passes": brain.passes_done, "loiter": brain._loiter_time, "deadline": brain._deadline,
			"budget_left": brain.budget.remaining()}
		if aimed_pattern.aim_point.is_finite():
			locked = aimed_pattern.aim_point
		for mode in pools:
			var pool: BulletPool = pools[mode]
			for bullet in pool._active.duplicate():
				out.shots.append({"t": t, "i": i, "mode": mode, "dir": (bullet as EnemyBullet)._direction,
					"from": (bullet as Node2D).global_position, "phase": brain.phase, "nose": nose0,
					"d": x0.distance_to(h.player.global_position), "aim_point": locked})
				pool._recycle(bullet)
		out.ticks.append(rec)
		if each.is_valid() and each.call(rec):
			break
	return out


## The runs in a log: each a maximal stretch of RUN_IN ticks, with its closest approach to the
## tick's P̂ (`pass_anchor`) and to the live player.
func _runs(run: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cur: Dictionary = {}
	for r in run.ticks:
		if r.phase != P.RUN_IN:
			if not cur.is_empty():
				out.append(cur)
				cur = {}
			continue
		if cur.is_empty():
			cur = {"t0": r.t, "t1": r.t, "kind": r.kind, "lane": r.lane, "dir": r.dir, "bearing": r.bearing,
				"side": r.side, "start": r.start, "entry": r, "ticks": [], "anchor_min": INF, "player_min": INF,
				"closest": r}
		cur.t1 = r.t
		cur.ticks.append(r)
		var da: float = r.x.distance_to(r.anchor)
		if da < cur.anchor_min:
			cur.anchor_min = da
		var dp: float = r.x.distance_to(r.p)
		if dp < cur.player_min:
			cur.player_min = dp
			cur.closest = r
	if not cur.is_empty():
		out.append(cur)
	return out


## Bursts in a log: each starts on the tick the light turns CHARGING and owns the shots up to the
## next one.
func _bursts(run: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var last_light := StateLight.State.OFF
	for r in run.ticks:
		if r.light == StateLight.State.CHARGING and last_light != StateLight.State.CHARGING:
			out.append({"t_charge": r.t, "phase": r.phase, "shots": []})
		last_light = r.light
	for s in run.shots:
		for k in range(out.size() - 1, -1, -1):
			if out[k].t_charge <= s.t:
				out[k].shots.append(s)
				break
	return out


func _min_player_distance(run: Dictionary) -> float:
	var m := INF
	for r in run.ticks:
		m = minf(m, r.x.distance_to(r.p))
	return m


# ── Scene ────────────────────────────────────────────────────────────────────────────────────────

func test_the_scene_has_the_ai_stack_and_no_state_machine() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	assert_not_null(f.get_node_or_null("Brain") as FighterBrain)
	assert_not_null(f.get_node_or_null("EnemyMover") as EnemyMover)
	assert_not_null(f.get_node_or_null("StateLight") as StateLight)
	assert_null(f.get_node_or_null("AIStateMachine"), "the AIStateMachine is deleted")
	assert_false(DirAccess.dir_exists_absolute("res://assault/scenes/enemies/fighter/states"),
		"states/ is deleted")
	assert_eq((f.get_node("EnemyMover") as EnemyMover).constraint_mode, EnemyMover.ConstraintMode.AUTO)


func test_both_attack_controllers_are_brain_driven_and_disabled() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	for n in ["AimedAttack", "ForwardAttack"]:
		var a := f.get_node(n) as AttackController
		assert_true(a.driven_by_brain, "%s is driven by the brain" % n)
		assert_false(a.enabled, "%s starts disabled" % n)
	assert_eq((f.get_node("AimedAttack") as AttackController).bullet_pool, f.get_node("AimedPool"))
	assert_eq((f.get_node("ForwardAttack") as AttackController).bullet_pool, f.get_node("ForwardPool"))
	assert_same(_brain(f).attack, f.get_node("AimedAttack"))
	assert_same(_brain(f).forward_attack, f.get_node("ForwardAttack"))


## `BulletPool` resolves its container as `get_parent().get_parent()`: a pool under an
## `AttackController` would put live bullets under the ship, and they would move with it.
func test_every_bullet_pool_is_a_direct_child_of_the_root() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	var pools := f.find_children("*", "BulletPool", true, false)
	assert_eq(pools.size(), 2)
	for p in pools:
		assert_eq(p.get_parent(), f, "%s is a direct child of the root" % p.name)


func test_the_pools_hold_the_pulse_and_scatter_rounds() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	assert_same((f.get_node("AimedPool") as BulletPool).bullet_scene, EnemyRounds.PULSE)
	assert_same((f.get_node("ForwardPool") as BulletPool).bullet_scene, EnemyRounds.SCATTER)


# ── Config ───────────────────────────────────────────────────────────────────────────────────────

## The mover follows the curve only if the sideways acceleration `turn_rate × max_speed` fits.
func test_config_pins_the_turn_against_the_acceleration() -> void:
	assert_true(CONFIG.turn_rate * CONFIG.max_speed <= CONFIG.acceleration,
		"turn_rate × max_speed ≤ acceleration")


func test_the_config_reaches_the_mover_and_the_hull() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(600, 0))
	var m := f.get_node("EnemyMover") as EnemyMover
	assert_eq(m.max_speed, CONFIG.max_speed)
	assert_eq(m.acceleration, CONFIG.acceleration)
	assert_eq(m.max_turn_rate, CONFIG.turn_rate)
	assert_eq(f.health.max_health, CONFIG.max_health)
	assert_eq(f.contact_hit_box.damage, CONFIG.collision_damage)
	assert_same(_brain(f).config, f.config)


func test_the_rail_fields_are_the_legacy_weapon() -> void:
	assert_eq(CONFIG.rail_aimed_speed, 250.0)
	assert_eq(CONFIG.rail_forward_speed, 420.0)
	assert_eq(CONFIG.rail_forward_interval, 0.3)
	assert_eq(CONFIG.fire_interval, 0.8)


# ── Pools (plan §2.2, review N4) ─────────────────────────────────────────────────────────────────

func test_the_aimed_pool_covers_the_ai_and_both_rail_cadences() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	var size := (f.get_node("AimedPool") as BulletPool).pool_size
	var ai := EnemyRounds.pool_size_for(CONFIG.aimed_max,
		_lifetime(EnemyRounds.PULSE, CONFIG.aimed_speed), CONFIG.min_burst_period)
	var rail_forward := EnemyRounds.pool_size_for(1,
		_lifetime(EnemyRounds.PULSE, CONFIG.rail_forward_speed), CONFIG.rail_forward_interval)
	var rail_aimed := EnemyRounds.pool_size_for(1,
		_lifetime(EnemyRounds.PULSE, CONFIG.rail_aimed_speed), CONFIG.fire_interval)
	assert_gte(size, ai, "AI burst cadence")
	assert_gte(size, rail_forward, "rail FORWARD cadence (the station's shoot_forward fighters)")
	assert_gte(size, rail_aimed, "rail aimed cadence")


func test_the_forward_pool_covers_the_ai_forward_burst() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	var size := (f.get_node("ForwardPool") as BulletPool).pool_size
	var need := EnemyRounds.pool_size_for(CONFIG.forward_max,
		_lifetime(EnemyRounds.SCATTER, CONFIG.forward_speed), CONFIG.min_burst_period)
	assert_gte(size, need)


func test_a_pool_one_short_of_the_need_would_fail_the_check() -> void:
	# Boundary: the sizing rule is a real inequality, not a tautology.
	var need := EnemyRounds.pool_size_for(CONFIG.aimed_max,
		_lifetime(EnemyRounds.PULSE, CONFIG.aimed_speed), CONFIG.min_burst_period)
	assert_false(need - 1 >= need)
	assert_eq(need, 20, "5 rounds × ceil(4.67 s / 1.2 s)")


# ── Rail fallback (plan §2.8) ────────────────────────────────────────────────────────────────────

func test_suspend_installs_the_aimed_rail_pattern_from_config() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400))
	f.suspend_ai()
	var a := f.get_node("AimedAttack") as AttackController
	var p := a.pattern as AimedAttackPattern
	assert_false(a.driven_by_brain)
	assert_true(a.enabled)
	assert_eq(p.fire_interval, CONFIG.fire_interval)
	assert_eq(p.bullet_speed, CONFIG.rail_aimed_speed)
	assert_eq(p.bullet_damage, CONFIG.bullet_damage)
	assert_true(p.aim_at_player)
	assert_false((f.get_node("ForwardAttack") as AttackController).enabled)


func test_suspend_installs_the_forward_rail_pattern_from_config() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400), "FORWARD")
	f.suspend_ai()
	var p := (f.get_node("AimedAttack") as AttackController).pattern as AimedAttackPattern
	assert_eq(p.fire_interval, CONFIG.rail_forward_interval)
	assert_eq(p.bullet_speed, CONFIG.rail_forward_speed)
	assert_eq(p.bullet_damage, CONFIG.bullet_damage)
	assert_false(p.aim_at_player)


func test_the_config_default_aim_mode_is_used_when_no_spawn_prop_is_set() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400), "", func(c: FighterConfig) -> void: c.aim_mode = "FORWARD")
	f.suspend_ai()
	var p := (f.get_node("AimedAttack") as AttackController).pattern as AimedAttackPattern
	assert_eq(p.bullet_speed, CONFIG.rail_forward_speed, "the config's FORWARD applies")


## Rail fire is real: the self-timed controller puts Pulse rounds in the world at the rail cadence.
func test_a_rail_forward_fighter_fires_at_the_rail_interval() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400), "FORWARD")
	f.suspend_ai()
	var a := f.get_node("AimedAttack") as AttackController
	for _i in 3:
		a.tick(CONFIG.rail_forward_interval + 0.001)
	assert_eq(_bullets_under(h.root), 3, "one Pulse round per rail_forward_interval")


func test_a_rail_fighter_is_silent_on_the_forward_controller() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400), "FORWARD")
	f.suspend_ai()
	(f.get_node("ForwardAttack") as AttackController).tick(5.0)
	assert_eq(_bullets_under(h.root), 0)


# ── aim_mode is rail-only ────────────────────────────────────────────────────────────────────────

## Rewritten for t8b: an AI fighter fires now, and `aim_mode` still changes nothing — the same seed
## gives the same motion and the same shots. One harness (TargetInfo reads the first player in the
## tree, so a second harness would be aimed at the first one's player), ticked in lockstep.
func test_aim_mode_on_an_ai_fighter_changes_nothing() -> void:
	var h := _harness("open_space")
	var fighters: Array[Fighter] = [_spawn(h, MID + Vector2(900, -100), ""), _spawn(h, MID + Vector2(900, -100), "FORWARD")]
	var shots: Array = [[], []]
	var same := true
	for i in int(round(11.0 / DT)):
		for k in 2:
			_tick(fighters[k])
			for n in ["AimedPool", "ForwardPool"]:
				var pool := fighters[k].get_node(n) as BulletPool
				for bullet in pool._active.duplicate():
					shots[k].append([i, n, (bullet as EnemyBullet)._direction])
					pool._recycle(bullet)
		if same and (fighters[0].global_position != fighters[1].global_position
				or _brain(fighters[0]).phase != _brain(fighters[1]).phase):
			same = false
			fail_test("tick %d differs: %s vs %s" % [i, fighters[0].global_position, fighters[1].global_position])
	assert_true(same, "same motion")
	assert_eq(shots[1], shots[0], "the same shots")
	assert_gt(shots[0].size(), 0, "sanity: the AI fighter fired")
	for n in ["AimedAttack", "ForwardAttack"]:
		assert_true((fighters[1].get_node(n) as AttackController).driven_by_brain)


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

## Rewritten for t8b: APPROACH no longer holds at the standoff. It hands over to RUN_IN at the pass's
## start point, already pointing along the run.
func test_approach_hands_over_to_run_in_at_the_start_point() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	var brain := _brain(f)
	var handed := false
	for _i in 600:
		_tick(f)
		if brain.phase == P.RUN_IN:
			handed = true
			break
	assert_true(handed, "APPROACH ends in RUN_IN")
	assert_eq(brain.pass_kind, FighterBrain.PassKind.FLANK_RIGHT, "a solo fighter on the right flies FLANK_RIGHT")
	assert_lte(f.global_position.distance_to(brain.pass_start), CONFIG.start_tolerance, "at S")
	assert_lte(absf(f.velocity.angle_to(brain.pass_dir)), deg_to_rad(FighterBrain.HANDOVER_HEADING_DEG),
		"pointing along the run")


func test_phase_changed_carries_the_phase_entered() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	watch_signals(_brain(f))
	_brain(f).enter_phase(P.TURN)
	assert_signal_emitted_with_parameters(_brain(f), "phase_changed", [P.TURN])


# ── Assault DISENGAGE ────────────────────────────────────────────────────────────────────────────

func test_the_assault_budget_expiry_enters_disengage() -> void:
	var h := _harness("assault")
	var f := _spawn(h, MID + Vector2(200, 0), "", func(c: FighterConfig) -> void: c.engage_seconds = 0.5)
	var brain := _brain(f)
	for _i in 20:
		_tick(f)
	assert_ne(brain.phase, P.DISENGAGE, "0.33 s in: still fighting")
	for _i in 20:
		_tick(f)
	assert_eq(brain.phase, P.DISENGAGE)


func test_assault_disengage_frees_the_fighter_outside_the_world_rect() -> void:
	var h := _harness("assault")
	var f := _spawn(h, MID + Vector2(200, 0))
	var brain := _brain(f)
	brain.enter_phase(P.DISENGAGE)
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var freed := false
	for _i in 1500:
		_tick(f)
		if f.is_queued_for_deletion():
			freed = true
			break
	assert_true(freed, "the fighter leaves and frees itself")
	assert_false(rect.has_point(f.global_position), "and it was outside the world rect when freed")


func test_open_space_never_disengages() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(700, 0), "", func(c: FighterConfig) -> void: c.engage_seconds = 0.1)
	for _i in 120:
		_tick(f)
	assert_ne(_brain(f).phase, P.DISENGAGE)
	assert_false(f.is_queued_for_deletion())


# ══ t8b: the attack run ═════════════════════════════════════════════════════════════════════════

## The epic §2.4.1 table with the player at MID facing UP (h = UP, right(h) = RIGHT): per forced kind,
## a far spawn on the approach side, and the latched bearing `b`, run direction `u` and lane `l`.
## FLANK_RIGHT is role-shaped (`pass_offset + flank_lane_gap`); FRONTAL's σ is the spawn's side (+1).
func _worked(kind: int) -> Dictionary:
	match kind:
		K.FLANK_LEFT:
			return {"spawn": MID + Vector2(-900, 200), "b": Vector2(-1, 0), "u": Vector2(1, 0),
				"l": Vector2(0, -CONFIG.pass_offset)}
		K.FLANK_RIGHT:
			return {"spawn": MID + Vector2(900, 200), "b": Vector2(1, 0), "u": Vector2(-1, 0),
				"l": Vector2(0, -(CONFIG.pass_offset + CONFIG.flank_lane_gap))}
		_:
			return {"spawn": MID + Vector2(200, -900), "b": Vector2(0, -1), "u": Vector2(0, 1),
				"l": Vector2(CONFIG.pass_offset, 0)}


func _bearing_for(kind: int, h: Vector2) -> Vector2:
	match kind:
		K.FLANK_LEFT: return h.rotated(-PI / 2.0)
		K.FLANK_RIGHT: return h.rotated(PI / 2.0)
		_: return h


func _first_runs(h: RefCounted, f: Fighter, count: int, seconds: float) -> Dictionary:
	var seen := [0]
	var last := [-1]
	var run := _simulate(h, f, seconds, func(r: Dictionary) -> bool:
		if last[0] == P.RUN_IN and r.phase != P.RUN_IN:
			seen[0] += 1
		last[0] = r.phase
		return seen[0] >= count)
	return run


# ── Phase sequence (dual) ────────────────────────────────────────────────────────────────────────

## Assault raises `engage_seconds` on the private config so the budget allows a second pass.
func test_a_pass_cycle_runs_the_whole_phase_sequence(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _harness(mode)
	var f := _spawn(h, Vector2(900, -500), "", func(c: FighterConfig) -> void: c.engage_seconds = 60.0)
	var seen: Array[int] = []
	_simulate(h, f, 30.0, func(r: Dictionary) -> bool:
		if seen.is_empty() or seen[-1] != r.phase:
			seen.append(r.phase)
		return seen.size() >= 6)
	assert_eq(seen, [P.APPROACH, P.RUN_IN, P.EXTEND, P.TURN, P.REPOSITION, P.RUN_IN] as Array[int],
		"%s: APPROACH → RUN_IN → EXTEND → TURN → REPOSITION → RUN_IN" % mode)


# ── Pass geometry: the epic's worked check (Open Space) ──────────────────────────────────────────

func test_a_holding_player_is_passed_at_the_lane_on_the_stated_side(kind: int = use_parameters([K.FLANK_LEFT, K.FLANK_RIGHT, K.FRONTAL])) -> void:
	var h := _harness("open_space")
	var w := _worked(kind)
	var f := _spawn(h, w.spawn)
	_brain(f).forced_pass_kind = kind
	var runs := _runs(_first_runs(h, f, 1, 20.0))
	assert_eq(runs.size(), 1, "kind %d: one RUN_IN" % kind)
	if runs.is_empty():
		return
	var run: Dictionary = runs[0]
	assert_eq(run.kind, kind)
	assert_lt(run.bearing.distance_to(w.b), 1e-3, "b = %s (got %s)" % [w.b, run.bearing])
	assert_lt(run.dir.distance_to(w.u), 1e-3, "u = %s (got %s)" % [w.u, run.dir])
	assert_lt(run.lane.distance_to(w.l), 1e-3, "l = %s (got %s)" % [w.l, run.lane])
	assert_almost_eq(run.player_min, w.l.length(), 40.0, "kind %d: closest approach = |l| ± 40" % kind)
	var c: Dictionary = run.closest
	if kind == K.FRONTAL:
		assert_gt((c.x - c.p).x * run.side, 0.0, "FRONTAL passes on side σ")
		assert_eq(run.side, 1.0, "σ starts on the fighter's own side")
	else:
		assert_gt((c.x - c.p).dot(Vector2.UP), 0.0, "a flank lane is ahead of the player")


## A player moving at 200 px/s along h (review N1): the lane is anchored on the tick's P̂, so the
## closest approach is measured against `pass_anchor`; "ahead" is still checked against the live
## player. The fighter is staged 100 px beyond S along `b`, pointing along the run heading g.
func test_a_moving_player_is_passed_at_the_lane_around_the_predicted_point(kind: int = use_parameters([K.FLANK_LEFT, K.FLANK_RIGHT, K.FRONTAL])) -> void:
	var h := _harness("open_space")
	h.player.velocity = Vector2(0, -200)
	var w := _worked(kind)
	var f := _spawn(h, w.spawn)
	var brain := _brain(f)
	brain.forced_pass_kind = kind
	for _i in 3:
		_tick(f)
		f.global_position = brain.pass_start + brain.pass_bearing * 100.0
		_pose(f, brain._run_heading, CONFIG.max_speed)
	var runs := _runs(_first_runs(h, f, 1, 12.0))
	assert_false(runs.is_empty(), "kind %d: a RUN_IN" % kind)
	if runs.is_empty():
		return
	var run: Dictionary = runs[0]
	assert_eq(run.kind, kind)
	assert_almost_eq(run.anchor_min, w.l.length(), 40.0, "kind %d: closest approach to P̂ = |l| ± 40" % kind)
	var c: Dictionary = run.closest
	if kind != K.FRONTAL:
		assert_gt((c.x - c.p).dot(Vector2.UP), 0.0, "the flank lane is ahead of the live player")


## A cruising player at a natural spawn (review I6): the passes come (breach-shaped in the steady
## state), and none of them hits the player.
func test_a_cruising_player_still_gets_attack_runs_that_never_touch_it() -> void:
	var h := _harness("open_space")
	h.player.velocity = Vector2(0, -200)
	# Ahead and to the side of the player's course: an encounter it flies into. The steady state is a
	# breach-shaped pass about every 15 s (REPOSITION cannot catch a moving S before its deadline).
	var f := _spawn(h, MID + Vector2(600, -600))
	var run := _simulate(h, f, 20.0)
	var runs := _runs(run)
	assert_gte(runs.size(), 2, "at least two RUN_IN entries in 20 s")
	for r in runs:
		assert_gte(r.player_min, _hull(f) + PLAYER_HURTBOX_RADIUS, "no pass touches the player")


# ── Latching (task plan §1) ──────────────────────────────────────────────────────────────────────

func test_the_pass_is_latched_through_run_in_and_follows_the_player_before_it() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	var brain := _brain(f)
	_simulate(h, f, 15.0, func(r: Dictionary) -> bool: return r.phase == P.RUN_IN)
	assert_eq(brain.phase, P.RUN_IN)
	var latched := [brain.pass_bearing, brain.pass_dir, brain.pass_lane]
	var changed := [false]
	# The player turns through the whole run; h follows its facing, the latched pass must not.
	_simulate(h, f, 5.0, func(r: Dictionary) -> bool:
		h.player.rotation += 0.02
		if r.phase == P.RUN_IN and [r.bearing, r.dir, r.lane] != latched:
			changed[0] = true
		return r.phase != P.RUN_IN)
	assert_false(changed[0], "b, u and l never change during RUN_IN")
	_simulate(h, f, 15.0, func(r: Dictionary) -> bool: return r.phase == P.REPOSITION)
	assert_eq(brain.phase, P.REPOSITION)
	h.player.rotation += PI / 4.0
	_tick(f)
	var h_now := Vector2.UP.rotated(h.player.rotation)
	assert_lt(brain.pass_bearing.distance_to(_bearing_for(brain.pass_kind, h_now)), 1e-3,
		"during REPOSITION the pass follows the player's new heading")


# ── Solo alternation, TURN, clearance ────────────────────────────────────────────────────────────

func test_a_solo_fighter_alternates_flanks_at_the_lane() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	var runs := _runs(_first_runs(h, f, 3, 45.0))
	assert_eq(runs.size(), 3, "three passes")
	var expected := [K.FLANK_RIGHT, K.FLANK_LEFT, K.FLANK_RIGHT]
	for i in runs.size():
		assert_eq(runs[i].kind, expected[i], "pass %d's kind" % i)
		assert_almost_eq(runs[i].player_min, CONFIG.pass_offset, 40.0, "pass %d at pass_offset ± 40" % i)
		assert_gt((runs[i].closest.x - runs[i].closest.p).dot(Vector2.UP), 0.0, "pass %d ahead" % i)


## Measured on the turn-in (TURN's first step), which really turns (review N8): path length over
## heading change.
func test_the_turn_is_a_wide_turn_at_the_configured_radius() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	var run := _simulate(h, f, 15.0, func(r: Dictionary) -> bool: return r.phase == P.TURN and r.turn_step != 0)
	var length := 0.0
	var turned := 0.0
	var prev: Dictionary = {}
	for r in run.ticks:
		if r.phase != P.TURN or r.turn_step != 0:
			prev = {}
			continue
		if not prev.is_empty():
			length += r.x.distance_to(prev.x)
			turned += absf(prev.v.angle_to(r.v))
		prev = r
	assert_gte(turned, PI / 2.0, "the turn-in turns at least 90° (%.0f°)" % rad_to_deg(turned))
	var radius := length / maxf(turned, 1e-6)
	var expected := CONFIG.max_speed / CONFIG.turn_rate
	assert_almost_eq(radius, expected, expected * 0.15, "TURN radius within 15 %")


func test_the_body_never_overlaps_the_player_hurtbox_over_solo_passes() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	var run := _simulate(h, f, 25.0)
	assert_gte(_runs(run).size(), 2, "sanity: it flew passes")
	assert_gte(_min_player_distance(run), _hull(f) + PLAYER_HURTBOX_RADIUS)


## Review I3: one full natural FRONTAL cycle, the closest case in the prototype.
func test_the_body_never_overlaps_the_player_hurtbox_over_frontal_passes() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(200, -900))
	_brain(f).forced_pass_kind = K.FRONTAL
	var run := _first_runs(h, f, 2, 40.0)
	assert_eq(_runs(run).size(), 2, "sanity: two FRONTAL passes")
	assert_gte(_min_player_distance(run), _hull(f) + PLAYER_HURTBOX_RADIUS)


# ── Breach (review N9) ───────────────────────────────────────────────────────────────────────────

## Spawned 380 px out heading at the player, inside the breach radius: the first run is
## FRONTAL-shaped from the current bearing, its lane ⟂ the new run on the side the fighter drifts to.
func test_a_breach_starts_a_frontal_pass_from_the_current_bearing() -> void:
	var h := _harness("open_space")
	var spawn := MID + Vector2(380, 0)
	var f := _spawn(h, spawn)
	var heading := Vector2.LEFT.rotated(0.17)
	_pose(f, heading, CONFIG.max_speed)
	var run := _first_runs(h, f, 1, 10.0)
	var runs := _runs(run)
	assert_eq(runs.size(), 1)
	if runs.is_empty():
		return
	var r: Dictionary = runs[0]
	assert_eq(r.entry.i, 0, "the breach is immediate")
	assert_eq(r.kind, K.FRONTAL)
	assert_lt(r.bearing.distance_to((spawn - MID).normalized()), 1e-3, "b = dir(X − P̂)")
	assert_almost_eq(r.lane.dot(r.dir), 0.0, 1e-3, "l ⟂ u")
	assert_almost_eq(r.lane.length(), CONFIG.pass_offset, 1e-3)
	var drift := signf(r.dir.rotated(PI / 2.0).dot(heading))
	assert_eq(r.side, drift, "σ = the side the fighter already drifts to")
	assert_almost_eq(r.player_min, CONFIG.pass_offset, 60.0, "closest approach pass_offset ± 60")
	assert_gte(_min_player_distance(run), _hull(f) + PLAYER_HURTBOX_RADIUS, "no overlap")


func test_a_player_closing_on_an_approaching_fighter_breaches_it_the_same_way() -> void:
	var h := _harness("open_space")
	h.player.velocity = Vector2(250, 0)
	var f := _spawn(h, MID + Vector2(700, 0))
	_pose(f, Vector2.LEFT, CONFIG.max_speed)  # heading at the player, closing at 550 px/s
	var run := _first_runs(h, f, 1, 10.0)
	var runs := _runs(run)
	assert_eq(runs.size(), 1)
	if runs.is_empty():
		return
	var r: Dictionary = runs[0]
	assert_eq(r.kind, K.FRONTAL, "breached into a FRONTAL-shaped pass")
	assert_lt(r.entry.x0.distance_to(r.entry.p), CONFIG.standoff_radius, "inside the standoff: a breach")
	assert_lt(r.bearing.distance_to((r.start - r.entry.anchor).normalized()), 1e-3, "b = dir(X − P̂)")
	assert_almost_eq(r.lane.dot(r.dir), 0.0, 1e-3, "l ⟂ u")
	assert_gte(_min_player_distance(run), _hull(f) + PLAYER_HURTBOX_RADIUS, "no overlap")


# ── RUN_IN never stalls ──────────────────────────────────────────────────────────────────────────

func test_the_run_in_seek_target_is_always_a_lookahead_ahead() -> void:
	for mode in ["open_space", "assault"]:
		var h := _harness(mode)
		var f := _spawn(h, Vector2(900, -500), "", func(c: FighterConfig) -> void: c.engage_seconds = 60.0)
		var ticks := 0
		for r in _simulate(h, f, 25.0).ticks:
			if r.phase != P.RUN_IN:
				continue
			ticks += 1
			assert_gte((r.seek - r.x0).dot(r.dir), CONFIG.lookahead - 1.0, "%s t=%.2f" % [mode, r.t])
		assert_gt(ticks, 60, "%s: sanity, RUN_IN ran" % mode)


# ── Liveness (task plan §3) ──────────────────────────────────────────────────────────────────────

## A player it cannot catch (420 px/s): APPROACH ends by its deadline in a FRONTAL breach pass, and
## RUN_IN ends by `run_in_max`.
func test_a_player_it_cannot_catch_still_gets_a_pass_by_the_deadline() -> void:
	var h := _harness("open_space")
	h.player.velocity = Vector2(0, -420)
	var f := _spawn(h, MID + Vector2(600, 300))
	var run := _first_runs(h, f, 1, 20.0)
	var runs := _runs(run)
	assert_eq(runs.size(), 1, "a RUN_IN came")
	if runs.is_empty():
		return
	var r: Dictionary = runs[0]
	var last_approach: Dictionary = run.ticks[r.entry.i - 1]
	assert_eq(last_approach.phase, P.APPROACH)
	assert_lte(r.t0, last_approach.deadline + 2.0 * DT, "by APPROACH's deadline")
	assert_eq(r.kind, K.FRONTAL, "the breach pass")
	assert_lte(r.t1 - r.t0, CONFIG.run_in_max + DT, "RUN_IN ends by run_in_max")


# ── Passes done ──────────────────────────────────────────────────────────────────────────────────

## `engage_seconds` raised on the private config so the budget never ends the run first.
func test_assault_disengages_when_the_second_pass_extends_out() -> void:
	var h := _harness("assault")
	var f := _spawn(h, Vector2(900, -860), "", func(c: FighterConfig) -> void: c.engage_seconds = 60.0)
	var run := _simulate(h, f, 40.0, func(r: Dictionary) -> bool: return r.phase == P.DISENGAGE)
	var ticks: Array = run.ticks
	assert_eq(ticks[-1].phase, P.DISENGAGE)
	assert_eq(ticks[-1].passes, CONFIG.passes, "after `passes` passes")
	assert_eq(ticks[-2].phase, P.EXTEND, "straight out of the last EXTEND")


## A burst still running when the last pass completes holds DISENGAGE to its last shot. The private
## config stretches the aimed burst (5 shots, 0.8 s apart) so it outlasts EXTEND, and sets
## `passes` 1.
func test_assault_passes_done_during_a_burst_waits_for_the_last_shot() -> void:
	var h := _harness("assault")
	var f := _spawn(h, Vector2(900, -860), "", func(c: FighterConfig) -> void:
		c.engage_seconds = 60.0
		c.passes = 1
		c.aimed_min = 5
		c.aimed_max = 5
		c.aimed_gap = 0.8)
	var run := _simulate(h, f, 30.0, func(r: Dictionary) -> bool: return r.phase == P.DISENGAGE)
	var ticks: Array = run.ticks
	var completed := -1
	for k in ticks.size():
		if ticks[k].passes >= 1:
			completed = k
			break
	assert_gt(completed, 0)
	assert_true(ticks[completed].bursting, "sanity: a burst was running when the pass completed")
	assert_ne(ticks[completed].phase, P.DISENGAGE, "not yet")
	var last_shot: Dictionary = run.shots[-1]
	assert_eq(ticks[-1].phase, P.DISENGAGE)
	assert_eq(ticks[-1].i, last_shot.i, "DISENGAGE on the burst's last shot")
	assert_eq(_bursts(run)[-1].shots.size(), 5, "the whole burst fired")


## Open Space: after `passes` passes the fighter holds its next start point for `regroup_seconds`.
func test_open_space_regroups_at_the_start_point_after_the_passes() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	var run := _first_runs(h, f, CONFIG.passes + 1, 45.0)
	var loiter: Array = []
	for r in run.ticks:
		if r.phase == P.REPOSITION and r.loiter >= 0.0:
			loiter.append(r)
	assert_false(loiter.is_empty(), "it loitered")
	if loiter.is_empty():
		return
	assert_eq(loiter[0].passes, CONFIG.passes, "after the cycle's passes")
	assert_almost_eq(loiter.size() * DT, CONFIG.regroup_seconds, DT + 1e-6, "for regroup_seconds ± one tick")
	for r in loiter:
		assert_lte(r.x.distance_to(r.start), CONFIG.start_tolerance, "holding S (t=%.2f)" % r.t)
	var after: Dictionary = run.ticks[loiter[-1].i + 1]
	assert_eq(after.phase, P.RUN_IN, "then the next pass")


# ── Assault corridor rules (epic R3.5) ───────────────────────────────────────────────────────────

## `place.call(inner_rect)` returns the player's position: the rect is read from the fighter's own
## constraint, in this harness (a second harness would put a second player in the tree).
func _corridor_run(place: Callable, seconds: float = 8.0) -> Dictionary:
	var h := _harness("assault")
	var f := _spawn(h, Vector2(900, -860))
	var constraint := (f.get_node("EnemyMover") as EnemyMover).constraint as AssaultCorridorConstraint
	h.player.global_position = place.call(constraint.inner_rect())
	var run := _simulate(h, f, seconds)
	run["rect"] = constraint.inner_rect()
	run["soft_band"] = constraint.soft_band
	return run


func _assert_contained(run: Dictionary, label: String) -> void:
	var rect: Rect2 = run.rect
	var band := rect.grow(run.soft_band)
	var entered := false
	for r in run.ticks:
		if r.phase == P.DISENGAGE:
			break
		entered = entered or rect.has_point(r.x)
		if entered and not band.has_point(r.x):
			fail_test("%s: left inner_rect().grow(soft_band) at t=%.2f, %s" % [label, r.t, r.x])
			return
	assert_true(entered, "%s: it entered the corridor" % label)


## The intent case: the shipped config (6 s budget), a centred player, a spawn above the screen.
func test_assault_first_pass_is_a_lateral_flank_run_within_the_budget() -> void:
	var run := _corridor_run(func(_r: Rect2) -> Vector2: return MID)
	var runs := _runs(run)
	assert_false(runs.is_empty(), "a RUN_IN within the budget")
	if runs.is_empty():
		return
	var r: Dictionary = runs[0]
	assert_true(r.kind == K.FLANK_LEFT or r.kind == K.FLANK_RIGHT, "FLANK-shaped")
	assert_almost_eq(absf(r.dir.x), 1.0, 1e-3, "|u.x| = 1: a sweep across the corridor")
	assert_lt(r.t0, CONFIG.engage_seconds)
	for tick in r.ticks:
		if tick.t - r.t0 > 0.2:
			assert_gt(absf(tick.v.x), absf(tick.v.y), "lateral at t=%.2f" % tick.t)
	assert_almost_eq(r.player_min, CONFIG.pass_offset, 40.0)
	_assert_contained(run, "centred")


## Boundary: a flank lane ahead of a player 100 px under the corridor top would be off the top, so
## it flips behind.
func test_assault_lane_flips_behind_a_player_near_the_corridor_top() -> void:
	var run := _corridor_run(func(r: Rect2) -> Vector2: return Vector2(640, r.position.y + 100.0))
	var runs := _runs(run)
	assert_false(runs.is_empty(), "a RUN_IN")
	if runs.is_empty():
		return
	var r: Dictionary = runs[0]
	assert_gt(r.lane.y, 0.0, "the lane is behind (down-screen)")
	assert_gt(r.closest.x.y, r.closest.p.y, "and the fighter passes behind the player")
	assert_almost_eq(r.player_min, CONFIG.pass_offset, 40.0)
	_assert_contained(run, "near the top")


## Boundary: 150 px from the left wall, FLANK_LEFT's clamped start leaves a run shorter than
## `min_run_length`, so the pass comes from the right.
func test_assault_bearing_flips_when_the_run_would_be_too_short() -> void:
	var run := _corridor_run(func(r: Rect2) -> Vector2: return Vector2(r.position.x + 150.0, 360.0))
	var runs := _runs(run)
	assert_false(runs.is_empty(), "a RUN_IN")
	if runs.is_empty():
		return
	for r in runs:
		assert_gt(r.bearing.x, 0.0, "the pass comes from the open (right) side")
		assert_gte((r.entry.anchor + r.lane - r.start).dot(r.dir), CONFIG.min_run_length, "the run is long enough")
	_assert_contained(run, "near the left wall")


# ── Weapons (epic §2.4.2) ────────────────────────────────────────────────────────────────────────

## The intent case (task plan §4): one natural cycle fires the aimed Pulse burst on the run and the
## close Scatter spray when the nose comes back on in the TURN.
func test_a_natural_cycle_fires_one_aimed_burst_on_the_run_and_one_forward_burst_in_the_turn() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	var run := _simulate(h, f, 20.0, func(r: Dictionary) -> bool: return r.phase == P.REPOSITION)
	var bursts := _bursts(run)
	assert_eq(bursts.size(), 2, "two bursts in the first cycle")
	if bursts.size() != 2:
		return
	assert_eq(bursts[0].phase, P.RUN_IN)
	assert_between(bursts[0].shots.size(), CONFIG.aimed_min, CONFIG.aimed_max)
	for s in bursts[0].shots:
		assert_eq(s.mode, "aimed", "RUN_IN fires Pulse")
	assert_eq(bursts[1].phase, P.TURN)
	assert_between(bursts[1].shots.size(), CONFIG.forward_min, CONFIG.forward_max)
	for s in bursts[1].shots:
		assert_eq(s.mode, "forward", "the TURN snapshot fires Scatter")
		assert_lt(s.d, CONFIG.forward_range, "close")


## Stages the TURN snapshot: the player `d` px to the left, the nose on it, the fighter moving
## tangentially (up) at full speed.
func _stage_turn_snapshot(h: RefCounted, d: float, configure: Callable = Callable()) -> Fighter:
	var f := _spawn(h, MID + Vector2(d, 0), "", configure)
	_pose(f, Vector2.LEFT, CONFIG.max_speed, Vector2.UP)
	_brain(f).enter_phase(P.TURN)
	return f


func test_a_close_snapshot_fires_a_forward_scatter_burst_along_the_nose() -> void:
	var h := _harness("open_space")
	var f := _stage_turn_snapshot(h, 250.0)
	var run := _simulate(h, f, 1.5)
	var bursts := _bursts(run)
	assert_eq(bursts.size(), 1)
	if bursts.is_empty():
		return
	assert_eq(_brain(f).weapon_mode, W.FORWARD)
	assert_between(bursts[0].shots.size(), CONFIG.forward_min, CONFIG.forward_max)
	for s in bursts[0].shots:
		assert_eq(s.mode, "forward")
		assert_lte(absf(s.nose.angle_to(s.dir)), CONFIG.forward_spread + 1e-3, "along the nose")


func test_a_far_snapshot_fires_an_aimed_pulse_burst_at_the_locked_point() -> void:
	var h := _harness("open_space")
	var f := _stage_turn_snapshot(h, 400.0)
	var run := _simulate(h, f, 1.5)
	var bursts := _bursts(run)
	assert_eq(bursts.size(), 1)
	if bursts.is_empty():
		return
	assert_eq(_brain(f).weapon_mode, W.AIMED)
	assert_between(bursts[0].shots.size(), CONFIG.aimed_min, CONFIG.aimed_max)
	for s in bursts[0].shots:
		assert_eq(s.mode, "aimed")
		assert_true(s.aim_point.is_finite(), "the aim point is locked for the burst")
		var to_point: Vector2 = s.aim_point - s.from
		assert_lte(absf(to_point.angle_to(s.dir)), CONFIG.aimed_spread + 1e-3, "toward the locked point")
	assert_false(((f.get_node("AimedAttack") as AttackController).pattern as AimedAttackPattern).aim_point.is_finite(),
		"and released after it")


## Boundaries 250/400/330 (the task's acceptance) and the band edges, from the shipped numbers.
func test_weapon_mode_selection_has_hysteresis() -> void:
	assert_eq(CONFIG.forward_range, 325.0)
	assert_eq(CONFIG.mode_hysteresis, 60.0)
	var brain := FighterBrain.new()
	brain.config = CONFIG
	var fr := CONFIG.forward_range
	var top := fr + CONFIG.mode_hysteresis
	for last in [W.AIMED, W.FORWARD]:
		brain.weapon_mode = last
		assert_eq(brain.select_weapon_mode(250.0), W.FORWARD, "250 → FORWARD")
		assert_eq(brain.select_weapon_mode(400.0), W.AIMED, "400 → AIMED")
		assert_eq(brain.select_weapon_mode(330.0), last, "330 keeps the last mode")
		assert_eq(brain.select_weapon_mode(fr - 1.0), W.FORWARD)
		assert_eq(brain.select_weapon_mode(fr), last, "forward_range is inside the band")
		assert_eq(brain.select_weapon_mode(top - 1.0), last)
		assert_eq(brain.select_weapon_mode(top), W.AIMED, "forward_range + hysteresis is AIMED")
	brain.free()


## A FORWARD opportunity with the nose 30° off the player is skipped, not spent: the leg stays open
## and a later on-nose tick fires. Staged on a RUN_IN (forced FLANK_RIGHT, u = LEFT) 300 px out.
func test_an_off_nose_forward_opportunity_is_skipped_not_spent() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(150, -260))
	var brain := _brain(f)
	brain.forced_pass_kind = K.FLANK_RIGHT
	_pose(f, Vector2.LEFT, CONFIG.max_speed)
	brain.enter_phase(P.RUN_IN)
	watch_signals(brain)
	var to_player := MID - f.global_position
	_pose(f, to_player.rotated(deg_to_rad(30.0)), CONFIG.max_speed, Vector2.LEFT)
	_tick(f)
	assert_eq(brain.phase, P.RUN_IN)
	assert_false(brain.is_bursting(), "30° off the nose: no FORWARD burst")
	assert_true(brain._leg_a_open, "the leg is still open")
	assert_eq(brain.weapon_mode, W.AIMED, "nothing latched")
	assert_signal_not_emitted(brain, "weapon_mode_changed")
	_pose(f, MID - f.global_position, CONFIG.max_speed, Vector2.LEFT)
	_tick(f)
	assert_true(brain.is_bursting(), "on the nose: it fires")
	assert_eq(brain._burst_mode, W.FORWARD)


func test_the_mode_is_latched_for_the_whole_burst() -> void:
	var h := _harness("open_space")
	var f := _stage_turn_snapshot(h, 300.0)
	var moved := [false]
	var run := _simulate(h, f, 1.5, func(r: Dictionary) -> bool:
		if r.bursting and not moved[0]:
			moved[0] = true
			h.player.global_position = f.global_position + Vector2.LEFT * 450.0  # past 385 mid-burst
		return false)
	var bursts := _bursts(run)
	assert_eq(bursts.size(), 1)
	if bursts.is_empty():
		return
	assert_between(bursts[0].shots.size(), CONFIG.forward_min, CONFIG.forward_max)
	for s in bursts[0].shots:
		assert_eq(s.mode, "forward", "still FORWARD at %.0f px" % s.d)
	assert_gt(bursts[0].shots[-1].d, CONFIG.forward_range + CONFIG.mode_hysteresis, "sanity: it crossed")


func test_weapon_mode_changed_fires_once_per_change_and_never_for_a_repeat() -> void:
	var h := _harness("open_space")
	var brain: FighterBrain
	var fired := [0]
	for d in [250.0, 250.0, 400.0]:
		var f := _stage_turn_snapshot(h, d)
		var b := _brain(f)
		b.weapon_mode_changed.connect(func(mode: int) -> void: fired.append(mode))
		if brain != null:
			b.weapon_mode = brain.weapon_mode  # the same fighter's history, carried over
		_simulate(h, f, 1.0)
		brain = b
		f.queue_free()
	assert_eq(fired, [0, W.FORWARD, W.AIMED], "FORWARD once, not for the repeat, then AIMED")


# ── Cadence and telegraph ────────────────────────────────────────────────────────────────────────

func test_burst_cadence_and_the_telegraph_over_natural_passes() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	var run := _simulate(h, f, 25.0)
	var bursts := _bursts(run)
	assert_gte(bursts.size(), 3, "sanity: several bursts")
	for b in bursts:
		var shots: Array = b.shots
		assert_false(shots.is_empty(), "a telegraph is always followed by shots")
		if shots.is_empty():
			continue
		assert_almost_eq(shots[0].t - b.t_charge, CONFIG.burst_telegraph, DT + 1e-6,
			"CHARGING precedes the first shot by burst_telegraph ± one tick")
		var gap := CONFIG.forward_gap if shots[0].mode == "forward" else CONFIG.aimed_gap
		for k in range(1, shots.size()):
			assert_eq(shots[k].mode, shots[0].mode, "one mode per burst")
			assert_almost_eq(shots[k].t - shots[k - 1].t, gap, DT + 1e-6, "shot gap ± one tick")
	# At most one burst per leg: leg A = RUN_IN (+ EXTEND), leg B = TURN.
	var per_leg := {}
	var leg := -1
	var last_phase := -1
	for r in run.ticks:
		if r.phase != last_phase and (r.phase == P.RUN_IN or r.phase == P.TURN):
			leg += 1
		last_phase = r.phase
		if r.light == StateLight.State.CHARGING and (r.i == 0 or run.ticks[r.i - 1].light != StateLight.State.CHARGING):
			per_leg[leg] = per_leg.get(leg, 0) + 1
	for k in per_leg:
		assert_lte(per_leg[k], 1, "leg %d: at most one burst" % k)


## Review I2, the TURN half: a nose-on blocked by `min_burst_period` gives no leg-B burst in that
## TURN, and leg B stays unspent until the TURN ends.
func test_a_snapshot_inside_min_burst_period_gives_no_turn_burst() -> void:
	var h := _harness("open_space")
	var f := _stage_turn_snapshot(h, 250.0)
	var brain := _brain(f)
	brain._since_burst = 0.5
	var open_throughout := [true]
	var run := _simulate(h, f, 10.0, func(r: Dictionary) -> bool:
		if r.phase == P.TURN and not brain._leg_b_open:
			open_throughout[0] = false
		return r.phase != P.TURN)
	assert_ne(brain.phase, P.TURN, "sanity: the TURN ended")
	assert_eq(run.shots.size(), 0, "no burst in that TURN")
	assert_true(open_throughout[0], "leg B unspent until the TURN ended")


## Review I2, the RUN_IN half: a RUN_IN staged 0.5 s after a burst start opens its burst at
## `min_burst_period` (1.2 s), not before.
func test_a_run_in_burst_waits_for_min_burst_period() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(450, -260))
	var brain := _brain(f)
	brain.forced_pass_kind = K.FLANK_RIGHT
	_pose(f, Vector2.LEFT, CONFIG.max_speed)
	brain.enter_phase(P.RUN_IN)
	brain._since_burst = 0.5
	var run := _simulate(h, f, 1.5, func(r: Dictionary) -> bool: return r.bursting)
	assert_true(run.ticks[-1].bursting, "the burst opened")
	assert_eq(run.ticks[-1].phase, P.RUN_IN, "on the run")
	assert_almost_eq(run.ticks[-1].t, CONFIG.min_burst_period - 0.5, DT + 1e-6, "at 1.2 s after the last start")


# ── Deferred DISENGAGE ───────────────────────────────────────────────────────────────────────────

## Budget expiry mid-telegraph (the private config: a 0.15 s budget and the longest aimed burst):
## the phase holds until the last shot, and DISENGAGE starts within 0.8 s of expiry.
func test_budget_expiry_during_a_burst_defers_disengage_to_its_end() -> void:
	var h := _harness("assault")
	var f := _spawn(h, MID + Vector2(450, -260), "", func(c: FighterConfig) -> void:
		c.engage_seconds = 0.15
		c.aimed_min = c.aimed_max)
	var brain := _brain(f)
	brain.forced_pass_kind = K.FLANK_RIGHT
	_pose(f, Vector2.LEFT, CONFIG.max_speed)
	brain.enter_phase(P.RUN_IN)
	var run := _simulate(h, f, 2.0, func(r: Dictionary) -> bool: return r.phase == P.DISENGAGE)
	var ticks: Array = run.ticks
	var expiry := -1.0
	for r in ticks:
		if expiry < 0.0 and r.budget_left <= 0.0:
			expiry = r.t
			assert_true(r.bursting, "sanity: the budget expired mid-burst")
			assert_eq(r.light, StateLight.State.CHARGING, "sanity: during the telegraph")
	assert_eq(ticks[-1].phase, P.DISENGAGE)
	assert_eq(run.shots.size(), CONFIG.aimed_max, "the whole burst fired first")
	assert_eq(ticks[-1].i, run.shots[-1].i, "DISENGAGE on the last shot's tick")
	assert_lte(ticks[-1].t - expiry, 0.8, "within 0.8 s of expiry")
	for k in ticks.size() - 1:
		assert_ne(ticks[k].phase, P.DISENGAGE)


func test_budget_expiry_with_no_burst_disengages_on_the_same_tick() -> void:
	var h := _harness("assault")
	# Inside the world rect, or the first DISENGAGE tick frees it before the log sees it.
	var f := _spawn(h, MID + Vector2(520, 0), "", func(c: FighterConfig) -> void: c.engage_seconds = 0.5)
	var run := _simulate(h, f, 1.0, func(r: Dictionary) -> bool: return r.budget_left <= 0.0)
	var last: Dictionary = run.ticks[-1]
	assert_false(last.bursting, "sanity: no burst")
	assert_eq(last.phase, P.DISENGAGE, "the tick the budget expires")
	assert_ne(run.ticks[-2].phase, P.DISENGAGE)


# ══ t12: hub idle (epic §2.10, X2; task docs/plans/cmulwkarc00c9qj2xd96u20gn) ═══════════════════════
#
# Cold-start helpers: unlike `_spawn()` (which sets `start_engaged = true`, so every case above keeps
# assuming combat-from-spawn exactly as before this task), these leave the brain to decide for itself —
# Open Space starts IDLE, Assault starts in combat.

const FAR_AWAY := Vector2(100000.0, 100000.0)


func _idle_spawn(h: RefCounted, pos: Vector2, squad: SquadController = null, anchor: Vector2 = Vector2.INF) -> Fighter:
	var f := SCENE.instantiate() as Fighter
	f.global_position = pos
	f.squad = squad
	_brain(f).rng_seed = SEED
	_brain(f).patrol_anchor = anchor
	h.root.add_child(f)
	f.set_physics_process(false)
	return f


## One squad, one shared `patrol_anchor` on every member (as `SectorHub` will), each at `anchor + offsets[i]`.
func _idle_squad(h: RefCounted, anchor: Vector2, offsets: Array) -> Array[Fighter]:
	var squad := SquadController.new()
	var out: Array[Fighter] = []
	for off in offsets:
		out.append(_idle_spawn(h, anchor + off, squad, anchor))
	return out


func _tick_all(fighters: Array[Fighter]) -> void:
	for f in fighters:
		_tick(f)


## Ticks `f` until `cond` is true or `seconds` run out; returns whether it became true.
## True once the fighter is past its beat: in a fight phase (APPROACH usually hands straight over to RUN_IN).
func _fighting(f: Fighter) -> bool:
	return _brain(f).phase != P.IDLE and _brain(f).phase != P.NOTICING and _brain(f).phase != P.RETURNING


func _until(f: Fighter, seconds: float, cond: Callable) -> bool:
	for _i in int(seconds / DT):
		_tick(f)
		if cond.call():
			return true
	return false


func test_idle_phases_are_appended_so_the_earlier_values_do_not_move() -> void:
	assert_eq(P.APPROACH, 0)
	assert_eq(P.DISENGAGE, 5)
	assert_eq(P.IDLE, 6)
	assert_eq(P.NOTICING, 7)
	assert_eq(P.RETURNING, 8)


func test_the_idle_radii_clear_the_fire_range_with_a_hysteresis_margin() -> void:
	assert_gte(CONFIG.perceive_radius, CONFIG.fire_range, "it must notice the player before it can shoot")
	assert_gt(CONFIG.lose_radius, CONFIG.perceive_radius, "AnchorIdle's hysteresis margin")


func test_open_space_cold_start_begins_idle_on_the_spawn_point() -> void:
	var h := _harness("open_space")
	h.player.global_position = FAR_AWAY
	var pos := Vector2(321.0, -654.0)
	var f := _idle_spawn(h, pos)
	_tick(f)
	assert_eq(_brain(f).phase, P.IDLE, "Open Space starts on patrol, not in combat")
	assert_not_null(_brain(f).anchor_idle)
	assert_eq(_brain(f).patrol_anchor, pos, "an unset anchor defaults to the spawn position")


func test_the_assault_harness_starts_in_approach_with_no_idle() -> void:
	var h := _harness("assault")
	var f := _idle_spawn(h, MID + Vector2(0, -700))
	_tick(f)
	assert_eq(_brain(f).phase, P.APPROACH, "Assault always starts in combat")
	assert_null(_brain(f).anchor_idle, "no AnchorIdle is built in Assault")


func test_no_shot_is_fired_while_idle() -> void:
	var h := _harness("open_space")
	h.player.global_position = MID
	var f := _idle_spawn(h, MID + Vector2(CONFIG.perceive_radius + CONFIG.idle_radius + 80.0, 0.0))  # the whole ring is clear
	var run := _simulate(h, f, 10.0)
	assert_eq(run.shots.size(), 0, "no shot while the player is outside perceive_radius")
	for r in run.ticks:
		assert_eq(r.phase, P.IDLE)


func test_idle_stays_on_the_ring_over_20_seconds() -> void:
	var h := _harness("open_space")
	h.player.global_position = FAR_AWAY
	var anchor := Vector2(500.0, -400.0)
	var fighters := _idle_squad(h, anchor, [Vector2(20, 0), Vector2(-15, 10)])
	var worst := 0.0
	for _i in int(20.0 / DT):
		_tick_all(fighters)
		for f in fighters:
			assert_eq(_brain(f).phase, P.IDLE)
			worst = maxf(worst, f.global_position.distance_to(anchor))
	assert_lte(worst, CONFIG.idle_radius + 30.0, "worst %.1f px from the anchor" % worst)


## `member_index × TAU / n`: a pair sits opposite each other.
func test_a_pair_sits_opposite_each_other_on_the_ring() -> void:
	var h := _harness("open_space")
	h.player.global_position = FAR_AWAY
	var anchor := Vector2(-800.0, 300.0)
	var pair := _idle_squad(h, anchor, [Vector2.ZERO, Vector2.ZERO])
	for _i in int(8.0 / DT):
		_tick_all(pair)
	var gap := pair[0].global_position.distance_to(pair[1].global_position)
	assert_gt(gap, CONFIG.idle_radius * 1.6, "a pair is spread round the ring (%.0f px apart)" % gap)


func test_a_trio_is_spread_a_third_of_the_ring_apart() -> void:
	var h := _harness("open_space")
	h.player.global_position = FAR_AWAY
	var anchor := Vector2(-800.0, 300.0)
	var trio := _idle_squad(h, anchor, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	for _i in int(8.0 / DT):
		_tick_all(trio)
	for a in 3:
		for b in range(a + 1, 3):
			var d := trio[a].global_position.distance_to(trio[b].global_position)
			assert_gt(d, CONFIG.idle_radius, "trio members %d and %d are a third of the ring apart (%.0f px)" % [a, b, d])


func test_perceiving_the_player_notices_then_fights_with_no_shot_in_between() -> void:
	var h := _harness("open_space")
	var f := _idle_spawn(h, MID + Vector2(0.0, -400.0))
	var run := _simulate(h, f, 0.5)
	var seq: Array = []
	for r in run.ticks:
		if seq.is_empty() or seq[-1] != r.phase:
			seq.append(r.phase)
	assert_eq(seq[0], P.NOTICING, "NOTICING for a beat first")
	assert_true(seq.size() > 1 and (seq[1] == P.APPROACH or seq[1] == P.RUN_IN), "then the fight starts (phase %s)" % [seq])
	for s in run.shots:
		assert_ne(s.phase, P.NOTICING, "no shot during NOTICING")
	assert_eq(run.shots.size(), 0, "no shot in the first half second either")


func test_a_player_just_outside_perceive_radius_changes_nothing_and_just_inside_wakes_it() -> void:
	var h := _harness("open_space")
	var f := _idle_spawn(h, Vector2.ZERO)
	h.player.global_position = Vector2(CONFIG.perceive_radius + CONFIG.idle_radius + 40.0, 0.0)  # the whole ring is clear
	for _i in 120:
		_tick(f)
	assert_eq(_brain(f).phase, P.IDLE)
	h.player.global_position = f.global_position + Vector2(CONFIG.perceive_radius - 40.0, 0.0)
	_tick(f)
	assert_eq(_brain(f).phase, P.NOTICING)


func test_it_stays_engaged_between_the_radii() -> void:
	var h := _harness("open_space")
	var f := _idle_spawn(h, Vector2.ZERO)
	h.player.global_position = Vector2(300.0, 0.0)
	assert_true(_until(f, 2.0, func() -> bool: return _fighting(f)), "reached combat")
	var mid := (CONFIG.perceive_radius + CONFIG.lose_radius) / 2.0
	for _i in int(5.0 / DT):
		h.player.global_position = f.global_position + Vector2(mid, 0.0)
		_tick(f)
		assert_ne(_brain(f).phase, P.RETURNING, "never returns while within lose_radius")
		assert_ne(_brain(f).phase, P.IDLE)


func test_beyond_lose_radius_it_returns_to_the_ring_and_can_fight_again() -> void:
	var h := _harness("open_space")
	var anchor := Vector2.ZERO
	var f := _idle_spawn(h, anchor + Vector2(100.0, 0.0), null, anchor)
	h.player.global_position = Vector2(400.0, 0.0)
	assert_true(_until(f, 2.0, func() -> bool: return _fighting(f)))
	for _i in int(2.0 / DT):
		_tick(f)
	h.player.global_position = FAR_AWAY
	var saw := {"returning": false}  # a lambda captures a bool by value
	var settled := _until(f, 30.0, func() -> bool:
		saw.returning = saw.returning or _brain(f).phase == P.RETURNING
		return _brain(f).phase == P.IDLE)
	assert_true(saw.returning, "it passes through RETURNING on the way home")
	assert_true(settled, "and reaches IDLE")
	assert_lte(f.global_position.distance_to(anchor), CONFIG.idle_radius + 30.0, "back inside the ring")
	# …and turns to fight again.
	h.player.global_position = f.global_position + Vector2(0.0, -400.0)
	assert_true(_until(f, 4.0, func() -> bool: return _brain(f).phase == P.RUN_IN), "a second engagement flies a real pass")


func test_returning_never_interrupts_a_burst() -> void:
	var h := _harness("open_space")
	var f := _idle_spawn(h, MID + Vector2(0.0, -400.0), null, MID + Vector2(0.0, -1000.0))  # home is far
	assert_true(_until(f, 2.0, func() -> bool: return _fighting(f)))
	_brain(f).enter_phase(P.RUN_IN)
	assert_true(_until(f, 3.0, func() -> bool: return _brain(f).is_bursting()), "a burst opened")
	h.player.global_position = FAR_AWAY
	var ticks_bursting := 0
	for _i in int(3.0 / DT):
		_tick(f)
		if _brain(f).is_bursting():
			ticks_bursting += 1
			assert_ne(_brain(f).phase, P.RETURNING, "RETURNING waits for the burst")
		elif _brain(f).phase == P.RETURNING:
			break
	assert_gt(ticks_bursting, 0, "sanity: the burst was still running after the player left")
	assert_eq(_brain(f).phase, P.RETURNING, "and the fighter heads home as soon as it ends")


func test_one_member_perceiving_wakes_the_whole_squad() -> void:
	var h := _harness("open_space")
	h.player.global_position = FAR_AWAY
	var fighters := _idle_squad(h, Vector2.ZERO, [Vector2(-5000, 0), Vector2(0, 0)])
	_tick_all(fighters)
	h.player.global_position = fighters[1].global_position + Vector2(CONFIG.perceive_radius - 50.0, 0.0)
	_tick_all(fighters)
	_tick_all(fighters)
	for f in fighters:
		assert_ne(_brain(f).phase, P.IDLE, "every member is out of IDLE by the end of the next tick")


func test_a_squad_leaves_idle_with_no_attack_window_left_open() -> void:
	var h := _harness("open_space")
	var fighters := _idle_squad(h, Vector2.ZERO, [Vector2.ZERO, Vector2.ZERO])
	h.player.global_position = Vector2(400.0, 0.0)
	for _i in int(6.0 / DT):
		_tick_all(fighters)
	h.player.global_position = FAR_AWAY
	for _i in int(30.0 / DT):
		_tick_all(fighters)
	for f in fighters:
		assert_eq(_brain(f).phase, P.IDLE, "the whole squad is home")
	assert_false(fighters[0].squad.attack_window_open, "no window stays open behind a squad that went home")


# ── Art (t14-art-fighter, plan §2.7) ─────────────────────────────────────────────────────────────

## The PNG is drawn nose-UP and the sprite is a single-frame `AnimatedSprite2D`, which
## `BaseEnemy._rotate_sprite()` turns 180° on entering the tree, so the nose in the root's frame is
## straight down: PI/2. The node keeps its type and name, so the HitFlash track path and
## `test_base_enemy.gd`'s flip list stay valid.
func test_the_scene_declares_the_nose_the_sprite_was_drawn_with() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400))
	var sprite := f.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	assert_not_null(sprite, "the node the HitFlash track and the flip list name")
	assert_almost_eq(sprite.rotation_degrees, 180.0, 0.001, "flipped by _rotate_sprite")
	assert_almost_eq(f.sprite_forward_angle, PI / 2.0, 0.0001)
	var nose_in_root := Vector2.UP.rotated(sprite.rotation)  # the PNG's nose is up
	assert_almost_eq(Vector2.RIGHT.rotated(f.sprite_forward_angle).dot(nose_in_root), 1.0, 0.0001,
		"the declared nose is where the flipped art's nose points")


## The declared angle is honest about the PNG: a compact dart — the top rows (the nose) are narrow,
## the wings at mid-hull are the widest part, and it is well inside a 64 px canvas.
func test_the_art_is_a_compact_dart_with_the_nose_at_the_top() -> void:
	var f := SCENE.instantiate() as Fighter
	var img: Image = ((f.get_node("AnimatedSprite2D") as AnimatedSprite2D).sprite_frames.get_frame_texture(&"default", 0)).get_image()
	f.free()
	var first_row := -1
	var nose_width := 0
	var widest := 0
	for y in img.get_height():
		var lo := img.get_width()
		var hi := -1
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				lo = mini(lo, x)
				hi = maxi(hi, x)
		if hi < 0:
			continue
		var w := hi - lo + 1
		if first_row < 0:
			first_row = y
			nose_width = w
		widest = maxi(widest, w)
	assert_lte(first_row, 6, "the nose reaches the top of the texture")
	assert_lt(nose_width * 4, widest, "a pointed nose, far narrower than the wings")
	assert_lte(img.get_width(), 72)
	assert_lte(img.get_height(), 72)
	assert_gte(img.get_height(), 56, "56-72 px readable hull")


## A forward rail shot on the REAL scene leaves along the travel direction: at the rotation
## `EnemyMover` would give each heading, the Pulse round goes that way.
func test_a_forward_rail_shot_leaves_along_the_travel_direction_on_the_real_scene() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400), "FORWARD")
	f.suspend_ai()
	var p := (f.get_node("AimedAttack") as AttackController).pattern as AimedAttackPattern
	p.spread_angle = 0.0
	var pool := f.get_node("AimedPool") as BulletPool
	for heading in [Vector2.DOWN, Vector2.UP, Vector2.RIGHT]:
		f.rotation = (heading as Vector2).angle() - f.sprite_forward_angle
		p.fire(f, pool)
		var shot: EnemyBullet = null
		for c in h.root.get_children():
			if c is EnemyBullet and (c as EnemyBullet).visible:
				shot = c
		assert_not_null(shot)
		var dir := Vector2.from_angle(shot.rotation + PI / 2.0)
		assert_gt(dir.dot(heading), 0.999, "the round leaves along the travel direction %s" % heading)
		shot.visible = false


## The StateLight sits on the hull (an opaque pixel of the sprite), not floating off the art.
func test_the_state_light_sits_on_the_hull() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400))
	var sprite := f.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var tex := sprite.sprite_frames.get_frame_texture(&"default", 0)
	var img := tex.get_image()
	var local := sprite.to_local((f.get_node("StateLight") as Node2D).global_position) + Vector2(img.get_size()) * 0.5
	assert_gt(img.get_pixelv(Vector2i(local)).a, 0.99, "StateLight at texture pixel %s is on opaque hull" % local)
