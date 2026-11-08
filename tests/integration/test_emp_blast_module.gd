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
