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


func _idle_spawn(h: RefCounted, pos: Vector2, squad: SquadController = null, anchor: Vector2 = Vector2.INF, rng_seed: int = SEED) -> Fighter:
	var f := SCENE.instantiate() as Fighter
	f.global_position = pos
	f.squad = squad
	_brain(f).rng_seed = rng_seed
	_brain(f).patrol_anchor = anchor
	h.root.add_child(f)
	f.set_physics_process(false)
	return f


## One squad, one shared `patrol_anchor` on every member (as `SectorHub` will), each at `anchor + offsets[i]`.
func _idle_squad(h: RefCounted, anchor: Vector2, offsets: Array) -> Array[Fighter]:
	var squad := SquadController.new()
	var out: Array[Fighter] = []
	for i in offsets.size():
		# Each member has its own seed, as the hub gives them, so ring spacing is tested under real draws.
		out.append(_idle_spawn(h, anchor + offsets[i], squad, anchor, SEED + i))
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


# ── Cover (Phase 6 t14; task plan docs/plans/cmvg30aba0087qs2xwv86aq35/3-plan.md) ───────────────────
#
# A solo fighter or a squad LEAD slips behind a wreck on its way in, waits there out of the player's sight, then makes
# its pass from where it is. A real `Wreck` is a solid body on layer 1: a row that needs `can_see_player()` to see it
# awaits two physics frames after placing it (test_sniper.gd's rule); the body-less fixture serves where only the
# registry matters (and, having no body, it never hides the player, so a hold on it never completes). Hazard nodes are
# children of the harness root, so the static registry is empty again after each test.

const _MODES := ["open_space", "assault"]
const FIXTURE_WRECK := preload("res://tests/helpers/fixture_wreck.gd")
const WRECK_MEDIUM: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_medium.tscn")
## The layout: the player at MID, the wreck between it and the fighter, all on one line. C = MID + (315, 0): beyond
## `cover_break_range` from the player and inside the swoop radius (a solo breaches straight out of it), 145 px from
## the fighter, inside the Assault corridor; S (a solo's FLANK_RIGHT pass) is near enough that the Assault reserve
## leaves room for the hold.
const COVER_FIGHTER := MID + Vector2(460.0, 0.0)
const COVER_WRECK := MID + Vector2(250.0, 0.0)
## `cover_hold` (1.2 s) in ticks.
const HOLD_TICKS := 72
## A squad LEAD's layout: above the player on its right, the wreck on its way in, C near the LEAD's FRONTAL S.
const LEAD_FIGHTER := MID + Vector2(150.0, -600.0)
const LEAD_WRECK := MID + Vector2(100.0, -330.0)


## A real medium wreck (r 25), held still unless `drifting`: its own drift and lifetime clock are off.
func _real_wreck(h: RefCounted, pos: Vector2, drifting: bool = false) -> Wreck:
	var wreck := WRECK_MEDIUM.instantiate() as Wreck
	wreck.set_physics_process(drifting)
	h.root.add_child(wreck)
	wreck.global_position = pos
	return wreck


## A body-less, claimable line-of-sight blocker of `radius` at `pos`.
func _fixture_wreck(h: RefCounted, pos: Vector2, radius: float = 25.0) -> Node2D:
	var wreck := FIXTURE_WRECK.new() as Node2D
	wreck.info.radius = radius
	h.root.add_child(wreck)
	wreck.global_position = pos
	return wreck


## A non-blocking hazard of `radius` at `pos` (a well stand-in): the fixture with the blocker flag off.
func _fixture_well(h: RefCounted, pos: Vector2, radius: float) -> Node2D:
	var well := _fixture_wreck(h, pos, radius)
	well.info.line_of_sight_blocker = false
	well.info.kind = &"gravity_well"
	return well


func _info_of(wreck: Node) -> HazardInfo:
	return wreck.call(&"hazard_info") as HazardInfo


## The plan's cover point: on the wreck's far side from `player`, `radius + cover_gap` from its centre.
func _cover_point(wreck_pos: Vector2, radius: float, player: Vector2) -> Vector2:
	return wreck_pos + (wreck_pos - player).normalized() * (radius + CONFIG.cover_gap)


## A squad member, seeded, joined to `squad` by `fighter.gd._ready()` (roles sort by distance to the player).
func _member(h: RefCounted, pos: Vector2, squad: SquadController, rng_seed: int, configure: Callable = Callable()) -> Fighter:
	var f := SCENE.instantiate() as Fighter
	f.global_position = pos
	f.squad = squad
	_brain(f).rng_seed = rng_seed
	_brain(f).start_engaged = true
	if configure.is_valid():
		configure.call(f.config)
	h.root.add_child(f)
	f.set_physics_process(false)
	return f


## Frees a harness now: `TargetInfo.player()` reads the first player in the tree, so a case that builds several
## harnesses drops each before the next.
func _drop(h: RefCounted) -> void:
	var root: Node = h.root
	root.get_parent().remove_child(root)
	root.free()


## Every phase `f` emits from now on, in order.
func _phase_log(f: Fighter) -> Array:
	var out: Array = []
	_brain(f).phase_changed.connect(func(p: int) -> void: out.append(p))
	return out


## The phase emitted right after the first COVER, or -1.
func _after_cover(phases: Array) -> int:
	var at := phases.find(P.COVER)
	return phases[at + 1] if at >= 0 and at + 1 < phases.size() else -1


## Puts every shot straight back in its pool (hand-ticked bullets never fly or expire).
func _recycle(f: Fighter) -> void:
	for pool_name in ["AimedPool", "ForwardPool"]:
		var pool := f.get_node(pool_name) as BulletPool
		for bullet in pool._active.duplicate():
			pool._recycle(bullet)


