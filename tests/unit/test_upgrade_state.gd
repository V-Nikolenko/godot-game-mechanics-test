## Characterization tests for UpgradeState (global/autoloads/upgrade_state.gd).
##
## Exception: the tests marked `INTENT` below assert intended behaviour, not today's.
## They cover the id validation in `unlock()` / `_load()` and the ALL_IDS vs
## ABILITY_IDS split, which replaced a characterized silent-failure bug.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const UpgradeStateScript := preload("res://global/autoloads/upgrade_state.gd")

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


## Tree-less instance: `_ready()` (which loads from disk and seeds &"default") never fires.
func _fresh() -> Node:
	return UpgradeStateScript.new()


func test_nothing_is_unlocked_before_ready_runs() -> void:
	var us := _fresh()
	assert_false(us.is_unlocked(&"default"))
	assert_eq(us.unlocked_ids(), [] as Array[StringName])
	us.free()


func test_ready_seeds_default_when_the_store_is_empty() -> void:
	_sandbox.clear_all()
	var us := _fresh()
	add_child_autofree(us)              ## entering the tree runs _ready()
	assert_true(us.is_unlocked(&"default"), "_ready seeds &\"default\" on a fresh profile")
	assert_eq(us.unlocked_ids(), [&"default"] as Array[StringName])


func test_unlock_sets_the_flag_and_emits_once() -> void:
	var us := _fresh()
	var seen: Array[StringName] = []
	us.unlocked_changed.connect(func(id: StringName) -> void: seen.append(id))
	us.unlock(&"spread")
	assert_true(us.is_unlocked(&"spread"))
	assert_eq(seen, [&"spread"] as Array[StringName])
	us.unlock(&"spread")
	assert_eq(seen.size(), 1, "re-unlocking an already unlocked id emits nothing")
	us.free()


func test_unlocked_ids_follows_all_ids_order_not_unlock_order() -> void:
	var us := _fresh()
	us.unlock(&"mining_laser")
	us.unlock(&"default")
	us.unlock(&"gatling")
	## ALL_IDS order is: default, sniper_shot, spread, gatling, mining_laser
	assert_eq(us.unlocked_ids(), [&"default", &"gatling", &"mining_laser"] as Array[StringName])
	us.free()


## INTENT (not characterization): `unlock()` validates its id against the known-id
## set, the same way `ShipModuleState.unlock()` validates against `SLOT_MODULES`.
## Before this guard a typo'd id was stored and reported `true` by `is_unlocked()`
## while `unlocked_ids()` — which iterates `ALL_IDS` — never listed it, so the
## upgrade silently did nothing.
func test_unknown_ids_are_rejected() -> void:
	var us := _fresh()
	var seen: Array[StringName] = []
	us.unlocked_changed.connect(func(id: StringName) -> void: seen.append(id))
	us.unlock(&"not_a_real_upgrade")
	assert_false(us.is_unlocked(&"not_a_real_upgrade"), "an invalid id is not recorded")
	assert_eq(seen, [] as Array[StringName], "and no unlock is announced for it")
	assert_eq(us.unlocked_ids(), [] as Array[StringName])
	us.free()


## INTENT: `&"reflect"` is gated by `reflect_state.gd` via `is_unlocked()` but is an
## ability, not a weapon mode — it has no `weapons/modes/reflect.tres`. It must be
## unlockable, yet must stay out of `unlocked_ids()`, which feeds the weapon cycle
## and the player menu's main-weapon column.
func test_ability_ids_unlock_but_never_enter_the_weapon_list() -> void:
	var us := _fresh()
	us.unlock(&"reflect")
	assert_true(us.is_unlocked(&"reflect"), "an ability id is a valid unlock target")
	assert_eq(us.unlocked_ids(), [] as Array[StringName], "but it is not a weapon")
	us.free()



## INTENT: an id that is invalid today (a renamed or removed upgrade left behind in
## an old profile) must not survive a load either, or the guard in `unlock()` is
## trivially bypassed by whatever is already on disk.
func test_load_drops_unknown_ids_left_in_the_save_file() -> void:
	_sandbox.clear_all()
	var cfg := ConfigFile.new()
	cfg.set_value(UpgradeStateScript.SECTION, "gatling", true)
	cfg.set_value(UpgradeStateScript.SECTION, "an_upgrade_that_was_removed", true)
	assert_eq(cfg.save(UpgradeStateScript.SAVE_PATH), OK, "sandbox save file written")

	var us := _fresh()
	us._load()
	assert_true(us.is_unlocked(&"gatling"), "known ids still load")
	assert_false(us.is_unlocked(&"an_upgrade_that_was_removed"), "unknown ids are dropped")
	us.free()


## Boundary: `unlock_all()` walks ALL_IDS, so it must not switch abilities on too.
func test_unlock_all_unlocks_every_known_id() -> void:
	var us := _fresh()
	us.unlock_all()
	assert_eq(us.unlocked_ids(), UpgradeStateScript.ALL_IDS)
	assert_false(us.is_unlocked(&"reflect"), "unlock_all covers ALL_IDS, not abilities")
	us.free()


func test_unlocks_survive_a_save_load_round_trip() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer.unlock(&"sniper_shot")
	writer.unlock(&"gatling")
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_true(reader.is_unlocked(&"sniper_shot"))
	assert_true(reader.is_unlocked(&"gatling"))
	assert_false(reader.is_unlocked(&"spread"))
	reader.free()
