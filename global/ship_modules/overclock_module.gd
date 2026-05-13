# global/ship_modules/overclock_module.gd
class_name OverclockModule
extends ShipModuleBase

func get_display_name() -> String: return "Weapon Overclock"
func get_description() -> String:
	return "Bypasses thermal safeties. Weapons continue firing past heat limit, but each shot while overheated deals 3 damage to the hull."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_weapon_oveclock.png")
func get_slot() -> StringName: return &"weapons"

func apply(player: Node) -> void:
	player.set("overclock_module_active", true)

func remove(player: Node) -> void:
	player.set("overclock_module_active", false)
