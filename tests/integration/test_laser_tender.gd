## The Laser Tender and Attack B: a V-launch into a moving wall (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.13; task plan
## docs/plans/cmvqw0vnz018nqs2xv56q6a0a/3-plan.md; Phase 8 t13). INTENT tests.
##
## Rows run in both harnesses (`tests/helpers/enemy_ai_harness.gd`) unless the name says `assault_` / `open_space_`. They are hand-ticked: each tick
## calls the tender's `_physics_process(DT)`, then every live drone it launched (A before B, as on real physics), putting each at `before + velocity *
## DT`, then moves the stub by its velocity. The tender and every launched drone have their body `collision_mask` cleared (t12's finding: with no
## physics step between hand ticks the broadphase is stale). The stub is the harness player with a 14 px `HurtBox`. Numbers come from
## `laser_tender_config.tres`, `twin_laser_drone_config.tres` (both preloaded, read only) and `twin_beam.tscn` (`EnemyBeamScenes`), never typed.
##
## Geometry: Open Space P = (640, 360), tender at `P + (0, -preferred_range)` (it HOLDs and starts LAUNCH on its first tick); Assault P = (640, 600),
## tender at its hold point (in the band, so it launches on the first eligible tick). Rows 13b and 15's boundary spawn it from above instead.
##
## **Shared recordings (gate time):** one Attack B run per setup key, memoised in `_cache` as plain data (this script's instance is reused for every
## test in it), read by rows 4/5, 7, 8, 9, 12 and 13. The real-physics row runs at the 8x clock.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const TENDER: PackedScene = preload("res://assault/scenes/enemies/laser_tender/laser_tender.tscn")
const CONFIG: LaserTenderConfig = preload("res://assault/scenes/enemies/laser_tender/laser_tender_config.tres")  # read only
const DRONE_CONFIG: TwinLaserDroneConfig = preload("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone_config.tres")  # read only
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const BEAM_SCRIPT: Script = preload("res://assault/scenes/projectiles/enemy_beams/enemy_beam.gd")

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const P_OPEN := Vector2(640.0, 360.0)
const P_ASSAULT := Vector2(640.0, 600.0)
const LETHAL := 10000
const STUB_RADIUS := 14.0
const FIXTURE_HP := 100
## Two ticks of slack on a summed-delta bound (the plan's `_TICK_SLACK`).
const TICK_SLACK := 2.0 / 60.0
const _SPEEDUP := 8
const RIG_LAUNCHED := TwinLaserPair.Phase.LAUNCHED

## The test clock (s), advanced by `_step`.
var _t: float = 0.0
## The drones the current scenario's tender launched, in launch order (A, B, A2, B2...): `_step` ticks the live ones.
var _drones: Array = []
## Drones `_step` skips (held away).
var _held: Array = []
var _tick_tender: bool = true
## Memoised recordings (plain data), keyed by setup.
var _cache: Dictionary = {}
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_each() -> void:
	_t = 0.0
	_drones = []
	_held = []
	_tick_tender = true


func after_each() -> void:
	_restore_clock()


func _scale_clock() -> void:
	if _clock_scaled:
		return
	_clock_scaled = true
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
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


# ── Helpers ─────────────────────────────────────────────────────────────────────────────────────────────────────────

func _world(mode: String, player_at: Vector2):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = player_at
	return h


func _p_of(mode: String) -> Vector2:
	return P_OPEN if mode == "open_space" else P_ASSAULT


func _beam_export(property: StringName) -> Variant:
	return EnemyBeamScenes.export_of(EnemyBeam.Kind.TWIN, property, BEAM_SCRIPT.get_property_default_value(property))


func _ticks(seconds: float) -> int:
	return ceili(seconds / DT - 1e-3)


func _circle(radius: float) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	return cs


## The harness player made a beam target: a 14 px `HurtBox` with no physics layers. Returns its hit log (the test clock of every hit).
func _arm_stub(h) -> Array:
	var hb := HurtBox.new()
	hb.name = "HurtBox"
	hb.collision_layer = 0
	hb.collision_mask = 0
	hb.add_child(_circle(STUB_RADIUS))
	h.player.add_child(hb)
	var hits: Array = []
	hb.received_damage.connect(func(_damage: int) -> void: hits.append(_t))
	return hits


## `fixture_enemy.tscn` made a beam victim: a 14 px circle on its `HurtBox` and group `enemies`; inert (no physics tick).
func _victim(h, at: Vector2, hp: int = FIXTURE_HP) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	e.get_node("HurtBox").add_child(_circle(STUB_RADIUS))
	e.add_to_group(&"enemies")
	var health := e.get_node("Health") as Health
	health.max_health = hp
	health.current_health = hp
	h.root.add_child(e)
	e.global_position = at
	e.set_physics_process(false)
	return e


func _hp(node: Node) -> int:
	return (node.get_node("Health") as Health).current_health


func _live(d: Variant) -> bool:
	return is_instance_valid(d) and not (d as Node).is_queued_for_deletion()


func _tender_brain(t: Node) -> LaserTenderBrain:
	return t.get_node("Brain") as LaserTenderBrain


func _drone_brain(d: Node) -> TwinLaserDroneBrain:
	return d.get_node("Brain") as TwinLaserDroneBrain


## A tender at [param at], hand-ticked unless [param real]. Every drone it launches joins `_drones` (and, hand-ticked, gets its mask cleared).
func _tender(h, at: Vector2, real: bool = false, rng_seed: int = 11) -> LaserTender:
	var t := TENDER.instantiate() as LaserTender
	(t.get_node("Brain") as EnemyBrain).rng_seed = rng_seed
	t.position = at
	h.root.add_child(t)
	if not real:
		t.set_physics_process(false)
		t.collision_mask = 0
	_tender_brain(t).launched.connect(_on_launched.bind(real))
	return t


func _on_launched(rig: TwinLaserPair, real: bool) -> void:
	for d: Node2D in [rig.drone_a, rig.drone_b]:
		_drones.append(d)
		if not real:
			d.set_physics_process(false)
			(d as CharacterBody2D).collision_mask = 0


func _hand_tick(body: CharacterBody2D) -> void:
	var before := body.global_position
	body._physics_process(DT)
	if _live(body):
		body.global_position = before + body.velocity * DT