## Hand-ticks `f`, logging what the brain saw before each tick (`x0`, `v0`, `rot0`, `nose0`, `seen0` =
## `can_see_player()` there, `before` = the phase) and the state after it. Stops when `stop.call(rec)` is true.
func _cover_run(f: Fighter, seconds: float, stop: Callable = Callable(), info: HazardInfo = null) -> Array[Dictionary]:
	var brain := _brain(f)
	var out: Array[Dictionary] = []
	for i in int(round(seconds / DT)):
		var rec := {"i": i, "x0": f.global_position, "v0": f.velocity, "rot0": f.rotation, "nose0": _nose(f),
			"seen0": brain.can_see_player(), "before": brain.phase}
		_tick(f)
		_recycle(f)
		rec["phase"] = brain.phase
		rec["x"] = f.global_position
		rec["bursting"] = brain.is_bursting()
		rec["slack"] = brain.run_budget_slack()
		rec["left"] = brain.budget.remaining()
		rec["start"] = brain.pass_start
		rec["kind"] = brain.pass_kind
		rec["claimed"] = info != null and info.is_claimed_by(f)
		out.append(rec)
		if f.is_queued_for_deletion() or (stop.is_valid() and stop.call(rec)):
			break
	return out


## The index of the first tick that started in COVER and ended elsewhere, or -1.
func _exit_tick(run: Array[Dictionary]) -> int:
	for i in run.size():
		if run[i]["before"] == P.COVER and run[i]["phase"] != P.COVER:
			return i
	return -1


func _first_tick_in(run: Array[Dictionary], phase: int, from: int = 0) -> int:
	for i in range(from, run.size()):
		if run[i]["phase"] == phase:
			return i
	return -1


## True when some tick at or after `from` opened a burst before any DISENGAGE.
func _bursts_before_disengage(run: Array[Dictionary], from: int) -> bool:
	for i in range(from, run.size()):
		if run[i]["phase"] == P.DISENGAGE:
			return false
		if run[i]["bursting"]:
			return true
	return false


func _stop_at_burst(rec: Dictionary) -> bool:
	return rec["bursting"] or rec["phase"] == P.DISENGAGE


func test_cover_is_appended_after_returning() -> void:
	assert_eq(P.COVER, 9, "COVER is appended")
	assert_eq([P.APPROACH, P.RUN_IN, P.EXTEND, P.TURN, P.REPOSITION, P.DISENGAGE, P.IDLE, P.NOTICING, P.RETURNING],
		[0, 1, 2, 3, 4, 5, 6, 7, 8], "no earlier value moved")


func test_the_cover_fields_ship_with_a_gate_assault_can_open() -> void:
	assert_eq(CONFIG.cover_search_radius, 500.0)
	assert_eq(CONFIG.cover_gap, 40.0)
	assert_eq(CONFIG.cover_hold, 1.2)
	assert_eq(CONFIG.cover_break_range, 300.0)
	assert_eq(CONFIG.cover_max, 5.0)
	assert_eq(CONFIG.cover_min_budget, 5.0)
	assert_eq(CONFIG.cover_pass_reserve, 3.0)
	assert_lt(CONFIG.cover_min_budget, CONFIG.engage_seconds - DT, "epic review N2: the Assault gate opens on the spawn tick")
	assert_gte(CONFIG.cover_min_budget, CONFIG.cover_pass_reserve + CONFIG.cover_hold,
		"a cover the gate admits has room for its own hold before the reserve")


func test_a_solo_fighter_hides_behind_a_wreck_then_runs_in(mode: String = use_parameters(_MODES)) -> void:
	var h := _harness(mode)
	var wreck := _real_wreck(h, COVER_WRECK)
	await wait_physics_frames(2)
	var info := wreck.hazard_info()
	var c := _cover_point(COVER_WRECK, info.radius, MID)
	var f := _spawn(h, COVER_FIGHTER)
	_pose(f, Vector2.LEFT)
	var mover := f.get_node("EnemyMover") as EnemyMover
	assert_gt(mover.hazard_avoidance, 0.0, "%s: sanity: the avoidance stage is on for the fighter" % mode)
	var phases := _phase_log(f)
	var run := _cover_run(f, 8.0, _stop_at_burst, info)
	assert_eq(run[0]["phase"], P.COVER, "%s: COVER on the first tick" % mode)
	assert_true(run[0]["claimed"], "%s: the wreck is claimed by the fighter" % mode)
	var exit := _exit_tick(run)
	assert_gt(exit, HOLD_TICKS, "%s: it leaves COVER after holding" % mode)
	if exit <= HOLD_TICKS:
		return
	for i in range(exit - HOLD_TICKS, exit):
		var r: Dictionary = run[i]
		assert_lte((r["x0"] as Vector2).distance_to(c), FighterBrain.COVER_HOLD_PX,
			"%s: within 30 px of C on hold tick %d" % [mode, i])
		assert_false(r["seen0"], "%s: out of the player's sight on hold tick %d" % [mode, i])
		assert_true(r["claimed"], "%s: still claimed on hold tick %d" % [mode, i])
	assert_false(run[exit]["claimed"], "%s: the claim is released on the exit tick" % mode)
	assert_eq(_after_cover(phases), P.APPROACH, "%s: COVER hands to APPROACH" % mode)
	assert_eq(phases.count(P.COVER), 1, "%s: COVER is entered once" % mode)
	assert_lte(exit * DT, CONFIG.cover_max, "%s: within cover_max" % mode)
	if mode == "open_space":
		# Review M1: the latch leaves it at rest, nose on the player, so its heading out of cover is the nose.
		var exit_pose: Dictionary = run[exit]
		assert_lte((exit_pose["v0"] as Vector2).length(), FighterBrain.HEADING_MIN_SPEED, "at rest on the exit tick")
		var to_player := MID - (exit_pose["x0"] as Vector2)
		assert_lte(rad_to_deg(absf((exit_pose["nose0"] as Vector2).angle_to(to_player))), CONFIG.nose_cone_deg,
			"the nose is on the player on the exit tick")
	var run_in := _first_tick_in(run, P.RUN_IN, exit)
	assert_gte(run_in, exit, "%s: a RUN_IN follows" % mode)
	if mode == "assault":
		assert_true(_bursts_before_disengage(run, exit), "assault: the attack after cover fits the budget")
	# "Its usual lead-in": a control from the exit pose, with the wreck gone (the registry is static, review n3).
	var pose: Dictionary = run[exit]
	f.free()
	wreck.free()
	assert_eq(Hazards.count(), 0, "%s: sanity: the control runs with no hazard registered" % mode)
	var control := _spawn(h, pose["x0"])
	control.rotation = pose["rot0"]
	control.velocity = pose["v0"]
	var lead_in := _cover_run(control, 8.0, func(r: Dictionary) -> bool: return r["phase"] == P.RUN_IN)
	assert_eq(lead_in[lead_in.size() - 1]["phase"], P.RUN_IN, "%s: sanity: the control runs in" % mode)
	assert_lte((run_in - exit) * DT, (lead_in.size() - 1) * DT + 0.5,
		"%s: RUN_IN starts within the usual lead-in from the exit pose" % mode)


