## INTENT tests for Phase 9 plan §2.6 (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md; task plan
## docs/plans/cmw5k4yjv00a6qs2xvkf73b18/3-plan.md): the enemy side of an EMP, and EMP against seekers.
##
## `BaseEnemy.answers_emp()` (default `is_ai_driven()`) is the routing question every EMP source asks. An enemy that
## answers it and gets `apply_emp(seconds, source)` halts (`mover.halt()`), its brain hears `on_emp_started()` once, a
## blue-white `EmpStatic` overlay shows, and for the window its brain is not ticked while its mover still steps; it
## stays tangible. The window follows the 1e-6 clock rule (2.0 s at 1/60 ends on tick 120). `suspend_ai()` clears a live
## window. A twin pair collapses when one drone is EMP'd and a Laser Tender drops a launch telegraph.
## `EmpPulse.TARGET_SEEKERS` jams the guidance of both sides' seeking rockets; DUMB rockets are untouched. The EMP mine
## reaches enemies only when placed (`Hostility.ALL`).
##
## Behaviour rows run in both harnesses (`tests/helpers/enemy_ai_harness.gd`), hand-ticked at 1/60; the bullet row runs
## on real physics at the 8x clock.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const FIGHTER: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
const GUNSHIP: PackedScene = preload("res://assault/scenes/enemies/gunship/gunship.tscn")
const SHIELD_GENERATOR: PackedScene = preload("res://assault/scenes/enemies/shield_generator/shield_generator.tscn")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const PAIR_SPAWN: PackedScene = preload("res://assault/scenes/enemies/twin_laser_drone/twin_laser_pair_spawn.tscn")
const DRONE_CONFIG: TwinLaserDroneConfig = preload("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone_config.tres")  # read only
const TENDER: PackedScene = preload("res://assault/scenes/enemies/laser_tender/laser_tender.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const MID := Vector2(640.0, 360.0)
## Where a Fighter starts: 250 px above the player, inside the Assault view, so the corridor never pushes it.
const FIGHTER_AT := Vector2(640.0, 110.0)
const SEED := 1
const _SPEEDUP := 8

## A brainless enemy that answers EMP anyway (the shape a structure's override takes, t7): the clock must still run.
class _AnsweringFixture extends "res://tests/helpers/fixture_enemy.gd":
	func answers_emp() -> bool:
		return true


## Stands in for a player in group `player`: records every `apply_emp`.
class _PlayerProbe extends Node2D:
	var hits: int = 0
	func apply_emp(_seconds: float, _source: Node) -> void:
		hits += 1


var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func after_each() -> void:
	if _clock_scaled:
		_clock_scaled = false
		Engine.time_scale = _saved_time_scale
		Engine.physics_ticks_per_second = _saved_ticks
		Engine.max_physics_steps_per_frame = _saved_max_steps


func _scale_clock() -> void:
	_clock_scaled = true
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP


# ── Helpers ─────────────────────────────────────────────────────────────────────────────────────────────────────────

func _world(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = MID
	return h


## A seeded, engaged Fighter at [param at], hand-ticked unless [param real].
func _fighter(h: RefCounted, at: Vector2 = FIGHTER_AT, real: bool = false) -> Fighter:
	var f := FIGHTER.instantiate() as Fighter
	f.global_position = at
	(f.get_node("Brain") as FighterBrain).rng_seed = SEED
	(f.get_node("Brain") as FighterBrain).start_engaged = true
	h.root.add_child(f)
	if not real:
		f.set_physics_process(false)
	return f


## One hand tick of an AI body: its own physics tick, then placed at `before + velocity * DT` (the test_fighter.gd rule).
func _tick(e: CharacterBody2D) -> void:
	var before := e.global_position
	e._physics_process(DT)
	if is_instance_valid(e) and not e.is_queued_for_deletion():
		e.global_position = before + e.velocity * DT


## Shots the Fighter has in flight right now, each put straight back in its pool (hand-ticked bullets never fly).
func _take_shots(f: Fighter) -> int:
	var n := 0
	for pool_name: String in ["AimedPool", "ForwardPool"]:
		var pool := f.get_node(pool_name) as BulletPool
		for bullet in pool._active.duplicate():
			n += 1
			pool._recycle(bullet)
	return n


func _overlay(e: Node) -> Node2D:
	return e.get_node_or_null("EmpStatic") as Node2D


func _overlay_visible(e: Node) -> bool:
	var o := _overlay(e)
	return o != null and o.visible


## The fixture enemy (brain + mover) in [param h], hand-ticked.
func _fixture(h: RefCounted, at: Vector2 = MID + Vector2(0, -200)) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	h.root.add_child(e)
	e.global_position = at
	e.set_physics_process(false)
	return e


func _fixture_brain(e: Node) -> EnemyBrain:
	return e.get_node("Brain") as EnemyBrain


# ── The routing question ──────────────────────────────────────────────────────────────────────────────────────────

func test_answers_emp_follows_is_ai_driven(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var f := _fighter(h)
	assert_true(f.answers_emp(), "%s: an AI Fighter answers" % mode)
	assert_true(_fixture(h).answers_emp(), "%s: the fixture enemy (brain + mover) answers" % mode)
	var gun := GUNSHIP.instantiate() as BaseEnemy
	h.root.add_child(gun)
	gun.set_physics_process(false)
	assert_false(gun.answers_emp(), "%s: a legacy Gunship (no brain) does not" % mode)
	var gen := SHIELD_GENERATOR.instantiate() as BaseEnemy
	h.root.add_child(gen)
	gen.set_physics_process(false)
	assert_false(gen.answers_emp(), "%s: a ShieldGenerator (a brain, no mover) does not" % mode)
	var railed := _fighter(h, FIGHTER_AT + Vector2(100, 0))
	railed.suspend_ai()
	assert_false(railed.answers_emp(), "%s: a railed Fighter does not" % mode)


func test_a_non_answering_enemy_ignores_apply_emp(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var gun := GUNSHIP.instantiate() as BaseEnemy
	h.root.add_child(gun)
	gun.set_physics_process(false)
	var gen := SHIELD_GENERATOR.instantiate() as BaseEnemy
	h.root.add_child(gen)
	gen.set_physics_process(false)
	var railed := _fighter(h)
	railed.suspend_ai()
	for e: BaseEnemy in [gun, gen, railed]:
		var hp := e.health.current_health
		e.apply_emp(2.0, null)
		assert_false(e.is_emp_disrupted(), "%s: %s is not disrupted" % [mode, e.name])
		assert_null(_overlay(e), "%s: %s grows no EmpStatic" % [mode, e.name])
		assert_eq(e.health.current_health, hp, "%s: %s health untouched" % [mode, e.name])


# ── The window ────────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_emp_window_is_exactly_120_ticks_and_the_longest_wins(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var e := _fixture(h)
	var brain := _fixture_brain(e)
	e.apply_emp(2.0, null)
	assert_eq(brain.emp_started_count, 1, "%s: on_emp_started once on the start" % mode)
	assert_true(e.is_emp_disrupted(), "%s: disrupted on the call" % mode)
	assert_true(_overlay_visible(e), "%s: the overlay shows on the call" % mode)
	var all_on := true
	for i in range(1, 120):
		if i == 30:
			e.apply_emp(1.0, null)  # 0.5 s: a shorter re-hit changes nothing
		_tick(e)
		all_on = all_on and e.is_emp_disrupted() and _overlay_visible(e)
	assert_true(all_on, "%s: disrupted, overlay shown, after ticks 1 .. 119" % mode)
	assert_eq(brain.tick_count, 0, "%s: the brain was never ticked in the window" % mode)
	assert_eq(brain.emp_started_count, 1, "%s: a re-hit is not a new start" % mode)
	_tick(e)
	assert_false(e.is_emp_disrupted(), "%s: over after tick 120 exactly (the 1e-6 rule)" % mode)
	assert_false(_overlay_visible(e), "%s: the overlay hides with it" % mode)
	assert_eq(brain.tick_count, 1, "%s: the brain ticks again on tick 120" % mode)

	var g := _fixture(h, MID + Vector2(200, -200))
	var gb := _fixture_brain(g)
	g.apply_emp(2.0, null)
	for i in 60:
		_tick(g)
	g.apply_emp(3.0, null)  # tick 60: 3.0 s remaining beats 1.0 s
	for i in 179:
		_tick(g)
	assert_true(g.is_emp_disrupted(), "%s: still disrupted after tick 239" % mode)
	_tick(g)
	assert_false(g.is_emp_disrupted(), "%s: over after tick 240 (60 + 180)" % mode)
	assert_eq(gb.emp_started_count, 1, "%s: one start" % mode)
	g.apply_emp(0.5, null)
	assert_eq(gb.emp_started_count, 2, "%s: a new EMP after the end is a new start" % mode)


func test_a_brainless_enemy_that_answers_emp_still_comes_out_of_it() -> void:
	var h := _world("open_space")
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	e.get_node("Brain").free()
	e.set_script(_AnsweringFixture)
	h.root.add_child(e)
	e.set_physics_process(false)
	assert_false(e.is_ai_driven(), "precondition: no brain")
	e.apply_emp(2.0, null)
	assert_true(e.is_emp_disrupted(), "an overridden answers_emp() lets the base window start")
	for i in 119:
		e._physics_process(DT)
	assert_true(e.is_emp_disrupted(), "disrupted after tick 119")
	e._physics_process(DT)
	assert_false(e.is_emp_disrupted(), "over after tick 120: the clock runs ahead of the no-brain return")
	assert_false(_overlay_visible(e), "and the overlay is hidden")


func test_emp_halts_a_committed_boost_on_the_call(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var f := _fighter(h)
	var mover := f.get_node("EnemyMover") as EnemyMover
	mover.boost(Vector2.RIGHT, 600.0, 1.0)  # test staging: a committed dash in progress
	_tick(f)
	assert_true(mover.is_boosting(), "%s: precondition: boosting" % mode)
	assert_gt(f.velocity.length(), 500.0, "%s: precondition: moving at boost speed" % mode)
	f.apply_emp(1.0, null)
	assert_false(mover.is_boosting(), "%s: the boost is cancelled on the call" % mode)
	assert_eq(f.velocity, Vector2.ZERO, "%s: and the ship stops dead" % mode)

	var c := _fighter(h, FIGHTER_AT + Vector2(-200, 0))
	var cm := c.get_node("EnemyMover") as EnemyMover
	cm.boost(Vector2.RIGHT, 600.0, 1.0)
	_tick(c)
	_tick(c)
	assert_true(cm.is_boosting(), "%s: control: without the EMP it is still boosting" % mode)


## The control run finds the Fighter's first shot; the EMP'd run (same seed, same start) fires nothing for the 2.0 s
## window, stands still, keeps its brain phase, and fires again afterwards.
func test_an_emp_d_fighter_fires_nothing_stands_still_and_resumes(mode: String = use_parameters(MODES)) -> void:
	var hc := _world(mode)
	var ctrl := _fighter(hc)
	var first := -1
	for i in range(1, 601):
		_tick(ctrl)
		if _take_shots(ctrl) > 0:
			first = i
			break
	assert_gt(first, 0, "%s: precondition: the control Fighter fires within 10 s" % mode)

	var h := _world(mode)
	var f := _fighter(h)
	var brain := f.get_node("Brain") as FighterBrain
	var phase0 := brain.phase
	f.apply_emp(2.0, null)
	var shots := 0
	var max_speed := 0.0
	var phase_kept := true
	for i in range(1, 120):
		_tick(f)
		shots += _take_shots(f)
		max_speed = maxf(max_speed, f.velocity.length())
		phase_kept = phase_kept and brain.phase == phase0
	assert_eq(shots, 0, "%s: no shot in the window" % mode)
	assert_lt(max_speed, 5.0, "%s: it stands still under the EMP" % mode)
	assert_true(phase_kept, "%s: the brain's phase is frozen" % mode)
	var resumed := false
	for i in first + 60:
		_tick(f)
		if _take_shots(f) > 0:
			resumed = true
			break
	assert_true(resumed, "%s: it fires again after the window" % mode)


func test_a_real_player_bullet_kills_an_emp_d_fighter(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h := _world(mode)
	var f := _fighter(h, FIGHTER_AT, true)
	f.health.current_health = 1
	f.apply_emp(5.0, null)
	var at_death: Array = []
	f.died.connect(func() -> void: at_death.append(f.is_emp_disrupted()))
	var b: Node2D = BULLET_SCENE.instantiate()
	h.root.add_child(b)
	b.global_position = FIGHTER_AT + Vector2(0, 110)
	b.rotation = 0.0  # flies along Vector2.UP
	b.expired.connect(b.queue_free)
	for i in 30:
		await get_tree().physics_frame
	assert_eq(at_death, [true], "%s: the bullet killed it while it was EMP'd (it stays tangible)" % mode)
	assert_true(not is_instance_valid(f) or f.was_killed, "%s: killed, not escaped" % mode)


func test_suspend_ai_mid_emp_clears_the_window(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var f := _fighter(h)
	f.apply_emp(2.0, null)
	for i in 30:
		_tick(f)
	assert_true(f.is_emp_disrupted() and _overlay_visible(f), "%s: precondition: disrupted at 0.5 s" % mode)
	f.suspend_ai()
	assert_false(f.is_emp_disrupted(), "%s: cleared on the suspend call" % mode)
	assert_false(_overlay_visible(f), "%s: overlay hidden on that call" % mode)
	var stayed := true
	for i in 180:
		f._physics_process(DT)
		stayed = stayed and not f.is_emp_disrupted() and not _overlay_visible(f)
	assert_true(stayed, "%s: and both stay so for the next 180 ticks" % mode)


# ── Beam carriers ─────────────────────────────────────────────────────────────────────────────────────────────────

func _pair(h: RefCounted) -> TwinLaserPair:
	var s := PAIR_SPAWN.instantiate() as TwinLaserPairSpawn
	s.rng_seed = 7
	s.position = MID + Vector2(0.0, -DRONE_CONFIG.standoff)
	h.root.add_child(s)
	var rig := s.spawn_pair()
	for d: Node2D in [rig.drone_a, rig.drone_b]:
		(d.get_node("Brain") as TwinLaserDroneBrain).start_engaged = true
		d.set_physics_process(false)
		(d as CharacterBody2D).collision_mask = 0
	return rig


func _step_pair(rig: TwinLaserPair) -> void:
	for d: Variant in [rig.drone_a, rig.drone_b]:
		if is_instance_valid(d) and not (d as Node).is_queued_for_deletion():
			_tick(d as CharacterBody2D)


func test_a_twin_pair_collapses_when_one_drone_is_emp_d(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var rig := _pair(h)
	var gone: Array = []
	rig.collapsed.connect(func(intact: bool) -> void: gone.append(intact))
	_step_pair(rig)
	assert_true(rig.is_intact(), "%s: precondition: intact" % mode)
	rig.drone_b.apply_emp(2.0, null)
	assert_true(rig.is_broken(), "%s: broken on the call" % mode)
	assert_eq(rig.phase, TwinLaserPair.Phase.COLLAPSED, "%s: COLLAPSED" % mode)
	assert_eq(gone, [false], "%s: collapsed(false) once" % mode)


func test_an_emp_d_leader_frees_its_lit_beam(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var rig := _pair(h)
	var advancing := false
	for i in 240:
		_step_pair(rig)
		if rig.phase == TwinLaserPair.Phase.ADVANCE:
			advancing = true
			break
	assert_true(advancing, "%s: precondition: the pair advances" % mode)
	var beam := rig.beam
	assert_true(is_instance_valid(beam), "%s: precondition: a beam" % mode)
	var a := rig.drone_a
	a.apply_emp(2.0, null)
	assert_true(rig.is_broken(), "%s: the pair broke" % mode)
	assert_null(rig.beam, "%s: the rig dropped the beam" % mode)
	assert_true(not is_instance_valid(beam) or beam.is_queued_for_deletion(), "%s: and it is freed, not frozen lit" % mode)
	for i in 121:
		_step_pair(rig)
	if is_instance_valid(a) and not a.is_queued_for_deletion():
		var p := (a.get_node("Brain") as TwinLaserDroneBrain).phase
		assert_ne(p, TwinLaserDroneBrain.Phase.ADVANCE, "%s: drone A no longer advances after the window" % mode)
		assert_ne(p, TwinLaserDroneBrain.Phase.TELEGRAPH, "%s" % mode)


func test_a_tender_emp_d_in_its_launch_telegraph_drops_it(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var t := TENDER.instantiate() as LaserTender
	var brain := t.get_node("Brain") as LaserTenderBrain
	brain.rng_seed = 11
	brain.start_engaged = true
	t.position = MID + Vector2(0, -260)
	h.root.add_child(t)
	t.set_physics_process(false)
	t.collision_mask = 0
	var light := t.get_node("StateLight") as StateLight
	brain.enter_phase(LaserTenderBrain.Phase.LAUNCH)
	assert_eq(light.get_state(), StateLight.State.CHARGING, "%s: precondition: the cradle telegraph shows" % mode)
	t.apply_emp(2.0, null)
	assert_eq(brain.phase, LaserTenderBrain.Phase.HOLD, "%s: the telegraph is dropped back to HOLD" % mode)
	assert_ne(light.get_state(), StateLight.State.CHARGING, "%s: the light stops charging on the call" % mode)
	for i in 119:
		_tick(t)
	assert_eq(t.launches(), 0, "%s: nothing launched in the window" % mode)

	var u := TENDER.instantiate() as LaserTender
	var ub := u.get_node("Brain") as LaserTenderBrain
	ub.start_engaged = true
	u.position = MID + Vector2(200, -260)
	h.root.add_child(u)
	u.set_physics_process(false)
	ub.enter_phase(LaserTenderBrain.Phase.LAUNCH)
	ub._leave_after_launch = true
	u.apply_emp(1.0, null)
	assert_eq(ub.phase, LaserTenderBrain.Phase.DISENGAGE, "%s: a spent budget leaves instead" % mode)


## Every brain of a mover-driven ship that carries a beam (`EnemyBeam`, `TwinLaserPair`) must say what an EMP does to it.
func test_every_beam_brain_of_a_mover_driven_ship_overrides_on_emp_started() -> void:
	var found: Array[String] = []
	var missing: Array[String] = []
	var dir := DirAccess.open("res://assault/scenes/enemies")
	for sub in dir.get_directories():
		var path := "res://assault/scenes/enemies/%s" % sub
		if not _dir_has_mover_scene(path):
			continue
		for file in DirAccess.get_files_at(path):
			if not file.ends_with("_brain.gd"):
				continue
			var src := FileAccess.get_file_as_string("%s/%s" % [path, file])
			if not _carries_a_beam(src):
				continue
			found.append(file)
			if not _overrides_on_emp_started(src):
				missing.append(file)
	assert_true(found.has("twin_laser_drone_brain.gd"), "the sweep finds the twin-laser drone brain (%s)" % [found])
	assert_true(found.has("laser_tender_brain.gd"), "the sweep finds the laser tender brain (%s)" % [found])
	assert_eq(missing, [] as Array[String], "every beam brain overrides on_emp_started()")
	# Boundary: the matcher really rejects a beam brain without the override.
	var synthetic := "extends EnemyBrain\nvar pair: TwinLaserPair\nfunc on_suspended() -> void:\n\tpass\n"
	assert_true(_carries_a_beam(synthetic) and not _overrides_on_emp_started(synthetic), "a synthetic beam brain without it is reported")


func _dir_has_mover_scene(path: String) -> bool:
	for file in DirAccess.get_files_at(path):
		if file.ends_with(".tscn") and FileAccess.get_file_as_string("%s/%s" % [path, file]).contains("enemy_mover.gd"):
			return true
	return false


func _carries_a_beam(src: String) -> bool:
	return src.contains("EnemyBeam") or src.contains("TwinLaserPair")


func _overrides_on_emp_started(src: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^func on_emp_started\\(")
	return re.search(src) != null


# ── Seekers ───────────────────────────────────────────────────────────────────────────────────────────────────────

func _enemy_rocket(parent: Node, kind: EnemyRocket.Kind, at: Vector2, dir: Vector2, aim: Vector2) -> EnemyRocket:
	var r: EnemyRocket = EnemyRocketScenes.scene_for(kind).instantiate()
	parent.add_child(r)
	r.global_position = at
	r.reset()
	r.set_physics_process(false)
	(r.get_node("ProjectileLifetime") as ProjectileLifetime).set_physics_process(false)
	r.launch(dir, aim, null)
	return r


func _tick_rocket(r: EnemyRocket) -> void:
	r._tick(DT)
	(r.get_node("ProjectileLifetime") as ProjectileLifetime)._physics_process(DT)


func _homing(parent: Node, at: Vector2, dir: Vector2, target: Node) -> homing_missile:
	var r: homing_missile = HOMING_SCENE.instantiate()
	r.locked_target = target
	parent.add_child(r)
	r.global_position = at
	r.rotation = dir.angle() + PI / 2.0
	r.set_physics_process(false)
	(r.get_node("ProjectileLifetime") as ProjectileLifetime).set_physics_process(false)
	return r


func _tick_homing(r: homing_missile) -> void:
	r._physics_process(DT)
	(r.get_node("ProjectileLifetime") as ProjectileLifetime)._physics_process(DT)


func test_seekers_in_radius_lose_guidance_and_a_dumb_rocket_is_unchanged(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	# The player's homing rocket, locked on a target off its nose.
	var target := Node2D.new()
	h.root.add_child(target)
	target.global_position = MID + Vector2(300, 0)
	var mine := _homing(h.root, MID + Vector2(0, 100), Vector2.UP, target)
	_tick_homing(mine)
	# An enemy Pursuit rocket inside its guidance window, and two DUMB rockets (one is the control, outside the pulse).
	var pursuit := _enemy_rocket(h.root, EnemyRocket.Kind.PURSUIT, MID + Vector2(-300, -200), Vector2.RIGHT, MID)
	assert_true(pursuit.is_in_group(SeekingOrdnance.ENEMY_GROUP), "%s: a guided rocket joins the enemy seeker group" % mode)
	var guiding := false
	for i in 120:
		_tick_rocket(pursuit)
		if pursuit.is_guiding():
			guiding = true
			break
	assert_true(guiding, "%s: precondition: the Pursuit rocket is guiding" % mode)
	var dumb := _enemy_rocket(h.root, EnemyRocket.Kind.DUMB, MID + Vector2(-100, -250), Vector2.DOWN, MID)
	var ctrl := _enemy_rocket(h.root, EnemyRocket.Kind.DUMB, MID + Vector2(-600, -250), Vector2.DOWN, MID + Vector2(-500, 0))
	assert_false(dumb.is_in_group(SeekingOrdnance.ENEMY_GROUP), "%s: a DUMB rocket never joins" % mode)

	EmpPulse.emit(get_tree(), MID, 400.0, 2.0, null, EmpPulse.TARGET_SEEKERS)  # the control, 650 px out, is not reached

	assert_false(pursuit.is_guiding(), "%s: the Pursuit rocket's guidance ends at once" % mode)
	var mine_heading := mine.rotation
	var pursuit_heading := pursuit.heading()
	var mine_kept := true
	var pursuit_kept := true
	var dumb_same := true
	for i in 30:
		_tick_homing(mine)
		_tick_rocket(pursuit)
		_tick_rocket(dumb)
		_tick_rocket(ctrl)
		mine_kept = mine_kept and absf(angle_difference(mine.rotation, mine_heading)) < 1e-5
		pursuit_kept = pursuit_kept and pursuit.heading().is_equal_approx(pursuit_heading)
		dumb_same = dumb_same and (dumb.global_position - ctrl.global_position).is_equal_approx(Vector2(500, 0))
	assert_true(mine_kept, "%s: the player's homing rocket flies straight" % mode)
	assert_true(pursuit_kept, "%s: the Pursuit rocket flies straight" % mode)
	assert_true(dumb_same, "%s: a DUMB rocket flies exactly as its control" % mode)

	# Group hygiene: out once its life ends, out again after a pool reset.
	pursuit._detonate()
	assert_false(pursuit.is_in_group(SeekingOrdnance.ENEMY_GROUP), "%s: out of the group once it detonates" % mode)
	var again := _enemy_rocket(h.root, EnemyRocket.Kind.PURSUIT, MID + Vector2(300, -200), Vector2.LEFT, MID)
	again.jam_guidance(null)
	again.reset()
	assert_false(again.is_in_group(SeekingOrdnance.ENEMY_GROUP), "%s: out after reset()" % mode)
	again.launch(Vector2.LEFT, MID, null)
	assert_true(again.is_in_group(SeekingOrdnance.ENEMY_GROUP), "%s: back in on the next launch" % mode)
	for i in 120:
		_tick_rocket(again)
		if again.is_guiding():
			break
	assert_true(again.is_guiding(), "%s: reset() clears a jam: the next life guides again" % mode)


# ── The EMP mine ──────────────────────────────────────────────────────────────────────────────────────────────────

func _emp_mine(h: RefCounted, at: Vector2, placed: bool) -> EnemyMine:
	var m := EnemyMineScenes.scene_for(EnemyMine.Variant.EMP).instantiate() as EnemyMine
	m.process_mode = Node.PROCESS_MODE_DISABLED
	if placed:
		m.hostility = EnemyMine.Hostility.ALL
	h.root.add_child(m)
	m.global_position = at
	m.launch(Vector2.ZERO, 0.0, at)
	return m


func _detonate_mine(m: EnemyMine) -> void:
	m.chain_trigger(0.0)
	var lt := m.get_node("ProjectileLifetime") as ProjectileLifetime
	for i in 3:
		if not is_instance_valid(m):
			return
		m._physics_process(DT)
		if is_instance_valid(lt):
			lt._physics_process(DT)


func test_an_enemy_laid_emp_mine_never_reaches_enemies_and_a_placed_one_does(mode: String = use_parameters(MODES)) -> void:
	for placed: bool in [false, true]:
		var h := _world(mode)
		var at := MID + Vector2(2000.0 if placed else 0.0, -150)  # apart, so one world never reaches the other
		var probe := _PlayerProbe.new()
		probe.add_to_group(&"player")
		h.root.add_child(probe)
		probe.global_position = at + Vector2(-60, 0)
		var f := _fighter(h, at + Vector2(60, 0))
		assert_true(f.is_in_group(&"enemies"), "precondition: the Fighter is in group enemies")
		_detonate_mine(_emp_mine(h, at, placed))
		assert_eq(probe.hits, 1, "%s placed=%s: the player beside it is reached" % [mode, placed])
		assert_eq(f.is_emp_disrupted(), placed, "%s placed=%s: an enemy is reached only by a placed mine" % [mode, placed])
