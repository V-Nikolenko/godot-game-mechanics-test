## INTENT tests for Phase 7 plan §2.6 (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md): both player ships can have their
## boost weakened for a few seconds through one hook on `PlayerBase`.
##
## `apply_boost_disruption(strength, seconds)` sets a strength (strongest wins) and a time (longest wins); while it lasts
## `boost_efficiency()` is `1 - strength`. A disrupted boost speed scales only its excess over a floor
## (`floor + (speed - floor) * efficiency`): `cruise_speed()` for the Shift boost and the Boost Drive, the dash's own
## lateral `move_speed` for the roll. Below `MIN_BOOST_EFFICIENCY` every boost verb is refused before anything is spent.
##
## Both real players (`player_ship.tscn`, `player_fighter.tscn`), set up as `test_player_hazards.gd` does: in the tree with
## their own `_physics_process` off, every step hand-ticked at 60 Hz. Nothing here awaits. The Boost Drive rows equip the real
## module through `ShipModuleState`, under the `SaveSandbox` + snapshot discipline of `test_open_space_boost_verb.gd`.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

const D: float = 1.0 / 60.0
const MODES: Array = ["open_space", "assault"]

var _sandbox := SaveSandbox.new()
var _saved_engine_equipped: StringName = &""
var _saved_engine_unlocked: Array = []


func before_all() -> void:
	_sandbox.capture()
	_saved_engine_equipped = ShipModuleState.get_equipped(&"engines")
	_saved_engine_unlocked = (ShipModuleState._unlocked[&"engines"] as Array).duplicate()


func after_all() -> void:
	ShipModuleState._equipped[&"engines"] = _saved_engine_equipped
	ShipModuleState._unlocked[&"engines"] = _saved_engine_unlocked
	_sandbox.restore()


func before_each() -> void:
	ShipModuleState._equipped[&"engines"] = &""
	(ShipModuleState._unlocked[&"engines"] as Array).clear()


func after_each() -> void:
	Input.action_release("move_up")
	DialogPlayer.is_active = false


func _equip_engine_boost() -> void:
	ShipModuleState.unlock(&"engines", &"engine_boost")
	ShipModuleState.equip(&"engines", &"engine_boost")


func _ship() -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	ship.rotation = 0.0
	ship.velocity = Vector2.ZERO
	return ship


## `box` (optional) parents the fighter in an autofreed container: the warp drops its ghost into the fighter's parent,
## and a ghost left on the test script outlives the test as an unfreed child.
func _fighter(box: Node = null) -> AssaultPlayer:
	var f := FIGHTER_SCENE.instantiate() as AssaultPlayer
	if box != null:
		box.add_child(f)
	else:
		add_child_autofree(f)
	f.set_physics_process(false)
	f.global_position = Vector2(640, 360)
	return f


func _player(mode: String) -> PlayerBase:
	return _ship() if mode == "open_space" else _fighter()


func _tick(p: PlayerBase, ticks: int) -> void:
	for i in range(ticks):
		p._step_disruption(D)


func _h_press() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"use_ability"
	ev.pressed = true
	return ev


# --- The hook (both ships) --------------------------------------------------------------------------------------------


