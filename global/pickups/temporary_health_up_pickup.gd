# global/pickups/temporary_health_up_pickup.gd
class_name TemporaryHealthUpPickup
extends PickupBase

func _collect(player: PlayerBase) -> void:
	if player.temp_health_component and player.health_component:
		player.temp_health_component.add_stack(player.health_component.max_health)

func _get_dialog_text() -> String:
	return "Emergency hull reinforcement active!"