func test_the_player_within_break_range_breaks_cover_at_once(mode: String = use_parameters(_MODES)) -> void:
	var h := _harness(mode)
	var info := _info_of(_fixture_wreck(h, COVER_WRECK))
	var f := _spawn(h, COVER_FIGHTER)
	_pose(f, Vector2.LEFT)
	var brain := _brain(f)
	var phases := _phase_log(f)
	for _i in 30:
		_tick(f)
	assert_eq(brain.phase, P.COVER, "%s: sanity: in cover" % mode)
	var toward := (MID - f.global_position).normalized()
	h.player.global_position = f.global_position + toward * (CONFIG.cover_break_range + 5.0)
	_tick(f)
	assert_eq(brain.phase, P.COVER, "%s: 5 px outside cover_break_range it stays" % mode)
	h.player.global_position = f.global_position + toward * (CONFIG.cover_break_range - 5.0)
	_tick(f)
	assert_ne(brain.phase, P.COVER, "%s: 5 px inside, it breaks cover that tick" % mode)
	assert_eq(_after_cover(phases), P.APPROACH, "%s: to APPROACH" % mode)
	assert_false(info.is_claimed(), "%s: the claim is free" % mode)


func test_two_solo_fighters_and_one_wreck_only_one_takes_cover(mode: String = use_parameters(_MODES)) -> void:
	var h := _harness(mode)
	var info := _info_of(_fixture_wreck(h, COVER_WRECK))
	var a := _spawn(h, COVER_FIGHTER)
	var b := _spawn(h, COVER_FIGHTER + Vector2(40.0, 60.0))
	a.add_collision_exception_with(b)
	b.add_collision_exception_with(a)
	_pose(a, Vector2.LEFT)
	_pose(b, Vector2.LEFT)
	var took := {}
	var both := false
	var wrong_claimer := false
	for _i in 120:
		_tick(a)
		_tick(b)
		_recycle(a)
		_recycle(b)
		var n := 0
		for f: Fighter in [a, b]:
			if _brain(f).phase == P.COVER:
				n += 1
				took[f] = true
				wrong_claimer = wrong_claimer or not info.is_claimed_by(f)
		both = both or n > 1
	assert_false(both, "%s: never both in cover at once" % mode)
	assert_eq(took.size(), 1, "%s: exactly one fighter ever takes cover" % mode)
	assert_true(took.has(a), "%s: the first to look claims it" % mode)
	assert_false(wrong_claimer, "%s: the one in cover is the claimer" % mode)


func test_a_flank_never_takes_cover_and_its_lead_does(mode: String = use_parameters(_MODES)) -> void:
	var h := _harness(mode)
	var squad := SquadController.new()
	# The LEAD's FRONTAL S is MID + (160, -480) (the player faces UP, the LEAD is on its right); its C, about
	# MID + (119, -392), is ~97 px from it, so it slides from cover straight onto its station (the swoop rule).
	var lead_wreck := _info_of(_fixture_wreck(h, LEAD_WRECK))
	var flank_wreck := _info_of(_fixture_wreck(h, MID + Vector2(-250.0, -250.0)))
	var lead := _member(h, LEAD_FIGHTER, squad, SEED)
	var flank := _member(h, MID + Vector2(-500.0, -500.0), squad, SEED + 1)
	lead.add_collision_exception_with(flank)
	flank.add_collision_exception_with(lead)
	assert_eq(squad.role_of(lead), SquadController.Role.LEAD, "%s: sanity: the nearer member leads" % mode)
	assert_ne(squad.role_of(flank), SquadController.Role.LEAD, "%s: sanity: the other is a flank" % mode)
	var flank_phases := _phase_log(flank)
	var flank_claimed := false
	_tick(lead)
	_tick(flank)
	assert_eq(_brain(lead).phase, P.COVER, "%s: the LEAD takes cover on its first tick" % mode)
	assert_true(lead_wreck.is_claimed_by(lead), "%s: and claims its wreck" % mode)
	for _i in 180:
		_tick(lead)
		_tick(flank)
		_recycle(lead)
		_recycle(flank)
		flank_claimed = flank_claimed or flank_wreck.is_claimed()
	assert_false(flank_phases.has(P.COVER), "%s: the FLANK never takes cover" % mode)
	assert_false(flank_claimed, "%s: its wreck is never claimed" % mode)


func test_a_lead_demoted_in_cover_leaves_it_that_tick(mode: String = use_parameters(_MODES)) -> void:
	var h := _harness(mode)
	var squad := SquadController.new()
	var info := _info_of(_fixture_wreck(h, COVER_WRECK))
	var lead := _member(h, COVER_FIGHTER, squad, SEED)
	var phases := _phase_log(lead)
	for _i in 10:
		_tick(lead)
	assert_eq(_brain(lead).phase, P.COVER, "%s: sanity: a squad of one leads, and takes cover" % mode)
	var closer := _member(h, MID + Vector2(-350.0, 0.0), squad, SEED + 1)
	closer.add_collision_exception_with(lead)
	lead.add_collision_exception_with(closer)
	assert_ne(squad.role_of(lead), SquadController.Role.LEAD, "%s: sanity: the closer join took the lead" % mode)
	_tick(lead)
	assert_ne(_brain(lead).phase, P.COVER, "%s: demoted, it leaves cover that tick" % mode)
	assert_eq(_after_cover(phases), P.APPROACH, "%s: to APPROACH" % mode)
	assert_false(info.is_claimed(), "%s: the claim is released" % mode)


