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


func test_change_state_from_an_idle_machine_enters_without_crashing() -> void:
	## Not characterization — this asserts intent. `change_state()` used to read
	## `current_state.name` for a log line BEFORE its own `if current_state:` guard,
	## so the first transition of a machine built without an `initial_state` died on
	## a null dereference. Latent rather than live only because every shipped machine
	## happens to set one.
	var parts := _machine(false)
	var sm: StateMachine = parts[0]
	var a: RecordingState = parts[1]
	var b: RecordingState = parts[2]
	assert_null(sm.current_state, "precondition: the machine starts idle")
	sm.change_state(b)
	assert_eq(sm.current_state, b, "the machine adopts the new state")
	assert_eq(b.calls, ["enter"] as Array[String], "and enters it")
	assert_eq(a.calls, [] as Array[String], "nothing is exited, there was nothing to exit")


func test_state_transition_declares_the_state_it_emits() -> void:
	## Not characterization — asserts intent. `state_transition` is emitted with the
	## target State (`dash_state.gd:55`, `move_state.gd:50`), so it must be declared
	## with one, or `StateMachine.change_state` looks like an arity mismatch to a reader.
	var s := State.new()
	var args: Array = []
	for sig in s.get_signal_list():
		if sig["name"] == "state_transition":
			args = sig["args"]
	assert_eq(args.size(), 1, "state_transition is emitted with the target state")
	assert_eq(args[0]["type"], TYPE_OBJECT, "and that argument is an object")
	s.free()
