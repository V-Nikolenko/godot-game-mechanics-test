# global/ship_modules/armor_plating_module.gd
class_name ArmorPlatingModule
extends ShipModuleBase

const _HEALTH_BONUS: int = 40
const _REDUCTION: float = 0.25

func get_display_name() -> String: return "Increased Armor"
func get_description() -> String:
	return "Reinforced hull plating increases maximum hull integrity by 40 and reduces all incoming damage by 25%%."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_armor_increased_plating.png")
func get_slot() -> StringName: return &"armor"

func apply(player: Node) -> void:
	var health := player.get("health_component")
	if health:
		health.max_health += _HEALTH_BONUS
		## Also restore the bonus HP so the player doesn't gain a phantom bonus bar.
		health.increase(_HEALTH_BONUS)
	player.set("damage_reduction", player.get("damage_reduction") + _REDUCTION)

func remove(player: Node) -> void:
	var health := player.get("health_component")
	if health:
		health.max_health -= _HEALTH_BONUS
		## Clamp current health so it doesn't exceed new max.
		if health.current_health > health.max_health:
			health.set_health(health.max_health)
	player.set("damage_reduction", maxf(0.0, player.get("damage_reduction") - _REDUCTION))