func test_a_wreck_freed_mid_hold_sends_it_to_approach_next_tick(mode: String = use_parameters(_MODES)) -> void:
	var h := _harness(mode)
	var wreck := _real_wreck(h, COVER_WRECK)
	await wait_physics_frames(2)
	var info := wreck.hazard_info()
	var c := _cover_point(COVER_WRECK, info.radius, MID)
	var f := _spawn(h, COVER_FIGHTER)
	_pose(f, Vector2.LEFT)
	var brain := _brain(f)
	var phases := _phase_log(f)
	assert_true(_until(f, 3.0, func() -> bool: return f.global_position.distance_to(c) <= FighterBrain.COVER_HOLD_PX),
		"%s: sanity: it reaches C" % mode)
	for _i in 12:
		_tick(f)
	assert_eq(brain.phase, P.COVER, "%s: sanity: mid-hold" % mode)
	wreck.free()
	_tick(f)
	assert_ne(brain.phase, P.COVER, "%s: out of cover the next tick" % mode)
	assert_eq(_after_cover(phases), P.APPROACH, "%s: to APPROACH" % mode)
	assert_false(info.is_claimed(), "%s: no claim left behind" % mode)


func test_a_wreck_retired_mid_hold_sends_it_to_approach_next_tick() -> void:
	var h := _harness("open_space")
	var wreck := _real_wreck(h, COVER_WRECK)
	await wait_physics_frames(2)
	var info := wreck.hazard_info()
	var f := _spawn(h, COVER_FIGHTER)
	_pose(f, Vector2.LEFT)
	var brain := _brain(f)
	var phases := _phase_log(f)
	for _i in 60:
		_tick(f)
	assert_eq(brain.phase, P.COVER, "sanity: in cover")
	assert_true(info.is_claimed_by(f), "sanity: holding the wreck")
	wreck.retire()
	_tick(f)
	assert_ne(brain.phase, P.COVER, "a retiring wreck is no cover: out the next tick")
	assert_eq(_after_cover(phases), P.APPROACH, "to APPROACH")
	assert_null(brain.cover, "no cover held")


func test_assault_with_less_than_cover_min_budget_takes_no_cover() -> void:
	for extra: float in [0.5, 1.5]:
		var h := _harness("assault")
		var info := _info_of(_fixture_wreck(h, COVER_WRECK))
		# The fighter's PRIVATE config: the budget left after the first update is cover_min_budget -/+ DT / 2.
		var f := _spawn(h, COVER_FIGHTER, "", func(cfg: FighterConfig) -> void:
			cfg.engage_seconds = CONFIG.cover_min_budget + extra * DT)
		_pose(f, Vector2.LEFT)
		_tick(f)
		if extra < 1.0:
			assert_ne(_brain(f).phase, P.COVER, "%.2f s left (< cover_min_budget): no cover" % _brain(f).budget.remaining())
			assert_false(info.is_claimed(), "and the wreck stays unclaimed")
		else:
			assert_eq(_brain(f).phase, P.COVER, "%.2f s left (>= cover_min_budget): cover" % _brain(f).budget.remaining())
		_drop(h)


func test_with_no_wreck_in_reach_the_pass_is_identical_to_the_control(mode: String = use_parameters(_MODES)) -> void:
	var runs: Array[Dictionary] = []
	for far_wreck: bool in [false, true]:
		var h := _harness(mode)
		if far_wreck:
			_fixture_wreck(h, MID + Vector2(5000.0, 0.0))
		assert_eq(Hazards.count(), 1 if far_wreck else 0, "%s: sanity: registry" % mode)
		var f := _spawn(h, COVER_FIGHTER + Vector2(200.0, -200.0))
		_pose(f, Vector2.LEFT)
		var brain := _brain(f)
		var phases := _phase_log(f)
		var ticks: Array = []
		for _i in int(8.0 / DT):
			_tick(f)
			_recycle(f)
			ticks.append([brain.phase, f.global_position, f.velocity])
			if brain.phase == P.TURN:
				break
		runs.append({"ticks": ticks, "phases": phases.duplicate(), "draw": brain.rng.randf()})
		_drop(h)
	assert_true(runs[0]["phases"].has(P.TURN), "%s: sanity: a full pass to the TURN" % mode)
	assert_false(runs[1]["phases"].has(P.COVER), "%s: no COVER with nothing in reach" % mode)
	assert_eq(runs[1]["phases"], runs[0]["phases"], "%s: the same phase sequence" % mode)
	assert_eq(runs[1]["ticks"].size(), runs[0]["ticks"].size(), "%s: the same length" % mode)
	var first_diff := -1
	for i in mini(runs[0]["ticks"].size(), runs[1]["ticks"].size()):
		if runs[0]["ticks"][i] != runs[1]["ticks"][i]:
			first_diff = i
			break
	assert_eq(first_diff, -1, "%s: every tick's phase, position and velocity are identical" % mode)
	assert_eq(runs[1]["draw"], runs[0]["draw"], "%s: and so is the next rng draw" % mode)


## Takes one tick of a fresh Open Space (or Assault) fighter at `fighter_pos` with a fixture wreck at `wreck_pos` after
## `setup.call(h, f, wreck_info)`; returns whether it took cover. Drops the harness.
func _takes_cover(mode: String, fighter_pos: Vector2, wreck_pos: Vector2, setup: Callable = Callable()) -> bool:
	var h := _harness(mode)
	var info := _info_of(_fixture_wreck(h, wreck_pos))
	var f := _spawn(h, fighter_pos)
	_pose(f, (MID - fighter_pos).normalized())
	if setup.is_valid():
		setup.call(h, f, info)
	_tick(f)
	var took := _brain(f).phase == P.COVER
	_drop(h)
	return took


