## INVARIANT test (not characterization): every weapon mode the player can see must have
## something in the world that unlocks it, and unlocking one must be visible where it happens.
##
## `UpgradeState._ready()` seeds `STARTING_IDS` (`&"default"`) and nothing else. Every other id in
## `ALL_IDS` — `sniper_shot`, `spread`, `gatling`, `mining_laser` — has a tuned `.tres`, a
## `WeaponBehavior` and a menu row, and before this gate existed none of them could ever be fired:
## `grep 'UpgradeState.unlock('` outside `tests/` found exactly one call site, `unlock_all()` inside
## the autoload itself, which nothing invokes. That is the same failure
## `test_module_unlock_sources.gd` pins for ship modules, so it is pinned the same way here.
##
## Lives in integration/ because it loads real scenes (`tests/README.md`: unit/ is "no scene
## loading"). `sector_hub.tscn` is instantiated but never added to the tree — `_ready()` is what
## spawns drones and initialises the HUD, and walking the node list needs none of it.
##
## ⚠️ Autoload state. `WeaponModeUnlockerPickup._collect()` calls the **`UpgradeState` autoload**,
## not any instance a test holds, and the whole suite shares it — so a fresh script instance would
## prove nothing about `_collect()`, and mutating the live one would leak `gatling` into every later
## test in the process. `before_all`/`after_all` therefore snapshot and restore the live
## `_unlocked` dictionary on top of `SaveSandbox` (which only covers the file). This is the pattern
## `test_module_list_lock.gd:31-42` established and `tests/README.md` documents; `_unlocked` is a
## flat `StringName -> bool` dict, so a shallow `duplicate()` is a complete snapshot.
##
## ⚠️ Orphan counts in the PlayerMenu test are expected and are not a leak you introduced:
## `WeaponFrame.populate()` (`weapon_frame.gd:20-24`) `queue_free()`s the previous rows and the
## delete queue does not flush before the test ends — the same effect `tests/README.md` already
## documents for `ModuleList`.
extends GutTest

const HUB_SCENE: PackedScene = preload("res://open_space/scenes/levels/sector_hub.tscn")
const PICKUP_SCENE: PackedScene = preload("res://global/pickups/scenes/weapon_mode_unlocker_pickup.tscn")
const MENU_SCENE: PackedScene = preload("res://global/ui/player_menu/player_menu.tscn")
const UpgradeStateScript := preload("res://global/autoloads/upgrade_state.gd")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const MODES_DIR := "res://assault/scenes/player/weapons/modes"

var _sandbox := SaveSandbox.new()
var _saved_unlocked: Dictionary = {}


func before_all() -> void:
	_sandbox.capture()
	_saved_unlocked = UpgradeState._unlocked.duplicate()


func after_all() -> void:
	UpgradeState._unlocked = _saved_unlocked
	_sandbox.restore()


func before_each() -> void:
	## Assigned directly rather than through unlock(), so the fixture does not depend on the
	## very code under test and writes nothing to disk.
	UpgradeState._unlocked = {&"default": true}


## Every `weapon_id()` granted by a WeaponModeUnlockerPickup anywhere under `root`.
func _granted_by(root: Node) -> Array[StringName]:
	var found: Array[StringName] = []
	for node: Node in _walk(root):
		if node is WeaponModeUnlockerPickup:
			found.append((node as WeaponModeUnlockerPickup).weapon_id())
	return found


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_walk(child))
	return out


func test_every_non_starting_weapon_id_has_an_unlocker_in_the_sector_hub() -> void:
	## The reason this file exists. A mode in ALL_IDS with no unlocker is a row the player can
	## see in the ship menu and can never select.
	var hub := HUB_SCENE.instantiate()
	var granted := _granted_by(hub)
	for id: StringName in UpgradeStateScript.ALL_IDS:
		if id in UpgradeStateScript.STARTING_IDS:
			continue        ## seeded on a fresh profile; needs no source
		assert_true(id in granted,
			"weapon mode '%s' has an unlocker in the sector hub" % id)
	hub.free()


func test_no_unlocker_grants_a_starting_weapon() -> void:
	## A pickup for an id the player already owns is a crate they can walk into for nothing:
	## unlock() early-returns and no dialog value is delivered.
	var hub := HUB_SCENE.instantiate()
	var granted := _granted_by(hub)
	for id: StringName in UpgradeStateScript.STARTING_IDS:
		assert_false(id in granted,
			"'%s' is a starting weapon, so an unlocker for it is a no-op pickup" % id)
	hub.free()


