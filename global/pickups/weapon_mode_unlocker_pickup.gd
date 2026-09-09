# global/pickups/weapon_mode_unlocker_pickup.gd
class_name WeaponModeUnlockerPickup
extends PickupBase

## Grants one main-weapon mode permanently (`UpgradeState.unlock`). The sibling of
## `ShipModuleUnlockerPickup`, for the other unlock store — see that file for the pattern.
##
## Every id in `UpgradeState.ALL_IDS` except `UpgradeState.STARTING_IDS` needs one of these
## somewhere in the world or the mode is unreachable content;
## `tests/integration/test_weapon_unlock_sources.gd` is the gate that says so.

const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

## Inspector-selectable enum — no raw string typing required, so a scene file cannot carry a
## typo'd id that would only push_warning at collect time.
## `&"default"` is deliberately absent: it is seeded on a fresh profile, so a pickup for it
## would be a crate the player walks into for nothing.
enum Weapon { SNIPER_SHOT, SPREAD, GATLING, MINING_LASER }

@export var weapon: Weapon = Weapon.SNIPER_SHOT


func _collect(_player: PlayerBase) -> void:
	UpgradeState.unlock(weapon_id())


func _get_dialog_text() -> String:
	## Named from the mode's own `.tres`, so renaming a weapon cannot desync the pickup text.
	var mode := _load_mode(weapon_id())
	if mode == null or mode.display_name.is_empty():
		return "Weapon acquired!"
	return "%s acquired!" % mode.display_name


## Public: the `UpgradeState` id this pickup grants. Read by the unlock-source gate.
## Returns &"" for a `Weapon` value with no match arm below.
func weapon_id() -> StringName:
	match weapon:
		Weapon.SNIPER_SHOT:  return &"sniper_shot"
		Weapon.SPREAD:       return &"spread"
		Weapon.GATLING:      return &"gatling"
		Weapon.MINING_LASER: return &"mining_laser"
	return &""


func _load_mode(id: StringName) -> WeaponModeResource:
	var path := _MODES_DIR + String(id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as WeaponModeResource