## One hand tick: the tender, then every live drone it launched that is not held (A before B; drones launched this tick get their first tick
## here too), then the stub moves by its velocity.
func _step(h, tender: Node) -> void:
	_t += DT
	if _tick_tender and _live(tender):
		_hand_tick(tender as CharacterBody2D)
	for d: Variant in _drones.duplicate():
		if _live(d) and not _held.has(d):
			_hand_tick(d as CharacterBody2D)
	h.player.global_position += h.player.velocity * DT


## Steps until [param done] holds or [param max_ticks] pass; true when it held.
func _run(h, tender: Node, max_ticks: int, done: Callable) -> bool:
	for i in max_ticks:
		_step(h, tender)
		if done.call():
			return true
	return false


func _kill(n: Node) -> void:
	(n.get_node("HurtBox") as HurtBox).received_damage.emit(LETHAL)


## The corridor's `inner_rect()` (Assault), as a fresh `AssaultCorridorConstraint` reports it; an empty rect in Open Space.
func _constraint_rect(h) -> Rect2:
	if not h.is_assault:
		return Rect2()
	var c := (h.root.get_node("ArenaCamera") as ArenaCamera).enemy_movement_constraint()
	return c.inner_rect()


func _view(h) -> Rect2:
	return EnemyWorld.view_rect(get_tree())


## Assault: where the tender holds for a player at [param p] (plan §2.13: the upper band, `2R` inside the inner rect, clear of the player).
func _hold_point(h, p: Vector2) -> Vector2:
	var r := _constraint_rect(h)
	var reach := 2.0 * 40.0
	var y := minf(_view(h).position.y + CONFIG.assault_hold_depth, p.y - reach - LaserTenderBrain.HOLD_CLEARANCE)
	return Vector2(clampf(p.x, r.position.x + reach, r.end.x - reach), clampf(y, r.position.y + reach, r.end.y - reach))


func _spawn_point(h, mode: String) -> Vector2:
	if mode == "open_space":
		return P_OPEN + Vector2(0.0, -CONFIG.preferred_range)
	return _hold_point(h, P_ASSAULT)


## Every gap between two hits in [param hits] is at least `rehit_interval`.
func _gaps_ok(hits: Array) -> bool:
	var rehit := float(_beam_export(&"rehit_interval"))
	for i in range(1, hits.size()):
		if float(hits[i]) - float(hits[i - 1]) + 1e-6 < rehit:
			return false
	return true


## The Attack B advance a test expects (task plan "The rig"): min((centre - P) . n, standoff) + overshoot, capped in Assault by the room the
## centre has along -n inside the inner rect inset by `slot_tolerance`.
func _expected_advance(centre: Vector2, n: Vector2, p: Vector2, rect: Rect2) -> float:
	var d := minf(maxf((centre - p).dot(n), 0.0), DRONE_CONFIG.standoff) + DRONE_CONFIG.overshoot
	if rect.has_area():
		var r := rect.grow(-DRONE_CONFIG.slot_tolerance)
		var dir := -n
		var room := INF
		if dir.x > 1e-6:
			room = minf(room, (r.end.x - centre.x) / dir.x)
		elif dir.x < -1e-6:
			room = minf(room, (r.position.x - centre.x) / dir.x)
		if dir.y > 1e-6:
			room = minf(room, (r.end.y - centre.y) / dir.y)
		elif dir.y < -1e-6:
			room = minf(room, (r.position.y - centre.y) / dir.y)
		d = minf(d, maxf(room, 0.0))
	return d


func _angle_deg(a: Vector2, b: Vector2) -> float:
	return rad_to_deg(absf(a.angle_to(b)))


# ── The shared Attack B recording ───────────────────────────────────────────────────────────────────────────────────

