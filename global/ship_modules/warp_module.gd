# global/ship_modules/warp_module.gd
class_name WarpModule
extends ShipModuleBase

func get_display_name() -> String: return "Warp Drive"
func get_description() -> String:
	return "Replaces the barrel-roll dash with a micro-warp teleport. Double-tap a movement key to instantly blink 120 px in that direction."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_engine_warp.png")
func get_slot() -> StringName: return &"engines"

func apply(player: Node) -> void:
	player.set("warp_module_active", true)

func remove(player: Node) -> void:
	player.set("warp_module_active", false)
