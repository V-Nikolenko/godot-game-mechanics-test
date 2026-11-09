## INTENT tests for Phase 9 plan §2.7: the player's EMP Blast routes by the duck-typed `answers_emp()`. An enemy that
## answers gets `apply_emp(5.0, player)` and stays tangible; every other enemy keeps the legacy process-disable path.
## The cooldown (15 s), the immune list (RamCorvette) and the scene-wide reach are unchanged.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const FIGHTER: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
const GUNSHIP: PackedScene = preload("res://assault/scenes/enemies/gunship/gunship.tscn")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const DT := 1.0 / 60.0
const _SPEEDUP := 8

## A brainless enemy that answers EMP anyway (the jammer's shape): it must go through apply_emp.
class _Answering extends "res://tests/helpers/fixture_enemy.gd":
	var emp_calls: Array = []
	func answers_emp() -> bool:
		return true
	func apply_emp(seconds: float, source: Node) -> void:
		emp_calls.append([seconds, source])

var _saved_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_steps: int = 8
var _scaled: bool = false


func after_each() -> void:
	if _scaled:
		_scaled = false
		Engine.time_scale = _saved_scale
		Engine.physics_ticks_per_second = _saved_ticks
		Engine.max_physics_steps_per_frame = _saved_steps


func _scale_clock() -> void:
	_scaled = true
	_saved_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_steps = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_steps * _SPEEDUP
	Engine.time_scale = _saved_scale * _SPEEDUP


func _world() -> RefCounted:
	var h: RefCounted = HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = Vector2(640.0, 360.0)
	return h


func test_brain_driven_enemy_is_emp_d_for_five_seconds_and_stays_shootable() -> void:
	_scale_clock()
	var h := _world()
	var f := FIGHTER.instantiate() as Fighter
	f.global_position = Vector2(640.0, 110.0)
	(f.get_node("Brain") as FighterBrain).start_engaged = true
	h.root.add_child(f)
	f.health.current_health = 1
	var module := EMPBlastModule.new()
	assert_true(module.try_activate(h.player))
	assert_true(f.is_emp_disrupted(), "EMP'd by the module")
	assert_ne(f.process_mode, Node.PROCESS_MODE_DISABLED, "not process-disabled")
	var b: Node2D = BULLET_SCENE.instantiate()
	h.root.add_child(b)
	b.global_position = Vector2(640.0, 220.0)
	b.rotation = 0.0
	b.expired.connect(b.queue_free)
	for i in 30:
		await get_tree().physics_frame
	assert_true(not is_instance_valid(f) or f.was_killed, "a real bullet still damages it")


func test_emp_window_is_five_seconds() -> void:
	var h := _world()
	var f := FIGHTER.instantiate() as Fighter
	f.global_position = Vector2(640.0, 110.0)
	h.root.add_child(f)
	f.set_physics_process(false)
	EMPBlastModule.new().try_activate(h.player)
	for i in 299:
		f._physics_process(DT)
	assert_true(f.is_emp_disrupted(), "still disrupted just before 5 s")
	for i in 3:
		f._physics_process(DT)
	assert_false(f.is_emp_disrupted(), "over after 5 s")


func test_legacy_enemy_is_still_process_disabled_for_five_seconds() -> void:
	_scale_clock()
	Engine.time_scale = _saved_scale * 40.0  ## only the module's SceneTreeTimer runs here; no physics
	var h := _world()
	var g := GUNSHIP.instantiate() as BaseEnemy
	h.root.add_child(g)
	assert_false(g.answers_emp(), "the legacy Gunship does not answer")
	EMPBlastModule.new().try_activate(h.player)
	assert_eq(g.process_mode, Node.PROCESS_MODE_DISABLED, "disabled")
	await get_tree().create_timer(5.2).timeout
	assert_ne(g.process_mode, Node.PROCESS_MODE_DISABLED, "restored after 5 s")


func test_cooldown_is_fifteen_seconds() -> void:
	var h := _world()
	var m := EMPBlastModule.new()
	assert_true(m.try_activate(h.player))
	assert_false(m.try_activate(h.player), "on cooldown")
	m.tick(h.player, 14.9)
	assert_false(m.try_activate(h.player), "still on cooldown at 14.9 s")
	m.tick(h.player, 0.2)
	assert_true(m.try_activate(h.player), "ready after 15 s")