## Setup keys: "<mode>:<stub>" with stub one of `still`, `toward` (200 px/s at the tender), `cross` (200 px/s along +x), `cross_stop` (+x until
## the launch, then still), `runner` (still until TELEGRAPH, then 360 px/s along the wall's axis toward the nearer end). `still` setups also place
## row 12's victim and move the tender onto the advance path at the latch (it is no longer ticked then).
func _record(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var mode := key.get_slice(":", 0)
	var stub := key.get_slice(":", 1)
	var p := _p_of(mode)
	var h = _world(mode, p)
	var hits := _arm_stub(h)
	var tender := _tender(h, _spawn_point(h, mode))
	var brain := _tender_brain(tender)
	var rect := _constraint_rect(h)
	if stub == "toward":
		h.player.velocity = (tender.global_position - p).normalized() * 200.0
	elif stub == "cross" or stub == "cross_stop":
		h.player.velocity = Vector2(200.0, 0.0)
	var rec := {
		"key": key, "launch_entry_t": -1.0, "launch_t": -1.0, "light_bad": 0, "tow_refused_in_launch": false,
		"starts": [], "points": [], "dirs": [], "secs": [], "p_launch": Vector2.ZERO, "tender_launch_pos": Vector2.ZERO,
		"cradles_hidden": false, "owner_ok": false, "brains_launched": false, "after_03": [Vector2.ZERO, Vector2.ZERO],
		"at_land": [Vector2.INF, Vector2.INF], "flown_at_form": [-1.0, -1.0], "latch_sep": -1.0, "latched": Vector2.ZERO,
		"centre": Vector2.ZERO, "axis": Vector2.ZERO, "normal": Vector2.ZERO, "max_err": 0.0, "strained_ticks": 0, "frame_changes": 0,
		"telegraph_ticks": 0, "advance_ticks": 0, "ended": false, "hits": hits, "outside": 0, "sign_change": false, "victim_lost": 0,
		"tender_lost": 0, "tender_in_group": false, "view": _view(h), "rect": rect, "tender_phase_after_launch": -1,
		"tender_released_after_launch": false, "tow_after_launch": false,
	}
	var tender_hp0 := _hp(tender)
	var victim: BaseEnemy = null
	var victim_hp0 := 0
	var rig: TwinLaserPair = null
	var frame: Array = []
	var prev_rig_phase := -1
	var prev_signed := 0.0
	for i in _ticks(9.0):
		_step(h, tender)
		if rec["launch_entry_t"] < 0.0 and brain.phase == LaserTenderBrain.Phase.LAUNCH:
			rec["launch_entry_t"] = _t
			rec["tow_refused_in_launch"] = not tender.accept_tow(Vector2(50.0, 0.0))
		if rig == null:
			if not _drones.is_empty():
				rig = tender.pair()
				rec["launch_t"] = _t
				rec["p_launch"] = h.player.global_position - h.player.velocity * DT  # the points were planned before this tick's stub move
				rec["tender_launch_pos"] = tender.global_position
				for d: Node2D in [rig.drone_a, rig.drone_b]:
					(rec["starts"] as Array).append(d.global_position - d.velocity * DT)
					(rec["points"] as Array).append(rig.launch_point_of(d))
					(rec["dirs"] as Array).append(rig.launch_dir_of(d))
					(rec["secs"] as Array).append(rig.launch_seconds_of(d))
				rec["cradles_hidden"] = not (tender.get_node("CradleL/DockedDrone") as CanvasItem).visible \
						and not (tender.get_node("CradleR/DockedDrone") as CanvasItem).visible
				rec["owner_ok"] = tender.is_in_group(rig.owner_group) and rig.drone_a.is_in_group(rig.owner_group) \
						and rig.drone_b.is_in_group(rig.owner_group)
				rec["brains_launched"] = _drone_brain(rig.drone_a).phase == TwinLaserDroneBrain.Phase.LAUNCHED \
						and _drone_brain(rig.drone_b).phase == TwinLaserDroneBrain.Phase.LAUNCHED
				rec["tender_phase_after_launch"] = brain.phase
				rec["tender_released_after_launch"] = (tender.get_node("EnemyMover") as EnemyMover).constraint_released()
				rec["tow_after_launch"] = tender.accept_tow(Vector2.ZERO)
				if stub == "cross_stop":
					h.player.velocity = Vector2.ZERO
				prev_rig_phase = rig.phase
			else:
				if brain.phase == LaserTenderBrain.Phase.LAUNCH and tender.state_light().get_state() != StateLight.State.CHARGING:
					rec["light_bad"] = int(rec["light_bad"]) + 1
				continue
		var since := _t - float(rec["launch_t"]) + DT  # ticks of drone motion so far (the launch tick moved them once)
		var ph := rig.phase
		for k in 2:
			var d: Node2D = rig.drone_a if k == 0 else rig.drone_b
			if not _live(d):
				continue
			if absf(since - 0.3) < DT * 0.5:
				(rec["after_03"] as Array)[k] = d.global_position - (rec["starts"] as Array)[k]
			if (rec["at_land"] as Array)[k] == Vector2.INF and since + 1e-6 >= float((rec["secs"] as Array)[k]) + DT:
				(rec["at_land"] as Array)[k] = d.global_position
			if ph == RIG_LAUNCHED:  # kept from the last LAUNCHED tick: the end of the capped boost
				(rec["flown_at_form"] as Array)[k] = d.global_position.distance_to((rec["starts"] as Array)[k])
			if rect.has_area() and not rect.has_point(d.global_position):
				rec["outside"] = int(rec["outside"]) + 1  # every tick from the launch to the end of ADVANCE (the loop stops there)
		if prev_rig_phase == TwinLaserPair.Phase.FORM and ph == TwinLaserPair.Phase.TELEGRAPH:
			rec["latch_sep"] = rig.drone_a.global_position.distance_to(rig.drone_b.global_position)
			rec["latched"] = rig.latched_player
			rec["centre"] = rig.centre
			rec["axis"] = rig.axis
			rec["normal"] = rig.normal
			prev_signed = (h.player.global_position - rig.centre).dot(rig.normal)
			if stub == "runner":
				var along: float = (h.player.global_position - rig.centre).dot(rig.axis)
				h.player.velocity = rig.axis * (1.0 if along >= 0.0 else -1.0) * 360.0
			if stub == "still":
				# Row 12: the tender onto the advance path at the stub's side, a victim beside the stub; both within the swept band.
				_tick_tender = false
				tender.global_position = h.player.global_position - rig.axis * 100.0
				victim = _victim(h, h.player.global_position + rig.axis * 60.0)
				victim_hp0 = _hp(victim)
				rec["tender_in_group"] = tender.is_in_group(rig.owner_group)
		if ph == TwinLaserPair.Phase.TELEGRAPH or ph == TwinLaserPair.Phase.ADVANCE:
			rec["max_err"] = maxf(float(rec["max_err"]), rig.separation_error())
			if rig.strained:
				rec["strained_ticks"] = int(rec["strained_ticks"]) + 1
			var f := [rig.centre, rig.axis, rig.normal]
			if frame.is_empty():
				frame = f
			elif f != frame:
				rec["frame_changes"] = int(rec["frame_changes"]) + 1
		if ph == TwinLaserPair.Phase.TELEGRAPH:
			rec["telegraph_ticks"] = int(rec["telegraph_ticks"]) + 1
		if ph == TwinLaserPair.Phase.ADVANCE:
			rec["advance_ticks"] = int(rec["advance_ticks"]) + 1
			var signed: float = (h.player.global_position - (rig.drone_a.global_position + rig.drone_b.global_position) * 0.5).dot(rig.normal)
			if signf(signed) != signf(prev_signed) and prev_signed != 0.0:
				rec["sign_change"] = true
		elif int(rec["advance_ticks"]) > 0:
			rec["ended"] = true
			break
		prev_rig_phase = ph
	if victim != null:
		rec["victim_lost"] = victim_hp0 - _hp(victim)
	rec["tender_lost"] = tender_hp0 - _hp(tender) if _live(tender) else 0
	rec["hits"] = hits.duplicate()
	_cache[key] = rec
	return rec


func _is_broadside(key: String) -> bool:
	return key.ends_with(":still") or key.ends_with(":toward")


# ── Structure ───────────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_tender_is_one_r40_circle_shared_by_body_hurtbox_and_contact_box_with_two_cradles() -> void:
	var h = _world("open_space", P_OPEN)
	var t := TENDER.instantiate() as LaserTender
	h.root.add_child(t)
	var body := t.get_node("CollisionShape2D") as CollisionShape2D
	var hurt := t.get_node("HurtBox/CollisionShape2D") as CollisionShape2D
	var contact := t.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D
	assert_true(body.shape is CircleShape2D, "a circle body")
	assert_eq((body.shape as CircleShape2D).radius, 40.0, "r 40")
	assert_same(hurt.shape, body.shape, "the hurtbox shares the body's shape")
	assert_same(contact.shape, body.shape, "and so does the contact box")
	assert_eq(contact.scale, body.scale)
	var box := t.get_node("ContactHitBox") as HitBox
	assert_eq([box.collision_layer, box.collision_mask], [256, 0], "COLLISION idiom: layer 256, mask 0")
	assert_eq(box.damage, CONFIG.collision_damage, "contact damage from the .tres")
	assert_eq(t.contact_profile.mode, ContactProfile.Mode.COLLISION)
	assert_not_null(t.state_light(), "a StateLight (the cradle light)")
	assert_true(t.get_node("EnemyMover") is EnemyMover, "a mover")
	assert_true(t.get_node("Brain") is LaserTenderBrain, "and its brain")
	var cradles := t.cradles()
	assert_eq(cradles.size(), 2)
	assert_eq(cradles[0].name, &"CradleL")
	assert_eq(cradles[0].position, Vector2(-30.0, 10.0))
	assert_eq(cradles[1].position, Vector2(30.0, 10.0))
	for c in cradles:
		var docked := c.get_node("DockedDrone") as CanvasItem
		assert_not_null(docked, "%s holds a docked-drone visual" % c.name)
		if docked != null:
			assert_true(docked.visible, "%s shows its docked drone" % c.name)
	assert_eq(t.docked_count(), 2, "two docked drones")
	assert_eq(t.launches(), 0)
	assert_null(t.pair())
	assert_eq(t.sprite_forward_angle, PI / 2.0, "nose-down")
	assert_true(t.is_in_group(&"enemies"), "joins enemies")


func test_the_shipped_config_wins_over_the_scene() -> void:
	var h = _world("open_space", P_OPEN)
	var t := TENDER.instantiate() as LaserTender
	h.root.add_child(t)
	assert_eq(t.health.max_health, CONFIG.max_health)
	assert_eq(t.health.current_health, CONFIG.max_health)
	assert_eq(t.score_value, CONFIG.score_value)
	var mover := t.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.max_speed, CONFIG.max_speed)
	assert_eq(mover.acceleration, CONFIG.acceleration)
	assert_eq([mover.hazard_avoidance, mover.hazard_margin, mover.hazard_resistance],
			[CONFIG.hazard_avoidance, CONFIG.hazard_margin, CONFIG.hazard_resistance], "the hazard profile")
	assert_same(_tender_brain(t).config, t.config, "the brain reads the tender's private copy")
	assert_true(t.counts_as_escape, "a ship, not a structure: drifting out is an escape")
	# §2.13's starting values, pinned once here (plus the six fields the task plan made data).
	var want := {
		"max_health": 160, "score_value": 120, "collision_damage": 15, "max_speed": 200.0, "acceleration": 400.0, "hazard_avoidance": 0.8,
		"hazard_margin": 24.0, "hazard_resistance": 0.3, "wreck_chance": 0.35, "wreck_size": 1, "preferred_range": 650.0,
		"launch_telegraph": 0.6, "launch_speed": 520.0, "launch_max_seconds": 1.4, "lead_time_max": 1.5, "rearm_seconds": 7.0,
		"assault_wall_lead": 180.0, "perceive_radius": 700.0, "lose_radius": 1600.0, "notice_time": 0.35, "idle_radius": 160.0,
		"idle_speed": 0.5, "engage_seconds": 10.0, "exit_speed": 380.0, "standing_lead": 120.0, "strafe_speed_min": 60.0,
		"range_tolerance": 80.0, "arc_rate": 0.12, "dock_radius": 72.0, "assault_hold_depth": 140.0,
	}
	for k: String in want:
		assert_almost_eq(float(CONFIG.get(k)), float(want[k]), 1e-6, k)


