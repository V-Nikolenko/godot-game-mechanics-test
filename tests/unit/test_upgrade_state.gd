## Characterization tests for UpgradeState (global/autoloads/upgrade_state.gd).
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


func test_unknown_ids_are_stored_but_never_listed() -> void:
	var us := _fresh()
	## CHARACTERIZED: `unlock()` does not validate against ALL_IDS, so a typo'd id
	## is happily stored and reported by is_unlocked() — but unlocked_ids() iterates
	## ALL_IDS, so it never shows up in any menu. Silent, invisible failure.
	us.unlock(&"not_a_real_upgrade")
	assert_true(us.is_unlocked(&"not_a_real_upgrade"), "an invalid id is still recorded")
	assert_eq(us.unlocked_ids(), [] as Array[StringName], "but it is never listed")
	us.free()


func test_unlock_all_unlocks_every_known_id() -> void:
	var us := _fresh()
	us.unlock_all()
	assert_eq(us.unlocked_ids(), UpgradeStateScript.ALL_IDS)
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
