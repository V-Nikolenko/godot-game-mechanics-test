## Characterization tests for the Overheat component.
##
## The instance is deliberately kept OUT of the scene tree so `_physics_process`
## only advances when a test calls it — heat dissipation is then exact rather
## than dependent on real frame timing.
extends GutTest

var _oh: Overheat
var _pct: Array[float]


func before_each() -> void:
	_oh = Overheat.new()
	_pct = []
	_oh.overheat.connect(func(p: float) -> void: _pct.append(p))


func after_each() -> void:
	_oh.free()


func test_defaults() -> void:
	assert_eq(_oh.heat_limit, 20.0)
	assert_eq(_oh.cooldown_time, 10.0)
	assert_eq(_oh.heat, 0.0)


func test_increase_heat_adds_and_reports_a_percentage() -> void:
	_oh.increase_heat(5.0)
	assert_almost_eq(_oh.heat, 5.0, 0.0001)
	assert_eq(_pct.size(), 1)
	assert_almost_eq(_pct[0], 25.0, 0.0001, "5 of a 20 limit is 25%")


func test_heat_saturates_at_the_limit() -> void:
	_oh.increase_heat(999.0)
	assert_almost_eq(_oh.heat, 20.0, 0.0001)
	assert_almost_eq(_pct[0], 100.0, 0.0001)


func test_heat_does_not_dissipate_during_the_shoot_grace_window() -> void:
	## The grace window exists so heat cannot bleed off between two shots of a
	## slow weapon. It must outlast the longest fire interval in the game.
	_oh.increase_heat(10.0)
	_oh._physics_process(0.4)
	assert_almost_eq(_oh.heat, 10.0, 0.0001, "still inside the 0.5 s grace window")
	assert_eq(_pct.size(), 1, "no cooling emission while held")


func test_heat_dissipates_once_the_grace_window_lapses() -> void:
	_oh.increase_heat(10.0)
	_oh._physics_process(0.5)            ## burns exactly the grace window
	assert_almost_eq(_oh.heat, 10.0, 0.0001)
	_oh._physics_process(1.0)            ## rate = heat_limit / cooldown_time = 2.0 / s
	assert_almost_eq(_oh.heat, 8.0, 0.0001)
	assert_almost_eq(_pct[-1], 40.0, 0.0001)


func test_a_full_bar_cools_off_in_cooldown_time_seconds() -> void:
	_oh.increase_heat(20.0)
	_oh._physics_process(0.5)            ## grace
	_oh._physics_process(10.0)           ## cooldown_time
	assert_almost_eq(_oh.heat, 0.0, 0.0001)


func test_heat_never_goes_below_zero() -> void:
	_oh.increase_heat(1.0)
	_oh._physics_process(0.5)
	_oh._physics_process(100.0)
	assert_eq(_oh.heat, 0.0)


func test_shooting_again_refreshes_the_grace_window() -> void:
	_oh.increase_heat(10.0)
	_oh._physics_process(0.4)
	_oh.increase_heat(2.0)               ## resets _no_shoot_timer to 0.5
	_oh._physics_process(0.4)
	assert_almost_eq(_oh.heat, 12.0, 0.0001, "the window restarts on every shot")


func test_a_cold_component_emits_nothing_while_idling() -> void:
	_oh._physics_process(1.0)
	_oh._physics_process(1.0)
	assert_eq(_pct, [] as Array[float], "zero heat means no per-frame signal traffic")
