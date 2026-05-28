# global/pickups/health_tank_pickup.gd
class_name HealthTankPickup
extends PickupBase

const HEAL_AMOUNT: int = 40

func _collect(player: PlayerBase) -> void:
	if player.health_component:
		player.health_component.increase(HEAL_AMOUNT)

func _get_dialog_text() -> String:
	return ""
