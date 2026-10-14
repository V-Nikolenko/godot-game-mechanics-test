## The Bomber shell (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.4, §2.8; task t9-bomber-shell).
##
## What t9 pins: the scene's structure (three persistent ordnance pools as root children, one
## `RectangleShape2D` body shared by the contact hitbox and the hurtbox so the wings are shootable),
## the rail fallback (a gravity bomb DOWN every `rail_bomb_interval`, from config), that a bomb outlives
## its bomber, and the Assault budget's DISENGAGE exit. t10 (below) adds the bombing runs.
##
## Everything is hand-stepped with a fixed delta (the harness world has no engine physics ticks for the
## bomber: `set_physics_process(false)`), never a `Timer`.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const BOMBER_SCENE: PackedScene = preload("res://assault/scenes/enemies/bomber/bomber.tscn")
const SHIPPED: BomberConfig = preload("res://assault/scenes/enemies/bomber/bomber_config.tres")  # read only

const DT := 1.0 / 60.0
const POOLS := {
	"GravityBombPool": EnemyOrdnance.Kind.GRAVITY_BOMB,
	"MinePool": EnemyOrdnance.Kind.MINE,
	"PursuitBombPool": EnemyOrdnance.Kind.PURSUIT_BOMB,
}


func _spawn(harness, pos: Vector2) -> Bomber:
	var bomber := BOMBER_SCENE.instantiate() as Bomber
	(bomber.get_node("Brain") as BomberBrain).start_engaged = true  # pre-t19: predates the hub idle
	bomber.global_position = pos
	harness.root.add_child(bomber)
	bomber.set_physics_process(false)  # hand-ticked
	bomber.set_process(false)          # the rail clock is hand-stepped too
	return bomber


func _tick(bomber: Bomber, delta: float) -> void:
	var before := bomber.global_position
	bomber._physics_process(delta)
	bomber.global_position = before + bomber.velocity * delta


func _ordnance_in(root: Node) -> Array[EnemyOrdnance]:
	var found: Array[EnemyOrdnance] = []
	for child in root.get_children():
		if child is EnemyOrdnance:
			found.append(child)
	return found


# ── Structure ────────────────────────────────────────────────────────────────────────────────────

func test_the_three_pools_are_root_children_that_let_ordnance_outlive_the_bomber() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	for pool_name: String in POOLS:
		var pool := bomber.get_node_or_null(pool_name) as BulletPool
		assert_not_null(pool, "%s is a direct child of the root" % pool_name)
		if pool == null:
			continue
		assert_true(pool.persist_after_owner_death, "%s: persist_after_owner_death" % pool_name)
		assert_gte(pool.pool_size, EnemyOrdnanceScenes.pool_size_for(POOLS[pool_name], bomber.config),
			"%s: sized for the config's run cadence and mine life" % pool_name)
		assert_eq(pool.bullet_scene, EnemyOrdnanceScenes.scene_for(POOLS[pool_name]),
			"%s feeds the matching ordnance scene" % pool_name)


func test_the_body_is_one_rectangle_shared_by_the_hurtbox_and_the_contact_hitbox() -> void:
	var bomber := BOMBER_SCENE.instantiate() as Bomber
	(bomber.get_node("Brain") as BomberBrain).start_engaged = true  # pre-t19: predates the hub idle
	add_child_autofree(bomber)
	var body := bomber.get_node("CollisionShape2D") as CollisionShape2D
	var hurt := bomber.get_node("HurtBox/CollisionShape2D") as CollisionShape2D
	var contact := bomber.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D
	assert_true(body.shape is RectangleShape2D, "the body is a RectangleShape2D")
	assert_same(hurt.shape, body.shape, "the hurtbox shares the body's shape sub-resource")
	assert_same(contact.shape, body.shape, "the contact hitbox shares it too")
	assert_eq(hurt.scale, body.scale, "hurtbox scale matches the body")
	assert_eq(contact.scale, body.scale, "contact hitbox scale matches the body")
	var sprite := bomber.get_node("Sprite2D") as Sprite2D
	var wingspan: float = (body.shape as RectangleShape2D).size.x * absf(body.scale.x)
	assert_gte(wingspan, 0.85 * sprite.texture.get_width(),
		"the wings are shootable: the body is at least 0.85 x the sprite's width")


func test_the_legacy_timer_physics_loop_and_bomb_scene_are_gone() -> void:
	var bomber := BOMBER_SCENE.instantiate() as Bomber
	(bomber.get_node("Brain") as BomberBrain).start_engaged = true  # pre-t19: predates the hub idle
	add_child_autofree(bomber)
	for child in bomber.get_children():
		assert_false(child is Timer, "no Timer child (%s)" % child.name)
	# Read the source: `get_script_method_list()` also reports the inherited BaseEnemy tick.
	var source := FileAccess.get_file_as_string((bomber.get_script() as GDScript).resource_path)
	assert_false(source.contains("func _physics_process"), "bomber.gd leaves the physics tick to BaseEnemy")
	assert_false(FileAccess.file_exists("res://assault/scenes/enemies/bomber/bomb.tscn"), "bomb.tscn is deleted")
	assert_false(FileAccess.file_exists("res://assault/scenes/enemies/bomber/bomb.gd"), "bomb.gd is deleted")


func test_the_shipped_config_keeps_the_legacy_stats_and_a_wall_that_can_hurt_a_fast_player() -> void:
	assert_eq(SHIPPED.max_health, 150)
	assert_eq(SHIPPED.collision_damage, 35)
	assert_eq(SHIPPED.score_value, 80)
	# Review B1(a): a player crossing a mine at the top of the mine band must still be inside the blast
	# when the warning ends, or the wall is harmless at normal speeds.
	assert_gte((SHIPPED.trigger_radius + SHIPPED.mine_blast_radius) / SHIPPED.mine_warning,
		SHIPPED.mine_speed_max, "(trigger + blast) / mine_warning >= mine_speed_max")


func test_the_config_reaches_the_mover_the_brain_and_the_hitbox() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	var mover := bomber.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.max_speed, SHIPPED.max_speed)
	assert_eq(mover.acceleration, SHIPPED.acceleration)
	assert_eq(mover.max_turn_rate, SHIPPED.max_turn_rate)
	assert_eq((bomber.get_node("ContactHitBox") as HitBox).damage, SHIPPED.collision_damage)
	assert_same((bomber.get_node("Brain") as BomberBrain).config, bomber.config)
	assert_not_same(bomber.config, SHIPPED, "the bomber holds a private copy of the shipped config")


