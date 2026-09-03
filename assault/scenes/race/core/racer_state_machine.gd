## RacerStateMachine — holds a racer's State children, injects the host into each, ticks the
## current state on demand (RaceShip drives the order), and transitions by node NAME. Bespoke
## decision logic lives in the State subclasses, never here.
class_name RacerStateMachine
extends Node

@export var initial_state_name: StringName = &""

var host: RaceShip = null
var current: State = null
var _states: Dictionary = {}   ## StringName -> State

func setup(p_host: RaceShip) -> void:
	host = p_host
	for child in get_children():
		if child is State:
			_states[child.name] = child
			child.set("host", host)      ## inject; each race State declares `var host: RaceShip`
	var start := _states.get(initial_state_name, null) as State
	if start == null and not _states.is_empty():
		start = _states.values()[0]
	current = start
	if current:
		current.enter()

func tick(delta: float) -> void:
	if current:
		current.process_physics(delta)

func transition_to(state_name: StringName) -> void:
	var next := _states.get(state_name, null) as State
	if next == null or next == current:
		return
	if current:
		current.exit()
	current = next
	current.enter()

func get_state(state_name: StringName) -> State:
	return _states.get(state_name, null)