func test_brainless_answering_enemy_goes_through_apply_emp() -> void:
	var h := _world()
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	e.get_node("Brain").free()
	e.set_script(_Answering)
	e.set_physics_process(false)
	e.add_to_group(&"enemies")
	h.root.add_child(e)
	EMPBlastModule.new().try_activate(h.player)
	assert_eq(e.emp_calls.size(), 1, "apply_emp called once")
	assert_eq(e.emp_calls[0][0], 5.0, "for 5 s")
	assert_eq(e.emp_calls[0][1], h.player, "sourced by the player")
	assert_ne(e.process_mode, Node.PROCESS_MODE_DISABLED, "not process-disabled")


# ── Phase 9 t7: the jammer (plan §2.8). Both real player scenes, hand-ticked at 1/60; the jammer root, its `Field`, the
# field art and `AssaultDrift` have physics / process off for the whole row and are hand-ticked root first, then the field,
# so the 8x frames a bullet flies on advance neither the BaseEnemy EMP clock nor the suppression clock. ─────────────────

const JAMMER: PackedScene = preload("res://assault/scenes/enemies/jamming_structure/jamming_structure.tscn")
const PULSED_JAMMER: PackedScene = preload("res://assault/scenes/enemies/pulsed_jammer/pulsed_jammer.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_PLAYER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const MODES := ["open_space", "assault"]
const JAMMER_AT := Vector2(640.0, 200.0)

var _sandbox := SaveSandbox.new()
var _saved_equipped: Dictionary = {}


func before_all() -> void:
	_sandbox.capture()
	for slot: StringName in ShipModuleState.SLOTS:
		_saved_equipped[slot] = ShipModuleState.get_equipped(slot)


func after_all() -> void:
	for slot: StringName in ShipModuleState.SLOTS:
		ShipModuleState._equipped[slot] = _saved_equipped[slot]
	_sandbox.restore()


func before_each() -> void:
	for slot: StringName in ShipModuleState.SLOTS:
		ShipModuleState._equipped[slot] = &""


func _hand_jammer(parent: Node, scene: PackedScene = JAMMER, at: Vector2 = JAMMER_AT) -> JammingStructure:
	var j := scene.instantiate() as JammingStructure
	j.position = at
	parent.add_child(j)
	j.set_physics_process(false)
	j.set_process(false)
	j.field().set_physics_process(false)
	(j.get_node("Field/Art") as Node).set_process(false)
	(j.get_node("AssaultDrift") as AssaultDrift).set_physics_process(false)
	return j


func _step_jammer(j: JammingStructure, ticks: int) -> void:
	for i in ticks:
		j._physics_process(DT)
		j.field()._physics_process(DT)


## A real player alone in [param box], physics off, with only `emp_blast` in its H loop.
func _real_player(mode: String, box: Node, at: Vector2) -> Array:
	var p := (SHIP_SCENE if mode == "open_space" else FIGHTER_PLAYER_SCENE).instantiate() as PlayerBase
	box.add_child(p)
	p.set_physics_process(false)
	p.global_position = at
	p.velocity = Vector2.ZERO
	var mod := ShipModuleBase.create(&"emp_blast")
	mod.apply(p)
	p._module_pool[&"emp_blast"] = mod
	return [p, mod]


## One H press through the engine's own input dispatch (`_input` of every node, so exactly one player may be in the tree).
func _push_h() -> bool:
	assert_eq(get_tree().get_nodes_in_group(&"player").size(), 1, "precondition: exactly one player gets the push")
	var ev := InputEventAction.new()
	ev.action = &"use_ability"
	ev.pressed = true
	get_viewport().push_input(ev)
	return get_viewport().is_input_handled()


func test_from_outside_the_field_the_blast_switches_a_jammer_off_for_five_seconds(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var box := Node2D.new()
	add_child_autofree(box)
	var j := _hand_jammer(box)
	var info := j.field().hazard_info()
	var pm := _real_player(mode, box, JAMMER_AT + Vector2(0.0, j.field().radius + 120.0))  # 120 px outside the 240 px field
	var p: PlayerBase = pm[0]
	p._step_disruption(DT)
	assert_false(p.abilities_locked(), "%s: precondition: unlocked outside" % mode)
	assert_true(info.disables_abilities, "%s: precondition: lit" % mode)
	assert_true(_push_h(), "%s: the press is consumed" % mode)
	assert_eq(float(pm[1].get(&"_cooldown_left")), 15.0, "%s: the 15 s cooldown started" % mode)
	assert_true(j.is_emp_disrupted(), "%s: the jammer took the tangible EMP" % mode)
	assert_eq(j.process_mode, Node.PROCESS_MODE_INHERIT, "%s: not process-disabled" % mode)
	_step_jammer(j, 1)
	assert_false(info.disables_abilities, "%s: quiet on the next tick" % mode)
	var hp := j.health.current_health
	var b: Node2D = BULLET_SCENE.instantiate()
	box.add_child(b)
	b.global_position = JAMMER_AT + Vector2(0.0, 80.0)
	b.rotation = 0.0
	b.expired.connect(b.queue_free)
	for i in 30:
		await get_tree().physics_frame
		if j.health.current_health < hp:
			break
	assert_lt(j.health.current_health, hp, "%s: a real bullet damages the suppressed jammer" % mode)
	_step_jammer(j, 298)
	assert_false(info.disables_abilities, "%s: still quiet after tick 299" % mode)
	_step_jammer(j, 2)
	assert_true(info.disables_abilities, "%s: lit again by tick 301 (5.0 s)" % mode)


func test_inside_a_lit_field_the_blast_press_is_refused(mode: String = use_parameters(MODES)) -> void:
	var box := Node2D.new()
	add_child_autofree(box)
	var j := _hand_jammer(box)
	var pm := _real_player(mode, box, JAMMER_AT + Vector2(0.0, 100.0))
	var p: PlayerBase = pm[0]
	var refusals: Array = []
	p.ability_press_refused.connect(func() -> void: refusals.append(true))
	p._step_disruption(DT)
	assert_true(p.abilities_locked(), "%s: precondition: locked inside" % mode)
	assert_true(_push_h(), "%s: the press is consumed" % mode)
	assert_eq(refusals.size(), 1, "%s: and refused" % mode)
	assert_eq(float(pm[1].get(&"_cooldown_left")), 0.0, "%s: the cooldown is untouched" % mode)
	_step_jammer(j, 1)
	assert_true(j.field().hazard_info().disables_abilities, "%s: the field stays lit" % mode)
	assert_false(j.is_emp_disrupted(), "%s: the jammer was not EMP'd" % mode)


## Bypasses the H seam on purpose (it would refuse the press inside the field): the module's own `try_activate()` reaches the
## jammer scene-wide, the field goes quiet, and the player inside unlocks after the field's 0.75 s stabilisation.
func test_a_direct_try_activate_from_inside_quiets_the_field_and_the_ship_unlocks_0_75_s_later(
		mode: String = use_parameters(MODES)) -> void:
	var box := Node2D.new()
	add_child_autofree(box)
	var j := _hand_jammer(box)
	var pm := _real_player(mode, box, JAMMER_AT + Vector2(0.0, 100.0))
	var p: PlayerBase = pm[0]
	p._step_disruption(DT)
	assert_true(p.abilities_locked(), "%s: precondition: locked inside" % mode)
	assert_true((pm[1] as EMPBlastModule).try_activate(p), "%s: the module fires (seam bypassed)" % mode)
	_step_jammer(j, 1)
	assert_false(j.field().hazard_info().disables_abilities, "%s: quiet on the next tick" % mode)
	p._step_disruption(DT)  # the exit tick T: the field no longer disables abilities
	for i in 44:
		p._step_disruption(DT)
	assert_true(p.abilities_locked(), "%s: locked at T+44" % mode)
	p._step_disruption(DT)
	assert_false(p.abilities_locked(), "%s: unlocked at T+45 (0.75 s)" % mode)