# ── The rail fallback ────────────────────────────────────────────────────────────────────────────

func test_a_rail_bomber_drops_a_gravity_bomb_straight_down_every_interval() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	bomber.suspend_ai()
	var drop_times: Array[float] = []
	var seen := 0
	var steps := int((SHIPPED.rail_bomb_interval * 3.0 + 0.3) / DT)
	for i in steps:
		bomber._process(DT)
		var now := _ordnance_in(harness.root).size()
		if now > seen:
			drop_times.append((i + 1) * DT)
			seen = now
	assert_eq(drop_times.size(), 3, "three bombs in three intervals and a bit")
	for n in drop_times.size():
		assert_almost_eq(drop_times[n], SHIPPED.rail_bomb_interval * (n + 1), DT * 2.0,
			"bomb %d drops on the interval" % n)
	var bomb := _ordnance_in(harness.root)[0]
	assert_eq(bomb.kind, EnemyOrdnance.Kind.GRAVITY_BOMB)
	assert_eq(bomb.heading(), Vector2.DOWN, "launched DOWN")
	var before := bomb.global_position
	bomb._physics_process(0.5)
	assert_almost_eq(bomb.global_position.distance_to(before), SHIPPED.rail_bomb_speed * 0.5, 0.01,
		"at rail_bomb_speed")
	assert_eq(bomb.blast_damage, SHIPPED.gravity_blast_damage, "its blast comes from the config")


func test_an_unsuspended_bomber_drops_nothing_from_the_rail_clock() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	for i in int(SHIPPED.rail_bomb_interval * 3.0 / DT):
		bomber._process(DT)
	assert_eq(_ordnance_in(harness.root).size(), 0, "the clock is a rail fallback only")


func test_a_bomb_in_flight_survives_its_bomber_dying() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	bomber.suspend_ai()
	for i in int((SHIPPED.rail_bomb_interval + 0.1) / DT):
		bomber._process(DT)
	var bombs := _ordnance_in(harness.root)
	assert_eq(bombs.size(), 1, "sanity: one bomb in flight")
	var bomb := bombs[0]
	bomber.health.decrease(bomber.health.current_health)
	await wait_frames(3)
	assert_true(is_instance_valid(bomber) == false or bomber.is_queued_for_deletion() or not bomber.is_inside_tree(),
		"sanity: the bomber is gone")
	assert_true(is_instance_valid(bomb), "the bomb is still alive")
	assert_true(bomb.is_inside_tree(), "and still in the level")
	assert_false(bomb.is_queued_for_deletion(), "and not queued for deletion")


# ── Assault: the budget and DISENGAGE ────────────────────────────────────────────────────────────

func test_assault_disengage_frees_the_bomber_only_outside_the_world_rect() -> void:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var bomber := _spawn(harness, Vector2(640.0, 60.0))
	bomber.config.engage_seconds = 0.2
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var freed_at := Vector2.INF
	for _i in 1500:
		_tick(bomber, DT)
		if bomber.is_queued_for_deletion():
			freed_at = bomber.global_position
			break
	assert_true(freed_at.is_finite(), "the budget disengages it")
	assert_false(rect.has_point(freed_at), "and it is freed only once outside the world rect")
	assert_eq((bomber.get_node("Brain") as BomberBrain).phase, BomberBrain.Phase.DISENGAGE)


func test_open_space_has_no_budget_so_the_bomber_stays() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var bomber := _spawn(harness, Vector2(640.0, 60.0))
	bomber.config.engage_seconds = 0.2
	var brain := bomber.get_node("Brain") as BomberBrain
	var disengaged := false
	for _i in 600:
		_tick(bomber, DT)
		disengaged = disengaged or brain.phase == BomberBrain.Phase.DISENGAGE
	assert_false(bomber.is_queued_for_deletion())
	assert_false(disengaged, "with no budget the bomber never disengages")


func test_approach_closes_on_the_player() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(900.0, 360.0)
	var bomber := _spawn(harness, Vector2(100.0, 100.0))
	var start := bomber.global_position.distance_to(harness.player.global_position)
	for _i in 60:
		_tick(bomber, DT)
	assert_lt(bomber.global_position.distance_to(harness.player.global_position), start,
		"APPROACH heads for a bombing line near the player")


# ══ t10: the bombing runs (task plan docs/plans/cmuyk2qpr0089oa2xlih7xvmg/3-plan.md, Revision 3) ═════════
#
# Hand-ticked: the bomber's `_physics_process`, then every ordnance's, then the player stub moves by its own
# velocity. The real-physics rows (the blast outcome and the attack-in-budget replay) are further down.

const MODES := ["open_space", "assault"]
const SEED := 4207
## The head-on set-up of rows (1)/(2) and the outcome row (task plan F1, N7): the player crosses left to right
## below the bomber, which waits ahead of it, nose down, so the wall's start comes toward it.
const HEAD_ON_PLAYER := Vector2(100.0, 700.0)
const HEAD_ON_BOMBER := Vector2(1150.0, 150.0)
const CRUISE := Vector2(220.0, 0.0)


func _world(mode: String):
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	return harness


func _brain(bomber: Bomber) -> BomberBrain:
	return bomber.get_node("Brain") as BomberBrain


## A seeded bomber with no choice jitter, hand-ticked.
func _run_bomber(harness, pos: Vector2) -> Bomber:
	var bomber := _spawn(harness, pos)
	bomber.config.choice_jitter = 0.0
	_brain(bomber).rng.seed = SEED
	return bomber


## One hand tick of the whole world: the bomber, its ordnance, then the player stub.
func _step(harness, bomber: Bomber) -> void:
	if is_instance_valid(bomber) and not bomber.is_queued_for_deletion():
		_tick(bomber, DT)
	for o in _ordnance_in(harness.root):
		o._physics_process(DT)
	harness.player.global_position += harness.player.velocity * DT


## Ticks until `brain.phase == p` (true) or `seconds` pass (false).
func _until_phase(harness, bomber: Bomber, p: int, seconds: float) -> bool:
	for _i in int(seconds / DT):
		_step(harness, bomber)
		if _brain(bomber).phase == p:
			return true
	return false


func _mines_in(root: Node) -> Array[EnemyOrdnance]:
	var out: Array[EnemyOrdnance] = []
	for o in _ordnance_in(root):
		if o.kind == EnemyOrdnance.Kind.MINE:
			out.append(o)
	return out


