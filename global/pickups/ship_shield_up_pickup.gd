# global/pickups/ship_shield_up_pickup.gd
class_name ShipShieldUpPickup
extends PickupBase

func _collect(_player: PlayerBase) -> void:
	ShipProgressionState.add_permanent_shield()

func _get_dialog_text() -> String:
	return "Permanent shield slot unlocked!"