func test_every_unlocker_grants_a_known_id() -> void:
	## Boundary: `weapon_id()` returns &"" for an enum value with no match arm — a `Weapon`
	## entry added without its arm. That would only push_warning at collect time; catch it here.
	## Mirrors the slot-mismatch case in test_module_unlock_sources.gd.
	var hub := HUB_SCENE.instantiate()
	for id: StringName in _granted_by(hub):
		assert_true(id in UpgradeStateScript.ALL_IDS,
			"an unlocker grants '%s', which is not an id in UpgradeState.ALL_IDS" % id)
	hub.free()


func test_no_weapon_has_two_unlockers_in_the_hub() -> void:
	## Not a correctness requirement on its own, but a duplicate in the bench means a
	## copy-paste slip left some *other* mode without one.
	var hub := HUB_SCENE.instantiate()
	var seen: Array[StringName] = []
	for id: StringName in _granted_by(hub):
		assert_false(id in seen, "'%s' is granted by exactly one unlocker in the hub" % id)
		seen.append(id)
	hub.free()


func test_collecting_an_unlocker_actually_unlocks_the_mode() -> void:
	## BOUNDARY. Every test above passes against a pickup whose `_collect()` is empty — they only
	## check placement. This is the one that proves the pickup does the thing, against the live
	## autoload the pickup actually calls.
	##
	## It calls `_collect()` directly rather than driving `body_entered`, so it proves the
	## *effect*, not the trigger; the trigger is `PickupBase`'s, already covered by every other
	## pickup in the game.
	var pickup := PICKUP_SCENE.instantiate() as WeaponModeUnlockerPickup
	assert_not_null(pickup, "weapon_mode_unlocker_pickup.tscn root must be a WeaponModeUnlockerPickup")
	if pickup == null:
		return
	pickup.weapon = WeaponModeUnlockerPickup.Weapon.GATLING

	assert_false(UpgradeState.is_unlocked(&"gatling"), "fixture starts with gatling locked")
	pickup._collect(null)
	assert_true(UpgradeState.is_unlocked(&"gatling"),
		"collecting a GATLING unlocker unlocks the gatling weapon mode")
	pickup.free()


func test_unlocking_repopulates_an_already_built_player_menu() -> void:
	## BOUNDARY, and the regression guard for the half of this feature the player actually sees.
	## `PlayerMenu._populate_lists()` runs once, from `connect_states()`, during HUD `_ready()`
	## (`mission_hud.gd:19/24/43`); `_toggle()` never repopulates. So without the
	## `UpgradeState.unlocked_changed` connection the player collects a crate in the hub, opens
	## the menu two seconds later, and the main-weapon column is still one row — and worse,
	## `_confirm_selection()` (live `unlocked_ids()`) and `_current_max_row()` (stale frame count)
	## disagree, which cannot happen before this feature exists.
	var menu := MENU_SCENE.instantiate() as PlayerMenu
	assert_not_null(menu, "player_menu.tscn root must be a PlayerMenu")
	if menu == null:
		return
	add_child_autofree(menu)
	menu.connect_states(null, null)   ## exactly what mission_hud.gd:19 does with no player

	var frame: WeaponFrame = menu.get_node("ShipLayout/MainWeaponFrame") as WeaponFrame
	assert_not_null(frame, "PlayerMenu has a MainWeaponFrame")
	if frame == null:
		return
	var before: int = frame.get_count()
	assert_eq(before, 1, "fixture has only the starting weapon unlocked")

	UpgradeState.unlock(&"gatling")
	assert_eq(frame.get_count(), before + 1,
		"unlocking a mode while the menu exists adds its row to the main-weapon column")

	## Boundary within the boundary: unlock() early-returns without emitting for an id that is
	## already unlocked (upgrade_state.gd:42-43), so the handler cannot be duplicating rows.
	UpgradeState.unlock(&"gatling")
	assert_eq(frame.get_count(), before + 1,
		"re-unlocking an already-unlocked mode does not add a second row")


func test_every_weapon_mode_resource_has_an_icon() -> void:
	## BOUNDARY over the *other* half of "the player can see it". `WeaponModeResource.icon`
	## (`weapon_mode.gd:11`) is what the in-game HUD chip draws (`weapon_chip.gd:26`) and, since
	## `_WEAPON_ICONS` was deleted, what the ship menu draws too. A mode that ships without one
	## is a blank row and a blank chip, and nothing else in the project would report it.
	for id: StringName in UpgradeStateScript.ALL_IDS:
		var path := "%s/%s.tres" % [MODES_DIR, id]
		var mode := load(path) as WeaponModeResource
		assert_not_null(mode, "%s loads as a WeaponModeResource" % path)
		if mode == null:
			continue
		assert_not_null(mode.icon, "weapon mode '%s' has an icon set in %s" % [id, path])
