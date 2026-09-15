## INTENT tests for BoostBar — the readout task of the boost epic
## (`docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md`,
## "The bar" and "Test plan" → `test_boost_bar.gd`).
##
## Every case here needs `add_child_autofree(ship)`, not just the overlap one: the bar is
## constructed in `OpenSpacePlayerShip._ready()` (mirroring `_overheat_bar`), so on a
## merely-instantiated ship there is no `BoostBar` child at all and even "the bar is in the
## scene" fails.
##
## Autoload discipline, the shape of `test_open_space_boost_wiring.gd`: from the persistence
## task onward `player_ship.tscn`'s `BoostMeter` reads the LIVE `ShipProgressionState` in its
## own `_ready()`. This file is written before that binding exists, so the two-layer pattern
## below is inert today and correct the day the persistence task lands.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

var _sandbox := SaveSandbox.new()
var _saved_boost: int = 0
var _saved_shields: int = 0


func before_all() -> void:
	_sandbox.capture()
	_saved_boost = _live_boost_count()
	_saved_shields = ShipProgressionState._permanent_shield_count


func after_all() -> void:
	_set_live_boost_count(_saved_boost)
	ShipProgressionState._permanent_shield_count = _saved_shields
	_sandbox.restore()


func before_each() -> void:
	_set_live_boost_count(_default_boost_count())
	ShipProgressionState._permanent_shield_count = 1


func _live_boost_count() -> int:
	if "_boost_charge_count" in ShipProgressionState:
		return int(ShipProgressionState.get("_boost_charge_count"))
	return 0


func _set_live_boost_count(value: int) -> void:
	if "_boost_charge_count" in ShipProgressionState:
		ShipProgressionState.set("_boost_charge_count", value)


func _default_boost_count() -> int:
	if "MIN_BOOST_CHARGES" in ShipProgressionState:
		return int(ShipProgressionState.get("MIN_BOOST_CHARGES"))
	return 2


func _spawn_ship() -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	return ship


func _bar_of(ship: Node) -> BoostBar:
	for child: Node in ship.get_children():
		if child is BoostBar:
			return child as BoostBar
	return null


func _meter_of(ship: Node) -> BoostMeter:
	for child: Node in ship.get_children():
		if child is BoostMeter:
			return child as BoostMeter
	return null


## ── The bar is actually in the scene ─────────────────────────────────────────────────────
func test_the_ship_carries_a_boost_bar() -> void:
	var ship := _spawn_ship()
	var bar := _bar_of(ship)
	assert_not_null(bar, "OpenSpacePlayerShip._ready() must create a BoostBar child")
	if bar == null:
		return
	assert_true(bar.top_level, "the bar must be top_level, like the overheat bar")


## ── It is visible at full — a hidden readout is the failure mode ────────────────────────
func test_the_bar_is_visible_at_full_charges() -> void:
	var ship := _spawn_ship()
	var bar := _bar_of(ship)
	assert_not_null(bar)
	if bar == null:
		return
	assert_true(bar.visible, "a boost meter at full charge must still be visible")


## ── Seeded at _ready(), before any signal — the N3 hole ─────────────────────────────────
## Children _ready() before parents, so BoostMeter's initial state exists before
## OpenSpacePlayerShip._ready() calls setup(). Connect-only would leave `_max_charges` at 0
## until the first spend. "visible at full" passes on the broken build too (visible defaults
## true) — this is the case that does not.
func test_the_bar_is_seeded_from_the_meter_at_ready_with_no_signal_emitted() -> void:
	var ship := _spawn_ship()
	var bar := _bar_of(ship)
	var meter := _meter_of(ship)
	assert_not_null(bar)
	assert_not_null(meter)
	if bar == null or meter == null:
		return
	assert_eq(bar._max_charges, meter.max_charges,
			"the bar must be seeded from the meter's current max_charges at _ready(), " +
			"not only after the first charges_changed signal")


## ── Boundary: it does not overlap the overheat bar ───────────────────────────────────────
## Physics is left running here (unlike every other case) because the bars' global_position
## is only updated from OpenSpacePlayerShip._physics_process() — a frozen ship never moves
## either bar off (0, 0), which would trivially "pass" a same-position check.
func test_the_boost_bar_does_not_overlap_the_overheat_bar() -> void:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.velocity = Vector2.ZERO
	await wait_physics_frames(2)
	var bar := _bar_of(ship)
	assert_not_null(bar)
	if bar == null:
		return
	var overheat: OverheatBar = null
	for child: Node in ship.get_children():
		if child is OverheatBar:
			overheat = child as OverheatBar
	assert_not_null(overheat, "expected the ship to also carry an OverheatBar")
	if overheat == null:
		return
	var dy: float = absf(bar.global_position.y - overheat.global_position.y)
	assert_gte(dy, OverheatBar.BAR_HEIGHT,
			"the boost bar must sit clear of the overheat bar's 4 px height")


## ── Segments follow capacity ──────────────────────────────────────────────────────────────
func test_segments_follow_capacity_on_signal() -> void:
	var ship := _spawn_ship()
	var bar := _bar_of(ship)
	assert_not_null(bar)
	if bar == null:
		return
	bar._on_charges_changed(2.0, 4)
	assert_eq(bar._max_charges, 4,
			"_draw()'s segment loop reads _max_charges, which the handler must update")


## ── The fill tracks current, not just capacity ────────────────────────────────────────────
func test_fill_tracks_current_charges_for_smooth_refill() -> void:
	var ship := _spawn_ship()
	var bar := _bar_of(ship)
	assert_not_null(bar)
	if bar == null:
		return
	bar._on_charges_changed(2.0, 4)
	bar._on_charges_changed(3.5, 4)
	assert_eq(bar._charges, 3.5,
			"a partially-recharged segment must be representable so the refill animates")


## ── Boundary: capacity 0 does not divide by zero ──────────────────────────────────────────
func test_zero_capacity_does_not_error_on_draw() -> void:
	var ship := _spawn_ship()
	var bar := _bar_of(ship)
	assert_not_null(bar)
	if bar == null:
		return
	bar._on_charges_changed(0.0, 0)
	assert_eq(bar._max_charges, 0)
