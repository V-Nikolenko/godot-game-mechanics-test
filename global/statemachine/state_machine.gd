class_name StateMachine
extends Node

@export var initial_state: State
var current_state: State

func _ready():
	for child in get_children():
		if child is State:
			child.state_transition.connect(change_state) #On signal method in connect will be called

	if initial_state:
		initial_state.enter()
		current_state = initial_state

func _process(delta):
	if current_state:
		current_state.process_physics(delta)

func change_state(new_state : State):
	if !new_state:
		return
	
	if current_state == new_state:
		_log("Same state. Ignoring")
		return
	
	## Both the log line and exit() live behind the guard: a machine built without an
	## `initial_state` has no current_state to name, and reading `.name` off null here
	## used to kill the first transition outright.
	if current_state:
		_log("Exiting previous state: " + current_state.name)
		current_state.exit()
		
	_log("Entering new state: " + new_state.name)
	new_state.enter()
	
	current_state = new_state


## Transition tracing. Off unless Godot was started with `--verbose` — every player dash,
## shot and move cycles states, so unconditionally this is several lines per second.
func _log(message: String) -> void:
	if OS.is_stdout_verbose():
		print("[StateMachine] %s: %s" % [name, message])
