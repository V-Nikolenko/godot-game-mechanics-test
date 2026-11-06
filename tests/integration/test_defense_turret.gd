## The Stationary Defense Turret, its `TurretMount` cycle with the burst cannon, and `AssaultDrift` (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md
## §2.7; task plan docs/plans/cmvqw0vnb017rqs2xsyursu5d/3-plan.md, whose row numbers these tests follow). INTENT tests, not characterization.
##
## Rows run in both harnesses (`tests/helpers/enemy_ai_harness.gd`) unless the name says otherwise. They are hand-ticked: the turret's and its
## drift's `_physics_process` are off and each tick is `turret._physics_process(DT)` - the real brain -> mount path. Hand-ticked rows run outside
## the physics step, so the brain never casts its line-of-sight ray; the one row with a blocker (row 15) runs on real physics at the 8x clock.
## Every tuning number is read from the burst-cannon mount scene (`TurretMountScenes.export_of`, with the script default as the fallback) or the
## shipped `.tres`.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const TURRET_SCENE: PackedScene = preload("res://assault/scenes/enemies/defense_turret/defense_turret.tscn")
const SHIPPED: DefenseTurretConfig = preload("res://assault/scenes/enemies/defense_turret/defense_turret_config.tres")  # read only
const BURST_SCRIPT: Script = preload("res://assault/scenes/enemies/defense_turret/mounts/burst_cannon_mount.gd")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const FIXTURE_MOUNT: GDScript = preload("res://tests/helpers/fixture_turret_mount.gd")
const WRECK_MEDIUM: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_medium.tscn")
const MOUNT_SCRIPT: Script = preload("res://assault/scenes/enemies/defense_turret/mounts/turret_mount.gd")
const BEAM_SCRIPT: Script = preload("res://assault/scenes/projectiles/enemy_beams/enemy_beam.gd")
const LASER_MODE: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/mining_laser.tres")

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
## The turret's spot: inside the Assault view (0..1280 x 0..720) with room below for the player.
const T := Vector2(640.0, 300.0)
const BELOW := Vector2(0.0, 300.0)
const _SPEEDUP: int = 8

var _clock_scaled: bool = false
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8


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


## A burst-cannon export as the mount scene authors it.
func _x(property: StringName) -> Variant:
	return TurretMountScenes.export_of(TurretMount.Variant.BURST_CANNON, property, BURST_SCRIPT.get_property_default_value(property))


func _world(mode: String):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	return h


## A hand-ticked turret at `pos` (its own and its drift's physics ticks off). `prepare` runs before `add_child` (a slot override, a group).
func _turret(h, pos: Vector2 = T, engaged: bool = false, seed_value: int = 4242, prepare: Callable = Callable()) -> DefenseTurret:
	var t := TURRET_SCENE.instantiate() as DefenseTurret
	var brain := t.get_node("Brain") as DefenseTurretBrain
	brain.start_engaged = engaged
	brain.rng_seed = seed_value
	t.position = pos
	if prepare.is_valid():
		prepare.call(t)
	h.root.add_child(t)
	t.set_physics_process(false)
	(t.get_node("AssaultDrift") as AssaultDrift).set_physics_process(false)
	return t


func _mount(t: DefenseTurret) -> BurstCannonMount:
	return t.mounts()[0] as BurstCannonMount


func _brain(t: DefenseTurret) -> DefenseTurretBrain:
	return t.get_node("Brain") as DefenseTurretBrain


func _light(t: DefenseTurret) -> StateLight:
	return t.get_node("StateLight") as StateLight


## Records every `round_fired` as {t, round, err, dir, facing}; `clock` is the caller's one-element time cell.
func _record(mount: TurretMount, clock: Array, into: Array) -> void:
	mount.round_fired.connect(func(projectile: Node2D) -> void:
		into.append({
			"t": clock[0],
			"round": projectile,
			"err": mount.aim_error(),
			"dir": (projectile as EnemyBullet)._direction,
			"facing": Vector2.RIGHT.rotated(mount.global_rotation),
		}))


## Ticks `t` until `done` answers true or `max_ticks` pass; advances `clock[0]` by DT before each tick. Returns whether `done` was met.
func _run_until(t: DefenseTurret, clock: Array, max_ticks: int, done: Callable) -> bool:
	for i in max_ticks:
		clock[0] += DT
		t._physics_process(DT)
		if done.call():
			return true
	return false


# ── 1. Static shell, rotation and turn rate ─────────────────────────────────────────────────────────────────────────

func test_the_root_stays_still_and_only_the_mount_turns_at_its_turn_rate(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T - BELOW  # opposite the 90 degree rest bearing
	var t := _turret(h, T, true)
	var m := _mount(t)
	var turn_rate: float = _x(&"turn_rate")
	var slots := t.get_node("MountSlots") as Node2D
	var slot := t.get_node("MountSlots/Slot0") as Node2D
	var slots_xf := slots.transform
	var slot_xf := slot.transform
	var start := t.global_position

	var worst_step := 0.0
	var root_turned := false
	var prev := m.rotation
	var aligned_at := -1.0
	for i in 100:
		t._physics_process(DT)
		worst_step = maxf(worst_step, absf(angle_difference(prev, m.rotation)))
		prev = m.rotation
		root_turned = root_turned or t.rotation != 0.0
		if aligned_at < 0.0 and m.aim_error() < deg_to_rad(1.0):
			aligned_at = (i + 1) * DT
	assert_gt(aligned_at, 0.0, "%s: the mount comes round to the player" % mode)
	assert_lte(aligned_at, PI / turn_rate + 2.0 * DT, "%s: a half turn takes at most pi / turn_rate (%.3f s)" % [mode, aligned_at])

	# The player circles the turret once in 3 s.
	for i in 180:
		h.player.global_position = T + Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 180.0) * 300.0
		t._physics_process(DT)
		worst_step = maxf(worst_step, absf(angle_difference(prev, m.rotation)))
		prev = m.rotation
		root_turned = root_turned or t.rotation != 0.0
	assert_lte(worst_step, turn_rate * DT + 1e-4, "%s: never faster than turn_rate" % mode)
	assert_false(root_turned, "%s: the root's rotation stays exactly 0" % mode)
	assert_eq(t.global_position, start, "%s: the root never moves itself" % mode)
	assert_eq(slots.transform, slots_xf, "%s: MountSlots untouched" % mode)
	assert_eq(slot.transform, slot_xf, "%s: the slot untouched: the mount is the only thing that turned" % mode)

	assert_null(t._mover, "no EnemyMover")
	assert_false(t.is_ai_driven(), "never AI-driven")
	assert_false(t.accept_tow(Vector2(50.0, 0.0)), "refuses a tow")
	assert_false(t.is_laser_blocking(), "the mining beam treats it as a target")
	assert_true(t.is_in_group("enemies"))
	assert_eq(t.contact_profile.mode, ContactProfile.Mode.NONE, "harmless on contact")
	assert_null(t.get_node_or_null("ContactHitBox"), "and has no ContactHitBox")


# ── 2. Partial lead ─────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_burst_cannon_leads_a_crossing_target_by_lead_blend(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + Vector2(-250.0, 300.0)
	h.player.velocity = Vector2(200.0, 0.0)
	var t := _turret(h, T, true)
	var m := _mount(t)
	for i in 30:
		h.player.global_position += h.player.velocity * DT
		t._physics_process(DT)
	var info := TargetInfo.of(h.player)
	var hit := info.intercept(m.muzzle_position(), float(_x(&"round_speed")))
	assert_true(hit["ok"], "sanity: the round can catch the stub")
	var full: Vector2 = hit["point"]
	var expected := info.position.lerp(full, float(_x(&"lead_blend")))
	assert_lt(m.aim_point().distance_to(expected), 2.0, "%s: aim point is lead_blend of the way to the intercept" % mode)
	assert_gt(m.aim_point().distance_to(info.position), 20.0, "%s: not the plain position (no lead)" % mode)
	assert_gt(m.aim_point().distance_to(full), 20.0, "%s: not the full intercept" % mode)


# ── 3. No round outside the cone ────────────────────────────────────────────────────────────────────────────────────

