## Characterization tests for ShipModuleState (equipped/unlocked ship modules).
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const ModuleStateScript := preload("res://global/autoloads/ship_module_state.gd")

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func _fresh() -> Node:
	return ModuleStateScript.new()


func test_every_slot_starts_empty() -> void:
	var m := _fresh()
	for slot: StringName in ModuleStateScript.SLOTS:
		assert_eq(m.get_equipped(slot), &"", "slot '%s' starts empty" % slot)
	m.free()


func test_slot_and_module_catalogue_is_stable() -> void:
	## Pins the public catalogue the ship menu renders from.
	assert_eq(ModuleStateScript.SLOTS, [&"cockpit", &"armor", &"weapons", &"engines"] as Array[StringName])
	for slot: StringName in ModuleStateScript.SLOTS:
		var ids: Array = ModuleStateScript.SLOT_MODULES[slot]
		assert_eq(ids[0], &"", "slot '%s' lists &\"\" (None) first" % slot)
	assert_eq((ModuleStateScript.SLOT_MODULES[&"engines"] as Array).size(), 3)


func test_equip_sets_the_slot_and_emits() -> void:
	var m := _fresh()
	var equipped: Array = []
	m.module_equipped.connect(func(s: StringName, id: StringName) -> void: equipped.append([s, id]))
	m.equip(&"weapons", &"pierce")
	assert_eq(m.get_equipped(&"weapons"), &"pierce")
	assert_eq(equipped, [[&"weapons", &"pierce"]])
	m.free()


func test_equipping_the_same_module_twice_emits_nothing() -> void:
	var m := _fresh()
	m.equip(&"armor", &"parry")
	var equipped: Array = []
	m.module_equipped.connect(func(s: StringName, id: StringName) -> void: equipped.append([s, id]))
	m.equip(&"armor", &"parry")
	assert_eq(equipped, [], "re-equipping the current module is a no-op")
	m.free()


func test_swapping_modules_emits_unequip_then_equip() -> void:
	var m := _fresh()
	m.equip(&"cockpit", &"emp_blast")
	var events: Array = []
	m.module_unequipped.connect(func(s: StringName, prev: StringName) -> void: events.append(["off", s, prev]))
	m.module_equipped.connect(func(s: StringName, id: StringName) -> void: events.append(["on", s, id]))
	m.equip(&"cockpit", &"ai_targeting")
	assert_eq(events, [["off", &"cockpit", &"emp_blast"], ["on", &"cockpit", &"ai_targeting"]])
	m.free()


func test_unequipping_emits_only_unequipped() -> void:
	var m := _fresh()
	m.equip(&"engines", &"warp")
	var events: Array = []
	m.module_unequipped.connect(func(s: StringName, prev: StringName) -> void: events.append(["off", s, prev]))
	m.module_equipped.connect(func(s: StringName, id: StringName) -> void: events.append(["on", s, id]))
	m.equip(&"engines", &"")
	assert_eq(m.get_equipped(&"engines"), &"")
	assert_eq(events, [["off", &"engines", &"warp"]], "clearing a slot emits no module_equipped")
	m.free()


func test_equip_rejects_an_unknown_slot() -> void:
	var m := _fresh()
	m.equip(&"nose_cone", &"pierce")     ## push_warning, no state change
	assert_eq(m.get_equipped(&"nose_cone"), &"")
	m.free()


func test_equip_rejects_a_module_from_the_wrong_slot() -> void:
	var m := _fresh()
	## &"pierce" is a weapons module; asking for it in the armor slot must not stick.
	m.equip(&"armor", &"pierce")
	assert_eq(m.get_equipped(&"armor"), &"", "cross-slot modules are refused")
	m.free()


func test_unlock_is_independent_of_equip() -> void:
	var m := _fresh()
	var unlocked: Array = []
	m.module_unlocked.connect(func(s: StringName, id: StringName) -> void: unlocked.append([s, id]))
	m.unlock(&"weapons", &"plasma_nova")
	assert_true(m.is_unlocked(&"weapons", &"plasma_nova"))
	assert_eq(m.get_equipped(&"weapons"), &"", "unlocking does not equip")
	assert_eq(unlocked, [[&"weapons", &"plasma_nova"]])
	m.unlock(&"weapons", &"plasma_nova")
	assert_eq(unlocked.size(), 1, "a duplicate unlock emits nothing")
	m.free()


func test_unlock_rejects_invalid_slot_and_module() -> void:
	var m := _fresh()
	m.unlock(&"nose_cone", &"pierce")
	m.unlock(&"engines", &"pierce")      ## valid slot, wrong slot's module
	assert_false(m.is_unlocked(&"engines", &"pierce"))
	m.free()


func test_equipping_does_not_require_unlocking() -> void:
	## CHARACTERIZED: `equip()` never consults `_unlocked`. Anything in the
	## catalogue can be equipped whether or not the player has earned it.
	var m := _fresh()
	m.equip(&"weapons", &"overclock")
	assert_eq(m.get_equipped(&"weapons"), &"overclock")
	assert_false(m.is_unlocked(&"weapons", &"overclock"))
	m.free()


func test_equipped_and_unlocked_survive_a_save_load_round_trip() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer.equip(&"weapons", &"shooting")
	writer.unlock(&"armor", &"final_resort")
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_eq(reader.get_equipped(&"weapons"), &"shooting")
	assert_true(reader.is_unlocked(&"armor", &"final_resort"))
	assert_eq(reader.get_equipped(&"cockpit"), &"", "untouched slots stay empty")
	reader.free()


func test_load_drops_a_module_id_that_is_no_longer_valid() -> void:
	_sandbox.clear_all()
	var cfg := ConfigFile.new()
	cfg.set_value(ModuleStateScript.SECTION, "weapons", "removed_in_a_later_patch")
	cfg.set_value(ModuleStateScript.SECTION, "weapons_unlocked", ["pierce", "also_removed"])
	cfg.save(ModuleStateScript.SAVE_PATH)

	var reader := _fresh()
	reader._load()                       ## also emits a push_warning, by design
	assert_eq(reader.get_equipped(&"weapons"), &"", "an unknown equipped id falls back to empty")
	assert_true(reader.is_unlocked(&"weapons", &"pierce"), "valid unlocks are kept")
	assert_false(reader.is_unlocked(&"weapons", &"also_removed"), "unknown unlocks are dropped")
	reader.free()
