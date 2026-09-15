## INTENT tests for BoostMeter — the charge economy behind the open-space Shift boost
## (`docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md` →
## Design → "The meter: BoostMeter, a component beside the ship").
##
## Tree-less `BoostMeter.new()`, `free()`d in `after_each`: the component reads no Input, never
## touches the tree, and deliberately has NO `_physics_process` of its own — the ship calls
## `step(delta)` — which is exactly what makes it drivable by hand here.
##
## These are all green on a build where the meter is never added to `player_ship.tscn`.
## `tests/integration/test_open_space_boost_wiring.gd` is the file that catches that.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

## One physics frame at the project's 60 Hz.
const D: float = 1.0 / 60.0

var _meter: BoostMeter = null

## Two-layer discipline (`3-plan.md` → Test plan → "Autoload discipline"): `SaveSandbox` covers
## the `user://` file only, and the mid-session-upgrade case below binds a `BoostMeter` to the
## LIVE `ShipProgressionState`, which never re-reads the file after boot. Without the explicit
## snapshot/restore of the singleton's own members, that one case would leak a raised boost
## count into every test that runs after it in the same GUT process.
var _sandbox := SaveSandbox.new()
var _saved_boost: int = 0
var _saved_shields: int = 0


func before_all() -> void:
	_sandbox.capture()
	_saved_boost = ShipProgressionState._boost_charge_count
	_saved_shields = ShipProgressionState._permanent_shield_count


func after_all() -> void:
	ShipProgressionState._boost_charge_count = _saved_boost
	ShipProgressionState._permanent_shield_count = _saved_shields
	_sandbox.restore()


func before_each() -> void:
	## Assigned to the backing field directly, not via set_boost_charge_count(), so the fixture
	## does not depend on the code under test and writes nothing to disk.
	ShipProgressionState._boost_charge_count = ShipProgressionState.MIN_BOOST_CHARGES
	ShipProgressionState._permanent_shield_count = 1
	_meter = BoostMeter.new()
	## Explicit, not assumed: every case below except the mid-session-upgrade one is about the
	## meter's own economy, with no autoload in the loop.
	_meter.bind_progression = false


func after_each() -> void:
	if _meter != null:
		_meter.free()
		_meter = null


## Steps `seconds` worth of 60 Hz frames, the way the ship does.
func _step_seconds(seconds: float) -> void:
	var frames: int = int(round(seconds / D))
	for _i in range(frames):
		_meter.step(D)


## ── The starting state ───────────────────────────────────────────────────────────────────
func test_the_meter_starts_full() -> void:
	assert_eq(_meter.max_charges, 2, "the boost starts as a 2-charge meter")
	assert_almost_eq(_meter.charges, float(_meter.max_charges), 0.001,
			"a fresh meter is full — the player's first boost is never blocked")
	assert_true(_meter.can_spend(), "a full meter can spend")


## ── Spending ─────────────────────────────────────────────────────────────────────────────
func test_a_spend_costs_exactly_one_charge() -> void:
	var before: float = _meter.charges
	assert_true(_meter.try_spend(), "a full meter must grant the boost")
	assert_almost_eq(_meter.charges, before - 1.0, 0.001, "a boost costs exactly one charge")


## Boundary: pins "refuse", not "fire weakly" — a partially recharged meter has no half boost.
func test_a_partial_charge_refuses_and_spends_nothing() -> void:
	_meter.charges = 0.99
	assert_false(_meter.can_spend(), "0.99 of a charge is not a charge")
	assert_false(_meter.try_spend(), "a partial charge must refuse outright")
	assert_almost_eq(_meter.charges, 0.99, 0.0001, "a refused spend costs nothing")


func test_an_empty_meter_refuses_and_emits_nothing() -> void:
	_meter.charges = 0.0
	watch_signals(_meter)
	assert_false(_meter.try_spend(), "an empty meter must refuse")
	assert_eq(_meter.charges, 0.0, "a refused spend must not go negative")
	assert_signal_not_emitted(_meter, "charges_changed",
			"nothing changed, so nothing is announced")


## ── Recharging ───────────────────────────────────────────────────────────────────────────
## The pause after a spend (Overheat._SHOOT_GRACE uses the same 0.5 s, 30 lines away): without
## it a mashed key trickle-charges between activations.
func test_no_refill_during_the_pause_after_a_spend() -> void:
	assert_true(_meter.try_spend())
	var after_spend: float = _meter.charges
	_step_seconds(_meter.recharge_delay_sec - 0.01)
	assert_almost_eq(_meter.charges, after_spend, 0.0001,
			"the meter must not refill until recharge_delay_sec has elapsed")


