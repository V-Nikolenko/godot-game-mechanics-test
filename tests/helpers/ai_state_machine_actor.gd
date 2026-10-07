## Root script for `ai_state_machine_fixture.tscn`: a `path_mover_actor.gd` that also answers the
## `suspend_ai()` contract a brain-driven `BaseEnemy` has (a deliberate no-op).
##
## The old subject of `tests/integration/test_enemy_path_mover.gd`'s AIStateMachine case, the
## Light Assault Ship, was a `BaseEnemy` and so had `suspend_ai()` *and* an AIStateMachine. That
## combination is what makes the case fail if `EnemyPathMover._ready()`'s "AIStateMachine" name
## lookup is ever turned into an else-branch of `if _actor.has_method("suspend_ai")`: the method
## exists, so the else-branch never runs, and the legacy state machine keeps moving the host.
## Without this method the regression would take the else path and the test would stay green.
##
## No `class_name`: test-only types stay out of the global class list.
extends "res://tests/helpers/path_mover_actor.gd"


func suspend_ai() -> void:
	pass