## Plays the head-on scenario to the end of the run plus `after` seconds and records what rows (1) and (2)
## measure: the line-centre trace over APPROACH, the frozen P-hat, each mine's arm time and the player there.
func _play_head_on(harness, speed: float = CRUISE.x, bomber_at: Vector2 = HEAD_ON_BOMBER) -> Dictionary:
	harness.player.global_position = HEAD_ON_PLAYER
	harness.player.velocity = Vector2(speed, 0.0)
	var bomber := _run_bomber(harness, bomber_at)
	var brain := _brain(bomber)
	var rec := {"centres": [], "entered": false, "approach_time": 0.0, "mines": []}
	var t := 0.0
	for _i in int(9.0 / DT):
		_step(harness, bomber)
		t += DT
		if brain.phase == BomberBrain.Phase.APPROACH:
			rec.centres.append([t, brain.line_centre()])
			continue
		if not rec.entered:
			rec.entered = true
			rec.approach_time = t
			rec.kind = brain.ordnance_kind
			rec.p_hat = brain.predicted_drop_point()
			rec.clamped = brain.wall_clamped()
			rec.heading_err = rad_to_deg(absf(bomber.velocity.angle_to(brain.line_dir)))
			rec.planned = brain.planned_rest_points.duplicate()
			rec.entry_player = harness.player.global_position
		for m in _mines_in(harness.root):
			var known := false
			for r in rec.mines:
				if r.node == m:
					known = true
					if not r.has("arm_player") and m.is_armed():
						r.arm_player = harness.player.global_position
						r.arm_t = t
			if not known:
				rec.mines.append({"node": m, "launch_t": t})
		if brain.phase != BomberBrain.Phase.RUN and t - rec.approach_time > 3.0:
			break
	for r in rec.mines:
		r.rest = (r.node as EnemyOrdnance).global_position
	return rec


