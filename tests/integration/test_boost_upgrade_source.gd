## INVARIANT test (not characterization): the sector hub must place a pickup that grants a
## permanent open-space boost charge, and that pickup must actually raise the count on the live
## `ShipProgressionState` autoload.
##
## Same family as `test_module_unlock_sources.gd` / `test_weapon_unlock_sources.gd`: a pickup
## whose `_collect()` never fires is a crate the player can walk into for nothing, and placement
## alone does not prove that.
##
## ⚠️ Autoload state. `ShipBoostUpPickup._collect()` calls the **`ShipProgressionState` autoload**,
## not any instance a test holds, and the whole GUT process shares it — `SaveSandbox` covers the
## `user://` file only. `before_all`/`after_all` snapshot and restore the live singleton's backing
## fields on top of `SaveSandbox`, and `before_each` assigns them directly rather than through
## `add_boost_charge()`, so the fixture does not depend on the code under test. See `3-plan.md` →
## Test plan → "Autoload discipline".
extends GutTest

const HUB_SCENE: PackedScene = preload("res://open_space/scenes/levels/sector_hub.tscn")
const PICKUP_SCENE: PackedScene = preload("res://global/pickups/scenes/ship_boost_up_pickup.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

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
	## Assigned to the backing fields directly, not via add_boost_charge(), so the fixture does
	## not depend on the code under test and writes nothing to disk.
	ShipProgressionState._boost_charge_count = ShipProgressionState.MIN_BOOST_CHARGES
	ShipProgressionState._permanent_shield_count = 1


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_walk(child))
	return out


func test_sector_hub_places_a_ship_boost_up_pickup() -> void:
	var hub := HUB_SCENE.instantiate()
	var found := false
	for node: Node in _walk(hub):
		if node is ShipBoostUpPickup:
			found = true
			break
	assert_true(found, "sector_hub.tscn places a ShipBoostUpPickup on the pickup bench")
	hub.free()


func test_collecting_the_pickup_adds_a_boost_charge() -> void:
	## BOUNDARY. Every test above (well, the one above) passes on a pickup whose `_collect()` is
	## empty — it only checks placement. This is the one that proves the pickup does the thing,
	## against the live autoload the pickup actually calls.
	var pickup := PICKUP_SCENE.instantiate() as ShipBoostUpPickup
	assert_not_null(pickup, "ship_boost_up_pickup.tscn root must be a ShipBoostUpPickup")
	if pickup == null:
		return

	var before: int = ShipProgressionState.boost_charge_count
	pickup._collect(null)
	assert_eq(ShipProgressionState.boost_charge_count, before + 1,
		"collecting a ShipBoostUpPickup raises the live boost charge count by 1")
	pickup.free()


func test_collecting_at_cap_does_not_exceed_the_maximum() -> void:
	## BOUNDARY. Reached by assigning the backing field directly, never by collecting five
	## pickups in a row — the fixture must not depend on the code under test.
	ShipProgressionState._boost_charge_count = ShipProgressionState.MAX_BOOST_CHARGES

	var pickup := PICKUP_SCENE.instantiate() as ShipBoostUpPickup
	assert_not_null(pickup, "ship_boost_up_pickup.tscn root must be a ShipBoostUpPickup")
	if pickup == null:
		return

	pickup._collect(null)
	assert_eq(ShipProgressionState.boost_charge_count, ShipProgressionState.MAX_BOOST_CHARGES,
		"collecting a boost pickup at the cap does not push the count past MAX_BOOST_CHARGES")
	pickup.free()
