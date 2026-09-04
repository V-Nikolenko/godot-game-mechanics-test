## INVARIANT test (not characterization): every ship module in the catalogue must have
## something in the world that unlocks it.
##
## Since `ShipModuleState.equip()` consults `_unlocked`, a module with no unlocker is a row
## the player can see and can never turn on. That is exactly the failure the plan review
## caught, so it is pinned here rather than left to a future reader to notice: adding a 16th
## module to `SLOT_MODULES` without an unlocker fails this test.
##
## Lives in integration/ because it loads a real scene (`tests/README.md`: unit/ is
## "no scene loading"). The hub is instantiated but never added to the tree — `_ready()` is
## what spawns drones and initialises the HUD, and walking the node list needs none of it.
extends GutTest

const HUB_SCENE: PackedScene = preload("res://open_space/scenes/levels/sector_hub.tscn")
const ModuleStateScript := preload("res://global/autoloads/ship_module_state.gd")


## slot -> Array[StringName] of module ids granted by unlockers somewhere in `root`.
func _granted_by(root: Node) -> Dictionary:
	var found: Dictionary = {}
	for node: Node in _walk(root):
		if node is ShipModuleUnlockerPickup:
			var pickup := node as ShipModuleUnlockerPickup
			var slot: StringName = pickup._slot_name()
			var ids: Array = found.get(slot, [] as Array[StringName])
			ids.append(pickup._module_name())
			found[slot] = ids
	return found


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_walk(child))
	return out


func test_every_catalogue_module_has_an_unlocker_in_the_sector_hub() -> void:
	var hub := HUB_SCENE.instantiate()
	var granted := _granted_by(hub)
	for slot: StringName in ModuleStateScript.SLOTS:
		var granted_here: Array = granted.get(slot, [])
		for id: StringName in ModuleStateScript.SLOT_MODULES[slot]:
			if id == &"":
				continue        ## &"" is unequip, not a module; it needs no source
			assert_true(id in granted_here,
				"module '%s' (slot '%s') has an unlocker in the sector hub" % [id, slot])
	hub.free()


func test_every_unlocker_grants_a_module_that_exists_in_its_slot() -> void:
	## Boundary: `Module` is one flat enum across all four slots
	## (`ship_module_unlocker_pickup.gd:7-16`), so a mismatched pair like
	## cockpit + PIERCE is expressible in the inspector and would only push_warning at
	## collect time. Catch it here instead.
	var hub := HUB_SCENE.instantiate()
	var granted := _granted_by(hub)
	for slot: StringName in granted:
		var valid: Array = ModuleStateScript.SLOT_MODULES.get(slot, [])
		for id: StringName in granted[slot]:
			assert_true(id in valid,
				"unlocker grants '%s' for slot '%s', which is not a module of that slot" % [id, slot])
	hub.free()


func test_no_module_has_two_unlockers_in_the_hub() -> void:
	## Not a correctness requirement, but a duplicate in the bench means a copy-paste slip
	## left some *other* module without one — and the coverage test above would still pass
	## if the catalogue later shrank. Cheap to pin.
	var hub := HUB_SCENE.instantiate()
	var granted := _granted_by(hub)
	for slot: StringName in granted:
		var seen: Array[StringName] = []
		for id: StringName in granted[slot]:
			assert_false(id in seen, "'%s' (slot '%s') is granted by exactly one unlocker" % [id, slot])
			seen.append(id)
	hub.free()