func test_a_wreck_that_breaks_a_cover_rule_is_never_taken() -> void:
	var os := "open_space"
	assert_true(_takes_cover(os, COVER_FIGHTER, COVER_WRECK), "control: the layout takes cover")
	# On its way in: the wreck nearer the player than the fighter (352 px out). Off to the side, so both cover points
	# (412 / 422 px out) stay inside the swoop radius (425 px here) and only this rule decides.
	var side := Vector2.from_angle(deg_to_rad(30.0))
	assert_true(_takes_cover(os, MID + Vector2(352.0, 0.0), MID + side * 347.0), "a wreck 347 px out is on the way in")
	assert_false(_takes_cover(os, MID + Vector2(352.0, 0.0), MID + side * 357.0), "a wreck 357 px out is behind the fighter")
	# C beyond cover_break_range (C = wreck + 65 px).
	assert_true(_takes_cover(os, COVER_FIGHTER, MID + Vector2(240.0, 0.0)), "C 305 px from the player")
	assert_false(_takes_cover(os, COVER_FIGHTER, MID + Vector2(200.0, 0.0)), "C 265 px from the player")
	# C outside every other hazard's radius + hazard_margin (40 + 60).
	var c := _cover_point(COVER_WRECK, 25.0, MID)
	assert_true(_takes_cover(os, COVER_FIGHTER, COVER_WRECK, func(h: RefCounted, _f: Fighter, _i: HazardInfo) -> void:
		_fixture_well(h, c + Vector2(0.0, 105.0), 40.0)), "a well 105 px from C leaves it reachable")
	assert_false(_takes_cover(os, COVER_FIGHTER, COVER_WRECK, func(h: RefCounted, _f: Fighter, _i: HazardInfo) -> void:
		_fixture_well(h, c + Vector2(0.0, 95.0), 40.0)), "a well 95 px from C makes it unreachable")
	# A wreck someone else holds.
	assert_false(_takes_cover(os, COVER_FIGHTER, COVER_WRECK, func(h: RefCounted, _f: Fighter, i: HazardInfo) -> void:
		i.try_claim(h.player)), "a wreck claimed by another node")
	# The forced-pass test seam.
	assert_false(_takes_cover(os, COVER_FIGHTER, COVER_WRECK, func(_h: RefCounted, f: Fighter, _i: HazardInfo) -> void:
		_brain(f).forced_pass_kind = K.FRONTAL), "a FORCED pass kind")
	# cover_search_radius (500) from the wreck's edge (r 25): the fighter 520 / 530 px from its centre.
	assert_true(_takes_cover(os, MID + Vector2(770.0, 0.0), COVER_WRECK), "the wreck's edge 495 px away")
	assert_false(_takes_cover(os, MID + Vector2(780.0, 0.0), COVER_WRECK), "the wreck's edge 505 px away")
	# Assault: C inside the corridor shrunk by the hull (y >= -351.4). A fighter entering from the top; the player moves
	# with the wreck, so C is 310 px from it in both cases (inside the swoop radius, ~325 px with S clamped into the
	# corridor) and only the corridor decides.
	var near_top := func(player_y: float) -> Callable:
		return func(h: RefCounted, _f: Fighter, _i: HazardInfo) -> void: h.player.global_position = Vector2(640.0, player_y)
	assert_true(_takes_cover("assault", Vector2(640.0, -700.0), Vector2(640.0, -280.0), near_top.call(-35.0)),
		"assault: C at y -345")
	assert_false(_takes_cover("assault", Vector2(640.0, -700.0), Vector2(640.0, -300.0), near_top.call(-55.0)),
		"assault: C at y -365")


func test_every_exit_from_cover_releases_the_claim(mode: String = use_parameters(_MODES)) -> void:
	# The mode's own exit: the hub idle loses the player (Open Space), the budget runs out (Assault).
	var h := _harness(mode)
	var info := _info_of(_fixture_wreck(h, COVER_WRECK))
	var f: Fighter
	if mode == "open_space":
		f = _idle_spawn(h, COVER_FIGHTER)
	else:
		# The fighter's PRIVATE config: a reserve far below zero switches the reserve exit off and the hold and cover_max
		# are out of reach, so the budget runs out in COVER (with the shipped reserve the reserve exit always comes first).
		f = _spawn(h, COVER_FIGHTER, "", func(cfg: FighterConfig) -> void:
			cfg.cover_pass_reserve = -100.0
			cfg.cover_hold = 100.0
			cfg.cover_max = 100.0)
	var brain := _brain(f)
	var phases := _phase_log(f)
	assert_true(_until(f, 2.0, func() -> bool: return brain.phase == P.COVER), "%s: sanity: it takes cover" % mode)
	assert_true(info.is_claimed_by(f), "%s: sanity: claimed" % mode)
	if mode == "open_space":
		h.player.global_position = f.global_position + Vector2(-(CONFIG.lose_radius + 50.0), 0.0)
		_tick(f)
		assert_eq(brain.phase, P.RETURNING, "open_space: beyond lose_radius it goes home")
	else:
		assert_true(_until(f, CONFIG.engage_seconds, func() -> bool: return brain.phase != P.COVER), "assault: sanity")
		assert_eq(brain.phase, P.DISENGAGE, "assault: the budget ran out in COVER: DISENGAGE that tick")
	assert_eq(_after_cover(phases), brain.phase, "%s: straight from COVER" % mode)
	assert_false(info.is_claimed(), "%s: the claim is released" % mode)
	_drop(h)
	# A rail takes the fighter over.
	h = _harness(mode)
	info = _info_of(_fixture_wreck(h, COVER_WRECK))
	f = _spawn(h, COVER_FIGHTER)
	_tick(f)
	assert_eq(_brain(f).phase, P.COVER, "%s: sanity: in cover" % mode)
	f.suspend_ai()
	assert_false(info.is_claimed(), "%s: suspend_ai() releases the claim" % mode)
	_drop(h)
	# The player goes away (review m4).
	h = _harness(mode)
	info = _info_of(_fixture_wreck(h, COVER_WRECK))
	f = _spawn(h, COVER_FIGHTER)
	phases = _phase_log(f)
	_tick(f)
	assert_eq(_brain(f).phase, P.COVER, "%s: sanity: in cover" % mode)
	h.player.remove_from_group(&"player")
	_tick(f)
	assert_eq(_brain(f).phase, P.APPROACH, "%s: no player: back to APPROACH the next tick" % mode)
	assert_eq(_after_cover(phases), P.APPROACH, "%s: emitted" % mode)
	assert_false(info.is_claimed(), "%s: the claim is released" % mode)


