## INTENT tests for AITargetingModule's snap, the duck-typing hole this epic opened.
##
## Nothing in the suite activated AITargetingModule before this file (`grep -rl
## ai_targeting tests/` found only test_ship_module_state.gd, which never calls
## try_activate()). Two things could ship silently broken without this: a misspelled
## has_method("face_instant") guard, and a change to face_instant() that quietly
## altered the assault fighter's snap.
extends GutTest

const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")

var _module: AITargetingModule


func before_each() -> void:
	_module = AITargetingModule.new()


func _spawn_enemy(pos: Vector2) -> Node2D:
	var enemy := Node2D.new()
	enemy.add_to_group("enemies")
	add_child_autofree(enemy)
	enemy.global_position = pos
	return enemy


## The duck-typing hole: a misspelled has_method() guard would leave this case
## returning true with the stub's recorded angle at its default (0.0), not the
## computed one.
func test_module_calls_face_instant_and_leaves_rotation_alone() -> void:
	var actor := _FaceInstantStub.new()
	add_child_autofree(actor)
	actor.global_position = Vector2(100.0, 100.0)
	actor.rotation = 0.0
	var enemy := _spawn_enemy(Vector2(100.0, 0.0))  ## straight "up" from the actor

	var activated := _module.try_activate(actor)

	var dir: Vector2 = enemy.global_position - actor.global_position
	var expected_angle: float = dir.angle() + PI * 0.5
	assert_true(activated, "a reachable enemy activates the module")
	assert_eq(actor.face_instant_calls, 1, "face_instant must be called exactly once")
	assert_almost_eq(actor.last_angle, expected_angle, 1e-6, "with the angle to the enemy")
	assert_eq(actor.rotation, 0.0, "the module must not write rotation directly")


## The B3 regression gate: activating this module against a real assault fighter must
## still land exactly where ai_targeting_module.gd's old `actor.rotation = ...` did.
func test_assault_fighter_snap_is_unchanged() -> void:
	var fighter := FIGHTER_SCENE.instantiate() as AssaultPlayer
	add_child_autofree(fighter)
	fighter.set_physics_process(false)
	fighter.global_position = Vector2(200.0, 200.0)
	fighter.rotation = 0.0
	var enemy := _spawn_enemy(Vector2(500.0, 260.0))

	var activated := _module.try_activate(fighter)

	var dir: Vector2 = enemy.global_position - fighter.global_position
	var expected_angle: float = dir.angle() + PI * 0.5
	assert_true(activated, "a reachable enemy activates the module")
	assert_almost_eq(fighter.rotation, expected_angle, 1e-6, "same angle the old direct write produced")


## Boundary: an actor that cannot face is left alone entirely, and — critically — the
## 15-second cooldown is NOT spent, so a stray call against a facing-less actor cannot
## eat a player's ability.
func test_actor_without_face_instant_is_left_alone_and_keeps_its_cooldown() -> void:
	var actor := Node2D.new()
	add_child_autofree(actor)
	actor.global_position = Vector2.ZERO
	actor.rotation = 1.23
	_spawn_enemy(Vector2(50.0, 50.0))

	var activated := _module.try_activate(actor)
	assert_false(activated, "an actor with no face_instant() cannot be snapped")
	assert_almost_eq(actor.rotation, 1.23, 1e-6, "rotation must be untouched")

	## Cooldown not spent: a second call (with a face-capable actor) still succeeds.
	var capable := _FaceInstantStub.new()
	add_child_autofree(capable)
	capable.global_position = Vector2.ZERO
	var second_activation := _module.try_activate(capable)
	assert_true(second_activation, "the failed call above must not have spent the cooldown")


## Minimal duck-typed target for face_instant(), recording calls without touching
## rotation itself — proves the module drives through the method, not the property.
class _FaceInstantStub:
	extends Node2D
	var face_instant_calls: int = 0
	var last_angle: float = 0.0
	func face_instant(angle: float) -> void:
		face_instant_calls += 1
		last_angle = angle