func test_the_phase_enums_are_declared_in_full_and_in_order() -> void:
	assert_eq(LaserTenderBrain.Phase.keys(), ["APPROACH", "HOLD", "LAUNCH", "WAIT", "REARM", "DISENGAGE", "IDLE", "NOTICING", "RETURNING"])
	assert_eq(TwinLaserPair.Phase.keys(), ["FORM", "TELEGRAPH", "ADVANCE", "BREAK", "COLLAPSED", "WAIT", "LAUNCHED"])


# ── Launch (rows 4 and 5 share one launch per case) ─────────────────────────────────────────────────────────────────

func test_the_cradle_telegraph_shows_for_launch_telegraph_before_the_drones_leave_on_a_v_that_never_crosses(
		case: String = use_parameters(["open_space:still", "open_space:toward", "assault:still", "open_space:cross", "assault:cross"])) -> void:
	var rec := _record(case)
	# Row 4: the cradle telegraph.
	assert_almost_eq(float(rec["launch_entry_t"]), DT, 1e-6, "%s: LAUNCH on the first tick" % case)
	assert_true(rec["tow_refused_in_launch"], "%s: the cradle telegraph refuses a tow" % case)
	assert_eq(int(rec["light_bad"]), 0, "%s: the cradle light is CHARGING on every LAUNCH tick" % case)
	assert_almost_eq(float(rec["launch_t"]) - float(rec["launch_entry_t"]), CONFIG.launch_telegraph, DT + 1e-6,
			"%s: the drones appear launch_telegraph after LAUNCH entry" % case)
	assert_true(rec["cradles_hidden"], "%s: both cradles empty" % case)
	assert_true(rec["owner_ok"], "%s: both drones and the tender in the rig's owner group" % case)
	assert_true(rec["brains_launched"], "%s: both brains LAUNCHED after their first tick" % case)
	# Row 5: the V.
	var starts: Array = rec["starts"]
	var points: Array = rec["points"]
	var dirs: Array = rec["dirs"]
	var secs: Array = rec["secs"]
	assert_eq(points.size(), 2, "%s: two launch points" % case)
	if points.size() != 2:
		return
	assert_null(Geometry2D.segment_intersects_segment(starts[0], points[0], starts[1], points[1]), "%s: the legs never cross" % case)
	var angle := _angle_deg(dirs[0], dirs[1])
	gut.p("%s: V angle %.1f deg, legs %.0f / %.0f px, boosts %.2f / %.2f s" % [case, angle, (starts[0] as Vector2).distance_to(points[0]),
			(starts[1] as Vector2).distance_to(points[1]), secs[0], secs[1]])
	assert_gt(angle, 0.0, "%s: diverging" % case)
	assert_lt(angle, 160.0, "%s: never anti-parallel" % case)
	if _is_broadside(case):
		assert_gt(angle, 20.0, "%s: a broadside wall gives §2.13's V" % case)
	for k in 2:
		var moved: Vector2 = (rec["after_03"] as Array)[k]
		assert_gt(moved.length(), 0.0, "%s: drone %d moved in 0.3 s" % [case, k])
		assert_lt(_angle_deg(moved, dirs[k]), 5.0, "%s: drone %d's leg is straight" % [case, k])
		if float(secs[k]) + 1e-6 < CONFIG.launch_max_seconds:
			var landed: Vector2 = (rec["at_land"] as Array)[k]
			assert_lte(landed.distance_to(points[k]), DRONE_CONFIG.slot_tolerance, "%s: drone %d is on its point a tick after its boost" % [case, k])
		else:
			assert_almost_eq(float((rec["flown_at_form"] as Array)[k]), CONFIG.launch_speed * CONFIG.launch_max_seconds,
					CONFIG.launch_speed * DT, "%s: drone %d's capped leg flew launch_speed * launch_max_seconds" % [case, k])
	assert_almost_eq(float(rec["latch_sep"]), DRONE_CONFIG.rig_length, DRONE_CONFIG.length_tolerance, "%s: L apart at the latch" % case)


