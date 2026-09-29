## Stand-in for a legacy `AIStateMachine` child: it moves its parent from `_process`, the way the
## Fighter's old `FighterApproachState` / `FighterStrafeExitState` did (`actor.velocity = ...` then
## `move_and_slide()` from `StateMachine._process`). `set_physics_process(false)` on the host does
## NOT stop this — only `EnemyPathMover`'s "AIStateMachine" name lookup does, which is what
## `tests/integration/test_enemy_path_mover.gd` pins with this fixture (Ph1 decision: the lookup
## stays until Phase 15).
##
## No `class_name`: test-only types stay out of the global class list.
extends Node

const SPEED := 80.0


func _process(_delta: float) -> void:
	var actor := get_parent() as CharacterBody2D
	if actor == null:
		return
	actor.velocity = Vector2(0.0, SPEED)
	actor.move_and_slide()