func test_assault_cover_leaves_with_the_pass_reserve_and_still_attacks() -> void:
	var h := _harness("assault")
	_fixture_wreck(h, COVER_WRECK)
	# The fighter's PRIVATE config: the hold and cover_max are out of reach, so only the reserve can end COVER.
	var f := _spawn(h, COVER_FIGHTER, "", func(cfg: FighterConfig) -> void:
		cfg.cover_hold = 100.0
		cfg.cover_max = 100.0)
	_pose(f, Vector2.LEFT)
	var run := _cover_run(f, CONFIG.engage_seconds + 1.0, _stop_at_burst)
	var exit := _exit_tick(run)
	assert_gt(exit, 1, "sanity: it held cover for a while")
	if exit <= 1:
		return
	# The player is still and so is S: the threshold is read with the S the brain derived in COVER the tick before.
	var s: Vector2 = run[exit - 1]["start"]
	var before: Dictionary = run[exit - 1]
	assert_gt(before["left"], CONFIG.cover_pass_reserve + (before["x0"] as Vector2).distance_to(s) / CONFIG.max_speed,
		"the tick before, the reserve was not yet due")
	assert_lte(run[exit]["left"], CONFIG.cover_pass_reserve + (run[exit]["x0"] as Vector2).distance_to(s) / CONFIG.max_speed,
		"COVER ends on the tick the reserve plus the trip to S is reached")
	var run_in := _first_tick_in(run, P.RUN_IN, exit)
	assert_gte(run_in, exit, "a RUN_IN follows")
	if run_in < 0:
		return
	assert_gt(run[run_in]["slack"], 0.0, "it starts with the run still fitting the budget")
	assert_true(_bursts_before_disengage(run, exit), "and a burst opens before the budget expires")


func test_an_assault_squad_lead_still_attacks_after_cover() -> void:
	# Review M2 (a): a LEAD never breaches; it flies to its S and holds there, and `_go()` refuses once the run no
	# longer fits. Player low on the screen, the LEAD entering from the top, its wreck on the way to its FRONTAL S.
	var h := _harness("assault")
	var player := Vector2(640.0, 600.0)
	h.player.global_position = player
	var w := Vector2(796.0, 210.0)
	_fixture_wreck(h, w)
	var squad := SquadController.new()
	var hold_off := func(cfg: FighterConfig) -> void:
		cfg.cover_hold = 100.0
		cfg.cover_max = 100.0
	var lead := _member(h, Vector2(900.0, -100.0), squad, SEED, hold_off)
	var flank := _member(h, Vector2(380.0, -150.0), squad, SEED + 1)
	lead.add_collision_exception_with(flank)
	flank.add_collision_exception_with(lead)
	assert_eq(squad.role_of(lead), SquadController.Role.LEAD, "sanity: the LEAD")
	var brain := _brain(lead)
	var phases := _phase_log(lead)
	var ticks: Array[Dictionary] = []
	for _i in int((CONFIG.engage_seconds + 1.0) / DT):
		_tick(lead)
		_tick(flank)
		_recycle(lead)
		_recycle(flank)
		ticks.append({"phase": brain.phase, "slack": brain.run_budget_slack(), "bursting": brain.is_bursting()})
		if brain.is_bursting() or brain.phase == P.DISENGAGE:
			break
	assert_eq(ticks[0]["phase"], P.COVER, "sanity: the LEAD takes cover")
	assert_gt(phases.count(P.COVER), 0, "sanity: COVER emitted")
	var run_in := -1
	for i in ticks.size():
		if ticks[i]["phase"] == P.RUN_IN:
			run_in = i
			break
	assert_gt(run_in, 0, "the LEAD runs in after cover")
	if run_in < 0:
		return
	assert_gt(ticks[run_in]["slack"], 0.0, "its RUN_IN starts with the run fitting the budget")
	assert_true(ticks[ticks.size() - 1]["bursting"], "and a burst opens before DISENGAGE")


## The radius a solo at `fighter_pos` would breach from on its first tick (no wreck): APPROACH's own breach radius less
## the hold's slack, read from the brain's own pass, as `FighterBrain._swoops_from()` reads it.
func _solo_swoop_radius(mode: String, fighter_pos: Vector2) -> float:
	var h := _harness(mode)
	var probe := _spawn(h, fighter_pos)
	_pose(probe, (MID - fighter_pos).normalized())
	_tick(probe)
	var b := _brain(probe)
	var swoop := minf(CONFIG.standoff_radius, b.pass_start.distance_to(b.pass_anchor)) - 1.0 \
			- FighterBrain.BREACH_MARGIN - FighterBrain.COVER_HOLD_PX
	_drop(h)
	return swoop


func _short_cover(cfg: FighterConfig) -> void:
	cfg.cover_max = 2.5  # the fixture wreck never hides the player, so the hold never ends COVER: cover_max does


func test_a_solo_takes_cover_only_where_it_breaches_straight_out_of_it(mode: String = use_parameters(_MODES)) -> void:
	# Plan Revision 2: from a cover point beyond its breach radius a solo would fly a Dubins lead-in from rest with its own
	# wreck in the way; the wreck's skirt bends it off that path into a re-planned loop (3-6 s late, in Assault mostly no
	# attack). So it hides only where it breaches from: C 5 px inside the radius is taken, 5 px outside it is not.
	var fighter_pos := MID + Vector2(560.0, 0.0)
	var swoop := _solo_swoop_radius(mode, fighter_pos)
	assert_between(swoop, CONFIG.cover_break_range + 10.0, CONFIG.cover_search_radius, "%s: sanity: a usable band" % mode)
	for inside: bool in [true, false]:
		var c_out := swoop + (-5.0 if inside else 5.0)
		var h := _harness(mode)
		var info := _info_of(_fixture_wreck(h, MID + Vector2(c_out - 25.0 - CONFIG.cover_gap, 0.0)))
		var f := _spawn(h, fighter_pos, "", _short_cover)
		_pose(f, Vector2.LEFT)
		var run := _cover_run(f, 4.0, func(r: Dictionary) -> bool: return r["phase"] == P.RUN_IN, info)
		if inside:
			assert_eq(run[0]["phase"], P.COVER, "%s: C %.0f px out (inside %.0f): cover" % [mode, c_out, swoop])
			var exit := _exit_tick(run)
			assert_gt(exit, 0, "%s: it leaves cover" % mode)
			if exit > 0:
				assert_eq(run[exit]["phase"], P.RUN_IN, "%s: straight into its run, the tick it leaves (a breach)" % mode)
		else:
			assert_ne(run[0]["phase"], P.COVER, "%s: C %.0f px out (outside %.0f): no cover" % [mode, c_out, swoop])
			assert_false(info.is_claimed(), "%s: and the wreck stays unclaimed" % mode)
		_drop(h)