func test_open_space_points_lie_on_the_predicted_path_across_the_heading(case: String = use_parameters(["moving", "standing"])) -> void:
	var rec := _record("open_space:cross" if case == "moving" else "open_space:still")
	var centre: Vector2 = rec["centre"]
	var axis: Vector2 = rec["axis"]
	var p_l: Vector2 = rec["p_launch"]
	if case == "moving":
		assert_lte(absf(centre.y - p_l.y), 30.0, "the centre lies on the stub's path line")
		assert_gt(centre.x, p_l.x, "ahead of where the stub was at the launch")
		assert_lte(absf(axis.dot(Vector2.RIGHT)), sin(deg_to_rad(5.0)), "the axis is across the heading")
	else:
		assert_almost_eq(centre, p_l + Vector2.UP * CONFIG.standing_lead, Vector2.ONE, "a standing stub: standing_lead ahead of its nose")
		var bearing := (p_l - (rec["tender_launch_pos"] as Vector2)).normalized()
		assert_lte(absf(axis.dot(bearing)), sin(deg_to_rad(5.0)), "the axis is across the tender's bearing")
	# Pure: the prediction horizon on a 360 px/s stub.
	var v := Vector2(360.0, 0.0)
	var near := LaserTenderBrain.open_space_points(P_OPEN, v, Vector2.UP, P_OPEN + Vector2(0.0, -650.0), DRONE_CONFIG.rig_length, CONFIG)
	var far := LaserTenderBrain.open_space_points(P_OPEN, v, Vector2.UP, P_OPEN + Vector2(0.0, -1000.0), DRONE_CONFIG.rig_length, CONFIG)
	assert_almost_eq((near[0] + near[1]) * 0.5, P_OPEN + v * (650.0 / CONFIG.launch_speed), Vector2.ONE * 0.01, "650 px: lead 1.25 s")
	assert_almost_eq((far[0] + far[1]) * 0.5, P_OPEN + v * CONFIG.lead_time_max, Vector2.ONE * 0.01, "1000 px: capped at lead_time_max")
	assert_almost_eq(LaserTenderBrain.lead_time(1000.0, CONFIG), CONFIG.lead_time_max, 1e-6, "not 1000 / 520 = 1.92 s")
	for pts: PackedVector2Array in [near, far]:
		assert_almost_eq(pts[0].distance_to(pts[1]), DRONE_CONFIG.rig_length, 1e-3, "always rig_length apart")


# ── Attack B: the wall (R8.24 for the V-launched wall) ──────────────────────────────────────────────────────────────

func test_attack_b_keeps_its_length_on_every_telegraph_and_advance_tick(
		case: String = use_parameters(["open_space:still", "open_space:cross", "assault:still", "assault:cross"])) -> void:
	var rec := _record(case)
	assert_true(rec["ended"], "%s: the advance ran to its end" % case)
	assert_gt(int(rec["telegraph_ticks"]), 0, "%s: it telegraphed" % case)
	gut.p("%s: worst separation error %.2f px over %d + %d ticks" % [case, rec["max_err"], rec["telegraph_ticks"], rec["advance_ticks"]])
	assert_lte(float(rec["max_err"]), DRONE_CONFIG.length_tolerance, "%s: L held on every TELEGRAPH / ADVANCE tick" % case)
	assert_eq(int(rec["strained_ticks"]), 0, "%s: never strained" % case)
	assert_eq(int(rec["frame_changes"]), 0, "%s: the frame is latched" % case)
	var points: Array = rec["points"]
	var centre: Vector2 = rec["centre"]
	var axis: Vector2 = rec["axis"]
	var normal: Vector2 = rec["normal"]
	assert_almost_eq(centre, ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5, Vector2.ONE * 1e-3, "%s: centre = mid(points)" % case)
	assert_almost_eq(axis, ((points[1] as Vector2) - (points[0] as Vector2)).normalized(), Vector2.ONE * 1e-4, "%s: axis A -> B" % case)
	var latched: Vector2 = rec["latched"]
	var ortho := axis.orthogonal()
	var want_n := ortho * (1.0 if (centre - latched).dot(ortho) >= 0.0 else -1.0)
	assert_almost_eq(normal, want_n, Vector2.ONE * 1e-4, "%s: n signed toward the line from the latched player" % case)
	var d := _expected_advance(centre, normal, latched, rec["rect"])
	assert_almost_eq(int(rec["advance_ticks"]), roundi(d / DRONE_CONFIG.advance_speed / DT), 1, "%s: the advance is %.0f px" % [case, d])


func test_the_wall_advances_at_a_standing_player_and_hits_it(mode: String = use_parameters(MODES)) -> void:
	var rec := _record("%s:still" % mode)
	assert_true(rec["sign_change"], "%s: the wall crossed the stub (it moved along -n toward it)" % mode)
	var hits: Array = rec["hits"]
	assert_gte(hits.size(), 1, "%s: the stub was hit" % mode)
	assert_true(_gaps_ok(hits), "%s: at most once per rehit_interval" % mode)


