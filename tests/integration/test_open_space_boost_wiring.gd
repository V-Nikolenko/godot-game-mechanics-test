## INTENT tests for the wiring between OpenSpacePlayerShip and BoostMeter — the anti-inert
## gate for step 2 of the boost epic
## (`docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md`).
##
## Every case in tests/unit/test_boost_meter.gd is green on a build where `BoostMeter` exists
## as a script but was never added to `player_ship.tscn` — the boost would still be free and
## the meter would be a component nothing owns. THIS is the file that fails on that build.
## The meter node is therefore always found BY CLASS, never by node path, so a rename cannot
## silently pass.
##
## Ship instances go in the tree (`add_child_autofree`) before anything touches them:
## `_handle_thrust()` dereferences `_thruster`, which `_setup_effects()` builds from `_ready()`
## (`player_ship.gd:64-83`), so on an un-parented instance the call is a hard error. Parenting
## also runs `PlayerBase._setup_components()` → `SessionState.apply_to()` and the
## `ShipModuleState` hookups, which is the second reason for the autoload discipline below.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const INFILTRATION_PLAYER_SCENE: PackedScene = preload("res://infiltration/scenes/entities/player/player.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

## One physics frame at the project's 60 Hz.
const D: float = 1.0 / 60.0

## The `boost` action is an open-space verb. Anything under these two roots is exempt from the
## "nobody else reads it" sweep: `open_space/` owns it, `tests/` asserts about it.
const _BOOST_ACTION_EXEMPT: Array[String] = ["res://open_space", "res://tests"]

var _sandbox := SaveSandbox.new()
var _saved_boost: int = 0
var _saved_shields: int = 0


## Two-layer discipline, the shape of test_weapon_unlock_sources.gd:38-53, and NOT optional
## even though nothing here binds to the autoload yet. `SaveSandbox` covers the `user://` file
## only; it does nothing to the in-memory singleton, and `ShipProgressionState` never re-reads
## the file after boot. From the persistence task onward `player_ship.tscn` carries a
## `BoostMeter` whose `_ready()` reads the LIVE `ShipProgressionState`, so a sibling test that
## raised the count would change what this file instantiates. GUT walks `res://tests` with
## `-ginclude_subdirs`, so that failure only reproduces in a full-suite run — the most
## expensive failure mode this suite has. Inert today, correct the day the binding lands.
func before_all() -> void:
	_sandbox.capture()
	_saved_boost = _live_boost_count()
	_saved_shields = ShipProgressionState._permanent_shield_count


func after_all() -> void:
	_set_live_boost_count(_saved_boost)
	ShipProgressionState._permanent_shield_count = _saved_shields
	_sandbox.restore()


func before_each() -> void:
	## Assigned to the backing fields directly, not via the setters, so the fixture does not
	## depend on the code under test and writes nothing to disk.
	_set_live_boost_count(_default_boost_count())
	ShipProgressionState._permanent_shield_count = 1


## `_boost_charge_count` and `MIN_BOOST_CHARGES` arrive with the persistence task; until then
## the autoload has neither, and a direct member access on a statically-typed autoload would
## not even compile. Reached through `in` / `get()` / `set()` so the block above is written
## once and starts working the moment that task lands.
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


## In the tree (see the header), with its own _physics_process off: otherwise real physics
## frames run _handle_rotation + _handle_thrust + move_and_slide against whatever the headless
## mouse position is, racing every hand-driven step below.
func _spawn_ship() -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	ship.rotation = 0.0
	ship.velocity = Vector2.ZERO
	return ship


