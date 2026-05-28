# global/pickups/temporary_health_shield_up_pickup.gd
class_name TemporaryHealthShieldUpPickup
extends PickupBase

func _collect(player: PlayerBase) -> void:
	if player.temp_health_component and player.health_component:
		player.temp_health_component.add_stack(player.health_component.max_health)
	if player.shield_component:
		player.shield_component.add_temporary()

func _get_dialog_text() -> String:
	return "Combat stims active! Hull and shields reinforced!"