func test_a_player_who_runs_round_an_end_is_not_hit(mode: String = use_parameters(MODES)) -> void:
	var rec := _record("%s:runner" % mode)
	assert_true(rec["ended"], "%s: the advance ran to its end" % mode)
	assert_eq((rec["hits"] as Array).size(), 0, "%s: the runner was never hit" % mode)
	var control := _record("%s:still" % mode)
	assert_gte((control["hits"] as Array).size(), 1, "%s control: a still stub on the same setup is hit" % mode)


func test_the_tender_is_never_hit_by_its_pairs_beam(mode: String = use_parameters(MODES)) -> void:
	var rec := _record("%s:still" % mode)
	assert_true(rec["tender_in_group"], "%s: the tender is in the rig's owner group" % mode)
	assert_gt(int(rec["victim_lost"]), 0, "%s: the victim beside it on the advance path was hit" % mode)
	assert_eq(int(rec["tender_lost"]), 0, "%s: the tender never" % mode)


# ── One live pair, rearm, docking (Open Space) ──────────────────────────────────────────────────────────────────────

func test_no_launch_while_a_pair_lives_and_rearm_after_both_drones_die() -> void:
	var h = _world("open_space", P_OPEN)
	var tender := _tender(h, _spawn_point(h, "open_space"))
	var brain := _tender_brain(tender)
	assert_true(_run(h, tender, _ticks(1.0), func() -> bool: return tender.launches() == 1), "the first launch")
	var first := _drones.duplicate()
	_held = first.duplicate()  # left untouched: alive, the pair intact
	_run(h, tender, _ticks(CONFIG.rearm_seconds + 2.0), func() -> bool: return false)
	assert_eq(brain.phase, LaserTenderBrain.Phase.WAIT, "WAIT while the pair lives")
	assert_eq(tender.launches(), 1, "no second launch while it lives")
	assert_eq(tender.docked_count(), 0, "cradles empty")
	for d: Node in first:
		_kill(d)
	var died_at := _t
	_step(h, tender)
	assert_eq(brain.phase, LaserTenderBrain.Phase.REARM, "REARM on the next tick")
	var empty_until := [-1.0]
	assert_true(_run(h, tender, _ticks(CONFIG.rearm_seconds + CONFIG.launch_telegraph + 1.0), func() -> bool:
		if tender.launches() == 1 and tender.docked_count() == 0:
			empty_until[0] = _t
		return tender.launches() == 2), "a second pair")
	var second_at := _t
	gut.p("both died at %.3f s, cradles empty until %.3f s, second launch at %.3f s" % [died_at, empty_until[0], second_at])
	assert_gte(empty_until[0] - died_at, CONFIG.rearm_seconds - DT - 1e-6, "cradles empty for rearm_seconds")
	assert_gte(second_at - died_at, CONFIG.rearm_seconds + CONFIG.launch_telegraph - 1e-6, "no earlier than rearm + telegraph")
	assert_lte(second_at - died_at, CONFIG.rearm_seconds + CONFIG.launch_telegraph + TICK_SLACK, "and no later than that + slack")
	assert_eq(_drones.size(), 4, "a fresh pair")


func test_a_lone_surviving_drone_flies_home_and_docks(case: String = use_parameters(["at_once", "after_a_rearm"])) -> void:
	var h = _world("open_space", P_OPEN)
	var tender := _tender(h, _spawn_point(h, "open_space"))
	var brain := _tender_brain(tender)
	assert_true(_run(h, tender, _ticks(4.0), func() -> bool: return tender.pair() != null and tender.pair().phase == TwinLaserPair.Phase.FORM),
			"the first FORM tick")
	var a: Node2D = _drones[0]
	var b: Node2D = _drones[1]
	var a_died := [false]
	a.connect(&"died", func() -> void: a_died[0] = true)
	_kill(b)
	if case == "after_a_rearm":
		_held = [a]
		assert_true(_run(h, tender, _ticks(CONFIG.rearm_seconds + CONFIG.launch_telegraph + 0.5), func() -> bool: return tender.launches() == 2),
				"the tender rearmed and launched a second pair while A was held away")
		assert_eq(tender.docked_count(), 0, "cradles empty after the second launch")
		_held = []
	var t0 := _t
	assert_true(_run(h, tender, _ticks(6.0), func() -> bool: return not _live(a)), "A came home")
	gut.p("%s: A docked %.2f s after release" % [case, _t - t0])
	assert_false(a_died[0], "it docked, it did not die")
	if case == "at_once":
		assert_lt(_t - t0, 4.0, "within 4 s")
		assert_eq(tender.docked_count(), 1, "one drone docked")
		assert_true((tender.get_node("CradleL/DockedDrone") as CanvasItem).visible, "one DockedDrone shown")
		assert_false((tender.get_node("CradleR/DockedDrone") as CanvasItem).visible, "the other still empty")
		assert_eq(brain.phase, LaserTenderBrain.Phase.REARM, "the tender is rearming")
	else:
		assert_eq(tender.docked_count(), 1, "the old drone docks into the emptied cradles")
		assert_lte(tender.docked_count(), 2)


# ── Assault ─────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_assault_vertical_wall_for_a_strafing_player_horizontal_for_a_still_one(
		case: String = use_parameters(["cross_stop", "cross", "still"])) -> void:
	var rec := _record("assault:%s" % case)
	var axis: Vector2 = rec["axis"]
	var normal: Vector2 = rec["normal"]
	var centre: Vector2 = rec["centre"]
	var p_l: Vector2 = rec["p_launch"]
	if case == "still":
		assert_lt(absf(axis.y), 0.01, "a still player: a horizontal wall")
		assert_almost_eq(centre.y, p_l.y - DRONE_CONFIG.standoff, 1.0, "standoff above it")
		assert_almost_eq(normal, Vector2.UP, Vector2.ONE * 1e-4, "advancing down")
	else:
		assert_lt(absf(axis.x), 0.01, "%s: a strafing player: a vertical wall" % case)
		assert_almost_eq(centre.x, p_l.x + CONFIG.assault_wall_lead, 1.0, "%s: assault_wall_lead ahead along x" % case)
		if case == "cross_stop":
			assert_gt(normal.x, 0.99, "stopped: the wall is ahead and advances back at the player")
			assert_gte((rec["hits"] as Array).size(), 1, "and hits it")
		else:
			assert_lt(normal.x, -0.99, "still strafing: the stub is past the wall at the latch, which chases from behind")
			var latched: Vector2 = rec["latched"]
			var d := _expected_advance(centre, normal, latched, rec["rect"])
			assert_gt((centre - latched).dot(normal), 0.0, "the advance closes the distance to the stub")
			assert_almost_eq(int(rec["advance_ticks"]), roundi(d / DRONE_CONFIG.advance_speed / DT), 1, "an advance of %.0f px" % d)
	assert_eq(int(rec["outside"]), 0, "%s: both drones inside inner_rect() from the launch to the end of ADVANCE" % case)
	var view: Rect2 = rec["view"]
	assert_lte((rec["tender_launch_pos"] as Vector2).y, view.position.y + CONFIG.assault_hold_depth + LaserTenderBrain.HOLD_REACH,
			"%s: launched from the view's upper band" % case)