func test_efficiency_is_one_until_disrupted_then_recovers_after_the_time(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	assert_eq(p.boost_efficiency(), 1.0, "%s: default efficiency is 1.0" % mode)
	p.apply_boost_disruption(0.6, 2.5)
	assert_almost_eq(p.boost_efficiency(), 0.4, 0.0001, "%s: strength 0.6 -> efficiency 0.4" % mode)
	_tick(p, 149)  # 2.483 s
	assert_almost_eq(p.boost_efficiency(), 0.4, 0.0001, "%s: still 0.4 one tick before 2.5 s" % mode)
	_tick(p, 2)  # 2.517 s: the end is within one tick of 2.5 s
	assert_eq(p.boost_efficiency(), 1.0, "%s: back to 1.0 within a tick of 2.5 s" % mode)


func test_the_strongest_and_the_longest_win_and_never_stack(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	p.apply_boost_disruption(0.6, 1.0)
	p.apply_boost_disruption(0.3, 3.0)
	assert_almost_eq(p.boost_efficiency(), 0.4, 0.0001,
			"%s: the stronger 0.6 holds (never 0.4 x 0.7 = 0.28, never replaced by 0.3)" % mode)
	_tick(p, 120)  # 2.0 s: past the first one's time, inside the second's
	assert_almost_eq(p.boost_efficiency(), 0.4, 0.0001, "%s: the longer time holds the stronger strength" % mode)
	_tick(p, 62)  # 3.03 s
	assert_eq(p.boost_efficiency(), 1.0, "%s: over after the longest time" % mode)

	var q := _player(mode)
	q.apply_boost_disruption(0.3, 1.0)
	q.apply_boost_disruption(0.6, 0.5)
	assert_almost_eq(q.boost_efficiency(), 0.4, 0.0001, "%s: a stronger later one raises the strength" % mode)
	_tick(q, 54)  # 0.9 s: the shorter second one's time does not cut the first's
	assert_almost_eq(q.boost_efficiency(), 0.4, 0.0001, "%s: still live at 0.9 s" % mode)


func test_a_zero_strength_or_zero_time_does_nothing(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got: Array = []
	p.boost_disruption_changed.connect(func(e: float) -> void: got.append(e))
	p.apply_boost_disruption(0.0, 2.0)
	p.apply_boost_disruption(0.6, 0.0)
	assert_eq(p.boost_efficiency(), 1.0, "%s: neither is a disruption" % mode)
	assert_eq(got.size(), 0, "%s: and neither announces one" % mode)


func test_the_signal_is_declared_and_emitted_with_its_arity(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var args: Array = []
	for s: Dictionary in p.get_signal_list():
		if s.name == "boost_disruption_changed":
			args = s.args
	assert_eq(args.size(), 1, "%s: boost_disruption_changed(efficiency: float) declares one argument" % mode)
	if args.size() == 1:
		assert_eq(int(args[0].type), TYPE_FLOAT, "%s: and it is a float" % mode)
	var got: Array = []
	p.boost_disruption_changed.connect(func(e: float) -> void: got.append(e))
	p.apply_boost_disruption(0.6, 1.0)
	p.apply_boost_disruption(0.6, 2.0)  # longer only: the efficiency does not change
	p.apply_boost_disruption(0.9, 0.5)  # stronger: it does
	_tick(p, 121)
	assert_eq(got.size(), 3, "%s: start, change and end, and nothing for a longer-only re-apply: %s" % [mode, got])
	if got.size() == 3:
		assert_almost_eq(float(got[0]), 0.4, 0.0001, "%s: start" % mode)
		assert_almost_eq(float(got[1]), 0.1, 0.0001, "%s: change" % mode)
		assert_eq(float(got[2]), 1.0, "%s: end" % mode)


func test_the_spark_ring_shows_for_the_duration(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var ring := p.get_node_or_null("BoostDisruptionRing") as Line2D
	assert_true(ring == null or not ring.visible, "%s: no ring before a disruption" % mode)
	p.apply_boost_disruption(0.6, 0.5)
	ring = p.get_node_or_null("BoostDisruptionRing") as Line2D
	assert_not_null(ring, "%s: a code-built Line2D ring" % mode)
	if ring == null:
		return
	assert_true(ring.visible, "%s: visible while disrupted" % mode)
	assert_true(ring.closed and ring.points.size() >= 12, "%s: a closed ring" % mode)
	_tick(p, 31)
	assert_false(ring.visible, "%s: hidden once it ends" % mode)


# --- The clock is wired into each ship's own physics tick (anti-inert) ------------------------------------------------
# Every other row steps `_step_disruption()` by hand, so all of them stay green on a build whose ships never call it, where
# a disruption would never end. These drive only the ship's own `_physics_process`.


func test_the_ships_own_physics_tick_ends_a_disruption(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	p.apply_boost_disruption(0.6, 0.1)
	for i in range(3):
		p._physics_process(D)
	assert_almost_eq(p.boost_efficiency(), 0.4, 0.0001, "%s: still disrupted at 0.05 s" % mode)
	for i in range(4):
		p._physics_process(D)
	assert_eq(p.boost_efficiency(), 1.0, "%s: the ship's own tick ended a 0.1 s disruption" % mode)


func test_assault_clock_runs_through_a_dialog_a_knockback_and_an_engine_boost() -> void:
	var f := _fighter()
	DialogPlayer.is_active = true
	f.apply_boost_disruption(0.6, 0.1)
	for i in range(7):
		f._physics_process(D)
	assert_eq(f.boost_efficiency(), 1.0, "the dialog's early return comes after the clock")
	DialogPlayer.is_active = false
	var g := _fighter()
	g.apply_knockback(Vector2(5000.0, 0.0))
	g.apply_boost_disruption(0.6, 0.1)
	for i in range(7):
		g._physics_process(D)
	assert_true(g.is_knockback_active(), "precondition: the knockback is still running")
	assert_eq(g.boost_efficiency(), 1.0, "the knockback's early return comes after the clock")
	var h := _fighter()
	h.engine_boost_active = true
	h.apply_boost_disruption(0.6, 0.1)
	for i in range(7):
		h._physics_process(D)
	assert_eq(h.boost_efficiency(), 1.0, "the engine boost's early return comes after the clock")


func test_cruise_speed_is_normal_flight_and_is_read_not_cached() -> void:
	var ship := _ship()
	assert_eq(ship.cruise_speed(), 420.0, "Open Space cruise is max_speed 420")
	ship.max_speed = 300.0
	assert_eq(ship.cruise_speed(), 300.0, "read from max_speed, never cached")
	var f := _fighter()
	var move_state := f.get_node("MovementStateMachine/MoveState")
	assert_eq(f.cruise_speed(), 360.0, "Assault cruise is MoveState.move_speed 360")
	move_state.move_speed = 200.0
	assert_eq(f.cruise_speed(), 200.0, "read from MoveState, never cached")


# --- Open Space: the Shift boost --------------------------------------------------------------------------------------


func test_open_space_disrupted_boost_buys_only_part_of_the_excess_at_the_normal_drain() -> void:
	var ship := _ship()
	var twin := _ship()
	ship.apply_boost_disruption(0.6, 5.0)
	ship._step_boost(true, true, D)
	twin._step_boost(true, true, D)
	var expected: float = ship.max_speed + (ship.boost_exit_speed - ship.max_speed) * 0.4
	assert_almost_eq(expected, 532.0, 0.001, "sanity: 420 + 280 x 0.4")
	assert_almost_eq(ship.velocity.length(), expected, 1.0, "the boost starts at 532 px/s")
	assert_almost_eq(twin.velocity.length(), ship.boost_exit_speed, 0.5, "control: undisrupted it is 700")
	for i in range(10):
		ship._step_boost(false, true, D)
		twin._step_boost(false, true, D)
	assert_almost_eq(ship.velocity.length(), expected, 1.0, "the sustain holds 532 px/s")
	assert_almost_eq(ship._speed_ceiling, expected, 1.0, "and the ceiling is the disrupted boost speed")
	assert_eq(ship._boost_meter.charges, twin._boost_meter.charges,
			"a disrupted boost drains exactly as much as an undisrupted one")


func test_open_space_boost_is_refused_below_the_floor_with_nothing_spent() -> void:
	var ship := _ship()
	ship.velocity = Vector2(0, -200)
	var before: float = ship._boost_meter.charges
	ship.apply_boost_disruption(0.9, 5.0)
	ship._step_boost(true, true, D)
	assert_false(ship._boosting, "efficiency 0.1 < 0.15 refuses the boost")
	assert_eq(ship.velocity, Vector2(0, -200), "no velocity write")
	assert_eq(ship._boost_meter.charges, before, "no drain")
	assert_eq(ship._boost_hold_left, 0.0, "no hold window left behind by a refused press")


func test_open_space_boost_starts_exactly_at_the_floor() -> void:
	var ship := _ship()
	ship.apply_boost_disruption(0.85, 5.0)  # efficiency 0.15: the floor is inclusive
	ship._step_boost(true, true, D)
	assert_true(ship._boosting, "efficiency exactly MIN_BOOST_EFFICIENCY still boosts")
	assert_almost_eq(ship.velocity.length(), 420.0 + 280.0 * 0.15, 1.0, "at 462 px/s")
	var under := _ship()
	under.apply_boost_disruption(0.86, 5.0)  # efficiency 0.14
	under._step_boost(true, true, D)
	assert_false(under._boosting, "just under the floor is refused")


func test_open_space_boost_ends_on_the_tick_the_efficiency_drops_to_zero() -> void:
	var ship := _ship()
	var twin := _ship()
	for s: OpenSpacePlayerShip in [ship, twin]:
		s._step_boost(true, true, D)
		for i in range(3):
			s._step_boost(false, true, D)
		s.rotation = PI / 2.0  # the nose turns right; a running sustain would re-assert velocity along it
	assert_true(ship._boosting, "precondition: boosting")
	var charges_before: float = ship._boost_meter.charges
	ship.apply_boost_disruption(1.0, 1.0)
	ship._step_boost(false, true, D)
	twin._step_boost(false, true, D)
	assert_false(ship._boosting, "the boost stops on the tick the efficiency reaches 0")
	assert_eq(ship._boost_meter.charges, charges_before, "no drain on that tick")
	assert_almost_eq(ship.velocity.normalized().y, -1.0, 0.001, "no velocity write along the turned nose")
	assert_true(twin._boosting, "control: the undisrupted twin is still boosting")
	assert_almost_eq(twin.velocity.normalized().x, 1.0, 0.001, "control: its sustain re-asserts along the turned nose")


# --- Open Space: the Boost Drive --------------------------------------------------------------------------------------


func test_open_space_boost_drive_refused_below_the_floor_spends_no_tank() -> void:
	_equip_engine_boost()
	var ship := _ship()
	var meter := ship._boost_meter
	var charges: float = meter.charges
	var tanks: int = meter.tanks
	assert_gt(tanks, 1, "precondition: the Drive partitions the bar into tanks")
	ship.apply_boost_disruption(0.9, 5.0)
	ship._step_boost(true, true, D)
	assert_eq(meter.charges, charges, "a refused Drive press spends no tank")
	assert_eq(meter.tanks, tanks, "and the tank count is unchanged")
	assert_false(ship.engine_boost_active, "the Drive did not activate")
	assert_false(ship._boosting, "and the press did not fall through into the default boost")


func test_open_space_boost_drive_disrupted_burst_scales_only_the_excess_over_cruise() -> void:
	_equip_engine_boost()
	var ship := _ship()
	var meter := ship._boost_meter
	var before: float = meter.charges
	ship.apply_boost_disruption(0.6, 5.0)
	ship._step_boost(true, true, D)
	assert_true(ship.engine_boost_active, "efficiency 0.4 still fires the Drive")
	assert_almost_eq(meter.charges, before - meter.tank_size(), 0.0001, "one tank spent")
	assert_almost_eq(ship.velocity.length(), 852.0, 1.0, "420 + (1500 - 420) x 0.4")
	var mod: ShipModuleBase = ship._module_pool[&"engine_boost"]
	var last: float = ship.velocity.length()
	var lowest: float = last
	var ticks: int = 0
	while ship.engine_boost_active and ticks < 120:
		mod.tick(ship, D)
		last = ship.velocity.length()
		lowest = minf(lowest, last)
		ticks += 1
	assert_false(ship.engine_boost_active, "precondition: the burst ended")
	assert_almost_eq(last, 452.0, 1.0, "the eased tail ends at 420 + (500 - 420) x 0.4")
	assert_gte(lowest, ship.max_speed, "a disrupted burst never drops below cruise")


# --- Assault ----------------------------------------------------------------------------------------------------------


func test_assault_disrupted_dash_rolls_slower_but_never_below_its_lateral_speed() -> void:
	var f := _fighter()
	var dash: DashState = f.get_node("MovementStateMachine/DashState")
	f.apply_boost_disruption(0.6, 5.0)
	dash.dashing_direction = Vector2.RIGHT
	dash.dashing_timer.start()
	dash.process_physics(D)
	assert_almost_eq(f.velocity.x, 248.0, 1.0, "180 + (350 - 180) x 0.4")
	assert_gte(f.velocity.x, dash.move_speed, "never below the dash's own move_speed")


func test_assault_dash_is_refused_below_the_floor() -> void:
	var f := _fighter()
	var machine: StateMachine = f.get_node("MovementStateMachine")
	var dash: DashState = f.get_node("MovementStateMachine/DashState")
	f.apply_boost_disruption(0.9, 5.0)
	dash.start_state_transition("move_right")
	assert_true(dash.dashing_timer.is_stopped(), "the roll did not start")
	assert_ne(machine.current_state, dash, "the machine is not in DashState")

	var g := _fighter()
	var g_machine: StateMachine = g.get_node("MovementStateMachine")
	var g_dash: DashState = g.get_node("MovementStateMachine/DashState")
	g_dash.start_state_transition("move_right")
	assert_eq(g_machine.current_state, g_dash, "control: undisrupted the same press dashes")


func test_assault_warp_blink_distance_follows_the_efficiency() -> void:
	var distances: Array = []
	for strength: float in [0.0, 0.6, 0.9]:
		var box := Node2D.new()
		add_child_autofree(box)
		var f := _fighter(box)
		WarpModule.new().apply(f)
		if strength > 0.0:
			f.apply_boost_disruption(strength, 5.0)
		var dash: DashState = f.get_node("MovementStateMachine/DashState")
		var start: Vector2 = f.global_position
		dash.start_state_transition("move_right")
		distances.append(f.global_position.x - start.x)
	assert_almost_eq(float(distances[0]), 120.0, 0.5, "control: an undisrupted blink is 120 px")
	assert_almost_eq(float(distances[1]), 48.0, 0.5, "at efficiency 0.4 the blink is 48 px")
	assert_almost_eq(float(distances[2]), 0.0, 0.0001, "below the floor the blink is refused")


func test_assault_h_key_boost_drive_follows_the_efficiency() -> void:
	_equip_engine_boost()
	var refused := _fighter()
	refused.apply_boost_disruption(0.9, 5.0)
	refused._input(_h_press())
	assert_false(refused.engine_boost_active, "H is refused below the floor")
	var weak := _fighter()
	weak.apply_boost_disruption(0.6, 5.0)
	weak._input(_h_press())
	assert_true(weak.engine_boost_active, "H fires at efficiency 0.4")
	assert_almost_eq(weak.velocity.length(), 816.0, 1.0, "360 + (1500 - 360) x 0.4")


# --- Controls: normal flight is never touched -------------------------------------------------------------------------


func test_open_space_cruise_thrust_and_ceiling_are_unchanged_while_disrupted() -> void:
	var ship := _ship()
	var twin := _ship()
	ship.apply_boost_disruption(0.6, 5.0)
	Input.action_press("move_up")
	for i in range(30):
		ship._handle_thrust(D)
		twin._handle_thrust(D)
	assert_eq(ship.velocity, twin.velocity, "cruise thrust is bit-identical while disrupted")
	Input.action_release("move_up")
	ship.velocity = Vector2.UP * 900.0
	twin.velocity = Vector2.UP * 900.0
	ship._step_boost(false, false, D)
	twin._step_boost(false, false, D)
	assert_eq(ship.velocity, twin.velocity, "and so is the cruise ceiling clamp")
	assert_almost_eq(ship.velocity.length(), ship.max_speed, 0.01, "at max_speed")


func test_assault_cruise_is_unchanged_while_disrupted() -> void:
	var f := _fighter()
	var move_state := f.get_node("MovementStateMachine/MoveState")
	f.apply_boost_disruption(0.6, 5.0)
	move_state.move(Vector2.RIGHT)
	assert_eq(f.velocity.x, move_state.move_speed, "normal flight is never disrupted")


# --- Readability: the Open Space boost bar ----------------------------------------------------------------------------


func test_open_space_boost_bar_tints_violet_while_disrupted() -> void:
	var ship := _ship()
	var bar: BoostBar = ship._boost_bar
	var normal: Color = bar._fill_color()
	ship.apply_boost_disruption(0.6, 0.5)
	assert_eq(bar._fill_color(), BoostBar._FILL_COLOR_DISRUPTED, "violet while disrupted")
	assert_ne(BoostBar._FILL_COLOR_DISRUPTED, normal, "sanity: violet is not the normal fill")
	bar._process(0.05)  # the bar's own flicker clock (its _process does not run in a hand-ticked test)
	assert_lt(bar.modulate.a, 1.0, "the bar flickers while disrupted")
	_tick(ship, 31)
	assert_eq(bar._fill_color(), normal, "back to the tier colour after")
	assert_eq(bar.modulate, Color.WHITE, "and the flicker is cleared")
