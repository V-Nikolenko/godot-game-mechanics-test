## Twin-Laser Drones and the `TwinLaserPair` rig, Attack A (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.12; task plan
## docs/plans/cmvqw0vnw018jqs2x5k4l6ahb/3-plan.md; Phase 8 t12). INTENT tests.
##
## Rows run in both harnesses (`tests/helpers/enemy_ai_harness.gd`) unless the name says `assault_` / `open_space_`. They are hand-ticked: each tick
## calls drone A's `_physics_process(DT)`, then drone B's (A leads, as on real physics, where A is added first), puts each at `before + velocity * DT`
## (off a physics frame `move_and_slide()` uses the frame delta), then moves the stub by its velocity. The stub is the harness player given a 14 px
## `HurtBox` (no physics layers: the beam's scan reads shapes, not physics). The wreck row runs on real physics at the 8x clock (a body has to stop on
## a body). Numbers are read from `twin_laser_drone_config.tres` (preloaded, read only) and `twin_beam.tscn` (`EnemyBeamScenes`), never typed.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const DRONE: PackedScene = preload("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone.tscn")
const SPAWN: PackedScene = preload("res://assault/scenes/enemies/twin_laser_drone/twin_laser_pair_spawn.tscn")
const CONFIG: TwinLaserDroneConfig = preload("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone_config.tres")  # read only
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const WRECK_LARGE: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_large.tscn")
const BEAM_SCRIPT: Script = preload("res://assault/scenes/projectiles/enemy_beams/enemy_beam.gd")
const SINGLE_WRITER: GDScript = preload("res://tests/integration/test_enemy_mover_single_writer.gd")
const RIG_SCRIPT_PATH := "res://assault/scenes/enemies/twin_laser_drone/twin_laser_pair.gd"
const SPAWN_SCRIPT_PATH := "res://assault/scenes/enemies/twin_laser_drone/twin_laser_pair_spawn.gd"
## t13: the Laser Tender holds launched drones too (t12 DECISIONS: any new non-brain file that holds a drone joins the no-motion sweep; review N6 adds its
## brain, which the single-writer gate sweeps only through `actor.` / `body.` / `self.`).
const TENDER_SCRIPT_PATH := "res://assault/scenes/enemies/laser_tender/laser_tender.gd"
const TENDER_BRAIN_SCRIPT_PATH := "res://assault/scenes/enemies/laser_tender/laser_tender_brain.gd"

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const P := Vector2(640.0, 360.0)
const LETHAL := 10000
const STUB_RADIUS := 14.0
const FIXTURE_HP := 100
## Two ticks of slack on a summed-delta bound (the plan's `_TICK_SLACK`).
const TICK_SLACK := 2.0 / 60.0
const _SPEEDUP := 8

const FORM := TwinLaserPair.Phase.FORM
const TELEGRAPH := TwinLaserPair.Phase.TELEGRAPH
const ADVANCE := TwinLaserPair.Phase.ADVANCE
const BREAK := TwinLaserPair.Phase.BREAK
const COLLAPSED := TwinLaserPair.Phase.COLLAPSED
const WAIT := TwinLaserPair.Phase.WAIT

## The test clock (s), advanced by `_step`.
var _t: float = 0.0
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_each() -> void:
	_t = 0.0


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

func _world(mode: String, player_at: Vector2 = P):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = player_at
	return h


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


## A pair spawned through `TwinLaserPairSpawn.spawn_pair()`: midpoint [param at], axis along [param rot]. Hand-ticked unless [param real].
func _pair(h, at: Vector2, rot: float = 0.0, rng_seed: int = 7, real: bool = false) -> TwinLaserPair:
	var s := SPAWN.instantiate() as TwinLaserPairSpawn
	s.rng_seed = rng_seed
	s.position = at
	s.rotation = rot
	h.root.add_child(s)
	var rig := s.spawn_pair()
	if not real:
		for d: Node2D in [rig.drone_a, rig.drone_b]:
			_hand_ticked(d)
	return rig


## A drone driven by `_step` instead of the physics loop. Its body mask is cleared: with no physics step between hand ticks the broadphase still
## holds every body where it was spawned, so `move_and_slide()` would stop drone A on drone B's stale spawn position. Body contact only means
## something on real physics (the wreck row); the beam reads hurtbox shapes, which this leaves alone.
func _hand_ticked(d: Node2D) -> void:
	d.set_physics_process(false)
	(d as CharacterBody2D).collision_mask = 0


## Where a pair spawns so it starts on its slots: `standoff` above [param p] (n = UP, u = +x, A on the left).
func _on_slots(p: Vector2 = P) -> Vector2:
	return p + Vector2(0.0, -CONFIG.standoff)


func _brain(d: Node) -> TwinLaserDroneBrain:
	return d.get_node("Brain") as TwinLaserDroneBrain


func _live(d: Variant) -> bool:
	return is_instance_valid(d) and not (d as Node).is_queued_for_deletion()


## One hand tick: drone A, then drone B (each put at `before + velocity * DT`), then the stub moves by its velocity.
func _step(rig: TwinLaserPair, h) -> void:
	_t += DT
	for d: Variant in [rig.drone_a, rig.drone_b]:
		if not _live(d):
			continue
		var drone := d as CharacterBody2D
		var before := drone.global_position
		drone._physics_process(DT)
		if _live(drone):
			drone.global_position = before + drone.velocity * DT
	h.player.global_position += h.player.velocity * DT


## Steps until [param done] holds or [param max_ticks] pass; true when it held.
func _run(rig: TwinLaserPair, h, max_ticks: int, done: Callable) -> bool:
	for i in max_ticks:
		_step(rig, h)
		if done.call():
			return true
	return false


## The corridor's `inner_rect()` as drone A's mover sees it (Assault only).
func _inner_rect(rig: TwinLaserPair) -> Rect2:
	return (rig.drone_a.get_node("EnemyMover") as EnemyMover).constraint.inner_rect()


## Runs one Attack A to its end (the rig leaves ADVANCE), recording every TELEGRAPH / ADVANCE tick. [param rect] (when it has an area) is checked
## to hold both drones on every such tick. On every tick both lenses are checked against the beam (CHARGING while it telegraphs, ARMED while it is
## ACTIVE, OFF otherwise); `latch_speeds` are the drones' own speeds on the latch tick.
func _record_attack(rig: TwinLaserPair, h, max_seconds: float, rect: Rect2 = Rect2()) -> Dictionary:
	var rec := {
		"max_err": 0.0, "strained_ticks": 0, "frame_changes": 0, "telegraph_ticks": 0, "advance_ticks": 0,
		"first_lethal": -1, "unlit_after_lit": 0, "outside": 0, "form_centres": [], "ended": false,
		"frame": [], "mid_drift": 0.0, "a_start": Vector2.ZERO, "a_end": Vector2.ZERO, "lens_mismatches": 0, "latch_speeds": [],
	}
	for i in ceili(max_seconds / DT):
		var was := rig.phase
		_step(rig, h)
		var ph := rig.phase
		var want := _lens_for(rig)
		for d: Variant in [rig.drone_a, rig.drone_b]:
			if _live(d) and (d as TwinLaserDrone).state_light().get_state() != want:
				rec["lens_mismatches"] = int(rec["lens_mismatches"]) + 1
		if was == FORM and ph == TELEGRAPH:
			for d: Node2D in [rig.drone_a, rig.drone_b]:
				(rec["latch_speeds"] as Array).append((d.get_node("EnemyMover") as EnemyMover).own_velocity().length())
		if ph == FORM:
			(rec["form_centres"] as Array).append(rig.centre)
		if ph == TELEGRAPH or ph == ADVANCE:
			rec["max_err"] = maxf(float(rec["max_err"]), rig.separation_error())
			if rig.strained:
				rec["strained_ticks"] = int(rec["strained_ticks"]) + 1
			var frame := [rig.centre, rig.axis, rig.normal]
			if (rec["frame"] as Array).is_empty():
				rec["frame"] = frame
			elif frame != rec["frame"]:
				rec["frame_changes"] = int(rec["frame_changes"]) + 1
			if rect.has_area():
				for d: Node2D in [rig.drone_a, rig.drone_b]:
					if not rect.has_point(d.global_position):
						rec["outside"] = int(rec["outside"]) + 1
		if ph == TELEGRAPH:
			rec["telegraph_ticks"] = int(rec["telegraph_ticks"]) + 1
			var mid := (rig.drone_a.global_position + rig.drone_b.global_position) * 0.5
			rec["mid_drift"] = maxf(float(rec["mid_drift"]), mid.distance_to(rig.centre))
		if ph == ADVANCE:
			var n := int(rec["advance_ticks"])
			if n == 0:
				rec["a_start"] = rig.drone_a.global_position
			rec["a_end"] = rig.drone_a.global_position
			if rig.beam.is_lethal():
				if int(rec["first_lethal"]) < 0:
					rec["first_lethal"] = n
			elif int(rec["first_lethal"]) >= 0:
				rec["unlit_after_lit"] = int(rec["unlit_after_lit"]) + 1
			rec["advance_ticks"] = n + 1
		elif int(rec["advance_ticks"]) > 0:
			rec["ended"] = true
			break
	return rec