func test_assault_tender_from_above_reaches_its_band_and_launches_against_a_strafing_player() -> void:
	var h = _world("assault", P_ASSAULT)
	var inset := _constraint_rect(h).grow(-DRONE_CONFIG.slot_tolerance)
	h.player.global_position = Vector2(inset.position.x, P_ASSAULT.y)
	h.player.velocity = Vector2(360.0, 0.0)
	var tender := _tender(h, Vector2(1000.0, -200.0))
	var brain := _tender_brain(tender)
	var reversal := [-1.0]
	var hold_at := [-1.0]
	var closest := [INF]
	var launched := _run(h, tender, _ticks(CONFIG.engage_seconds), func() -> bool:
		var p: Vector2 = h.player.global_position
		if (p.x >= inset.end.x and h.player.velocity.x > 0.0) or (p.x <= inset.position.x and h.player.velocity.x < 0.0):
			h.player.velocity.x = -h.player.velocity.x
			if reversal[0] < 0.0:
				reversal[0] = _t
		if reversal[0] < 0.0:
			if brain.phase == LaserTenderBrain.Phase.APPROACH:
				closest[0] = minf(closest[0], tender.global_position.distance_to(_hold_point(h, p)))
			elif hold_at[0] < 0.0:
				hold_at[0] = _t
		return tender.launches() == 1)
	gut.p("band / HOLD at %.2f s, first reversal at %.2f s, closest approach to the hold point before it %.1f px, launch at %.2f s" %
			[hold_at[0], reversal[0], closest[0], _t])
	assert_true(launched, "it launches within engage_seconds")
	assert_lte(_t, CONFIG.engage_seconds, "inside its budget")
	assert_gt(hold_at[0], 0.0, "boundary: it reached the band (HOLD) before the stub's first reversal")
	assert_gt(closest[0], LaserTenderBrain.HOLD_REACH, "boundary: without ever coming within HOLD_REACH of the moving hold point")


func test_assault_one_launch_per_life_then_disengage() -> void:
	var h = _world("assault", P_ASSAULT)
	var tender := _tender(h, _spawn_point(h, "assault"))
	var brain := _tender_brain(tender)
	assert_true(_run(h, tender, _ticks(1.0), func() -> bool: return tender.launches() == 1), "it launches")
	var launched_at := _t
	assert_eq(brain.phase, LaserTenderBrain.Phase.DISENGAGE, "then DISENGAGE")
	assert_true((tender.get_node("EnemyMover") as EnemyMover).constraint_released(), "with the corridor released")
	var a: Node2D = _drones[0]
	var b: Node2D = _drones[1]
	assert_true(_run(h, tender, _ticks(5.0), func() -> bool: return not _live(tender)), "freed")
	assert_lt(_t - launched_at, 5.0, "outside the projectile world rect within 5 s")
	assert_eq(_drones.size(), 2, "one launch per life")
	var rig: TwinLaserPair = _drone_brain(a).pair if _live(a) else null
	assert_not_null(rig)
	if rig == null:
		return
	assert_true(_run(h, tender, _ticks(6.0), func() -> bool: return rig.advances_started == 1 and rig.phase != TwinLaserPair.Phase.ADVANCE),
			"the pair's one attack")
	_step(h, tender)
	for d in [a, b]:
		if _live(d):
			assert_eq(_drone_brain(d).phase, TwinLaserDroneBrain.Phase.DISENGAGE, "the drones disengage after their one ADVANCE")


func test_assault_budget_expiring_in_the_cradle_telegraph_lets_the_launch_finish(
		case: String = use_parameters(["mid_telegraph", "before_launch"])) -> void:
	var h = _world("assault", P_ASSAULT)
	var at := _spawn_point(h, "assault")
	if case == "before_launch":
		at += Vector2(0.0, -300.0)  # still in APPROACH when the budget runs out
	var tender := _tender(h, at)
	var engage := DT + 0.3 if case == "mid_telegraph" else 0.1
	tender.config.engage_seconds = engage
	var brain := _tender_brain(tender)
	var left_at := [-1.0]
	brain.phase_changed.connect(func(p: int) -> void:
		if p == LaserTenderBrain.Phase.DISENGAGE and left_at[0] < 0.0:
			left_at[0] = _t)
	var launch_at := [-1.0]
	brain.launched.connect(func(_rig: TwinLaserPair) -> void: launch_at[0] = _t)
	_run(h, tender, _ticks(2.0), func() -> bool: return left_at[0] >= 0.0)
	gut.p("%s: budget %.3f s, launch at %.3f s, DISENGAGE at %.3f s" % [case, engage, launch_at[0], left_at[0]])
	if case == "mid_telegraph":
		assert_gt(launch_at[0], engage, "the launch came after the budget ran out")
		assert_lte(launch_at[0], engage + CONFIG.launch_telegraph + TICK_SLACK, "no later than engage + launch_telegraph + slack")
		assert_almost_eq(left_at[0], launch_at[0], 1e-6, "then DISENGAGE")
	else:
		assert_almost_eq(left_at[0], engage, DT + 1e-6, "boundary: DISENGAGE at the budget's end")
		assert_lt(launch_at[0], 0.0, "and it never launches")
		_run(h, tender, _ticks(1.0), func() -> bool: return false)
		assert_eq(tender.launches() if _live(tender) else 0, 0, "not later either")


