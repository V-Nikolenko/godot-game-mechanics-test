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

func change_state(source_state : State, new_state : State):
	if !new_state:
		return
		
	if current_state:
		current_state.exit()
		
	new_state.enter()
	
	current_state = new_state