## The lens state the pair's beam calls for (§2.3): CHARGING while it telegraphs, ARMED while it is ACTIVE, OFF otherwise (and once it is freed).
func _lens_for(rig: TwinLaserPair) -> int:
	if not is_instance_valid(rig.beam):
		return StateLight.State.OFF
	match rig.beam.phase():
		EnemyBeam.Phase.TELEGRAPH:
			return StateLight.State.CHARGING
		EnemyBeam.Phase.ACTIVE:
			return StateLight.State.ARMED
	return StateLight.State.OFF


## Every gap between two hits in [param hits] is at least `rehit_interval`.
func _gaps_ok(hits: Array) -> bool:
	var rehit := float(_beam_export(&"rehit_interval"))
	for i in range(1, hits.size()):
		if float(hits[i]) - float(hits[i - 1]) + 1e-6 < rehit:
			return false
	return true


func _advance_ticks() -> int:
	return roundi((CONFIG.standoff + CONFIG.overshoot) / CONFIG.advance_speed / DT)


# ── Structure ───────────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_drone_is_one_r13_circle_shared_by_body_hurtbox_and_contact_box_with_a_mover_brain_and_lens() -> void:
	var h = _world("open_space")
	var d := DRONE.instantiate() as TwinLaserDrone
	h.root.add_child(d)
	d.set_physics_process(false)
	var body := (d.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	var hurt := (d.get_node("HurtBox/CollisionShape2D") as CollisionShape2D).shape
	var contact := (d.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D).shape
	assert_not_null(body, "a circle body")
	assert_eq(body.radius, 13.0, "r 13")
	assert_same(hurt, body, "the hurtbox shares the body's shape")
	assert_same(contact, body, "the contact box shares the body's shape")
	assert_eq(d.body_radius(), 13.0)
	var hb := d.get_node("ContactHitBox") as HitBox
	assert_eq([hb.collision_layer, hb.collision_mask], [256, 0], "the COLLISION idiom: layer 256, mask 0")
	assert_eq(hb.damage, CONFIG.collision_damage, "contact damage from the .tres")
	assert_eq(d.contact_profile.mode, ContactProfile.Mode.COLLISION)
	assert_not_null(d.state_light(), "the lens light")
	assert_true(d.get_node("EnemyMover") is EnemyMover and d.brain() is TwinLaserDroneBrain, "a mover and a brain")
	assert_true(d.is_in_group(&"enemies"))
	assert_eq(d.sprite_forward_angle, PI / 2.0, "nose-down art")
	assert_null(d.pair(), "a lone drone has no rig")


func test_the_shipped_config_wins_over_the_scene() -> void:
	var h = _world("open_space")
	var d := DRONE.instantiate() as TwinLaserDrone
	h.root.add_child(d)
	d.set_physics_process(false)
	var mover := d.get_node("EnemyMover") as EnemyMover
	assert_eq(d.health.max_health, CONFIG.max_health)
	assert_eq(d.health.current_health, CONFIG.max_health)
	assert_eq(d.score_value, CONFIG.score_value)
	assert_true(d.counts_as_escape, "a drone is not static")
	assert_eq([mover.max_speed, mover.acceleration], [CONFIG.max_speed, CONFIG.acceleration])
	assert_eq([mover.hazard_avoidance, mover.hazard_margin, mover.hazard_resistance],
			[CONFIG.hazard_avoidance, CONFIG.hazard_margin, CONFIG.hazard_resistance])
	assert_same(d.brain().config, d.config, "the brain reads the drone's private copy")
	# §2.12's starting values, pinned once against the .tres.
	assert_eq([CONFIG.max_health, CONFIG.collision_damage, CONFIG.score_value, CONFIG.wreck_chance], [30, 8, 30, 0.0])
	assert_eq([CONFIG.hazard_avoidance, CONFIG.hazard_margin, CONFIG.hazard_resistance], [0.6, 16.0, 0.1])
	assert_eq([CONFIG.max_speed, CONFIG.acceleration], [300.0, 900.0])
	assert_eq([CONFIG.rig_length, CONFIG.length_tolerance, CONFIG.strain_seconds, CONFIG.advance_speed, CONFIG.standoff, CONFIG.overshoot],
			[420.0, 16.0, 0.15, 240.0, 260.0, 200.0])
	assert_eq([CONFIG.slot_tolerance, CONFIG.form_timeout, CONFIG.break_seconds, CONFIG.break_speed], [24.0, 3.0, 1.2, 260.0])
	assert_eq([CONFIG.attack_period_min, CONFIG.attack_period_max, CONFIG.engage_seconds, CONFIG.exit_speed], [4.0, 6.0, 8.0, 420.0])


func test_the_phase_enums_are_declared_in_full_and_in_order() -> void:
	assert_eq(TwinLaserDroneBrain.Phase.keys(), ["FORM", "TELEGRAPH", "ADVANCE", "BREAK", "WAIT", "SOLO", "DISENGAGE", "LAUNCHED", "IDLE",
			"NOTICING", "RETURNING"])
	assert_eq(TwinLaserPair.Phase.keys(), ["FORM", "TELEGRAPH", "ADVANCE", "BREAK", "COLLAPSED", "WAIT", "LAUNCHED"])


func test_the_spawner_places_two_drones_half_a_rig_length_along_its_local_x_binds_them_and_frees_itself(
		mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var announced: Array = []
	var on_orphan := func(e: Node) -> void: announced.append(e)
	EventBus.enemy_spawned_orphan.connect(on_orphan)
	var s := SPAWN.instantiate() as TwinLaserPairSpawn
	s.rng_seed = 41
	s.position = Vector2(500.0, 200.0)
	s.rotation = PI / 2.0
	h.root.add_child(s)
	assert_false(s.counts_toward_wave_clear or s.counts_as_escape, "%s: the spawner is never scored" % mode)
	assert_false(s.is_in_group(&"enemies"))
	var rig := s.spawn_pair()
	EventBus.enemy_spawned_orphan.disconnect(on_orphan)
	assert_not_null(rig, "%s: a rig" % mode)
	var a := rig.drone_a as TwinLaserDrone
	var b := rig.drone_b as TwinLaserDrone
	var half := CONFIG.rig_length * 0.5
	assert_almost_eq(a.global_position, Vector2(500.0, 200.0 - half), Vector2.ONE * 0.01, "%s: A at -L/2 along the rotated x" % mode)
	assert_almost_eq(b.global_position, Vector2(500.0, 200.0 + half), Vector2.ONE * 0.01, "%s: B at +L/2" % mode)
	assert_eq(a.get_parent(), h.root, "siblings in the spawner's parent")
	assert_lt(a.get_index(), b.get_index(), "A is added first (it leads on real physics)")
	for d: TwinLaserDrone in [a, b]:
		assert_true(d.is_in_group(rig.owner_group) and d.is_in_group(&"enemies"), "%s: in the owner group and enemies" % mode)
		assert_same(d.pair(), rig, "%s: each brain holds the rig" % mode)
	assert_true(String(rig.owner_group).begins_with("twin_pair_"))
	var beam := rig.beam
	assert_true(beam is EnemyBeam and beam.get_parent() == a, "%s: the beam is A's child" % mode)
	assert_eq(beam.kind, EnemyBeam.Kind.TWIN)
	assert_true(EnergyHitScan.is_exempt(a, a, rig.owner_group) and EnergyHitScan.is_exempt(b, a, rig.owner_group), "host A, group exempts B")
	assert_eq(announced, [a, b], "%s: both announced as orphans" % mode)
	assert_eq([a.brain().rng_seed, b.brain().rng_seed], [41, 42], "seeded s / s + 1")
	assert_true(s.is_queued_for_deletion(), "the spawner frees itself")
	assert_same(s.spawn_pair(), rig, "idempotent")
	assert_eq(h.root.get_children().filter(func(c: Node) -> bool: return c is TwinLaserDrone).size(), 2, "a second call spawns nothing")


## Review N3: `test_enemy_mover_single_writer.gd` sweeps brains and mover-driven roots through the receivers `actor.` / `body.` / `self.`, but the rig and
## the spawner hold the drones as `drone_a` / `drone_b` / `drone`. So they are swept here with that gate's own matchers (its `_PROPS` / `_ASSIGN` /
## `_CALLS`, comments and strings blanked by its `_hits()`) through **any** receiver. The spawner's `drone.position = ...` before `add_child` is
## placement, not motion, and `position` is not a forbidden property.
func test_the_rig_and_the_spawner_write_no_motion() -> void:
	var patterns: Array[RegEx] = [
		RegEx.create_from_string("\\b\\w+\\." + SINGLE_WRITER._PROPS + SINGLE_WRITER._ASSIGN),
		RegEx.create_from_string("\\b\\w+\\." + SINGLE_WRITER._CALLS),
		RegEx.create_from_string("\\bmove_and_(slide|collide)\\s*\\("),
	]
	for path: String in [RIG_SCRIPT_PATH, SPAWN_SCRIPT_PATH, TENDER_SCRIPT_PATH, TENDER_BRAIN_SCRIPT_PATH]:
		var source := FileAccess.get_file_as_string(path)
		assert_gt(source.length(), 0, "read %s" % path)
		var found: Array = SINGLE_WRITER._hits(source, patterns)
		assert_true(found.is_empty(), "%s writes no velocity / rotation and calls no move_and_*: %s" % [path, found])
	for line: String in ["drone_b.velocity = Vector2.ZERO", "drone_a.global_rotation += 0.1", "d.velocity.x /= 2.0", "drone.look_at(p)",
			"drone_a.move_and_slide()"]:
		assert_eq(SINGLE_WRITER._hits(line, patterns).size(), 1, "boundary: '%s' is caught" % line)
	for line: String in ["player_velocity = target.velocity if target.has_target else Vector2.ZERO",
			"normal = normal.rotated(clampf(normal.angle_to(n_target), -cap, cap)).normalized()", "drone.position = at",
			"# drone_b.velocity = Vector2.ZERO"]:
		assert_eq(SINGLE_WRITER._hits(line, patterns).size(), 0, "a read, a placement or a comment is not a write: '%s'" % line)


# ── Attack A (R8.24: the moving wall keeps its length) ─────────────────────────────────────────────────────────────

## Spawned 120 px left of its slots (so FORM has to fly), against a standing stub or one crossing along +x at 200 px/s.
func test_attack_a_keeps_its_length_on_every_telegraph_and_advance_tick(
		case: String = use_parameters(["open_space:0", "open_space:200", "assault:0", "assault:200"])) -> void:
	var mode := case.get_slice(":", 0)
	var speed := float(case.get_slice(":", 1))
	var h = _world(mode)
	var hits := _arm_stub(h)
	h.player.velocity = Vector2(speed, 0.0)
	var rig := _pair(h, _on_slots() + Vector2(-120.0, 0.0))
	var rec := _record_attack(rig, h, 8.0)
	gut.p("%s: worst separation error %.2f px over %d telegraph + %d advance ticks; hits %s" % [case, rec["max_err"], rec["telegraph_ticks"],
			rec["advance_ticks"], hits])
	assert_true(rec["ended"], "%s: the attack ran to its end" % case)
	assert_gt(int(rec["telegraph_ticks"]), 0, "%s: telegraphed" % case)
	assert_lte(float(rec["max_err"]), CONFIG.length_tolerance, "%s: | |A-B| - L | <= length_tolerance on every tick" % case)
	assert_eq(int(rec["strained_ticks"]), 0, "%s: never strained" % case)
	assert_eq(int(rec["frame_changes"]), 0, "%s: the latched frame never moves" % case)
	assert_almost_eq(int(rec["advance_ticks"]), _advance_ticks(), 1, "%s: the advance lasts (standoff + overshoot) / advance_speed" % case)
	assert_between(int(rec["first_lethal"]), 0, _ticks(float(_beam_export(&"ignite_grace"))) + 1, "%s: lethal from ignite_grace" % case)
	assert_eq(int(rec["unlit_after_lit"]), 0, "%s: lethal through the rest of ADVANCE" % case)
	assert_eq(int(rec["lens_mismatches"]), 0, "%s: both lenses CHARGING while the beam warns, ARMED while it burns, OFF otherwise" % case)
	if speed == 0.0:
		assert_eq(hits.size(), 1, "%s: the standing stub is hit exactly once" % case)
	else:
		assert_lte(hits.size(), 1, "%s: the crossing stub at most once" % case)
		var centres: Array = rec["form_centres"]
		assert_gt((centres[centres.size() - 1] as Vector2).distance_to(centres[0]), 100.0, "%s boundary: the FORM frame followed the stub" % case)
		var speeds: Array = rec["latch_speeds"]
		assert_eq(speeds.size(), 2, "%s: the latch tick was seen" % case)
		for s: float in speeds:
			assert_gte(s, 100.0, "%s boundary: the drones latch while moving (%.0f px/s), so the stop on the latched slot is measured" % [case, s])
	assert_true(_gaps_ok(hits), "%s: no two hits closer than rehit_interval" % case)


func test_a_stub_moving_during_telegraph_does_not_move_the_line_and_the_advance_crosses_the_latched_point(
		mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var hits := _arm_stub(h)
	var rig := _pair(h, _on_slots())
	assert_true(_run(rig, h, 120, func() -> bool: return rig.phase == TELEGRAPH), "%s: telegraphs" % mode)
	var latched := rig.latched_player
	assert_eq(latched, P, "%s: the line is latched on the stub" % mode)
	h.player.velocity = Vector2(300.0, 0.0)
	var frame := [rig.centre, rig.axis, rig.normal]
	var signs: Array[float] = []
	var mid_drift := 0.0
	for i in _ticks(4.0):
		_step(rig, h)
		if rig.phase != TELEGRAPH and rig.phase != ADVANCE:
			break
		assert_eq([rig.centre, rig.axis, rig.normal], frame, "%s: the stub's run does not move the line" % mode)
		var a := rig.drone_a.global_position
		var b := rig.drone_b.global_position
		if rig.phase == TELEGRAPH:
			mid_drift = maxf(mid_drift, ((a + b) * 0.5).distance_to(rig.centre))
		else:
			var u := (b - a).normalized()
			var along := (latched - a).dot(u)
			if along >= 0.0 and along <= a.distance_to(b):
				signs.append(signf((latched - a).cross(u)))
	assert_lte(mid_drift, CONFIG.slot_tolerance, "%s: the drones hold the latched slots through TELEGRAPH" % mode)
	assert_true(signs.has(1.0) and signs.has(-1.0), "%s: the advancing line passes through the latched point" % mode)
	assert_eq(hits.size(), 0, "%s: the stub that ran is never hit" % mode)


## The tick after a kill (review B1): the survivor [param d] is no longer boosted along [param dir] (the advance direction) and its own velocity has turned
## toward its new request: SOLO (Open Space) toward `patrol_anchor`, DISENGAGE (Assault) out along -n, speeding up past `advance_speed` toward
## `exit_speed`. A boost left running for the rest of the advance would hold it at exactly `advance_speed` along [param dir].
func _assert_out_of_the_boost(d: Node2D, dir: Vector2, mode: String) -> void:
	var mover := d.get_node("EnemyMover") as EnemyMover
	var v := mover.own_velocity()
	assert_false(mover.is_boosting(), "%s: the survivor is not boosted any more" % mode)
	if mode == "assault":
		assert_gt(CONFIG.exit_speed, CONFIG.advance_speed, "precondition: the exit is faster than the advance")
		assert_gt(v.dot(dir), CONFIG.advance_speed + 1.0, "%s: DISENGAGE speeds it up toward exit_speed (%.1f px/s)" % [mode, v.dot(dir)])
	else:
		var to_anchor := _brain(d).patrol_anchor - d.global_position
		assert_gt((v - dir * CONFIG.advance_speed).dot(to_anchor), 0.0, "%s: SOLO turns it toward its anchor (v %s)" % [mode, v])


func test_killing_drone_a_mid_advance_ends_the_beam_at_once_and_frees_it_with_a(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var hits := _arm_stub(h)
	var rig := _pair(h, _on_slots())
	var gone: Array = []
	rig.collapsed.connect(func(intact: bool) -> void: gone.append(intact))
	assert_true(_run(rig, h, 180, func() -> bool: return rig.phase == ADVANCE), "%s: advancing" % mode)
	_run(rig, h, 29, func() -> bool: return false)
	assert_true(rig.beam.is_lethal(), "%s: precondition: lethal on the 30th ADVANCE tick" % mode)
	var beam := rig.beam
	var b := rig.drone_b
	var dir := rig.advance_dir()
	rig.drone_a.hurt_box.received_damage.emit(LETHAL)
	assert_false(beam.is_lethal(), "%s: not lethal before any further tick" % mode)
	assert_eq(rig.phase, COLLAPSED, "%s: the rig collapsed" % mode)
	assert_eq(gone, [false], "%s: collapsed(false) once" % mode)
	assert_same(rig.leader(), b, "%s: B leads now" % mode)
	await get_tree().process_frame
	assert_false(is_instance_valid(beam), "%s: the beam was freed with A" % mode)
	var hit_count := hits.size()
	_step(rig, h)
	assert_eq(_brain(b).phase, TwinLaserDroneBrain.Phase.DISENGAGE if mode == "assault" else TwinLaserDroneBrain.Phase.SOLO,
			"%s: the survivor goes SOLO / DISENGAGE" % mode)
	_assert_out_of_the_boost(b, dir, mode)
	_run(rig, h, _ticks(2.0), func() -> bool: return not _live(b))
	assert_eq(hits.size(), hit_count, "%s: nothing is hit after the kill" % mode)
	assert_eq(gone, [false], "%s: and nothing relights" % mode)


func test_killing_drone_b_mid_advance_makes_a_cancel_the_beam_and_never_relight_it(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var hits := _arm_stub(h)
	var rig := _pair(h, _on_slots())
	assert_true(_run(rig, h, 180, func() -> bool: return rig.phase == ADVANCE), "%s: advancing" % mode)
	_run(rig, h, 29, func() -> bool: return false)
	var beam := rig.beam
	var a := rig.drone_a
	assert_true(beam.is_lethal(), "%s: precondition: lethal" % mode)
	var dir := rig.advance_dir()
	var phases: Array = []
	beam.phase_changed.connect(func(p: int) -> void: phases.append(p))
	rig.drone_b.hurt_box.received_damage.emit(LETHAL)
	assert_false(beam.is_lethal(), "%s: not lethal before any further tick" % mode)
	var hit_count := hits.size()
	var lethal_ticks := 0
	for i in _ticks(2.0):
		_step(rig, h)
		if not _live(a):
			break
		if is_instance_valid(beam) and beam.is_lethal():
			lethal_ticks += 1
		if i == 0:
			assert_eq(_brain(a).phase, TwinLaserDroneBrain.Phase.DISENGAGE if mode == "assault" else TwinLaserDroneBrain.Phase.SOLO,
					"%s: A goes SOLO / DISENGAGE" % mode)
			_assert_out_of_the_boost(a, dir, mode)
	assert_eq(lethal_ticks, 0, "%s: never lethal again" % mode)
	assert_false(phases.has(EnemyBeam.Phase.TELEGRAPH) or phases.has(EnemyBeam.Phase.ACTIVE), "%s: never restarted" % mode)
	assert_true(phases.has(EnemyBeam.Phase.OFF), "%s: A's ticks faded it out" % mode)
	if _live(a):
		assert_eq((a as TwinLaserDrone).state_light().get_state(), StateLight.State.OFF, "%s: and A's lens is OFF" % mode)
	assert_eq(hits.size(), hit_count, "%s: nothing is hit after the kill" % mode)


## A gravity well beside drone B's advance path (453 px from its slot, outside the well's reach, so FORM and TELEGRAPH are untouched) drifts B
## during the boost: the beam strains and collapses. Open Space: the survivors BREAK (and re-FORM later). Assault: the collapse ended the life's
## one attack, so both DISENGAGE. Control: the same spawn without the well runs the whole advance unstrained.
func test_a_well_beside_drone_bs_path_strains_the_beam_and_it_collapses_after_strain_seconds(mode: String = use_parameters(MODES)) -> void:
	for with_well: bool in [true, false]:
		_t = 0.0
		var h = _world(mode)
		var b_slot := _on_slots() + Vector2(CONFIG.rig_length * 0.5, 0.0)
		if with_well:
			var well := HazardField.new()
			well.kind = &"gravity_well"
			well.radius = 420.0
			well.core_radius = 90.0
			well.pull_force = 520.0
			h.root.add_child(well)
			well.global_position = b_slot + Vector2(340.0, 0.0) + Vector2.DOWN * 300.0
		var rig := _pair(h, _on_slots())
		var outcome: Array = []
		rig.collapsed.connect(func(intact: bool) -> void: outcome.append(intact))
		var seq: Array = []
		rig.phase_changed.connect(func(p: int) -> void: seq.append(p))
		var first_strain := -1.0
		var strained_phase := -1
		var collapse_at := -1.0
		var lethal_while_strained := 0
		var b_lateral := 0.0
		var alive_at_collapse := false
		for i in _ticks(6.0):
			_step(rig, h)
			if rig.strained and first_strain < 0.0:
				first_strain = _t
				strained_phase = rig.phase
			if rig.strained and is_instance_valid(rig.beam) and rig.beam.is_lethal():
				lethal_while_strained += 1
			if collapse_at < 0.0 and outcome.has(true):
				collapse_at = _t
				b_lateral = rig.drone_b.global_position.x - b_slot.x
				alive_at_collapse = _live(rig.drone_a) and _live(rig.drone_b)
				_step(rig, h)  # one more tick: what the survivors do next
				break
			if seq.has(BREAK):
				break  # the advance ran to its end
		if with_well:
			gut.p("%s: strain at %.3f s, collapse at %.3f s, B's lateral drift %.1f px" % [mode, first_strain, collapse_at, b_lateral])
			assert_eq(strained_phase, ADVANCE, "%s: the first strained tick is in ADVANCE" % mode)
			assert_gt(collapse_at, 0.0, "%s: the beam collapsed" % mode)
			assert_almost_eq(collapse_at - first_strain, CONFIG.strain_seconds, DT + 1e-6, "%s: strain_seconds after the strain began" % mode)
			assert_eq(lethal_while_strained, 0, "%s: never lethal while strained" % mode)
			assert_true(alive_at_collapse, "%s: a strain collapse, both drones alive" % mode)
			assert_gt(b_lateral, CONFIG.length_tolerance * 0.5, "%s: the well drew B off its path" % mode)
			if mode == "assault":
				assert_eq(outcome, [true, false], "%s: collapsed(true), then the pair breaks for good" % mode)
				assert_eq([_brain(rig.drone_a).phase, _brain(rig.drone_b).phase],
						[TwinLaserDroneBrain.Phase.DISENGAGE, TwinLaserDroneBrain.Phase.DISENGAGE], "%s: one attack per life: both leave" % mode)
				_assert_out_of_the_boost(rig.drone_b, rig.advance_dir(), mode)
			else:
				assert_eq(outcome, [true], "%s: collapsed(true)" % mode)
				assert_eq(rig.phase, BREAK, "%s: then the survivors BREAK" % mode)
				# Review B1: on the next tick both are out of the boost and B turns toward its break side (+u), slowing along -n.
				for d: Node2D in [rig.drone_a, rig.drone_b]:
					assert_false((d.get_node("EnemyMover") as EnemyMover).is_boosting(), "%s: not boosted after the collapse" % mode)
				var v_b := (rig.drone_b.get_node("EnemyMover") as EnemyMover).own_velocity()
				assert_gt(v_b.dot(rig.axis), 0.0, "%s: B breaks along +u (v %s)" % [mode, v_b])
				assert_lt(v_b.dot(rig.advance_dir()), CONFIG.advance_speed - 1.0, "%s: and stops advancing" % mode)
		else:
			assert_true(seq.has(ADVANCE) and seq.has(BREAK), "%s control: the advance ran to its end" % mode)
			assert_lt(first_strain, 0.0, "%s control: no well, no strain" % mode)
			assert_false(outcome.has(true), "%s control: no strain collapse" % mode)
		h.root.free()  # out of the tree now: the control must not see this well or this player


func test_the_beam_hurts_an_enemy_on_its_line_but_never_its_drones_or_controller(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var half := CONFIG.rig_length * 0.5
	var a := DRONE.instantiate() as TwinLaserDrone
	var b := DRONE.instantiate() as TwinLaserDrone
	a.position = _on_slots() + Vector2(-half, 0.0)
	b.position = _on_slots() + Vector2(half, 0.0)
	h.root.add_child(a)
	h.root.add_child(b)
	for d: TwinLaserDrone in [a, b]:
		_hand_ticked(d)
	var controller := _victim(h, P + Vector2(-100.0, 0.0))
	var victim := _victim(h, P + Vector2(100.0, 0.0))
	var rig := TwinLaserPair.bind(a, b, controller)
	assert_true(controller.is_in_group(rig.owner_group), "%s: the controller is in the owner group" % mode)
	assert_same(rig.controller, controller)
	_run(rig, h, _ticks(4.0), func() -> bool: return rig.phase == BREAK)
	assert_lt(_hp(victim), FIXTURE_HP, "%s: the enemy on the line is hurt" % mode)
	assert_eq(_hp(controller), FIXTURE_HP, "%s: never the controller" % mode)
	assert_eq([_hp(a), _hp(b)], [CONFIG.max_health, CONFIG.max_health], "%s: never the drones" % mode)


func test_only_the_leaders_tick_advances_the_rig() -> void:
	var h = _world("open_space")
	var rig := _pair(h, _on_slots() + Vector2(-60.0, 0.0))
	var b := rig.drone_b as CharacterBody2D
	for i in 10:
		b._physics_process(DT)
	assert_eq([rig.phase, rig.phase_time(), rig.has_frame], [FORM, 0.0, false], "ticking only B moves no rig clock while A lives")
	(rig.drone_a as CharacterBody2D)._physics_process(DT)
	assert_almost_eq(rig.phase_time(), DT, 1e-6, "A's tick does")
	assert_true(rig.has_frame)
	rig.drone_a.hurt_box.received_damage.emit(LETHAL)
	assert_same(rig.leader(), b, "after A dies B leads")


## Review N2: `died` is emitted before `queue_free()`, so a handler running inside the death hook (connected after the rig's own) must already
## see B as the leader and the pair as broken: the rig reads its own `_gone` flag, not "queued for deletion".
func test_inside_the_death_hook_the_rig_already_counts_the_drone_gone() -> void:
	var h = _world("open_space")
	var rig := _pair(h, _on_slots())
	var seen: Array = []
	var rig_ref: WeakRef = weakref(rig)
	var a := rig.drone_a as TwinLaserDrone
	a.died.connect(func() -> void:
		var r := rig_ref.get_ref() as TwinLaserPair
		seen.append([a.is_queued_for_deletion(), r.leader() == r.drone_b, r.is_intact()]))
	a.hurt_box.received_damage.emit(LETHAL)
	assert_eq(seen, [[false, true, false]], "not yet queued, yet B already leads and the pair is broken")


func _wall_registered(group: StringName) -> bool:
	return not Hazards.around(P, 10000.0).filter(func(i: HazardInfo) -> bool: return i.kind == &"laser_wall" and i.exempt_group == group).is_empty()


## A rail taking over a drone (`BaseEnemy.suspend_ai()`, review N6) breaks the pair: a railed drone A frees the beam and its wall (nobody would tick
## its fade); a railed drone B leaves A to cancel it (a TELEGRAPH cancel is OFF at once), and it never relights while A goes SOLO / DISENGAGE.
func test_a_rail_taking_over_a_drone_breaks_the_pair(mode: String = use_parameters(MODES)) -> void:
	for which: String in ["a", "b"]:
		var label := "%s, rail on %s" % [mode, which]
		var h = _world(mode)
		var rig := _pair(h, _on_slots())
		var outcome: Array = []
		rig.collapsed.connect(func(intact: bool) -> void: outcome.append(intact))
		assert_true(_run(rig, h, 30, func() -> bool: return rig.phase == TELEGRAPH), "%s: telegraphing" % label)
		var beam := rig.beam
		assert_true(_wall_registered(rig.owner_group), "%s: precondition: the wall is registered" % label)
		var railed := (rig.drone_a if which == "a" else rig.drone_b) as BaseEnemy
		var other := rig.drone_b if which == "a" else rig.drone_a
		railed.suspend_ai()
		assert_eq(outcome, [false], "%s: the pair broke for good in the same call" % label)
		assert_false(rig.is_intact(), label)
		if which == "a":
			await get_tree().process_frame
			assert_false(is_instance_valid(beam), "%s: the beam is freed" % label)
		else:
			assert_eq(beam.phase(), EnemyBeam.Phase.OFF, "%s: A cancelled it (TELEGRAPH -> OFF)" % label)
		assert_false(_wall_registered(rig.owner_group), "%s: the wall is gone" % label)
		var lethal := 0
		for i in _ticks(1.0):
			_step(rig, h)
			if is_instance_valid(beam) and beam.is_lethal():
				lethal += 1
		assert_eq(lethal, 0, "%s: never lethal again" % label)
		if _live(other):
			assert_eq(_brain(other).phase, TwinLaserDroneBrain.Phase.DISENGAGE if mode == "assault" else TwinLaserDroneBrain.Phase.SOLO,
					"%s: the other drone goes SOLO / DISENGAGE" % label)
		h.root.free()


# ── Assault ─────────────────────────────────────────────────────────────────────────────────────────────────────────

func _inset() -> Rect2:
	return AssaultCorridorConstraint.new().inner_rect().grow(-CONFIG.slot_tolerance)


func _plan(p: Vector2, rect: Rect2 = _inset(), prev_vertical: bool = false, prev_side: float = 0.0) -> Dictionary:
	return TwinLaserPair.assault_frame(p, rect, CONFIG.rig_length, CONFIG.standoff, CONFIG.overshoot, prev_vertical, prev_side, CONFIG.slot_tolerance)


func test_assault_frame_planner_clamps_switches_sides_and_refuses() -> void:
	var rect := _inset()
	var half := CONFIG.rig_length * 0.5
	var f := _plan(P)
	assert_eq([f["vertical"], f["normal"], f["centre"], f["advance"]], [false, Vector2.UP, Vector2(640.0, 100.0), CONFIG.standoff + CONFIG.overshoot],
			"a centred player: horizontal, standoff above, a full advance")
	var near_left := Vector2(rect.position.x + 30.0, 360.0)
	f = _plan(near_left)
	assert_almost_eq((f["centre"] as Vector2).x, rect.position.x + half, 0.001, "clamped so the whole line is inside")
	assert_lte(absf((f["centre"] as Vector2).x - near_left.x), half, "and the line still covers the player")
	var near_top := Vector2(400.0, rect.position.y + 106.0)
	f = _plan(near_top)
	assert_true(f["vertical"], "106 px of room above < standoff: vertical")
	assert_eq(f["normal"], Vector2.RIGHT, "toward the roomier side (right)")
	assert_almost_eq((f["centre"] as Vector2).x, near_top.x + CONFIG.standoff, 0.001)
	assert_almost_eq((f["centre"] as Vector2).y, rect.position.y + half, 0.001, "clamped along y")
	f = _plan(Vector2(640.0, rect.end.y - 50.0))
	assert_almost_eq(float(f["advance"]), CONFIG.standoff + 50.0, 0.001, "the overshoot is clamped to the room below")
	var hold := Vector2(640.0, rect.position.y + CONFIG.standoff + 10.0)
	assert_false(_plan(hold)["vertical"], "fresh: horizontal at standoff + 10")
	assert_true(_plan(hold, rect, true, 1.0)["vertical"], "hysteresis: a vertical frame stays vertical at standoff + 10")
	var release := Vector2(640.0, rect.position.y + CONFIG.standoff + CONFIG.slot_tolerance + 1.0)
	assert_false(_plan(release, rect, true, 1.0)["vertical"], "and switches at standoff + slot_tolerance + 1")
	var side_tie := Vector2(rect.get_center().x + CONFIG.slot_tolerance * 0.25, rect.position.y + 50.0)
	assert_eq(_plan(side_tie, rect, true, 1.0)["side"], 1.0, "the side is kept while the other has no more than hysteresis extra room")
	var side_far := Vector2(rect.get_center().x + CONFIG.slot_tolerance + 2.0, rect.position.y + 50.0)
	assert_eq(_plan(side_far, rect, true, 1.0)["side"], -1.0, "and switched past it")
	assert_eq(_plan(Vector2(150.0, 150.0), Rect2(0.0, 0.0, 300.0, 300.0)), {}, "a 300 x 300 rect fits no rig")
	assert_eq(_plan(Vector2(250.0, 100.0), Rect2(0.0, 0.0, 500.0, 500.0)), {}, "boundary: room for neither shape")


func test_assault_rig_stays_inside_inner_rect_with_the_player_by_a_side_edge() -> void:
	var p := Vector2(-40.0, 360.0)
	var h = _world("assault", p)
	var hits := _arm_stub(h)
	var clamped_x := _inset().position.x + CONFIG.rig_length * 0.5
	var rig := _pair(h, Vector2(clamped_x + 300.0, p.y - CONFIG.standoff))
	var rec := _record_attack(rig, h, 8.0, _inner_rect(rig))
	assert_true(rec["ended"], "the attack ran")
	assert_eq(int(rec["outside"]), 0, "both drones inside inner_rect() on every TELEGRAPH / ADVANCE tick")
	assert_lte(float(rec["max_err"]), CONFIG.length_tolerance, "and the length held")
	assert_almost_eq((rec["frame"][0] as Vector2).x, clamped_x, 0.001, "the frame was clamped")
	assert_eq(hits.size(), 1, "the line still crossed the stub")


func test_assault_rig_is_vertical_when_the_room_above_the_player_is_short() -> void:
	var p := Vector2(400.0, -250.0)
	var h = _world("assault", p)
	var hits := _arm_stub(h)
	var f := _plan(p)
	assert_true(f["vertical"], "precondition: the planner says vertical")
	var rig := _pair(h, f["centre"], PI / 2.0)
	var rec := _record_attack(rig, h, 8.0, _inner_rect(rig))
	assert_true(rec["ended"], "the attack ran")
	assert_eq((rec["frame"] as Array)[2], Vector2.RIGHT, "n = +RIGHT: the line beside the player, advancing across")
	assert_eq(int(rec["outside"]), 0, "inside inner_rect() on every TELEGRAPH / ADVANCE tick")
	assert_lte(float(rec["max_err"]), CONFIG.length_tolerance, "the length held")
	assert_lt((rec["a_end"] as Vector2).x, (rec["a_start"] as Vector2).x - 300.0, "advancing along -x")
	assert_eq(hits.size(), 1, "the stub is hit once")


func test_one_advance_per_assault_life_then_disengage_but_open_space_repeats(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var rig := _pair(h, _on_slots())
	var telegraphs := [0]
	rig.phase_changed.connect(func(p: int) -> void:
		if p == TELEGRAPH:
			telegraphs[0] += 1)
	var a := rig.drone_a
	var b := rig.drone_b
	var released := []
	for d: Node in [a, b]:
		_brain(d).phase_changed.connect(func(p: int) -> void:
			if p == TwinLaserDroneBrain.Phase.DISENGAGE:
				released.append((d.get_node("EnemyMover") as EnemyMover).constraint_released()))
	assert_true(_run(rig, h, _ticks(5.0), func() -> bool: return rig.advances_started == 1 and rig.phase != ADVANCE), "%s: one attack" % mode)
	var ended_at := _t
	if mode == "assault":
		_run(rig, h, _ticks(5.0), func() -> bool: return not _live(a) and not _live(b))
		assert_eq(released, [true, true], "both disengage with the corridor released")
		assert_eq(rig.advances_started, 1, "one ADVANCE per life")
		assert_eq(telegraphs[0], 1, "no second TELEGRAPH")
		assert_false(_live(a) or _live(b), "both freed outside the projectile world rect")
		assert_lt(_t - ended_at, 5.0, "within 5 s of the advance's end")
	else:
		assert_true(_run(rig, h, _ticks(3.0), func() -> bool: return rig.phase == WAIT), "BREAK, then WAIT")
		var wait := rig.wait_seconds
		assert_between(wait, CONFIG.attack_period_min, CONFIG.attack_period_max, "a period in [min, max]")
		var wait_start := _t
		assert_true(_run(rig, h, _ticks(7.0), func() -> bool: return rig.phase != WAIT), "the wait ends")
		assert_almost_eq(_t - wait_start, wait, DT + 1e-6, "after its period")
		assert_eq(rig.phase, FORM, "then FORM")
		# Review N1: the re-FORM takes the bearing outright (the drones are past the player now), so it latches inside form_timeout, no BREAK between,
		# on a frame on the drones' side.
		var form_start := _t
		_step(rig, h)  # the re-FORM's first frame
		var first_mid := (a.global_position + b.global_position) * 0.5
		assert_gt(rig.normal.dot(first_mid - h.player.global_position), 0.0,
				"the re-FORM's first frame takes the drones' bearing outright (turning the old normal would still point away)")
		assert_true(_run(rig, h, _ticks(CONFIG.form_timeout) + 1, func() -> bool: return rig.phase != FORM), "the re-FORM ends")
		assert_eq(rig.phase, TELEGRAPH, "with a TELEGRAPH, not a BREAK")
		assert_lt(_t - form_start, CONFIG.form_timeout, "inside form_timeout (%.2f s)" % (_t - form_start))
		var mid := (a.global_position + b.global_position) * 0.5
		assert_gt(rig.normal.dot(mid - h.player.global_position), 0.0, "the second line stands on the drones' side of the player")
		assert_true(_run(rig, h, _ticks(8.0), func() -> bool: return rig.advances_started == 2), "and a second attack")
		assert_eq(telegraphs[0], 2)
		assert_eq(released, [], "Open Space never disengages")


## Review round 2 (3a): a pair that cannot reach its slots gives up FORM at `form_timeout` (±1 tick) without ever starting the beam, BREAKs, and then
## WAITs (Open Space) or re-FORMs (Assault, where the attack is still owed: no DISENGAGE, no attack spent).
func test_a_pair_that_cannot_reach_its_slots_breaks_at_form_timeout_without_a_beam(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var rig := _pair(h, _on_slots() + Vector2(-600.0, 0.0))
	for d: Node in [rig.drone_a, rig.drone_b]:
		(d.get_node("EnemyMover") as EnemyMover).max_speed = 10.0
	var seq: Array = []
	rig.phase_changed.connect(func(p: int) -> void: seq.append(p))
	assert_true(_run(rig, h, _ticks(CONFIG.form_timeout) + 2, func() -> bool: return rig.phase != FORM), "%s: FORM ends" % mode)
	assert_eq(rig.phase, BREAK, "%s: in a BREAK" % mode)
	assert_almost_eq(_t, CONFIG.form_timeout, DT + 1e-6, "%s: at form_timeout" % mode)
	assert_eq(rig.beam.phase(), EnemyBeam.Phase.OFF, "%s: the beam never started" % mode)
	assert_false(seq.has(TELEGRAPH), "%s: no TELEGRAPH" % mode)
	_step(rig, h)
	for d: Node in [rig.drone_a, rig.drone_b]:
		assert_eq(_brain(d).phase, TwinLaserDroneBrain.Phase.BREAK, "%s: both brains BREAK" % mode)
	var after_break := WAIT if mode == "open_space" else FORM
	assert_true(_run(rig, h, _ticks(CONFIG.break_seconds) + 2, func() -> bool: return rig.phase != BREAK), "%s: the BREAK ends" % mode)
	assert_eq(rig.phase, after_break, "%s: then %s" % [mode, "WAIT" if mode == "open_space" else "FORM again"])
	assert_eq(rig.advances_started, 0, "%s: no attack spent" % mode)
	assert_true(rig.is_intact(), "%s: the pair is intact" % mode)


## Review round 2 (3b): a strain collapse while the beam only warns (no ADVANCE yet) BREAKs both drones and re-forms the rig; in Assault it does not
## spend the life's one attack, so neither drone disengages. B is held 150 px off its slot along n after every tick until the collapse.
func test_a_strain_collapse_in_telegraph_breaks_and_re_forms_without_spending_the_attack(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var rig := _pair(h, _on_slots())
	var b := rig.drone_b
	var outcome: Array = []
	var phase_at_collapse: Array = []
	var rig_ref: WeakRef = weakref(rig)
	rig.collapsed.connect(func(intact: bool) -> void:
		outcome.append(intact)
		phase_at_collapse.append((rig_ref.get_ref() as TwinLaserPair).beam.phase()))
	assert_true(_run(rig, h, 30, func() -> bool: return rig.phase == TELEGRAPH), "%s: telegraphing" % mode)
	var beam := rig.beam
	var pushed := 0
	while outcome.is_empty() and pushed < 30:
		b.global_position = rig.slot_of(b) + rig.normal * 150.0
		_step(rig, h)
		pushed += 1
	assert_eq(outcome, [true], "%s: one strain collapse with both drones alive" % mode)
	assert_eq(phase_at_collapse, [EnemyBeam.Phase.OFF], "%s: during the telegraph, which a cancel turns OFF at once" % mode)
	assert_between(pushed, _ticks(CONFIG.strain_seconds), _ticks(CONFIG.strain_seconds) + 2, "%s: after strain_seconds of strain" % mode)
	assert_eq(rig.advances_started, 0, "%s: no ADVANCE" % mode)
	_step(rig, h)
	for d: Node in [rig.drone_a, rig.drone_b]:
		assert_eq(_brain(d).phase, TwinLaserDroneBrain.Phase.BREAK, "%s: both brains BREAK, neither DISENGAGE nor SOLO" % mode)
	assert_true(_run(rig, h, _ticks(CONFIG.break_seconds) + 2, func() -> bool: return rig.phase != BREAK), "%s: the BREAK ends" % mode)
	assert_eq(rig.phase, WAIT if mode == "open_space" else FORM, "%s: then WAIT / FORM" % mode)
	if mode == "assault":
		assert_true(_run(rig, h, _ticks(CONFIG.form_timeout), func() -> bool: return rig.phase == TELEGRAPH), "assault: the owed attack re-forms")
		for d: Node in [rig.drone_a, rig.drone_b]:
			assert_false((d.get_node("EnemyMover") as EnemyMover).constraint_released(), "assault: still in the corridor")
	assert_same(rig.beam, beam, "%s: the same beam (A lives)" % mode)


## The drones start on their slots, so the first tick is the latch tick. `latch`: the budget expires on that very tick, the worst case (review N7:
## 47 + 1 + 115 = 163 ticks to DISENGAGE against a 2.75 s bound); `mid_telegraph`: it expires 0.3 s into TELEGRAPH.
func test_assault_budget_expiring_in_telegraph_lets_the_attack_finish_then_disengages(case: String = use_parameters(["latch", "mid_telegraph"])) -> void:
	var h = _world("assault")
	var hits := _arm_stub(h)
	var rig := _pair(h, _on_slots())
	var engage := DT if case == "latch" else DT + 0.3
	var latched_at := [-1.0]
	rig.phase_changed.connect(func(p: int) -> void:
		if p == TELEGRAPH and latched_at[0] < 0.0:
			latched_at[0] = _t)
	for d: Node in [rig.drone_a, rig.drone_b]:
		(d as TwinLaserDrone).config.engage_seconds = engage
	var a := rig.drone_a
	var disengaged_at := [-1.0]
	_brain(a).phase_changed.connect(func(p: int) -> void:
		if p == TwinLaserDroneBrain.Phase.DISENGAGE and disengaged_at[0] < 0.0:
			disengaged_at[0] = _t)
	var rec := _record_attack(rig, h, 6.0)
	_step(rig, h)
	assert_true(rec["ended"], "the attack finished")
	assert_almost_eq(int(rec["advance_ticks"]), _advance_ticks(), 1, "the whole ADVANCE ran after the budget expired")
	assert_eq(hits.size(), 1, "and hit the stub")
	var bound := engage + float(_beam_export(&"telegraph_seconds")) + (CONFIG.standoff + CONFIG.overshoot) / CONFIG.advance_speed + TICK_SLACK
	gut.p("%s: latched at %.3f s, budget out at %.3f s, DISENGAGE at %.3f s against the bound %.3f s" % [case, latched_at[0], engage, disengaged_at[0],
			bound])
	assert_almost_eq(latched_at[0], DT, 1e-6, "%s: precondition: the first tick latches" % case)
	assert_gt(disengaged_at[0], engage, "%s: then DISENGAGE" % case)
	assert_lte(disengaged_at[0], bound, "%s: no later than engage + telegraph + advance + slack" % case)


func test_assault_a_pair_whose_budget_expires_in_form_disengages_without_telegraphing() -> void:
	var h = _world("assault")
	var rig := _pair(h, _on_slots() + Vector2(-600.0, 0.0))
	for d: Node in [rig.drone_a, rig.drone_b]:
		(d as TwinLaserDrone).config.engage_seconds = 0.2
	var telegraphed := [false]
	rig.phase_changed.connect(func(p: int) -> void: telegraphed[0] = telegraphed[0] or p == TELEGRAPH)
	assert_true(_run(rig, h, _ticks(1.0), func() -> bool: return _brain(rig.drone_a).phase == TwinLaserDroneBrain.Phase.DISENGAGE),
			"boundary: it disengages")
	assert_almost_eq(_t, 0.2, DT + 1e-6, "at 0.2 s")
	assert_false(telegraphed[0], "without ever telegraphing")


# ── Real physics (8x) ───────────────────────────────────────────────────────────────────────────────────────────────

## "Bait into terrain": a wreck placed in front of drone B when the rig telegraphs stops B's boosted body; the beam strains and collapses with both
## drones alive. Read at the collapse (review B3): B stopped short, in the gap to the wreck, and A leads it by at least the lag at which
## `| |A - B| - L |` first passes `length_tolerance`, `sqrt((L + tol)^2 - L^2)`. Its no-hazard control is the next row.
func test_a_wreck_in_front_of_drone_b_stops_it_and_the_beam_strains_and_collapses(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	_scale_clock()
	var rig := _pair(h, _on_slots(), 0.0, 7, true)
	var a := rig.drone_a as TwinLaserDrone
	var b := rig.drone_b as TwinLaserDrone
	var gap := 60.0
	var placed: Array = []
	var starts: Array = []  # [A, B, advance direction] at ADVANCE entry
	var at_collapse: Array = []  # [A's progress, B's progress] along the advance
	var outcome: Array = []
	# A weak reference: a lambda on the rig's own signal that captured the rig would be a cycle, and the RefCounted rig would leak at exit.
	var rig_ref: WeakRef = weakref(rig)
	rig.phase_changed.connect(func(p: int) -> void:
		var r := rig_ref.get_ref() as TwinLaserPair
		if p == TELEGRAPH and placed.is_empty():
			var w := WRECK_LARGE.instantiate() as Wreck
			w.assault_drift = 0.0
			w.position = b.global_position + r.advance_dir() * (b.body_radius() + gap)
			placed.append(w)
			h.root.add_child.call_deferred(w)
		elif p == ADVANCE and starts.is_empty():
			starts.append_array([a.global_position, b.global_position, r.advance_dir()]))
	rig.collapsed.connect(func(intact: bool) -> void:
		outcome.append(intact)
		if intact and at_collapse.is_empty() and not starts.is_empty():
			var dir: Vector2 = starts[2]
			at_collapse.append_array([(a.global_position - (starts[0] as Vector2)).dot(dir), (b.global_position - (starts[1] as Vector2)).dot(dir)]))
	for i in 90:
		await wait_physics_frames(4)
		if not outcome.is_empty():
			break
	assert_eq(placed.size(), 1, "%s: the wreck was placed" % mode)
	# Assault: the collapse ended the life's one attack, so the same tick also breaks the pair for good (both DISENGAGE).
	assert_eq(outcome, [true] if mode == "open_space" else [true, false], "%s: the beam strained and collapsed with both drones alive" % mode)
	assert_true(_live(a) and _live(b), "%s: both alive" % mode)
	assert_eq(at_collapse.size(), 2, "%s: the collapse came during the advance" % mode)
	if at_collapse.size() == 2 and not placed.is_empty():
		var wreck_r := (placed[0] as Wreck).body_radius()
		var lag := sqrt(pow(CONFIG.rig_length + CONFIG.length_tolerance, 2.0) - pow(CONFIG.rig_length, 2.0))
		gut.p("%s: at the collapse A advanced %.1f px, B %.1f px (wreck gap %.0f px, strain lag %.1f px)" % [mode, at_collapse[0], at_collapse[1],
				gap - wreck_r, lag])
		assert_lte(float(at_collapse[1]), gap - wreck_r + 2.0, "%s: B was stopped in the gap to the wreck" % mode)
		assert_gte(float(at_collapse[0]) - float(at_collapse[1]), lag, "%s: A led B by at least the strain lag" % mode)
		# Review round 2 (5): and by no more than A covers in `strain_seconds` past it (two ticks of slack), so the collapse timing is pinned here too.
		assert_lte(float(at_collapse[0]) - float(at_collapse[1]), lag + CONFIG.advance_speed * (CONFIG.strain_seconds + TICK_SLACK),
				"%s: the collapse came strain_seconds after the strain began" % mode)


## Samples the rig after both drones on every physics frame (added to the world after them, so it runs last).
class _Sampler extends Node:
	var rig: TwinLaserPair
	var max_err: float = 0.0
	var samples: int = 0

	func _physics_process(_delta: float) -> void:
		if rig.phase == TwinLaserPair.Phase.TELEGRAPH or rig.phase == TwinLaserPair.Phase.ADVANCE:
			max_err = maxf(max_err, rig.separation_error())
			samples += 1


## The wreck row's no-hazard control, on the same real physics: with no wreck the same spawn runs its advance to the end unstrained, keeping its
## length on every physics frame of TELEGRAPH and ADVANCE (R8.24 with the engine's own tick order and `move_and_slide()`).
func test_with_no_wreck_the_same_real_physics_attack_runs_to_its_end_unstrained(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	_scale_clock()
	var rig := _pair(h, _on_slots(), 0.0, 7, true)
	var sampler := _Sampler.new()
	sampler.rig = rig
	h.root.add_child(sampler)
	var outcome: Array = []
	rig.collapsed.connect(func(intact: bool) -> void: outcome.append(intact))
	var seq: Array = []
	rig.phase_changed.connect(func(p: int) -> void: seq.append(p))
	for i in 90:
		await wait_physics_frames(4)
		if seq.has(BREAK) or not outcome.is_empty():
			break
	gut.p("%s: worst separation error %.2f px over %d physics frames; phases %s" % [mode, sampler.max_err, sampler.samples, seq])
	assert_true(seq.has(TELEGRAPH) and seq.has(ADVANCE) and seq.has(BREAK), "%s control: the advance ran to its end" % mode)
	assert_false(outcome.has(true), "%s control: no wreck, no strain collapse" % mode)
	assert_gt(sampler.samples, _advance_ticks(), "%s: sampled every TELEGRAPH / ADVANCE frame" % mode)
	assert_lte(sampler.max_err, CONFIG.length_tolerance, "%s: the length held on real physics" % mode)


# ── Through a real WaveManager (Assault) ────────────────────────────────────────────────────────────────────────────

func test_assault_wave_builder_spawns_a_bound_pair_through_a_real_wave_manager() -> void:
	var h = _world("assault")
	var cam := h.root.get_node("ArenaCamera") as ArenaCamera
	cam.set_physics_process(false)
	var container := Node2D.new()
	h.root.add_child(container)
	var wm := WaveManager.new()
	wm.enemy_container = container
	h.root.add_child(wm)
	var at_spawn: Array = []
	var on_orphan := func(e: Node) -> void: at_spawn.append((e as Node2D).global_position)
	EventBus.enemy_spawned_orphan.connect(on_orphan)
	var b := WaveBuilder.new()
	var w := b.wave(0.0, [b.twin_laser_pair().at(0.0, -100.0)])
	assert_eq(w.entries[0].ship_scene.resource_path, WaveBuilder.TWIN_LASER_PAIR, "the spawner path")
	wm.load_section([w] as Array[WaveResource])
	for i in 4:
		await get_tree().process_frame
	EventBus.enemy_spawned_orphan.disconnect(on_orphan)
	var drones := container.get_children().filter(func(c: Node) -> bool: return c is TwinLaserDrone)
	assert_eq(drones.size(), 2, "two drones")
	assert_eq(container.get_children().filter(func(c: Node) -> bool: return c is TwinLaserPairSpawn and not c.is_queued_for_deletion()).size(), 0,
			"no spawner left")
	if drones.size() == 2:
		assert_same((drones[0] as TwinLaserDrone).pair(), (drones[1] as TwinLaserDrone).pair(), "sharing one rig")
		assert_not_null((drones[0] as TwinLaserDrone).pair())
	assert_eq(at_spawn.size(), 2, "announced")
	if at_spawn.size() == 2:
		var mid := ((at_spawn[0] as Vector2) + (at_spawn[1] as Vector2)) * 0.5
		assert_almost_eq(mid, cam.global_position + Vector2(0.0, -100.0) * ArenaCamera.WORLD_SCALE, Vector2.ONE * 0.01,
				"the midpoint is camera-relative design space")