# ── Real physics (8x clock, masks intact) ───────────────────────────────────────────────────────────────────────────

## Samples the launched drones after every other node on each physics frame (high physics priority).
class _Probe extends Node:
	var tender: LaserTender
	var rig: TwinLaserPair
	var frames: int = 0
	var starts: Array = []
	var after_03: Array = [Vector2.ZERO, Vector2.ZERO]
	var landed: Array = [INF, INF]
	var flown_at_form: Array = [-1.0, -1.0]
	var in_tree_on_launch: bool = false
	## Per drone, on the launch tick: [the tender excepts it, it excepts the tender].
	var exceptions: Array = []
	var prev_phase: int = -1

	func on_launched(r: TwinLaserPair) -> void:
		rig = r
		frames = 0
		for d: Node2D in [r.drone_a, r.drone_b]:
			starts.append(d.global_position)
		in_tree_on_launch = r.drone_a.is_inside_tree() and r.drone_b.is_inside_tree() \
				and r.drone_a.is_in_group(&"enemies") and r.drone_b.is_in_group(&"enemies")
		for d: Node2D in [r.drone_a, r.drone_b]:
			exceptions.append([tender.get_collision_exceptions().has(d), (d as PhysicsBody2D).get_collision_exceptions().has(tender)])
		prev_phase = r.phase

	func _physics_process(_delta: float) -> void:
		if rig == null:
			return
		frames += 1
		var dt := 1.0 / 60.0
		for k in 2:
			var d: Node2D = rig.drone_a if k == 0 else rig.drone_b
			if not is_instance_valid(d):
				continue
			if frames == roundi(0.3 / dt):
				after_03[k] = d.global_position - (starts[k] as Vector2)
			if float(landed[k]) == INF and frames >= ceili(rig.launch_seconds_of(d) / dt - 1e-3) + 2:
				landed[k] = d.global_position.distance_to(rig.launch_point_of(d))
			if rig.phase == TwinLaserPair.Phase.LAUNCHED:
				flown_at_form[k] = d.global_position.distance_to(starts[k] as Vector2)
		prev_phase = rig.phase


class _Ticker extends Node:
	var fn: Callable

	func _physics_process(_delta: float) -> void:
		fn.call()


func test_on_real_physics_the_launch_flies_straight_out_of_the_tender(mode: String = use_parameters(MODES)) -> void:
	var p := _p_of(mode)
	var h = _world(mode, p)
	_scale_clock()
	var tender := _tender(h, _spawn_point(h, mode), true)
	var probe := _Probe.new()
	probe.tender = tender
	probe.process_physics_priority = 1000
	h.root.add_child(probe)
	_tender_brain(tender).launched.connect(probe.on_launched)
	if mode == "assault":
		var player: CharacterBody2D = h.player
		var ticker := _Ticker.new()
		ticker.fn = func() -> void: player.global_position += Vector2(200.0, 0.0) * DT
		player.velocity = Vector2(200.0, 0.0)
		h.root.add_child(ticker)
	for i in 60:
		await wait_physics_frames(4)
		if probe.rig != null and probe.frames > ceili(CONFIG.launch_max_seconds / DT) + 4:
			break
	assert_not_null(probe.rig, "%s: it launched" % mode)
	if probe.rig == null:
		return
	var rig := probe.rig
	assert_true(probe.in_tree_on_launch, "%s: both drones in the tree and in enemies on the launch tick" % mode)
	for k in 2:
		var d: Node2D = rig.drone_a if k == 0 else rig.drone_b
		if not is_instance_valid(d):
			fail_test("%s: drone %d is gone" % [mode, k])
			continue
		assert_eq(probe.exceptions[k], [true, true], "%s: drone %d and the tender except each other" % [mode, k])
		var moved: Vector2 = probe.after_03[k]
		gut.p("%s: drone %d moved %.1f px in 0.3 s at %.1f deg off its leg; landed %.1f px off its point" % [mode, k, moved.length(),
				_angle_deg(moved, rig.launch_dir_of(d)), float(probe.landed[k])])
		assert_lt(_angle_deg(moved, rig.launch_dir_of(d)), 5.0, "%s: drone %d flies straight out" % [mode, k])
		assert_gte(moved.length(), 0.8 * CONFIG.launch_speed * 0.3, "%s: not held by the tender's body" % mode)
		if rig.launch_seconds_of(d) + 1e-6 < CONFIG.launch_max_seconds:
			assert_lte(float(probe.landed[k]), DRONE_CONFIG.slot_tolerance, "%s: drone %d on its point" % [mode, k])
		else:
			assert_almost_eq(float(probe.flown_at_form[k]), CONFIG.launch_speed * CONFIG.launch_max_seconds, 2.0 * CONFIG.launch_speed * DT,
					"%s: drone %d's capped leg" % [mode, k])


# ── Through a real WaveManager (Assault) ────────────────────────────────────────────────────────────────────────────

func test_assault_wave_builder_spawns_a_laser_tender_through_a_real_wave_manager() -> void:
	var h = _world("assault", P_ASSAULT)
	var cam := h.root.get_node("ArenaCamera") as ArenaCamera
	cam.set_physics_process(false)
	var container := Node2D.new()
	h.root.add_child(container)
	var wm := WaveManager.new()
	wm.enemy_container = container
	h.root.add_child(wm)
	var at_spawn: Array = []
	var on_spawn := func(e: Node, _wave: int) -> void: at_spawn.append((e as Node2D).global_position)
	wm.enemy_spawned.connect(on_spawn)
	var b := WaveBuilder.new()
	var w := b.wave(0.0, [b.laser_tender().at(0.0, -100.0)])
	assert_eq(w.entries[0].ship_scene.resource_path, WaveBuilder.LASER_TENDER, "the tender's scene path")
	wm.load_section([w] as Array[WaveResource])
	for i in 4:
		await get_tree().process_frame
	var tenders := container.get_children().filter(func(c: Node) -> bool: return c is LaserTender)
	assert_eq(tenders.size(), 1, "one Laser Tender")
	assert_eq(at_spawn.size(), 1, "announced")
	if at_spawn.size() == 1:
		assert_almost_eq(at_spawn[0] as Vector2, cam.global_position + Vector2(0.0, -100.0) * ArenaCamera.WORLD_SCALE, Vector2.ONE * 0.01,
				"camera-relative design space")