func test_no_round_leaves_outside_the_fire_cone(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + BELOW
	var t := _turret(h, T, true)
	var m := _mount(t)
	var half_cone := deg_to_rad(float(_x(&"fire_cone_deg"))) * 0.5
	var jump := 1.6 * float(_x(&"turn_rate")) * float(_x(&"burst_gap"))
	var clock := [0.0]
	var fired: Array = []
	_record(m, clock, fired)
	var state := {"jumped": false, "held": 0, "index": 0}
	m.round_fired.connect(func(_p: Node2D) -> void:
		if state["jumped"]:
			return
		state["jumped"] = true
		state["held"] = m.shots_held
		state["index"] = fired.size()
		h.player.global_position = T + (h.player.global_position - T).rotated(jump))
	var ended := _run_until(t, clock, 180, func() -> bool:
		return state["jumped"] and m.phase() == TurretMount.Phase.COOLDOWN)
	assert_true(ended, "%s: the first burst ran to its end" % mode)
	for f in fired:
		assert_lte(f["err"] as float, half_cone + 1e-4, "%s: fired inside the cone (pivot error %.4f rad)" % [mode, f["err"]])
		assert_lt(absf((f["dir"] as Vector2).angle_to(f["facing"] as Vector2)), 1e-4, "%s: the round leaves along the mount's facing" % mode)
	assert_gt(m.shots_held, int(state["held"]), "%s: a due shot fell outside the cone and was held, not fired wide" % mode)
	assert_gte(fired.size() - int(state["index"]), 1, "%s: a later shot of the same burst left once back inside the cone" % mode)


# ── 4. Burst cadence ────────────────────────────────────────────────────────────────────────────────────────────────

func test_bursts_follow_the_mount_exports(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + BELOW
	var t := _turret(h, T, true)
	var m := _mount(t)
	var count: int = _x(&"burst_count")
	var gap: float = _x(&"burst_gap")
	var charge: float = _x(&"charge_seconds")
	var cooldown: float = _x(&"cooldown_seconds")
	var clock := [0.0]
	var fired: Array = []
	_record(m, clock, fired)
	var telegraphs: Array[float] = []
	m.phase_changed.connect(func(p: int) -> void:
		if p == TurretMount.Phase.TELEGRAPH:
			telegraphs.append(clock[0]))
	var done := _run_until(t, clock, 450, func() -> bool: return fired.size() >= 2 * count + 1)
	assert_true(done, "%s: three bursts began within 7.5 s" % mode)

	for b in 2:
		for k in range(1, count):
			var in_gap: float = fired[b * count + k]["t"] - fired[b * count + k - 1]["t"]
			assert_almost_eq(in_gap, gap, DT + 1e-6, "%s: burst %d gap %d" % [mode, b, k])
		var rest: float = fired[(b + 1) * count]["t"] - fired[(b + 1) * count - 1]["t"]
		assert_gte(rest, cooldown + charge - 1e-6, "%s: cooldown + charge between bursts (%.4f s)" % [mode, rest])
		assert_lte(rest, cooldown + charge + 2.0 * DT + 1e-6, "%s: and no more than two ticks over" % mode)
	assert_gte(telegraphs.size(), 3, "%s: one charge per burst" % mode)
	for b in 3:
		var since: float = fired[b * count]["t"] - telegraphs[b]
		assert_gte(since, charge - 1e-6, "%s: burst %d's first round comes a full charge after TELEGRAPH" % [mode, b])


# ── 5. Perception flicker keeps the cooldown ────────────────────────────────────────────────────────────────────────

## Drops perception for 0.2 s (the stub beyond `lose_radius`) once `fired` holds `after_rounds` rounds, then brings it back, and returns
## {cut: the first tick of the drop, cooldown_on_return, next: the next first round's time} (next -1 if none within 5 s).
func _flicker_run(after_rounds: int) -> Dictionary:
	var h = _world("open_space")
	h.player.global_position = T + BELOW
	var t := _turret(h, T, true)
	var m := _mount(t)
	var clock := [0.0]
	var fired: Array = []
	_record(m, clock, fired)
	assert_true(_run_until(t, clock, 240, func() -> bool: return fired.size() >= after_rounds), "rounds before the drop")
	var cut: float = clock[0] + DT
	h.player.global_position = T + Vector2(0.0, SHIPPED.lose_radius + 100.0)
	_run_until(t, clock, 12, func() -> bool: return false)
	h.player.global_position = T + BELOW
	var on_return := m.cooldown_left()
	var before := fired.size()
	_run_until(t, clock, 300, func() -> bool: return fired.size() > before)
	return {"cut": cut, "last": fired[after_rounds - 1]["t"], "on_return": on_return,
			"next": fired[before]["t"] if fired.size() > before else -1.0, "cut_rounds": before}


func test_open_space_a_perception_flicker_after_a_burst_keeps_the_cooldown() -> void:
	var period := float(_x(&"cooldown_seconds")) + float(_x(&"charge_seconds"))
	var run := _flicker_run(int(_x(&"burst_count")))
	assert_gt(run["on_return"] as float, 0.0, "the cooldown is still running when the player is back")
	assert_gt(run["next"] as float, 0.0, "the turret fires again")
	assert_gte((run["next"] as float) - (run["last"] as float), period - DT, "no burst inside cooldown + charge of the last round")


func test_open_space_a_burst_cut_by_a_flicker_still_starts_the_cooldown() -> void:
	var period := float(_x(&"cooldown_seconds")) + float(_x(&"charge_seconds"))
	var run := _flicker_run(2)
	assert_eq(run["cut_rounds"], 2, "the burst was cut at 2 rounds")
	assert_gt(run["on_return"] as float, 0.0, "a cut burst still started the cooldown")
	assert_gte((run["next"] as float) - (run["cut"] as float), period - DT, "no burst inside cooldown + charge of the cut")


# ── 6. Scan ─────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_with_no_target_the_mount_scans_its_arc_at_scan_speed(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.remove_from_group(&"player")
	var t := _turret(h, T, false, 11)
	var m := _mount(t)
	var rest := deg_to_rad(m.rest_bearing_deg)
	var half := deg_to_rad(float(_x(&"scan_arc_deg"))) * 0.5
	var speed: float = _x(&"scan_speed")
	var lo := INF
	var hi := -INF
	var worst_out := 0.0
	var worst_step := 0.0
	var prev := m.rotation
	for i in 540:
		t._physics_process(DT)
		var off := angle_difference(rest, m.rotation)
		lo = minf(lo, off)
		hi = maxf(hi, off)
		worst_out = maxf(worst_out, absf(off) - half)
		worst_step = maxf(worst_step, absf(angle_difference(prev, m.rotation)))
		prev = m.rotation
	assert_eq(_brain(t).phase, DefenseTurretBrain.Phase.SCAN, "%s: no target, no notice" % mode)
	assert_eq(m.phase(), TurretMount.Phase.SCAN)
	assert_lte(worst_out, 1e-3, "%s: never past the arc" % mode)
	assert_lte(worst_step, speed * DT + 1e-4, "%s: at scan_speed" % mode)
	assert_gte(hi - lo, half * 2.0 - deg_to_rad(1.0), "%s: the sweep covers the whole arc" % mode)
	var other := _turret(h, T + Vector2(200.0, 0.0), false, 12)
	assert_gt(absf(angle_difference(_mount(other).rotation, _mount(_turret(h, T + Vector2(-200.0, 0.0), false, 11)).rotation)), 1e-3,
			"%s: the start offset comes from the brain's rng" % mode)
	assert_lt(absf(angle_difference(_mount(_turret(h, T + Vector2(0.0, 100.0), false, 11)).rotation,
			_mount(_turret(h, T + Vector2(0.0, -100.0), false, 11)).rotation)), 1e-6, "%s: the same seed gives the same offset" % mode)


# ── 7. Perception (Open Space) ──────────────────────────────────────────────────────────────────────────────────────

func test_open_space_perception_notices_at_899_px_ignores_901_and_keeps_to_1100() -> void:
	var h = _world("open_space")
	h.player.global_position = T + Vector2(0.0, SHIPPED.perceive_radius - 1.0)
	var t := _turret(h)
	var brain := _brain(t)
	var light := _light(t)
	t._physics_process(DT)
	assert_eq(brain.phase, DefenseTurretBrain.Phase.NOTICING, "noticed at perceive_radius - 1")
	assert_eq(light.get_state(), StateLight.State.OFF, "NOTICING is a beat, not a threat level")
	assert_true(light.modulate.is_equal_approx(Color(Color.YELLOW, StateLight.MAX_ALPHA)), "the light blinks once")
	var ticks := 0
	while brain.phase == DefenseTurretBrain.Phase.NOTICING and ticks < 60:
		t._physics_process(DT)
		ticks += 1
	assert_eq(brain.phase, DefenseTurretBrain.Phase.ENGAGED)
	assert_almost_eq(ticks * DT, SHIPPED.notice_time, DT + 1e-6, "ENGAGED after notice_time")

	h.player.global_position = T + Vector2(0.0, SHIPPED.lose_radius - 1.0)
	for i in 10:
		t._physics_process(DT)
	assert_eq(brain.phase, DefenseTurretBrain.Phase.ENGAGED, "kept to lose_radius")
	h.player.global_position = T + Vector2(0.0, SHIPPED.lose_radius + 1.0)
	t._physics_process(DT)
	assert_eq(brain.phase, DefenseTurretBrain.Phase.SCAN, "lost past lose_radius")
	h.player.global_position = T + Vector2(0.0, SHIPPED.perceive_radius + 1.0)
	for i in 60:
		t._physics_process(DT)
	assert_eq(brain.phase, DefenseTurretBrain.Phase.SCAN, "never noticed at perceive_radius + 1")


# ── 8. Assault view gate ────────────────────────────────────────────────────────────────────────────────────────────

func test_assault_no_round_while_the_turret_is_above_the_view() -> void:
	var h = _world("assault")
	h.player.global_position = Vector2(640.0, 600.0)
	var t := _turret(h, Vector2(640.0, -90.0), true)
	var m := _mount(t)
	var drift := t.get_node("AssaultDrift") as AssaultDrift
	var top := EnemyWorld.view_rect(get_tree()).position.y
	var entered_at := -1.0
	var first_at := -1.0
	var first_y := 0.0
	var clock := 0.0
	var fired: Array = []
	m.round_fired.connect(func(p: Node2D) -> void: fired.append(p))
	for i in 360:
		clock += DT
		drift.step(DT)
		t._physics_process(DT)
		if entered_at < 0.0 and t.global_position.y >= top:
			entered_at = clock
		if not fired.is_empty():
			first_at = clock
			first_y = t.global_position.y
			break
	assert_gt(entered_at, 0.0, "the turret drifted into view")
	assert_gt(first_at, 0.0, "and fired")
	assert_gte(first_y, top, "no round while its centre was above the view")
	assert_lte(first_at - entered_at, 4.0, "a round within 4 s of entering (%.2f s)" % (first_at - entered_at))


# ── 9. Drift ────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_drift_scrolls_only_in_assault_and_frees_below_the_world(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + BELOW
	var t := _turret(h)
	var drift := t.get_node("AssaultDrift") as AssaultDrift
	var speed := SHIPPED.assault_drift_speed
	assert_eq(drift.speed, speed, "the config's drift speed is copied onto the drift")
	var y0 := t.global_position.y
	for i in 60:
		drift.step(DT)
	if mode == "assault":
		assert_almost_eq(t.global_position.y - y0, speed * 60.0 * DT, 0.01, "assault: 60 px/s down")
		assert_eq(drift.velocity(), Vector2(0.0, speed))
		var end_y := EnemyWorld.projectile_world_rect(get_tree()).end.y
		var low := _turret(h, Vector2(640.0, end_y - 1.0))
		(low.get_node("AssaultDrift") as AssaultDrift).step(0.1)
		assert_true(low.is_queued_for_deletion(), "freed once below the projectile world rect")
		assert_false(t.is_queued_for_deletion(), "a turret still inside is kept")
	else:
		assert_eq(t.global_position.y, y0, "open space: no drift")
		assert_eq(drift.velocity(), Vector2.ZERO)


# ── 10. Not an escape ───────────────────────────────────────────────────────────────────────────────────────────────

func test_assault_a_turret_drifting_out_does_not_cost_the_combo() -> void:
	var h = _world("assault")
	var tracker := ScoreTracker.new()
	add_child_autofree(tracker)
	tracker.start_tracking()
	tracker.set_process(false)  # `_process` would decay a combo with no decay time left straight back to 1.0
	tracker.set("_combo", 4.0)
	var end_y := EnemyWorld.projectile_world_rect(get_tree()).end.y
	var t := _turret(h, Vector2(640.0, end_y - 1.0))
	EventBus.enemy_spawned_orphan.emit(t)
	(t.get_node("AssaultDrift") as AssaultDrift).step(0.1)
	assert_true(t.is_queued_for_deletion(), "sanity: it drifted out")
	await get_tree().process_frame
	assert_almost_eq(float(tracker.get("_combo")), 4.0, 0.0001, "a drifted-out turret is not an escape")

	var control := FIXTURE_ENEMY.instantiate() as BaseEnemy
	h.root.add_child(control)
	control.set_physics_process(false)
	assert_true(control.counts_as_escape, "control: a fixture enemy counts as an escape")
	EventBus.enemy_spawned_orphan.emit(control)
	control.queue_free()
	await get_tree().process_frame
	assert_almost_eq(float(tracker.get("_combo")), 4.0 * tracker.score_config.escape_combo_multiplier, 0.0001,
			"control: the same exit by an escaping enemy costs the penalty")


# ── 11. turn_rate_override ──────────────────────────────────────────────────────────────────────────────────────────

func test_open_space_a_slot_turn_rate_override_retunes_its_mount() -> void:
	var h = _world("open_space")
	var tuned := _turret(h, T, false, 4242, func(t: DefenseTurret) -> void:
		(t.get_node("MountSlots/Slot0") as TurretMountSlot).turn_rate_override = 1.2)
	assert_almost_eq(_mount(tuned).turn_rate, 1.2, 1e-6, "an override >= 0 is copied onto the mount")
	var shipped := _turret(h, T + Vector2(200.0, 0.0))
	assert_eq((shipped.get_node("MountSlots/Slot0") as TurretMountSlot).turn_rate_override, -1.0, "the shipped slot keeps the mount's")
	assert_almost_eq(_mount(shipped).turn_rate, float(_x(&"turn_rate")), 1e-6, "-1 keeps the scene's turn_rate")
	assert_almost_eq(_mount(shipped).turn_rate, 2.0, 1e-6, "which is 2.0")
	var by_variant := _turret(h, T + Vector2(-200.0, 0.0), false, 4242, func(t: DefenseTurret) -> void:
		t.variant = TurretMount.Variant.BURST_CANNON)
	assert_true(by_variant.mounts()[0] is BurstCannonMount, "variant 0 builds a burst cannon")


# ── 12. Power down mid-burst ────────────────────────────────────────────────────────────────────────────────────────

func test_power_down_stops_the_burst_and_droops_the_mount(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + BELOW + Vector2(150.0, 0.0)
	var t := _turret(h, T, true)
	var m := _mount(t)
	var turn_rate: float = _x(&"turn_rate")
	var clock := [0.0]
	var fired: Array = []
	_record(m, clock, fired)
	assert_true(_run_until(t, clock, 120, func() -> bool: return fired.size() >= 2), "%s: two rounds of the burst out" % mode)
	t.set_powered(false)
	assert_false(t.is_powered())
	var pool := t.get_node("PulsePool_0") as BulletPool
	var idle := pool._idle.size()
	assert_eq(_light(t).get_state(), StateLight.State.OFF, "%s: light OFF" % mode)
	assert_eq(_brain(t).phase, DefenseTurretBrain.Phase.UNPOWERED)
	assert_eq(m.phase(), TurretMount.Phase.UNPOWERED)

	var rest := deg_to_rad(m.rest_bearing_deg)
	var at_rest := -1.0
	for i in 120:
		t._physics_process(DT)
		if at_rest < 0.0 and absf(angle_difference(m.rotation, rest)) < deg_to_rad(0.5):
			at_rest = (i + 1) * DT
	assert_eq(fired.size(), 2, "%s: no further round" % mode)
	assert_eq(pool._idle.size(), idle, "%s: no further acquire" % mode)
	assert_gt(at_rest, 0.0, "%s: the mount droops to rest" % mode)
	assert_lte(at_rest, PI / turn_rate, "%s: within pi / turn_rate" % mode)

	for f in fired:
		var r := f["round"] as EnemyBullet
		var p0 := r.global_position
		for i in 10:
			r._physics_process(DT)
		assert_true(is_instance_valid(r) and r.get_parent() == h.root, "%s: a round in flight lives on in the container" % mode)
		assert_almost_eq(r.global_position.distance_to(p0), r.speed * 10.0 * DT, 0.01, "%s: and keeps flying" % mode)

	t.set_powered(true)
	t._physics_process(DT)
	assert_eq(_brain(t).phase, DefenseTurretBrain.Phase.UNPOWERED, "%s: never re-powered in this phase" % mode)
	m.power_down()
	assert_eq(m.phase(), TurretMount.Phase.UNPOWERED, "power_down() is idempotent")


# ── 13. Pools and container ─────────────────────────────────────────────────────────────────────────────────────────

func test_the_pool_is_a_root_child_and_rounds_land_in_the_enemy_container(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + BELOW
	var t := _turret(h, T, true)
	var m := _mount(t)
	var pools := t.get_children().filter(func(c: Node) -> bool: return c is BulletPool)
	assert_eq(pools.size(), 1, "%s: one pool, a direct child of the root" % mode)
	var pool := pools[0] as BulletPool
	assert_eq(String(pool.name), "PulsePool_0")
	var period := float(_x(&"charge_seconds")) + (int(_x(&"burst_count")) - 1) * float(_x(&"burst_gap")) + float(_x(&"cooldown_seconds"))
	var max_time := float(EnemyBeamScenes.export_of_scene(EnemyRounds.PULSE, &"max_time", -1.0, ^"ProjectileLifetime"))
	assert_eq(pool.pool_size, EnemyRounds.pool_size_for(int(_x(&"burst_count")), max_time, period), "%s: sized from the exports" % mode)
	assert_eq(pool.pool_size, m.pool_specs()[0]["size"])
	assert_eq(pool.bullet_scene.resource_path, EnemyRounds.PULSE.resource_path, "Pulse rounds")
	var clock := [0.0]
	var fired: Array = []
	_record(m, clock, fired)
	assert_true(_run_until(t, clock, 120, func() -> bool: return not fired.is_empty()), "%s: a round" % mode)
	assert_eq((fired[0]["round"] as Node).get_parent(), t.get_parent(), "%s: the round is in the enemy container" % mode)


# ── 14. Owner group ─────────────────────────────────────────────────────────────────────────────────────────────────

class _GroupStub extends RefCounted:
	var owner_group: StringName = &"g_test"


func test_open_space_the_owner_group_is_the_groups_or_the_turrets_own() -> void:
	var h = _world("open_space")
	var alone := _turret(h)
	var own := StringName("turret_%d" % alone.get_instance_id())
	assert_true(alone.is_in_group(own), "without a group the turret is its own owner group")
	assert_eq(_mount(alone).owner_group(), own, "and its mount shares it")
	var stub := _GroupStub.new()
	var member := _turret(h, T + Vector2(200.0, 0.0), false, 4242, func(t: DefenseTurret) -> void: t.set_turret_group(stub))
	assert_true(member.is_in_group(&"g_test"), "a group member joins the group's owner group")
	assert_eq(member.owner_group(), &"g_test")
	assert_eq(_mount(member).owner_group(), &"g_test")
	assert_same(member.turret_group(), stub)


# ── 15. Real physics at 8x: line of sight, then the mining beam ─────────────────────────────────────────────────────

## Drives a real `BeamBehavior` from `_physics_process` (test_ram_corvette.gd's driver).
class BeamDriver extends Node2D:
	var actor: Node2D
	var behavior: BeamBehavior
	var mode: WeaponModeResource
	var muzzles: Array[Marker2D] = []

	func _physics_process(delta: float) -> void:
		if behavior != null:
			behavior.tick(self, mode, muzzles, delta)


func _physics_frames_until(max_frames: int, done: Callable) -> bool:
	for i in max_frames:
		await get_tree().physics_frame
		if done.call():
			return true
	return false


func test_cover_holds_fire_and_the_mining_beam_burns_the_turret(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 400.0)
	var wreck := WRECK_MEDIUM.instantiate() as Wreck
	wreck.set_physics_process(false)
	h.root.add_child(wreck)
	wreck.global_position = T + Vector2(0.0, 200.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var t := TURRET_SCENE.instantiate() as DefenseTurret
	(t.get_node("Brain") as DefenseTurretBrain).start_engaged = true
	t.position = T
	h.root.add_child(t)
	var fired: Array = []
	_mount(t).round_fired.connect(func(p: Node2D) -> void: fired.append(p))

	await _physics_frames_until(90, func() -> bool: return false)
	assert_eq(fired.size(), 0, "%s: a wreck between turret and player holds fire" % mode)
	assert_eq(_brain(t).phase, DefenseTurretBrain.Phase.ENGAGED, "%s: while engaged (not merely unaware)" % mode)

	wreck.queue_free()
	var resumed: bool = await _physics_frames_until(90, func() -> bool: return not fired.is_empty())
	assert_true(resumed, "%s: with the wreck gone it fires within 1.5 s" % mode)

	var d := BeamDriver.new()
	d.behavior = BeamBehavior.new()
	d.mode = LASER_MODE
	var muzzle := Marker2D.new()
	d.add_child(muzzle)
	d.muzzles = [muzzle]
	d.actor = d
	h.root.add_child(d)
	d.global_position = t.global_position + Vector2(0.0, 250.0)
	var max_hp := t.health.max_health
	var burned: bool = await _physics_frames_until(40, func() -> bool: return t.health.current_health < max_hp)
	assert_true(burned, "%s: the player's mining beam passes over the root and burns the turret" % mode)


# ── 16. Every phase ticks the weapon ────────────────────────────────────────────────────────────────────────────────

func test_open_space_every_phase_ticks_the_weapon_once_and_telegraph_done_decides() -> void:
	var h = _world("open_space")
	var holder := Node2D.new()
	holder.position = T
	h.root.add_child(holder)
	var m := FIXTURE_MOUNT.new() as TurretMount
	holder.add_child(m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	m.rng = rng
	m.setup(holder, {}, &"g_fixture")
	h.player.global_position = T + BELOW
	var target := TargetInfo.of(h.player)
	var calls := 0
	for i in 3:
		m.scan(DT)
		calls += 1
	assert_eq(m.phase(), TurretMount.Phase.SCAN)
	for i in 3:
		m.tick(DT, target, false)  # TRACK, held: no can_fire
		calls += 1
	assert_eq(m.phase(), TurretMount.Phase.TRACK)
	var ticks := 0
	while m.phase() == TurretMount.Phase.TRACK and ticks < 120:
		m.tick(DT, target, true)
		calls += 1
		ticks += 1
	assert_eq(m.phase(), TurretMount.Phase.TELEGRAPH)
	for i in 10:  # past _telegraph_seconds() (0.05 s): the hook, not the clock, decides
		m.tick(DT, target, true)
		calls += 1
	assert_eq(m.phase(), TurretMount.Phase.TELEGRAPH, "_telegraph_done() holds TELEGRAPH past the clock")
	m.set("telegraph_ready", true)
	while m.phase() != TurretMount.Phase.COOLDOWN and calls < 400:
		m.tick(DT, target, true)
		calls += 1
	assert_eq(m.phase(), TurretMount.Phase.COOLDOWN)
	for i in 3:
		m.tick(DT, target, true)
		calls += 1
	m.power_down()
	for i in 3:
		m.tick(DT, target, true)
		calls += 1
	for i in 2:
		m.scan(DT)
		calls += 1
	var counts: Dictionary = m.get("weapon_ticks")
	var total := 0
	for p in counts:
		total += int(counts[p])
	assert_eq(total, calls, "exactly one _weapon_tick per tick() / scan() call")
	for p in TurretMount.Phase.values():
		assert_true(counts.has(p), "_weapon_tick ran in %s" % TurretMount.Phase.keys()[p])


# ── 17. Beam mounts (Phase 8 t7): sweep, lance, beam cannon ─────────────────────────────────────────────────────────
#
# Hand-ticked in both harnesses. Every number is read from the mount scene or the beam scene it fires (`_mx` / `_bx`); the only typed
# numbers are the test stub's distance and velocity. Hits are read from the mount's own beam (`target_hit`) on `fixture_enemy.tscn`
# victims with a 14 px hurtbox, so the player stub (no hurtbox) is never a target.

const SWEEP := TurretMount.Variant.SWEEP_BEAM
const LANCE := TurretMount.Variant.LANCE
const CANNON := TurretMount.Variant.BEAM_CANNON
const BEAM_VARIANTS := [SWEEP, LANCE, CANNON]
const BEAM_KIND := {SWEEP: EnemyBeam.Kind.SWEEP, LANCE: EnemyBeam.Kind.LANCE, CANNON: EnemyBeam.Kind.BEAM}


## A mount export as the variant's scene authors it.
func _mx(variant: int, property: StringName) -> Variant:
	return TurretMountScenes.export_of(variant, property, MOUNT_SCRIPT.get_property_default_value(property))


## A beam export as the variant's beam scene authors it.
func _bx(variant: int, property: StringName) -> Variant:
	return EnemyBeamScenes.export_of(BEAM_KIND[variant], property, BEAM_SCRIPT.get_property_default_value(property))


func _beam_turret(h, variant: int, prepare: Callable = Callable(), seed_value: int = 4242) -> DefenseTurret:
	return _turret(h, T, true, seed_value, func(t: DefenseTurret) -> void:
		t.variant = variant
		if prepare.is_valid():
			prepare.call(t))


func _beam_mount(t: DefenseTurret) -> BeamTurretMount:
	return t.mounts()[0] as BeamTurretMount


func _circle(radius: float) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	return cs


func _victim(h, at: Vector2) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	e.get_node("HurtBox").add_child(_circle(14.0))
	e.add_to_group(&"enemies")
	h.root.add_child(e)
	e.global_position = at
	return e


## Every `target_hit` of the mount's beam as [target, damage].
func _hit_log(m: BeamTurretMount) -> Array:
	var record: Array = []
	m.beam().target_hit.connect(func(target: Node2D, damage: int) -> void: record.append([target, damage]))
	return record


func _hits_on(record: Array, target: Node) -> int:
	var n := 0
	for entry: Array in record:
		if entry[0] == target:
			n += 1
	return n


## The lead point of a beam aim: the stub's position plus its velocity over the beam's telegraph, `lead_blend` of the way.
func _beam_lead(variant: int, p: Vector2, v: Vector2) -> Vector2:
	return p + v * float(_bx(variant, &"telegraph_seconds")) * float(_mx(variant, &"lead_blend"))


func test_every_beam_variant_builds_with_a_mount_child_beam_of_its_own_scene(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	for variant in BEAM_VARIANTS:
		assert_not_null(TurretMountScenes.scene_for(variant), "%s: variant %d has a scene" % [mode, variant])
		var t := _beam_turret(h, variant)
		var m := _beam_mount(t)
		assert_not_null(m, "%s: the slot holds a beam mount" % mode)
		var b := m.beam()
		assert_eq(b.get_parent(), m, "%s: the beam is a mount child" % mode)
		assert_eq(b.kind, BEAM_KIND[variant], "%s: of the variant's own kind" % mode)
		assert_eq(b.length, float(_bx(variant, &"length")), "%s: the weapon scene's length" % mode)
		assert_eq(b.telegraph_seconds, float(_bx(variant, &"telegraph_seconds")))
		assert_eq(m.fire_range, float(_mx(variant, &"fire_range")))
		assert_eq(m.pool_specs().size(), 0, "%s: a beam mount builds no pools" % mode)
		assert_eq(b.global_position, m.muzzle_position(), "%s: the beam starts at the muzzle" % mode)
		assert_false(m.is_committed(), "%s: nothing committed at rest" % mode)
		assert_false(m.fires_past_cover(), "%s: a beam holds fire without line of sight" % mode)


func test_the_sweep_telegraph_line_sits_at_the_start_bearing_on_the_side_the_player_comes_from(mode: String = use_parameters(MODES)) -> void:
	var half_arc := deg_to_rad(float(_bx(SWEEP, &"sweep_arc_deg"))) * 0.5
	var half_cone := deg_to_rad(float(_mx(SWEEP, &"fire_cone_deg"))) * 0.5
	for s in [1.0, -1.0]:
		var h = _world(mode)
		h.player.global_position = T + Vector2(0.0, 250.0)
		h.player.velocity = Vector2(-100.0 * s, 0.0)  # about the turret a stub below it moving -x is turning positively (clockwise)
		var t := _beam_turret(h, SWEEP)
		var m := _beam_mount(t)
		var clock := [0.0]
		assert_true(_run_until(t, clock, 240, func() -> bool: return m.phase() == TurretMount.Phase.TELEGRAPH),
				"%s s=%d: the mount reaches the start bearing and telegraphs" % [mode, s])
		var lead := _beam_lead(SWEEP, h.player.global_position, h.player.velocity)
		var aim := (lead - m.global_position).angle()
		var expected: float = aim - s * half_arc
		var line := m.beam().global_rotation
		assert_lt(absf(angle_difference(line, expected)), half_cone + 0.01, "%s s=%d: the line is at aim - s * arc/2" % [mode, s])
		assert_eq(m.beam().phase(), EnemyBeam.Phase.TELEGRAPH, "%s: the beam shows its warning" % mode)
		assert_eq(_light(t).get_state(), StateLight.State.CHARGING, "%s: light CHARGING" % mode)
		# Moving the stub changes nothing: the shown line is the line that fires.
		h.player.global_position += Vector2(150.0 * s, 40.0)
		for i in 20:
			t._physics_process(DT)
		assert_eq(m.beam().global_rotation, line, "%s s=%d: the line does not re-aim during TELEGRAPH" % [mode, s])
		h.root.free()


func test_the_sweep_turns_its_arc_at_the_sweep_rate_through_the_aim_bearing_and_hits_a_stub_there(mode: String = use_parameters(MODES)) -> void:
	var arc := deg_to_rad(float(_bx(SWEEP, &"sweep_arc_deg")))
	var rate: float = _bx(SWEEP, &"sweep_rate")
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 250.0)
	h.player.velocity = Vector2(-100.0, 0.0)  # s = +1
	var t := _beam_turret(h, SWEEP)
	var m := _beam_mount(t)
	var aim := (_beam_lead(SWEEP, h.player.global_position, h.player.velocity) - m.global_position).angle()
	var victim := _victim(h, m.global_position + Vector2.from_angle(aim) * 220.0)
	var hits := _hit_log(m)
	var clock := [0.0]
	var times := {}
	m.beam().phase_changed.connect(func(p: int) -> void: times[p] = clock[0])
	var first_active := [NAN]
	var worst_step := [0.0]
	var prev := [m.rotation]
	var light_in_active := [-1]
	for i in 600:
		clock[0] += DT
		t._physics_process(DT)
		if m.beam().phase() == EnemyBeam.Phase.ACTIVE:
			if is_nan(first_active[0]):
				first_active[0] = prev[0]
			worst_step[0] = maxf(worst_step[0], absf(angle_difference(prev[0], m.rotation)))
			light_in_active[0] = _light(t).get_state()
		prev[0] = m.rotation
		if times.has(EnemyBeam.Phase.FADE):
			break
	assert_true(times.has(EnemyBeam.Phase.FADE), "%s: the sweep ran its course" % mode)
	assert_almost_eq(times[EnemyBeam.Phase.ACTIVE] - times[EnemyBeam.Phase.TELEGRAPH], float(_bx(SWEEP, &"telegraph_seconds")), DT + 1e-6,
			"%s: TELEGRAPH lasts telegraph_seconds" % mode)
	assert_almost_eq(times[EnemyBeam.Phase.FADE] - times[EnemyBeam.Phase.ACTIVE], float(_bx(SWEEP, &"active_seconds")), DT + 1e-6,
			"%s: ACTIVE lasts active_seconds" % mode)
	assert_almost_eq(angle_difference(first_active[0], m.rotation), arc, rate * DT * 2.0, "%s: ACTIVE turns the whole arc toward the player" % mode)
	assert_almost_eq(worst_step[0], rate * DT, 1e-4, "%s: a step is sweep_rate * dt" % mode)
	assert_gt(_hits_on(hits, victim), 0, "%s: a stub standing at the aim bearing is hit" % mode)
	assert_eq(light_in_active[0], StateLight.State.ARMED, "%s: light ARMED while lit" % mode)


func test_the_mount_turn_rate_cap_does_not_apply_during_the_sweep(mode: String = use_parameters(MODES)) -> void:
	var rate: float = _bx(SWEEP, &"sweep_rate")
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 250.0)
	h.player.velocity = Vector2(-100.0, 0.0)
	var slow := rate * 0.3
	var t := _beam_turret(h, SWEEP, func(tt: DefenseTurret) -> void:
		(tt.get_node("MountSlots/Slot0") as TurretMountSlot).turn_rate_override = slow)
	var m := _beam_mount(t)
	assert_almost_eq(m.turn_rate, slow, 1e-6, "sanity: the mount is slower than the sweep")
	var half_arc := deg_to_rad(float(_bx(SWEEP, &"sweep_arc_deg"))) * 0.5
	var aim := (_beam_lead(SWEEP, h.player.global_position, h.player.velocity) - m.global_position).angle()
	m.rotation = aim - half_arc  # already on the start bearing
	var clock := [0.0]
	assert_true(_run_until(t, clock, 600, func() -> bool: return m.beam().phase() == EnemyBeam.Phase.ACTIVE), "%s: reaches ACTIVE" % mode)
	var prev := m.rotation
	var worst := 0.0
	for i in 40:
		t._physics_process(DT)
		worst = maxf(worst, absf(angle_difference(prev, m.rotation)))
		prev = m.rotation
	assert_gt(worst, slow * DT * 2.0, "%s: the sweep turns faster than turn_rate allows" % mode)


func test_a_still_player_draws_the_sweep_side_from_the_rng(mode: String = use_parameters(MODES)) -> void:
	var half_arc := deg_to_rad(float(_bx(SWEEP, &"sweep_arc_deg"))) * 0.5
	var sides := {}
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var h = _world(mode)
		h.player.global_position = T + Vector2(0.0, 250.0)
		var t := _beam_turret(h, SWEEP, Callable(), seed_value)
		var m := _beam_mount(t)
		var clock := [0.0]
		assert_true(_run_until(t, clock, 300, func() -> bool: return m.phase() == TurretMount.Phase.TELEGRAPH), "%s: telegraphs" % mode)
		var off := angle_difference((h.player.global_position - m.global_position).angle(), m.beam().global_rotation)
		assert_almost_eq(absf(off), half_arc, deg_to_rad(5.0), "%s: still offset by half the arc" % mode)
		sides[signf(off)] = true
		h.root.free()
	assert_eq(sides.size(), 2, "%s: both sides occur across seeds" % mode)


func test_the_lance_tracks_then_freezes_for_commit_and_hits_once_for_its_damage(mode: String = use_parameters(MODES)) -> void:
	var commit: float = _bx(LANCE, &"commit_seconds")
	var telegraph: float = _bx(LANCE, &"telegraph_seconds")
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 500.0)
	var t := _beam_turret(h, LANCE)
	var m := _beam_mount(t)
	var clock := [0.0]
	assert_true(_run_until(t, clock, 240, func() -> bool: return m.phase() == TurretMount.Phase.TELEGRAPH), "%s: telegraphs" % mode)
	var b := m.beam()
	var started := [clock[0]]
	var victim := _victim(h, m.global_position + Vector2.from_angle(m.global_rotation) * 300.0)
	var hits := _hit_log(m)
	var damages: Array = []
	b.target_hit.connect(func(_target: Node2D, damage: int) -> void: damages.append(damage))
	# Tracking: the stub steps aside and the aim follows.
	var before := m.rotation
	h.player.global_position += Vector2(60.0, 0.0)
	for i in 6:
		clock[0] += DT
		t._physics_process(DT)
	assert_ne(m.rotation, before, "%s: the aim tracks before COMMIT" % mode)
	assert_false(m.is_committed(), "%s: not yet committed" % mode)
	assert_eq(_light(t).get_state(), StateLight.State.CHARGING, "%s: light CHARGING" % mode)
	var seen_commit := false
	var light_at_commit := -1
	for i in 120:
		clock[0] += DT
		t._physics_process(DT)
		if m.is_committed():
			seen_commit = true
			light_at_commit = _light(t).get_state()
			break
	assert_true(seen_commit, "%s: the lance commits" % mode)
	assert_eq(light_at_commit, StateLight.State.COMMIT, "%s: light COMMIT" % mode)
	assert_almost_eq(clock[0] - float(started[0]), telegraph - commit, 2.0 * DT, "%s: COMMIT is the last commit_seconds" % mode)
	var frozen_rot := m.rotation
	victim.global_position = m.global_position + Vector2.from_angle(b.global_rotation) * 300.0
	h.player.global_position += Vector2(260.0, 0.0)  # a stub that moves during COMMIT changes nothing
	var saw_armed := false
	for i in 90:
		t._physics_process(DT)
		if b.phase() == EnemyBeam.Phase.TELEGRAPH or b.phase() == EnemyBeam.Phase.ACTIVE:
			assert_eq(m.rotation, frozen_rot, "%s: frozen through COMMIT and the shot" % mode)
		if b.phase() == EnemyBeam.Phase.ACTIVE and _light(t).get_state() == StateLight.State.ARMED:
			saw_armed = true
	assert_true(saw_armed, "%s: light ARMED while the lance is lit" % mode)
	assert_eq(_hits_on(hits, victim), 1, "%s: one hit, however long it is held" % mode)
	assert_eq(damages, [int(_bx(LANCE, &"damage"))], "%s: for the lance's damage" % mode)


func test_the_beam_cannon_freezes_its_bearing_at_telegraph_start_and_a_step_aside_dodges_it(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 300.0)
	var t := _beam_turret(h, CANNON)
	var m := _beam_mount(t)
	var clock := [0.0]
	var times := {}
	m.beam().phase_changed.connect(func(p: int) -> void: times[p] = clock[0])
	assert_true(_run_until(t, clock, 240, func() -> bool: return m.phase() == TurretMount.Phase.TELEGRAPH), "%s: telegraphs" % mode)
	var b := m.beam()
	var frozen := b.global_rotation
	var frozen_aim := m.aim_point()
	var on_line := _victim(h, m.global_position + Vector2.from_angle(frozen) * 350.0)
	var stepped_to := _victim(h, m.global_position + Vector2.from_angle(frozen + deg_to_rad(25.0)) * 350.0)
	var hits := _hit_log(m)
	h.player.global_position += Vector2(200.0, 0.0)  # the stub steps out during TELEGRAPH
	var armed_seen := false
	var lethal_ticks := 0
	var moved := false
	for i in 200:
		clock[0] += DT
		t._physics_process(DT)
		if b.phase() == EnemyBeam.Phase.TELEGRAPH:
			assert_eq(_hits_on(hits, on_line), 0, "%s: no hit during TELEGRAPH" % mode)
			assert_eq(m.aim_point(), frozen_aim, "%s: the aim point is frozen too" % mode)
		if b.phase() == EnemyBeam.Phase.TELEGRAPH or b.phase() == EnemyBeam.Phase.ACTIVE:
			moved = moved or b.global_rotation != frozen
		if b.is_lethal():
			lethal_ticks += 1
		if b.phase() == EnemyBeam.Phase.ACTIVE and _light(t).get_state() == StateLight.State.ARMED:
			armed_seen = true
		if times.has(EnemyBeam.Phase.OFF):
			break
	assert_false(moved, "%s: the bearing never changes while the shot is out" % mode)
	assert_true(armed_seen, "%s: light ARMED while lit" % mode)
	assert_gt(_hits_on(hits, on_line), 0, "%s: the shown line is the line that fires" % mode)
	assert_eq(_hits_on(hits, stepped_to), 0, "%s: where the stub stepped to is not hit" % mode)
	assert_almost_eq(times[EnemyBeam.Phase.ACTIVE] - times[EnemyBeam.Phase.TELEGRAPH], float(_bx(CANNON, &"telegraph_seconds")), DT + 1e-6,
			"%s: TELEGRAPH lasts telegraph_seconds" % mode)
	assert_almost_eq(float(lethal_ticks) * DT, float(_bx(CANNON, &"active_seconds")) - float(_bx(CANNON, &"ignite_grace")), 2.0 * DT,
			"%s: lethal for the active window less the ignite grace" % mode)
	assert_gt(m.cooldown_left(), 0.0, "%s: the cooldown is running" % mode)


func test_a_beam_never_burns_its_owner_group_and_dies_with_its_turret(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 300.0)
	var t := _beam_turret(h, CANNON)
	var m := _beam_mount(t)
	var clock := [0.0]
	assert_true(_run_until(t, clock, 240, func() -> bool: return m.phase() == TurretMount.Phase.TELEGRAPH), "%s: telegraphs" % mode)
	var dir := Vector2.from_angle(m.beam().global_rotation)
	var mate := _victim(h, m.global_position + dir * 300.0)
	mate.add_to_group(t.owner_group())
	var foe := _victim(h, m.global_position + dir * 360.0)
	var hits := _hit_log(m)
	_run_until(t, clock, 120, func() -> bool: return m.beam().phase() == EnemyBeam.Phase.FADE)
	assert_gt(_hits_on(hits, foe), 0, "%s: control: an outsider on the line is hit" % mode)
	assert_eq(_hits_on(hits, mate), 0, "%s: a member of the turret's owner group is not" % mode)
	var b := m.beam()
	t.free()
	assert_false(is_instance_valid(b), "%s: the beam goes with its turret" % mode)


func test_power_down_cancels_a_telegraph_or_fades_a_lit_beam_and_never_restarts(mode: String = use_parameters(MODES)) -> void:
	for variant in BEAM_VARIANTS:
		for lit in [false, true]:
			var label := "%s %d %s" % [mode, variant, "ACTIVE" if lit else "TELEGRAPH"]
			var h = _world(mode)
			h.player.global_position = T + Vector2(0.0, 250.0)
			h.player.velocity = Vector2(-60.0, 0.0)
			var t := _beam_turret(h, variant)
			var m := _beam_mount(t)
			var b := m.beam()
			var clock := [0.0]
			assert_true(_run_until(t, clock, 300, func() -> bool: return b.phase() == EnemyBeam.Phase.TELEGRAPH), "%s: telegraphs" % label)
			var victim := _victim(h, m.global_position + Vector2.from_angle(b.global_rotation) * 150.0)
			var hits := _hit_log(m)
			if lit:
				assert_true(_run_until(t, clock, 300, func() -> bool: return b.is_lethal()), "%s: lethal" % label)
			else:
				_run_until(t, clock, 5, func() -> bool: return false)
			var hit_before := _hits_on(hits, victim)
			t.set_powered(false)
			if lit:
				assert_eq(b.phase(), EnemyBeam.Phase.FADE, "%s: a lit beam fades at once" % label)
			else:
				assert_eq(b.phase(), EnemyBeam.Phase.OFF, "%s: a telegraph is cancelled at once" % label)
			assert_eq(m.phase(), TurretMount.Phase.UNPOWERED, "%s: UNPOWERED" % label)
			assert_eq(_light(t).get_state(), StateLight.State.OFF, "%s: light OFF" % label)
			for i in 400:
				t._physics_process(DT)
			assert_eq(_hits_on(hits, victim), hit_before, "%s: no hit after power-down" % label)
			if not lit:
				assert_eq(hit_before, 0, "%s: a cancelled telegraph never hurt" % label)
			assert_eq(b.phase(), EnemyBeam.Phase.OFF, "%s: never restarts" % label)
			assert_false(b.is_lethal())
			h.root.free()


# ── 18. Rocket battery and pulse ring mounts (Phase 8 t8) ───────────────────────────────────────────────────────────
#
# Hand-ticked in both harnesses unless the name says real physics (8x clock). Mount numbers come from the mount scenes, rocket numbers from the
# rocket scenes (`EnemyRocketScenes.export_of`), ring numbers from `energy_ring.tscn` (`EnemyBeamScenes.export_of_scene`). A rocket never moves in a
# hand-ticked row (the scene tree runs no physics frame), so a row that fires many salvos recycles each rocket with `expired`, as the pool would.

const ROCKET := TurretMount.Variant.ROCKET_BATTERY
const RING := TurretMount.Variant.PULSE_RING
const RING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_beams/energy_ring.tscn")
const RING_SCRIPT: Script = preload("res://assault/scenes/projectiles/enemy_beams/energy_ring.gd")
const ROCKET_SCRIPT: Script = preload("res://assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd")


func _rocket_mount(t: DefenseTurret) -> RocketBatteryMount:
	return t.mounts()[0] as RocketBatteryMount


func _ring_mount(t: DefenseTurret) -> PulseRingMount:
	return t.mounts()[0] as PulseRingMount


## A ring export as `energy_ring.tscn` authors it.
func _rx(property: StringName) -> Variant:
	return EnemyBeamScenes.export_of_scene(RING_SCENE, property, RING_SCRIPT.get_property_default_value(property))


## A rocket export as the kind's scene authors it.
func _kx(kind: EnemyRocket.Kind, property: StringName) -> Variant:
	return EnemyRocketScenes.export_of(kind, property, ROCKET_SCRIPT.get_property_default_value(property))


## Every rocket the mount launches as {t, rocket}; `clock` is the caller's one-element time cell.
func _rocket_log(m: TurretMount, clock: Array) -> Array:
	var log: Array = []
	m.round_fired.connect(func(projectile: Node2D) -> void: log.append({"t": clock[0], "rocket": projectile}))
	return log


func test_the_rocket_battery_builds_two_persisting_root_pools_sized_for_a_worst_case_salvo(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var t := _beam_turret(h, ROCKET)
	var m := _rocket_mount(t)
	assert_not_null(m, "%s: the slot holds a rocket battery" % mode)
	assert_true(m.fires_past_cover(), "%s: curving ordnance fires without line of sight" % mode)
	assert_false(m.is_committed())
	var count: int = _mx(ROCKET, &"salvo_count")
	var period: float = float(_mx(ROCKET, &"charge_seconds")) + (count - 1) * float(_mx(ROCKET, &"salvo_gap")) + float(_mx(ROCKET, &"cooldown_seconds"))
	assert_eq(count, 2, "%s: a salvo of 2" % mode)
	var specs := m.pool_specs()
	assert_eq(specs.size(), 2, "%s: a Dumb and a Pursuit pool" % mode)
	var kinds := {&"DumbPool": EnemyRocket.Kind.DUMB, &"PursuitPool": EnemyRocket.Kind.PURSUIT}
	for spec in specs:
		var kind: EnemyRocket.Kind = kinds[spec["name"]]
		assert_true(spec["persist"], "%s: %s persists after its turret" % [mode, spec["name"]])
		assert_eq(spec["scene"], EnemyRocketScenes.scene_for(kind), "%s: %s holds its kind's scene" % [mode, spec["name"]])
		var stand_in := {"salvo_count": count, "warhead_salvo_count": 0, "salvo_period_min": period}
		assert_eq(spec["size"], EnemyRocketScenes.pool_size_for(kind, stand_in), "%s: %s is sized by pool_size_for" % [mode, spec["name"]])
		assert_gte(spec["size"], count, "%s: a whole salvo of one kind fits" % mode)
		# Worst live count: a salvo's rockets, plus the previous salvo's while still flying (zero extra here: a rocket's max_time < the period).
		var worst := count * int(ceil(float(_kx(kind, &"max_time")) / period))
		assert_eq(spec["size"], worst, "%s: %s is pinned to the worst-case live count" % [mode, spec["name"]])
		var pool := t.get_node("%s_0" % spec["name"]) as BulletPool
		assert_not_null(pool, "%s: %s is a root child of the turret" % [mode, spec["name"]])
		assert_true(pool.persist_after_owner_death, "%s: persist_after_owner_death" % mode)
		assert_eq(pool.pool_size, spec["size"])


func test_the_turret_answers_the_rocket_launcher_contract(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var t := _beam_turret(h, ROCKET)
	var body := t.get_node("CollisionShape2D") as CollisionShape2D
	assert_eq(t.launch_velocity(), Vector2.ZERO, "%s: a static host adds nothing to a rocket's speed" % mode)
	assert_almost_eq(t.rocket_clear_radius(), (body.shape as CircleShape2D).radius + 4.0, 1e-4, "%s: clear radius = body radius + 4" % mode)


func test_a_salvo_of_two_after_the_tube_glow_then_the_cooldown(mode: String = use_parameters(MODES)) -> void:
	var charge: float = _mx(ROCKET, &"charge_seconds")
	var gap: float = _mx(ROCKET, &"salvo_gap")
	var cooldown: float = _mx(ROCKET, &"cooldown_seconds")
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 500.0)
	var t := _beam_turret(h, ROCKET)
	var m := _rocket_mount(t)
	var clock := [0.0]
	var log := _rocket_log(m, clock)
	var started := [NAN]
	m.phase_changed.connect(func(p: int) -> void:
		if p == TurretMount.Phase.TELEGRAPH and is_nan(started[0]):
			started[0] = clock[0])
	var light_in_glow := [-1]
	var first_salvo := _run_until(t, clock, 600, func() -> bool:
		if m.phase() == TurretMount.Phase.TELEGRAPH:
			light_in_glow[0] = _light(t).get_state()
		return log.size() >= 2)
	assert_true(first_salvo, "%s: a salvo leaves" % mode)
	assert_eq(light_in_glow[0], StateLight.State.CHARGING, "%s: light CHARGING through the tube glow" % mode)
	assert_eq(log.size(), 2, "%s: exactly two rockets" % mode)
	assert_almost_eq(float(log[0]["t"]) - float(started[0]), charge, 2.0 * DT, "%s: the first leaves when the glow ends" % mode)
	assert_almost_eq(float(log[1]["t"]) - float(log[0]["t"]), gap, 2.0 * DT, "%s: the second %s s later" % [mode, gap])
	for entry in log:
		var rocket := entry["rocket"] as EnemyRocket
		assert_almost_eq(rocket.global_position.distance_to(m.muzzle_position()), 0.0, 1e-3, "%s: from the muzzle" % mode)
		assert_lt(rad_to_deg(absf(angle_difference(rocket.heading().angle(), m.global_rotation))), 1.0, "%s: along the barrel" % mode)
	for entry in log:
		(entry["rocket"] as EnemyRocket).expired.emit()  # a flown-out rocket goes back to its pool on the next idle frame
	await get_tree().process_frame
	# Nothing more until the cooldown is out.
	for i in int((cooldown - 0.5) / DT):
		clock[0] += DT
		t._physics_process(DT)
	assert_eq(log.size(), 2, "%s: no third rocket during the cooldown" % mode)
	_run_until(t, clock, 300, func() -> bool: return log.size() >= 3)
	assert_eq(log.size(), 3, "%s: the next salvo follows" % mode)
	assert_gte(float(log[2]["t"]) - float(log[1]["t"]), cooldown + charge - DT, "%s: after cooldown + glow" % mode)


func test_the_rocket_kind_is_pursuit_one_time_in_three_from_the_seeded_rng(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var t := _beam_turret(h, ROCKET, Callable(), 99)
	var m := _rocket_mount(t)
	var counts := {EnemyRocket.Kind.DUMB: 0, EnemyRocket.Kind.PURSUIT: 0}
	for i in 60:  # 30 salvos of two
		counts[m.pick_kind()] += 1
	var p := 1.0 / 3.0
	var sigma := sqrt(60.0 * p * (1.0 - p))
	assert_between(float(counts[EnemyRocket.Kind.PURSUIT]), 60.0 * p - 4.0 * sigma, 60.0 * p + 4.0 * sigma, "%s: Pursuit about a third of rockets" % mode)
	assert_gt(int(counts[EnemyRocket.Kind.DUMB]), 0, "%s: and Dumb the rest" % mode)
	# Real salvos launch a rocket out of the pool of the kind drawn.
	h.player.global_position = T + Vector2(0.0, 500.0)
	var clock := [0.0]
	var log := _rocket_log(m, clock)
	_run_until(t, clock, 600, func() -> bool: return log.size() >= 2)
	for entry in log:
		assert_true((entry["rocket"] as EnemyRocket).kind in [EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT], "%s: a Dumb or Pursuit rocket" % mode)


func test_the_battery_fires_with_a_wreck_between_real_physics(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 400.0)
	var wreck := WRECK_MEDIUM.instantiate() as Wreck
	wreck.set_physics_process(false)
	h.root.add_child(wreck)
	wreck.global_position = T + Vector2(0.0, 200.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var t := TURRET_SCENE.instantiate() as DefenseTurret
	t.variant = ROCKET
	(t.get_node("Brain") as DefenseTurretBrain).start_engaged = true
	t.position = T
	h.root.add_child(t)
	var fired: Array = []
	_rocket_mount(t).round_fired.connect(func(p: Node2D) -> void: fired.append(p))
	var fires: bool = await _physics_frames_until(240, func() -> bool: return not fired.is_empty())
	assert_true(fires, "%s: a rocket battery fires past the wreck within 4 s" % mode)
	assert_true(is_instance_valid(wreck), "%s: the wreck was still between them" % mode)


func test_rockets_persist_after_the_turret_dies_and_never_hit_it_real_physics(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 500.0)
	var t := TURRET_SCENE.instantiate() as DefenseTurret
	t.variant = ROCKET
	(t.get_node("Brain") as DefenseTurretBrain).start_engaged = true
	t.position = T
	h.root.add_child(t)
	var m := _rocket_mount(t)
	var fired: Array = []
	var armed_at_launch: Array = []
	m.round_fired.connect(func(p: Node2D) -> void:
		fired.append(p)
		armed_at_launch.append((p as EnemyRocket).is_armed()))
	var launched: bool = await _physics_frames_until(300, func() -> bool: return fired.size() >= 2)
	assert_true(launched, "%s: a salvo leaves" % mode)
	var rocket := fired[0] as EnemyRocket
	assert_false(armed_at_launch[0], "%s: a rocket is not armed on the muzzle (its host is in the way)" % mode)
	var max_hp := t.health.max_health
	var armed: bool = await _physics_frames_until(120, func() -> bool: return rocket.is_armed())
	assert_true(armed, "%s: it arms once clear of the hull" % mode)
	assert_eq(t.health.current_health, max_hp, "%s: it never hit its own turret" % mode)
	var pos_at_death := rocket.global_position
	t.free()
	await _physics_frames_until(30, func() -> bool: return false)
	assert_true(is_instance_valid(rocket) and rocket.is_inside_tree(), "%s: the rocket outlives its turret" % mode)
	assert_ne(rocket.global_position, pos_at_death, "%s: and keeps flying" % mode)
	# Its own `expired` now frees it (the pool handed it over): still exactly one owner.
	var rocket_id := rocket.get_instance_id()
	rocket.expired.emit()
	var freed: bool = await _physics_frames_until(10, func() -> bool: return not is_instance_valid(instance_from_id(rocket_id)))
	assert_true(freed, "%s: and is freed on expiry" % mode)


func test_power_down_stops_a_rocket_battery_mid_glow_or_mid_salvo_and_never_restarts(mode: String = use_parameters(MODES)) -> void:
	for mid_salvo in [false, true]:
		var label := "%s %s" % [mode, "mid-salvo" if mid_salvo else "mid-glow"]
		var h = _world(mode)
		h.player.global_position = T + Vector2(0.0, 500.0)
		var t := _beam_turret(h, ROCKET)
		var m := _rocket_mount(t)
		var clock := [0.0]
		var log := _rocket_log(m, clock)
		if mid_salvo:
			assert_true(_run_until(t, clock, 300, func() -> bool: return log.size() == 1), "%s: the first rocket leaves" % label)
		else:
			assert_true(_run_until(t, clock, 300, func() -> bool: return m.phase() == TurretMount.Phase.TELEGRAPH), "%s: the glow starts" % label)
		var first := log.size()
		var in_flight: Array = log.map(func(e: Dictionary) -> Node: return e["rocket"])
		t.set_powered(false)
		assert_eq(m.phase(), TurretMount.Phase.UNPOWERED, "%s: UNPOWERED" % label)
		assert_eq(_light(t).get_state(), StateLight.State.OFF, "%s: light OFF" % label)
		for i in 900:
			t._physics_process(DT)
		assert_eq(log.size(), first, "%s: no further rocket, ever" % label)
		for rocket in in_flight:
			assert_true(is_instance_valid(rocket), "%s: a rocket already out is unaffected" % label)
		h.root.free()


func test_the_pulse_ring_builds_a_mount_child_ring_set_up_for_the_turret_group(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var t := _beam_turret(h, RING)
	var m := _ring_mount(t)
	assert_not_null(m, "%s: the slot holds a pulse ring mount" % mode)
	var ring := m.ring()
	assert_eq(ring.get_parent(), m, "%s: the ring is a mount child" % mode)
	assert_eq(m.pool_specs().size(), 0, "%s: a ring mount builds no pools" % mode)
	assert_eq(float(_mx(RING, &"trigger_range")), 300.0, "%s: trigger range 300" % mode)
	assert_eq(ring.telegraph_seconds, float(_rx(&"telegraph_seconds")), "%s: the ring scene's own telegraph" % mode)
	assert_false(m.fires_past_cover(), "%s: holds fire without line of sight" % mode)
	assert_eq(m.owner_group(), t.owner_group())
	assert_eq(ring.global_position, m.global_position, "%s: centred on the mount, not the muzzle" % mode)


func test_no_ring_with_the_player_at_301_px_a_ring_at_299_and_a_cooldown_between(mode: String = use_parameters(MODES)) -> void:
	var trigger: float = _mx(RING, &"trigger_range")
	var cooldown: float = _mx(RING, &"cooldown_seconds")
	var h = _world(mode)
	h.player.global_position = T + Vector2(trigger + 1.0, 0.0)
	var t := _beam_turret(h, RING)
	var m := _ring_mount(t)
	var clock := [0.0]
	var times: Array = []
	var phases := {}
	m.ring().phase_changed.connect(func(p: int) -> void:
		if p == EnergyRing.Phase.TELEGRAPH:
			times.append(clock[0])
		if p == EnergyRing.Phase.FADE:
			phases[times.size()] = clock[0])
	for i in 240:
		clock[0] += DT
		t._physics_process(DT)
	assert_eq(m.ring().phase(), EnergyRing.Phase.OFF, "%s: nothing at 301 px" % mode)
	assert_eq(times.size(), 0)
	h.player.global_position = T + Vector2(trigger - 1.0, 0.0)
	var light_in_telegraph := [-1]
	_run_until(t, clock, 120, func() -> bool:
		if m.ring().phase() == EnergyRing.Phase.TELEGRAPH:
			light_in_telegraph[0] = _light(t).get_state()
		return times.size() >= 1 and m.ring().phase() == EnergyRing.Phase.EXPANDING)
	assert_eq(times.size(), 1, "%s: a ring at 299 px" % mode)
	assert_eq(light_in_telegraph[0], StateLight.State.CHARGING, "%s: light CHARGING during the telegraph" % mode)
	assert_eq(m.phase(), TurretMount.Phase.FIRE, "%s: FIRE while the band expands" % mode)
	_run_until(t, clock, 600, func() -> bool: return times.size() >= 2)
	assert_eq(times.size(), 2, "%s: and again after the cooldown" % mode)
	assert_almost_eq(float(times[1]) - float(phases[1]), cooldown, 2.0 * DT, "%s: the cooldown counts from the end of the expansion" % mode)
	assert_almost_eq(float(phases[1]) - float(times[0]), float(_rx(&"telegraph_seconds")) + float(_rx(&"max_radius")) / float(_rx(&"ring_speed")) - float(_rx(&"band")) * 0.5 / float(_rx(&"ring_speed")), 3.0 * DT, "%s: telegraph then expansion" % mode)


func test_a_ring_hurts_outsiders_on_its_path_once_and_never_its_own_group(mode: String = use_parameters(MODES)) -> void:
	var damage: int = _rx(&"damage")
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 250.0)
	var t := _beam_turret(h, RING)
	var m := _ring_mount(t)
	# Four outsiders round the ring: the two gaps are 180 degrees apart and 45 wide, so at least two of the four are outside both.
	var foes: Array = []
	for angle in [0.0, 90.0, 180.0, 270.0]:
		foes.append(_victim(h, T + Vector2.from_angle(deg_to_rad(angle)) * 150.0))
	var mates: Array = []
	for angle in [45.0, 135.0, 225.0, 315.0]:
		var mate := _victim(h, T + Vector2.from_angle(deg_to_rad(angle)) * 150.0)
		mate.add_to_group(t.owner_group())
		mates.append(mate)
	var record: Array = []
	m.ring().target_hit.connect(func(target: Node2D, dmg: int) -> void: record.append([target, dmg]))
	var clock := [0.0]
	_run_until(t, clock, 400, func() -> bool: return m.ring().phase() == EnergyRing.Phase.FADE)
	for mate in mates:
		assert_eq(_hits_on(record, mate), 0, "%s: a member of the turret's group is never hit" % mode)
	assert_eq(t.health.current_health, t.health.max_health, "%s: nor the turret itself" % mode)
	var total := 0
	for foe in foes:
		var n := _hits_on(record, foe)
		assert_lte(n, 1, "%s: never twice" % mode)
		total += n
	assert_gte(total, 2, "%s: the ring hurt the outsiders outside its gaps" % mode)
	for entry: Array in record:
		assert_eq(entry[1], damage, "%s: for the ring's damage" % mode)


func test_power_down_cancels_a_ring_telegraph_or_fades_an_expanding_ring_and_never_restarts(mode: String = use_parameters(MODES)) -> void:
	for expanding in [false, true]:
		var label := "%s %s" % [mode, "EXPANDING" if expanding else "TELEGRAPH"]
		var h = _world(mode)
		h.player.global_position = T + Vector2(100.0, 0.0)
		var t := _beam_turret(h, RING)
		var m := _ring_mount(t)
		var ring := m.ring()
		var foes: Array = []
		for angle in [0.0, 90.0, 180.0, 270.0]:
			foes.append(_victim(h, T + Vector2.from_angle(deg_to_rad(angle)) * 200.0))
		var record: Array = []
		ring.target_hit.connect(func(target: Node2D, _dmg: int) -> void: record.append(target))
		var clock := [0.0]
		var want: int = EnergyRing.Phase.EXPANDING if expanding else EnergyRing.Phase.TELEGRAPH
		assert_true(_run_until(t, clock, 300, func() -> bool: return ring.phase() == want), "%s: reaches the phase" % label)
		var before := record.size()
		t.set_powered(false)
		assert_eq(ring.phase(), EnergyRing.Phase.FADE if expanding else EnergyRing.Phase.OFF, "%s: stopped at once" % label)
		assert_eq(m.phase(), TurretMount.Phase.UNPOWERED, "%s: UNPOWERED" % label)
		assert_eq(_light(t).get_state(), StateLight.State.OFF, "%s: light OFF" % label)
		for i in 600:
			t._physics_process(DT)
		assert_eq(record.size(), before, "%s: no hit after power-down" % label)
		if not expanding:
			assert_eq(before, 0, "%s: a cancelled telegraph never hurt" % label)
		assert_eq(ring.phase(), EnergyRing.Phase.OFF, "%s: never restarts" % label)
		assert_false(ring.is_lethal())
		h.root.free()


# ── 19. The heavy emplacement (Phase 8 t11; plan §2.9) ──────────────────────────────────────────────────────────────
#
# The same `DefenseTurret` root and brain on its own scene and config, with two slots: a BEAM_CANNON at (0, -30) and a BURST_CANNON at (0, 34),
# each slot retuning its mount to 1.2 rad/s. Hand-ticked in both harnesses like the rows above.

const HEAVY_SCENE: PackedScene = preload("res://assault/scenes/enemies/heavy_emplacement/heavy_emplacement.tscn")
const HEAVY_CONFIG: DefenseTurretConfig = preload("res://assault/scenes/enemies/heavy_emplacement/heavy_emplacement_config.tres")  # read only


func _heavy(h, engaged: bool = true, seed_value: int = 4242) -> DefenseTurret:
	var t := HEAVY_SCENE.instantiate() as DefenseTurret
	var brain := t.get_node("Brain") as DefenseTurretBrain
	brain.start_engaged = engaged
	brain.rng_seed = seed_value
	t.position = T
	h.root.add_child(t)
	t.set_physics_process(false)
	(t.get_node("AssaultDrift") as AssaultDrift).set_physics_process(false)
	return t


func _heavy_beam(t: DefenseTurret) -> BeamTurretMount:
	return t.mounts()[0] as BeamTurretMount


func _heavy_burst(t: DefenseTurret) -> BurstCannonMount:
	return t.mounts()[1] as BurstCannonMount


func test_the_heavy_emplacement_is_a_turret_with_two_mounts_on_a_64_px_body(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var t := _heavy(h, false)
	assert_eq(t.get_script(), load("res://assault/scenes/enemies/defense_turret/defense_turret.gd"), "%s: the same root script as the standard turret" % mode)
	assert_eq(t.mounts().size(), 2, "%s: two mounts" % mode)
	assert_true(t.mounts()[0] is BeamTurretMount and t.mounts()[1] is BurstCannonMount, "%s: beam cannon then burst cannon" % mode)
	var beam_slot := t.get_node("MountSlots").get_child(0) as TurretMountSlot
	var burst_slot := t.get_node("MountSlots").get_child(1) as TurretMountSlot
	assert_eq(beam_slot.variant, TurretMount.Variant.BEAM_CANNON)
	assert_eq(burst_slot.variant, TurretMount.Variant.BURST_CANNON)
	assert_eq(beam_slot.position, Vector2(0.0, -30.0), "%s: beam cannon at (0, -30)" % mode)
	assert_eq(burst_slot.position, Vector2(0.0, 34.0), "%s: burst cannon at (0, 34)" % mode)
	assert_eq(t.mounts()[0].get_parent(), beam_slot)
	assert_eq(t.mounts()[1].get_parent(), burst_slot)
	var body := (t.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	var hurt := (t.get_node("HurtBox/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	assert_eq(body.radius, 64.0, "%s: body r 64" % mode)
	assert_same(hurt, body, "%s: one shape shared by body and hurtbox" % mode)
	assert_null(t.get_node_or_null("ContactHitBox"), "%s: no contact hitbox" % mode)
	assert_eq(t.rotation, 0.0)
	assert_false(t.is_ai_driven(), "%s: no mover" % mode)
	assert_false(t.is_laser_blocking())
	assert_eq(t.owner_group(), t.mounts()[0].owner_group(), "%s: the mounts share the turret's owner group" % mode)
	assert_eq(t.mounts()[0].owner_group(), t.mounts()[1].owner_group())
	assert_eq(t.rocket_clear_radius(), 64.0 + DefenseTurret.ROCKET_CLEARANCE, "%s: a rocket clears the 64 px hull, not the standard 28" % mode)
	assert_not_null(t.get_node_or_null("PulsePool_1"), "%s: the burst cannon's pool is a root child named for its slot index" % mode)


func test_each_heavy_mount_reads_a_turn_rate_of_1_2_and_the_standard_turret_keeps_its_own(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var t := _heavy(h, false)
	assert_eq(_heavy_beam(t).turn_rate, 1.2, "%s: beam cannon" % mode)
	assert_eq(_heavy_burst(t).turn_rate, 1.2, "%s: burst cannon" % mode)
	var standard := _turret(h)
	assert_eq(_mount(standard).turn_rate, 2.0, "%s: a standard turret's mount is untouched" % mode)


func test_hp_score_and_escape_flag_come_from_the_heavy_emplacements_own_config(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var t := _heavy(h, false)
	assert_eq(HEAVY_CONFIG.max_health, 260)
	assert_eq(HEAVY_CONFIG.score_value, 150)
	assert_false(HEAVY_CONFIG.counts_as_escape)
	assert_eq(HEAVY_CONFIG.collision_damage, 0)
	assert_eq(t.health.max_health, 260, "%s: HP from the .tres" % mode)
	assert_eq(t.health.current_health, 260)
	assert_eq(t.score_value, 150, "%s: score from the .tres" % mode)
	assert_false(t.counts_as_escape, "%s: never an escape" % mode)
	assert_ne(t.config, SHIPPED, "%s: not the standard turret's config" % mode)
	assert_ne(t.config, HEAVY_CONFIG, "%s: a private copy of its own" % mode)
	assert_eq(t.config.max_health, HEAVY_CONFIG.max_health)


func test_the_two_heavy_mounts_aim_independently(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 300.0)
	var t := _heavy(h)
	var beam := _heavy_beam(t)
	var burst := _heavy_burst(t)
	var clock := [0.0]
	assert_true(_run_until(t, clock, 300, func() -> bool: return beam.phase() == TurretMount.Phase.TELEGRAPH), "%s: the beam cannon telegraphs" % mode)
	var beam_frozen := beam.rotation
	var burst_before := burst.rotation
	h.player.global_position = T + Vector2(450.0, 150.0)
	var worst_beam := 0.0
	var worst_burst := 0.0
	var prev_beam := beam.rotation
	var prev_burst := burst.rotation
	for i in 20:
		t._physics_process(DT)
		worst_beam = maxf(worst_beam, absf(angle_difference(prev_beam, beam.rotation)))
		worst_burst = maxf(worst_burst, absf(angle_difference(prev_burst, burst.rotation)))
		prev_beam = beam.rotation
		prev_burst = burst.rotation
	assert_eq(beam.phase(), TurretMount.Phase.TELEGRAPH, "%s: still in its warning" % mode)
	assert_eq(beam.rotation, beam_frozen, "%s: the beam cannon holds the bearing it showed" % mode)
	assert_gt(absf(angle_difference(burst_before, burst.rotation)), 0.1, "%s: while the burst cannon follows the player" % mode)
	assert_lte(worst_burst, 1.2 * DT + 1e-6, "%s: at no more than its 1.2 rad/s" % mode)
	assert_lte(worst_beam, 1.2 * DT + 1e-6)
	# Each aims from its own pivot: their aim points are not one shared value.
	assert_ne(beam.aim_point(), burst.aim_point(), "%s: separate aim points" % mode)


func test_both_heavy_weapons_fire_in_one_engagement(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 300.0)
	var t := _heavy(h)
	var beam := _heavy_beam(t)
	var burst := _heavy_burst(t)
	var clock := [0.0]
	var rounds: Array = []
	_record(burst, clock, rounds)
	var lit := [false]
	beam.beam().phase_changed.connect(func(p: int) -> void:
		if p == EnemyBeam.Phase.ACTIVE:
			lit[0] = true)
	_run_until(t, clock, 600, func() -> bool: return lit[0] and rounds.size() >= 1)
	assert_true(lit[0], "%s: the beam cannon's beam went ACTIVE" % mode)
	assert_gt(rounds.size(), 0, "%s: the burst cannon fired" % mode)
	assert_ne(_light(t).get_state(), StateLight.State.OFF, "%s: one light shows the engagement" % mode)


func test_the_heavy_beam_never_hits_its_own_cannon_or_hull(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 300.0)
	var t := _heavy(h)
	var beam := _heavy_beam(t)
	var clock := [0.0]
	assert_true(_run_until(t, clock, 300, func() -> bool: return beam.phase() == TurretMount.Phase.TELEGRAPH), "%s: telegraphs" % mode)
	var hits := _hit_log(beam)
	var dir := Vector2.from_angle(beam.beam().global_rotation)
	var foe := _victim(h, beam.global_position + dir * 300.0)
	# The burst cannon's own mount shares the owner group; a mate in that group stands on the line too.
	var mate := _victim(h, beam.global_position + dir * 200.0)
	mate.add_to_group(t.owner_group())
	_run_until(t, clock, 120, func() -> bool: return beam.beam().phase() == EnemyBeam.Phase.FADE)
	assert_gt(_hits_on(hits, foe), 0, "%s: control: an outsider on the line is hit" % mode)
	assert_eq(_hits_on(hits, t), 0, "%s: the emplacement is not hit by its own beam" % mode)
	assert_eq(_hits_on(hits, mate), 0, "%s: nor anything in its owner group" % mode)
	assert_eq(t.health.current_health, 260, "%s: no damage taken" % mode)


func test_power_down_reaches_both_heavy_mounts(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = T + Vector2(0.0, 300.0)
	var t := _heavy(h)
	var beam := _heavy_beam(t)
	var burst := _heavy_burst(t)
	var clock := [0.0]
	assert_true(_run_until(t, clock, 300, func() -> bool: return beam.phase() == TurretMount.Phase.TELEGRAPH), "%s: telegraphs" % mode)
	var hits := _hit_log(beam)
	var outsider := _victim(h, beam.global_position + Vector2.from_angle(beam.beam().global_rotation) * 300.0)
	t.set_powered(false)
	assert_eq(beam.phase(), TurretMount.Phase.UNPOWERED, "%s: beam cannon down" % mode)
	assert_eq(burst.phase(), TurretMount.Phase.UNPOWERED, "%s: burst cannon down" % mode)
	assert_eq(_light(t).get_state(), StateLight.State.OFF)
	for i in 300:
		t._physics_process(DT)
	assert_eq(_hits_on(hits, outsider), 0, "%s: the cancelled telegraph never hurt" % mode)
	assert_eq(beam.beam().phase(), EnemyBeam.Phase.OFF)
	var rest := deg_to_rad(burst.rest_bearing_deg)
	assert_almost_eq(angle_difference(burst.rotation, rest), 0.0, deg_to_rad(0.5), "%s: both droop to rest" % mode)
	assert_almost_eq(angle_difference(beam.rotation, deg_to_rad(beam.rest_bearing_deg)), 0.0, deg_to_rad(0.5))


func test_assault_wave_builder_spawns_the_heavy_emplacement() -> void:
	var b := WaveBuilder.new()
	var w := b.wave(0.0, [b.heavy_emplacement().at(0.0, -100.0)])
	assert_eq(w.entries[0].ship_scene.resource_path, WaveBuilder.HEAVY_EMPLACEMENT)
	assert_eq(WaveBuilder.HEAVY_EMPLACEMENT, "res://assault/scenes/enemies/heavy_emplacement/heavy_emplacement.tscn")
