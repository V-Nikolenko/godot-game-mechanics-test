# global/ship_modules/pierce_module.gd
class_name PierceModule
extends ShipModuleBase

## Passive only. Sets pierce_module_active on the player; weapon behaviors
## read this flag to assign Bullet.MAX_PIERCE (3) on each spawned projectile.
## Each pierce reduces damage by ~45% (Bullet.PIERCE_DAMAGE_FACTOR = 0.55).

func get_display_name() -> String: return "Penetrating Rounds"
func get_description() -> String:
	return "Passive: all projectiles pierce through up to 3 enemies. Each enemy hit after the first reduces bullet damage by 45%."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_pierce.png")
func get_slot() -> StringName: return &"weapons"

func apply(player: Node) -> void:
	player.set("pierce_module_active", true)

func remove(player: Node) -> void:
	player.set("pierce_module_active", false)
