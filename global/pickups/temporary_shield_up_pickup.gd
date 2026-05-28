# global/pickups/temporary_shield_up_pickup.gd
class_name TemporaryShieldUpPickup
extends PickupBase

func _collect(player: PlayerBase) -> void:
	if player.shield_component:
		player.shield_component.add_temporary()

func _get_dialog_text() -> String:
	return "Temporary shield restored!"
