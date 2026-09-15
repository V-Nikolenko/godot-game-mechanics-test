# global/pickups/ship_boost_up_pickup.gd
class_name ShipBoostUpPickup
extends PickupBase

func _collect(_player: PlayerBase) -> void:
	ShipProgressionState.add_boost_charge()

func _get_dialog_text() -> String:
	return "+1 boost charge"