## BY CLASS, never by node path.
func _meters_of(ship: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in ship.get_children():
		if child is BoostMeter:
			found.append(child)
	return found


func _meter_of(ship: Node) -> BoostMeter:
	var found := _meters_of(ship)
	return found[0] as BoostMeter if not found.is_empty() else null


## ── The meter is actually in the scene ───────────────────────────────────────────────────
## The one case the whole file exists for: a BoostMeter that is never added to
## player_ship.tscn passes every unit test and does nothing in the game.
func test_the_ship_scene_carries_exactly_one_boost_meter() -> void:
	var ship := _spawn_ship()
	var meters := _meters_of(ship)
	assert_eq(meters.size(), 1,
			"player_ship.tscn must carry exactly one BoostMeter child (found by class)")


## ── Boosting drains from THAT meter ──────────────────────────────────────────────────────
func test_a_held_boost_drains_continuously_from_the_scene_meter() -> void:
	var ship := _spawn_ship()
	var meter := _meter_of(ship)
	assert_not_null(meter, "no BoostMeter in player_ship.tscn")
	if meter == null:
		return
	var before: float = meter.charges
	ship._step_boost(true, true, D)
	assert_almost_eq(meter.charges, before - meter.drain_rate * D, 0.001,
			"a Shift boost drains the ship's own meter continuously — one frame's worth per frame")


## ── Boundary: a meter below min_start_charge refuses, and costs nothing ──────────────────
## `recharge_rate = 0.0` for this case only, so `charges` can be asserted at exactly 0.0:
## the meter's step() would otherwise trickle a frame's worth of refill back in and mask the
## difference between "refused" and "spent then refilled". The refill itself has its own case.
func test_an_empty_meter_refuses_the_boost_and_spends_nothing() -> void:
	var ship := _spawn_ship()
	var meter := _meter_of(ship)
	assert_not_null(meter, "no BoostMeter in player_ship.tscn")
	if meter == null:
		return
	meter.recharge_rate = 0.0
	meter.charges = 0.0
	ship.velocity = Vector2.ZERO
	ship._step_boost(true, true, D)
	assert_eq(ship.velocity, Vector2.ZERO,
			"an empty meter must refuse outright — nothing happens to velocity")
	assert_eq(meter.charges, 0.0, "a refused boost must not go negative or spend anything")


## ── Boundary: a boost refused by a module burns no charge ────────────────────────────────
## This passes on `_step_boost()`'s own `if engine_boost_active: return` and on nothing else —
## the case drives `_step_boost()` directly and so bypasses `_handle_thrust()`'s early return.
## If it fails, add the guard back; do not weaken the case.
func test_a_boost_refused_by_an_active_module_burns_no_charge() -> void:
	var ship := _spawn_ship()
	var meter := _meter_of(ship)
	assert_not_null(meter, "no BoostMeter in player_ship.tscn")
	if meter == null:
		return
	ship.engine_boost_active = true
	var before: float = meter.charges
	var velocity_before: Vector2 = ship.velocity
	ship._step_boost(true, true, D)
	assert_eq(meter.charges, before,
			"an EngineBoostModule boost outranks Shift — the refused press must cost nothing")
	assert_eq(ship.velocity, velocity_before, "the module owns velocity while it is active")


## ── Boundary: mashing Shift mid-hold does not over-drain ─────────────────────────────────
## Ordering is part of the contract: `not _boosting` and the `boost_hold_sec` retrigger floor
## are both checked BEFORE the sustain drain, so a mashed press mid-hold cannot trigger a
## second start-and-drain in the same frame — the meter loses exactly one frame's worth of
## drain per physics frame, mash or not.
func test_mashing_shift_while_already_boosting_does_not_overdrain() -> void:
	var ship := _spawn_ship()
	var meter := _meter_of(ship)
	assert_not_null(meter, "no BoostMeter in player_ship.tscn")
	if meter == null:
		return
	var before: float = meter.charges
	ship._step_boost(true, true, D)  ## trigger frame — one frame of drain
	ship._step_boost(true, true, D)  ## mashed press mid-hold — must not double-drain
	assert_almost_eq(meter.charges, before - meter.drain_rate * D * 2.0, 0.001,
			"two physics frames of a held boost drain exactly two frames' worth, mash or not")


## ── The ship drives the meter, and the meter never ticks itself ──────────────────────────
## BoostMeter deliberately has no _physics_process of its own: `set_physics_process(false)` on
## the ship (which MissionTrigger._open_menu() calls) does not stop a child's own physics tick,
## so a self-ticking meter would charge while a mission menu is open. The ship's physics is off
## here, so the only thing moving the meter is the hand-driven _handle_thrust() below.
func test_the_ship_recharges_the_meter_through_handle_thrust() -> void:
	var ship := _spawn_ship()
	var meter := _meter_of(ship)
	assert_not_null(meter, "no BoostMeter in player_ship.tscn")
	if meter == null:
		return
	## Spent directly, bypassing the trigger: headless Input can never report `boost` pressed
	## or held, so a call through _handle_thrust() below can never start a NEW boost — only
	## _step_boost()'s unconditional meter.step(delta) call is what this case means to exercise.
	meter.drain(1.0)
	var spent: float = meter.charges
	assert_almost_eq(spent, float(meter.max_charges) - 1.0, 0.001, "precondition: one unit spent")

	## Half the delay window: still paused, so nothing has come back yet.
	var delay_frames: int = int(meter.recharge_delay_sec / D) / 2
	for _i in range(delay_frames):
		ship._handle_thrust(D)
	assert_almost_eq(meter.charges, spent, 0.001,
			"no refill during the post-spend pause")

	## The rest of the pause plus a full charge's worth of refill, with a frame of slack.
	var refill_frames: int = int((meter.recharge_delay_sec + 1.0 / meter.recharge_rate) / D) + 2
	for _i in range(refill_frames):
		ship._handle_thrust(D)
	assert_almost_eq(meter.charges, float(meter.max_charges), 0.001,
			"the ship's _handle_thrust() must drive meter.step() back to full")


## ── Invariant: the boost is open-space only ──────────────────────────────────────────────
## The idea's last line is "boost should be exclusive to open-space gameplay", and
## `class_name BoostMeter` registers globally whatever directory the file sits in — the
## directory is a convention, this is the enforcement. Both scenes are named explicitly:
## a sweep of "the player scenes" quietly covers one of them.
func test_the_assault_fighter_has_no_boost_meter() -> void:
	_assert_scene_is_boost_free(FIGHTER_SCENE, "assault/scenes/player/player_fighter.tscn")


func test_the_infiltration_player_has_no_boost_meter() -> void:
	_assert_scene_is_boost_free(
			INFILTRATION_PLAYER_SCENE, "infiltration/scenes/entities/player/player.tscn")


## Walks the instantiated scene by class. `BoostBar` (the readout task) has no class yet, so it
## is matched on its script path instead — this case must cover it the day it lands, not the day
## someone remembers to come back here.
func _assert_scene_is_boost_free(scene: PackedScene, label: String) -> void:
	var root: Node = scene.instantiate()
	autofree(root)
	for node: Node in _walk(root):
		assert_false(node is BoostMeter,
				"%s must not carry a BoostMeter — the boost is open-space only" % label)
		var script: Script = node.get_script() as Script
		if script != null:
			assert_false(script.resource_path.ends_with("boost_bar.gd"),
					"%s must not carry a BoostBar — the boost is open-space only" % label)


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_walk(child))
	return out


## ── Invariant: nothing outside open_space/ reads the `boost` action ──────────────────────
## The other half of "open-space only": a scene without a meter can still be flown by another
## script that polls the same key.
func test_no_script_outside_open_space_reads_the_boost_action() -> void:
	var re := RegEx.new()
	re.compile("is_action_[a-z_]*\\(\\s*&?\"boost\"")
	var offenders: Array[String] = []
	for path: String in _gd_files("res://"):
		var exempt: bool = false
		for prefix: String in _BOOST_ACTION_EXEMPT:
			if path.begins_with(prefix):
				exempt = true
				break
		if exempt:
			continue
		var text: String = FileAccess.get_file_as_string(path)
		if re.search(text) != null:
			offenders.append(path)
	assert_eq(offenders, [] as Array[String],
			"the `boost` action belongs to open_space/ only; these read it: %s" % [offenders])


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with(".") and name != "addons":
				out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out