func test_it_refills_at_the_stated_rate_once_the_pause_ends() -> void:
	assert_true(_meter.try_spend())
	_step_seconds(_meter.recharge_delay_sec)
	var at_start: float = _meter.charges
	_step_seconds(1.0)
	assert_almost_eq(_meter.charges - at_start, _meter.recharge_rate, 0.01,
			"one second of step() returns exactly recharge_rate charges")


## The epic's headline number: empty to full in ~3.4 s (0.5 s pause + 2 / 0.7 s).
func test_empty_to_full_takes_about_three_and_a_half_seconds() -> void:
	_meter.charges = 0.0
	_meter._delay_left = _meter.recharge_delay_sec
	_step_seconds(3.5)
	assert_almost_eq(_meter.charges, float(_meter.max_charges), 0.05,
			"empty to full is ~3.4 s at 0.7 charges/s after a 0.5 s pause")


## Boundary: the refill clamps, and a long idle never banks extra boosts.
func test_the_refill_clamps_at_max_charges() -> void:
	assert_true(_meter.try_spend())
	_step_seconds(60.0)
	assert_eq(_meter.charges, float(_meter.max_charges),
			"the meter tops out at max_charges exactly, never above")


func test_a_second_spend_restarts_the_pause() -> void:
	assert_true(_meter.try_spend())
	_step_seconds(0.4)
	assert_true(_meter.try_spend(), "the second charge is still there")
	var after_second: float = _meter.charges
	_step_seconds(0.4)
	assert_almost_eq(_meter.charges, after_second, 0.0001,
			"every spend restarts the pause — 0.4 s after the second one, still nothing back")


func test_stepping_zero_is_a_no_op() -> void:
	assert_true(_meter.try_spend())
	var before: float = _meter.charges
	watch_signals(_meter)
	_meter.step(0.0)
	assert_eq(_meter.charges, before, "step(0.0) changes nothing")
	assert_signal_not_emitted(_meter, "charges_changed", "step(0.0) announces nothing")


## ── The signal ───────────────────────────────────────────────────────────────────────────
## Declared with its parameters — `tests/integration/test_signal_emit_arity.gd` sweeps the
## declaration, this asserts what actually comes out of it, on both the spend and the refill.
func test_charges_changed_carries_current_and_maximum() -> void:
	watch_signals(_meter)
	assert_true(_meter.try_spend())
	var spend_params: Array = get_signal_parameters(_meter, "charges_changed", 0)
	assert_eq(spend_params.size(), 2, "charges_changed(current: float, maximum: int)")
	assert_almost_eq(float(spend_params[0]), _meter.charges, 0.0001,
			"first argument is the current charge level")
	assert_eq(int(spend_params[1]), _meter.max_charges, "second argument is the capacity")
	assert_typeof(spend_params[0], TYPE_FLOAT, "current is a float — partial charges exist")
	assert_typeof(spend_params[1], TYPE_INT, "maximum is a whole number of charges")

	## Delay cleared by hand rather than stepped down: 30 frames of 1/60 lands a hair either
	## side of 0.5 s depending on float rounding, which would make the emit count flaky.
	_meter._delay_left = 0.0
	_meter.step(D)
	assert_signal_emit_count(_meter, "charges_changed", 2,
			"a refill tick announces itself too, so the readout can animate")


## ── Persistence: the mid-session upgrade ─────────────────────────────────────────────────
## `bind_progression = true`, under the full two-layer autoload discipline above (before_each
## pins the live count to MIN_BOOST_CHARGES): raising the saved capacity mid-flight must widen
## the live meter AND grant the new charge immediately, not just on the next load.
func test_a_mid_session_upgrade_widens_the_meter_and_grants_the_charge_now() -> void:
	_meter.free()
	_meter = BoostMeter.new()
	_meter.bind_progression = true
	_meter._ready()   ## tree-less: nothing calls _ready() for us, so drive it by hand.

	assert_eq(_meter.max_charges, ShipProgressionState.MIN_BOOST_CHARGES,
			"a freshly bound meter takes its capacity from the live autoload")
	assert_almost_eq(_meter.charges, float(_meter.max_charges), 0.001, "and starts full")

	assert_true(_meter.try_spend(), "spend one so the grant is observable, not just a full meter")
	var before_grant: float = _meter.charges

	ShipProgressionState.set_boost_charge_count(3)

	assert_eq(_meter.max_charges, 3, "the meter's cap follows the raised save immediately")
	assert_almost_eq(_meter.charges, before_grant + 1.0, 0.001,
			"the new charge is granted right away, usable this session, not next")