## The FRONTAL S of a squad LEAD above the player on its right (the `LEAD_FIGHTER` side), with no wreck anywhere.
func _lead_start(mode: String) -> Vector2:
	var h := _harness(mode)
	var squad := SquadController.new()
	var lead := _member(h, LEAD_FIGHTER, squad, SEED)
	_member(h, MID + Vector2(-700.0, -700.0), squad, SEED + 1)
	_tick(lead)
	var s := _brain(lead).pass_start
	_drop(h)
	return s


func test_a_squad_lead_takes_cover_only_where_it_slides_straight_onto_its_station(
		mode: String = use_parameters(_MODES)) -> void:
	# Plan Revision 2, the LEAD's half: a LEAD never breaches, it flies to S and holds. It hides only where APPROACH
	# would slide it straight onto S as a station (`_fly_to_start`'s direct arrive) rather than plan a Dubins lead-in
	# from rest behind its wreck. C sits on S's line, `d` to its right. S is the LEAD's FRONTAL start, read from a probe
	# squad with no wreck: MID + (160, -480) in Open Space, its y clamped into the corridor in Assault.
	var s := _lead_start(mode)
	var plan_radius := CONFIG.max_speed / CONFIG.turn_rate * FighterBrain.PLAN_RADIUS_FACTOR
	var limit := FighterBrain.STATION_ARRIVE_PLAN_RADII * plan_radius - FighterBrain.COVER_HOLD_PX
	for inside: bool in [true, false]:
		var c := s + Vector2(limit + (-5.0 if inside else 5.0), 0.0)
		var out := (c - MID).normalized()
		var h := _harness(mode)
		var info := _info_of(_fixture_wreck(h, c - out * (25.0 + CONFIG.cover_gap)))
		var squad := SquadController.new()
		var lead := _member(h, c + out * 200.0, squad, SEED, _short_cover)
		var flank := _member(h, MID + Vector2(-700.0, -700.0), squad, SEED + 1)
		lead.add_collision_exception_with(flank)
		flank.add_collision_exception_with(lead)
		_pose(lead, -out)
		assert_eq(squad.role_of(lead), SquadController.Role.LEAD, "%s: sanity: the LEAD" % mode)
		var brain := _brain(lead)
		_tick(lead)
		_tick(flank)
		assert_almost_eq(brain.pass_start, s, Vector2(0.5, 0.5), "%s: sanity: its S" % mode)
		if not inside:
			assert_ne(brain.phase, P.COVER, "%s: C %.0f px from S (> %.0f): no cover" % [mode, c.distance_to(s), limit])
			assert_false(info.is_claimed(), "%s: and the wreck stays unclaimed" % mode)
			_drop(h)
			continue
		assert_eq(brain.phase, P.COVER, "%s: C %.0f px from S (< %.0f): cover" % [mode, c.distance_to(s), limit])
		var exit := -1
		var at_s := -1
		for i in int(5.0 / DT):
			var before := brain.phase
			_tick(lead)
			_tick(flank)
			_recycle(lead)
			_recycle(flank)
			if exit < 0 and before == P.COVER and brain.phase != P.COVER:
				exit = i
			if exit >= 0 and brain.phase in [P.REPOSITION, P.RUN_IN, P.DISENGAGE]:
				at_s = i
				break
		assert_gt(exit, 0, "%s: it leaves cover" % mode)
		assert_ne(brain.phase, P.DISENGAGE, "%s: and is not sent home" % mode)
		assert_between((at_s - exit) * DT, 0.0, 1.5, "%s: it is on its station (or running in) within 1.5 s" % mode)
		_drop(h)


## A lean replay of the build's measurement (plan Revision 2, 270 layouts): every solo that takes cover leaves it
## straight into its run. Twelve bearings (in Assault, the ones a fighter enters from: above the player), two wreck
## distances each: C 335 / 395 px out in Open Space, 305 / 315 in Assault (where the corridor clamps S inward, so a
## centred player's breach radius is ~355 px and the swoop radius ~325).
func test_every_solo_cover_is_left_straight_into_the_run(mode: String = use_parameters(_MODES)) -> void:
	var player := MID if mode == "open_space" else Vector2(640.0, 620.0)
	var taken := 0
	var late: Array[String] = []
	for i in 12:
		var a := deg_to_rad(7.0 + 30.0 * i) if mode == "open_space" else deg_to_rad(187.0 + 15.0 * i)
		var dir := Vector2.from_angle(a)
		for wreck_out: float in ([270.0, 330.0] if mode == "open_space" else [240.0, 250.0]):
			var h := _harness(mode)
			h.player.global_position = player
			_fixture_wreck(h, player + dir * wreck_out)
			var f := _spawn(h, player + dir * 560.0, "", _short_cover)
			_pose(f, -dir)
			var run := _cover_run(f, 4.0, func(r: Dictionary) -> bool: return r["phase"] == P.RUN_IN)
			if run[0]["phase"] == P.COVER:
				taken += 1
				var exit := _exit_tick(run)
				if exit < 0 or run[exit]["phase"] != P.RUN_IN:
					late.append("bearing %.0f, wreck %.0f px out" % [rad_to_deg(a), wreck_out])
			_drop(h)
	assert_gte(taken, 20, "%s: sanity: most layouts take cover" % mode)
	assert_eq(late, [] as Array[String], "%s: each cover is left straight into RUN_IN, the same tick" % mode)


