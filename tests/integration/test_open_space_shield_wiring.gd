## The anti-inert gate for the open-space ship's permanent shield binding.
##
## `player_ship.tscn`'s ShieldComponent shipped with no `bind_progression = true`, so it fell
## back to `shield_component.gd`'s default of `false` and started with its own
## `permanent_charges` (1) instead of `ShipProgressionState.permanent_shield_count`. The hub's
## `ShipShieldUpPickup` raises the saved count, but the ship the player actually flies in open
## space never read it — the upgrade was visible in the menu and inert in flight.
##
## Every case in `tests/unit/test_shield_component.gd` (including
## `test_bind_progression_tracks_the_progression_autoload`) is green on a build where the
## `ShieldComponent` node in `player_ship.tscn` never sets `bind_progression` — that flag lives
## on the scene node, not the script default. THIS is the file that fails on that build. The
## component is found BY CLASS, never by node path, so a rename cannot silently pass.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

var _sandbox := SaveSandbox.new()
var _saved_permanent_count: int


func before_all() -> void:
	_sandbox.capture()
	_saved_permanent_count = ShipProgressionState._permanent_shield_count


func after_all() -> void:
	ShipProgressionState._permanent_shield_count = _saved_permanent_count
	_sandbox.restore()


## In the tree before anything touches it: parenting runs PlayerBase._setup_components() and
## the ShipModuleState hookups (same discipline as _spawn_ship() in
## test_open_space_boost_wiring.gd).
func _spawn_ship() -> Node:
	var ship := SHIP_SCENE.instantiate()
	add_child_autofree(ship)
	return ship


## BY CLASS, never by node path.
func _shield_of(ship: Node) -> Shield:
	for child: Node in ship.get_children():
		if child is Shield:
			return child
	return null


func test_the_ship_scene_carries_exactly_one_shield_component() -> void:
	var ship := _spawn_ship()
	var found: Array[Node] = []
	for child: Node in ship.get_children():
		if child is Shield:
			found.append(child)
	assert_eq(found.size(), 1,
			"player_ship.tscn must carry exactly one ShieldComponent child (found by class)")


func test_the_ships_shield_binds_to_the_progression_autoload() -> void:
	## Assigned to the backing field directly, not the setter, so the fixture does not depend
	## on the code under test and writes nothing to disk.
	ShipProgressionState._permanent_shield_count = 3
	var ship := _spawn_ship()
	var shield := _shield_of(ship)
	assert_not_null(shield, "no ShieldComponent in player_ship.tscn")
	if shield == null:
		return
	assert_true(shield.bind_progression,
			"the ship's ShieldComponent must bind to ShipProgressionState")
	assert_eq(shield.permanent_max, 3,
			"the ship's shield cap must come from the saved permanent shield count")
	assert_eq(shield.permanent_active, 3, "a freshly spawned ship starts with a full shield")


## Boundary: a shield_up pickup collected mid-mission (raising the live autoload count after
## the ship already exists) must reach the ship's own component, not just a future one.
func test_a_live_progression_change_reaches_the_already_spawned_ship() -> void:
	ShipProgressionState._permanent_shield_count = 1
	var ship := _spawn_ship()
	var shield := _shield_of(ship)
	assert_not_null(shield, "no ShieldComponent in player_ship.tscn")
	if shield == null:
		return
	assert_eq(shield.permanent_max, 1)

	ShipProgressionState.set_permanent_shield_count(2)
	assert_eq(shield.permanent_max, 2,
			"the live ship's shield must track a shield_up pickup collected mid-mission")
	assert_eq(shield.permanent_active, 2, "the newly unlocked slot is filled immediately")
