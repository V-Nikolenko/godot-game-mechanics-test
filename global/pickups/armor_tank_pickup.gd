# global/pickups/armor_tank_pickup.gd
class_name ArmorTankPickup
extends PickupBase

func _collect(player: PlayerBase) -> void:
	if player.shield_component:
		player.shield_component.restore_all_permanent()

func _get_dialog_text() -> String:
	return ""
