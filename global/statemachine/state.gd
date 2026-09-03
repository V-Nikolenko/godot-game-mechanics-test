class_name State
extends Node

## Emitted by a state to hand control to a sibling without knowing its machine.
## `StateMachine._ready()` connects this to `change_state`, which is why the target
## State travels as the argument (`dash_state.gd:55`, `move_state.gd:50`).
signal state_transition(new_state: State)

func enter() -> void:
	pass
	
func process_physics(delta: float):
	pass
	
func exit() -> void:
	pass