func test_cover_ends_at_cover_max_when_the_hold_cannot_complete() -> void:
	var h := _harness("open_space")
	var info := _info_of(_fixture_wreck(h, COVER_WRECK))
	# The fighter's PRIVATE config: a hold longer than cover_max.
	var f := _spawn(h, COVER_FIGHTER, "", func(cfg: FighterConfig) -> void: cfg.cover_hold = CONFIG.cover_max + 1.0)
	_pose(f, Vector2.LEFT)
	var phases := _phase_log(f)
	var run := _cover_run(f, CONFIG.cover_max + 0.5, func(r: Dictionary) -> bool: return r["phase"] != P.COVER, info)
	var exit := _exit_tick(run)
	var last := int(round(CONFIG.cover_max / DT))
	assert_eq(run[last - 1]["phase"], P.COVER, "still in cover at cover_max - DT")
	assert_between(exit, last, last + 1, "out at cover_max (tick %d)" % exit)
	assert_eq(_after_cover(phases), P.APPROACH, "to APPROACH")
	assert_false(info.is_claimed(), "the claim is released")


func test_cover_is_once_per_run_in_and_once_per_engagement() -> void:
	var h := _harness("open_space")
	_fixture_wreck(h, COVER_WRECK)
	var f := _spawn(h, COVER_FIGHTER)
	_pose(f, Vector2.LEFT)
	var brain := _brain(f)
	_tick(f)
	assert_eq(brain.phase, P.COVER, "sanity: cover")
	# (a) Back to APPROACH with no RUN_IN in between (the test seam): no second cover.
	brain.enter_phase(P.APPROACH)
	_tick(f)
	assert_ne(brain.phase, P.COVER, "no second cover before a RUN_IN")
	# (b) After a RUN_IN it may take cover again. Only the entry is asserted: a forced RUN_IN leaves the pass latched.
	brain.enter_phase(P.RUN_IN)
	brain.enter_phase(P.APPROACH)
	_tick(f)
	assert_eq(brain.phase, P.COVER, "a RUN_IN clears it")
	_drop(h)
	# (c) A hub fighter that took cover and lost the player (no RUN_IN) takes cover again on the next wake.
	h = _harness("open_space")
	_fixture_wreck(h, COVER_WRECK)
	f = _idle_spawn(h, COVER_FIGHTER)
	brain = _brain(f)
	var phases := _phase_log(f)
	assert_true(_until(f, 2.0, func() -> bool: return brain.phase == P.COVER), "sanity: the woken fighter takes cover")
	h.player.global_position = MID + Vector2(-2000.0, 0.0)
	assert_true(_until(f, 1.0, func() -> bool: return brain.phase == P.RETURNING), "sanity: it goes home")
	h.player.global_position = MID
	assert_true(_until(f, 4.0, func() -> bool: return phases.count(P.COVER) == 2), "it takes cover again on the next wake")
	var first := phases.find(P.COVER)
	assert_false(phases.slice(first, phases.rfind(P.COVER)).has(P.RUN_IN), "with no RUN_IN in between")


# A live-physics row: the hand-ticked rows above overwrite the position after `move_and_slide`, so none of them feels the
# wreck's body. Here the fighter runs on the engine's own physics (8x clock) beside the solid wreck it has claimed.
const _LIVE_SPEEDUP := 8
var _live_saved := [1.0, 60, 8]
var _live_scaled := false


func after_each() -> void:
	if _live_scaled:
		_live_scaled = false
		Engine.time_scale = _live_saved[0]
		Engine.physics_ticks_per_second = _live_saved[1]
		Engine.max_physics_steps_per_frame = _live_saved[2]


func test_on_real_physics_the_fighter_hides_beside_the_solid_wreck(mode: String = use_parameters(_MODES)) -> void:
	var h := _harness(mode)
	# Assault wrecks drift (60 px/s down, review m6): COVER then ends on the hold or on the corridor rule.
	var wreck := _real_wreck(h, COVER_WRECK, mode == "assault")
	await wait_physics_frames(2)
	var info := wreck.hazard_info()
	var f := _spawn(h, COVER_FIGHTER)
	_pose(f, Vector2.LEFT)
	var phases := _phase_log(f)
	var hull := _hull(f)
	var stats := {"min_gap": INF, "held": 0.0, "best_hold": 0.0}
	# The nodes go in through a dictionary, never as captures: GUT resumes this body inside a `physics_frame` emission,
	# so the harness can be freed while that emission still owes this (already disconnected) lambda its call.
	var live := {"f": f, "wreck": wreck}
	var sample := func() -> void:
		if not is_instance_valid(live["f"]) or not is_instance_valid(live["wreck"]):
			return
		var fighter: Fighter = live["f"]
		var w: Node2D = live["wreck"]
		if _brain(fighter).phase != P.COVER:
			return
		stats["min_gap"] = minf(stats["min_gap"], fighter.global_position.distance_to(w.global_position))
		var c := _cover_point(w.global_position, info.radius, MID)
		if fighter.global_position.distance_to(c) <= FighterBrain.COVER_HOLD_PX and not _brain(fighter).can_see_player():
			stats["held"] += fighter.get_physics_process_delta_time()
		else:
			stats["held"] = 0.0
		stats["best_hold"] = maxf(stats["best_hold"], stats["held"])
	get_tree().physics_frame.connect(sample)
	f.set_physics_process(true)
	_live_saved = [Engine.time_scale, Engine.physics_ticks_per_second, Engine.max_physics_steps_per_frame]
	_live_scaled = true
	Engine.physics_ticks_per_second = _live_saved[1] * _LIVE_SPEEDUP
	Engine.max_physics_steps_per_frame = _live_saved[2] * _LIVE_SPEEDUP
	Engine.time_scale = _live_saved[0] * _LIVE_SPEEDUP
	var frames := 0
	while _after_cover(phases) < 0 and frames < 60 * 6:  # 6 s of game time (each physics frame is 1/60 s of it)
		await wait_physics_frames(8)
		frames += 8
	get_tree().physics_frame.disconnect(sample)
	assert_true(phases.has(P.COVER), "%s: it took cover" % mode)
	assert_eq(_after_cover(phases), P.APPROACH, "%s: and left it for APPROACH" % mode)
	assert_false(info.is_claimed(), "%s: with the claim released" % mode)
	assert_gt(stats["min_gap"], info.radius + hull - 2.0, "%s: never inside the wreck's body" % mode)
	if mode == "open_space":
		assert_gte(stats["best_hold"], CONFIG.cover_hold - 0.01, "open_space: it held the cover point, hidden, for cover_hold")
