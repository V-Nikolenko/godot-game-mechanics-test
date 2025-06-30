class_name StateMachine
extends Node

# NodePath to the state that should be active when the machine starts.
@export var initial_state: NodePath

var current_state: State
var states: Dictionary = {}

func _ready():
        for child in get_children():
                if child is State:
                        states[child.name] = child
                        child.state_transition.connect(change_state)

        if initial_state != NodePath():
                var start_state: State = get_node_or_null(initial_state)
                if start_state:
                        start_state.enter()
                        current_state = start_state

func _physics_process(delta: float) -> void:
        if current_state:
                current_state.physics_process(delta)

func change_state(new_state : State):
        if !new_state:
                return

	if current_state == new_state:
		print("Same state. Ignoring")
		return


	print("Exiting previous state: " + current_state.name)

	if current_state:
		current_state.exit()

	print("Entering new state: " + new_state.name)
	new_state.enter()

        current_state = new_state

func change_state_by_name(state_name: String) -> void:
        var state = states.get(state_name)
        if state:
                change_state(state)
