## Characterization tests for the shared StateMachine / State pair
## (global/statemachine/). Complex entities compose one of these with a
## `states/` folder of one State per file.
extends GutTest


## Records the lifecycle calls the machine makes, so ordering can be asserted.
class RecordingState extends State:
	var calls: Array[String] = []

	func enter() -> void:
		calls.append("enter")

	func exit() -> void:
		calls.append("exit")

	func process_physics(_delta: float):
		calls.append("physics")


func _machine(with_initial: bool = true) -> Array:
	var sm := StateMachine.new()
	var a := RecordingState.new()
	a.name = "StateA"
	var b := RecordingState.new()
	b.name = "StateB"
	sm.add_child(a)
	sm.add_child(b)
	if with_initial:
		sm.initial_state = a
	add_child_autofree(sm)
	return [sm, a, b]


func test_ready_enters_the_initial_state() -> void:
	var parts := _machine()
	var sm: StateMachine = parts[0]
	var a: RecordingState = parts[1]
	var b: RecordingState = parts[2]
	assert_eq(sm.current_state, a)
	assert_eq(a.calls, ["enter"] as Array[String])
	assert_eq(b.calls, [] as Array[String], "only the initial state is entered")


func test_no_initial_state_leaves_the_machine_idle() -> void:
	var parts := _machine(false)
	var sm: StateMachine = parts[0]
	var a: RecordingState = parts[1]
	assert_null(sm.current_state)
	assert_eq(a.calls, [] as Array[String])


func test_process_drives_only_the_current_state() -> void:
	var parts := _machine()
	var sm: StateMachine = parts[0]
	var a: RecordingState = parts[1]
	var b: RecordingState = parts[2]
	sm._process(0.016)
	sm._process(0.016)
	assert_eq(a.calls, ["enter", "physics", "physics"] as Array[String])
	assert_eq(b.calls, [] as Array[String])


func test_process_on_an_idle_machine_is_a_no_op() -> void:
	var parts := _machine(false)
	var sm: StateMachine = parts[0]
	sm._process(0.016)
	assert_null(sm.current_state)


func test_change_state_exits_the_old_and_enters_the_new() -> void:
	var parts := _machine()
	var sm: StateMachine = parts[0]
	var a: RecordingState = parts[1]
	var b: RecordingState = parts[2]
	sm.change_state(b)
	assert_eq(sm.current_state, b)
	assert_eq(a.calls, ["enter", "exit"] as Array[String])
	assert_eq(b.calls, ["enter"] as Array[String])


func test_changing_to_the_current_state_is_ignored() -> void:
	var parts := _machine()
	var sm: StateMachine = parts[0]
	var a: RecordingState = parts[1]
	sm.change_state(a)
	assert_eq(sm.current_state, a)
	assert_eq(a.calls, ["enter"] as Array[String], "no re-enter, no exit")


func test_change_state_to_null_is_ignored() -> void:
	var parts := _machine()
	var sm: StateMachine = parts[0]
	var a: RecordingState = parts[1]
	sm.change_state(null)
	assert_eq(sm.current_state, a, "the machine keeps running its current state")
	assert_eq(a.calls, ["enter"] as Array[String])


func test_states_request_transitions_through_their_own_signal() -> void:
	## _ready() connects every child State's `state_transition` to change_state,
	## which is how a state hands control to a sibling without knowing the machine.
	var parts := _machine()
	var sm: StateMachine = parts[0]
	var a: RecordingState = parts[1]
	var b: RecordingState = parts[2]
	a.state_transition.emit(b)
	assert_eq(sm.current_state, b)
	assert_eq(a.calls, ["enter", "exit"] as Array[String])
	assert_eq(b.calls, ["enter"] as Array[String])


func test_only_state_children_are_wired_up() -> void:
	var sm := StateMachine.new()
	var a := RecordingState.new()
	a.name = "StateA"
	var plain := Node.new()
	plain.name = "NotAState"
	sm.add_child(a)
	sm.add_child(plain)
	sm.initial_state = a
	add_child_autofree(sm)
	assert_eq(sm.current_state, a, "a non-State sibling is simply skipped")


func test_base_state_methods_are_inert_hooks() -> void:
	var s := State.new()
	s.enter()
	s.exit()
	assert_null(s.process_physics(0.016), "the base implementations do nothing")
	assert_true(s.has_signal("state_transition"))
	s.free()