## (1) Every mine comes to rest near the line through the frozen wall P-hat, perpendicular to the player's
## velocity, and on its own planned point.
func test_mine_rest_points_lie_on_the_wall_through_p_hat(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var rec := _play_head_on(harness)
	assert_true(rec.entered, "%s: the bomber reaches its RUN" % mode)
	if not rec.entered:
		return
	assert_eq(rec.kind, EnemyOrdnance.Kind.MINE, "%s: a cruising player gets a mine wall" % mode)
	assert_false(rec.clamped, "%s: the head-on wall is not clamped (set-up check, N7)" % mode)
	assert_gte(rec.mines.size(), SHIPPED.mines_per_run_min, "%s: a full pattern" % mode)
	assert_eq(rec.mines.size(), rec.planned.size(), "%s: every planned mine was dropped" % mode)
	for i in rec.mines.size():
		var rest: Vector2 = rec.mines[i].rest
		assert_lt(absf(rest.x - rec.p_hat.x), 40.0,
			"%s: mine %d rests %.1f px off the wall line x = %.1f" % [mode, i, rest.x - rec.p_hat.x, rec.p_hat.x])
		assert_lt(rest.distance_to(rec.planned[i]), 4.0, "%s: mine %d stops on its planned point" % [mode, i])


## (2) Against the LIVE player: the middle mine is still more than `trigger_radius` ahead when it arms (so the
## player enters its radius after arming — review B1c), and the player's straight path passes within
## `trigger_radius` of at least one armed mine.
func test_the_wall_is_armed_ahead_of_the_live_player(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var rec := _play_head_on(harness)
	assert_true(rec.entered, "%s: the bomber reaches its RUN" % mode)
	if rec.entered:
		assert_eq(rec.kind, EnemyOrdnance.Kind.MINE, "%s: a mine wall" % mode)
	assert_gt(rec.mines.size(), 0, "%s: mines were laid" % mode)
	if not rec.entered or rec.mines.is_empty():
		return
	var middle: Dictionary = rec.mines[0]
	for r in rec.mines:
		if absf(r.rest.y - HEAD_ON_PLAYER.y) < absf(middle.rest.y - HEAD_ON_PLAYER.y):
			middle = r
	assert_true(middle.has("arm_player"), "%s: the middle mine armed" % mode)
	if not middle.has("arm_player"):
		return
	var ahead: float = (middle.rest - middle.arm_player).dot(CRUISE.normalized())
	gut.p("%s: middle mine %.1f px ahead of the live player when it armed (trigger %.0f); approach %.2f s"
		% [mode, ahead, SHIPPED.trigger_radius, rec.approach_time])
	assert_gt(ahead, SHIPPED.trigger_radius, "%s: the player reaches the middle mine's radius after it arms" % mode)
	var hits := 0
	for r in rec.mines:
		if not r.has("arm_player"):
			continue
		# The closest the straight path comes to this mine from its arm time on.
		var along: float = maxf((r.rest - r.arm_player).dot(CRUISE.normalized()), 0.0)
		var closest: Vector2 = r.arm_player + CRUISE.normalized() * along
		if closest.distance_to(r.rest) < SHIPPED.trigger_radius:
			hits += 1
	assert_gt(hits, 0, "%s: the straight path crosses an armed mine's trigger radius" % mode)


## For a constant-velocity player the line does not move over the last second of APPROACH (R2-1: the lead-in is
## planned to where the wall will be on arrival).
func test_the_line_stands_still_for_a_constant_velocity_player(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var rec := _play_head_on(harness)
	assert_true(rec.entered, "%s: the bomber reaches its RUN" % mode)
	if not rec.entered:
		return
	assert_gte(rec.approach_time, 1.0, "%s: the APPROACH lasts at least 1 s, so the row is not vacuous" % mode)
	var last: Vector2 = rec.centres[rec.centres.size() - 1][1]
	var worst := 0.0
	for c in rec.centres:
		if rec.approach_time - float(c[0]) <= 1.0:
			worst = maxf(worst, (c[1] as Vector2).distance_to(last))
	gut.p("%s: line centre moved at most %.1f px over the last 1.0 s of a %.2f s approach" % [mode, worst, rec.approach_time])
	assert_lt(worst, 20.0, "%s: the line stands still across re-plans" % mode)


## The lead-in arrives on the line pointing along it.
func test_the_approach_arrives_within_15_degrees_of_the_line(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var rec := _play_head_on(harness)
	assert_true(rec.entered, "%s: the bomber reaches its RUN" % mode)
	if rec.entered:
		assert_lt(rec.heading_err, 15.0, "%s: heading %.1f deg off the line at RUN entry" % [mode, rec.heading_err])


## Plays a stationary-player run (or one with `player_v`) to the end of ESCAPE and records the RUN-entry snapshot,
## every ordnance launch and the ESCAPE ticks.
func _play_run(harness, player_at: Vector2, bomber_at: Vector2, player_v := Vector2.ZERO, seconds := 9.0) -> Dictionary:
	harness.player.global_position = player_at
	harness.player.velocity = player_v
	var bomber := _run_bomber(harness, bomber_at)
	var brain := _brain(bomber)
	var rec := {"bomber": bomber, "entered": false, "launches": [], "escape": [], "phases": [], "light_ok": true,
		"choice": -1}
	brain.phase_changed.connect(func(p: int) -> void: rec.phases.append(p))
	var light := bomber.get_node("StateLight") as StateLight
	var seen := {}
	for _i in int(seconds / DT):
		if not is_instance_valid(bomber) or bomber.is_queued_for_deletion():
			break
		var before := bomber.global_position
		var before_v := bomber.velocity
		var was := brain.phase
		_step(harness, bomber)
		if not is_instance_valid(bomber) or bomber.is_queued_for_deletion():
			break
		if rec.choice < 0:
			rec.choice = brain.ordnance_kind
		if (light.get_state() == StateLight.State.ARMED) != (brain.phase == BomberBrain.Phase.RUN):
			rec.light_ok = false
		if brain.phase == BomberBrain.Phase.RUN and not rec.entered:
			rec.entered = true
			rec.kind = brain.ordnance_kind
			rec.p_hat = brain.predicted_drop_point()
			rec.entry_pos = bomber.global_position
			rec.entry_player = harness.player.global_position
			rec.entry_v = harness.player.velocity
			rec.line_start = brain.line_start
			rec.line_dir = brain.line_dir
			rec.line_length = brain.line_length
		for o in _ordnance_in(harness.root):
			if not seen.has(o):
				seen[o] = true
				rec.launches.append({"kind": o.kind, "at": o.global_position, "heading": o.heading(),
					"player": harness.player.global_position})
		if was == BomberBrain.Phase.ESCAPE and brain.phase == BomberBrain.Phase.ESCAPE and before_v.length() > 1.0:
			rec.escape.append({
				"turn": absf(before_v.angle_to(bomber.velocity)),
				"d0": before.distance_to(harness.player.global_position - harness.player.velocity * DT),
				"d1": bomber.global_position.distance_to(harness.player.global_position)})
		if brain.phase == BomberBrain.Phase.REPOSITION or brain.phase == BomberBrain.Phase.DISENGAGE:
			if rec.phases.count(BomberBrain.Phase.APPROACH) > 0 or brain.phase == BomberBrain.Phase.DISENGAGE:
				pass
	return rec


## The nose-on close-range GRAVITY set-up: the player 300 px straight below the bomber.
const CLOSE_PLAYER := Vector2(640.0, 400.0)
const CLOSE_BOMBER := Vector2(640.0, 100.0)
## The far PURSUIT set-up: 800 px.
const FAR_PLAYER := Vector2(640.0, 560.0)
const FAR_BOMBER := Vector2(640.0, -240.0)


func test_the_choice_rule(mode: String = use_parameters(MODES)) -> void:
	var cases := [
		["220 px/s -> a mine wall", Vector2(400.0, 700.0), Vector2(220.0, 0.0), Vector2(900.0, 150.0), EnemyOrdnance.Kind.MINE],
		["stationary at 300 px -> a gravity bomb", CLOSE_PLAYER, Vector2.ZERO, CLOSE_BOMBER, EnemyOrdnance.Kind.GRAVITY_BOMB],
		["stationary at 800 px -> a pursuit bomb", FAR_PLAYER, Vector2.ZERO, FAR_BOMBER, EnemyOrdnance.Kind.PURSUIT_BOMB],
		# F3: inside gravity_range, so only the speed rule can give PURSUIT.
		["600 px/s inside gravity_range -> a pursuit bomb", CLOSE_PLAYER, Vector2(600.0, 0.0), CLOSE_BOMBER, EnemyOrdnance.Kind.PURSUIT_BOMB],
	]
	for c in cases:
		var harness = _world(mode)
		harness.player.global_position = c[1]
		harness.player.velocity = c[2]
		var bomber := _run_bomber(harness, c[3])
		_step(harness, bomber)
		assert_eq(_brain(bomber).ordnance_kind, c[4], "%s: %s" % [mode, c[0]])
		harness.root.get_parent().remove_child(harness.root)
		harness.root.free()


## A boosting player never gets a mine wall: the choice is PURSUIT and stays non-MINE through the approach.
func test_a_600_px_s_player_gets_a_pursuit_bomb_never_a_wall(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	harness.player.global_position = CLOSE_PLAYER
	harness.player.velocity = Vector2(600.0, 0.0)
	var bomber := _run_bomber(harness, CLOSE_BOMBER)
	assert_lt(CLOSE_PLAYER.distance_to(CLOSE_BOMBER), SHIPPED.gravity_range, "sanity: inside gravity_range")
	_step(harness, bomber)
	assert_eq(_brain(bomber).ordnance_kind, EnemyOrdnance.Kind.PURSUIT_BOMB, "%s: a pursuit bomb" % mode)
	var mines := 0
	for _i in int(2.0 / DT):
		_step(harness, bomber)
		mines += _mines_in(harness.root).size()
	assert_eq(mines, 0, "%s: no mine is ever laid for a boosting player" % mode)


func test_a_stationary_player_is_on_the_line(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var rec := _play_run(harness, CLOSE_PLAYER, CLOSE_BOMBER, Vector2.ZERO, 3.0)
	assert_true(rec.entered, "%s: the gravity run starts" % mode)
	if rec.entered:
		assert_eq(rec.kind, EnemyOrdnance.Kind.GRAVITY_BOMB)
		var off := absf((rec.line_dir as Vector2).cross(CLOSE_PLAYER - rec.line_start))
		assert_lt(off, 1.0, "%s: the gravity line passes through P (%.2f px off)" % [mode, off])
	harness.root.get_parent().remove_child(harness.root)
	harness.root.free()

	harness = _world(mode)
	rec = _play_run(harness, FAR_PLAYER, FAR_BOMBER, Vector2.ZERO, 4.0)
	assert_true(rec.entered, "%s: the pursuit run starts" % mode)
	if rec.entered:
		assert_eq(rec.kind, EnemyOrdnance.Kind.PURSUIT_BOMB)
		var end: Vector2 = rec.line_start + rec.line_dir * rec.line_length
		var rel := FAR_PLAYER - end
		assert_almost_eq(absf((rec.line_dir as Vector2).cross(rel)), SHIPPED.pursuit_launch_range, 1.0,
			"%s: P is pursuit_launch_range beside the pursuit line" % mode)
		assert_almost_eq(rel.dot(rec.line_dir), 0.0, 1.0, "%s: abeam the line's end" % mode)


## The gravity bomb's flight line passes within 30 px of the damped P-hat, computed here from the RUN-entry
## snapshot: a stationary player at 300 px, and a 100 px/s player moving along the bearing toward the bomber.
func test_the_gravity_bomb_flies_over_the_damped_aim_point(mode: String = use_parameters(MODES)) -> void:
	for v in [Vector2.ZERO, Vector2(0.0, -100.0)]:
		var harness = _world(mode)
		var rec := _play_run(harness, CLOSE_PLAYER, CLOSE_BOMBER, v, 3.0)
		assert_true(rec.entered, "%s v=%s: the run starts" % [mode, v])
		assert_eq(rec.launches.size(), 1, "%s v=%s: one bomb" % [mode, v])
		if rec.entered and rec.launches.size() == 1:
			assert_eq(rec.kind, EnemyOrdnance.Kind.GRAVITY_BOMB)
			var p: Vector2 = rec.entry_player
			var d: float = (rec.entry_pos as Vector2).distance_to(p)
			var ref: Vector2 = p + v * SHIPPED.lead_factor * minf(SHIPPED.horizon, d / SHIPPED.run_speed)
			var launch: Dictionary = rec.launches[0]
			var along: float = maxf((ref - launch.at).dot(launch.heading), 0.0)
			var miss: float = (launch.at + launch.heading * along).distance_to(ref)
			assert_lt(miss, 30.0, "%s v=%s: the bomb's ray passes %.1f px from the damped P-hat" % [mode, v, miss])
		harness.root.get_parent().remove_child(harness.root)
		harness.root.free()


func test_the_pursuit_bomb_is_launched_at_p_hat(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var rec := _play_run(harness, FAR_PLAYER, FAR_BOMBER, Vector2.ZERO, 4.0)
	assert_eq(rec.launches.size(), 1, "%s: one pursuit bomb" % mode)
	if rec.launches.size() == 1:
		var launch: Dictionary = rec.launches[0]
		assert_eq(launch.kind, EnemyOrdnance.Kind.PURSUIT_BOMB)
		var err := rad_to_deg(absf((launch.heading as Vector2).angle_to(FAR_PLAYER - launch.at)))
		assert_lt(err, 10.0, "%s: launched %.1f deg off P-hat" % [mode, err])


## ESCAPE turns at no more than its rate and opens the distance on every tick, after a GRAVITY run (which overflies
## the player) and after a PURSUIT run (which passes beside it, F2).
func test_escape_turns_at_its_rate_and_opens_distance(mode: String = use_parameters(MODES)) -> void:
	for setup in [[CLOSE_PLAYER, CLOSE_BOMBER, "gravity"], [FAR_PLAYER, FAR_BOMBER, "pursuit"]]:
		var harness = _world(mode)
		var rec := _play_run(harness, setup[0], setup[1], Vector2.ZERO, 7.0)
		assert_gt(rec.escape.size(), int(SHIPPED.escape_time / DT) - 3, "%s %s: a full ESCAPE" % [mode, setup[2]])
		var worst_turn := 0.0
		var shrinks := 0
		for e in rec.escape:
			worst_turn = maxf(worst_turn, e.turn)
			if e.d1 <= e.d0:
				shrinks += 1
		assert_lte(worst_turn, SHIPPED.escape_turn_rate * DT + 1e-4,
			"%s %s: turns at most escape_turn_rate (%.4f rad/tick)" % [mode, setup[2], worst_turn])
		assert_eq(shrinks, 0, "%s %s: the distance to the player grows on every ESCAPE tick" % [mode, setup[2]])
		harness.root.get_parent().remove_child(harness.root)
		harness.root.free()


## Open Space keeps attacking: APPROACH -> RUN -> ESCAPE -> REPOSITION -> APPROACH. Assault flies one run per life:
## RUN -> ESCAPE -> DISENGAGE. The red light is on exactly while the run lasts.
func test_the_phase_loop_and_the_armed_light(mode: String = use_parameters(MODES)) -> void:
	var harness = _world(mode)
	var rec := _play_run(harness, FAR_PLAYER, FAR_BOMBER, Vector2.ZERO, 9.0)
	var expected := [BomberBrain.Phase.RUN, BomberBrain.Phase.ESCAPE]
	if mode == "open_space":
		expected += [BomberBrain.Phase.REPOSITION, BomberBrain.Phase.APPROACH]
	else:
		expected += [BomberBrain.Phase.DISENGAGE]
	assert_eq(rec.phases.slice(0, expected.size()), expected, "%s: the phase sequence" % mode)
	assert_true(rec.light_ok, "%s: StateLight is ARMED exactly in RUN" % mode)


## Budget expiry mid-RUN: the run finishes — every planned mine is dropped — and RUN goes straight to DISENGAGE.
func test_assault_budget_expiry_mid_run_finishes_the_run() -> void:
	var harness = _world("assault")
	harness.player.global_position = HEAD_ON_PLAYER
	harness.player.velocity = CRUISE
	var bomber := _run_bomber(harness, HEAD_ON_BOMBER)
	var brain := _brain(bomber)
	var phases: Array[int] = []
	brain.phase_changed.connect(func(p: int) -> void: phases.append(p))
	var expired_in_run := false
	var planned := 0
	for _i in int(9.0 / DT):
		if not is_instance_valid(bomber) or bomber.is_queued_for_deletion():
			break
		_step(harness, bomber)
		if brain.phase == BomberBrain.Phase.RUN and not expired_in_run:
			expired_in_run = true
			planned = brain.planned_rest_points.size()
			# Expire 0.3 s into the run: before any mine has been released.
			brain.budget.seconds = brain.budget.seconds - brain.budget.remaining() + 0.3
		if brain.phase == BomberBrain.Phase.DISENGAGE:
			break
	assert_true(expired_in_run, "sanity: the run started")
	assert_gt(planned, 0, "sanity: a mine wall was planned")
	assert_eq(_mines_in(harness.root).size(), planned, "every planned mine was dropped before leaving")
	assert_eq(phases.slice(-2), [BomberBrain.Phase.RUN, BomberBrain.Phase.DISENGAGE], "RUN -> DISENGAGE, never ESCAPE")


## R4.6: a wall laid for a player at the corridor's edge stays inside `inner_rect().grow(-drop_margin)`.
func test_assault_edge_keeps_every_rest_point_inside_the_corridor() -> void:
	var harness = _world("assault")
	harness.player.global_position = Vector2(1320.0, 500.0)
	harness.player.velocity = CRUISE
	var bomber := _run_bomber(harness, Vector2(1000.0, -300.0))
	var brain := _brain(bomber)
	var rect := (bomber.get_node("EnemyMover") as EnemyMover).constraint.inner_rect().grow(-SHIPPED.drop_margin)
	var planned: Array[Vector2] = []
	var t_run := -1.0
	var t := 0.0
	for _i in int(9.0 / DT):
		_step(harness, bomber)
		t += DT
		if brain.phase == BomberBrain.Phase.RUN and planned.is_empty():
			planned = brain.planned_rest_points.duplicate()
			assert_true(brain.wall_clamped(), "sanity: the wall was clamped")
		if not planned.is_empty() and brain.phase != BomberBrain.Phase.RUN:
			t_run = t
		if t_run > 0.0 and t - t_run > 0.6:
			break
	assert_gt(planned.size(), 0, "the bomber laid a wall")
	var tolerance := Rect2(rect.position - Vector2.ONE * 0.01, rect.size + Vector2.ONE * 0.02)
	for p in planned:
		assert_true(tolerance.has_point(p), "planned rest point %s inside %s" % [p, rect])
	for m in _mines_in(harness.root):
		assert_true(rect.grow(4.0).has_point(m.global_position), "mine at rest %s inside %s" % [m.global_position, rect])


func test_a_gravity_bomb_released_at_the_lead_can_hurt_a_stationary_player() -> void:
	# Task plan R2-2: released further out than the trigger radius plus its arming run, the bomb arms outside the
	# radius, so it triggers at the radius edge and goes off at most `speed * fuse - trigger_radius` past.
	assert_gte(SHIPPED.gravity_release_lead,
		SHIPPED.trigger_radius + SHIPPED.gravity_bomb_speed * SHIPPED.gravity_bomb_arm_delay,
		"gravity_release_lead >= trigger_radius + gravity_bomb_speed * gravity_bomb_arm_delay")
	assert_lte(SHIPPED.gravity_bomb_speed * SHIPPED.gravity_bomb_fuse - SHIPPED.trigger_radius,
		SHIPPED.gravity_blast_radius, "and then it goes off within its blast of a stationary player")


# ── Real physics: the blast outcome (review B1d) and attack-in-budget (§2.9.4) ───────────────────────────
#
# These rows step the engine (`await physics_frame`); game time is summed physics delta. The player stub
# moves itself on each frame. Its HurtBox is the mode's own player hurtbox circle (R2-4): 13.5 px for the
# Assault fighter, 5 px for the Open Space ship.
#
# They run sped up `_SPEEDUP`x with the physics step kept at 1/60 game-second, the pattern
# test_level1_fighter_fire_density.gd established: `Engine.time_scale`, `physics_ticks_per_second` and
# `max_physics_steps_per_frame` are scaled together, and the originals are restored at the end of each row AND
# in `after_each`. At 1x these rows cost about a minute of wall clock, which the verification gate cannot spare.

const PLAYER_HURT_RADIUS := {"open_space": 5.0, "assault": 13.5}
const _SPEEDUP := 8

var _blasts: int = 0
var _phase_log: Array[int] = []
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func after_each() -> void:
	_restore_clock()


func _scale_clock() -> void:
	if _clock_scaled:
		return
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	_clock_scaled = true
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP


func _restore_clock() -> void:
	if not _clock_scaled:
		return
	_clock_scaled = false
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


func _give_hurtbox(player: CharacterBody2D, radius: float) -> void:
	player.collision_layer = 0
	player.collision_mask = 0
	var hurt := Area2D.new()
	hurt.name = "HurtBox"
	hurt.collision_layer = CollisionLayers.PLAYER_HURTBOX
	hurt.collision_mask = 1281  # the player's real hurtbox mask
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	hurt.add_child(shape)
	player.add_child(hurt)
	# Only the ordnance's ContactBlast counts: the bomber's own contact box is layer 256 too (F7).
	hurt.area_entered.connect(func(area: Area2D) -> void:
		if area is ContactBlast:
			_blasts += 1)


## The head-on wall in real time. `turn` turns the stub 90 degrees (up, away from the wall's end) at RUN entry.
## Returns {kind, entered, blasts, clamped}; the window ends 2.5 s after the last mine armed.
func _physics_wall(mode: String, speed: float, bomber_at: Vector2, turn: bool) -> Dictionary:
	_blasts = 0
	var harness = _world(mode)
	harness.player.global_position = HEAD_ON_PLAYER
	harness.player.velocity = Vector2(speed, 0.0)
	_give_hurtbox(harness.player, PLAYER_HURT_RADIUS[mode])
	var bomber := BOMBER_SCENE.instantiate() as Bomber
	(bomber.get_node("Brain") as BomberBrain).start_engaged = true  # pre-t19: predates the hub idle
	bomber.global_position = bomber_at
	harness.root.add_child(bomber)
	bomber.config.choice_jitter = 0.0
	var brain := _brain(bomber)
	brain.rng.seed = SEED
	var out := {"kind": -1, "entered": false, "blasts": 0, "clamped": false}
	var t := 0.0
	var last_launch := -1.0
	var seen := 0
	_scale_clock()
	while t < 12.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		harness.player.global_position += harness.player.velocity * dt
		if not out.entered and is_instance_valid(bomber) and brain.phase == BomberBrain.Phase.RUN:
			out.entered = true
			out.kind = brain.ordnance_kind
			out.clamped = brain.wall_clamped()
			if turn:
				harness.player.velocity = Vector2(0.0, -speed)
		var mines := _mines_in(harness.root).size()
		if mines > seen:
			seen = mines
			last_launch = t
		if out.entered and last_launch > 0.0 and is_instance_valid(bomber) \
				and brain.phase != BomberBrain.Phase.RUN and t > last_launch + SHIPPED.mine_arm_delay + 2.5:
			break
	_restore_clock()
	out.blasts = _blasts
	# TargetInfo.player() reads the first player in the tree: drop this world before the next one is built.
	harness.root.get_parent().remove_child(harness.root)
	harness.root.free()
	return out


## A player holding course into the wall takes a blast; the same player turning away at RUN entry takes none.
func test_a_wall_hits_a_player_who_holds_course_and_misses_one_who_turns(mode: String = use_parameters(MODES)) -> void:
	var straight: Dictionary = await _physics_wall(mode, CRUISE.x, HEAD_ON_BOMBER, false)
	assert_true(straight.entered, "%s: the run started" % mode)
	assert_eq(straight.kind, EnemyOrdnance.Kind.MINE, "%s: a mine wall" % mode)
	assert_false(straight.clamped, "%s: an unclamped wall (set-up check, N7)" % mode)
	assert_gt(straight.blasts, 0, "%s: holding course at 220 px/s into the wall is punished" % mode)
	var turned: Dictionary = await _physics_wall(mode, CRUISE.x, HEAD_ON_BOMBER, true)
	assert_true(turned.entered, "%s: the run started" % mode)
	assert_eq(turned.blasts, 0, "%s: a 90 degree turn at RUN entry escapes it" % mode)
	gut.p("%s: blasts straight %d, turned %d" % [mode, straight.blasts, turned.blasts])


## At `mine_speed_max` (Open Space only: the Assault fighter tops out at 400 px/s, and a 440 px/s wall's lead cannot
## sit unclamped in the corridor — the clamp side is the edge row's job, N7). Review N-a: the bomber waits where
## the wall's start will be.
func test_a_wall_hits_a_player_at_mine_speed_max() -> void:
	var r: Dictionary = await _physics_wall("open_space", SHIPPED.mine_speed_max, Vector2(1820.0, 150.0), false)
	assert_true(r.entered, "the run started")
	assert_eq(r.kind, EnemyOrdnance.Kind.MINE, "a mine wall at mine_speed_max")
	assert_gt(r.blasts, 0, "holding course at %.0f px/s into the wall is punished" % SHIPPED.mine_speed_max)


## §2.9.4: a level-1 bomber, spawned through a real WaveManager at its own design position (0, -400) under a real
## ArenaCamera, starts its run before its engagement budget expires: stub at the camera centre and 200 px past
## it, stationary and moving sideways at 220 px/s (not clamped: it keeps going).
func test_a_level_1_bomber_attacks_inside_its_budget(
		params = use_parameters([[0.0, 0.0], [200.0, 0.0], [0.0, 220.0], [200.0, 220.0]])) -> void:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	var cam := harness.root.get_node("ArenaCamera") as Camera2D
	harness.player.global_position = cam.global_position + Vector2(0.0, params[0])
	harness.player.velocity = Vector2(params[1], 0.0)
	harness.player.collision_layer = 0
	harness.player.collision_mask = 0
	var container := Node2D.new()
	harness.root.add_child(container)
	var wm := WaveManager.new()
	wm.enemy_container = container
	harness.root.add_child(wm)
	_phase_log = []
	var spawned: Array = []
	container.child_entered_tree.connect(func(n: Node) -> void:
		if n is Bomber:
			spawned.append(n)
			(n.get_node("Brain") as BomberBrain).rng_seed = SEED
			(n.get_node("Brain") as BomberBrain).phase_changed.connect(func(p: int) -> void: _phase_log.append(p)))
	var b := WaveBuilder.new()
	wm.load_section([b.wave(0.0, [b.bomber().at(0.0, -400.0)])] as Array[WaveResource])
	var t := 0.0
	var spawn_t := -1.0
	var run_t := -1.0
	var left := false
	_scale_clock()
	while t < SHIPPED.engage_seconds + 8.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		harness.player.global_position += harness.player.velocity * dt
		if spawn_t < 0.0 and not spawned.is_empty():
			spawn_t = t
		if spawn_t >= 0.0 and run_t < 0.0 and _phase_log.has(BomberBrain.Phase.RUN):
			run_t = t - spawn_t
		if spawn_t >= 0.0 and not is_instance_valid(spawned[0]):
			left = true
			break
	_restore_clock()
	assert_gt(spawn_t, -1.0, "sanity: the bomber spawned")
	assert_gt(run_t, 0.0, "the bomber started a run")
	assert_lt(run_t, SHIPPED.engage_seconds, "RUN entered before the %.1f s budget expires" % SHIPPED.engage_seconds)
	gut.p("bomber from (0, -400), stub +%.0f px moving %.0f px/s: RUN after %.2f s of %.1f; runs per life %d; left: %s"
		% [params[0], params[1], run_t, SHIPPED.engage_seconds, _phase_log.count(BomberBrain.Phase.RUN), left])


# ══ t19: hub idle (epic §2.10; task cmuyk2qqh0099oa2xbltzoust) ═══════════════════════════════════════════════════
#
# Cold-start helpers: unlike `_spawn()` (which sets `start_engaged = true`, so every case above keeps assuming
# combat-from-spawn as before this task), these leave the brain to decide for itself - Open Space starts IDLE,
# Assault starts in combat. The stub player is stationary unless a case moves it.

const FAR_AWAY := Vector2(100000.0, 100000.0)
const BP := BomberBrain.Phase


func _cold_bomber(harness, pos: Vector2, player_pos: Vector2, anchor: Vector2 = Vector2.INF) -> Bomber:
	harness.player.global_position = player_pos
	harness.player.velocity = Vector2.ZERO
	var bomber := BOMBER_SCENE.instantiate() as Bomber
	bomber.config.choice_jitter = 0.0
	var brain := bomber.get_node("Brain") as BomberBrain
	brain.rng_seed = SEED
	brain.patrol_anchor = anchor
	bomber.global_position = pos
	harness.root.add_child(bomber)
	bomber.set_physics_process(false)
	bomber.set_process(false)
	return bomber


func _b_calm(p: int) -> bool:
	return p == BP.IDLE or p == BP.NOTICING or p == BP.RETURNING


func test_the_idle_phases_are_appended_so_the_earlier_values_do_not_move() -> void:
	assert_eq(BP.APPROACH, 0)
	assert_eq(BP.DISENGAGE, 4)
	assert_eq(BP.IDLE, 5)
	assert_eq(BP.NOTICING, 6)
	assert_eq(BP.RETURNING, 7)


## §2.10: lose_radius >= max(standoff + escape_speed * escape_time, mine_horizon * mine_speed_max + run_length / 2)
## + 100, read from fields.
func test_the_idle_radii_clear_the_largest_distance_the_bombing_cycle_opens() -> void:
	var c: BomberConfig = SHIPPED
	var opened := maxf(c.standoff + c.escape_speed * c.escape_time, c.mine_horizon * c.mine_speed_max + c.run_length * 0.5)
	assert_gte(c.lose_radius, opened + 100.0, "lose_radius %.0f vs the distance the cycle opens %.0f + 100" % [c.lose_radius, opened])
	assert_gt(c.lose_radius, c.perceive_radius, "AnchorIdle's hysteresis margin")
	assert_eq(c.perceive_radius, 650.0)
	assert_eq(c.lose_radius, 1700.0)


func test_open_space_cold_start_begins_idle_and_assault_starts_in_combat() -> void:
	var h = _world("open_space")
	var bomber := _cold_bomber(h, Vector2(321.0, -654.0), FAR_AWAY)
	_tick(bomber, DT)
	assert_eq(_brain(bomber).phase, BP.IDLE, "Open Space starts on patrol")
	assert_not_null(_brain(bomber).anchor_idle)
	assert_eq(_brain(bomber).patrol_anchor, Vector2(321.0, -654.0), "an unset anchor defaults to the spawn position")
	var a = _world("assault")
	var bomber2 := _cold_bomber(a, Vector2(640.0, -100.0), Vector2(640.0, 560.0))
	_tick(bomber2, DT)
	assert_eq(_brain(bomber2).phase, BP.APPROACH, "Assault always starts in combat")
	assert_null(_brain(bomber2).anchor_idle, "no AnchorIdle is built in Assault")


func test_idle_never_drops_anything_and_stays_on_its_ring() -> void:
	var h = _world("open_space")
	var anchor := Vector2(500.0, -400.0)
	var bomber := _cold_bomber(h, anchor + Vector2(20.0, 0.0), anchor + Vector2(SHIPPED.perceive_radius + SHIPPED.idle_radius + 80.0, 0.0), anchor)
	var worst := 0.0
	for _i in int(20.0 / DT):
		_step(h, bomber)
		assert_eq(_brain(bomber).phase, BP.IDLE)
		if _i > int(5.0 / DT):  # the first seconds are the bomber's slow turn onto the ring
			worst = maxf(worst, bomber.global_position.distance_to(anchor))
	assert_lte(worst, SHIPPED.idle_radius + 30.0, "worst %.1f px from the anchor once settled" % worst)
	assert_eq(_ordnance_in(h.root).size(), 0, "nothing was dropped")


func test_perceiving_the_player_notices_for_a_beat_then_approaches() -> void:
	var h = _world("open_space")
	var bomber := _cold_bomber(h, Vector2(640.0, 0.0), Vector2(640.0, SHIPPED.perceive_radius - 100.0))
	var seen: Array[int] = []
	for _i in int(1.0 / DT):
		_step(h, bomber)
		if seen.is_empty() or seen[-1] != _brain(bomber).phase:
			seen.append(_brain(bomber).phase)
	assert_eq(seen[0], BP.NOTICING, "NOTICING for a beat first")
	assert_eq(seen[1], BP.APPROACH, "then the fight starts (phases %s)" % [seen])
	assert_eq(_ordnance_in(h.root).size(), 0, "nothing dropped yet")


func test_beyond_lose_radius_it_goes_home_and_can_fight_again() -> void:
	var h = _world("open_space")
	var anchor := Vector2.ZERO
	var bomber := _cold_bomber(h, anchor + Vector2(100.0, 0.0), Vector2(500.0, 0.0), anchor)
	for _i in int(2.0 / DT):
		_step(h, bomber)
		if not _b_calm(_brain(bomber).phase):
			break
	assert_eq(_brain(bomber).phase, BP.APPROACH, "it reached combat")
	bomber.global_position += Vector2(0.0, 700.0)  # well away from home, so there is a way back to walk
	h.player.global_position = FAR_AWAY
	var saw_returning := false
	var home := false
	for _i in int(60.0 / DT):
		_step(h, bomber)
		saw_returning = saw_returning or _brain(bomber).phase == BP.RETURNING
		if _brain(bomber).phase == BP.IDLE:
			home = true
			break
	assert_true(saw_returning, "it passes through RETURNING on the way home")
	assert_true(home, "and reaches IDLE")
	h.player.global_position = bomber.global_position + Vector2(SHIPPED.perceive_radius - 50.0, 0.0)
	for _i in int(1.0 / DT):
		_step(h, bomber)
	assert_false(_b_calm(_brain(bomber).phase), "and fights again")


## RETURNING never interrupts a RUN: the player vanishes (beyond lose_radius) during the run, and the run still
## finishes - ESCAPE follows it, never RETURNING.
func test_returning_never_interrupts_a_run() -> void:
	var h = _world("open_space")
	var bomber := _cold_bomber(h, Vector2(640.0, 100.0), Vector2(640.0, 560.0))
	assert_true(_until_phase(h, bomber, BP.RUN, 12.0), "it reaches its run")
	h.player.global_position = FAR_AWAY
	var seen: Array[int] = [BP.RUN]
	for _i in int(8.0 / DT):
		_step(h, bomber)
		if seen[-1] != _brain(bomber).phase:
			seen.append(_brain(bomber).phase)
		if _b_calm(_brain(bomber).phase):
			break
	assert_eq(seen[1], BP.ESCAPE, "the run is followed by its escape (phases %s)" % [seen])
	assert_eq(seen[-1], BP.RETURNING, "and then it goes home (phases %s)" % [seen])


## A hub bomber's whole cycle - APPROACH -> RUN -> ESCAPE -> REPOSITION - against a stationary player never reads as
## losing it: it stays in combat on every tick, and never opens more than lose_radius.
func test_a_hub_bomber_stays_in_combat_through_a_full_cycle() -> void:
	var h = _world("open_space")
	var bomber := _cold_bomber(h, Vector2(640.0, 100.0), Vector2(640.0, 560.0))
	var visited := {}
	var in_combat := false
	var worst := 0.0
	var runs := 0
	for _i in int(60.0 / DT):
		_step(h, bomber)
		var p: int = _brain(bomber).phase
		if p == BP.APPROACH:
			in_combat = true
		if in_combat:
			assert_false(_b_calm(p), "combat tick %d is phase %s" % [_i, p])
			worst = maxf(worst, bomber.global_position.distance_to(h.player.global_position))
		if not visited.has(p):
			visited[p] = true
		runs = _brain(bomber).runs_started
		if runs >= 2 and p == BP.APPROACH:
			break
	assert_gte(runs, 2, "two full cycles ran")
	for p in [BP.APPROACH, BP.RUN, BP.ESCAPE, BP.REPOSITION]:
		assert_true(visited.has(p), "phase %s was visited" % p)
	assert_lt(worst, SHIPPED.lose_radius, "the cycle opened %.0f px against lose_radius %.0f" % [worst, SHIPPED.lose_radius])
