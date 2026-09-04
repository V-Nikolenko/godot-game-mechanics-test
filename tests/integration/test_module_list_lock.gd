## INTENT tests (not characterization) for the locked-row presentation in the ship menu's
## module list. The rows and the gate are new; these assert what should happen, not what
## used to.
##
## The rule under test: a module the player has not unlocked is shown — greyed, with a
## "LOCKED" description — rather than hidden, and confirming it is a defined no-op. The
## "None" row is the exception and is never locked, because `ModuleList` is the only way to
## take a module back out (`player_menu.gd:180-184` is the game's only `equip()` caller).
##
## Lives in integration/ because it instances a real scene (`tests/README.md`: unit/ is
## "no scene loading"). `ModuleList` reads the live `ShipModuleState` singleton, which the
## whole suite shares, so before_all snapshots `_unlocked`/`_equipped` and after_all puts
## them back — on top of SaveSandbox, which covers the file the autoload writes.
extends GutTest

const LIST_SCENE: PackedScene = preload("res://global/ui/player_menu/module_list.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

## weapons is the longest slot: [&"", overclock, plasma_nova, overheat_nullifier, pierce, shooting]
const _WEAPON_ROWS: int = 6
const _ROW_OVERCLOCK: int = 1
const _ROW_PIERCE: int = 4

var _sandbox := SaveSandbox.new()
var _saved_unlocked: Dictionary = {}
var _saved_equipped: Dictionary = {}
var _list: ModuleList
var _confirmed: Array[StringName] = []


func before_all() -> void:
	_sandbox.capture()
	for slot: StringName in ShipModuleState.SLOTS:
		_saved_unlocked[slot] = (ShipModuleState._unlocked[slot] as Array).duplicate()
		_saved_equipped[slot] = ShipModuleState.get_equipped(slot)


func after_all() -> void:
	for slot: StringName in ShipModuleState.SLOTS:
		ShipModuleState._unlocked[slot] = _saved_unlocked[slot]
		ShipModuleState._equipped[slot] = _saved_equipped[slot]
	_sandbox.restore()


func before_each() -> void:
	## Mutated directly rather than through unlock()/equip() so the setup does not depend on
	## the very gate under test, and so it writes nothing to disk.
	for slot: StringName in ShipModuleState.SLOTS:
		(ShipModuleState._unlocked[slot] as Array).clear()
		ShipModuleState._equipped[slot] = &""
	_confirmed.clear()
	_list = LIST_SCENE.instantiate() as ModuleList
	add_child_autofree(_list)
	_list.confirmed.connect(func(id: StringName) -> void: _confirmed.append(id))


func _unlock(slot: StringName, id: StringName) -> void:
	(ShipModuleState._unlocked[slot] as Array).append(id)


func _locked_flags() -> Array[bool]:
	var out: Array[bool] = []
	for item: ModuleListItem in _list._items:
		out.append(item.is_locked())
	return out


func test_locked_rows_are_marked_and_unlocked_ones_are_not() -> void:
	_unlock(&"weapons", &"pierce")
	_list.open(&"weapons", &"")
	assert_eq(_list._items.size(), _WEAPON_ROWS, "locked modules are shown, not filtered out")
	assert_eq(_locked_flags(), [false, true, true, true, false, true] as Array[bool],
		"only the None row and the unlocked 'pierce' row are selectable")


func test_a_locked_row_says_how_to_unlock_it() -> void:
	_list.open(&"weapons", &"")
	_list.navigate(_ROW_OVERCLOCK)
	assert_string_contains(_list._descs[_ROW_OVERCLOCK], "LOCKED",
		"a greyed row carries its own call to action rather than being a dead end")


func test_the_none_row_is_never_locked() -> void:
	## Boundary. `is_unlocked(slot, &"")` is always false — nothing ever appends &"" to the
	## unlocked store — so a naive per-row lock check would grey out the unequip row and
	## trap the player's module in its slot.
	_list.open(&"weapons", &"")
	assert_false(_list._items[0].is_locked(), "row 0 (None) is selectable with nothing unlocked")
	_list.confirm()
	assert_eq(_confirmed, [&""] as Array[StringName], "confirming None emits the unequip id")


func test_confirming_a_locked_row_emits_nothing() -> void:
	_list.open(&"weapons", &"")
	_list.navigate(_ROW_OVERCLOCK)
	_list.confirm()
	assert_eq(_confirmed, [] as Array[StringName], "a locked row is a no-op, not an equip")


func test_confirming_an_unlocked_row_still_emits() -> void:
	## The control for the test above: it must not be passing because confirm() is broken.
	_unlock(&"weapons", &"pierce")
	_list.open(&"weapons", &"")
	_list.navigate(_ROW_PIERCE)
	_list.confirm()
	assert_eq(_confirmed, [&"pierce"] as Array[StringName])


func test_reopening_rebuilds_the_lock_flags() -> void:
	## `_locked` is cleared in _clear() alongside _ids/_descs; if it were not, the flags
	## would accumulate across opens and go out of step with the rows.
	_list.open(&"weapons", &"")
	assert_eq(_locked_flags(), [false, true, true, true, true, true] as Array[bool])
	## NOTE: GUT reports 24 orphans for this test. They are the first open's rows, which
	## _clear() removes and queue_free()s; the delete queue does not flush before the test
	## ends. Pre-existing ModuleList behaviour, harmless in play (menu opens are frames
	## apart), and awaiting process_frame here does not change the count.
	_unlock(&"weapons", &"shooting")
	_list.open(&"weapons", &"")
	assert_eq(_locked_flags(), [false, true, true, true, true, false] as Array[bool],
		"unlocking a module and reopening frees exactly its row")
