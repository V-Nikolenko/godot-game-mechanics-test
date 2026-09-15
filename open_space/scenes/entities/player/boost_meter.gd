# open_space/scenes/entities/player/boost_meter.gd
## The cost side of the open-space Shift boost: a small pool of discrete charges that a boost
## spends one of, and that refills on its own after a short pause.
##
## Lives beside the ship rather than in `global/components/`, and is a child node of
## `player_ship.tscn`, because the boost is an open-space verb — the same placement
## `ShipTurnController` uses. (`class_name` registers globally whatever directory the file sits
## in, so the directory signals intent; the enforcement is the pair of invariant cases in
## `tests/integration/test_open_space_boost_wiring.gd`.)
##
## Deliberately NOT a reuse of `Shield`, which implements four of the same five behaviours:
## `Shield`'s charge is entangled with `consume_one()` on the incoming-damage chain, with
## temporary charges, with the hacked state and with `ShieldIconStrip`'s snapshot Dictionary.
## A boost charge is spent by a verb and refills on a timer. Merging them would grow a
## damage-path component an upgrade-meter concept to save ~20 lines. See
## `docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md`.
##
## Continuous internal float, whole-unit spends: the refill animates instead of popping, while
## "+1 boost" stays legible as a pip. There is no exhaustion/soft-failure state — boost is the
## verb the player crosses the hub with, and an empty meter simply refuses while W/S still fly
## the ship.
class_name BoostMeter
extends Node

## Emitted on every change, declared with exactly what it emits
## (`tests/integration/test_signal_emit_arity.gd` sweeps this).
## `current` is a float so a partially recharged charge is representable.
signal charges_changed(current: float, maximum: int)

@export var recharge_rate: float = 0.7          ## charges per second
## Pause after a spend before any refill starts, at the value `Overheat._SHOOT_GRACE` already
## uses: without it a mashed key trickle-charges between activations.
@export var recharge_delay_sec: float = 0.5
## Take `max_charges` from `ShipProgressionState` instead of the local default. Mirrors
## `Shield.bind_progression` (`shield_component.gd:20,38-46,116-124`) line for line, including
## the immediate grant of the new charge on a mid-session upgrade.
@export var bind_progression: bool = true

var max_charges: int = 2
var charges: float = 2.0

## Seconds left of the post-spend pause.
var _delay_left: float = 0.0


func _ready() -> void:
	if bind_progression:
		max_charges = ShipProgressionState.boost_charge_count
		ShipProgressionState.boost_charge_count_changed.connect(_on_progression_changed)
	charges = float(max_charges)


func can_spend() -> bool:
	return charges >= 1.0


## Spend one whole charge. Returns false — changing and announcing nothing — when the meter
## cannot afford it, which is what makes an empty meter a refusal rather than a weak boost.
func try_spend() -> bool:
	if not can_spend():
		return false
	charges -= 1.0
	_delay_left = recharge_delay_sec
	charges_changed.emit(charges, max_charges)
	return true


## Driven by `OpenSpacePlayerShip._step_boost()`, NOT by a `_physics_process` of our own.
## That is deliberate and differs from `Overheat`: `set_physics_process(false)` on the ship
## (which `MissionTrigger._open_menu()` calls) does not stop a child's own physics tick, so a
## self-ticking meter would keep charging while a mission menu is open — and a hand-driven
## step() is what makes this component testable in a headless run.
func step(delta: float) -> void:
	if delta <= 0.0:
		return
	if _delay_left > 0.0:
		## The pause eats only as much of the frame as it needs; the remainder still
		## recharges, so the refill rate does not depend on where the frame boundary fell.
		var used: float = minf(_delay_left, delta)
		_delay_left -= used
		delta -= used
		if delta <= 0.0:
			return
	if charges >= float(max_charges):
		return
	charges = minf(charges + recharge_rate * delta, float(max_charges))
	charges_changed.emit(charges, max_charges)


## `ShipProgressionState.boost_charge_count_changed` — mirrors
## `Shield._on_progression_changed` (`shield_component.gd:116-124`): raises the cap and grants
## the new charge immediately, so a pickup collected mid-flight is usable now rather than next
## session, not just wider on the next boot.
func _on_progression_changed(new_max: int) -> void:
	max_charges = new_max
	charges = clampf(charges, 0.0, float(max_charges))
	if charges < float(max_charges):
		charges = minf(charges + 1.0, float(max_charges))
	charges_changed.emit(charges, max_charges)
